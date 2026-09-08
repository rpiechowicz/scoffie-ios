import SwiftUI

struct CalendarView: View {
    @Environment(\.mealCalendarStore) private var mealStore
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
            "\(MealCalendarStore.dateKey(for: date)).\(slot.rawValue).\(meal.id)"
        }
    }

    // MARK: - Derived

    /// Kalendarz is a personal day view: only what *you* eat. Someone else's
    /// variant of a slot is their business, and counting it here inflated the
    /// day's macros against a per-person goal.
    private func myMeals(for slot: MealSlot, on date: Date) -> [PlanMeal] {
        let all = mealStore.meals(for: date, slot: slot)
        guard let userId = sessionStore.currentUserId else { return all }
        return all.visibleTo(memberId: userId)
    }

    /// Sloty rysowane dla wybranego dnia: włączone przez gospodarstwo plus
    /// te, w których mimo wyłączenia coś stoi. Ta sama reguła co w Planie —
    /// wyłączenie posiłku ukrywa slot, ale nigdy nie ukrywa jedzenia.
    private func visibleSlots(on date: Date) -> [MealSlot] {
        sessionStore.mealSlots.visibleSlots(
            planned: mealStore.plan(for: date).plannedSlots
        )
    }

    private func dayMeals(on date: Date) -> [PlanMeal] {
        visibleSlots(on: date).flatMap { myMeals(for: $0, on: date) }
    }

    /// Posiłki dnia, który pokazuje PRZYPIĘTY nagłówek (oś, makra, licznik).
    /// Strona dnia rysuje z własnego argumentu — przez chwilę po machnięciu
    /// pokazuje jeszcze poprzedni dzień, a nagłówek już nowy.
    private var selectedDayMeals: [PlanMeal] {
        dayMeals(on: selectedDate)
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
        selectedDayMeals.filter { $0.isEaten(by: sessionStore.currentUserId) }
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
    private var dayPlannedKcal: Int { dayTotal(selectedDayMeals, \.kcal) }

    /// Odhaczać można dziś i wstecz. Dzień z przyszłości nie ma czego
    /// odhaczać, a przeszły jest zablokowany tylko do *planowania* — to, co
    /// już się wydarzyło, wolno zapisać.
    private func canLogEatenMeals(on date: Date) -> Bool {
        Calendar.current.startOfDay(for: date)
            <= Calendar.current.startOfDay(for: Date())
    }

    /// Pasek kroków: integracja „Zdrowie" włączona i dzień dzisiejszy lub
    /// przeszły — ta sama granica co przy odhaczaniu posiłków.
    private var stepsBarVisible: Bool {
        stepsEnabled && canLogEatenMeals(on: selectedDate)
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

    private func dayCards(on date: Date) -> [DayCard] {
        visibleSlots(on: date).flatMap { slot -> [DayCard] in
            let meals = myMeals(for: slot, on: date)
            guard !meals.isEmpty else { return [DayCard(slot: slot, meal: nil)] }
            return meals.map { DayCard(slot: slot, meal: $0) }
        }
    }

    // MARK: - Oś dnia

    /// Posiłek osi razem z tym, czego oś sama nie niesie: slotem i wpisem
    /// planu. Po stuknięciu w węzeł trzeba z niego wrócić do tego samego
    /// arkusza szczegółów, który otwiera kafel niżej.
    private typealias AxisEntry = (slot: MealSlot, meal: PlanMeal, minutes: Int)

    /// Posiłki wybranego dnia, KTÓRE MAJĄ GODZINĘ — tylko one trafiają na oś.
    ///
    /// Posiłek bez pory (domyślnie przekąska) zostaje na liście niżej.
    /// Makieta stawiała go kreskowanego w rynnie na końcu osi, ale rynna to
    /// osobna zasada do nauczenia się, a doba i tak nie wie, gdzie go
    /// postawić — zgadywanie za użytkownika byłoby gorsze od pominięcia.
    private var axisEntries: [AxisEntry] {
        dayCards(on: selectedDate).compactMap { card -> AxisEntry? in
            guard let meal = card.meal,
                  let minutes = sessionStore.mealSlotSchedule.minutes(for: card.slot)
            else { return nil }
            return (card.slot, meal, minutes)
        }
    }

    private var axisNodes: [CalendarDayAxis.Node] {
        axisEntries.map { entry in
            CalendarDayAxis.Node(
                id: "\(entry.slot.rawValue).\(entry.meal.id)",
                slot: entry.slot,
                minutes: entry.minutes,
                kcal: perPersonKcal(entry.meal),
                isEaten: entry.meal.isEaten(by: sessionStore.currentUserId),
                title: entry.meal.recipe.name,
                imageURL: entry.meal.recipe.imageURL
            )
        }
    }

    /// Dzień z przeszłości — cała trasa na osi jest już przebyta.
    private var isPastDay: Bool {
        Calendar.current.startOfDay(for: selectedDate)
            < Calendar.current.startOfDay(for: Date())
    }

    /// Udział jednej osoby w kaloriach posiłku — ta sama liczba, którą kafel
    /// pokazuje w wierszu meta i którą sumuje blok makro.
    private func perPersonKcal(_ meal: PlanMeal) -> Int {
        Int(
            meal.nutritionPerPerson(knownHouseholdMemberCount: knownHouseholdMemberCount)
                .kcal
                .rounded()
        )
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
                SCPageBackground(scheme: scheme)
                    .ignoresSafeArea()

                // Nagłówek dnia stoi, przewijają się wyłącznie kafle
                // posiłków. Wcześniej cała strona była jednym `ScrollView`
                // i przy dłuższym dniu pasek dni, makro i kroki wyjeżdżały
                // za górną krawędź — czyli to, po czym się nawiguje, znikało
                // dokładnie wtedy, gdy było potrzebne.
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        // Kalendarz nie ma tytułu — pasek dni sam mówi, co
                        // to za ekran. Układ ignoruje górny safe area
                        // (rozciąga się pod pasek nawigacji), więc pełne
                        // 78pt idzie tu jako jawny padding, tak jak tytuł na
                        // pozostałych zakładkach.
                        EditorialWeekBar(
                            datesViewModel: datesViewModel,
                            selectedDate: $selectedDate,
                            plannedDates: plannedDates
                        )
                        .padding(.horizontal, SCPageMetrics.horizontal)
                        .padding(.top, SCPageMetrics.top)

                        // Oś dnia siedzi MIĘDZY paskiem dni a kreską, tak jak
                        // w makiecie D6 — i jest przypięta razem z nimi.
                        // „Gdzie w dobie jestem" to pytanie zadawane przez cały
                        // czas oglądania listy, nie tylko na jej górze, więc oś
                        // nie może odjechać z pierwszym przewinięciem.
                        if !axisNodes.isEmpty {
                            CalendarDayAxis(
                                nodes: axisNodes,
                                isToday: Calendar.current.isDateInToday(selectedDate),
                                isPast: isPastDay,
                                onTap: { openAxisNode($0) }
                            )
                            .padding(.horizontal, SCPageMetrics.horizontal)
                            .padding(.top, 14)
                        }

                        // Kreska pod paskiem dni — `margin: 14px … 18px`
                        // z projektu. Z osią nad sobą odstęp schodzi do 12,
                        // bo oś kończy się własnym wierszem godzin.
                        Rectangle()
                            .fill(Color.scRule(scheme))
                            .frame(height: 1)
                            .padding(.horizontal, SCPageMetrics.horizontal)
                            .padding(.top, axisNodes.isEmpty ? 14 : 12)
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
                        .padding(.horizontal, SCPageMetrics.horizontal)
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
                            .padding(.horizontal, SCPageMetrics.horizontal)
                            .padding(.bottom, 22)
                        }

                        // Nagłówek dnia w miejscu dawnej kreski „W MENU".
                        // Kreska mówiła tylko „niżej są posiłki", co widać
                        // i bez niej; ten wiersz mówi, KTÓRY to dzień i ile
                        // z niego zostało do zjedzenia.
                        CalendarDayHeader(
                            date: selectedDate,
                            isToday: Calendar.current.isDateInToday(selectedDate),
                            eaten: eatenMeals.count,
                            total: selectedDayMeals.count
                        )
                        .padding(.horizontal, SCPageMetrics.horizontal)
                        .padding(.bottom, 14)

                        if let errorMessage = mealStore.errorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, SCPageMetrics.horizontal)
                                .padding(.bottom, 12)
                        }
                    }
                    // Dzień, w którym żaden posiłek nie ma godziny, nie ma osi
                    // — a bez tego lista podskakiwałaby o jej wysokość
                    // dokładnie w chwili, gdy wjeżdża nowy dzień.
                    .animation(DayNavigationMotion.spring, value: axisNodes.isEmpty)

                    // Posiłki — kompaktowe wiersze, `gap: 10`. Jedyna
                    // przewijana część ekranu; ruch palcem w bok przestawia
                    // dzień, tak samo jak w Planie tygodnia.
                    DayPager(
                        datesViewModel: datesViewModel,
                        selectedDate: $selectedDate,
                        // Stuknięcie w pasek dni i strzałki tygodnia jadą tak
                        // samo jak machnięcie palcem. Warunek jest jeden:
                        // strona MUSI rysować dzień z argumentu, bo na czas
                        // zjazdu pager pokazuje jeszcze poprzedni dzień.
                        animatesSelectionChanges: true
                    ) { date in
                        dayPage(for: date)
                    }
                }
                // Układ wchodzi pod pasek nawigacji, żeby siadał w miejscu
                // z projektu (~78pt od góry ekranu) zamiast być zepchniętym
                // o jego ~44pt. Przezroczysty pasek nadal stoi na wierzchu.
                .ignoresSafeArea(.container, edges: .top)
            }
            // Pasek nawigacji zostaje na miejscu, ale pusty i przezroczysty:
            // nagłówek ekranu jest przypięty, więc nie ma czego pod niego
            // wsunąć i materiał `.bar` już się nie zapala. Pusty element
            // trzyma pasek przed zwinięciem.
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
                await mealStore.loadWeekPlanFromBackend(
                    weekStart: datesViewModel.weekStartISO,
                    dates: datesViewModel.dates
                )
            }
            // Kroki dnia spoza kroczącego okna (przeglądanie przeszłości) —
            // leniwy, czysto lokalny odczyt z HealthKit, bez wysyłki.
            .task(id: MealCalendarStore.dateKey(for: selectedDate)) {
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

    /// Posiłki jednego dnia — kompaktowe wiersze, `gap: 10`. Jedyna
    /// przewijana część ekranu; ruch palcem w bok przestawia dzień, tak samo
    /// jak w Planie tygodnia.
    ///
    /// Wszystko liczy się tu z `date`, a nie z `selectedDate`: `DayPager`
    /// trzyma starą stronę na ekranie przez czas zjazdu, więc strona czytająca
    /// stan ekranu podmieniałaby treść w połowie animacji — na oczach
    /// użytkownika, zanim jeszcze zjechała.
    private func dayPage(for date: Date) -> some View {
        let canLog = canLogEatenMeals(on: date)

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(dayCards(on: date)) { card in
                EditorialMealCard(
                    slot: card.slot,
                    meal: card.meal,
                    isFavourite: card.meal.map { isFavourite($0.recipe) } ?? false,
                    isEaten: card.meal?.isEaten(by: sessionStore.currentUserId) ?? false,
                    showsEatenToggle: canLog,
                    onTap: { if let meal = card.meal { handleAssignedTap(meal, slot: card.slot, on: date) } },
                    onToggleFavorite: { if let meal = card.meal { toggleFavorite(meal.recipe) } },
                    onToggleEaten: { if let meal = card.meal { toggleEaten(meal, slot: card.slot, on: date) } }
                )
            }
        }
        .padding(.horizontal, SCPageMetrics.horizontal)
        // Świeża tożsamość na każdy dzień: bez niej kafle próbowałyby
        // przeprowadzić śniadanie poniedziałku w śniadanie wtorku dokładnie
        // wtedy, gdy `DayPager` przesuwa całą stronę — dwie animacje na
        // jednym ruchu. Ta sama reguła co na osi Planu tygodnia.
        .id(MealCalendarStore.dateKey(for: date))
    }

    // MARK: - Actions

    /// Stuknięcie w węzeł osi otwiera to samo, co stuknięcie w kafel niżej —
    /// szczegóły posiłku. Oś nie jest osobnym trybem, tylko drugim widokiem
    /// tej samej listy, więc nie może odpowiadać na dotyk czymś innym.
    private func openAxisNode(_ node: CalendarDayAxis.Node) {
        guard let entry = axisEntries.first(where: {
            "\($0.slot.rawValue).\($0.meal.id)" == node.id
        }) else { return }

        handleAssignedTap(entry.meal, slot: entry.slot, on: selectedDate)
    }

    private func handleAssignedTap(_ meal: PlanMeal, slot: MealSlot, on date: Date) {
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

    private func toggleEaten(_ meal: PlanMeal, slot: MealSlot, on date: Date) {
        let isEaten = meal.isEaten(by: sessionStore.currentUserId)
        Task { @MainActor in
            await mealStore.setMealEaten(
                !isEaten,
                recipeId: meal.recipe.id,
                for: date,
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
