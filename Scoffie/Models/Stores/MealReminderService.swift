import Foundation
import UserNotifications

// Powiadomienia systemowe o WŁASNYM dniu.
//
// `PlanChangeNotificationService` obok odpowiada na „co zrobił ktoś inny
// w gospodarstwie" — i to jest jedyne, co aplikacja dotąd mówiła poza swoim
// ekranem. Tutaj jest druga połowa: co ma zrobić TEN użytkownik i kiedy.
//
// Wszystko jest LOKALNE, planowane na telefonie z wyprzedzeniem. To nie jest
// oszczędność na backendzie, tylko właściwy mechanizm: telefon zna plan
// tygodnia, zna rozkład godzin gospodarstwa i zna zegar — a `UNCalendar-
// NotificationTrigger` odpala się nawet wtedy, gdy aplikacja jest ubita
// i telefon jest offline. Push musiałby dowieźć to samo z serwera, który
// o strefie czasowej telefonu wie tylko tyle, ile mu powiedziano.
//
// Cztery zasady:
//
// 1. **Jedno powiadomienie na posiłek.** Danie, które się gotuje, dostaje
//    uprzedzenie („pora gotować"); danie, którego się nie gotuje — sygnał
//    o porze („pora jeść"). Nigdy oba, bo to ten sam posiłek.
// 2. **Nic o przeszłości i nic o zjedzonym.** Termin, który już minął, i danie
//    już odhaczone wypadają z rozkładu przy każdym przeplanowaniu.
// 3. **Rozkład planuje się od zera, nie przyrostowo.** Każde przeplanowanie
//    najpierw zdejmuje CAŁE okno (tydzień w przód, dzień wstecz), potem
//    wstawia to, co ma stać. Identyfikatory są policzalne z daty i pory, więc
//    nie trzeba nic pamiętać między uruchomieniami — a zmiana planu przez
//    domownika nie zostawia po sobie powiadomienia o daniu, którego już nie ma.
// 4. **Wieczorem najwyżej jedno zdanie.** Dzień bez odhaczeń i jutro bez planu
//    to dwie różne sprawy, ale obie wypadają wieczorem i obie są przypomnieniem
//    — więc dzielą jeden termin i wygrywa pilniejsza.
enum MealReminderService {

    // MARK: - Wejście

    /// Posiłek do przypomnienia — tyle, ile trzeba, żeby ułożyć zdanie
    /// i termin. Serwis nie zna `PlanMeal` ani store'ów celowo: składa je
    /// wołający, który jako jedyny wie, czyje są posiłki i który tydzień
    /// jest wczytany.
    struct Meal {
        let slot: MealSlot
        /// Pora posiłku w minutach od północy, z rozkładu gospodarstwa.
        /// `nil` = slot bez stałej pory (przekąska) — nie ma czego przypominać.
        let minutes: Int?
        /// Nazwa dania — to ona idzie w treść powiadomienia.
        let title: String
        let prepMinutes: Int
        let isEaten: Bool
    }

    /// Jeden dzień planu. Do rozkładu trafiają WYŁĄCZNIE dni, dla których
    /// wołający ma prawdziwe dane — pusty dzień z tej listy znaczy „wiem, że
    /// nic tu nie ma", a nie „nie wiem".
    struct Day {
        let date: Date
        let meals: [Meal]
    }

    // MARK: - Reguły

    /// Od ilu minut przygotowania warto uprzedzać osobnym powiadomieniem.
    ///
    /// Dwadzieścia, a nie dziesięć jak na łuku w Kalendarzu. Podpowiedź na
    /// ekranie nic nie kosztuje — ogląda ją ten, kto i tak patrzy. Systemowy
    /// banner przerywa cokolwiek, co człowiek akurat robi, więc próg musi być
    /// wyżej: jajecznica na dwanaście minut nie jest powodem, żeby zawibrować
    /// w kieszeni.
    static let minPrepForCookReminder = 20

    /// Ile dni w przód planujemy.
    ///
    /// Trzy, a nie siedem, choć sufit iOS (64 oczekujące żądania) zniósłby
    /// i tydzień. Powód jest inny: im dalej, tym większa szansa, że plan się
    /// jeszcze zmieni, a rozkład odświeża się przy każdym wejściu i wyjściu
    /// z aplikacji. Trzy dni wystarczą na weekend bez otwierania apki.
    static let horizonDays = 3

    /// Okno czyszczone przed każdym przeplanowaniem. Szersze niż horyzont,
    /// żeby skrócenie planu albo przestawienie zegara telefonu nie zostawiło
    /// za sobą powiadomienia o daniu, którego już nie ma.
    private static let sweepBackDays = 1
    private static let sweepForwardDays = 7

    /// O której wychodzi wieczorne podsumowanie.
    private static let wrapUpMinutes = 20 * 60 + 30

