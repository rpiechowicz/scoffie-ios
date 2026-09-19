import Foundation

// Briefing pustej rozmowy z asystentem — LOGIKA, bez SwiftUI.
//
// Pusty ekran asystenta nie jest jednym zdaniem dla wszystkich. Telefon zna
// godzinę, dzień tygodnia, plan tego i przyszłego tygodnia, godziny posiłków,
// bilans makro i stan puli — z tego składa się JEDEN briefing: co jest
// najważniejsze w tej chwili i co da się z tym zrobić jednym stuknięciem.
//
// Podział na trzy warstwy jest celowy:
//   - `AssistantBriefingContext` — fakty (co aplikacja wie),
//   - `AssistantBriefingResolver` — priorytety (co z tych faktów wynika),
//   - `AssistantBriefing` — model widoku (co narysować, bez wiedzy, jak).
// Widok (`AssistantBriefingCard`) dostaje gotowy model i nie liczy nic sam.
//
// Plik importuje TYLKO Foundation, żeby dało się go skompilować razem
// z `Scripts/AssistantLogic/main.swift` bez Xcode — to jedyny sposób na
// test priorytetów w projekcie bez targetu testów.

// MARK: - Fakty

/// Pora dnia w słowniku briefingu — kopia `MealSlot` bez zależności od
/// SwiftUI (tam `cozyAccent` jest `Color`). Mapowanie 1:1 po `rawValue`.
enum AssistantBriefingSlot: String, CaseIterable, Comparable, Hashable {
    case breakfast
    case secondBreakfast
    case lunch
    case afternoonSnack
    case dinner
    case snack

    /// Posiłki, których brak jest WAŻNY — pusty podwieczorek nie robi briefingu.
    static let core: [AssistantBriefingSlot] = [.breakfast, .lunch, .dinner]

    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    static func < (lhs: AssistantBriefingSlot, rhs: AssistantBriefingSlot) -> Bool {
        lhs.order < rhs.order
    }

    var title: String {
        switch self {
        case .breakfast: return "Śniadanie"
        case .secondBreakfast: return "II śniadanie"
        case .lunch: return "Obiad"
        case .afternoonSnack: return "Podwieczorek"
        case .dinner: return "Kolacja"
        case .snack: return "Przekąska"
        }
    }

    /// Biernik po czasowniku: „Dobierz kolację”.
    var accusative: String {
        switch self {
        case .breakfast: return "śniadanie"
        case .secondBreakfast: return "II śniadanie"
        case .lunch: return "obiad"
        case .afternoonSnack: return "podwieczorek"
        case .dinner: return "kolację"
        case .snack: return "przekąskę"
        }
    }

    /// „Kolacja jest jeszcze pusta” — rodzaj gramatyczny nazwy pory.
    var emptyPredicate: String {
        switch self {
        case .breakfast, .secondBreakfast: return "jest jeszcze puste"
        case .lunch, .afternoonSnack: return "jest jeszcze pusty"
        case .dinner, .snack: return "jest jeszcze pusta"
        }
    }

    /// Domyślna godzina, gdy dom nie ustawił własnej — do pytania „czy ta
    /// pora już minęła”.
    var defaultMinutes: Int {
        switch self {
        case .breakfast: return 8 * 60
        case .secondBreakfast: return 10 * 60 + 30
        case .lunch: return 14 * 60
        case .afternoonSnack: return 17 * 60
        case .dinner: return 19 * 60 + 30
        case .snack: return 21 * 60
        }
    }
}

/// Jeden dzień planu widziany z briefingu.
struct AssistantBriefingDay: Equatable {
    struct Meal: Equatable {
        let slot: AssistantBriefingSlot
        let title: String
        /// Kalorie na osobę; 0 = nieznane.
        let kcal: Int
        let imageURL: URL?
    }

    let date: Date
    /// Pory, które dom planuje (włączone w ustawieniach + te, w których coś stoi).
    let enabledSlots: [AssistantBriefingSlot]
    /// Co stoi — najwyżej jedno danie na porę, w porządku dnia.
    let meals: [Meal]

