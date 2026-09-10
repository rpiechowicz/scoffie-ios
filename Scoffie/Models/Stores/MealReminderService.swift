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
// ─── Trzy sloty doby ────────────────────────────────────────────────────
//
// Powodów, żeby się odezwać, jest więcej niż powiadomień, które człowiek
// zniesie. Dlatego doba ma TRZY stałe miejsca i w każdym mieści się najwyżej
// jedno zdanie; dołożenie kolejnego pomysłu nie zwiększa hałasu, tylko
// zmienia to, co pada w danym slocie.
//
//  • **Poranek** — jedno spojrzenie na dzień: ile posiłków, ile kalorii,
//    czym się zaczyna. Wypada przed pierwszym posiłkiem, nie o stałej
//    godzinie, bo dom jedzący śniadanie o 6:30 nie chce podglądu o 7:30.
//  • **Popołudnie** — wyłącznie przekąska. Slot bez stałej pory wypadał
//    z rozkładu w ogóle (nie ma czego przypiąć do zegara), więc dzień
//    z przekąską w planie nie słyszał o niej ani słowa.
//  • **Wieczór** — jedno z czterech, po kolei ważności: niedokończone
//    odhaczanie, zakupy przed jutrzejszym gotowaniem, jutro bez planu,
//    a na końcu — gdy nie ma o co prosić — seria domkniętych dni.
//
// Do tego przypomnienia przy samych posiłkach, po jednym na posiłek.
//
// ─── Zasady ─────────────────────────────────────────────────────────────
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
// 4. **Wieczór zna tylko dziś.** Poranek i przekąska planują się na cały
//    horyzont, bo ich treść wynika z samego planu. Wieczorne zdanie zależy od
//    stanu, który zna się dopiero teraz (seria, lista zakupów), więc dotyczy
//    wyłącznie dzisiejszego dnia.
enum MealReminderService {

    // MARK: - Wejście

    /// Posiłek do przypomnienia — tyle, ile trzeba, żeby ułożyć zdanie
    /// i termin. Serwis nie zna `PlanMeal` ani store'ów celowo: składa je
    /// wołający, który jako jedyny wie, czyje są posiłki i który tydzień
    /// jest wczytany.
    struct Meal {
        let slot: MealSlot
        /// Pora posiłku w minutach od północy, z rozkładu gospodarstwa.
        /// `nil` = slot bez stałej pory (przekąska) — trafia do slotu
        /// popołudniowego zamiast do przypomnień przy porach.
        let minutes: Int?
        /// Nazwa dania — to ona idzie w treść powiadomienia.
        let title: String
        let prepMinutes: Int
        /// Kalorie na jedną osobę — do porannego podglądu dnia.
        let kcal: Int
        let isFavourite: Bool
        let isEaten: Bool
    }

    /// Jeden dzień planu. Do rozkładu trafiają WYŁĄCZNIE dni, dla których
    /// wołający ma prawdziwe dane — pusty dzień z tej listy znaczy „wiem, że
    /// nic tu nie ma", a nie „nie wiem".
    struct Day {
        let date: Date
        let meals: [Meal]

        var pending: [Meal] { meals.filter { !$0.isEaten } }
        var kcal: Int { meals.reduce(0) { $0 + $1.kcal } }

        /// Posiłki z godziną, od najwcześniejszego.
        var timed: [(meal: Meal, minutes: Int)] {
            meals
                .compactMap { meal in meal.minutes.map { (meal, $0) } }
                .sorted { $0.1 < $1.1 }
        }
    }

    /// To, czego nie widać w samym planie dnia — a co decyduje o wieczornym
    /// zdaniu.
    struct Context {
        /// Ile dni z rzędu (licząc z dzisiejszym) zostało domkniętych.
        /// Zero = brak serii albo dziś jeszcze nie domknięty.
        let closedStreak: Int
        /// Ile produktów zostało na liście zakupów bieżącego tygodnia.
        let pendingShoppingItems: Int

        static let none = Context(closedStreak: 0, pendingShoppingItems: 0)
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

