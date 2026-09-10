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

            if meal.prepMinutes >= minPrepForCookReminder {
                // Uprzedzenie wychodzi o tyle wcześniej, ile zajmuje danie —
                // czyli dokładnie wtedy, kiedy trzeba stanąć przy garnkach,
                // żeby zdążyć na porę.
                let copy = cookCopy(
                    dish: meal.title,
                    slot: meal.slot,
                    time: MealSlotSchedule.format(minutes),
                    prep: meal.prepMinutes,
                    seed: "cook-\(key)-\(meal.slot.rawValue)"
                )
                schedule(
                    identifier: "\(NotificationIdentifierPrefix.cook)\(key)-\(meal.slot.rawValue)",
                    at: minutes - meal.prepMinutes,
                    on: day.date,
                    now: now,
                    calendar: calendar,
                    copy: copy,
                    dateKey: key,
                    isQuiet: false
                )
            } else {
                let copy = mealTimeCopy(
                    dish: meal.title,
                    slot: meal.slot,
                    time: MealSlotSchedule.format(minutes),
                    seed: "eat-\(key)-\(meal.slot.rawValue)"
                )
                schedule(
                    identifier: "\(NotificationIdentifierPrefix.mealTime)\(key)-\(meal.slot.rawValue)",
                    at: minutes,
                    on: day.date,
                    now: now,
                    calendar: calendar,
                    copy: copy,
                    dateKey: key,
                    isQuiet: false
                )
            }
        }
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
                copy: wrapUpCopy(
                    pending: pending,
                    total: day.meals.count,
                    seed: "wrap-\(key)"
                ),
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
            copy: tomorrowCopy(seed: "tomorrow-\(key)"),
            dateKey: key,
            isQuiet: true
        )
    }

    // MARK: - Treści
    //
    // Powiadomienie czyta się przez sekundę i widuje się je codziennie, więc
    // rządzą tu dwie zasady, których nie ma nigdzie indziej w aplikacji.
    //
    // **Mniej niż wiadomo.** Ekran może pokazać porę, kalorie, czas pracy
    // i godzinę startu naraz; banner ma na to jedną linijkę. Zostaje danie
    // i powód, dla którego telefon się odezwał — reszta czeka w Kalendarzu,
    // jedno stuknięcie dalej.
    //
    // **Nie to samo co wczoraj.** Ta sama formułka trzy razy dziennie przez
    // tydzień przestaje być przypomnieniem, a zaczyna być tapetą. Stąd kilka
    // wariantów na każdy powód i stabilne losowanie między nimi.
    //
    // Jedna pułapka warta zapisania: NIGDY nie stawiamy przy nazwie dania
    // czasownika ani przymiotnika. „Pierogi z truskawkami będzie gotowe"
    // i „Owsianka gotowy" to ta sama usterka — nazwy dań mają własny rodzaj
    // i liczbę, a aplikacja ich nie zna. Nazwa dania zostaje osobnym
    // kawałkiem zdania; odmienia się to, co pochodzi ze slotu, bo slotów
    // jest sześć i wszystkie są policzone (`slotPhrase`, `slotAccusative`).

    private struct Copy {
        let title: String
        let body: String
    }

    private static func cookCopy(
        dish: String,
        slot: MealSlot,
        time: String,
        prep: Int,
        seed: String
    ) -> Copy {
        let name = slotPhrase(slot)
        let accusative = slotAccusative(slot)

        switch variant(seed, of: 4) {
        case 0:
            return Copy(
                title: "Pora do garnków",
                body: "\(dish) na \(name) o \(time). Gotowanie zajmie \(prep) min."
            )
        case 1:
            return Copy(
                title: "Czas zacząć",
                body: "\(dish) — \(prep) min pracy, żeby zdążyć na \(time)."
            )
        case 2:
            return Copy(
                title: "Kuchnia czeka",
                body: "\(dish). Zaczynając teraz, zdążysz na \(accusative) o \(time)."
            )
        default:
            return Copy(
                title: "Pora gotować",
                body: "\(slot.title) o \(time), \(prep) min przy garnkach. W menu: \(dish)."
            )
        }
    }

    private static func mealTimeCopy(
        dish: String,
        slot: MealSlot,
        time: String,
        seed: String
    ) -> Copy {
        let name = slotPhrase(slot)
        let accusative = slotAccusative(slot)

        switch variant(seed, of: 4) {
        case 0:
            return Copy(title: "Pora jeść", body: "\(dish) — \(name) o \(time). Smacznego.")
        case 1:
            return Copy(title: "Czas na \(accusative)", body: "W menu: \(dish).")
        case 2:
            return Copy(title: "\(slot.title) o \(time)", body: "\(dish). Smacznego.")
        default:
            return Copy(title: "Pora do stołu", body: "\(dish) — \(name) o \(time).")
        }
    }

    /// Dzień, w którym nie odhaczono NICZEGO, to inna sytuacja niż dzień
    /// z jednym niedokończonym posiłkiem — pierwsza znaczy zwykle „nie
    /// otwierałem apki", druga „zapomniałem o kolacji". Stąd dwie pule.
    ///
    /// Czasownik przy liczbie idzie przez `PolishPlural.form`, bo polska
    /// liczba odmienia nie tylko rzeczownik: „został 1 posiłek", „zostały
    /// 3 posiłki", ale już „zostało 5 posiłków". Wpisany na sztywno wygląda
    /// poprawnie dokładnie do czwartego posiłku w dniu.
    private static func wrapUpCopy(pending: Int, total: Int, seed: String) -> Copy {
        let meals = PolishPlural.meals(pending)

        if pending == total, total > 1 {
            switch variant(seed, of: 2) {
            case 0:
                return Copy(
                    title: "Jak minął dzień?",
                    body: "Ani jeden posiłek nie odhaczony. Odhacz, co zjedzone."
                )
            default:
                return Copy(
                    title: "Domknij dzień",
                    body: "Cały dzień czeka na odhaczenie. To chwila."
                )
            }
        }

        let left = PolishPlural.form(pending, one: "Został", few: "Zostały", many: "Zostało")
        let waits = PolishPlural.form(pending, one: "czeka", few: "czekają", many: "czeka")

        switch variant(seed, of: 3) {
        case 0:
            return Copy(title: "Domknij dzień", body: "\(left) \(meals) do odhaczenia.")
        case 1:
            return Copy(
                title: "Zostało niewiele",
                body: "\(meals) bez odhaczenia — kilka stuknięć i gotowe."
            )
        default:
            return Copy(title: "Koniec dnia", body: "\(meals) \(waits) na odhaczenie.")
        }
    }

    private static func tomorrowCopy(seed: String) -> Copy {
        switch variant(seed, of: 3) {
        case 0:
            return Copy(title: "Jutro bez planu", body: "Wieczór to dobry moment, żeby ułożyć jutrzejszy dzień.")
        case 1:
            return Copy(title: "Co jutro jemy?", body: "Jutrzejszy dzień jest jeszcze pusty. Ułożysz go w Planie.")
        default:
            return Copy(title: "Jutro pusto", body: "Kilka minut teraz i jutro nie trzeba będzie myśleć, co jeść.")
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

    /// Pora w bierniku — „zdążysz na kolację", nie „na kolacja".
    private static func slotAccusative(_ slot: MealSlot) -> String {
        switch slot {
        case .breakfast:       return "śniadanie"
        case .secondBreakfast: return "II śniadanie"
        case .lunch:           return "obiad"
        case .afternoonSnack:  return "podwieczorek"
        case .dinner:          return "kolację"
        case .snack:           return "przekąskę"
        }
    }

    /// Stabilny wybór wariantu treści.
    ///
    /// Losowanie odpada z prostego powodu: rozkład przelicza się przy każdym
    /// wejściu i wyjściu z aplikacji, więc losowy wariant zmieniałby się
    /// kilka razy dziennie pod tym samym powiadomieniem. Ziarno liczy się
    /// z dnia i pory — TA SAMA kolacja zawsze mówi to samo, a dwa posiłki
    /// tego samego dnia prawie zawsze mówią inaczej.
    ///
    /// Własny FNV-1a, a nie `hashValue`: standardowy hash Swifta jest solony
    /// na start procesu, więc po restarcie aplikacji wypadałby inny wariant.
    private static func variant(_ seed: String, of count: Int) -> Int {
        guard count > 1 else { return 0 }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(hash % UInt64(count))
    }

    // MARK: - Wysyłka

    private static func schedule(
        identifier: String,
        at minutes: Int,
        on date: Date,
        now: Date,
        calendar: Calendar,
        copy: Copy,
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
        content.title = copy.title
        content.body = copy.body
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