    var isPlanned: Bool { !meals.isEmpty }
    var plannedSlots: Set<AssistantBriefingSlot> { Set(meals.map(\.slot)) }
    var missingSlots: [AssistantBriefingSlot] {
        enabledSlots.filter { !plannedSlots.contains($0) }.sorted()
    }
    /// Każda planowana pora ma danie.
    var isComplete: Bool { isPlanned && missingSlots.isEmpty }
}

/// Bilans makro policzony z PRAWDZIWYCH liczb — briefing nigdy ich nie zmyśla.
struct AssistantBriefingBalance: Equatable {
    /// Dopełniacz: „brakuje Ci białka”.
    let macroGenitive: String
    /// Biernik: „domknąć białko”.
    let macroAccusative: String
    let unit: String
    let averagePerDay: Int
    let target: Int
    /// Z ilu zaplanowanych dni liczona jest średnia.
    let daysCounted: Int
    /// W ilu z nich dzień był poniżej celu; `nil` = nie policzono.
    var daysBelowTarget: Int? = nil

    var deficit: Int { target - averagePerDay }
}

/// Wszystko, co ekran wie w chwili rysowania pustej rozmowy.
struct AssistantBriefingContext {
    var now: Date
    var calendar: Calendar = .current
    /// Imię z profilu; `nil` albo login = powitanie bez imienia.
    var displayName: String?
    /// Pula na próbę wykorzystana — nic nie da się wysłać.
    var trialExhausted = false
    /// Konto bez żadnego planu i bez żadnej rozmowy — Scoffie nic jeszcze
    /// o tym domu nie wie i nie ma prawa udawać, że wie.
    var isNewUser = false
    /// Siedem dni od poniedziałku bieżącego tygodnia.
    var thisWeek: [AssistantBriefingDay]
    /// Siedem dni od następnego poniedziałku.
    var nextWeek: [AssistantBriefingDay]
    /// Godziny posiłków domu (minuty od północy); brak = domyślne pory.
    var slotMinutes: [AssistantBriefingSlot: Int] = [:]
    /// Bilans tygodnia, gdy da się go policzyć; `nil` = nie ma danych.
    var balance: AssistantBriefingBalance?
}

// MARK: - Model widoku

struct AssistantBriefing: Equatable {
    enum Kind: String, Equatable {
        case trialExhausted
        case newUser
        case weekEmpty
        case todayEmpty
        case tomorrowEmpty
        case missingMeal
        case nextWeekEmpty
        case balanceIssue
        case dayReady
        case weekReady
        case weekendInspiration
    }

    /// Stan kółka dnia albo posiłku (`EDot` z makiety): pusty = kreskowany
    /// ring, częściowy = ring z ułamkiem, gotowy = pełny dysk z ptaszkiem.
    enum DotState: Equatable {
        case empty
        case partial(Double)
        case full
    }

    struct DayMark: Equatable, Identifiable {
        let id: String
        /// „Pn”.
        let short: String
        /// „22” — numer dnia pod kółkiem.
        let dayNumber: String
        let state: DotState
        let isToday: Bool

        var planned: Bool { state != .empty }
    }

    struct SlotMark: Equatable, Identifiable {
        let id: String
        let title: String
        let filled: Bool
    }

    struct MealPreview: Equatable, Identifiable {
        let id: String
        let slotTitle: String
        let title: String
        let kcal: Int
        let imageURL: URL?
    }

    /// Sześć typów wizualizacji kontekstu — stała wysokość strefy.
    enum Visual: Equatable {
        /// Tydzień: siedem kółek z numerami dni.
        case week([DayMark])
        /// Dzień: mini oś posiłków pod etykietą („Dziś”, „Jutro”).
        case day(label: String, slots: [SlotMark])
        /// Lekki podgląd istniejących posiłków dnia.
        case meals([MealPreview])
        /// Średnia vs cel na jednym pasku.
        case balance(current: Int, target: Int, unit: String)
        /// Trzy miniatury przepisów — bez nazw i bez wyboru.
        case teaser([URL?])
        /// Znak marki — gdy nie ma danych, których warto pokazać.
        case brand(muted: Bool)
    }