    /// Ile dni wstecz szuka się serii domkniętych dni.
    static let streakLookbackDays = 60

    /// Okno czyszczone przed każdym przeplanowaniem. Szersze niż horyzont,
    /// żeby skrócenie planu albo przestawienie zegara telefonu nie zostawiło
    /// za sobą powiadomienia o daniu, którego już nie ma.
    private static let sweepBackDays = 1
    private static let sweepForwardDays = 7

    /// Najpóźniejsza pora porannego podglądu i najwcześniejsza, na jaką wolno
    /// go zepchnąć, gdy dom je bardzo wcześnie.
    private static let morningLatestMinutes = 7 * 60 + 30
    private static let morningEarliestMinutes = 6 * 60
    /// Ile przed pierwszym posiłkiem staje podgląd dnia.
    private static let morningLeadMinutes = 30
    /// Pora popołudniowej przekąski — ta sama, którą aplikacja podpowiada
    /// przy nadawaniu przekąsce godziny.
    private static let snackMinutes = MealSlotSchedule.snackSuggestedMinutes
    /// O której wychodzi wieczorne podsumowanie.
    private static let eveningMinutes = 20 * 60 + 30

    // MARK: - Rozkład

    /// Układa cały rozkład powiadomień od nowa.
    ///
    /// Bez `getPendingNotificationRequests` — identyfikatory da się policzyć
    /// z daty i slotu, więc całe okno zdejmuje się jednym wywołaniem,
    /// synchronicznie i bez domknięcia lecącego z innego wątku.
    static func reschedule(days: [Day], context: Context = .none, now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: sweepIdentifiers(around: now))

        guard isEnabled else { return }

        let calendar = PlanWeek.calendar
        let today = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: today) ?? today

        for day in days {
            let start = calendar.startOfDay(for: day.date)
            guard start >= today, start < horizon else { continue }

            if isMorningBriefingEnabled {
                scheduleMorning(day, now: now, calendar: calendar)
            }
            if isMealRemindersEnabled {
                scheduleMeals(of: day, now: now, calendar: calendar)
                scheduleSnack(day, now: now, calendar: calendar)
            }
        }

        if isDayWrapUpEnabled {
            scheduleEvening(days: days, context: context, now: now, calendar: calendar)
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
            || identifier.hasPrefix(NotificationIdentifierPrefix.dayMorning)
            || identifier.hasPrefix(NotificationIdentifierPrefix.daySnack)
    }

    // MARK: - Poranek

