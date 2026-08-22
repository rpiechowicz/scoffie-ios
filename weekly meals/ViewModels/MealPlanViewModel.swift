import Foundation
import Observation

@Observable
class MealPlanViewModel {
    // MARK: - State

    var isActive: Bool = false

    /// Wybór użytkownika, slot po slocie.
    ///
    /// Słownik zamiast `breakfastRecipes / lunchRecipes / dinnerRecipes` —
    /// przy sześciu slotach trzy nazwane tablice zamieniały każdą operację
    /// w trzykrotnie powtórzonego `switch`-a.
    private(set) var recipesBySlot: [MealSlot: [Recipe]] = [:]

    var slotFullAlert: MealSlot? = nil
    var showSummarySheet: Bool = false

    // MARK: - Constants

    static let maxPerSlot = 7

    /// Sufit na cały tydzień skaluje się liczbą slotów — inaczej po włączeniu
    /// podwieczorku limit obcinałby plan w pół tygodnia.
    static var maxTotal: Int { maxPerSlot * MealSlot.allCases.count }

    // MARK: - Computed

    var totalCount: Int {
        recipesBySlot.values.reduce(0) { $0 + $1.count }
    }

    /// Zbiór ID wszystkich wybranych przepisów (do szybkiego sprawdzania w UI)
    var selectedRecipeIDs: Set<UUID> {
        Set(recipesBySlot.values.flatMap { $0 }.map(\.id))
    }

    // MARK: - Actions

    func isSelected(_ recipe: Recipe) -> Bool {
        recipes(for: recipe).contains { $0.id == recipe.id }
    }

    func recipeCount(_ recipe: Recipe) -> Int {
        recipes(for: recipe).filter { $0.id == recipe.id }.count
    }

    func toggleRecipe(_ recipe: Recipe) {
        guard recipe.category.toMealSlot != nil else { return }

        if isSelected(recipe) {
            removeAllOfRecipe(recipe)
        } else {
            addRecipe(recipe)
        }
    }

    func incrementRecipe(_ recipe: Recipe) {
        addRecipe(recipe)
    }

    func decrementRecipe(_ recipe: Recipe) {
        removeOneOfRecipe(recipe)
    }

    func canAdd(to slot: MealSlot) -> Bool {
        count(for: slot) < Self.maxPerSlot
    }

    func count(for slot: MealSlot) -> Int {
        recipes(for: slot).count
    }

    func recipes(for slot: MealSlot) -> [Recipe] {
        recipesBySlot[slot] ?? []
    }

    /// Unikalne przepisy dla danego slotu (bez duplikatów)
    func uniqueRecipes(for slot: MealSlot) -> [Recipe] {
        var seen = Set<UUID>()
        return recipes(for: slot).filter { seen.insert($0.id).inserted }
    }

    func enterPlanningMode() {
        isActive = true
    }

    func loadFromSaved(_ plan: SavedMealPlan) {
        isActive = true
        recipesBySlot = Dictionary(
            uniqueKeysWithValues: MealSlot.allCases.map { slot in
                (slot, plan.entries(for: slot).map(\.recipe))
            }
        )
    }

    func exitPlanningMode() {
        isActive = false
        resetPlan()
    }

    func savePlan() {
        isActive = false
        resetPlan()
    }

    func resetPlan() {
        recipesBySlot = [:]
    }

    // MARK: - Private

    private func recipes(for recipe: Recipe) -> [Recipe] {
        guard let slot = recipe.category.toMealSlot else { return [] }
        return recipes(for: slot)
    }

    private func addRecipe(_ recipe: Recipe) {
        guard let slot = recipe.category.toMealSlot else { return }

        guard canAdd(to: slot) else {
            slotFullAlert = slot
            return
        }

        recipesBySlot[slot, default: []].append(recipe)
    }

    private func removeAllOfRecipe(_ recipe: Recipe) {
        guard let slot = recipe.category.toMealSlot else { return }
        recipesBySlot[slot]?.removeAll { $0.id == recipe.id }
    }

    private func removeOneOfRecipe(_ recipe: Recipe) {
        guard let slot = recipe.category.toMealSlot else { return }
        guard let index = recipesBySlot[slot]?.lastIndex(where: { $0.id == recipe.id }) else {
            return
        }
        recipesBySlot[slot]?.remove(at: index)
    }
}
