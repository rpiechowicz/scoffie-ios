import Foundation

// „Dodaj do planu” — JEDNA reguła dla dwóch wejść ze szczegółów przepisu:
// pełnego arkusza (`AddToPlanSheet`: dowolny dzień, pora, „Dla kogo”, porcje)
// i szybkiego menu przycisku (`RecipeQuickPlan`: „Dziś · Obiad”, „Jutro ·
// Obiad” jednym stuknięciem, 6.10.2026 — „jak od Apple, mniej ceremonii”).
//
// Szybkie menu zapisuje to, co arkusz zapisałby bez ruszania czegokolwiek:
// cały dom i porcje ze szczegółów. Dlatego obie drogi liczą audytorium,
// kolizje i porcje TU, a nie każda po swojemu — inaczej menu mogłoby
// postawić drugie „Wspólne” danie tam, gdzie arkusz pokazałby „ZAMIENISZ”.

// MARK: - Porcje nowej pozycji

/// Porcje nowej pozycji planu: punkt startowy ze szczegółów przepisu i to,
/// co użytkownik zmienił w arkuszu.
struct AddToPlanPortions: Equatable {
    /// Porcje łączne (stepper łączny, 1…12) — gdy porcji osób nie da się
    /// pokazać (lista domowników jeszcze nie dojechała, dołączenie do dania,
    /// które już stoi w porze, więcej niż 6 na osobę).
    var servings: Int
    /// Czy użytkownik ruszył porcje ręcznie — tutaj albo jeszcze w szczegółach
    /// przepisu. Dopóki `false`, porcje nadążają za audytorium i nie lecą na
    /// serwer; potem są jego decyzją i „Dla kogo” ich nie rusza.
    var didOverride: Bool
    /// Porcje łączne (1/20), od których startują porcje osób: ze szczegółów
    /// przepisu albo ze steppera łącznego; `nil` = nikt nie wybierał (po 1).
    var seedTotalUnits: Int?
    /// Porcje osób ruszone stepperem (1/20); reszta osób ma punkt startowy.
    /// Klucz = id domownika.
    var touchedUnits: [String: Int] = [:]

    /// Punkt startowy ze szczegółów przepisu: porcje ze steppera (`units`,
    /// 1/20) i to, czy ktoś go ruszył. Klamrujemy już tutaj — wartość
    /// przychodzi z innego ekranu, a stepper łączny ma widełki 1…12.
    init(units: Int, didOverride: Bool) {
        servings = min(12, PlanPortions.plannedServings(forTotalUnits: units))
        self.didOverride = didOverride
        // Stepper w szczegółach i tutaj regulują to samo — świadome „gotuję
        // 4 porcje” ustawione ekran wcześniej nie może zniknąć przy zapisie.
        seedTotalUnits = didOverride ? units : nil
    }

    /// Wybrane porcje łączne rozpisane po pół porcji (suma się zgadza).
    func seedMap(eaters: [String]) -> [String: Int] {
        guard let seedTotalUnits else { return [:] }
        return PlanPortions.seededUnits(eaters: eaters, totalUnits: seedTotalUnits)
    }

    /// Porcja osoby: ruszona ręcznie, z punktu startowego albo 1 (jak reguła
    /// serwera). Po pierwszym ruszeniu nowi w audytorium zaczynają od 1.
    func units(for memberId: String, eaters: [String]) -> Int {
        if let touched = touchedUnits[memberId] { return touched }
        if touchedUnits.isEmpty, let seeded = seedMap(eaters: eaters)[memberId] { return seeded }
        return PlanPortions.missingEntryUnits
    }

    /// Porcje osób liczymy tylko dla NOWEJ pozycji — dołączenie do dania,
    /// które już stoi w porze, zostawia jego porcje (ustawia się je w planie).
    /// Więcej niż 6 porcji na osobę (na zapas) — zostaje stepper łączny.
    func showsPersonal(eaters: [String], joinsExisting: Bool) -> Bool {
        guard !eaters.isEmpty, !joinsExisting else { return false }
        guard let seedTotalUnits else { return true }
        return PlanPortions.fitsPerPerson(totalUnits: seedTotalUnits, eaterCount: eaters.count)
    }
}

// MARK: - Wybór i jego skutki