    /// Jedno spojrzenie na dzień, zanim się zacznie.
    ///
    /// Godzina liczy się od pierwszego posiłku, nie z zegara ściennego:
    /// podgląd, który wypada PO śniadaniu, jest już tylko wyrzutem sumienia.
    /// Dom bez ani jednego posiłku z godziną dostaje go o ósmej — jest wtedy
    /// o czym mówić (przekąska, plan na jutro), tylko nie ma czego się trzymać.
    private static func scheduleMorning(_ day: Day, now: Date, calendar: Calendar) {
        guard !day.meals.isEmpty else { return }
        let key = PlanWeek.dateKey(day.date)

        var minutes = 8 * 60
        if let first = day.timed.first?.minutes {
            minutes = max(morningEarliestMinutes, min(morningLatestMinutes, first - morningLeadMinutes))
            // Dom jedzący o szóstej rano nie zmieści już przed sobą podglądu.
            guard minutes < first else { return }
        }

        schedule(
            identifier: "\(NotificationIdentifierPrefix.dayMorning)\(key)",
            at: minutes,
            on: day.date,
            now: now,
            calendar: calendar,
            copy: morningCopy(day: day, seed: "morning-\(key)"),
            dateKey: key,
            isQuiet: true
        )
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
                schedule(
                    identifier: "\(NotificationIdentifierPrefix.cook)\(key)-\(meal.slot.rawValue)",
                    at: minutes - meal.prepMinutes,
                    on: day.date,
                    now: now,
                    calendar: calendar,
                    copy: cookCopy(
                        dish: meal.title,
                        slot: meal.slot,
                        time: MealSlotSchedule.format(minutes),
                        prep: meal.prepMinutes,
                        seed: "cook-\(key)-\(meal.slot.rawValue)"
                    ),
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
                    copy: mealTimeCopy(
                        dish: meal.title,
                        slot: meal.slot,
                        time: MealSlotSchedule.format(minutes),
                        seed: "eat-\(key)-\(meal.slot.rawValue)"
                    ),
                    dateKey: key,
                    isQuiet: false
                )
            }
        }
    }

    // MARK: - Popołudnie

    /// Przekąska — jedyny slot, który wolno mieć bez godziny.
    ///
    /// Przez to wypadała z rozkładu w całości: nie ma czego przypiąć do
    /// zegara, więc dzień z przekąską w planie nie słyszał o niej ani słowa.
    /// Dostaje więc stałe popołudnie — tę samą porę, którą aplikacja
    /// podpowiada, gdy ktoś chce przekąsce nadać godzinę.
    ///
    /// Cicho i bez dźwięku: przekąska jest propozycją, nie terminem.
    private static func scheduleSnack(_ day: Day, now: Date, calendar: Calendar) {
        let loose = day.meals.filter { $0.minutes == nil && !$0.isEaten }
        guard let meal = loose.first else { return }

        let key = PlanWeek.dateKey(day.date)
        schedule(
            identifier: "\(NotificationIdentifierPrefix.daySnack)\(key)",
            at: snackMinutes,
            on: day.date,
            now: now,
            calendar: calendar,
            copy: snackCopy(dish: meal.title, seed: "snack-\(key)"),
            dateKey: key,
            isQuiet: true
        )
    }

    // MARK: - Wieczór

    /// Jeden termin wieczorem i najwyżej jedno zdanie — wybrane po tym, czy
    /// jest o co prosić.
    ///
    /// Kolejność jest kolejnością pilności, nie ważności: najpierw to, co
    /// domyka DZISIAJ (odhaczanie), potem to, co ratuje JUTRO (zakupy, plan),
    /// a nagroda za serię idzie na koniec — bo należy się dokładnie wtedy,
    /// gdy nie ma o co poprosić.
    private static func scheduleEvening(
        days: [Day],
        context: Context,
        now: Date,
        calendar: Calendar
    ) {
        let today = calendar.startOfDay(for: now)
        guard let day = days.first(where: { calendar.isDate($0.date, inSameDayAs: today) }) else {
            return
        }

        let key = PlanWeek.dateKey(day.date)
        let identifier = "\(NotificationIdentifierPrefix.dayWrapUp)\(key)"
        let pending = day.pending.count

        // Jutro liczy się TYLKO wtedy, gdy wołający je zna. Dzień spoza
        // wczytanego tygodnia (niedzielny wieczór patrzący na poniedziałek)
        // nie jest pusty — jest nieznany, a to dwie różne rzeczy.
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today).flatMap { date in
            days.first(where: { calendar.isDate($0.date, inSameDayAs: date) })
        }

        let copy: Copy
        if pending > 0 {
            copy = wrapUpCopy(pending: pending, total: day.meals.count, seed: "wrap-\(key)")
        } else if let tomorrow, !tomorrow.meals.isEmpty, context.pendingShoppingItems > 0 {
            copy = shoppingCopy(items: context.pendingShoppingItems, seed: "shop-\(key)")
        } else if let tomorrow, tomorrow.meals.isEmpty {
            copy = tomorrowCopy(seed: "tomorrow-\(key)")
        } else if context.closedStreak >= 2 {
            copy = streakCopy(days: context.closedStreak, seed: "streak-\(key)")
        } else {
            // Dzień domknięty, jutro ogarnięte, serii jeszcze nie ma —
            // nie ma o czym mówić i najlepszym powiadomieniem jest jego brak.
            return
        }

        schedule(
            identifier: identifier,
            at: eveningMinutes,
            on: day.date,
            now: now,
            calendar: calendar,
            copy: copy,
            dateKey: key,
            isQuiet: true
        )
    }

    // MARK: - Treści
    //
    // Powiadomienie czyta się przez sekundę i widuje się je codziennie, więc
    // rządzą tu trzy zasady, których nie ma nigdzie indziej w aplikacji.
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
    // **Jak się mówi do kogoś, kogo się zna.** Bez „uprzejmie informujemy",
    // bez wykrzykników co zdanie. Krótko, ciepło i konkretnie — tak, jak
    // powiedziałby to ktoś, kto akurat stoi w tej kuchni.
    //
    // Jedna pułapka warta zapisania: NIGDY nie stawiamy przy nazwie dania
    // czasownika ani przymiotnika. „Pierogi z truskawkami będzie gotowe"
    // i „Owsianka gotowy" to ta sama usterka — nazwy dań mają własny rodzaj
    // i liczbę, a aplikacja ich nie zna. Nazwa dania zostaje osobnym
    // kawałkiem zdania; odmienia się to, co pochodzi ze slotu, bo slotów
    // jest sześć i wszystkie są policzone (`slotPhrase`, `slotAccusative`).
    // Ta sama reguła dotyczy liczb: polska liczba odmienia też czasownik
    // („został 1 posiłek", ale „zostało 5 posiłków") — od tego jest
    // `PolishPlural.form`.

    private struct Copy {
        let title: String
        let body: String
    }

    private static func morningCopy(day: Day, seed: String) -> Copy {
        let count = PolishPlural.meals(day.meals.count)
        let kcal = day.kcal

        if let favourite = day.meals.first(where: { $0.isFavourite && !$0.isEaten }) {
            switch variant(seed, of: 2) {
            case 0:
                return Copy(title: "Dziś coś dobrego", body: "W planie Twoje ulubione: \(favourite.title).")
            default:
                return Copy(
                    title: "Dzień dobry",
                    body: "\(count) na dziś, a wśród nich ulubione: \(favourite.title)."
                )
            }
        }

        guard let first = day.timed.first else {
            return Copy(title: "Co dziś jemy", body: "\(count) w planie, \(kcal) kcal.")
        }
        let time = MealSlotSchedule.format(first.minutes)

        switch variant(seed, of: 3) {
        case 0:
            return Copy(title: "Dzień dobry", body: "Dziś \(count) i \(kcal) kcal. Na start o \(time): \(first.meal.title).")
        case 1:
            return Copy(title: "Co dziś jemy", body: "\(count), \(kcal) kcal. Zaczynamy o \(time) — \(first.meal.title).")
        default:
            return Copy(title: "Plan na dziś", body: "\(count) i \(kcal) kcal. Pierwszy o \(time): \(first.meal.title).")
        }
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
                title: "Do garnków",
                body: "\(dish) na \(name) o \(time). Zajmie \(prep) min, więc to ten moment."
            )
        case 1:
            return Copy(
                title: "Czas zaczynać",
                body: "\(dish) — \(prep) min roboty. Na \(accusative) o \(time)."
            )
        case 2:
            return Copy(
                title: "Fartuch w dłoń",
                body: "\(dish). Zaczniesz teraz, zdążysz na \(time)."
            )
        default:
            return Copy(
                title: "Pora gotować",
                body: "\(slot.title) o \(time), \(prep) min przy garnkach. Dziś: \(dish)."
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
            return Copy(title: "Pora jeść", body: "\(dish) — \(name) o \(time). Smacznego!")
        case 1:
            return Copy(title: "Czas na \(accusative)", body: "Dziś: \(dish).")
        case 2:
            return Copy(title: "\(slot.title) o \(time)", body: "\(dish). Smacznego!")
        default:
            return Copy(title: "Do stołu", body: "\(dish) — \(name) o \(time).")
        }
    }

    private static func snackCopy(dish: String, seed: String) -> Copy {
        switch variant(seed, of: 3) {
        case 0:
            return Copy(title: "Coś małego?", body: "W planie czeka: \(dish).")
        case 1:
            return Copy(title: "Przekąska w planie", body: "\(dish) — kiedy tylko masz ochotę.")
        default:
            return Copy(title: "Przerwa", body: "\(dish). Dobra pora.")
        }
    }

    /// Dzień, w którym nie odhaczono NICZEGO, to inna sytuacja niż dzień
    /// z jednym niedokończonym posiłkiem — pierwsza znaczy zwykle „nie
    /// otwierałem apki", druga „zapomniałem o kolacji". Stąd dwie pule.
    private static func wrapUpCopy(pending: Int, total: Int, seed: String) -> Copy {
        let meals = PolishPlural.meals(pending)

        if pending == total, total > 1 {
            switch variant(seed, of: 2) {
            case 0:
                return Copy(
                    title: "Jak minął dzień?",
                    body: "Nic dziś nie odhaczone. Nadrobisz w pół minuty."
                )
            default:
                return Copy(
                    title: "Domknij dzień",
                    body: "Cały dzień czeka na odhaczenie. To naprawdę chwila."
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
                title: "Jeszcze chwilka",
                body: "\(meals) bez odhaczenia — dwa stuknięcia i po sprawie."
            )
        default:
            return Copy(title: "Koniec dnia", body: "\(meals) \(waits) na odhaczenie.")
        }
    }

    private static func shoppingCopy(items: Int, seed: String) -> Copy {
        let products = PolishPlural.products(items)

        switch variant(seed, of: 3) {
        case 0:
            return Copy(title: "Jutro gotujesz", body: "Na liście zostało: \(products).")
        case 1:
            return Copy(title: "Lista czeka", body: "Jutro w planie gotowanie, a na liście: \(products).")
        default:
            return Copy(title: "Zajrzyj na listę", body: "\(products) przed jutrzejszym gotowaniem.")
        }
    }

    private static func tomorrowCopy(seed: String) -> Copy {
        switch variant(seed, of: 3) {
        case 0:
            return Copy(title: "Jutro pusto", body: "Nic w planie na jutro. Ułożysz to szybciej, niż myślisz.")
        case 1:
            return Copy(title: "Co jutro jemy?", body: "Jutro jest jeszcze puste. Zajrzyj do Planu.")
        default:
            return Copy(title: "Jutro bez planu", body: "Wieczór to dobry moment, żeby ogarnąć jutro.")
        }
    }

    /// Nagroda, nie prośba — jedyne powiadomienie w tym pliku, które nie chce
    /// od nikogo niczego.
    private static func streakCopy(days: Int, seed: String) -> Copy {
        switch variant(seed, of: 3) {
        case 0:
            return Copy(title: "\(days). dzień z rzędu", body: "Wszystko odhaczone. Dobra robota!")
        case 1:
            return Copy(title: "Komplet", body: "\(days). domknięty dzień pod rząd. Tak trzymaj.")
        default:
            return Copy(title: "Dzień domknięty", body: "I to już \(days). raz z rzędu. Brawo!")
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

    /// Pora w bierniku — „na kolację", nie „na kolacja".
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
        // blokady. Poranek, przekąska i wieczór są informacją i mogą poczekać
        // w Centrum powiadomień.
        content.interruptionLevel = isQuiet ? .passive : .active
        // Jeden stos na dzień: kilka przypomnień z jednego dnia zwija się
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
            identifiers.append("\(NotificationIdentifierPrefix.dayMorning)\(key)")
            identifiers.append("\(NotificationIdentifierPrefix.daySnack)\(key)")
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
        static let morningBriefing = "settings.notifications.morningBriefing"
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

    static var isMorningBriefingEnabled: Bool {
        boolSetting(Keys.morningBriefing)
    }

    /// Brak wpisu = włączone. Nowy kanał ma działać od pierwszego
    /// uruchomienia, a nie czekać, aż ktoś znajdzie go w Ustawieniach.
    private static func boolSetting(_ key: String) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil { return true }
        return defaults.bool(forKey: key)
    }
}
