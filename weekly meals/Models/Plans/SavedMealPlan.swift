import Foundation

// MARK: - PlanMeal

/// One recipe planned into a `(day, slot)` pair, together with the household
/// members it is for.
///
/// A slot can hold several of these — that is what makes „Każdy je inaczej"
/// possible (Ania a salad, Marek a schnitzel, same Wednesday lunch).
/// An empty `participantIds` means the meal is shared by the whole household,
/// which is how every pre-split row reads.
struct PlanMeal: Codable, Identifiable, Hashable {
    /// Backend `PlanItem.id`. Locally-created meals get a synthetic id until
    /// the next week refresh replaces them with the server's.
    let id: String
    var recipe: Recipe
    var participantIds: [String]
    /// Household members who marked this meal as eaten. Per-user, because a
    /// shared meal is eaten by each person on their own schedule — one flag
    /// could not answer „did *I* eat this?".
    var eatenByUserIds: [String]

    /// Ile porcji przepisu gotujemy w tym slocie. To liczba ŁĄCZNA, nie „na
    /// osobę": przepis jest napisany na `recipe.servings` porcji, więc zarówno
    /// składniki, jak i makra skalują się przez `plannedServings /
    /// recipe.servings`. Podział tej liczby między jedzących liczy dopiero
    /// `servingsPerPerson(householdMemberCount:)`.
    ///
    /// `nil` znaczy „nie wiem, policz z audytorium" — tak wygląda posiłek
    /// wczytany ze starego pliku planu albo z serwera sprzed tej zmiany.
    /// Ani zero, ani jedynka nie mogą tu zastąpić `nil`, bo to są konkretne
    /// odpowiedzi: twarde `1` w domu dwuosobowym połowiłoby i listę zakupów,
    /// i licznik kalorii. Wartość faktycznie użytą do liczenia daje
    /// `effectiveServings(householdMemberCount:)`.
    var plannedServings: Int?

    init(
        id: String = UUID().uuidString,
        recipe: Recipe,
        participantIds: [String] = [],
        eatenByUserIds: [String] = [],
        plannedServings: Int? = nil
    ) {
        self.id = id
        self.recipe = recipe
        self.participantIds = participantIds
        self.eatenByUserIds = eatenByUserIds
        self.plannedServings = plannedServings
    }

    // Plans persisted before eaten-marks existed have no `eatenByUserIds` key.
    // The synthesized decoder would reject them outright and wipe the user's
    // local calendar, so the field decodes as „nobody ate it yet" instead.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.recipe = try container.decode(Recipe.self, forKey: .recipe)
        self.participantIds = try container.decodeIfPresent([String].self, forKey: .participantIds) ?? []
        self.eatenByUserIds = try container.decodeIfPresent([String].self, forKey: .eatenByUserIds) ?? []
        // Dokładnie z tego samego powodu co linijkę wyżej: plany zapisane przed
        // dodaniem porcji nie mają tego klucza, a pliki `meal_plans.json`
        // i `saved_plan.json` są bez wersji, więc nie ma jak ich odróżnić.
        // Twarde `decode` skasowałoby użytkownikowi cały lokalny kalendarz.
        //
        // Brak klucza zostaje `nil`, a NIE jedynką: stara wspólna kolacja
        // w domu dwuosobowym ma się dalej liczyć jako dwie porcje, czyli tak
        // samo jak przed wprowadzeniem tego pola. Podstawiona tu jedynka
        // utrwaliłaby przy pierwszym zapisie połowę składników i połowę kalorii.
        self.plannedServings = try container.decodeIfPresent(Int.self, forKey: .plannedServings)
    }

    var isShared: Bool { participantIds.isEmpty }

    /// Did this member mark the meal as eaten?
    func isEaten(by memberId: String?) -> Bool {
        guard let memberId else { return false }
        return eatenByUserIds.contains(memberId)
    }

    /// Ile osób realnie je to danie. Pusta lista uczestników = całe
    /// gospodarstwo.
    func eaterCount(householdMemberCount: Int) -> Int {
        let eaters = participantIds.isEmpty ? householdMemberCount : participantIds.count
        return max(1, eaters)
    }

    /// Liczba porcji użyta do liczenia — zapisana albo policzona z audytorium.
    ///
    /// To jest jedyne miejsce, w którym „nie wiem" zamienia się w liczbę, i
    /// robi to tą samą regułą co serwer. Dzięki temu posiłek bez zapisanej
    /// wartości (stary plik planu, stary backend) degraduje się do dzisiejszych
    /// liczb, a nie do połowy. `max(1, ...)` chroni przed zerem z uszkodzonego
    /// cache'u, które wyzerowałoby makra całego dnia.
    func effectiveServings(householdMemberCount: Int) -> Int {
        guard let plannedServings else {
            return eaterCount(householdMemberCount: householdMemberCount)
        }
        return max(1, plannedServings)
    }

    /// Czy użytkownik świadomie odszedł od reguły auto.
    ///
    /// `nil` to nie odejście, tylko brak odpowiedzi — bez tego rozróżnienia
    /// każdy posiłek sprzed tej zmiany doklejałby sobie plakietkę „1 porcja"
    /// w domu, w którym mieszka więcej niż jedna osoba.
    func isCustomServings(householdMemberCount: Int) -> Bool {
        guard plannedServings != nil else { return false }
        return effectiveServings(householdMemberCount: householdMemberCount)
            != eaterCount(householdMemberCount: householdMemberCount)
    }

    /// Udział jednej osoby w tym daniu, wyrażony w porcjach przepisu.
    ///
    /// Przy regule auto (wspólne → liczba domowników, solo → 1) wychodzi z tego
    /// równo `1.0`, więc licznik kalorii pokazuje dokładnie to samo co przed
    /// wprowadzeniem porcji. To jest zamierzone: sam stepper zmienia listę
    /// zakupów, a makra dopiero wtedy, gdy ktoś ręcznie ugotuje więcej lub
    /// mniej, niż wynika z audytorium.
    func servingsPerPerson(householdMemberCount: Int) -> Double {
        Double(effectiveServings(householdMemberCount: householdMemberCount))
            / Double(eaterCount(householdMemberCount: householdMemberCount))
    }

    /// Makra przypadające na jedną osobę.
    func nutritionPerPerson(householdMemberCount: Int) -> Nutrition {
        recipe.nutrition(
            forServings: servingsPerPerson(householdMemberCount: householdMemberCount)
        )
    }

    // `Recipe` isn't Hashable, so identity is carried by the ids that actually
    // distinguish one planned meal from another.
    static func == (lhs: PlanMeal, rhs: PlanMeal) -> Bool {
        lhs.id == rhs.id
            && lhs.recipe.id == rhs.recipe.id
            && lhs.participantIds == rhs.participantIds
            && lhs.eatenByUserIds == rhs.eatenByUserIds
            && lhs.plannedServings == rhs.plannedServings
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(recipe.id)
        hasher.combine(participantIds)
        hasher.combine(eatenByUserIds)
        hasher.combine(plannedServings)
    }
}