    struct Action: Equatable, Identifiable {
        enum Kind: Equatable {
            /// Wysyła gotowe zdanie do asystenta.
            case ask(String)
            case openPlans
            case openHistory
        }

        let title: String
        let kind: Kind
        /// Symbol w kafelku po lewej wiersza akcji wtórnej.
        var icon: String? = nil

        var id: String { title }

        static func ask(_ title: String, _ prompt: String, icon: String? = nil) -> Action {
            Action(title: title, kind: .ask(prompt), icon: icon)
        }
    }

    /// Podsumowanie pod wizualizacją z LICZBĄ osobno — liczba przewija się
    /// (`CountingNumber`), tekst stoi: „0 z 7 dni zaplanowanych”,
    /// „2 z 3 posiłków”, „Poniżej celu w 5 z 7 dni”.
    struct Summary: Equatable {
        var prefix: String? = nil
        let value: Int
        let text: String

        var sentence: String {
            [prefix, String(value), text].compactMap { $0 }.joined(separator: " ")
        }
    }

    let kind: Kind
    /// Eyebrow nazywa sytuację: „Widzę w Twoim planie”, „Na dziś”, „Bilans tygodnia”.
    let eyebrow: String
    /// Data albo zakres po prawej: „Śr 16 wrz”, „21–27 wrz”; `nil` = brak.
    let dateLabel: String?
    /// Jedno zdanie, stwierdza fakt.
    let headline: String
    /// Jedno zdanie: co mogę zrobić.
    let supporting: String
    let visual: Visual
    /// Pod wizualizacją (tydzień, dzień, bilans).
    let summary: Summary?
    let primary: Action
    /// Najwyżej dwie.
    let secondary: [Action]
    /// Co się stanie po dotknięciu: „Najpierw pokażę propozycję do zatwierdzenia.”
    let helper: String?

    /// Wyciszona wersja karty (wykorzystany limit): znak i eyebrow w szarości.
    var isQuiet: Bool { kind == .trialExhausted }
}

// MARK: - Resolver

