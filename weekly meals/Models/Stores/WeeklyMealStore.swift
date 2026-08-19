import Foundation
import Observation

/// In-memory + persisted store for the weekly calendar (per-day breakfast/lunch/dinner)
/// and the "saved plan" pool that Calendar/WeeklyPlan views draw from.
///
/// Companion types live alongside this file:
///   - `SavedMealPlan` (DayMealPlan / PlanEntry / SavedMealPlan structs) — `Models/Plans/SavedMealPlan.swift`
///   - Environment keys / defaults — `Models/Environment/StoreEnvironmentKeys.swift`
///   - Recipe data layer (protocols, DTOs, socket clients) — `Networking/Recipes/*`
@Observable
class WeeklyMealStore {

    // MARK: - Storage

    private(set) var plans: [String: DayMealPlan] = [:]
    private(set) var savedPlan: SavedMealPlan = SavedMealPlan()
    private let weeklyPlanRepository: WeeklyPlanRepository?
    private let currentUserId: String?
    private var observedWeekStart: String?
    private var observedWeekDates: [Date] = []
    private var observedSavedPlanWeekStart: String?
    private var lastWeekChangeVersionByWeek: [String: Int64] = [:]
    private var lastSavedPlanChangeVersionByWeek: [String: Int64] = [:]
    private var pendingWeekReloadTask: Task<Void, Never>?
    private var pendingSavedPlanReloadTask: Task<Void, Never>?
    var errorMessage: String?

    var hasSavedPlan: Bool { !savedPlan.isEmpty }

    // MARK: - Date formatting

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func dateKey(for date: Date) -> String {
        dateFormatter.string(from: date)
    }

    // MARK: - Init