// MARK: - Licznik, zanim znamy audytorium

extension PlanMeal {
    /// Makra na jedną osobę; `nil` znaczy „jeszcze nie wiadomo, ilu nas jest".
    ///
    /// `SessionStore` dowozi listę domowników asynchronicznie i do tego czasu
    /// `householdMembers.count` jest zerem — a zero to brak odpowiedzi, nie
    /// dom jednoosobowy. Podstawiona w to miejsce jedynka dzieliła zapisane
    /// trzy porcje przez jedną osobę, więc tuż po starcie apki ekran migał
    /// potrójnymi kaloriami, które sekundę później same spadały.
    ///
    /// Dopóki nie wiadomo, udział jednej osoby to pełna porcja przepisu —
    /// czyli dokładnie ta liczba, którą reguła auto pokaże po wczytaniu listy.
    /// Ekran nie miga wtedy w ogóle.
    func nutritionPerPerson(knownHouseholdMemberCount: Int?) -> Nutrition {
        guard let knownHouseholdMemberCount else { return recipe.nutritionPerServing }
        return nutritionPerPerson(householdMemberCount: knownHouseholdMemberCount)
    }

    /// Liczba porcji do pokazania, albo `nil`, dopóki nie da się jej wyznaczyć.
    ///
    /// Dwie niewiadome składają się tu w jedną odpowiedź: `plannedServings ==
    /// nil` (serwer nie podał) i `knownHouseholdMemberCount == nil`
    /// (`SessionStore` nie dowiózł jeszcze listy domowników). Wariant z
    /// nieopcjonalnym `householdMemberCount` musiał wtedy coś podstawić i
    /// podstawiał `max(1, 0)`, czyli jedynkę — a to jest dokładnie ta jedynka,
    /// którą użytkownik widział na produkcji zamiast swoich porcji. Tutaj
    /// „nie wiem" wychodzi na zewnątrz jako `nil` i decyzję, co pokazać,
    /// podejmuje ekran, który zna swój kontekst.
    func effectiveServings(knownHouseholdMemberCount: Int?) -> Int? {
        if let plannedServings { return max(1, plannedServings) }
        guard let knownHouseholdMemberCount else { return nil }
        return effectiveServings(householdMemberCount: knownHouseholdMemberCount)
    }
}

// MARK: - Slot audience