enum AssistantBriefingResolver {
    /// Kolejność sprawdzeń JEST specyfikacją: pierwsza prawdziwa sytuacja
    /// wygrywa, pokazuje się jedna karta.
    static func resolve(_ c: AssistantBriefingContext) -> AssistantBriefing {
        let cal = c.calendar
        let hour = cal.component(.hour, from: c.now)
        let minuteOfDay = hour * 60 + cal.component(.minute, from: c.now)
        // 1 = niedziela w kalendarzu gregoriańskim.
        let weekday = cal.component(.weekday, from: c.now)
        let isWeekendish = weekday == 5 || weekday == 6 || weekday == 7 || weekday == 1
        let isWeekend = weekday == 6 || weekday == 7 || weekday == 1
        let allDays = c.thisWeek + c.nextWeek
        let today = allDays.first { cal.isDate($0.date, inSameDayAs: c.now) }
        let tomorrowDate = cal.date(byAdding: .day, value: 1, to: c.now) ?? c.now
        let tomorrow = allDays.first { cal.isDate($0.date, inSameDayAs: tomorrowDate) }
        let todayDate = shortDayLabel(c.now, cal)
        let proposal = "Najpierw pokażę propozycję do zatwierdzenia."
        let viewOnly = "Bez zmian w planie — tylko podgląd."

        // 1. Wyczerpana pula — nic nie da się wysłać, więc żadna podpowiedź
        //    nie ma prawa się pojawić. Karta wyciszona, bez composera.
        if c.trialExhausted {
            return AssistantBriefing(
                kind: .trialExhausted,
                eyebrow: "Asystent",
                dateLabel: nil,
                headline: "Darmowe wiadomości są wykorzystane.",
                supporting: "Rozmowy i zapisany plan zostają.",
                visual: .brand(muted: true),
                summary: nil,
                primary: AssistantBriefing.Action(title: "Zobacz plany", kind: .openPlans),
                secondary: [AssistantBriefing.Action(title: "Historia rozmów", kind: .openHistory, icon: "clock")],
                helper: nil
            )
        }

        // 2. Nowe konto — Scoffie nie zna jeszcze tego domu i nie udaje, że zna.
        if c.isNewUser {
            return AssistantBriefing(
                kind: .newUser,
                eyebrow: "Zacznijmy",
                dateLabel: nil,
                headline: "Co chcesz zaplanować jako pierwsze?",
                supporting: "Możesz zacząć od jednego posiłku albo całego tygodnia.",
                visual: .brand(muted: false),
                summary: nil,
                primary: .ask("Ułóż pierwszy dzień", "Ułóż mi dzisiejszy dzień pod mój cel"),
                secondary: [
                    .ask("Znajdź pomysł na obiad", "Co zjeść dziś na obiad?", icon: "fork.knife"),
                    .ask("Zaplanuj cały tydzień", "Zaplanuj mi cały ten tydzień", icon: "calendar"),
                ],
                helper: proposal
            )
        }

        // 3. Bieżący tydzień w całości pusty.
        if !c.thisWeek.isEmpty, c.thisWeek.allSatisfy({ !$0.isPlanned }) {
            return AssistantBriefing(
                kind: .weekEmpty,
                eyebrow: "Widzę w Twoim planie",
                dateLabel: rangeLabel(c.thisWeek, cal),
                headline: "Ten tydzień jest jeszcze pusty.",
                supporting: "Mogę ułożyć go pod Wasze cele i przepisy.",
                visual: .week(marks(c.thisWeek, now: c.now, cal)),
                summary: plannedDaysSummary(c.thisWeek),
                primary: .ask("Zaplanuj ten tydzień", "Zaplanuj mi cały ten tydzień pod nasze cele i przepisy"),
                secondary: [
                    .ask("Ułóż tylko dzisiejszy dzień", "Ułóż mi tylko dzisiejszy dzień", icon: "calendar"),
                    .ask("Pokaż szybkie kolacje", "Daj mi trzy szybkie kolacje do wyboru", icon: "clock"),
                ],
                helper: proposal
            )
        }

        // 4. Dziś pusto (i jest jeszcze pora, żeby coś z tym zrobić).
        if let today, !today.isPlanned, hour < 20 {
            return AssistantBriefing(
                kind: .todayEmpty,
                eyebrow: "Na dziś",
                dateLabel: todayDate,
                headline: "Dziś jeszcze nic nie zaplanowano.",
                supporting: "Mogę ułożyć cały dzień albo znaleźć tylko jeden posiłek.",
                visual: .day(label: "Dziś", slots: slotMarks(today)),
                summary: mealsSummary(today),
                primary: .ask("Ułóż dzisiejszy dzień", "Ułóż mi dzisiejszy dzień pod mój cel"),
                secondary: [
                    .ask("Co dziś na obiad?", "Co zjeść dziś na obiad?", icon: "fork.knife"),
                    .ask("3 szybkie kolacje", "Daj mi trzy szybkie kolacje do wyboru", icon: "clock"),
                ],
                helper: proposal
            )
        }

        // 5. Wieczór, a jutro pusto.
        if hour >= 17, let tomorrow, !tomorrow.isPlanned {
            return AssistantBriefing(
                kind: .tomorrowEmpty,
                eyebrow: "Na jutro",
                dateLabel: shortDayLabel(tomorrowDate, cal),
                headline: "Jutro w planie jest jeszcze pusto.",
                supporting: "Ułóżmy je teraz, żeby rano było wiadomo, co przygotować.",
                visual: .day(label: "Jutro", slots: slotMarks(tomorrow)),
                summary: mealsSummary(tomorrow),
                primary: .ask("Ułóż jutro", "Ułóż mi jutrzejszy dzień"),
                secondary: [
                    .ask("Co na śniadanie?", "Co na jutrzejsze śniadanie?", icon: "fork.knife"),
                    .ask("Zakupy na jutro", "Co muszę dokupić na jutro?", icon: "cart"),
                ],
                helper: proposal
            )
        }

        // 6. Dziś jest plan, ale brakuje ważnej pory, która jeszcze nie minęła.
        if let today, today.isPlanned,
           let missing = upcomingMissingCoreSlot(today, minuteOfDay: minuteOfDay, times: c.slotMinutes) {
            return AssistantBriefing(
                kind: .missingMeal,
                eyebrow: "Brakuje jednego posiłku",
                dateLabel: todayDate,
                headline: "\(missing.title) \(missing.emptyPredicate).",
                supporting: "Reszta dnia jest już ustawiona.",
                visual: .day(label: "Dziś", slots: slotMarks(today)),
                summary: mealsSummary(today),
                primary: .ask("Dobierz \(missing.accusative)", "Dobierz mi \(missing.accusative) na dziś"),
                secondary: [
                    .ask("Coś do 30 minut", "Coś na \(missing.accusative) do 30 minut", icon: "clock"),
                    .ask("Pokaż 3 propozycje", "Daj mi trzy propozycje na \(missing.accusative)", icon: "fork.knife"),
                ],
                helper: proposal
            )
        }

        // 7. Koniec tygodnia, a przyszły tydzień pusty.
        if isWeekendish, !c.nextWeek.isEmpty, c.nextWeek.allSatisfy({ !$0.isPlanned }) {
            return AssistantBriefing(
                kind: .nextWeekEmpty,
                eyebrow: "Widzę w Twoim planie",
                dateLabel: rangeLabel(c.nextWeek, cal),
                headline: "Przyszły tydzień jest jeszcze pusty.",
                supporting: "Uwzględnię Wasze cele, przepisy i plan dnia.",
                visual: .week(marks(c.nextWeek, now: c.now, cal)),
                summary: plannedDaysSummary(c.nextWeek),
                primary: .ask("Zaplanuj przyszły tydzień", "Zaplanuj mi przyszły tydzień"),
                secondary: [
                    .ask("Zakupy na przyszły tydzień", "Co muszę kupić na przyszły tydzień?", icon: "cart"),
                    .ask("3 pomysły na weekendowy obiad", "Daj mi trzy pomysły na weekendowy obiad", icon: "fork.knife"),
                ],
                helper: proposal
            )
        }

        // 8. Realny brak w bilansie — tylko z policzonych liczb.
        if let balance = c.balance, isSignificant(balance) {
            return AssistantBriefing(
                kind: .balanceIssue,
                eyebrow: "Bilans tygodnia",
                dateLabel: rangeLabel(c.thisWeek, cal),
                headline: "W tym tygodniu brakuje Ci \(balance.macroGenitive).",
                supporting: "Średnio \(balance.deficit) \(balance.unit) dziennie poniżej celu.",
                visual: .balance(current: balance.averagePerDay, target: balance.target, unit: balance.unit),
                summary: balance.daysBelowTarget.map {
                    AssistantBriefing.Summary(prefix: "Poniżej celu w", value: $0, text: "z \(balance.daysCounted) dni")
                },
                primary: .ask("Pokaż, co poprawić", "Czego brakuje w planie, żeby domknąć \(balance.macroAccusative)?"),
                secondary: [
                    .ask("Podmień 1 posiłek", "Podmień jeden posiłek w tym tygodniu na taki z większą ilością \(balance.macroGenitive)", icon: "arrow.triangle.2.circlepath"),
                    .ask("Dodaj coś wysokobiałkowego", "Dołóż do planu coś z dużą ilością \(balance.macroGenitive)", icon: "plus"),
                ],
                helper: "Pokażę propozycje zmian do zatwierdzenia."
            )
        }

        // 9. Tydzień gotowy: od dziś do niedzieli każdy dzień ma plan.
        if let today, today.isComplete, restOfWeekPlanned(c.thisWeek, from: c.now, cal) {
            return AssistantBriefing(
                kind: .weekReady,
                eyebrow: "Ten tydzień",
                dateLabel: rangeLabel(c.thisWeek, cal),
                headline: "Plan wygląda na gotowy.",
                supporting: "Mogę pomóc z zakupami albo zrobić drobną zmianę.",
                visual: .week(marks(c.thisWeek, now: c.now, cal)),
                summary: plannedDaysSummary(c.thisWeek),
                primary: .ask("Pokaż listę zakupów", "Co muszę kupić na ten tydzień?"),
                secondary: [
                    .ask("Podmień jedno danie", "Podmień jedno danie w tym tygodniu na coś innego", icon: "arrow.triangle.2.circlepath"),
                    .ask("Sprawdź mój bilans", "Jak wychodzi mój bilans w tym tygodniu?", icon: "target"),
                ],
                helper: "Lista z tego, co już jest w planie."
            )
        }

        // 10. Weekend bez pilnych spraw — pomysł zamiast obowiązku.
        if isWeekend, let today, today.isPlanned {
            return AssistantBriefing(
                kind: .weekendInspiration,
                eyebrow: "Na weekend",
                dateLabel: weekendLabel(c.now, cal),
                headline: "Masz ochotę ugotować coś większego?",
                supporting: "Mogę wybrać coś dla całego domu z Waszych przepisów.",
                visual: .teaser(teaserImages(c)),
                summary: nil,
                primary: .ask("Pokaż 3 pomysły", "Daj mi trzy pomysły na weekendowy obiad"),
                secondary: [
                    .ask("Coś do godziny", "Coś na weekendowy obiad do godziny gotowania", icon: "clock"),
                    .ask("Coś dla całego domu", "Wybierz danie na weekend dla całego domu", icon: "person.2"),
                ],
                helper: "Z Waszych przepisów, do wyboru."
            )
        }

        // 11. Dzień gotowy — stan spokojny, podpowiedzi o poprawkach.
        let readyDay = today ?? tomorrow
        return AssistantBriefing(
            kind: .dayReady,
            eyebrow: "Dzisiaj",
            dateLabel: todayDate,
            headline: "Plan na dziś jest gotowy.",
            supporting: "Mogę go poprawić, sprawdzić bilans albo przygotować zakupy.",
            visual: readyDay.map { AssistantBriefing.Visual.meals(mealPreviews($0)) } ?? AssistantBriefing.Visual.brand(muted: false),
            summary: nil,
            primary: .ask("Sprawdź mój bilans", "Jak wychodzi mój bilans w tym tygodniu?"),
            secondary: [
                .ask("Podmień dzisiejszą kolację", "Podmień dzisiejszą kolację na coś szybszego", icon: "arrow.triangle.2.circlepath"),
                .ask("Co muszę kupić na ten tydzień?", "Co muszę kupić na ten tydzień?", icon: "cart"),
            ],
            helper: viewOnly
        )
    }