/// Dzień, pora, „Dla kogo” i porcje — oraz to, co zapis z nich zrobi w planie.
struct AddToPlanDraft {
    let recipe: Recipe
    let date: Date
    /// `nil` w arkuszu do pierwszego przemalowania — domyślną porę znamy
    /// dopiero wtedy, gdy wiadomo, które posiłki gospodarstwo planuje.
    let slot: MealSlot?
    /// Dania, które już stoją w tej porze tego dnia.
    let slotMeals: [PlanMeal]
    /// Pusty zbiór znaczy „Wspólne” — danie je całe gospodarstwo.
    let selection: Set<String>
    let members: [HouseholdMemberSnapshot]
    let portions: AddToPlanPortions

    init(
        recipe: Recipe,
        date: Date,
        slot: MealSlot?,
        store: MealCalendarStore,
        selection: Set<String> = [],
        members: [HouseholdMemberSnapshot],
        portions: AddToPlanPortions
    ) {
        self.recipe = recipe
        self.date = date
        self.slot = slot
        self.slotMeals = slot.map { store.meals(for: date, slot: $0) } ?? []
        self.selection = selection
        self.members = members
        self.portions = portions
    }

    // MARK: Audytorium

    /// Audytorium w formie, którą rozumie backend (`[]` = „Wspólne”).
    var participantsToSave: [String] {
        PlanAudienceChips.collapsed(selection, members: members)
    }

    /// Ten sam przepis stoi już w tej porze — dla kogokolwiek.
    var samePlanned: PlanMeal? {
        slotMeals.first { $0.recipe.id == recipe.id }
    }

    /// Audytorium, z którym przepis naprawdę trafi do planu: wybrane osoby
    /// plus te, dla których ten przepis już tu stoi, a pełny dom zwinięty
    /// do „Wspólne” (`PlanAudienceChips.merged`). Pozycja planu to para
    /// (pora, przepis): bez sumy zapis dla Ani zabierał obiad Rafałowi.
    var audienceToSave: [String] {
        PlanAudienceChips.merged(participantsToSave, with: samePlanned, members: members)
    }

    /// Wybrane były konkretne osoby, a po zsumowaniu wychodzi cały dom.
    var mergesIntoShared: Bool {
        samePlanned != nil && !participantsToSave.isEmpty && audienceToSave.isEmpty
    }

    /// Posiłek, który ten zapis zastąpi: ten sam dzień, pora i audytorium,
    /// INNY przepis. Pora z założenia mieści kilka posiłków („Każdy je
    /// inaczej”) — kolizją jest dopiero drugie danie dla TYCH SAMYCH osób.
    /// Porównujemy z wybranymi osobami i z audytorium po połączeniu —
    /// inaczej suma do „Wspólne” stawiała drugie wspólne danie obok.
    var conflictingMeal: PlanMeal? {
        let audiences: Set<Set<String>> = [Set(participantsToSave), Set(audienceToSave)]
        return slotMeals.first { $0.recipe.id != recipe.id && audiences.contains(Set($0.participantIds)) }
    }

    /// Ten przepis już tu jest dla wybranych osób — nie ma czego zapisywać.
    var isAlreadyPlanned: Bool {
        guard let existing = samePlanned else { return false }
        if existing.isShared { return true }
        let audience = Set(participantsToSave)
        return !audience.isEmpty && audience.isSubset(of: Set(existing.participantIds))
    }

    /// Danie, które zapis naprawdę wyprze z planu.
    var replacedMeal: PlanMeal? {
        isAlreadyPlanned ? nil : conflictingMeal
    }

    // MARK: Porcje

    /// Kto je nowe danie — osoby, których porcje pokazujemy. „Wspólne” =
    /// cały dom. Puste, dopóki lista domowników nie dojechała.
    var eaterIds: [String] {
        participantsToSave.isEmpty ? members.map(\.id) : participantsToSave
    }

    var showsPersonalPortions: Bool {
        portions.showsPersonal(eaters: eaterIds, joinsExisting: samePlanned != nil)
    }

    func units(for memberId: String) -> Int {
        portions.units(for: memberId, eaters: eaterIds)
    }

    /// Suma porcji osób ponad limit pozycji (np. dwie osoby po 6 i dołączona
    /// trzecia) — serwer odrzuciłby zapis, więc zapis czeka, aż ktoś zejdzie
    /// z porcją (minus działa zawsze, `PlanPortions.stepped`).
    var portionsOverLimit: Bool {
        guard showsPersonalPortions else { return false }
        return eaterIds.reduce(0) { $0 + units(for: $1) } > PlanPortions.maxTotalUnits
    }