extension Array where Element == PlanMeal {
    /// The meals in this slot that one member actually eats.
    ///
    /// Their own dish wins over the shared one — if Ania has her own lunch she
    /// isn't also eating the shared lunch — which is what keeps a personal day
    /// view from counting two dinners against one calorie goal.
    func visibleTo(memberId: String) -> [PlanMeal] {
        let own = filter { $0.participantIds.contains(memberId) }
        return own.isEmpty ? filter(\.isShared) : own
    }

    /// Who a meal in this slot effectively feeds.
    ///
    /// The same precedence seen from the other side: a shared meal only covers
    /// the members no personal dish names. An empty result means „Wspólne" —
    /// either nobody has a personal dish, or (degenerately) everybody does.
    func effectiveAudience(for meal: PlanMeal, allMemberIds: [String]) -> [String] {
        guard meal.isShared else { return meal.participantIds }

        let claimed = Set(filter { !$0.isShared }.flatMap(\.participantIds))
        guard !claimed.isEmpty else { return [] }

        let rest = allMemberIds.filter { !claimed.contains($0) }
        return rest.isEmpty ? [] : rest
    }
}

// MARK: - DayMealPlan

/// Plan jednego dnia: sloty → warianty posiłków.
///
/// Trzymane jako słownik, a nie trzy nazwane pola. Przy trzech posiłkach
/// `breakfast/lunch/dinner` czytało się dobrze, ale każdy nowy slot oznaczał
/// dopisywanie pola i kolejnego `case` w czterech metodach — i nic nie
/// przypominało o miejscach, których się nie dopisało.
struct DayMealPlan: Codable, Identifiable {
    var id: String { dateKey }
    let dateKey: String // "yyyy-MM-dd"

    private var mealsBySlot: [MealSlot: [PlanMeal]]

    init(dateKey: String, mealsBySlot: [MealSlot: [PlanMeal]] = [:]) {
        self.dateKey = dateKey
        self.mealsBySlot = mealsBySlot.filter { !$0.value.isEmpty }
    }

    func meals(for slot: MealSlot) -> [PlanMeal] {
        mealsBySlot[slot] ?? []
    }

    mutating func setMeals(_ meals: [PlanMeal], for slot: MealSlot) {
        // Pusty slot znika ze słownika zamiast siedzieć jako pusta tablica —
        // dzięki temu `plannedSlots` i zapis na dysk nie puchną o sloty,
        // w których nic nie ma.
        if meals.isEmpty {
            mealsBySlot.removeValue(forKey: slot)
        } else {
            mealsBySlot[slot] = meals
        }
    }

    /// First variant in the slot. Kept for callers that predate splits and
    /// still think one slot means one recipe.
    func recipe(for slot: MealSlot) -> Recipe? {
        meals(for: slot).first?.recipe
    }

    func recipes(for slot: MealSlot) -> [Recipe] {
        meals(for: slot).map(\.recipe)
    }

    /// Collapses a slot to a single shared meal (or clears it). Used by the
    /// optimistic write paths, which roll a slot back to a known recipe.
    mutating func setRecipe(_ recipe: Recipe?, for slot: MealSlot) {
        guard let recipe else {
            setMeals([], for: slot)
            return
        }
        setMeals([PlanMeal(recipe: recipe)], for: slot)
    }

    /// Sloty, w których cokolwiek stoi — porą dnia.
    ///
    /// To po tym poznaje się posiłek zaplanowany w slocie, który ktoś potem
    /// wyłączył w ustawieniach. Widok pokazuje taki slot mimo wyłączenia,
    /// żeby jedzenie nie znikało po cichu.
    var plannedSlots: [MealSlot] {
        MealSlot.allCases.filter { !meals(for: $0).isEmpty }
    }

    var allMeals: [PlanMeal] {
        MealSlot.allCases.flatMap { meals(for: $0) }
    }

    var allRecipes: [Recipe] { allMeals.map(\.recipe) }
}

// MARK: - DayMealPlan Codable
//
// Klucze na dysku to `rawValue` slotu, czyli dla trójki podstawowej dokładnie
// te same nazwy, których używała poprzednia wersja („breakfast", „lunch",
// „dinner"). Dzięki temu aktualizacja aplikacji nie unieważnia cache'u.
//
// Dodatkowo cache sprzed podziału posiłków trzymał w tych kluczach pojedynczy
// `Recipe` zamiast tablicy — dekodujemy go do jednoelementowej listy, zamiast
// rzucić błędem i wyczyścić użytkownikowi kalendarz.
extension DayMealPlan {
    private struct DayKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        init(_ slot: MealSlot) { self.stringValue = slot.rawValue }