    // MARK: - Reguły pomocnicze

    /// Brak liczy się, gdy jest wyraźny: co najmniej 15 % celu i nie mniej
    /// niż 10 jednostek, policzony z co najmniej trzech dni. Mniejszy brak to
    /// szum dobowy, a jeden dzień to nie tydzień.
    static func isSignificant(_ balance: AssistantBriefingBalance) -> Bool {
        guard balance.target > 0, balance.daysCounted >= 3 else { return false }
        let threshold = max(10, Int((Double(balance.target) * 0.15).rounded()))
        return balance.deficit >= threshold
    }

    /// Najwcześniejsza z pustych pór GŁÓWNYCH, której godzina jeszcze nie
    /// minęła. Pusty obiad o 16:00 nie jest już sprawą do załatwienia.
    static func upcomingMissingCoreSlot(
        _ day: AssistantBriefingDay,
        minuteOfDay: Int,
        times: [AssistantBriefingSlot: Int]
    ) -> AssistantBriefingSlot? {
        day.missingSlots
            .filter { AssistantBriefingSlot.core.contains($0) }
            .first { (times[$0] ?? $0.defaultMinutes) > minuteOfDay }
    }

    static func restOfWeekPlanned(_ week: [AssistantBriefingDay], from now: Date, _ cal: Calendar) -> Bool {
        let today = cal.startOfDay(for: now)
        let remaining = week.filter { cal.startOfDay(for: $0.date) >= today }
        return !remaining.isEmpty && remaining.allSatisfy(\.isPlanned)
    }

