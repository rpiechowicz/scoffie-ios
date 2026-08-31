import SwiftUI

// Plan tygodnia — v2 "Cozy Kitchen".
// Source of truth: claude.ai design canvas → `PlanA2FullWidth`
// (components/plan-a2-fix.jsx), sections "Plan tygodnia · Etap 1" and
// "Etap 2 — sekcja „Każdy je inaczej”".
//
// Layout: title + overflow menu + profile chip, a day strip, then a full-width
// paging carousel where one page = one day with all its meal slots followed by
// that day's „Każdy je inaczej" section.
//
// Household splits: every meal carries the members it is for (empty = shared).
// The profile chip switches the whole screen between the household lens and a
// single person's.
//
// Sloty posiłków: dzień rysuje tyle wierszy, ile gospodarstwo ma włączonych
// w Ustawieniach → „Posiłki w planie", plus te, w których mimo wyłączenia coś
// stoi (`visibleSlots(on:)`). Kolejność zawsze porą dnia.
struct WeeklyPlanView: View {
    @Environment(\.weeklyMealStore) private var mealStore
    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.shoppingListStore) private var shoppingListStore
    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.colorScheme) private var scheme

    /// Day currently centred in the carousel, keyed by "yyyy-MM-dd".
    @State private var scrolledDayKey: String?

    /// Dzień planowany w tej zakładce. Własny stan Planu — Kalendarz ma swój,
    /// wspólny zostaje tylko tydzień.
    @State private var selectedDate: Date = Date()
    @State private var profile: PlanProfile = .household
    @State private var showProfileSheet = false
    @State private var pickerTarget: PickerTarget?
    @State private var detailTarget: DetailTarget?
    @State private var showClearDayAlert = false
    @State private var showClearWeekAlert = false
    @State private var showAssistant = false

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
            "\(WeeklyMealStore.dateKey(for: date)).\(slot.rawValue).\(meal.id)"
        }
    }

    private struct PickerTarget: Identifiable {
        let date: Date
        let slot: MealSlot
        /// Set when the sheet edits an existing variant rather than adding one.
        let editing: PlanMeal?

        var id: String {
            let base = "\(WeeklyMealStore.dateKey(for: date)).\(slot.rawValue)"
            return editing.map { "\(base).\($0.id)" } ?? base
        }
    }

    private struct PlanDay: Identifiable, Hashable {
        let id: String      // "yyyy-MM-dd"
        let date: Date
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

    private var planDays: [PlanDay] {
        datesViewModel.dates.map { PlanDay(id: WeeklyMealStore.dateKey(for: $0), date: $0) }
    }

    private var selectedDayKey: String {
        WeeklyMealStore.dateKey(for: selectedDate)
    }

    /// Index of the day in view. Falls back to the selected day while the
    /// carousel has not reported a position yet.
    private var activeIndex: Int {
        let key = scrolledDayKey ?? selectedDayKey
        return planDays.firstIndex { $0.id == key } ?? 0
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

    /// Day the carousel is currently showing.
    private var activeDay: Date? {
        planDays.indices.contains(activeIndex) ? planDays[activeIndex].date : nil
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
                WMPageBackground(scheme: scheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Marginesy wspólne z pozostałymi zakładkami —
                        // tytuł siada w tym samym miejscu co „Przepisy".
                        headerRow
                            .padding(.horizontal, WMPageMetrics.horizontal)
                            .padding(.top, WMPageMetrics.top)
                            // 22 zamiast 14 — pasek dni to osobna kontrolka,
                            // a nie podtytuł nagłówka; przy 14 pt skrót „PON.
                            // WT. ŚR." wyglądał na przyklejony do tytułu.
                            .padding(.bottom, 22)

                        // Day strip instead of a week switcher: it is the
                        // navigation actually used day to day. Wygląd wspólny
                        // z Kalendarzem, ale wybrany dzień jest osobny —
                        // planowanie i podgląd dnia to dwie różne czynności.
                        EditorialWeekBar(
                            datesViewModel: datesViewModel,
                            selectedDate: $selectedDate,
                            plannedDates: plannedDates
                        )
                        .padding(.horizontal, WMPageMetrics.horizontal)

                        Rectangle()
                            .fill(Color.wmRule(scheme))
                            .frame(height: 1)
                            .padding(.horizontal, WMPageMetrics.horizontal)
                            .padding(.top, 6)
                            .padding(.bottom, 16)

                        if let errorMessage = mealStore.errorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal, WMPageMetrics.horizontal)
                                .padding(.bottom, 10)
                        }

                        carousel
                    }
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
                // Same trick as Kalendarz v2: let the layout start at the
                // design's 58pt-from-screen-top instead of below the nav bar,
                // while SwiftUI keeps rendering the bar so its blur-on-scroll
                // material still fades in.
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
                if scrolledDayKey == nil { scrolledDayKey = selectedDayKey }
            }
            .onChange(of: datesViewModel.weekStartISO) { _, _ in
                selectedDate = datesViewModel.selectedDate
            }
            .onChange(of: selectedDate) { _, newValue in
                datesViewModel.selectDate(newValue)
            }
            // Two-way with the day strip: tapping a day scrolls the carousel,
            // swiping the carousel moves the strip's underline.
            .onChange(of: scrolledDayKey) { oldKey, newKey in
                // The scroll view reports its initial page before `onAppear`
                // has aligned it; ignore that first nil → key transition or it
                // would drag the selection back to Monday.
                guard oldKey != nil,
                      let newKey,
                      let day = planDays.first(where: { $0.id == newKey }),
                      !Calendar.current.isDate(day.date, inSameDayAs: selectedDate) else { return }
                selectedDate = day.date
            }
            .onChange(of: selectedDayKey) { _, newKey in
                guard scrolledDayKey != newKey else { return }
                withAnimation(.smooth(duration: 0.25)) {
                    scrolledDayKey = newKey
                }
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
            .sheet(isPresented: $showAssistant) {
                if let agentStore = sessionStore.agentStore {
                    AssistantSheet(store: agentStore)
                } else {
                    // Sesja bez gospodarstwa (albo w trakcie wstawania) —
                    // pusty arkusz wyglądałby na awarię aplikacji.
                    Text("Asystent będzie dostępny, gdy wczyta się gospodarstwo.")
                        .font(.system(size: 15))
                        .multilineTextAlignment(.center)
                        .padding(32)
                        .presentationDetents([.height(160)])
                }
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

    private var headerRow: some View {
        EditorialPageHeader(title: "Plan tygodnia") {
            HStack(spacing: 8) {
                // Asystent siedzi przy Planie, a nie w osobnej zakładce:
                // rozmawia się o TYM tygodniu i wraca do niego z odpowiedzią.
                EditorialIconButton(icon: "sparkles") {
                    showAssistant = true
                }
                .accessibilityLabel("Asystent")

                overflowMenu

                PlanProfileChip(profile: profile, members: members) {
                    showProfileSheet = true
                }
            }
        }
    }

    /// Everything that isn't day-to-day planning: week jumps and clearing.
    /// Parked in a menu so the top of the screen stays about *this* week.
    private var overflowMenu: some View {
        Menu {
            Section {
                Button {
                    datesViewModel.goToPreviousWeek()
                } label: {
                    Label("Poprzedni tydzień", systemImage: "arrow.left")
                }
                Button {
                    datesViewModel.goToNextWeek()
                } label: {
                    Label("Następny tydzień", systemImage: "arrow.right")
                }
                if !datesViewModel.isCurrentWeek {
                    Button {
                        datesViewModel.goToCurrentWeek()
                    } label: {
                        Label("Wróć do bieżącego tygodnia", systemImage: "calendar.badge.clock")
                    }
                }
            }

            Section {
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
            }
        } label: {
            // Ten sam rozmiar co `EditorialIconButton` (38pt), żeby akcje
            // nagłówka wyglądały tak samo na każdej zakładce.
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.wmLabel(scheme))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.wmTileBg(scheme)))
                .overlay(Circle().stroke(Color.wmTileStroke(scheme), lineWidth: 1))
        }
        .accessibilityLabel("Więcej opcji planu")
    }

    private var carousel: some View {
        ScrollView(.horizontal) {
            // Top-aligned: days differ in height, and centring made a
            // three-slot day float away from the week header while a
            // four-slot day sat flush against it.
            HStack(alignment: .top, spacing: 0) {
                ForEach(planDays) { day in
                    // Card and its splits travel together, so the section is
                    // always flush under the day it describes. Pinning the
                    // section outside the carousel meant matching the scroll
                    // view's height to the page in view — which centred taller
                    // pages and let them bleed over the day strip.
                    VStack(alignment: .leading, spacing: 0) {
                        PlanDayCard(
                        date: day.date,
                        isToday: datesViewModel.isToday(day.date),
                        isPast: !datesViewModel.isEditable(day.date),
                        isEditable: datesViewModel.isEditable(day.date),
                        profile: profile,
                        members: members,
                        slots: visibleSlots(on: day.date),
                        meals: { slot in visibleMeals(date: day.date, slot: slot) },
                        onTapMeal: { slot, meal in openDetail(date: day.date, slot: slot, meal: meal) },
                        onAddMeal: { slot in
                            pickerTarget = PickerTarget(date: day.date, slot: slot, editing: nil)
                        },
                        onEditMeal: { slot, meal in
                            pickerTarget = PickerTarget(date: day.date, slot: slot, editing: meal)
                        },
                            onRemoveMeal: { slot, meal in
                                removeMeal(date: day.date, slot: slot, meal: meal)
                            }
                        )

                        // Only worth showing once the day holds something and
                        // there is someone to split with — otherwise it just
                        // repeats „Brak planu" from the card above.
                        if profile == .household, members.count > 1, hasMeals(on: day.date) {
                            PlanDaySplitsSection(
                                date: day.date,
                                slots: visibleSlots(on: day.date),
                                meals: { slot in mealStore.meals(for: day.date, slot: slot) },
                                members: members,
                                onTapMeal: { slot, meal in openDetail(date: day.date, slot: slot, meal: meal) }
                            )
                            .padding(.top, 30)
                        }
                    }
                    // Strona karuzeli trzyma wspólny margines strony.
                    .padding(.horizontal, WMPageMetrics.horizontal)
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolledDayKey)
        .scrollIndicators(.hidden)
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
        guard let activeDay else { return }
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