        static let dateKey = DayKey(stringValue: "dateKey")!
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DayKey.self)
        dateKey = try container.decode(String.self, forKey: .dateKey)

        var decoded: [MealSlot: [PlanMeal]] = [:]
        for slot in MealSlot.allCases {
            let key = DayKey(slot)

            // `try?` na `decodeIfPresent` daje `[PlanMeal]??` — podwójne
            // `nil` znaczy dwie różne rzeczy („klucza nie ma" vs „klucz jest,
            // ale w starym formacie"), więc rozplatamy je przez `flatMap`.
            let meals = (try? container.decodeIfPresent([PlanMeal].self, forKey: key))
                .flatMap { $0 }
            if let meals {
                if !meals.isEmpty { decoded[slot] = meals }
                continue
            }

            let legacyRecipe = (try? container.decodeIfPresent(Recipe.self, forKey: key))
                .flatMap { $0 }
            if let legacyRecipe {
                decoded[slot] = [PlanMeal(recipe: legacyRecipe)]
            }
        }
        mealsBySlot = decoded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DayKey.self)
        try container.encode(dateKey, forKey: .dateKey)
        for slot in MealSlot.allCases {
            let meals = meals(for: slot)
            guard !meals.isEmpty else { continue }
            try container.encode(meals, forKey: DayKey(slot))
        }
    }
}

// MARK: - PlanEntry

struct PlanEntry: Codable, Identifiable {
    let id: UUID
    let recipe: Recipe
    var isSelected: Bool

    init(recipe: Recipe, isSelected: Bool = false) {
        self.id = UUID()
        self.recipe = recipe
        self.isSelected = isSelected
    }
}

// MARK: - SavedMealPlan

/// Pula przepisów odłożona „na ten tydzień", slot po slocie.
///
/// Ten sam powód dla słownika co przy `DayMealPlan`: trzy nazwane pola nie
/// skalują się na sześć slotów, a kompilator nie przypomina o dopisaniu
/// czwartego.
struct SavedMealPlan: Codable {
    private var entriesBySlot: [MealSlot: [PlanEntry]]

    init(entriesBySlot: [MealSlot: [PlanEntry]] = [:]) {
        self.entriesBySlot = entriesBySlot.filter { !$0.value.isEmpty }
    }

    var isEmpty: Bool { entriesBySlot.values.allSatisfy(\.isEmpty) }

    func entries(for slot: MealSlot) -> [PlanEntry] {
        entriesBySlot[slot] ?? []
    }

    mutating func setEntries(_ entries: [PlanEntry], for slot: MealSlot) {
        if entries.isEmpty {
            entriesBySlot.removeValue(forKey: slot)
        } else {
            entriesBySlot[slot] = entries
        }
    }

    /// Zmiana wpisów jednego slotu w miejscu.
    ///
    /// Osobna metoda zamiast `inout` na przechowywanym polu, bo pola już nie
    /// ma — a wołający (`WeeklyMealStore`) i tak zawsze robił to samo:
    /// weź listę, przerób, odłóż.
    mutating func updateEntries(
        for slot: MealSlot,
        _ mutation: (inout [PlanEntry]) -> Void
    ) {
        var current = entries(for: slot)
        mutation(&current)
        setEntries(current, for: slot)
    }

    /// Wszystkie przepisy (do ProductsView - pełna lista niezależnie od isSelected)
    func allRecipes() -> [Recipe] {
        MealSlot.allCases.flatMap { entries(for: $0) }.map(\.recipe)
    }

    /// Dostępne do wybrania w CalendarView (nieoznaczone jako selected)
    func availableRecipes(for slot: MealSlot) -> [Recipe] {
        entries(for: slot).filter { !$0.isSelected }.map(\.recipe)
    }

    /// Liczba dostępnych (niewybranych) dla danego przepisu
    func availableCount(for recipeId: UUID, slot: MealSlot) -> Int {
        entries(for: slot).filter { !$0.isSelected && $0.recipe.id == recipeId }.count
    }
}

// MARK: - SavedMealPlan Codable
//
// Klucze zostają w formacie `<slot>Entries`, więc dla śniadania / obiadu /
// kolacji są identyczne jak przed zmianą i zapisana wcześniej pula wczytuje
// się bez migracji.
extension SavedMealPlan {
    private struct SlotKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        init(_ slot: MealSlot) { self.stringValue = "\(slot.rawValue)Entries" }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SlotKey.self)
        var decoded: [MealSlot: [PlanEntry]] = [:]
        for slot in MealSlot.allCases {
            let entries = try container.decodeIfPresent(
                [PlanEntry].self,
                forKey: SlotKey(slot)
            ) ?? []
            if !entries.isEmpty { decoded[slot] = entries }
        }
        entriesBySlot = decoded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SlotKey.self)
        for slot in MealSlot.allCases {
            let entries = entries(for: slot)
            guard !entries.isEmpty else { continue }
            try container.encode(entries, forKey: SlotKey(slot))
        }
    }
}