    init(weeklyPlanRepository: WeeklyPlanRepository? = nil, currentUserId: String? = nil) {
        self.weeklyPlanRepository = weeklyPlanRepository
        self.currentUserId = currentUserId
        self.weeklyPlanRepository?.observeWeekPlanChanges { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                await self.handleRemoteWeekPlanChanged(event: event)
            }
        }
        self.weeklyPlanRepository?.observeSavedPlanChanges { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                await self.handleRemoteSavedPlanChanged(event: event)
            }
        }
        self.weeklyPlanRepository?.observeRealtimeReconnect { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.scheduleRefreshForObservedState()
            }
        }
        load()
        loadSavedPlan()
    }

    // MARK: - Read API

    func plan(for date: Date) -> DayMealPlan {
        let key = Self.dateKey(for: date)
        return plans[key] ?? DayMealPlan(dateKey: key)
    }

    func recipe(for date: Date, slot: MealSlot) -> Recipe? {
        plan(for: date).recipe(for: slot)
    }

    /// Every variant planned into that slot — one per household split.
    func meals(for date: Date, slot: MealSlot) -> [PlanMeal] {
        plan(for: date).meals(for: slot)
    }

    func allRecipes(for dates: [Date]) -> [Recipe] {
        dates.flatMap { plan(for: $0).allRecipes }
    }

    // MARK: - Write API

    func setRecipe(_ recipe: Recipe?, for date: Date, slot: MealSlot) {
        let key = Self.dateKey(for: date)
        var dayPlan = plans[key] ?? DayMealPlan(dateKey: key)
        dayPlan.setRecipe(recipe, for: slot)
        plans[key] = dayPlan
        save()
    }

    func setMeals(_ meals: [PlanMeal], for date: Date, slot: MealSlot) {
        let key = Self.dateKey(for: date)
        var dayPlan = plans[key] ?? DayMealPlan(dateKey: key)
        dayPlan.setMeals(meals, for: slot)
        plans[key] = dayPlan
        save()
    }

    func clearRecipe(for date: Date, slot: MealSlot) {
        setRecipe(nil, for: date, slot: slot)
    }

    func clearWeek(dates: [Date]) {
        for date in dates {
            let key = Self.dateKey(for: date)
            plans.removeValue(forKey: key)
        }
        save()
    }

    @MainActor
    func loadWeekPlanFromBackend(weekStart: String, dates: [Date]) async {
        guard let weeklyPlanRepository else { return }
        observedWeekStart = weekStart
        observedWeekDates = dates
        do {
            let slots = try await weeklyPlanRepository.fetchWeekPlan(weekStart: weekStart)
            clearWeek(dates: dates)
            for slot in slots {
                let key = slot.dateKey
                var dayPlan = plans[key] ?? DayMealPlan(dateKey: key)
                // A slot can carry several variants, so accumulate rather than
                // overwrite — the backend returns one row per split.
                var meals = dayPlan.meals(for: slot.mealSlot)
                meals.append(
                    PlanMeal(
                        id: slot.itemId,
                        recipe: slot.recipe,
                        participantIds: slot.participantIds,
                        eatenByUserIds: slot.eatenByUserIds
                    )
                )
                dayPlan.setMeals(meals, for: slot.mealSlot)
                plans[key] = dayPlan
            }
            save()
            // Recompute availability flags based on the freshly loaded calendar state.
            // Without this, another device can keep stale "selected" entries and show 0/x as blocked.
            syncSavedPlanSelectionFlagsWithCalendar()
            errorMessage = nil
        } catch {
            errorMessage = UserFacingErrorMapper.message(from: error)
        }
    }

    /// Adds a recipe to a slot, or rewrites who an already-planned recipe is
    /// for. `participantIds` empty means the whole household eats it.
    ///
    /// `replacingRecipeId` drops another variant in the same call — that is how
    /// „Zmień przepis" swaps one meal for another without briefly showing both.
    @MainActor
    func upsertWeekSlot(
        recipe: Recipe,
        participantIds: [String] = [],
        replacingRecipeId: UUID? = nil,
        for date: Date,
        slot: MealSlot,
        weekStart: String
    ) async -> Bool {
        let previous = meals(for: date, slot: slot)

        var optimistic = previous.filter { $0.recipe.id != replacingRecipeId }
        if let index = optimistic.firstIndex(where: { $0.recipe.id == recipe.id }) {
            optimistic[index].participantIds = participantIds
        } else {
            optimistic.append(PlanMeal(recipe: recipe, participantIds: participantIds))
        }
        setMeals(optimistic, for: date, slot: slot)

        guard let weeklyPlanRepository else { return true }

        do {
            if let replacingRecipeId, replacingRecipeId != recipe.id {
                try await weeklyPlanRepository.removeWeekSlot(
                    weekStart: weekStart,
                    date: date,
                    mealSlot: slot,
                    recipeId: replacingRecipeId
                )
            }
            try await weeklyPlanRepository.upsertWeekSlot(
                weekStart: weekStart,
                date: date,
                mealSlot: slot,
                recipeId: recipe.id,
                participantIds: participantIds
            )
            errorMessage = nil
            return true
        } catch {
            setMeals(previous, for: date, slot: slot)
            errorMessage = UserFacingErrorMapper.message(from: error)
            return false
        }
    }

    /// Removes one variant from a slot, or the whole slot when `recipe` is nil.
    @MainActor
    func removeWeekSlot(
        for date: Date,
        slot: MealSlot,
        weekStart: String,
        recipe: Recipe? = nil
    ) async -> Bool {
        let previous = meals(for: date, slot: slot)
        let remaining = recipe.map { target in
            previous.filter { $0.recipe.id != target.id }
        } ?? []
        setMeals(remaining, for: date, slot: slot)

        guard let weeklyPlanRepository else { return true }

        do {
            try await weeklyPlanRepository.removeWeekSlot(
                weekStart: weekStart,
                date: date,
                mealSlot: slot,
                recipeId: recipe?.id
            )
            errorMessage = nil
            return true
        } catch {
            setMeals(previous, for: date, slot: slot)
            errorMessage = UserFacingErrorMapper.message(from: error)
            return false
        }
    }

    /// Marks a planned meal as eaten by the signed-in user, or clears the mark.
    ///
    /// Optimistic like the other writes here: the tick flips immediately and
    /// rolls back if the server refuses. Without a signed-in user there is
    /// nobody to attribute the mark to, so the call is a no-op rather than a
    /// silent local-only edit that would vanish on the next week refresh.
    @MainActor
    @discardableResult
    func setMealEaten(
        _ isEaten: Bool,
        recipeId: UUID,
        for date: Date,
        slot: MealSlot,
        weekStart: String
    ) async -> Bool {
        guard let currentUserId else { return false }

        let previous = meals(for: date, slot: slot)
        guard previous.contains(where: { $0.recipe.id == recipeId }) else { return false }

        var optimistic = previous
        for index in optimistic.indices where optimistic[index].recipe.id == recipeId {
            var marks = Set(optimistic[index].eatenByUserIds)
            if isEaten {
                marks.insert(currentUserId)
            } else {
                marks.remove(currentUserId)
            }
            optimistic[index].eatenByUserIds = Array(marks).sorted()
        }
        setMeals(optimistic, for: date, slot: slot)

        guard let weeklyPlanRepository else { return true }

        do {
            try await weeklyPlanRepository.setMealEaten(
                weekStart: weekStart,
                date: date,
                mealSlot: slot,
                recipeId: recipeId,
                isEaten: isEaten
            )
            errorMessage = nil
            return true
        } catch {
            setMeals(previous, for: date, slot: slot)
            errorMessage = UserFacingErrorMapper.message(from: error)
            return false
        }
    }

    @MainActor
    func clearWeekFromBackend(weekStart: String, dates: [Date]) async {
        guard let weeklyPlanRepository else {
            clearWeek(dates: dates)
            return
        }

        do {
            try await weeklyPlanRepository.clearWeekPlan(weekStart: weekStart)
            clearWeek(dates: dates)
            savedPlan = SavedMealPlan()
            saveSavedPlan()
            errorMessage = nil
        } catch {
            errorMessage = UserFacingErrorMapper.message(from: error)
        }
    }

    @MainActor
    func applySavedPlanToWeek(weekStart: String, dates: [Date], plan: SavedMealPlan) async {
        guard !dates.isEmpty else { return }

        // Upewnij się, że lokalny cache odzwierciedla backend przed nadpisaniem tygodnia.
        await loadWeekPlanFromBackend(weekStart: weekStart, dates: dates)

        var hadError = false

        func applySlot(_ slot: MealSlot, entries: [PlanEntry]) async {
            let recipes = entries.map(\.recipe)

            for (index, date) in dates.enumerated() {
                if index < recipes.count {
                    let targetRecipe = recipes[index]
                    if recipe(for: date, slot: slot)?.id == targetRecipe.id {
                        continue
                    }
                    let success = await upsertWeekSlot(
                        recipe: targetRecipe,
                        for: date,
                        slot: slot,
                        weekStart: weekStart
                    )
                    if !success { hadError = true }
                } else if recipe(for: date, slot: slot) != nil {
                    let success = await removeWeekSlot(
                        for: date,
                        slot: slot,
                        weekStart: weekStart
                    )
                    if !success { hadError = true }
                }
            }
        }

        await applySlot(.breakfast, entries: plan.breakfastEntries)
        await applySlot(.lunch, entries: plan.lunchEntries)
        await applySlot(.dinner, entries: plan.dinnerEntries)

        cleanupCalendarAndSync(with: plan)

        if !hadError {
            errorMessage = nil
        }
    }

    // MARK: - Saved Plan API

    func saveMealPlan(_ plan: SavedMealPlan) {
        savedPlan = plan
        saveSavedPlan()
    }

    func clearSavedPlan() {
        savedPlan = SavedMealPlan()
        saveSavedPlan()
    }

    @MainActor
    func loadSavedPlanFromBackend(weekStart: String) async {
        guard let weeklyPlanRepository else { return }
        observedSavedPlanWeekStart = weekStart
        do {
            let dto = try await weeklyPlanRepository.fetchSavedPlan(weekStart: weekStart)
            let mapped = mapSavedPlan(dto: dto)
            savedPlan = mapped
            syncSavedPlanSelectionFlagsWithCalendar()
            errorMessage = nil
        } catch {
            errorMessage = UserFacingErrorMapper.message(from: error)
        }
    }

    @MainActor
    func saveMealPlanToBackend(_ plan: SavedMealPlan, weekStart: String) async {
        saveMealPlan(plan)
        guard let weeklyPlanRepository else { return }

        do {
            let breakfast = plan.breakfastEntries.map { $0.recipe.id.uuidString }
            let lunch = plan.lunchEntries.map { $0.recipe.id.uuidString }
            let dinner = plan.dinnerEntries.map { $0.recipe.id.uuidString }
            let dto = try await weeklyPlanRepository.saveSavedPlan(
                weekStart: weekStart,
                breakfastRecipeIds: breakfast,
                lunchRecipeIds: lunch,
                dinnerRecipeIds: dinner
            )
            let mapped = mapSavedPlan(dto: dto)
            savedPlan = mapped
            cleanupCalendarAndSync(with: mapped)
            errorMessage = nil
        } catch {
            errorMessage = UserFacingErrorMapper.message(from: error)
        }
    }

    @MainActor
    func clearSavedPlanFromBackend(weekStart: String) async {
        await saveMealPlanToBackend(SavedMealPlan(), weekStart: weekStart)
    }

    /// Resetuje lokalny cache planów i zapisany plan.
    /// Używane przy zmianie kontekstu gospodarstwa, aby nie przenosić starych danych.
    func resetLocalPlanningState() {
        plans = [:]
        savedPlan = SavedMealPlan()
        observedWeekStart = nil
        observedWeekDates = []
        observedSavedPlanWeekStart = nil
        lastWeekChangeVersionByWeek = [:]
        lastSavedPlanChangeVersionByWeek = [:]
        pendingWeekReloadTask?.cancel()
        pendingSavedPlanReloadTask?.cancel()
        pendingWeekReloadTask = nil
        pendingSavedPlanReloadTask = nil
        save()
        saveSavedPlan()
    }

    func refreshObservedState() {
        scheduleRefreshForObservedState()
    }

    @MainActor
    private func handleRemoteWeekPlanChanged(event: BackendWeekChangedDTO) async {
        let changedByOtherUser = event.changedByUserId != nil && event.changedByUserId != currentUserId
        guard event.weekStart == observedWeekStart else { return }
        guard !observedWeekDates.isEmpty else { return }
        if let changeVersion = event.changeVersion {
            let previous = lastWeekChangeVersionByWeek[event.weekStart] ?? 0
            guard changeVersion > previous else { return }
            lastWeekChangeVersionByWeek[event.weekStart] = changeVersion
        }
        scheduleWeekReload(weekStart: event.weekStart, dates: observedWeekDates)
        if changedByOtherUser {
            PlanChangeNotificationService.notifyRemotePlanChange(
                action: event.action,
                weekStart: event.weekStart,
                changedByDisplayName: event.changedByDisplayName,
                dayOfWeek: event.dayOfWeek,
                mealType: event.mealType
            )
        }
    }

    @MainActor
    private func handleRemoteSavedPlanChanged(event: BackendSavedPlanChangedDTO) async {
        let changedByOtherUser = event.changedByUserId != nil && event.changedByUserId != currentUserId
        guard event.weekStart == observedSavedPlanWeekStart else { return }
        if let changeVersion = event.changeVersion {
            let previous = lastSavedPlanChangeVersionByWeek[event.weekStart] ?? 0
            guard changeVersion > previous else { return }
            lastSavedPlanChangeVersionByWeek[event.weekStart] = changeVersion
        }
        scheduleSavedPlanReload(weekStart: event.weekStart)
        if changedByOtherUser {
            if event.action?.uppercased() == "CLEAR_PLAN" {
                return
            }
            PlanChangeNotificationService.notifyRemotePlanChange(
                action: event.action,
                weekStart: event.weekStart,
                changedByDisplayName: event.changedByDisplayName
            )
        }
    }

    private func scheduleWeekReload(weekStart: String, dates: [Date]) {
        pendingWeekReloadTask?.cancel()
        pendingWeekReloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self else { return }
            await self.loadWeekPlanFromBackend(weekStart: weekStart, dates: dates)
        }
    }

    private func scheduleSavedPlanReload(weekStart: String) {
        pendingSavedPlanReloadTask?.cancel()
        pendingSavedPlanReloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self else { return }
            await self.loadSavedPlanFromBackend(weekStart: weekStart)
        }
    }

    private func scheduleRefreshForObservedState() {
        if let observedWeekStart, !observedWeekDates.isEmpty {
            scheduleWeekReload(weekStart: observedWeekStart, dates: observedWeekDates)
        }
        if let observedSavedPlanWeekStart {
            scheduleSavedPlanReload(weekStart: observedSavedPlanWeekStart)
        }
    }

    private func mapSavedPlan(dto: BackendSharedMealPlanDTO) -> SavedMealPlan {
        func expand(mealType: String) -> [PlanEntry] {
            dto.items
                .filter { $0.mealType.uppercased() == mealType }
                .flatMap { item -> [PlanEntry] in
                    guard let recipe = item.recipe.toAppRecipe(), item.quantity > 0 else { return [] }
                    return Array(repeating: PlanEntry(recipe: recipe), count: item.quantity)
                }
        }

        return SavedMealPlan(
            breakfastEntries: expand(mealType: "BREAKFAST"),
            lunchEntries: expand(mealType: "LUNCH"),
            dinnerEntries: expand(mealType: "DINNER")
        )
    }

    private func syncSavedPlanSelectionFlagsWithCalendar() {
        var usedBreakfast: [UUID: Int] = [:]
        var usedLunch: [UUID: Int] = [:]
        var usedDinner: [UUID: Int] = [:]

        for dayPlan in plans.values {
            for meal in dayPlan.breakfast { usedBreakfast[meal.recipe.id, default: 0] += 1 }
            for meal in dayPlan.lunch { usedLunch[meal.recipe.id, default: 0] += 1 }
            for meal in dayPlan.dinner { usedDinner[meal.recipe.id, default: 0] += 1 }
        }

        syncEntries(&savedPlan.breakfastEntries, usedCounts: usedBreakfast)
        syncEntries(&savedPlan.lunchEntries, usedCounts: usedLunch)
        syncEntries(&savedPlan.dinnerEntries, usedCounts: usedDinner)
        saveSavedPlan()
    }

    /// Czyści z kalendarza przepisy, których nie ma w nowym planie
    /// i synchronizuje flagi isSelected z aktualnym stanem kalendarza
    func cleanupCalendarAndSync(with newPlan: SavedMealPlan) {
        let newBreakfastIDs = Set(newPlan.breakfastEntries.map(\.recipe.id))
        let newLunchIDs = Set(newPlan.lunchEntries.map(\.recipe.id))
        let newDinnerIDs = Set(newPlan.dinnerEntries.map(\.recipe.id))

        // 1. Usuń z kalendarza przepisy spoza nowego planu
        var changed = false
        for (key, var dayPlan) in plans {
            var dayChanged = false

            let keptBreakfast = dayPlan.breakfast.filter { newBreakfastIDs.contains($0.recipe.id) }
            if keptBreakfast.count != dayPlan.breakfast.count {
                dayPlan.breakfast = keptBreakfast
                dayChanged = true
            }
            let keptLunch = dayPlan.lunch.filter { newLunchIDs.contains($0.recipe.id) }
            if keptLunch.count != dayPlan.lunch.count {
                dayPlan.lunch = keptLunch
                dayChanged = true
            }
            let keptDinner = dayPlan.dinner.filter { newDinnerIDs.contains($0.recipe.id) }
            if keptDinner.count != dayPlan.dinner.count {
                dayPlan.dinner = keptDinner
                dayChanged = true
            }

            if dayChanged {
                plans[key] = dayPlan
                changed = true
            }
        }
        if changed { save() }

        // 2. Policz ile razy każdy przepis jest użyty w kalendarzu per slot
        var usedBreakfast: [UUID: Int] = [:]
        var usedLunch: [UUID: Int] = [:]
        var usedDinner: [UUID: Int] = [:]

        for dayPlan in plans.values {
            for meal in dayPlan.breakfast { usedBreakfast[meal.recipe.id, default: 0] += 1 }
            for meal in dayPlan.lunch { usedLunch[meal.recipe.id, default: 0] += 1 }
            for meal in dayPlan.dinner { usedDinner[meal.recipe.id, default: 0] += 1 }
        }

        // 3. Ustaw isSelected na podstawie faktycznego użycia w kalendarzu
        syncEntries(&savedPlan.breakfastEntries, usedCounts: usedBreakfast)
        syncEntries(&savedPlan.lunchEntries, usedCounts: usedLunch)
        syncEntries(&savedPlan.dinnerEntries, usedCounts: usedDinner)

        saveSavedPlan()
    }

    /// Synchronizuje flagi isSelected — tyle wpisów ile jest w kalendarzu ustawia na true
    private func syncEntries(_ entries: inout [PlanEntry], usedCounts: [UUID: Int]) {
        // Najpierw ustaw wszystko na false
        for i in entries.indices { entries[i].isSelected = false }

        // Potem oznacz tyle ile jest w kalendarzu
        var remaining = usedCounts
        for i in entries.indices {
            let recipeId = entries[i].recipe.id
            if let count = remaining[recipeId], count > 0 {
                entries[i].isSelected = true
                remaining[recipeId] = count - 1
            }
        }
    }

    /// Oznacz jeden wpis jako wybrany (po dodaniu do kalendarza)
    func markAsSelected(_ recipe: Recipe, slot: MealSlot) {
        mutateEntries(for: slot) { entries in
            if let idx = entries.firstIndex(where: { !$0.isSelected && $0.recipe.id == recipe.id }) {
                entries[idx].isSelected = true
            }
        }
    }

    /// Oznacz jeden wpis jako dostępny (po usunięciu z kalendarza)
    func markAsAvailable(_ recipe: Recipe, slot: MealSlot) {
        mutateEntries(for: slot) { entries in
            if let idx = entries.firstIndex(where: { $0.isSelected && $0.recipe.id == recipe.id }) {
                entries[idx].isSelected = false
            }
        }
    }

    private func mutateEntries(for slot: MealSlot, _ mutation: (inout [PlanEntry]) -> Void) {
        switch slot {
        case .breakfast: mutation(&savedPlan.breakfastEntries)
        case .lunch:     mutation(&savedPlan.lunchEntries)
        case .dinner:    mutation(&savedPlan.dinnerEntries)
        }
        saveSavedPlan()
    }

    // MARK: - Persistence

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("meal_plans.json")
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(plans)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("WeeklyMealStore save error: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            plans = try JSONDecoder().decode([String: DayMealPlan].self, from: data)
        } catch {
            print("WeeklyMealStore load error: \(error)")
        }
    }

    // MARK: - Saved Plan Persistence

    private var savedPlanURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("saved_plan.json")
    }

    private func saveSavedPlan() {
        do {
            let data = try JSONEncoder().encode(savedPlan)
            try data.write(to: savedPlanURL, options: .atomic)
        } catch {
            print("WeeklyMealStore saveSavedPlan error: \(error)")
        }
    }

    private func loadSavedPlan() {
        guard let data = try? Data(contentsOf: savedPlanURL) else { return }
        do {
            savedPlan = try JSONDecoder().decode(SavedMealPlan.self, from: data)
        } catch {
            print("WeeklyMealStore loadSavedPlan error: \(error)")
        }
    }
}