    static func plannedDaysSummary(_ week: [AssistantBriefingDay]) -> AssistantBriefing.Summary {
        let planned = week.filter(\.isPlanned).count
        return AssistantBriefing.Summary(value: planned, text: "z \(week.count) dni zaplanowanych")
    }

    static func marks(_ week: [AssistantBriefingDay], now: Date, _ cal: Calendar) -> [AssistantBriefing.DayMark] {
        week.map { day in
            AssistantBriefing.DayMark(
                id: dateKey(day.date, cal),
                short: shortWeekday(day.date, cal),
                dayNumber: String(cal.component(.day, from: day.date)),
                state: dotState(day),
                isToday: cal.isDate(day.date, inSameDayAs: now)
            )
        }
    }

    /// Pusty / częściowy (ułamek pór z daniem) / gotowy.
    static func dotState(_ day: AssistantBriefingDay) -> AssistantBriefing.DotState {
        guard day.isPlanned else { return .empty }
        if day.isComplete { return .full }
        let total = max(1, day.enabledSlots.count)
        return .partial(Double(day.plannedSlots.count) / Double(total))
    }

    static func slotMarks(_ day: AssistantBriefingDay) -> [AssistantBriefing.SlotMark] {
        let planned = day.plannedSlots
        return day.enabledSlots.sorted().map { slot in
            AssistantBriefing.SlotMark(id: slot.rawValue, title: slot.title, filled: planned.contains(slot))
        }
    }

