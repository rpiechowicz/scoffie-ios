import SwiftUI

struct CalendarView: View {
    @Environment(\.weeklyMealStore) private var mealStore
    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.shoppingListStore) private var shoppingListStore
    @Environment(\.colorScheme) private var scheme

    // Mirrors the AppStorage row owned by Settings → Dieta i alergeny. The
    // value is synced to the backend by SessionStore so it stays in sync
    // across devices, and surfaced here as the kcal target on the macros
    // block (so the day's "X / GOAL" reading reflects the user's choice).
    @AppStorage("settings.diet.calorieGoal") private var calorieGoal: Int = 2000

    // Flaga i cel kroków przez @AppStorage, nie przez computed property na
    // store — tylko @AppStorage gwarantuje re-render, gdy arkusz „Zdrowie"
    // zmieni wartość (store trzyma je w UserDefaults poza swoim stanem
    // @Observable).
    @AppStorage(HealthStepsStore.Keys.enabled) private var stepsEnabled: Bool = false
    @AppStorage(HealthStepsStore.Keys.stepsGoal) private var stepsGoal: Int = HealthStepsStore.defaultStepsGoal

    @State private var detailTarget: DetailTarget?

    /// Dzień oglądany w Kalendarzu. Własny stan zakładki — Plan ma swój,
    /// wspólny zostaje tylko tydzień.
    @State private var selectedDate: Date = Date()

    /// Posiłek otwarty w szczegółach, razem ze slotem, z którego przyszedł.
    ///
    /// Szczegół pozwala teraz przestawić liczbę porcji, a zapis musi trafić
    /// w ten konkretny wpis planu — sam `Recipe` nie mówi, o który slot chodzi.
    private struct DetailTarget: Identifiable {
        let date: Date
        let slot: MealSlot
        let meal: PlanMeal
        /// Przepis z pełnymi szczegółami; `meal.recipe` bywa wersją skróconą.
        var recipe: Recipe

        var id: String {
            "\(WeeklyMealStore.dateKey(for: date)).\(slot.rawValue).\(meal.id)"
        }
    }

    // MARK: - Derived

    /// Kalendarz is a personal day view: only what *you* eat. Someone else's
    /// variant of a slot is their business, and counting it here inflated the
    /// day's macros against a per-person goal.
    private func myMeals(for slot: MealSlot) -> [PlanMeal] {
        let all = mealStore.meals(for: selectedDate, slot: slot)
        guard let userId = sessionStore.currentUserId else { return all }
        return all.visibleTo(memberId: userId)
    }

    /// Sloty rysowane dla wybranego dnia: włączone przez gospodarstwo plus
    /// te, w których mimo wyłączenia coś stoi. Ta sama reguła co w Planie —
    /// wyłączenie posiłku ukrywa slot, ale nigdy nie ukrywa jedzenia.
    private var visibleSlots: [MealSlot] {
        sessionStore.mealSlots.visibleSlots(
            planned: mealStore.plan(for: selectedDate).plannedSlots
        )
    }

    private var dayMeals: [PlanMeal] {
        visibleSlots.flatMap { myMeals(for: $0) }
    }

    /// Ilu domowników dzieli się porcjami, albo `nil`, dopóki `SessionStore`
    /// nie dowiezie listy.
    ///
    /// Pusta lista przed wczytaniem to brak odpowiedzi, a nie dom
    /// jednoosobowy — podstawiona tu jedynka dzieliłaby zapisane porcje przez
    /// jedną osobę i licznik kalorii pokazywałby przez pierwszą sekundę
    /// wielokrotność prawdziwej wartości.
    private var knownHouseholdMemberCount: Int? {
        guard sessionStore.didLoadHouseholdMembers else { return nil }
        return max(1, sessionStore.householdMembers.count)
    }

    /// Posiłki faktycznie odhaczone przez zalogowanego użytkownika. To one —
    /// a nie sam plan — zasilają licznik kalorii i makra: zaplanowany obiad
    /// nie jest dowodem, że ktokolwiek go zjadł.
    private var eatenMeals: [PlanMeal] {
        dayMeals.filter { $0.isEaten(by: sessionStore.currentUserId) }
    }

    /// Suma jednego makra po posiłkach, licząca udział jednej osoby.
    ///
    /// Sumujemy w `Double` i zaokrąglamy dopiero na końcu, bo obcinanie każdego
    /// posiłku z osobna gubiło do jednej kcal na pozycję i błąd kumulował się
    /// przez cały dzień. Przy porcjach jest to jeszcze ważniejsze: udział na
    /// osobę bywa ułamkowy (trzy porcje na dwie osoby to 1,5), więc część
    /// ułamkowa przestaje być zaokrągleniem gramatury, a staje się realną
    /// wartością, której nie wolno wyrzucić przy każdym składniku sumy.
    private func dayTotal(
        _ meals: [PlanMeal],
        _ macro: KeyPath<Nutrition, Double>
    ) -> Int {
        let sum = meals.reduce(0.0) { partial, meal in
            partial + meal.nutritionPerPerson(
                knownHouseholdMemberCount: knownHouseholdMemberCount
            )[keyPath: macro]
        }
        return Int(sum.rounded())
    }

    private var dayKcal:    Int { dayTotal(eatenMeals, \.kcal) }
    private var dayProtein: Int { dayTotal(eatenMeals, \.protein) }
    private var dayFat:     Int { dayTotal(eatenMeals, \.fat) }
    private var dayCarbs:   Int { dayTotal(eatenMeals, \.carbs) }

    /// Suma całego dnia — zjedzone i jeszcze nie. Rysuje widmo na pasku makro.
    private var dayPlannedKcal: Int { dayTotal(dayMeals, \.kcal) }

    /// Odhaczać można dziś i wstecz. Dzień z przyszłości nie ma czego
    /// odhaczać, a przeszły jest zablokowany tylko do *planowania* — to, co
    /// już się wydarzyło, wolno zapisać.
    private var canLogEatenMeals: Bool {
        Calendar.current.startOfDay(for: selectedDate)
            <= Calendar.current.startOfDay(for: Date())
    }

    /// Pasek kroków: integracja „Zdrowie" włączona i dzień dzisiejszy lub
    /// przeszły — ta sama granica co przy odhaczaniu posiłków.
    private var stepsBarVisible: Bool {
        stepsEnabled && canLogEatenMeals
    }

    /// Set of "yyyy-MM-dd" keys for visible days that already have ≥1 meal — drives the sage planned-dot.
    private var plannedDates: Set<String> {
        var set = Set<String>()
        for date in datesViewModel.dates {
            let plan = mealStore.plan(for: date)
            if !plan.allRecipes.isEmpty {
                set.insert(plan.dateKey)
            }
        }
        return set
    }

    /// One card per planned variant, plus an empty card for untouched slots.
    /// A household that splits a meal gets both variants stacked.
    private struct DayCard: Identifiable {
        let slot: MealSlot
        let meal: PlanMeal?
        var id: String {
            meal.map { "\(slot.rawValue).\($0.id)" } ?? "\(slot.rawValue).empty"
        }
    }

    private var dayCards: [DayCard] {
        visibleSlots.flatMap { slot -> [DayCard] in
            let meals = myMeals(for: slot)
            guard !meals.isEmpty else { return [DayCard(slot: slot, meal: nil)] }
            return meals.map { DayCard(slot: slot, meal: $0) }
        }
    }

    /// Live `favourite` flag from the recipe catalog. The meal store snapshots
    /// `Recipe.favourite` at plan-save time and never resyncs, so we look up
    /// the current state by recipe id and fall back to the snapshot.
    private func isFavourite(_ recipe: Recipe) -> Bool {
        if let live = recipeCatalogStore.recipes.first(where: { $0.id == recipe.id }) {
            return live.favourite
        }
        return recipe.favourite
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                WMPageBackground(scheme: scheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Kalendarz nie ma tytułu — pasek dni sam mówi, co
                        // to za ekran. ScrollView ignoruje górny safe area
                        // (rozciąga się pod pasek nawigacji), więc pełne
                        // 78pt idzie tu jako jawny padding, tak jak tytuł na
                        // pozostałych zakładkach.
                        EditorialWeekBar(
                            datesViewModel: datesViewModel,
                            selectedDate: $selectedDate,
                            plannedDates: plannedDates
                        )
                        .padding(.horizontal, WMPageMetrics.horizontal)
                        .padding(.top, WMPageMetrics.top)

                        // Kreska pod paskiem dni — `margin: 14px … 18px` z projektu.
                        Rectangle()
                            .fill(Color.wmRule(scheme))
                            .frame(height: 1)
                            .padding(.horizontal, WMPageMetrics.horizontal)
                            .padding(.top, 14)
                            .padding(.bottom, 18)

                        // Makro — dolny odstęp 22pt z projektu.
                        EditorialMacroBlock(
                            kcal: dayKcal,
                            plannedKcal: dayPlannedKcal,
                            protein: dayProtein,
                            fat: dayFat,
                            carbs: dayCarbs,
                            target: calorieGoal
                        )
                        .padding(.horizontal, WMPageMetrics.horizontal)
                        .padding(.bottom, stepsBarVisible ? 16 : 22)

                        // Kroki zHealthKit — tylko gdy integracja „Zdrowie"
                        // włączona i dzień nie jest z przyszłości (przyszłość
                        // nie ma czego pokazać, nawet zera).
                        if stepsBarVisible {
                            let day = sessionStore.healthStepsStore?
                                .steps(for: selectedDate)
                            EditorialStepsBar(
                                steps: day?.steps,
                                goal: stepsGoal,
                                source: day?.source
                            )
                            .padding(.horizontal, WMPageMetrics.horizontal)
                            .padding(.bottom, 22)
                        }

                        // Kreska "W MENU" — dolny odstęp 18pt z projektu.
                        menuRule
                            .padding(.horizontal, WMPageMetrics.horizontal)
                            .padding(.bottom, 18)

                        if let errorMessage = mealStore.errorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, WMPageMetrics.horizontal)
                                .padding(.bottom, 12)
                        }

                        // Posiłki — kompaktowe wiersze, `gap: 10`, dolny
                        // odstęp scrolla 40pt.
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(dayCards) { card in
                                EditorialMealCard(
                                    slot: card.slot,
                                    meal: card.meal,
                                    isFavourite: card.meal.map { isFavourite($0.recipe) } ?? false,
                                    isEaten: card.meal?.isEaten(by: sessionStore.currentUserId) ?? false,
                                    showsEatenToggle: canLogEatenMeals,
                                    onTap: { if let meal = card.meal { handleAssignedTap(meal, slot: card.slot) } },
                                    onToggleFavorite: { if let meal = card.meal { toggleFavorite(meal.recipe) } },
                                    onToggleEaten: { if let meal = card.meal { toggleEaten(meal, slot: card.slot) } }
                                )
                            }
                        }
                        .padding(.horizontal, WMPageMetrics.horizontal)
                        .padding(.bottom, 40)
                    }
                }
                .scrollIndicators(.hidden)
                // Extend the scroll view up under the nav-bar zone so the
                // editorial layout sits at design-spec position (~78pt from
                // screen top) instead of being pushed down by the nav bar's
                // ~44pt height. The transparent nav bar still sits on top
                // and keeps SwiftUI's native blur-on-scroll behavior live.
                .ignoresSafeArea(.container, edges: .top)
            }
            // Native Recipes-style auto-blur: the nav bar stays present but
            // empty + transparent at rest. SwiftUI fades in its `.bar`
            // material the moment content scrolls under the status bar.
            // The placeholder ToolbarItem keeps the bar from collapsing.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            // The empty nav-bar layer would otherwise intercept taps in the
            // ~44pt zone above the week bar, blocking the day chips. We let
            // SwiftUI keep rendering the bar (so the auto-blur still runs),
            // but disable its UIKit hit testing so touches fall through to
            // the scroll content underneath. There are no real toolbar
            // items, so nothing legitimate is lost.
            .background(NavBarHitTestPassthrough())
            .onAppear {
                selectedDate = datesViewModel.dayWithinVisibleWeek(selectedDate)
            }
            .onChange(of: datesViewModel.weekStartISO) { _, _ in
                selectedDate = datesViewModel.selectedDate
            }
            .onChange(of: selectedDate) { _, newValue in
                datesViewModel.selectDate(newValue)
            }
            .task(id: datesViewModel.weekStartISO) {
                await mealStore.loadSavedPlanFromBackend(weekStart: datesViewModel.weekStartISO)
                await mealStore.loadWeekPlanFromBackend(
                    weekStart: datesViewModel.weekStartISO,
                    dates: datesViewModel.dates
                )
            }
            // Kroki dnia spoza kroczącego okna (przeglądanie przeszłości) —
            // leniwy, czysto lokalny odczyt z HealthKit, bez wysyłki.
            .task(id: WeeklyMealStore.dateKey(for: selectedDate)) {
                await sessionStore.healthStepsStore?
                    .refreshIfNeeded(for: selectedDate)
            }
            // Kalendarz nie planuje — picker zniknął stąd celowo. Dwie drogi
            // dodawania posiłków (Plan i Kalendarz) robiły to samo w dwóch
            // miejscach i myliły się nawzajem; układanie tygodnia ma teraz
            // jedno miejsce, a Kalendarz odpowiada na „co jem i czy zjadłem".
            .sheet(item: $detailTarget) { target in
                RecipeDetailView(
                    recipe: target.recipe,
                    onToggleFavorite: {
                        Task { @MainActor in
                            await recipeCatalogStore.toggleFavorite(recipeId: target.recipe.id)
                            let refreshed = await recipeCatalogStore.loadRecipeDetail(recipeId: target.recipe.id)
                                ?? recipeCatalogStore.recipes.first(where: { $0.id == target.recipe.id })
                                ?? target.recipe
                            // Podmieniamy sam przepis, nie cały cel — `id`
                            // zostaje ten sam, więc arkusz się nie przeładowuje
                            // i porcje wybrane stepperem przeżywają serduszko.
                            detailTarget?.recipe = refreshed
                        }
                    },
                    onClose: { detailTarget = nil },
                    // Stepper startuje od liczby, którą pokazuje reszta ekranu.
                    // Posiłek bez zapisanej wartości podstawia tu regułę auto,
                    // bo zero i jedynka nie są tym samym co „nie ustawiono".
                    // Nieznana liczba domowników nie może zamienić się w
                    // jedynkę — wtedy stepper startuje od tego, na ile porcji
                    // napisany jest sam przepis, a nie od liczby, której nikt
                    // nie wybierał.
                    initialServings: target.meal.effectiveServings(
                        knownHouseholdMemberCount: knownHouseholdMemberCount
                    ) ?? target.recipe.servings,
                    context: .planned(day: target.date, slot: target.slot),
                    onSaveServings: { newValue in
                        saveServings(newValue, for: target)
                    }
                )
                .presentationDetents([.large])
                .dashboardLiquidSheet()
            }
        }
    }

    // MARK: - Pieces

    private var menuRule: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.wmRule(scheme))
                .frame(height: 1)
                .frame(maxWidth: .infinity)

            Text("W MENU")
                .font(.system(size: 9, weight: .bold))
                .tracking(2)
                .foregroundStyle(Color.wmMuted(scheme))

            Rectangle()
                .fill(Color.wmRule(scheme))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Actions

    private func handleAssignedTap(_ meal: PlanMeal, slot: MealSlot) {
        let date = selectedDate
        Task { @MainActor in
            let full = await recipeCatalogStore.loadRecipeDetail(recipeId: meal.recipe.id) ?? meal.recipe
            detailTarget = DetailTarget(date: date, slot: slot, meal: meal, recipe: full)
        }
    }

    /// Zapisuje liczbę porcji zmienioną stepperem w szczegółach.
    ///
    /// Audytorium zostaje nietknięte — zmieniamy ile gotujemy, a nie dla kogo.
    /// `plannedServings` idzie jawnie, więc serwer nie nadpisze go regułą auto.
    private func saveServings(_ servings: Int, for target: DetailTarget) {
        Task { @MainActor in
            _ = await mealStore.upsertWeekSlot(
                recipe: target.meal.recipe,
                participantIds: target.meal.participantIds,
                plannedServings: servings,
                householdMemberCount: knownHouseholdMemberCount,
                for: target.date,
                slot: target.slot,
                weekStart: datesViewModel.weekStartISO
            )
            detailTarget = nil
            await shoppingListStore.load(
                weekStart: datesViewModel.weekStartISO,
                force: true
            )
        }
    }

    private func toggleEaten(_ meal: PlanMeal, slot: MealSlot) {
        let isEaten = meal.isEaten(by: sessionStore.currentUserId)
        Task { @MainActor in
            await mealStore.setMealEaten(
                !isEaten,
                recipeId: meal.recipe.id,
                for: selectedDate,
                slot: slot,
                weekStart: datesViewModel.weekStartISO
            )
        }
    }

    private func toggleFavorite(_ recipe: Recipe) {
        Task { @MainActor in
            await recipeCatalogStore.toggleFavorite(recipeId: recipe.id)
        }
    }
}

#Preview {
    CalendarView()
}

// MARK: - Nav bar hit-test pass-through
//
// SwiftUI's `NavigationStack` keeps the toolbar layer "live" so the auto-blur
// material can fade in on scroll, but that layer also captures touches across
// its full ~44pt height — even when the toolbar is visually empty. That
// blocks the week-bar chips from receiving taps once the layout extends
// under it via `.ignoresSafeArea(.container, edges: .top)`.
//
// We don't have any real toolbar items here (just an invisible 1×1 placeholder
// used to keep the bar from collapsing). Disabling user interaction on the
// underlying `UINavigationBar` lets touches fall through to the SwiftUI
// content below while leaving the auto-blur rendering intact.
private struct NavBarHitTestPassthrough: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        BarUnlocker()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class BarUnlocker: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Defer one runloop tick so the navigation controller is wired up.
            DispatchQueue.main.async { [weak self] in
                self?.findNavigationBar()?.isUserInteractionEnabled = false
            }
        }

        private func findNavigationBar() -> UINavigationBar? {
            var responder: UIResponder? = self
            while let r = responder {
                if let vc = r as? UIViewController,
                   let bar = vc.navigationController?.navigationBar {
                    return bar
                }
                responder = r.next
            }
            return nil
        }
    }
}