    // MARK: - Rozkład

    /// Układa cały rozkład powiadomień od nowa.
    ///
    /// Bez `getPendingNotificationRequests` — identyfikatory da się policzyć
    /// z daty i slotu, więc całe okno zdejmuje się jednym wywołaniem,
    /// synchronicznie i bez domknięcia lecącego z innego wątku.
    static func reschedule(days: [Day], now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: sweepIdentifiers(around: now))

        guard isEnabled else { return }

        let calendar = PlanWeek.calendar
        let today = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: today) ?? today

        if isMealRemindersEnabled {
            for day in days {
                let start = calendar.startOfDay(for: day.date)
                guard start >= today, start < horizon else { continue }
                scheduleMeals(of: day, now: now, calendar: calendar)
            }
        }

        if isDayWrapUpEnabled {
            scheduleWrapUp(days: days, now: now, calendar: calendar)
        }
    }

    /// Zdejmuje wszystko, co ten serwis kiedykolwiek zaplanował. Woła się
    /// przy wylogowaniu: cudze śniadanie nie ma prawa zadzwonić na telefonie,
    /// z którego ktoś już wyszedł.
    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            // Domknięcie, nie goła referencja do metody: projekt ma włączone
            // `InferSendableFromCaptures` (SE-0418) i referencje metod
            // w takich miejscach potrafią rozjechać wnioskowanie typu.
            let ours = requests.map(\.identifier).filter { isOurs($0) }
            guard !ours.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
    }

    static func isOurs(_ identifier: String) -> Bool {
        identifier.hasPrefix(NotificationIdentifierPrefix.cook)
            || identifier.hasPrefix(NotificationIdentifierPrefix.mealTime)
            || identifier.hasPrefix(NotificationIdentifierPrefix.dayWrapUp)
    }

    // MARK: - Posiłki

    /// Identyfikator liczy się z daty i SLOTU, nie z dania. Dom, który dzieli
    /// obiad na dwa warianty, dostanie więc jedno powiadomienie o obiedzie,
    /// a nie dwa o tej samej godzinie — i tak jest dobrze: pora jest jedna.
    private static func scheduleMeals(of day: Day, now: Date, calendar: Calendar) {
        let key = PlanWeek.dateKey(day.date)

        for meal in day.meals {
            guard !meal.isEaten, let minutes = meal.minutes else { continue }

            let time = MealSlotSchedule.format(minutes)
            let dish = meal.title
            let slot = slotPhrase(meal.slot)

            if meal.prepMinutes >= minPrepForCookReminder {
                // Uprzedzenie wychodzi o tyle wcześniej, ile zajmuje danie —
                // czyli dokładnie wtedy, kiedy trzeba stanąć przy garnkach,
                // żeby zdążyć na porę.
                schedule(
                    identifier: "\(NotificationIdentifierPrefix.cook)\(key)-\(meal.slot.rawValue)",
                    at: minutes - meal.prepMinutes,
                    on: day.date,
                    now: now,
                    calendar: calendar,
                    title: "Pora gotować",
                    body: "\(dish) — \(slot) o \(time), zajmie \(meal.prepMinutes) min.",
                    dateKey: key,
                    isQuiet: false
                )
            } else {
                schedule(
                    identifier: "\(NotificationIdentifierPrefix.mealTime)\(key)-\(meal.slot.rawValue)",
                    at: minutes,
                    on: day.date,
                    now: now,
                    calendar: calendar,
                    title: "Pora jeść",
                    body: "\(dish) — \(slot) o \(time).",
                    dateKey: key,
                    isQuiet: false
                )
            }
        }
    }

    /// Nazwa pory w środku zdania („… — obiad o 14:00"). Małą literą, ale
    /// „II śniadanie" zostaje z rzymską dwójką: „ii śniadanie" czyta się jak
    /// literówka, a nie jak nazwa posiłku.
    private static func slotPhrase(_ slot: MealSlot) -> String {
        let title = slot.title
        guard slot != .secondBreakfast else { return title }
        return title.prefix(1).lowercased() + String(title.dropFirst())
    }

    // MARK: - Wieczorne podsumowanie

    /// Jeden termin wieczorem i najwyżej jedno zdanie.
    ///
    /// Pierwszeństwo ma dzień, który się właśnie kończy: niedokończone
    /// odhaczanie to trzy stuknięcia i licznik kalorii, który bez nich kłamie.
    /// Dopiero gdy dzień jest domknięty, wieczór może powiedzieć o jutrze.
    private static func scheduleWrapUp(days: [Day], now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        guard let day = days.first(where: { calendar.isDate($0.date, inSameDayAs: today) }) else {
            return
        }

        let pending = day.meals.filter { !$0.isEaten }.count
        let key = PlanWeek.dateKey(day.date)
        let identifier = "\(NotificationIdentifierPrefix.dayWrapUp)\(key)"

        if pending > 0 {
            schedule(
                identifier: identifier,
                at: wrapUpMinutes,
                on: day.date,
                now: now,
                calendar: calendar,
                title: "Domknij dzień",
                body: "Zostały \(PolishPlural.meals(pending)) do odhaczenia.",
                dateKey: key,
                isQuiet: true
            )
            return
        }

        // Jutro liczy się TYLKO wtedy, gdy wołający je zna. Dzień spoza
        // wczytanego tygodnia (niedzielny wieczór patrzący na poniedziałek)
        // nie jest pusty — jest nieznany, a to dwie różne rzeczy.
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let next = days.first(where: { calendar.isDate($0.date, inSameDayAs: tomorrow) }),
              next.meals.isEmpty
        else { return }

        schedule(
            identifier: identifier,
            at: wrapUpMinutes,
            on: day.date,
            now: now,
            calendar: calendar,
            title: "Jutro bez planu",
            body: "Na jutro nie masz nic zaplanowanego. Dzień układa się w Planie tygodnia.",
            dateKey: key,
            isQuiet: true
        )
    }

    // MARK: - Wysyłka

    private static func schedule(
        identifier: String,
        at minutes: Int,
        on date: Date,
        now: Date,
        calendar: Calendar,
        title: String,
        body: String,
        dateKey: String,
        isQuiet: Bool
    ) {
        // Pora policzona wstecz od posiłku potrafi wyjść przed północą
        // (kolacja o 00:20 po sześciu godzinach pieczenia). Taki termin nie
        // należy już do tego dnia i nie ma go jak uczciwie postawić.
        guard minutes >= 0, minutes < 24 * 60 else { return }

        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = minutes / 60
        components.minute = minutes % 60

        // Termin, który już minął, nie ma czego przypominać — a `UNCalendar-
        // NotificationTrigger` bez `repeats` po prostu nigdy by nie wystrzelił
        // i zajmowałby miejsce w limicie 64 żądań.
        guard let fireDate = calendar.date(from: components), fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = isQuiet ? nil : .default
        // Przypomnienie o porze jest wezwaniem — ma się pokazać na ekranie
        // blokady. Podsumowanie wieczorne jest informacją i może poczekać
        // w Centrum powiadomień.
        content.interruptionLevel = isQuiet ? .passive : .active
        // Jeden stos na dzień: cztery przypomnienia z jednego dnia zwijają się
        // w Centrum powiadomień w jedną pozycję, zamiast rozpychać listę.
        content.threadIdentifier = "\(NotificationIdentifierPrefix.dayThread)\(dateKey)"

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Wszystkie identyfikatory, jakie ten serwis mógł postawić w oknie wokół
    /// dzisiaj. Liczone, a nie odczytywane z systemu — dzięki temu czyszczenie
    /// jest synchroniczne i nie wyścigowe wobec wstawiania nowych.
    private static func sweepIdentifiers(around now: Date) -> [String] {
        let calendar = PlanWeek.calendar
        let today = calendar.startOfDay(for: now)
        var identifiers: [String] = []

        for offset in (-sweepBackDays)...sweepForwardDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let key = PlanWeek.dateKey(date)
            identifiers.append("\(NotificationIdentifierPrefix.dayWrapUp)\(key)")
            for slot in MealSlot.allCases {
                identifiers.append("\(NotificationIdentifierPrefix.cook)\(key)-\(slot.rawValue)")
                identifiers.append("\(NotificationIdentifierPrefix.mealTime)\(key)-\(slot.rawValue)")
            }
        }
        return identifiers
    }

    // MARK: - Przełączniki z Ustawień
    //
    // Klucze są LOKALNE i nie jadą na backend — inaczej niż kanały planu
    // i zakupów. Te powiadomienia planuje wyłącznie telefon, więc serwer nie
    // ma czego z nimi zrobić poza przechowaniem wartości, której nie użyje.

    enum Keys {
        static let mealReminders = "settings.notifications.mealReminders"
        static let dayWrapUp = "settings.notifications.dayWrapUp"
    }

    static var isEnabled: Bool {
        PlanChangeNotificationService.isNotificationsEnabled
    }

    static var isMealRemindersEnabled: Bool {
        boolSetting(Keys.mealReminders)
    }

    static var isDayWrapUpEnabled: Bool {
        boolSetting(Keys.dayWrapUp)
    }

    /// Brak wpisu = włączone. Nowy kanał ma działać od pierwszego
    /// uruchomienia, a nie czekać, aż ktoś znajdzie go w Ustawieniach.
    private static func boolSetting(_ key: String) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil { return true }
        return defaults.bool(forKey: key)
    }
}