    /// „2 z 3 posiłków”.
    static func mealsSummary(_ day: AssistantBriefingDay) -> AssistantBriefing.Summary {
        AssistantBriefing.Summary(value: day.plannedSlots.count, text: "z \(max(day.enabledSlots.count, day.plannedSlots.count)) \(mealsWord(day.enabledSlots.count))")
    }

    static func mealsWord(_ count: Int) -> String {
        if count == 1 { return "posiłku" }
        return "posiłków"
    }

    /// Trzy miniatury z planu tygodnia (najpierw z dzisiejszego dnia); brak
    /// zdjęcia zostawia puste miejsce, które widok wypełnia zapasem.
    static func teaserImages(_ c: AssistantBriefingContext) -> [URL?] {
        var urls: [URL?] = []
        for day in c.thisWeek.reversed() + c.nextWeek {
            for meal in day.meals where !urls.contains(meal.imageURL) {
                urls.append(meal.imageURL)
                if urls.count == 3 { return urls }
            }
        }
        while urls.count < 3 { urls.append(nil) }
        return urls
    }

    /// Najwyżej trzy dania dnia — karta ma być do ogarnięcia jednym spojrzeniem.
    static func mealPreviews(_ day: AssistantBriefingDay) -> [AssistantBriefing.MealPreview] {
        day.meals.sorted { $0.slot < $1.slot }.prefix(3).map { meal in
            AssistantBriefing.MealPreview(
                id: meal.slot.rawValue,
                slotTitle: meal.slot.title,
                title: meal.title,
                kcal: meal.kcal,
                imageURL: meal.imageURL
            )
        }
    }

    // MARK: - Teksty

    static func greeting(hour: Int, name: String?) -> String {
        let base: String
        switch hour {
        case 5..<11: base = "Dzień dobry"
        case 11..<17: base = "Cześć"
        case 17..<22: base = "Dobry wieczór"
        default: base = "Późna pora"
        }
        // Mianownik po przecinku, nie wołacz: wołacz jest dla imion nie do
        // przewidzenia (Kuba → Kubo, Rafał → Rafale) i potrafi wyjść potworkiem.
        return name.map { "\(base), \($0)" } ?? base
    }

