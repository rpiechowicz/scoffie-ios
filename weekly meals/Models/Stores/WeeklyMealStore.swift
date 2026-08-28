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
    /// Odracza pokazanie błędów łączności z odczytu tygodnia — patrz
    /// komentarz w `ConnectivityErrorGate`. Błędy mutacji planu pokazują
    /// się bez zmian, od razu.
    private let connectivityErrorGate = ConnectivityErrorGate()
    var errorMessage: String?

    var hasSavedPlan: Bool { !savedPlan.isEmpty }

    // MARK: - Date formatting

    /// Klucz dnia liczony przez `PlanWeek` — ten sam kalendarz i strefa, co
    /// `weekStart`, żeby dzień nie „przeskakiwał" przy innym kalendarzu
    /// systemowym niż gregoriański.
    static func dateKey(for date: Date) -> String {
        PlanWeek.dateKey(date)
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
        connectivityErrorGate.reset()
        do {
            let slots = try await weeklyPlanRepository.fetchWeekPlan(weekStart: weekStart)
            // Porcje znane sprzed odświeżenia, po `PlanItem.id`. Odczyt tygodnia
            // odtwarza plan od zera, więc bez tej mapy pozycja, przy której
            // serwer nie podał `plannedServings`, traciła zapisaną liczbę —
            // i wracała do reguły auto, czyli do jedynki w domu, którego
            // składu aplikacja akurat nie zna. Serwerowe `nil` znaczy „nie
            // wiem", a na „nie wiem" nie kasuje się tego, co się wie.
            let knownServingsByItemId = Dictionary(
                plans.values
                    .flatMap(\.allMeals)
                    .compactMap { meal in meal.plannedServings.map { (meal.id, $0) } },
                uniquingKeysWith: { first, _ in first }
            )
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
                        eatenByUserIds: slot.eatenByUserIds,
                        plannedServings: slot.plannedServings ?? knownServingsByItemId[slot.itemId]
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
            // Błąd łączności z odświeżenia pokazuje się dopiero, gdy się
            // utrzyma — reconnect po powrocie z tła gasił go po ~0,3 s
            // i banner tylko migał.
            connectivityErrorGate.publish(error) { [weak self] message in
                self?.errorMessage = message
            }
        }
    }

    /// Adds a recipe to a slot, or rewrites who an already-planned recipe is
    /// for. `participantIds` empty means the whole household eats it.
    ///
    /// `replacingRecipeId` drops another variant in the same call — that is how
    /// „Zmień przepis" swaps one meal for another without briefly showing both.
    ///
    /// `plannedServings == nil` znaczy „niech serwer policzy porcje z
    /// audytorium" — domyślna wartość jest tu po to, żeby wywołania sprzed
    /// steppera dalej trafiały w tę regułę zamiast wymuszać jedną porcję.
    ///
    /// `householdMemberCount` jest po to, żeby optymistyczny wpis powtórzył
    /// regułę serwera dla „Wspólne" — inaczej siada na dysk i miga złą liczbą,
    /// zanim tydzień się odświeży. `nil` znaczy „lista domowników jeszcze nie
    /// dojechała": wtedy NIE zgadujemy. Zgadywanie w tym miejscu dawało
    /// `max(1, 0)`, czyli jedną porcję, i ta jedynka utrwalała się w pliku
    /// planu. Lepiej zostawić „nie wiem" i podmienić je na prawdę z
    /// potwierdzenia zapisu.
    @MainActor
    func upsertWeekSlot(
        recipe: Recipe,
        participantIds: [String] = [],
        plannedServings: Int? = nil,
        householdMemberCount: Int?,
        replacingRecipeId: UUID? = nil,
        for date: Date,
        slot: MealSlot,
        weekStart: String
    ) async -> Bool {
        let previous = meals(for: date, slot: slot)

        // Optymistyczny wpis musi mieć konkretną liczbę porcji już teraz, więc
        // powtarzamy tu regułę serwera co do joty: liczba uczestników, a dla
        // „Wspólne" liczba domowników. Wcześniej stała tu jedynka i to ona
        // trafiała do `meal_plans.json` — wspólna kolacja w dwuosobowym domu
        // utrwalała się jako jedna porcja i nikt jej już potem nie poprawiał.
        let optimisticServings = plannedServings
            ?? (participantIds.isEmpty ? householdMemberCount.map { max(1, $0) } : participantIds.count)

        var optimistic = previous.filter { $0.recipe.id != replacingRecipeId }
        if let index = optimistic.firstIndex(where: { $0.recipe.id == recipe.id }) {
            optimistic[index].participantIds = participantIds
            optimistic[index].plannedServings = optimisticServings
        } else {
            optimistic.append(
                PlanMeal(
                    recipe: recipe,
                    participantIds: participantIds,
                    plannedServings: optimisticServings
                )
            )
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
            let saved = try await weeklyPlanRepository.upsertWeekSlot(
                weekStart: weekStart,
                date: date,
                mealSlot: slot,
                recipeId: recipe.id,
                participantIds: participantIds,
                plannedServings: plannedServings
            )
            // Wpis optymistyczny miał syntetyczne `id` i zgadywane porcje.
            // Podmieniamy go na to, co naprawdę leży w bazie — dzięki temu
            // późniejsze odświeżenie tygodnia trafia na ten sam `PlanItem.id`
            // i nie ma czego „poprawiać". Bez tego kroku pozycja żyła pod
            // losowym identyfikatorem aż do pełnego refetchu.
            if let saved, saved.mealSlot == slot {
                var confirmed = meals(for: date, slot: slot)
                if let index = confirmed.firstIndex(where: { $0.recipe.id == recipe.id }) {
                    confirmed[index] = PlanMeal(
                        id: saved.itemId,
                        recipe: confirmed[index].recipe,
                        participantIds: saved.participantIds,
                        eatenByUserIds: saved.eatenByUserIds,
                        // `nil` z serwera znaczy „nie znam tego pola" (starszy
                        // backend), więc zostawiamy własną wartość zamiast
                        // zerować ją do reguły auto.
                        plannedServings: saved.plannedServings ?? confirmed[index].plannedServings
                    )
                    setMeals(confirmed, for: date, slot: slot)
                }
            }
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

    /// - Parameter householdMemberCount: potrzebne tylko po to, żeby
    ///   optymistyczny wpis policzył porcje tą samą regułą co serwer. Wpisy
    ///   z zapisanego planu są zawsze „Wspólne", więc liczba porcji to liczba
    ///   domowników — a jedynka na sztywno połowiłaby im listę zakupów.
    ///   `nil` = jeszcze nie wiadomo, ilu ich jest; wtedy porcje wylicza serwer.
    @MainActor
    func applySavedPlanToWeek(
        weekStart: String,
        dates: [Date],
        plan: SavedMealPlan,
        householdMemberCount: Int?
    ) async {
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
                        householdMemberCount: householdMemberCount,
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

        // Pętla po wszystkich slotach, nie po trzech wypisanych z nazwy —
        // sloty puste są bezkosztowe, a wyliczanka gubiłaby każdy nowy posiłek.
        for slot in MealSlot.allCases {
            await applySlot(slot, entries: plan.entries(for: slot))
        }

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
        connectivityErrorGate.reset()
        do {
            let dto = try await weeklyPlanRepository.fetchSavedPlan(weekStart: weekStart)
            let mapped = mapSavedPlan(dto: dto)
            savedPlan = mapped
            syncSavedPlanSelectionFlagsWithCalendar()
            errorMessage = nil
        } catch {
            // Jak w `loadWeekPlanFromBackend` — chwilowy błąd łączności nie
            // ma migać bannerem, skoro reconnect zaraz go naprawi.
            connectivityErrorGate.publish(error) { [weak self] message in
                self?.errorMessage = message
            }
        }
    }

    @MainActor
    func saveMealPlanToBackend(_ plan: SavedMealPlan, weekStart: String) async {
        saveMealPlan(plan)
        guard let weeklyPlanRepository else { return }

        do {
            let recipeIdsByMealType = Dictionary(
                uniqueKeysWithValues: MealSlot.allCases.map { slot in
                    (
                        slot.backendMealType,
                        plan.entries(for: slot).map { $0.recipe.id.uuidString }
                    )
                }
            )
            let dto = try await weeklyPlanRepository.saveSavedPlan(
                weekStart: weekStart,
                recipeIdsByMealType: recipeIdsByMealType
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
                householdId: event.householdId,
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
                householdId: event.householdId,
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
        func expand(slot: MealSlot) -> [PlanEntry] {
            dto.items
                .filter { $0.mealType.uppercased() == slot.backendMealType }
                .flatMap { item -> [PlanEntry] in
                    guard let recipe = item.recipe.toAppRecipe(), item.quantity > 0 else { return [] }
                    return Array(repeating: PlanEntry(recipe: recipe), count: item.quantity)
                }
        }

        return SavedMealPlan(
            entriesBySlot: Dictionary(
                uniqueKeysWithValues: MealSlot.allCases.map { ($0, expand(slot: $0)) }
            )
        )
    }

    /// Ile razy dany przepis stoi w kalendarzu, slot po slocie.
    private func calendarUsageCounts() -> [MealSlot: [UUID: Int]] {
        var counts: [MealSlot: [UUID: Int]] = [:]
        for dayPlan in plans.values {
            for slot in MealSlot.allCases {
                for meal in dayPlan.meals(for: slot) {
                    counts[slot, default: [:]][meal.recipe.id, default: 0] += 1
                }
            }
        }
        return counts
    }

    private func syncSavedPlanSelectionFlagsWithCalendar() {
        let used = calendarUsageCounts()
        for slot in MealSlot.allCases {
            savedPlan.updateEntries(for: slot) { entries in
                syncEntries(&entries, usedCounts: used[slot] ?? [:])
            }
        }
        saveSavedPlan()
    }

    /// Czyści z kalendarza przepisy, których nie ma w nowym planie
    /// i synchronizuje flagi isSelected z aktualnym stanem kalendarza
    func cleanupCalendarAndSync(with newPlan: SavedMealPlan) {
        let allowedIdsBySlot: [MealSlot: Set<UUID>] = Dictionary(
            uniqueKeysWithValues: MealSlot.allCases.map { slot in
                (slot, Set(newPlan.entries(for: slot).map(\.recipe.id)))
            }
        )

        // 1. Usuń z kalendarza przepisy spoza nowego planu
        var changed = false
        for (key, var dayPlan) in plans {
            var dayChanged = false

            for slot in MealSlot.allCases {
                let current = dayPlan.meals(for: slot)
                guard !current.isEmpty else { continue }
                let allowed = allowedIdsBySlot[slot] ?? []
                let kept = current.filter { allowed.contains($0.recipe.id) }
                if kept.count != current.count {
                    dayPlan.setMeals(kept, for: slot)
                    dayChanged = true
                }
            }

            if dayChanged {
                plans[key] = dayPlan
                changed = true
            }
        }
        if changed { save() }

        // 2. + 3. Policz użycie w kalendarzu i ustaw na jego podstawie isSelected
        let used = calendarUsageCounts()
        for slot in MealSlot.allCases {
            savedPlan.updateEntries(for: slot) { entries in
                syncEntries(&entries, usedCounts: used[slot] ?? [:])
            }
        }

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
        savedPlan.updateEntries(for: slot, mutation)
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