    /// Mapa do wysłania — tylko gdy ktoś świadomie ustawił porcje; inaczej
    /// serwer liczy sam z audytorium.
    var portionsToSave: [String: Int]? {
        guard showsPersonalPortions, portions.didOverride else { return nil }
        let eaters = eaterIds
        return Dictionary(
            eaters.map { ($0, portions.units(for: $0, eaters: eaters)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Liczbę łączną wysyłamy tylko jako wybór użytkownika — brak pola znaczy
    /// dla serwera „policz sam z audytorium” na świeżej liście domowników.
    /// Przy łączeniu z istniejącą pozycją ręczna liczba zjadłaby porcję tamtej
    /// osoby, więc też jej nie ma. Porcje osób (gdy ktoś je ustawił) idą jako
    /// pełna mapa audytorium; wtedy liczbę łączną liczy serwer.
    var plannedServingsToSave: Int? {
        portionsToSave == nil && portions.didOverride && samePlanned == nil ? portions.servings : nil
    }

    // MARK: Zapis

    /// Zapis do planu. Wołający zamyka swój ekran od razu po wywołaniu, jak
    /// `PlanSlotPickerSheet`: wpis optymistyczny ląduje w store przed siecią,
    /// a toast przychodzi po potwierdzeniu. Store i kolejkę toastów podaje
    /// wołający — po zamknięciu arkusza jego środowiska już nie ma.
    ///
    /// `placement` = gdzie trafiło danie, jak mówi o tym ekran („Środa,
    /// 24 września · Obiad” w arkuszu, „Jutro · Obiad” w szybkim menu).
    func save(store: MealCalendarStore, toasts: SCToastCenter, placement: String) {
        guard let slot else { return }
        let recipe = recipe
        let date = date
        // Zajęty slot podmieniamy, zamiast dokładać obok — drugie „Wspólne”
        // śniadanie wjeżdżało do bazy jako wpis, którego plan nie pokazywał.
        // Nazwę wypieranego dania i audytorium bierzemy TERAZ — po zapisie
        // optymistycznym liczyłyby się już od nowego dania.
        let replacing = conflictingMeal?.recipe.id
        let replacedName = conflictingMeal?.recipe.name
        let audience = audienceToSave
        let portionsMap = portionsToSave
        let plannedServings = plannedServingsToSave
        let memberCount = members.isEmpty ? nil : members.count
        let message = mergesIntoShared ? placement + " · dla całego domu" : placement
        // Dwa identyczne błędy pod rząd nie są dla mostu zmianą — pamiętamy,
        // co było przed zapisem.
        let errorBefore = store.errorMessage

        Task { @MainActor in
            let saved = await store.upsertWeekSlot(
                recipe: recipe,
                participantIds: audience,
                plannedServings: plannedServings,
                householdMemberCount: memberCount,
                replacingRecipeId: replacing,
                portions: portionsMap,
                for: date,
                slot: slot,
                weekStart: PlanWeek.dateKey(PlanWeek.monday(of: date))
            )

            guard saved else {
                // Błąd łączności NIE ustawia `errorMessage`, więc bez tego
                // użytkownik odszedłby przekonany, że posiłek jest w planie.
                // Bez „sprawdź połączenie” — brak sieci ma jedno miejsce.
                if store.errorMessage == errorBefore {
                    toasts.error("Nie udało się dodać do planu", "Plan został bez zmian.")
                }
                return
            }

            // Toast sukcesu niesie też haptykę sukcesu (`SCToastHost`).
            if let replacedName {
                toasts.success("Zamieniono w planie", "\(slot.title) — zamiast: \(replacedName)")
            } else {
                toasts.success("Dodano do planu", message)
            }
        }
    }
}

// MARK: - Szybkie menu

/// Szybkie „Dodaj do planu” w szczegółach przepisu z katalogu: systemowe menu
/// pod przyciskiem z „Dziś · Obiad” (gdy ta pora dziś jeszcze przed nami),
/// „Jutro · Obiad” i „Inny dzień…” (pełny arkusz). Dla całego domu
/// i z porcjami ze szczegółów — dokładnie to, co zapisałby arkusz bez
/// ruszania czegokolwiek.
enum RecipeQuickPlan {
    /// Jedna pozycja menu.
    struct Option: Identifiable {
        /// „Dziś” / „Jutro”.
        let dayTitle: String
        let draft: AddToPlanDraft
        let slot: MealSlot
        /// Tydzień dnia był w tej sesji wczytany — inaczej stan pory jest
        /// niewiadomą i pozycja otwiera arkusz zamiast zapisywać od razu.
        var isWeekKnown: Bool = true

        var id: String { "\(dayTitle).\(slot.rawValue)" }
        var date: Date { draft.date }

        /// „Jutro · Obiad” — tytuł pozycji i zdanie toastu po zapisie.
        var title: String { "\(dayTitle) · \(slot.title)" }

        enum Outcome {
            /// Pora wolna (albo stoi w niej to samo danie dla części domu —
            /// zapis dołącza resztę): zapis jednym stuknięciem.
            case add
            /// Pora zajęta INNYM daniem dla całego domu — zapis by je
            /// podmienił, a tego po cichu nie robimy: pozycja otwiera pełny
            /// arkusz z kartą „ZAMIENISZ”.
            case replaces(PlanMeal)
            /// W porze stoi INNE danie dla części domu („Każdy je inaczej”).
            /// Zapis dołożyłby wspólne danie obok i ktoś miałby dwa — niech
            /// zdecyduje arkusz z „Dla kogo”.
            case besides(PlanMeal)
            /// To danie już tu stoi — pozycja wyłączona.
            case alreadyPlanned
            /// Tydzień dnia nie był jeszcze wczytany (jutro w niedzielę = nowy
            /// tydzień): pusta pora może być tylko niewczytana, więc pozycja
            /// otwiera pełny arkusz zamiast dokładać danie na ślepo.
            case unknownWeek
        }

        var outcome: Outcome {
            if !isWeekKnown { return .unknownWeek }
            if draft.isAlreadyPlanned { return .alreadyPlanned }
            if let replaced = draft.replacedMeal { return .replaces(replaced) }
            if let other = draft.slotMeals.first(where: { $0.recipe.id != draft.recipe.id }) {
                return .besides(other)
            }
            return .add
        }
    }

    /// Pory, w które przepis pasuje (`suitableMealTypes`), spośród `slots` —
    /// najpierw jego pora bazowa, potem reszta w kolejności dnia. Tę samą
    /// kolejność bierze domyślny wybór pory w arkuszu, więc „Jutro · Obiad”
    /// w menu i arkusz otwarty na jutro mówią o tej samej porze. Bazowa
    /// pierwsza, bo koktajl z II śniadania ma iść na II śniadanie, a nie na
    /// śniadanie, które jest wcześniej w dniu.
    static func candidateSlots(for recipe: Recipe, among slots: [MealSlot]) -> [MealSlot] {
        let fitting = slots.sortedByDay.filter { recipe.fits($0) }
        guard let base = recipe.primarySlot, fitting.contains(base) else { return fitting }
        return [base] + fitting.filter { $0 != base }
    }

    /// „Dziś · …” (pierwsza pasująca pora, która dziś jeszcze nie minęła —
    /// pora bez godziny, jak przekąska, nie mija) i „Jutro · …” (pierwsza
    /// pasująca). Pusto, gdy dom nie planuje żadnej pory, w którą przepis
    /// pasuje — wtedy przycisk otwiera od razu pełny arkusz.
    static func options(
        recipe: Recipe,
        store: MealCalendarStore,
        enabledSlots: [MealSlot],
        schedule: MealSlotSchedule,
        members: [HouseholdMemberSnapshot],
        portions: AddToPlanPortions,
        now: Date = Date()
    ) -> [Option] {
        let slots = candidateSlots(for: recipe, among: enabledSlots)
        guard !slots.isEmpty else { return [] }

        let calendar = Calendar.current
        let nowMinutes = MealSlotSchedule.minutes(from: now, calendar: calendar)
        var result: [Option] = []

        func option(_ dayTitle: String, _ date: Date, _ slot: MealSlot) -> Option {
            let weekStart = PlanWeek.dateKey(PlanWeek.monday(of: date))
            return Option(
                dayTitle: dayTitle,
                draft: AddToPlanDraft(
                    recipe: recipe,
                    date: date,
                    slot: slot,
                    store: store,
                    members: members,
                    portions: portions
                ),
                slot: slot,
                isWeekKnown: store.hasLoadedWeek(weekStart)
            )
        }

        // Ta sama miara „minęło”, co talerze w Kalendarzu: godzina pory
        // z rozkładu domu wobec zegara.
        if let today = slots.first(where: { slot in
            guard let minutes = schedule.minutes(for: slot) else { return true }
            return minutes > nowMinutes
        }) {
            result.append(option("Dziś", now, today))
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), let first = slots.first {
            result.append(option("Jutro", tomorrow, first))
        }
        return result
    }
}