    /// Pierwsze słowo z profilu — „Rafał Piechowicz” wita się jak „Rafał”.
    ///
    /// Login nie jest imieniem: konto z Apple bez podanego imienia ma w profilu
    /// zastępczy identyfikator („rpiechowicz”). Imię zaczyna się wielką literą
    /// i nie ma w sobie cyfr ani „@” — reszta dostaje powitanie bez imienia.
    static func firstName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let first = raw.split(separator: " ").first.map(String.init) ?? ""
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let initial = trimmed.first, initial.isUppercase else { return nil }
        guard !trimmed.contains("@"), !trimmed.contains(where: { $0.isNumber }) else { return nil }
        return trimmed
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    static func dateKey(_ date: Date, _ cal: Calendar) -> String {
        let parts = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static let polish = Locale(identifier: "pl_PL")

    private static func formatter(_ format: String, _ cal: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = polish
        formatter.calendar = cal
        formatter.timeZone = cal.timeZone
        formatter.dateFormat = format
        return formatter
    }

    /// „czwartek”.
    static func weekdayName(_ date: Date, _ cal: Calendar) -> String {
        formatter("EEEE", cal).string(from: date)
    }

    /// „Czw”.
    static func shortWeekday(_ date: Date, _ cal: Calendar) -> String {
        // Dwuliterowe jak w makiecie: siedem kafelków musi zmieścić się w karcie.
        switch cal.component(.weekday, from: date) {
        case 2: return "Pn"
        case 3: return "Wt"
        case 4: return "Śr"
        case 5: return "Cz"
        case 6: return "Pt"
        case 7: return "Sb"
        default: return "Nd"
        }
    }

    /// „19 września”.
    static func dayLabel(_ date: Date, _ cal: Calendar) -> String {
        formatter("d MMMM", cal).string(from: date)
    }

    /// „Śr 16 wrz” — dzień po prawej od eyebrow.
    static func shortDayLabel(_ date: Date, _ cal: Calendar) -> String {
        let day = formatter("d MMM", cal).string(from: date).replacingOccurrences(of: ".", with: "")
        return "\(shortWeekdayLong(date, cal)) \(day)"
    }

    /// „Czw” — trzyliterowy skrót do etykiety daty (w pasku tygodnia „Cz”).
    static func shortWeekdayLong(_ date: Date, _ cal: Calendar) -> String {
        switch cal.component(.weekday, from: date) {
        case 2: return "Pn"
        case 3: return "Wt"
        case 4: return "Śr"
        case 5: return "Czw"
        case 6: return "Pt"
        case 7: return "Sb"
        default: return "Nd"
        }
    }

    /// „19–20 wrz” — sobota i niedziela tego weekendu.
    static func weekendLabel(_ now: Date, _ cal: Calendar) -> String? {
        let weekday = cal.component(.weekday, from: now)
        // Sobota = 7, niedziela = 1.
        let saturday: Date?
        if weekday == 7 {
            saturday = cal.startOfDay(for: now)
        } else if weekday == 1 {
            saturday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))
        } else {
            saturday = cal.date(byAdding: .day, value: 7 - weekday, to: cal.startOfDay(for: now))
        }
        guard let saturday, let sunday = cal.date(byAdding: .day, value: 1, to: saturday) else { return nil }
        let days = [saturday, sunday].map { AssistantBriefingDay(date: $0, enabledSlots: [], meals: []) }
        return rangeLabel(days, cal)
    }

    /// „22–28 wrz” albo „29 wrz – 5 paź”.
    static func rangeLabel(_ week: [AssistantBriefingDay], _ cal: Calendar) -> String? {
        guard let first = week.first?.date, let last = week.last?.date else { return nil }
        let short = formatter("d MMM", cal)
        let sameMonth = cal.component(.month, from: first) == cal.component(.month, from: last)
        if sameMonth {
            let day = formatter("d", cal).string(from: first)
            return "\(day)–\(short.string(from: last))".replacingOccurrences(of: ".", with: "")
        }
        return "\(short.string(from: first)) – \(short.string(from: last))".replacingOccurrences(of: ".", with: "")
    }
}
