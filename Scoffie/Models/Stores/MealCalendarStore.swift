import Foundation
import Observation

/// In-memory + persisted store for the weekly calendar (per-day meals in
/// every enabled slot). Źródłem prawdy jest backendowy `PlanItem`; lokalny
/// plik `meal_plans.json` to cache dla szybkiego startu i pracy offline.
///
/// Companion types live alongside this file:
///   - `PlanMeal` / `DayMealPlan` — `Models/Plans/SavedMealPlan.swift`
///   - Environment keys / defaults — `Models/Environment/StoreEnvironmentKeys.swift`
///   - Recipe data layer (protocols, DTOs, socket clients) — `Networking/Recipes/*`
///
/// Dawna „pula tygodnia" (`SavedMealPlan`, `saved_plan.json`,
/// `weeklyPlans:getSavedPlan`) została wycofana: żaden widok jej nie czytał,
/// a każda zmiana tygodnia kosztowała dodatkowy round-trip po sockecie.
@Observable
class MealCalendarStore {

    // MARK: - Storage

    private(set) var plans: [String: DayMealPlan] = [:]
    private let weeklyPlanRepository: WeeklyPlanRepository?
    private let currentUserId: String?
    private var observedWeekStart: String?
    private var observedWeekDates: [Date] = []
    private var lastWeekChangeVersionByWeek: [String: Int64] = [:]
    private var pendingWeekReloadTask: Task<Void, Never>?
    /// Błędy łączności NIE trafiają tu wcale — `inlineMessage` oddaje na nie
    /// `nil` i melduje je w `ConnectivityMonitor`, który mówi o braku sieci
    /// raz, u góry ekranu, i dopiero gdy brak się utrzyma.
    var errorMessage: String?

    // MARK: - Date formatting

    /// Klucz dnia liczony przez `PlanWeek` — ten sam kalendarz i strefa, co
    /// `weekStart`, żeby dzień nie „przeskakiwał" przy innym kalendarzu
    /// systemowym niż gregoriański.
    static func dateKey(for date: Date) -> String {
        PlanWeek.dateKey(date)
    }

    // MARK: - Init

    /// Część nazwy pliku cache — `userId_householdId`. Bez tego plan
    /// poprzedniego konta wczytywał się następnej osobie na tym telefonie.
    private let cacheNamespace: String

    init(weeklyPlanRepository: WeeklyPlanRepository? = nil, currentUserId: String? = nil, cacheNamespace: String = "default") {
        self.cacheNamespace = Self.sanitizedCacheNamespace(cacheNamespace)
        self.weeklyPlanRepository = weeklyPlanRepository
        self.currentUserId = currentUserId
        self.weeklyPlanRepository?.observeWeekPlanChanges { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                await self.handleRemoteWeekPlanChanged(event: event)
            }
        }
        self.weeklyPlanRepository?.observeRealtimeReconnect { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.scheduleRefreshForObservedState()
            }
        }
        load()
        Self.deleteLegacySavedPlanFile()
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
            errorMessage = nil
        } catch {
            errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
        }
    }

    /// Adds a recipe to a slot, or rewrites who an already-planned recipe is
    /// for. `participantIds` empty means the whole household eats it.
    ///
    /// `replacingRecipeId` drops another variant in the same call — that is how
    /// „Zmień przepis" swaps one meal for another without briefly showing both.
    /// Serwer robi to w JEDNEJ transakcji (`replaceRecipeId` w payloadzie):
    /// nie ma już wstępnego `removeWeekSlot`, po którym slot stał pusty, drugi
    /// domownik dostawał dwa powiadomienia, a przerwany zapis zostawiał
    /// pustkę. Rollback poniżej przywraca STARE danie, bo serwer bez ACK-a nic
    /// nie zmienił.
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
            let saved = try await weeklyPlanRepository.upsertWeekSlot(
                weekStart: weekStart,
                date: date,
                mealSlot: slot,
                recipeId: recipe.id,
                participantIds: participantIds,
                plannedServings: plannedServings,
                replaceRecipeId: replacingRecipeId
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
            errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
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
            errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
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
            errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
            return false
        }
    }

    /// Oddaje, czy tydzień naprawdę zniknął.
    ///
    /// Wołający nie może tego wywnioskować z `errorMessage`: przy braku sieci
    /// mapper oddaje `nil`, więc puste pole znaczyłoby raz „udało się", a raz
    /// „nie mamy o czym mówić" — i potwierdzenie kłamałoby dokładnie wtedy,
    /// gdy sieci nie ma.
    @MainActor
    @discardableResult
    func clearWeekFromBackend(weekStart: String, dates: [Date]) async -> Bool {
        guard let weeklyPlanRepository else {
            clearWeek(dates: dates)
            return true
        }

        do {
            try await weeklyPlanRepository.clearWeekPlan(weekStart: weekStart)
            clearWeek(dates: dates)
            errorMessage = nil
            return true
        } catch {
            errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
            return false
        }
    }

    /// Resetuje lokalny cache planów.
    /// Używane przy zmianie kontekstu gospodarstwa, aby nie przenosić starych danych.
    func resetLocalPlanningState() {
        plans = [:]
        observedWeekStart = nil
        observedWeekDates = []
        lastWeekChangeVersionByWeek = [:]
        pendingWeekReloadTask?.cancel()
        pendingWeekReloadTask = nil
        save()
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

    private func scheduleWeekReload(weekStart: String, dates: [Date]) {
        pendingWeekReloadTask?.cancel()
        pendingWeekReloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self else { return }
            await self.loadWeekPlanFromBackend(weekStart: weekStart, dates: dates)
        }
    }

    private func scheduleRefreshForObservedState() {
        if let observedWeekStart, !observedWeekDates.isEmpty {
            scheduleWeekReload(weekStart: observedWeekStart, dates: observedWeekDates)
        }
    }

    // MARK: - Persistence

    private static let cacheFilePrefix = "meal_plans"

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(Self.cacheFilePrefix)_\(cacheNamespace).json")
    }

    private static func sanitizedCacheNamespace(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let value = String(cleaned)
        return value.isEmpty ? "default" : value
    }

    /// Wylogowanie, usunięcie konta, zmiana domu: plik planu (także stary,
    /// wspólny `meal_plans.json`) nie może przeżyć sesji.
    static func clearCache() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(cacheFilePrefix) && name.hasSuffix(".json") {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(plans)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            debugLog("MealCalendarStore save error: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            plans = try JSONDecoder().decode([String: DayMealPlan].self, from: data)
        } catch {
            debugLog("MealCalendarStore load error: \(error)")
        }
    }

    // MARK: - Legacy cleanup

    /// `saved_plan.json` trzymał wycofaną pulę tygodniową. Plik nie ma już
    /// czytelnika, więc kasujemy go raz, przy pierwszym starcie po
    /// aktualizacji — inaczej zostałby na dysku każdego użytkownika na zawsze.
    /// Błąd „nie ma pliku" jest normalnym przypadkiem i jest ignorowany, więc
    /// nie potrzeba flagi „czy już sprzątnięte".
    private static func deleteLegacySavedPlanFile() {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("saved_plan.json")
        try? FileManager.default.removeItem(at: url)
    }
}
