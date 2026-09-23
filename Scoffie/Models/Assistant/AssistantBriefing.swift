import Foundation

// Powitanie pustej rozmowy z asystentem — LOGIKA, bez SwiftUI.
//
// Pusty ekran asystenta nie jest jednym zdaniem dla wszystkich. Telefon zna
// godzinę, dzień tygodnia, plan tego i przyszłego tygodnia, godziny posiłków,
// bilans makro i stan puli — z tego składa się JEDNO powitanie: otwarcie,
// jedno zdanie pomocy, główna akcja i jedna alternatywa. „Mam inny pomysł”
// (fokus pola) dokłada widok zawsze, a przykład w polu zmienia się razem
// z sytuacją. Makieta: „Scoffie — Asystent · Empty state v2”, wariant A.
//
// Podział na trzy warstwy jest celowy:
//   - `AssistantBriefingContext` — fakty (co aplikacja wie),
//   - `AssistantBriefingResolver` — priorytety (co z tych faktów wynika),
//   - `AssistantBriefing` — model widoku (co narysować, bez wiedzy, jak).
// Widok (`AssistantGreeting`) dostaje gotowy model i nie liczy nic sam.
//
// Język (reguła z makiety): mówimy, w czym mogę pomóc. Bez liczenia braków
// („0 z 4”), bez dat i bez ponaglania. Stan dnia mówią talerzyki (zdjęcie
// albo pusty krążek), nie liczby.
//
// Każde zdanie wysyłane z powitania jest KOMPLETNE: mówi, na kiedy (dziś,
// jutro, ten tydzień), na jaką porę i czego chcemy — asystent nie ma
// o co dopytywać, więc jedno dotknięcie = jedna tura. „Chcę zamienić jeden
// dzisiejszy posiłek” kończyło się pytaniem „który?”; teraz powitanie samo
// wskazuje danie, bo zna plan.
//
// Akcje, które dotyczą JEDNEJ pory („Pokaż 3 pomysły”), proszą wprost
// o dania „do wyboru” — serwer odpowiada wtedy kartą OPTIONS, czyli
// arkuszem wyboru posiłku ze zdjęciem, opisem i makro. Plan dnia albo
// tygodnia to propozycja do zatwierdzenia, której dania przegląda się
// w tym samym arkuszu.
//
// Plik importuje TYLKO Foundation, żeby dało się go skompilować razem
// z `Scripts/AssistantLogic/main.swift` bez Xcode — to jedyny sposób na
// test priorytetów w projekcie bez targetu testów.

// MARK: - Fakty

/// Pora dnia w słowniku powitania — kopia `MealSlot` bez zależności od
/// SwiftUI (tam `cozyAccent` jest `Color`). Mapowanie 1:1 po `rawValue`.
enum AssistantBriefingSlot: String, CaseIterable, Comparable, Hashable {
    case breakfast
    case secondBreakfast
    case lunch
    case afternoonSnack
    case dinner
    case snack

    /// Posiłki, których brak jest WAŻNY — pusty podwieczorek nie robi powitania.
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

    /// Krótka nazwa pod talerzykiem — pięć pór musi zmieścić się w rzędzie.
    var shortTitle: String {
        switch self {
        case .breakfast: return "Śniad."
        case .secondBreakfast: return "II śn."
        case .lunch: return "Obiad"
        case .afternoonSnack: return "Podw."
        case .dinner: return "Kolacja"
        case .snack: return "Przek."
        }
    }

    /// Biernik po czasowniku: „Dobierz kolację”, „masz już obiad”.
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

