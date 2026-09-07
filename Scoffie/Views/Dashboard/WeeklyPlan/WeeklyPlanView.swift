import SwiftUI

// Plan tygodnia — v2 "Cozy Kitchen".
// Source of truth: claude.ai design canvas → `PlanA2FullWidth`
// (components/plan-a2-fix.jsx), sections "Plan tygodnia · Etap 1" and
// "Etap 2 — sekcja „Każdy je inaczej”".
//
// Layout: title + overflow menu + profile chip and a day strip — wszystko
// przypięte do góry — a pod nimi jedyna przewijana część ekranu: strona
// jednego dnia ze wszystkimi slotami i sekcją „Każdy je inaczej". Ruch palcem
// w bok przestawia dzień (`DayPager`), tak samo jak w Kalendarzu.
//
// Household splits: every meal carries the members it is for (empty = shared).
// The profile chip switches the whole screen between the household lens and a
// single person's.
//
// Sloty posiłków: dzień rysuje tyle wierszy, ile gospodarstwo ma włączonych
// w Ustawieniach → „Posiłki w planie", plus te, w których mimo wyłączenia coś
// stoi (`visibleSlots(on:)`). Kolejność zawsze porą dnia.
struct WeeklyPlanView: View {
    @Environment(\.mealCalendarStore) private var mealStore
    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.shoppingListStore) private var shoppingListStore
    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.colorScheme) private var scheme

    /// Dzień planowany w tej zakładce. Własny stan Planu — Kalendarz ma swój,
    /// wspólny zostaje tylko tydzień.
    @State private var selectedDate: Date = Date()
    @State private var profile: PlanProfile = .household
    @State private var showProfileSheet = false
    @State private var pickerTarget: PickerTarget?
    @State private var detailTarget: DetailTarget?
    @State private var showClearDayAlert = false
    @State private var showClearWeekAlert = false
    @State private var showProducts = false

    /// Posiłek otwarty w szczegółach, razem z miejscem, z którego przyszedł.
    ///
    /// Sam `Recipe` tu nie wystarczy: ekran szczegółu pozwala teraz zmienić
    /// liczbę porcji, a zapis musi trafić w ten konkretny wpis planu — czyli
    /// potrzebuje dnia, slotu i dotychczasowego audytorium.
    private struct DetailTarget: Identifiable {
        let date: Date
        let slot: MealSlot
        let meal: PlanMeal
        /// Przepis dociągnięty z pełnymi szczegółami; `meal.recipe` bywa
        /// skróconą wersją z listy planu.
        var recipe: Recipe

        var id: String {
            "\(MealCalendarStore.dateKey(for: date)).\(slot.rawValue).\(meal.id)"
        }
    }

    private struct PickerTarget: Identifiable {
        let date: Date
        let slot: MealSlot
        /// Set when the sheet edits an existing variant rather than adding one.
        let editing: PlanMeal?

        var id: String {
            let base = "\(MealCalendarStore.dateKey(for: date)).\(slot.rawValue)"
            return editing.map { "\(base).\($0.id)" } ?? base
        }
    }

    // MARK: - Derived

    private var members: [HouseholdMemberSnapshot] {
        sessionStore.householdMembers
    }

    /// Ilu domowników dzieli się porcjami, albo `nil`, dopóki `SessionStore`
    /// nie dowiezie listy. Pusta lista przed wczytaniem to brak odpowiedzi,
    /// a nie dom jednoosobowy — i to właśnie ta różnica decyduje, czy stepper
    /// porcji pokaże zapisaną liczbę, czy fałszywą jedynkę.
    private var knownHouseholdMemberCount: Int? {
        guard sessionStore.didLoadHouseholdMembers else { return nil }
        return max(1, members.count)
    }

    /// "yyyy-MM-dd" keys for days that already hold a meal — drives the sage
    /// dot under the day strip.
    private var plannedDates: Set<String> {
        var set = Set<String>()
        for date in datesViewModel.dates {
            let plan = mealStore.plan(for: date)
            if !plan.allMeals.isEmpty { set.insert(plan.dateKey) }
        }
        return set
    }

    private func hasMeals(on date: Date) -> Bool {
        !mealStore.plan(for: date).allMeals.isEmpty
    }

    /// Meals for a slot, narrowed to the active profile.
    ///
    /// A personal dish beats the slot's shared one: if Ania has her own lunch,
    /// her lens shows that, not the shared lunch as well. Without this rule a
    /// person's day double-counted every slot they had a variant in.
    private func visibleMeals(date: Date, slot: MealSlot) -> [PlanMeal] {
        let all = mealStore.meals(for: date, slot: slot)
        guard let memberId = profile.memberId else { return all }
        return all.visibleTo(memberId: memberId)
    }

    /// Sloty do narysowania dla jednego dnia.
    ///
    /// Do włączonych w ustawieniach dokładamy te, w których tego dnia coś
    /// stoi. Bez tego wyłączenie podwieczorku sprzątałoby z ekranu posiłki,
    /// które nadal są w bazie i nadal liczą się do listy zakupów — czyli
    /// aplikacja pokazywałaby plan inny niż ten, według którego się kupuje.
    private func visibleSlots(on date: Date) -> [MealSlot] {
        sessionStore.mealSlots.visibleSlots(
            planned: mealStore.plan(for: date).plannedSlots
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                SCPageBackground(scheme: scheme)
                    .ignoresSafeArea()

                // Nagłówek i pasek dni stoją, przewija się wyłącznie strona
                // dnia. Wcześniej cała strona była jednym `ScrollView` i przy
                // dłuższym dniu tytuł, profil i pasek dni wyjeżdżały za górną
                // krawędź — czyli to, po czym się nawiguje, znikało dokładnie
                // wtedy, gdy było potrzebne.
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        // Marginesy wspólne z pozostałymi zakładkami —
                        // tytuł siada w tym samym miejscu co „Przepisy".
                        headerRow
                            .padding(.horizontal, SCPageMetrics.horizontal)
                            .padding(.top, SCPageMetrics.top)
                            // 16, nie 22: pasek dni zaczyna się teraz własnym
                            // wierszem podpisu („TEN TYDZIEŃ · 8–14 WRZ"),
                            // który sam robi odstęp od tytułu. Przy 22 pt
                            // nagłówek i pasek rozjeżdżały się na dwie
                            // niepowiązane wyspy.
                            .padding(.bottom, 16)

                        // Day strip instead of a week switcher: it is the
                        // navigation actually used day to day. Wygląd wspólny
                        // z Kalendarzem, ale wybrany dzień jest osobny —
                        // planowanie i podgląd dnia to dwie różne czynności.
                        EditorialWeekBar(
                            datesViewModel: datesViewModel,
                            selectedDate: $selectedDate,
                            plannedDates: plannedDates
                        )
                        .padding(.horizontal, SCPageMetrics.horizontal)

                        Rectangle()
                            .fill(Color.scRule(scheme))
                            .frame(height: 1)
                            .padding(.horizontal, SCPageMetrics.horizontal)
                            .padding(.top, 6)
                            .padding(.bottom, 16)

                        if let errorMessage = mealStore.errorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal, SCPageMetrics.horizontal)
                                .padding(.bottom, 10)
                        }
                    }

                    DayPager(
                        datesViewModel: datesViewModel,
                        selectedDate: $selectedDate,
                        bottomPadding: 32
                    ) { date in
                        dayPage(for: date)
                    }
                }
                // Same trick as Kalendarz v2: let the layout start at the
                // design's 58pt-from-screen-top instead of below the nav bar.
                .ignoresSafeArea(.container, edges: .top)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            // The empty nav-bar layer would otherwise swallow taps on the
            // profile chip and overflow menu sitting underneath it.
            .background(NavBarHitTestPassthrough())
            .task(id: datesViewModel.weekStartISO) {
                await mealStore.loadWeekPlanFromBackend(
                    weekStart: datesViewModel.weekStartISO,
                    dates: datesViewModel.dates
                )
                prefetchWeekImages()
            }
            .task {
                // The profile filter and the "who eats this" badges are built
                // from the household roster, so make sure it is loaded.
                await sessionStore.refreshHouseholdMembers(force: false)
            }
            .onAppear {
                selectedDate = datesViewModel.dayWithinVisibleWeek(selectedDate)
            }
            .onChange(of: datesViewModel.weekStartISO) { _, _ in
                selectedDate = datesViewModel.selectedDate
            }
            .onChange(of: selectedDate) { _, newValue in
                datesViewModel.selectDate(newValue)
            }
            // A member who is filtered out can't be planned for, so drop back
            // to the household lens if the roster loses them.
            .onChange(of: members.map(\.id)) { _, ids in
                if let id = profile.memberId, !ids.contains(id) {
                    profile = .household
                }
            }
            .alert("Wyczyść ten dzień", isPresented: $showClearDayAlert) {
                Button("Wyczyść", role: .destructive) { clearActiveDay() }
                Button("Anuluj", role: .cancel) { }
            } message: {
                Text("Wszystkie posiłki tego dnia zostaną usunięte z planu.")
            }
            .alert("Usuń plan tygodnia", isPresented: $showClearWeekAlert) {
                Button("Usuń", role: .destructive) { clearWeek() }
                Button("Anuluj", role: .cancel) { }
            } message: {
                Text("Plan całego tygodnia zostanie usunięty razem z posiłkami przypisanymi do dni.")
            }
            .sheet(isPresented: $showProfileSheet) {
                PlanProfileSheet(profile: $profile, members: members)
            }
            .sheet(isPresented: $showProducts) {
                ProductsView(topPadding: 24)
            }
            // Skrót z karty asystenta: przełączenie zakładki to za mało,
            // bo lista zakupów jest arkuszem wewnątrz tego ekranu.
            .onChange(of: sessionStore.opensShoppingList, initial: true) { _, wants in
                guard wants else { return }
                showProducts = true
                sessionStore.opensShoppingList = false
            }
            .sheet(item: $pickerTarget) { target in
                PlanSlotPickerSheet(
                    date: target.date,
                    slot: target.slot,
                    weekStartISO: datesViewModel.weekStartISO,
                    members: members,
                    editing: target.editing,
                    // Planning through a person's lens means the meal is for
                    // them unless you say otherwise.
                    defaultParticipantIds: profile.memberId.map { [$0] } ?? [],
                    // Po acku serwera, nie po dismissie — arkusz zamyka się
                    // przed końcem zapisu, a lista zakupów liczona ze starego
                    // planu byłaby do wyrzucenia.
                    onSaveCompleted: { refreshShoppingList() }
                )
            }
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
                            // i liczba porcji wybrana stepperem przeżywa
                            // kliknięcie w serduszko.
                            detailTarget?.recipe = refreshed
                        }
                    },
                    onClose: { detailTarget = nil },
                    // Stepper startuje od liczby, którą pokazuje wiersz planu.
                    // Posiłek bez zapisanej wartości podstawia tu regułę auto,
                    // bo „nie ustawiono" to nie to samo co jedna porcja.
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

    /// Średnica pigułek akcji w nagłówku Planu.
    ///
    /// 34 pt, a nie domyślne 38: to jedyny nagłówek z TRZEMA akcjami naraz
    /// (zakupy, ⋯, profil) i przy 38 pt wiersz wychodził poza szerokość
    /// ekranu — tytuł urywał się jako „Plan tygodn…". Cztery punkty z każdej
    /// pigułki plus ciaśniejszy odstęp oddają tytułowi ~14 pt; resztę
    /// dokłada `EditorialPageHeader`, dobierając stopień pisma.
    private static let headerActionSize: CGFloat = 34

    private var headerRow: some View {
        EditorialPageHeader(title: "Plan tygodnia") {
            HStack(spacing: 6) {
                // Lista zakupów wchodzi stąd, a nie z dolnego menu: powstaje
                // z TEGO planu i ogląda się ją zaraz po jego ułożeniu.
                // Zwolnione miejsce w menu zajął asystent.
                EditorialIconButton(
                    icon: MenuConstans.Products.icon,
                    size: Self.headerActionSize
                ) {
                    showProducts = true
                }
                .accessibilityLabel(MenuConstans.Products.name)

                overflowMenu

                PlanProfileChip(profile: profile, members: members) {
                    showProfileSheet = true
                }
            }
        }
    }

    /// To, czego nie robi się codziennie: czyszczenie dnia i tygodnia.
    ///
    /// Skoki po tygodniach wyprowadziły się STĄD na pasek dni — tam da się
    /// przesunąć planszę palcem, są strzałki i „DZIŚ", a przede wszystkim
    /// widać, na którym tygodniu się stoi. Trzy pozycje menu robiące to samo
    /// co kontrolka o dwa wiersze niżej były już tylko dłuższym menu.
    private var overflowMenu: some View {
        Menu {
            Button(role: .destructive) {
                showClearDayAlert = true
            } label: {
                Label("Wyczyść ten dzień", systemImage: "eraser")
            }
            Button(role: .destructive) {
                showClearWeekAlert = true
            } label: {
                Label("Usuń plan tygodnia", systemImage: "trash")
            }
        } label: {
            // Ten sam rozmiar co `EditorialIconButton` obok, żeby akcje
            // nagłówka stały w jednym rytmie.
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.scLabel(scheme))
                .frame(width: Self.headerActionSize, height: Self.headerActionSize)
                .background(Circle().fill(Color.scTileBg(scheme)))
                .overlay(Circle().stroke(Color.scTileStroke(scheme), lineWidth: 1))
        }
        .accessibilityLabel("Więcej opcji planu")
    }

    /// Strona jednego dnia: karta ze slotami i sekcja podziałów pod nią.
    ///
    /// Karta i podziały jadą razem, więc sekcja jest zawsze tuż pod dniem,
    /// który opisuje.
    private func dayPage(for date: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PlanDayCard(
                date: date,
                isToday: datesViewModel.isToday(date),
                isPast: !datesViewModel.isEditable(date),
                isEditable: datesViewModel.isEditable(date),
                profile: profile,
                members: members,
                slots: visibleSlots(on: date),
                meals: { slot in visibleMeals(date: date, slot: slot) },
                onTapMeal: { slot, meal in openDetail(date: date, slot: slot, meal: meal) },
                onAddMeal: { slot in
                    pickerTarget = PickerTarget(date: date, slot: slot, editing: nil)
                },
                onEditMeal: { slot, meal in
                    pickerTarget = PickerTarget(date: date, slot: slot, editing: meal)
                },
                onRemoveMeal: { slot, meal in
                    removeMeal(date: date, slot: slot, meal: meal)
                }
            )

            // Only worth showing once the day holds something and there is
            // someone to split with — otherwise it just repeats „Brak planu"
            // from the card above.
            if profile == .household, members.count > 1, hasMeals(on: date) {
                PlanDaySplitsSection(
                    date: date,
                    slots: visibleSlots(on: date),
                    meals: { slot in mealStore.meals(for: date, slot: slot) },
                    members: members,
                    onTapMeal: { slot, meal in openDetail(date: date, slot: slot, meal: meal) }
                )
                .padding(.top, 30)
            }
        }
        // Strona trzyma wspólny margines strony.
        .padding(.horizontal, SCPageMetrics.horizontal)
    }

    // MARK: - Actions

    private func openDetail(date: Date, slot: MealSlot, meal: PlanMeal) {
        Task { @MainActor in
            let full = await recipeCatalogStore.loadRecipeDetail(recipeId: meal.recipe.id) ?? meal.recipe
            detailTarget = DetailTarget(date: date, slot: slot, meal: meal, recipe: full)
        }
    }

    /// Zapisuje liczbę porcji zmienioną stepperem w szczegółach.
    ///
    /// Audytorium zostaje takie, jakie było — użytkownik zmieniał porcje, a nie
    /// to, kto je danie. `plannedServings` idzie jawnie, więc serwer nie
    /// nadpisze go swoją regułą auto.
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
            refreshShoppingList()
        }
    }

    private func removeMeal(date: Date, slot: MealSlot, meal: PlanMeal) {
        Task { @MainActor in
            let ok = await mealStore.removeWeekSlot(
                for: date,
                slot: slot,
                weekStart: datesViewModel.weekStartISO,
                recipe: meal.recipe
            )
            if ok { refreshShoppingList() }
        }
    }

    private func clearActiveDay() {
        let activeDay = selectedDate
        Task { @MainActor in
            for slot in MealSlot.allCases where !mealStore.meals(for: activeDay, slot: slot).isEmpty {
                _ = await mealStore.removeWeekSlot(
                    for: activeDay,
                    slot: slot,
                    weekStart: datesViewModel.weekStartISO
                )
            }
            refreshShoppingList()
        }
    }

    private func clearWeek() {
        Task { @MainActor in
            await mealStore.clearWeekFromBackend(
                weekStart: datesViewModel.weekStartISO,
                dates: datesViewModel.dates
            )
            refreshShoppingList()
        }
    }

    private func refreshShoppingList() {
        Task { @MainActor in
            await shoppingListStore.load(weekStart: datesViewModel.weekStartISO, force: true)
        }
    }

    private func prefetchWeekImages() {
        let urls = datesViewModel.dates
            .flatMap { date in MealSlot.allCases.flatMap { mealStore.meals(for: date, slot: $0) } }
            .compactMap(\.recipe.imageURL)
        ImagePrefetcher.prefetch(urls)
    }
}

#Preview {
    WeeklyPlanView()
}

// MARK: - Nav bar hit-test pass-through
//
// Same helper every editorial v2 screen carries privately (Kalendarz, Przepisy,
// Produkty, Ustawienia): the toolbar layer stays alive so SwiftUI's
// blur-on-scroll material still fades in, but stops capturing touches across
// its ~44pt height — otherwise it would eat taps on the profile chip and the
// week chevrons that sit underneath it.
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
