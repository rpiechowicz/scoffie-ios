import Foundation

/// Tryb Gotuj na poziomie sesji: start i powrót do gotowania (pełny ekran nad
/// pulpitem), „Zjedzone” w planie i scenariusze pobierane z wyprzedzeniem.
extension SessionStore {
    /// Start nowej sesji. Najpierw zjeżdżają arkusze (szczegóły przepisu) —
    /// pełnego ekranu nie da się pokazać nad kontrolerem, który już coś
    /// przedstawia (ta sama droga co przepis z linku).
    @MainActor
    func startCooking(recipe: Recipe, package: CookPackage, portions: Int, slot: MealSlot?, planDate: Date?) async {
        guard let cookSessionStore else { return }
        await sessionCurtain.dismissPresentedScreensAnimated()
        cookSessionStore.start(recipe: recipe, package: package, portions: portions, mealSlot: slot, planDate: planDate)
    }

    /// „Gotuj dalej” / „Wróć do gotowania” — wstrzymana sesja wraca na ekran.
    @MainActor
    func resumeCooking() async {
        guard let cookSessionStore, cookSessionStore.session != nil else { return }
        await sessionCurtain.dismissPresentedScreensAnimated()
        cookSessionStore.resume()
    }

    /// Stuknięcie w Live Activity przyszło przed końcem startu — teraz, nad
    /// gotowym pulpitem, wraca tryb Gotuj (chyba że już stoi, bo zadzwonił
    /// timer).
    @MainActor
    func resumeCookingIfRequested() async {
        guard cookingResumeRequested else { return }
        cookingResumeRequested = false
        guard let cookSessionStore, !cookSessionStore.isPresented else { return }
        await resumeCooking()
    }

    /// Timer zadzwonił, a tryb jest schowany („Wstrzymaj”, zimny start) —
    /// pokazujemy go z ekranem końca timera, jak alarm w Zegarze. Najpierw
    /// zjeżdżają arkusze pulpitu (pełnego ekranu nie da się pokazać nad
    /// otwartym arkuszem) i tylko nad gotowym pulpitem — nad loaderem startu
    /// czeka, aż `startupPhase` dojdzie do `.ready` (wtedy woła to start).
    @MainActor
    func presentCookingIfRinging() async {
        guard let cookSessionStore,
              let session = cookSessionStore.session,
              session.ringingTimer(now: Date()) != nil,
              !cookSessionStore.isPresented,
              startupPhase == .ready else { return }
        await sessionCurtain.dismissPresentedScreensAnimated()
        cookSessionStore.resume()
    }

    /// „Zjedzone” na zakończeniu: danie z planu odhacza się na swój dzień
    /// i porę. Gotowanie spoza planu (D21: sam wpis do dzisiejszego planu)
    /// czeka na specyfikację po stronie backendu — na razie bez wpisu.
    @MainActor
    func markCookedAsEaten(_ session: CookSession) {
        guard let mealCalendarStore,
              let key = session.planDateKey,
              let date = PlanWeek.date(fromKey: key),
              let raw = session.mealSlotRaw,
              let slot = MealSlot(rawValue: raw) else { return }
        let weekStart = PlanWeek.dateKey(PlanWeek.monday(of: date))
        Task { @MainActor in
            await mealCalendarStore.setMealEaten(true, recipeId: session.recipeId, for: date, slot: slot, weekStart: weekStart)
            rescheduleMealReminders()
        }
    }

    /// Scenariusze dań dziś i jutro z planu — Gotuj ma być gotowe przed
    /// wejściem i działać w kuchni bez sieci (§7.7). Przepis z planu bywa
    /// kopią bez `cookScenarioVersion`, więc wersję bierzemy z katalogu.
    @MainActor
    func prefetchCookScenarios() async {
        guard let cookScenarioStore, let mealCalendarStore, let recipeCatalogStore else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dates = [today, calendar.date(byAdding: .day, value: 1, to: today) ?? today]
        let catalog = Dictionary(recipeCatalogStore.recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recipes = mealCalendarStore.allRecipes(for: dates).map { catalog[$0.id] ?? $0 }
        await cookScenarioStore.prefetch(recipes)
    }
}