    /// Mianownik małą literą: „Za 40 minut obiad.”
    var nominative: String {
        switch self {
        case .secondBreakfast: return "II śniadanie"
        default: return title.lowercased()
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

/// Jeden dzień planu widziany z powitania.
struct AssistantBriefingDay: Equatable {
    struct Meal: Equatable {
        let slot: AssistantBriefingSlot
        let title: String
        /// Kalorie na osobę; 0 = nieznane.
        let kcal: Int
        let imageURL: URL?
        /// Czas przygotowania; 0 = nieznany.
        var minutes: Int = 0
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
    /// Brakujące pory GŁÓWNE (śniadanie, obiad, kolacja).
    var missingCoreSlots: [AssistantBriefingSlot] {
        missingSlots.filter { AssistantBriefingSlot.core.contains($0) }
    }
    /// Każda planowana pora ma danie.
    var isComplete: Bool { isPlanned && missingSlots.isEmpty }

    func meal(_ slot: AssistantBriefingSlot) -> Meal? {
        meals.first { $0.slot == slot }
    }
}

/// Bilans makro policzony z PRAWDZIWYCH liczb — powitanie nigdy ich nie zmyśla.
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
    enum Kind: String, Equatable, CaseIterable {
        case trialExhausted
        case newUser
        case lateNight
        case weekEmpty
        case todayEmpty
        case cookSoon
        case breakfastMissing
        case lunchMissing
        case dinnerMissing
        case tomorrowEmpty
        case tomorrowPartial
        case nextWeekEmpty
        case balanceIssue
        case weekReady
        case weekendInspiration
        case eveningReady
        case dayReady
    }

    /// Talerzyk jednej pory: zdjęcie dania albo pusty, kreskowany krążek.
    struct Plate: Equatable, Identifiable {
        let id: String
        /// „Obiad” — krótko, pod talerzykiem.
        let title: String
        let imageURL: URL?
        let filled: Bool
        /// Pora, o której mówi powitanie — podświetlona.
        let isFocus: Bool
    }

    /// Jedno danie z planu — zdjęcie, nazwa i liczby, które liczą się od zera.
    struct MealPreview: Equatable {
        /// „OBIAD · 14:00”.
        let eyebrow: String
        let title: String
        let minutes: Int
        let kcal: Int
        let imageURL: URL?
    }

    /// Kontekst pod zdaniem pomocy — mówi stan bez słów.
    enum Visual: Equatable {
        case plain
        /// Pory jednego dnia jako talerzyki.
        case plates([Plate])
        /// Najbliższe danie z planu.
        case meal(MealPreview)
        /// Średnia vs cel na jednym pasku — liczby liczą się od zera.
        case balance(current: Int, target: Int, unit: String)
    }

    struct Action: Equatable, Identifiable {
        enum Kind: Equatable {
            /// Wysyła gotowe zdanie do asystenta — w historii widać, o co poproszono.
            case ask(String)
            /// „Mam inny pomysł” — tylko fokus pola, nic nie wysyła.
            case compose
            case openPlans
            case openHistory
        }

        let title: String
        let kind: Kind

        var id: String { title }

        static func ask(_ title: String, _ prompt: String) -> Action {
            Action(title: title, kind: .ask(prompt))
        }

        static let compose = Action(title: "Mam inny pomysł", kind: .compose)
    }

    let kind: Kind
    /// Otwarcie — jedno pytanie albo stwierdzenie, do trzech linii.
    let headline: String
    /// Jedno zdanie: w czym mogę pomóc.
    let supporting: String
    let visual: Visual
    let primary: Action
    /// Alternatywy pod główną akcją; ostatnia to zwykle „Mam inny pomysł”.
    let alternatives: [Action]
    /// Przykład pytania w polu wiadomości — pasuje do sytuacji.
    let placeholder: String

    /// Wyciszona wersja (wykorzystany limit): znak w szarości, bez pola.
    var isQuiet: Bool { kind == .trialExhausted }
}

// MARK: - Resolver

enum AssistantBriefingResolver {
    /// Ile przed porą posiłku powitanie mówi „Za 40 minut obiad”.
    static let cookSoonWindow = 90

    /// Kolejność sprawdzeń JEST specyfikacją: pierwsza prawdziwa sytuacja
    /// wygrywa, pokazuje się jedno powitanie.
    static func resolve(_ c: AssistantBriefingContext) -> AssistantBriefing {
        let cal = c.calendar
        let hour = cal.component(.hour, from: c.now)
        let minuteOfDay = hour * 60 + cal.component(.minute, from: c.now)
        // 1 = niedziela w kalendarzu gregoriańskim.
        let weekday = cal.component(.weekday, from: c.now)
        let isWeekend = weekday == 7 || weekday == 1
        let isLateWeek = weekday == 5 || weekday == 6 || isWeekend
        let allDays = c.thisWeek + c.nextWeek
        let today = allDays.first { cal.isDate($0.date, inSameDayAs: c.now) }
        let tomorrowDate = cal.date(byAdding: .day, value: 1, to: c.now) ?? c.now
        let tomorrow = allDays.first { cal.isDate($0.date, inSameDayAs: tomorrowDate) }
        let time = { (slot: AssistantBriefingSlot) in c.slotMinutes[slot] ?? slot.defaultMinutes }

        // 1. Wyczerpana pula — nic nie da się wysłać, więc żadna podpowiedź
        //    nie ma prawa się pojawić. Wyciszone, bez pola wiadomości.
        if c.trialExhausted {
            return AssistantBriefing(
                kind: .trialExhausted,
                headline: "Darmowe wiadomości są wykorzystane.",
                supporting: "Rozmowy i zapisany plan zostają. Pełny asystent jest w planach.",
                visual: .plain,
                primary: AssistantBriefing.Action(title: "Zobacz plany", kind: .openPlans),
                alternatives: [AssistantBriefing.Action(title: "Historia rozmów", kind: .openHistory)],
                placeholder: ""
            )
        }

        // 2. Nowe konto — Scoffie nie zna jeszcze tego domu i nie udaje, że zna.
        if c.isNewUser {
            let name = firstName(c.displayName)
            return AssistantBriefing(
                kind: .newUser,
                headline: name.map { "Cześć, \($0). Od czego zaczniemy?" } ?? "Cześć, od czego zaczniemy?",
                supporting: "Mogę ułożyć plan na kilka dni albo podsunąć jeden przepis na dziś.",
                visual: .plain,
                primary: .ask("Zaproponuj 3 dni", "Zaproponuj plan na 3 dni \(hour >= 17 ? "od jutra" : "od dziś") pod nasze cele"),
                alternatives: [.ask("Co potrafisz?", "Co potrafisz?"), .compose],
                placeholder: "Np. tydzień obiadów bez mięsa"
            )
        }

        // 3. Późna pora (22:00–4:59) — nie gotujemy, najwyżej myślimy o jutrze.
        if hour >= 22 || hour < 5 {
            // Po północy „jutro” to już dzisiejszy dzień — i tak mówi zdanie
            // do asystenta, bo on liczy dni od daty z telefonu.
            let next = hour < 5 ? today : tomorrow
            let nextWord = hour < 5 ? "dziś" : "jutro"
            let light = AssistantBriefing.Action.ask(
                "Coś lekkiego na teraz",
                hour < 5
                    ? "Pokaż 3 lekkie przekąski na dziś, na teraz, bez gotowania, do wyboru"
                    : "Pokaż 3 lekkie przekąski na dziś wieczór, bez gotowania, do wyboru"
            )
            if let next, !next.isPlanned {
                return AssistantBriefing(
                    kind: .lateNight,
                    headline: "Późno już. Ułożymy jutro na spokojnie?",
                    supporting: "Rano będzie wiadomo, co przygotować — bez myślenia przed kawą.",
                    visual: .plates(plates(next, focus: nil)),
                    primary: .ask("Ułóż jutro", "Zaproponuj cały dzień na \(nextWord)"),
                    alternatives: [light, .compose],
                    placeholder: "Np. coś lekkiego bez gotowania"
                )
            }
            return AssistantBriefing(
                kind: .lateNight,
                headline: "Jutro jest już w planie.",
                supporting: "Jeśli coś Cię jeszcze kusi, podsunę lekką przekąskę.",
                visual: next.map { AssistantBriefing.Visual.plates(plates($0, focus: nil)) } ?? AssistantBriefing.Visual.plain,
                primary: light,
                alternatives: [.ask("Zakupy na jutro", "Co muszę kupić na \(nextWord)?"), .compose],
                placeholder: "Np. coś lekkiego bez gotowania"
            )
        }

        // 4. Bieżący tydzień w całości pusty — gdy zostało z niego dość dni,
        //    żeby planowanie go miało sens (w piątek wieczorem już nie).
        let remainingThisWeek = c.thisWeek.filter { cal.startOfDay(for: $0.date) >= cal.startOfDay(for: c.now) }
        if !c.thisWeek.isEmpty, c.thisWeek.allSatisfy({ !$0.isPlanned }), remainingThisWeek.count >= 3 {
            let evening = hour >= 17
            return AssistantBriefing(
                kind: .weekEmpty,
                headline: "Ułożymy ten tydzień?",
                supporting: "Dobiorę posiłki pod Wasze cele i przepisy — albo zacznijmy od jednego dnia.",
                visual: .plain,
                primary: .ask("Zaplanuj tydzień", "Zaplanuj mi resztę tego tygodnia pod nasze cele i przepisy"),
                alternatives: [
                    evening
                        ? AssistantBriefing.Action.ask("Tylko jutro", "Zaproponuj cały dzień na jutro")
                        : AssistantBriefing.Action.ask("Tylko dziś", "Zaproponuj cały dzień na dziś"),
                    .compose,
                ],
                placeholder: "Np. obiady do 30 minut przez cały tydzień"
            )
        }

        // 5. Dziś pusto, a do kolacji jest jeszcze czas.
        if let today, !today.isPlanned, minuteOfDay < time(.dinner) {
            let next = upcomingSlot(today.enabledSlots.isEmpty ? AssistantBriefingSlot.core : today.enabledSlots, minuteOfDay: minuteOfDay, times: c.slotMinutes) ?? .dinner
            return AssistantBriefing(
                kind: .todayEmpty,
                headline: "Dziś jeszcze nic nie ma w planie.",
                supporting: "Ułożę cały dzień albo pokażę pomysły na \(next.accusative).",
                visual: .plates(plates(today, focus: next)),
                primary: .ask("Ułóż dzisiejszy dzień", "Zaproponuj cały dzień na dziś"),
                alternatives: [ideas(for: next, day: "dziś", title: "Pomysły na \(next.accusative)"), .compose],
                placeholder: placeholder(for: next)
            )
        }

        // 6. Najbliższe danie z planu zaraz — przepis ważniejszy niż planowanie.
        if let today, let soon = upcomingPlannedMeal(today, minuteOfDay: minuteOfDay, times: c.slotMinutes) {
            let minutesLeft = time(soon.slot) - minuteOfDay
            return AssistantBriefing(
                kind: .cookSoon,
                headline: cookSoonHeadline(slot: soon.slot, minutesLeft: minutesLeft),
                supporting: "Rozpiszę kroki albo podmienię na coś szybszego.",
                visual: .meal(AssistantBriefing.MealPreview(
                    eyebrow: "\(soon.slot.title) · \(clock(time(soon.slot)))",
                    title: soon.title,
                    minutes: soon.minutes,
                    kcal: soon.kcal,
                    imageURL: soon.imageURL
                )),
                primary: .ask("Jak to ugotować?", "Jak ugotować \(soon.title)? Rozpisz kroki."),
                alternatives: [
                    .ask("Coś szybszego", "Zamień \(soon.slot.accusative) na dziś (\(soon.title)) na coś szybszego: pokaż 3 dania do wyboru"),
                    .compose,
                ],
                placeholder: "Np. czym zastąpić składnik, którego nie mam"
            )
        }

        // 7. Dziś jest plan, ale brakuje ważnej pory, która jeszcze nie minęła.
        if let today, today.isPlanned,
           let missing = upcomingMissingCoreSlot(today, minuteOfDay: minuteOfDay, times: c.slotMinutes) {
            return missingMeal(missing, today: today)
        }

        // 8. Wieczór, a jutro pusto albo tylko częściowo.
        if hour >= 17, let tomorrow {
            if !tomorrow.isPlanned {
                let first = (tomorrow.enabledSlots.isEmpty ? AssistantBriefingSlot.core : tomorrow.enabledSlots).min() ?? .breakfast
                return AssistantBriefing(
                    kind: .tomorrowEmpty,
                    headline: "Zaplanujemy coś dobrego na jutro?",
                    supporting: "Mogę zaproponować cały dzień albo pomóc wybrać jeden posiłek.",
                    visual: .plates(plates(tomorrow, focus: nil)),
                    primary: .ask("Zaproponuj dzień", "Zaproponuj cały dzień na jutro"),
                    alternatives: [ideas(for: first, day: "jutro", title: "Tylko \(first.accusative)"), .compose],
                    placeholder: "Np. coś na kolację w 15 minut"
                )
            }
            let missing = tomorrow.missingCoreSlots
            if let first = missing.first {
                let planned = tomorrow.meals.map(\.slot).sorted().prefix(2).map(\.accusative)
                return AssistantBriefing(
                    kind: .tomorrowPartial,
                    headline: "Jutro masz już \(joined(planned)). Dobierzemy resztę?",
                    supporting: "Dobiorę brakujące posiłki tak, żeby dzień się domykał.",
                    visual: .plates(plates(tomorrow, focus: first)),
                    primary: .ask(
                        "Dobierz resztę dnia",
                        "Dobierz brakujące posiłki na jutro: \(joined(missing.map(\.accusative)))"
                    ),
                    alternatives: [ideas(for: first, day: "jutro", title: "Tylko \(first.accusative)"), .compose],
                    placeholder: placeholder(for: first)
                )
            }
        }

        // 9. Koniec tygodnia, a przyszły tydzień pusty.
        if isLateWeek, !c.nextWeek.isEmpty, c.nextWeek.allSatisfy({ !$0.isPlanned }) {
            return AssistantBriefing(
                kind: .nextWeekEmpty,
                headline: "Przyszły tydzień jest jeszcze pusty.",
                supporting: "Ułożę go teraz, a zakupy zrobisz na spokojnie przed poniedziałkiem.",
                visual: .plain,
                primary: .ask("Zaplanuj przyszły tydzień", "Zaplanuj mi przyszły tydzień pod nasze cele i przepisy"),
                alternatives: [.ask("Tylko poniedziałek", "Zaproponuj cały dzień na najbliższy poniedziałek"), .compose],
                placeholder: "Np. obiady do pracy na cały tydzień"
            )
        }

        // 10. Realny brak w bilansie — tylko z policzonych liczb.
        if let balance = c.balance, isSignificant(balance) {
            return AssistantBriefing(
                kind: .balanceIssue,
                headline: "W tym tygodniu brakuje Ci \(balance.macroGenitive).",
                supporting: "Podmienię jeden posiłek albo dołożę coś, co domknie cel.",
                visual: .balance(current: balance.averagePerDay, target: balance.target, unit: balance.unit),
                primary: .ask("Pokaż, co poprawić", "Czego brakuje w planie na ten tydzień, żeby domknąć \(balance.macroAccusative)?"),
                alternatives: [
                    // Który posiłek — wybiera asystent, z bilansu; pytanie
                    // „który?” kosztowałoby drugą turę.
                    .ask("Podmień 1 posiłek", "Znajdź w planie na ten tydzień posiłek z najmniejszą ilością \(balance.macroGenitive) i pokaż 3 zamienniki z większą ilością \(balance.macroGenitive) do wyboru"),
                    .compose,
                ],
                placeholder: "Np. więcej \(balance.macroGenitive) w śniadaniach"
            )
        }

        // 11. Tydzień gotowy: od dziś do niedzieli każdy dzień ma plan.
        if let today, today.isComplete, restOfWeekPlanned(c.thisWeek, from: c.now, cal), !isWeekend {
            return AssistantBriefing(
                kind: .weekReady,
                headline: "Do niedzieli wszystko jest w planie.",
                supporting: "Zbiorę listę zakupów albo podsunę coś nowego na odmianę.",
                visual: .plates(plates(today, focus: nil)),
                primary: .ask("Lista zakupów", "Co muszę kupić na ten tydzień?"),
                alternatives: [.ask("Coś nowego na weekend", "Pokaż 3 nowe pomysły na obiad na sobotę do wyboru"), .compose],
                placeholder: "Np. zamień piątkową kolację na rybę"
            )
        }

        // 12. Weekend z planem na dziś — pomysł zamiast obowiązku.
        if isWeekend, let today, today.isPlanned, hour < 17 {
            return AssistantBriefing(
                kind: .weekendInspiration,
                headline: "Masz ochotę ugotować coś większego?",
                supporting: "Wybiorę coś dla całego domu z Waszych przepisów.",
                visual: .plates(plates(today, focus: nil)),
                primary: .ask("Pokaż 3 pomysły", "Pokaż 3 pomysły na obiad na dziś dla całego domu do wyboru"),
                alternatives: [.ask("Coś do godziny", "Pokaż 3 obiady na dziś do godziny gotowania do wyboru"), .compose],
                placeholder: "Np. coś na obiad z rodziną, bez ryby"
            )
        }

        // 13. Wieczór, a jutro gotowe.
        if hour >= 17, let tomorrow, tomorrow.isPlanned {
            return AssistantBriefing(
                kind: .eveningReady,
                headline: "Jutro też jest gotowe.",
                supporting: "Zbiorę zakupy na jutro albo podmienię jedno danie.",
                visual: .plates(plates(tomorrow, focus: nil)),
                primary: .ask("Zakupy na jutro", "Co muszę kupić na jutro?"),
                alternatives: [swapAction(mainMeal(tomorrow), day: "jutro"), .compose],
                placeholder: "Np. zamień jutrzejszy obiad na coś szybszego"
            )
        }

        // 14. Dzień gotowy — stan spokojny, pomoc przy drobnych zmianach.
        let readyDay = today ?? tomorrow
        // Zamiana wskazuje danie z góry: najbliższe, którego pora jeszcze
        // nie minęła, a gdy wszystkie minęły — ostatnie z dnia.
        let swapMeal = today.flatMap { day in
            day.meals.sorted { $0.slot < $1.slot }.first { time($0.slot) > minuteOfDay }
                ?? day.meals.max { $0.slot < $1.slot }
        }
        return AssistantBriefing(
            kind: .dayReady,
            headline: hour < 11 ? "Dzień jest ułożony." : "Na dziś wszystko jest w planie.",
            supporting: "Jeśli masz ochotę na odmianę, podmienię jeden posiłek.",
            visual: readyDay.map { AssistantBriefing.Visual.plates(plates($0, focus: nil)) } ?? AssistantBriefing.Visual.plain,
            primary: swapMeal.map { swapAction($0, day: "dziś") }
                ?? ideas(for: .dinner, day: "dziś", title: "Pomysły na kolację"),
            alternatives: [.ask("Sprawdź bilans", "Jak wychodzi mój bilans w tym tygodniu?"), .compose],
            placeholder: "Np. zamień kolację na coś lżejszego"
        )
    }

    // MARK: - Sytuacje z porą

    /// Brakująca pora główna dziś — każda ma własne otwarcie i przykład.
    static func missingMeal(_ slot: AssistantBriefingSlot, today: AssistantBriefingDay) -> AssistantBriefing {
        let visual = AssistantBriefing.Visual.plates(plates(today, focus: slot))
        switch slot {
        case .breakfast:
            return AssistantBriefing(
                kind: .breakfastMissing,
                headline: "Co dziś na śniadanie?",
                supporting: "Pokażę trzy pomysły z Twoich przepisów — wybierzesz jeden.",
                visual: visual,
                primary: ideas(for: .breakfast, day: "dziś"),
                alternatives: [.ask("Coś w 10 minut", "Pokaż 3 śniadania do 10 minut na dziś do wyboru"), .compose],
                placeholder: placeholder(for: .breakfast)
            )
        case .lunch:
            return AssistantBriefing(
                kind: .lunchMissing,
                headline: "Co dziś na obiad?",
                supporting: "Reszta dnia już jest — dobiorę obiad, który do niej pasuje.",
                visual: visual,
                primary: ideas(for: .lunch, day: "dziś"),
                alternatives: [.ask("Coś do 30 minut", "Pokaż 3 obiady do 30 minut na dziś do wyboru"), .compose],
                placeholder: placeholder(for: .lunch)
            )
        default:
            return AssistantBriefing(
                kind: .dinnerMissing,
                headline: "Co dziś na kolację?",
                supporting: "Podsunę trzy pomysły albo dopasuję coś do tego, co masz w lodówce.",
                visual: visual,
                primary: ideas(for: .dinner, day: "dziś"),
                alternatives: [.ask("Coś lekkiego", "Pokaż 3 lekkie kolacje na dziś do wyboru"), .compose],
                placeholder: placeholder(for: .dinner)
            )
        }
    }

    /// „Pokaż 3 pomysły” — prośba o dania DO WYBORU, na którą serwer
    /// odpowiada arkuszem wyboru posiłku.
    static func ideas(for slot: AssistantBriefingSlot, day: String, title: String = "Pokaż 3 pomysły") -> AssistantBriefing.Action {
        .ask(title, "Pokaż 3 pomysły na \(slot.accusative) na \(day) do wyboru")
    }

    /// „Zamień obiad” — z nazwą dania i dniem w zdaniu, żeby asystent nie
    /// pytał, który posiłek. Odpowiedź to dania DO WYBORU na tę porę.
    static func swapAction(_ meal: AssistantBriefingDay.Meal, day: String) -> AssistantBriefing.Action {
        .ask(
            "Zamień \(meal.slot.accusative)",
            "Zamień \(meal.slot.accusative) na \(day) (\(meal.title)): pokaż 3 inne dania do wyboru"
        )
    }

    /// Danie dnia, które najczęściej się zamienia: obiad, potem kolacja,
    /// potem pierwsze z planu. Wołane tylko dla dnia z planem.
    static func mainMeal(_ day: AssistantBriefingDay) -> AssistantBriefingDay.Meal {
        day.meal(.lunch) ?? day.meal(.dinner) ?? day.meals.sorted { $0.slot < $1.slot }[0]
    }

    /// Przykład w polu — pasuje do pory, o której mowa.
    static func placeholder(for slot: AssistantBriefingSlot) -> String {
        switch slot {
        case .breakfast, .secondBreakfast: return "Np. coś na słodko z płatkami owsianymi"
        case .lunch: return "Np. mam kurczaka i paprykę"
        case .dinner: return "Np. mam jajka i szpinak"
        case .afternoonSnack, .snack: return "Np. coś słodkiego bez cukru"
        }
    }

    /// „Za 40 minut obiad.”, „Za godzinę kolacja.”, „Zaraz śniadanie.”
    static func cookSoonHeadline(slot: AssistantBriefingSlot, minutesLeft: Int) -> String {
        let meal = slot.nominative
        switch minutesLeft {
        case ..<6: return "Zaraz \(meal)."
        case 6..<60: return "Za \(minutesLeft) \(minutesWord(minutesLeft)) \(meal)."
        case 60..<75: return "Za godzinę \(meal)."
        default: return "Za półtorej godziny \(meal)."
        }
    }

    /// „minutę”, „minuty”, „minut” — biernik po „za”.
    static func minutesWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if count == 1 { return "minutę" }
        if (2...4).contains(mod10), !(12...14).contains(mod100) { return "minuty" }
        return "minut"
    }

    /// „obiad”, „obiad i kolację”, „śniadanie, obiad i kolację”.
    static func joined(_ words: [String]) -> String {
        guard let last = words.last else { return "" }
        guard words.count > 1 else { return last }
        return words.dropLast().joined(separator: ", ") + " i " + last
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
        day.missingCoreSlots.first { (times[$0] ?? $0.defaultMinutes) > minuteOfDay }
    }

    /// Najbliższa pora (dowolna z podanych), której godzina jeszcze nie minęła.
    static func upcomingSlot(
        _ slots: [AssistantBriefingSlot],
        minuteOfDay: Int,
        times: [AssistantBriefingSlot: Int]
    ) -> AssistantBriefingSlot? {
        slots.sorted().first { (times[$0] ?? $0.defaultMinutes) > minuteOfDay }
    }

    /// Danie z planu, którego pora przypada w ciągu `cookSoonWindow` minut.
    static func upcomingPlannedMeal(
        _ day: AssistantBriefingDay,
        minuteOfDay: Int,
        times: [AssistantBriefingSlot: Int]
    ) -> AssistantBriefingDay.Meal? {
        day.meals
            .sorted { $0.slot < $1.slot }
            .first { meal in
                let left = (times[meal.slot] ?? meal.slot.defaultMinutes) - minuteOfDay
                return left >= 0 && left <= cookSoonWindow
            }
    }

    static func restOfWeekPlanned(_ week: [AssistantBriefingDay], from now: Date, _ cal: Calendar) -> Bool {
        let today = cal.startOfDay(for: now)
        let remaining = week.filter { cal.startOfDay(for: $0.date) >= today }
        return !remaining.isEmpty && remaining.allSatisfy(\.isPlanned)
    }

    /// Talerzyki pór dnia w porządku dnia; `focus` = pora, o której mowa.
    static func plates(_ day: AssistantBriefingDay, focus: AssistantBriefingSlot?) -> [AssistantBriefing.Plate] {
        let slots = day.enabledSlots.isEmpty ? AssistantBriefingSlot.core : day.enabledSlots
        return slots.sorted().map { slot in
            let meal = day.meal(slot)
            return AssistantBriefing.Plate(
                id: slot.rawValue,
                title: slots.count > 4 ? slot.shortTitle : slot.title,
                imageURL: meal?.imageURL,
                filled: meal != nil,
                isFocus: slot == focus
            )
        }
    }

    // MARK: - Teksty

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
}
