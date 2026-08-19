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

    init(id: String = UUID().uuidString, recipe: Recipe, participantIds: [String] = []) {
        self.id = id
        self.recipe = recipe
        self.participantIds = participantIds
    }

    var isShared: Bool { participantIds.isEmpty }

    // `Recipe` isn't Hashable, so identity is carried by the ids that actually
    // distinguish one planned meal from another.
    static func == (lhs: PlanMeal, rhs: PlanMeal) -> Bool {
        lhs.id == rhs.id
            && lhs.recipe.id == rhs.recipe.id
            && lhs.participantIds == rhs.participantIds
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(recipe.id)
        hasher.combine(participantIds)
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

struct DayMealPlan: Codable, Identifiable {
    var id: String { dateKey }
    let dateKey: String // "yyyy-MM-dd"
    var breakfast: [PlanMeal]
    var lunch: [PlanMeal]
    var dinner: [PlanMeal]

    init(
        dateKey: String,
        breakfast: [PlanMeal] = [],
        lunch: [PlanMeal] = [],
        dinner: [PlanMeal] = []
    ) {
        self.dateKey = dateKey
        self.breakfast = breakfast
        self.lunch = lunch
        self.dinner = dinner
    }

    func meals(for slot: MealSlot) -> [PlanMeal] {
        switch slot {
        case .breakfast: breakfast
        case .lunch: lunch
        case .dinner: dinner
        }
    }

    mutating func setMeals(_ meals: [PlanMeal], for slot: MealSlot) {
        switch slot {
        case .breakfast: breakfast = meals
        case .lunch: lunch = meals
        case .dinner: dinner = meals
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

    var allMeals: [PlanMeal] { breakfast + lunch + dinner }

    var allRecipes: [Recipe] { allMeals.map(\.recipe) }
}

// MARK: - DayMealPlan legacy decoding
//
// Persisted caches written before splits stored `breakfast/lunch/dinner` as a
// single optional Recipe. Decode those into a one-element array instead of
// throwing, so an app update doesn't blank the calendar until the next sync.
extension DayMealPlan {
    private enum CodingKeys: String, CodingKey {
        case dateKey, breakfast, lunch, dinner
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dateKey = try container.decode(String.self, forKey: .dateKey)

        func decodeSlot(_ key: CodingKeys) throws -> [PlanMeal] {
            if let meals = try? container.decodeIfPresent([PlanMeal].self, forKey: key) {
                return meals ?? []
            }
            if let legacy = try container.decodeIfPresent(Recipe.self, forKey: key) {
                return [PlanMeal(recipe: legacy)]
            }
            return []
        }

        breakfast = try decodeSlot(.breakfast)
        lunch = try decodeSlot(.lunch)
        dinner = try decodeSlot(.dinner)
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

struct SavedMealPlan: Codable {
    var breakfastEntries: [PlanEntry] = []
    var lunchEntries: [PlanEntry] = []
    var dinnerEntries: [PlanEntry] = []

    var isEmpty: Bool {
        breakfastEntries.isEmpty && lunchEntries.isEmpty && dinnerEntries.isEmpty
    }

    func entries(for slot: MealSlot) -> [PlanEntry] {
        switch slot {
        case .breakfast: breakfastEntries
        case .lunch: lunchEntries
        case .dinner: dinnerEntries
        }
    }

    /// Wszystkie przepisy (do ProductsView - pełna lista niezależnie od isSelected)
    func allRecipes() -> [Recipe] {
        (breakfastEntries + lunchEntries + dinnerEntries).map(\.recipe)
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
