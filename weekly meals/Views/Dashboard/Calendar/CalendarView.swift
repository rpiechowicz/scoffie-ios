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

    @State private var detailRecipe: Recipe?
    @State private var pickerTarget: PickerTarget?

    /// Day + slot the recipe picker is filling.
    private struct PickerTarget: Identifiable {
        let date: Date
        let slot: MealSlot
        var id: String { "\(WeeklyMealStore.dateKey(for: date)).\(slot.rawValue)" }
    }

    // MARK: - Derived

    private var isDayEditable: Bool {
        datesViewModel.isEditable(datesViewModel.selectedDate)
    }

    private var dayRecipes: [Recipe] {
        mealStore.plan(for: datesViewModel.selectedDate).allRecipes
    }

    private var dayKcal:    Int { dayRecipes.reduce(0) { $0 + Int($1.nutritionPerServing.kcal) } }
    private var dayProtein: Int { dayRecipes.reduce(0) { $0 + Int($1.nutritionPerServing.protein) } }
    private var dayFat:     Int { dayRecipes.reduce(0) { $0 + Int($1.nutritionPerServing.fat) } }
    private var dayCarbs:   Int { dayRecipes.reduce(0) { $0 + Int($1.nutritionPerServing.carbs) } }

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
        MealSlot.allCases.flatMap { slot -> [DayCard] in
            let meals = mealStore.meals(for: datesViewModel.selectedDate, slot: slot)
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
                    @Bindable var bindableDates = datesViewModel
                    VStack(alignment: .leading, spacing: 0) {
                        // Week bar — design spec puts it at ~78pt from screen
                        // top. The ScrollView ignores top safe area below
                        // (extends from screen top through the nav-bar zone),
                        // so we use the full 78pt as explicit padding here.
                        EditorialWeekBar(
                            datesViewModel: bindableDates,
                            plannedDates: plannedDates
                        )
                        .padding(.horizontal, 22)
                        .padding(.top, 78)

                        // Rule below week bar — `margin: '14px 22px 18px'`.
                        Rectangle()
                            .fill(Color.wmRule(scheme))
                            .frame(height: 1)
                            .padding(.horizontal, 22)
                            .padding(.top, 14)
                            .padding(.bottom, 18)

                        // Hero — `padding: '0 22px 18px'`.
                        EditorialDayHero(date: datesViewModel.selectedDate)
                            .padding(.horizontal, 22)
                            .padding(.bottom, 18)

                        // Macros — `padding: '0 22px 22px'`.
                        EditorialMacroBlock(
                            kcal: dayKcal,
                            protein: dayProtein,
                            fat: dayFat,
                            carbs: dayCarbs,
                            target: calorieGoal
                        )
                        .padding(.horizontal, 22)
                        .padding(.bottom, 22)

                        // "W MENU" rule — `margin: '0 22px 18px'`.
                        menuRule
                            .padding(.horizontal, 22)
                            .padding(.bottom, 18)

                        if let errorMessage = mealStore.errorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 22)
                                .padding(.bottom, 12)
                        }

                        // Meals — `padding: '0 22px 0', gap: 16`. Outer scroll has `paddingBottom: 40`.
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(dayCards.enumerated()), id: \.element.id) { idx, card in
                                EditorialMealCard(
                                    slot: card.slot,
                                    number: idx + 1,
                                    meal: card.meal,
                                    members: sessionStore.householdMembers,
                                    isFavourite: card.meal.map { isFavourite($0.recipe) } ?? false,
                                    isEditable: isDayEditable,
                                    onTap: { if let meal = card.meal { handleAssignedTap(meal.recipe) } },
                                    onAssign: {
                                        pickerTarget = PickerTarget(
                                            date: datesViewModel.selectedDate,
                                            slot: card.slot
                                        )
                                    },
                                    onToggleFavorite: { if let meal = card.meal { toggleFavorite(meal.recipe) } }
                                )
                            }
                        }
                        .padding(.horizontal, 22)
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
            .task(id: datesViewModel.weekStartISO) {
                await mealStore.loadSavedPlanFromBackend(weekStart: datesViewModel.weekStartISO)
                await mealStore.loadWeekPlanFromBackend(
                    weekStart: datesViewModel.weekStartISO,
                    dates: datesViewModel.dates
                )
            }
            // Same picker Plan uses: pick a recipe, it lands on this day and
            // slot. The old `DayAssignerSheet` distributed a week-long *pool*
            // that Plan v2 no longer fills, so it could only ever report an
            // exhausted pool.
            .sheet(item: $pickerTarget) { target in
                PlanSlotPickerSheet(
                    date: target.date,
                    slot: target.slot,
                    weekStartISO: datesViewModel.weekStartISO,
                    members: sessionStore.householdMembers,
                    editing: nil
                )
            }
            .onChange(of: pickerTarget?.id) { oldValue, newValue in
                guard oldValue != nil, newValue == nil else { return }
                Task { @MainActor in
                    await shoppingListStore.load(
                        weekStart: datesViewModel.weekStartISO,
                        force: true
                    )
                }
            }
            .sheet(item: $detailRecipe) { selected in
                RecipeDetailView(
                    recipe: selected,
                    onToggleFavorite: {
                        Task { @MainActor in
                            await recipeCatalogStore.toggleFavorite(recipeId: selected.id)
                            detailRecipe = await recipeCatalogStore.loadRecipeDetail(recipeId: selected.id)
                                ?? recipeCatalogStore.recipes.first(where: { $0.id == selected.id })
                                ?? selected
                        }
                    },
                    onClose: { detailRecipe = nil }
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

    private func handleAssignedTap(_ recipe: Recipe) {
        Task { @MainActor in
            detailRecipe = await recipeCatalogStore.loadRecipeDetail(recipeId: recipe.id) ?? recipe
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
