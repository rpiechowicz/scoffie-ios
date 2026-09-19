import SwiftUI

// Plan tygodnia — v2 „Cozy Kitchen”, kierunek D.
// Źródło: canvas claude.ai → „Weekly Meals - Plan v2.html”
// (`components/plan-v2-d.jsx`, `plan-v2-edit.jsx`, `plan-v2-empty.jsx`).
//
// Układ: tytuł z akcjami i pasek dni — wszystko przypięte do góry — a pod nimi
// jedyna przewijana część ekranu: strona jednego dnia jako OŚ CZASU
// (`PlanDayTimeline`). Ruch palcem w bok przestawia dzień (`DayPager`), tak
// samo jak w Kalendarzu.
//
// Co zmienił kierunek D względem v2.0:
// • Karta dnia i osobna sekcja „Każdy je inaczej” zniknęły. Porę dnia niesie
//   szyna czasu po lewej, a danie domownika stoi wprost pod daniem domu.
// • Przełącznik gospodarstwa zszedł z nagłówka do menu „…”. Oś pokazuje dania
//   wszystkich obok siebie, więc soczewka jednej osoby przestała być czymś,
//   co trzeba mieć pod kciukiem przez cały czas.
// • Asystent siedzi w nagłówku EKRANU, w rzędzie z zakupami i „…”. Nagłówek
//   dnia jest już tylko podpisem: nazwa dnia po lewej, „2 z 3 posiłków” po
//   prawej. Dodawanie ręczne żyje w wierszach osi: „Wybierz przepis”
//   i „Dodaj posiłek”.
//
// Sloty posiłków: dzień rysuje tyle wierszy, ile gospodarstwo ma włączonych
// w Ustawieniach → „Posiłki w planie”, plus te, w których mimo wyłączenia coś
// stoi (`visibleSlots(on:)`). Reszta czeka pod „Dodaj posiłek”.
struct WeeklyPlanView: View {
    @Environment(\.toasts) private var toasts
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
    @State private var pickerTarget: PickerTarget?
    @State private var detailTarget: DetailTarget?
    @State private var showClearDayAlert = false
    @State private var showClearWeekAlert = false
    /// Arkusze bez własnego celu: lista zakupów i plansza asystenta.
    ///
    /// Jeden `@State` na oba, a nie dwa niezależne `Bool`-e z osobnymi
    /// `.sheet(isPresented:)`. SwiftUI potrafi zgubić wcześniejsze
    /// `.sheet(isPresented:)` w łańcuchu modyfikatorów tego samego widoku,
    /// a ten ekran ma ich cztery — z celami przepisu i wyboru posiłku.
    /// Jeden `item` to jedna prezentacja, więc nie ma czego gubić.
    @State private var simpleSheet: SimpleSheet?

    private enum SimpleSheet: String, Identifiable {
        case products
        case assistantIntro
        case dayGoal
        var id: String { rawValue }
    }

    /// Wysokość obszaru zakładki — z niej liczy się sufit arkusza „Cel dnia".
    /// Arkusz sam jej nie zna: `GeometryReader` w jego wnętrzu podaje wysokość
    /// AKTUALNEGO detentu, a nie tego, do ilu wolno mu urosnąć.
    @State private var pageHeight: CGFloat = 0
    /// Szerokość obszaru zakładki — z niej liczy się szerokość pigułki.
    @State private var pageWidth: CGFloat = 0

    /// Pigułka „Cel dnia" jest węższa od dolnego menu i to jest jedyna rzecz,
    /// która mówi, co jest nawigacją, a co podglądem: dwa paski tej samej
    /// szerokości jeden nad drugim czytały się jak dwa poziomy tego samego menu.
    ///
    /// Ile dokładnie — decydują podpisy w pigułce. Kolumna kalorii bierze
    /// tyle, ile potrzebuje „kcal 2298/2300" (~90 pt), a trzy makra dzielą resztę
    /// po równo i każde musi zmieścić „B 112/110" (~60 pt). Stąd 0,82, a nie
    /// okrągłe dwie trzecie: przy nich makra miały po ~50 pt i podpis się
    /// kurczył. Podłoga 310 pt trzyma to samo na wąskich telefonach
    /// (375 pt: makra po ~62 pt); sufit zostawia pigułkę w marginesach strony.
    private var goalBarWidth: CGFloat {
        guard pageWidth > 0 else { return 0 }
        let limit = pageWidth - SCPageMetrics.horizontal * 2
        return min(max(pageWidth * 0.82, 310), limit)
    }

    // Cel dnia mieszka w Ustawieniach → „Dieta i alergeny" i w profilu; tu
    // czytamy go tymi samymi kluczami, co Kalendarz, bo tylko `@AppStorage`
    // odświeży pigułkę, gdy ktoś przestawi suwak i wróci na Plan.
    @AppStorage(RecipePersonalization.Keys.calorieGoal)
    private var calorieGoal: Int = RecipePersonalization.defaultCalorieGoal
    @AppStorage(RecipePersonalization.Keys.goal)
    private var goalRaw: String = UserGoal.healthy.rawValue
    @AppStorage(BodyMetrics.Keys.heightCm) private var profileHeightCm: Int = 0
    @AppStorage(BodyMetrics.Keys.weightKg) private var profileWeightKg: Double = 0
    @AppStorage(BodyMetrics.Keys.sex) private var profileSexRaw: String = ""
    @AppStorage(BodyMetrics.Keys.yearOfBirth) private var profileYearOfBirth: Int = 0
    @AppStorage(BodyMetrics.Keys.activityLevel)
    private var profileActivityRaw: Int = ActivityLevel.light.rawValue
    @AppStorage(DailyNutritionTargets.Keys.proteinG)
    private var proteinOverride: Int = DailyNutritionTargets.Keys.noOverride
    @AppStorage(DailyNutritionTargets.Keys.fatG)
    private var fatOverride: Int = DailyNutritionTargets.Keys.noOverride
    @AppStorage(DailyNutritionTargets.Keys.carbsG)
    private var carbsOverride: Int = DailyNutritionTargets.Keys.noOverride

    /// Posiłek otwarty w szczegółach, razem z miejscem, z którego przyszedł.
    ///
    /// Sam `Recipe` tu nie wystarczy: ekran szczegółu pozwala zmienić liczbę
    /// porcji, a zapis musi trafić w ten konkretny wpis planu — czyli
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
        /// Ustawione, gdy arkusz edytuje istniejący wariant, a nie dokłada nowy.
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

    /// Klucze „yyyy-MM-dd” dni, w których coś już stoi — z nich bierze się
    /// zielona kropka pod paskiem dni i odpowiedź na „czy tydzień jest pusty”.
    private var plannedDates: Set<String> {
        var set = Set<String>()
        for date in datesViewModel.dates {
            let plan = mealStore.plan(for: date)
            if !plan.allMeals.isEmpty { set.insert(plan.dateKey) }
        }
        return set
    }

    /// Ile produktów zostało do kupienia w widocznym tygodniu — liczba na
    /// plakietce przy koszyku. Regułę („co się liczy po zamknięciu listy")
    /// trzyma magazyn, żeby nagłówek Planu i ekran Zakupów nie mogły podać
    /// dwóch różnych liczb.
    private var shoppingRemainingCount: Int {
        shoppingListStore.remainingCount(for: datesViewModel.weekStartISO)
    }

    /// VoiceOver czyta stan razem z akcją — sama plakietka jest dla niego
    /// niewidoczna, bo „19" wypowiedziane osobno nic nie znaczy.
    private var shoppingAccessibilityLabel: String {
        let remaining = shoppingRemainingCount
        guard remaining > 0 else { return "Lista zakupów" }
        return "Lista zakupów, \(PolishPlural.products(remaining)) do kupienia"
    }

    /// Cały widoczny tydzień bez jednego posiłku. Nie decyduje już o TYM, czy
    /// plansza asystenta się pokaże (pokazuje się zawsze, gdy stukniesz
    /// w przycisk) — tylko o tym, co na niej pisze: „ułożę” brzmi jak groźba
    /// nadpisania komuś, kto ma już pół tygodnia rozpisane ręcznie.
    private var isWeekEmpty: Bool { plannedDates.isEmpty }

    /// Dzienny cel — ta sama reguła, co w Ustawieniach.
    private var dailyTargets: DailyNutritionTargets {
        DailyNutritionTargets.resolve(
            calorieGoal: calorieGoal,
            goal: UserGoal(rawValue: goalRaw) ?? .healthy,
            metrics: BodyMetrics(
                heightCm: profileHeightCm,
                weightKg: profileWeightKg,
                yearOfBirth: profileYearOfBirth,
                activityRaw: profileActivityRaw,
                sexRaw: profileSexRaw
            ),
            proteinOverride: proteinOverride,
            fatOverride: fatOverride,
            carbsOverride: carbsOverride
        )
    }

    /// Wybrany dzień policzony raz — pigułka nad menu i arkusz „Cel dnia"
    /// biorą liczby stąd, przez tę samą listę slotów i tę samą soczewkę
    /// profilu, co oś dnia pod spodem.
    private var selectedDayNutrition: PlanDayNutrition {
        PlanDayNutrition.make(
            slots: visibleSlots(on: selectedDate),
            meals: { visibleMeals(date: selectedDate, slot: $0) },
            knownHouseholdMemberCount: knownHouseholdMemberCount
        )
    }

    /// Posiłki slotu, zawężone do bieżącego profilu.
    ///
    /// Danie osobiste bije danie wspólne: jeśli Ania ma swój obiad, jej
    /// soczewka pokazuje właśnie ten obiad, a nie dodatkowo wspólny. Bez tej
    /// reguły dzień jednej osoby liczył każdy slot podwójnie.
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

    /// Pory, których dzień jeszcze nie pokazuje — pod „Dodaj posiłek”.
    /// Pusto znaczy, że dom planuje już wszystkie sześć: wiersza nie ma wtedy
    /// czym wypełnić, więc go nie ma.
    private func extraSlots(on date: Date) -> [MealSlot] {
        let visible = Set(visibleSlots(on: date))
        return MealSlot.allCases.filter { !visible.contains($0) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                SCPageBackground(scheme: scheme)
                    .ignoresSafeArea()

                // Nagłówek i pasek dni stoją, przewija się wyłącznie strona
                // dnia. Wcześniej cała strona była jednym `ScrollView` i przy
                // dłuższym dniu tytuł i pasek dni wyjeżdżały za górną krawędź —
                // czyli to, po czym się nawiguje, znikało dokładnie wtedy, gdy
                // było potrzebne.
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        // Marginesy wspólne z pozostałymi zakładkami —
                        // tytuł siada w tym samym miejscu co „Przepisy”.
                        headerRow
                            .padding(.horizontal, SCPageMetrics.horizontal)
                            .padding(.top, SCPageMetrics.top)
                            // 16, nie 22: pasek dni zaczyna się własnym
                            // wierszem podpisu („TEN TYDZIEŃ · 8–14 WRZ”),
                            // który sam robi odstęp od tytułu.
                            .padding(.bottom, 16)

                        // Pasek dni zamiast przełącznika tygodni: to nawigacja
                        // faktycznie używana na co dzień. Wygląd wspólny
                        // z Kalendarzem, ale wybrany dzień jest osobny —
                        // planowanie i podgląd dnia to dwie różne czynności.
                        EditorialWeekBar(
                            datesViewModel: datesViewModel,
                            selectedDate: $selectedDate,
                            plannedDates: plannedDates
                        )
                        .padding(.horizontal, SCPageMetrics.horizontal)

                        // 14 pt nad kreską i nic pod nią: odstęp od kreski do
                        // nazwy dnia należy do osi (`PlanDayTimeline` zaczyna
                        // się własnym paddingiem 18 pt), żeby liczyć go w
                        // jednym miejscu, a nie po obu stronach granicy.
                        Rectangle()
                            .fill(Color.scRule(scheme))
                            .frame(height: 1)
                            .padding(.horizontal, SCPageMetrics.horizontal)
                            .padding(.top, 14)

                        // Bez czerwonego wiersza błędu: od kiedy most z korzenia
                        // aplikacji wystawia `errorMessage` jako toast, ten sam
                        // komunikat renderował się DWA razy — raz jako kapsuła,
                        // raz jako przypis, który dokładał wysokości przypiętemu
                        // nagłówkowi i spychał oś dnia w chwili, gdy treść pod
                        // spodem i tak się przekładała.
                    }

                    DayPager(
                        datesViewModel: datesViewModel,
                        selectedDate: $selectedDate,
                        // 16, nie 32: pigułka „Cel dnia" wstawia pod treść
                        // własny bezpieczny obszar (`safeAreaInset` niżej),
                        // więc to jest już tylko prześwit MIĘDZY ostatnim
                        // wierszem osi a szkłem pigułki.
                        bottomPadding: 16,
                        // Stuknięcie w dzień i strzałki tygodnia jadą tak samo
                        // jak gest — strona rysuje dzień z argumentu, więc
                        // pager może pokazać stary dzień na czas zjazdu.
                        animatesSelectionChanges: true
                    ) { date in
                        dayPage(for: date)
                    }
                }
                // Ten sam trik co w Kalendarzu v2: układ startuje od
                // projektowych 78 pt od GÓRNEJ KRAWĘDZI EKRANU, a nie spod
                // paska nawigacji.
                .ignoresSafeArea(.container, edges: .top)
            }
            // Pigułka wchodzi bezpiecznym obszarem, a nie `overlay`.
            // Różnica jest w tym, co się dzieje z osią dnia pod spodem:
            // `overlay` zostawiał ostatni wiersz („Dodaj posiłek") POD szkłem,
            // gdzie było go widać, ale nie dało się w niego stuknąć.
            // `safeAreaInset` doksięgowuje wysokość pigułki do wnętrza
            // `ScrollView`, więc treść nadal przelatuje pod szkłem przy
            // przewijaniu, ale kończy się nad nim.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PlanDayGoalBar(
                    nutrition: selectedDayNutrition,
                    targets: dailyTargets,
                    action: { simpleSheet = .dayGoal }
                )
                .frame(width: goalBarWidth)
                .padding(.bottom, 8)
                // Pierwsza klatka nie zna jeszcze szerokości zakładki, a
                // pigułka o zerowej szerokości mignęłaby jako kreska.
                .opacity(goalBarWidth > 0 ? 1 : 0)
            }
            // Wymiary obszaru zakładki: wysokość idzie na sufit arkusza
            // „Cel dnia", szerokość na szerokość pigułki. Mierzone spod spodu,
            // żeby pomiar nie ruszał układu.
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.size, initial: true) { _, size in
                            pageHeight = size.height
                            pageWidth = size.width
                        }
                }
            }
            // Miejsce pod własnym paskiem zakładek — musi być WEWNĄTRZ
            // `NavigationStack`, patrz `scReservesTabBarSpace`.
            .scReservesTabBarSpace()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            // Pusta warstwa paska nawigacji zjadałaby stuknięcia w akcje
            // nagłówka, które siedzą pod nią.
            .background(NavBarHitTestPassthrough())
            .task(id: datesViewModel.weekStartISO) {
                await mealStore.loadWeekPlanFromBackend(
                    weekStart: datesViewModel.weekStartISO,
                    dates: datesViewModel.dates
                )
                prefetchWeekImages()
            }
            // Plakietka przy koszyku musi znać stan listy, ZANIM ktokolwiek
            // otworzy arkusz — inaczej pokazywałaby zero do pierwszego
            // wejścia w zakupy. `load` idzie po cache, więc arkusz otwarty
            // chwilę później nie płaci za to drugim zapytaniem.
            .task(id: datesViewModel.weekStartISO) {
                await shoppingListStore.load(weekStart: datesViewModel.weekStartISO)
            }
            .task {
                // Imiona, kolory i odznaki „dla kogo” biorą się ze składu
                // gospodarstwa, więc musi być wczytany.
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
            // Domownika, którego nie ma na liście, nie da się zaplanować —
            // przy zniknięciu ze składu wracamy do soczewki całego domu.
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
            .alert("Wyczyść cały tydzień", isPresented: $showClearWeekAlert) {
                Button("Wyczyść", role: .destructive) { clearWeek() }
                Button("Anuluj", role: .cancel) { }
            } message: {
                Text("Plan całego tygodnia zostanie usunięty razem z posiłkami przypisanymi do dni.")
            }
            .sheet(item: $simpleSheet) { which in
                switch which {
                case .products:
                    ProductsView(topPadding: 24)
                case .dayGoal:
                    PlanDayGoalSheet(
                        date: selectedDate,
                        nutrition: selectedDayNutrition,
                        targets: dailyTargets,
                        // 0,9 wysokości zakładki: arkusz „do treści" nie ma
                        // prawa dojechać pod sam pasek stanu, bo wtedy
                        // przestaje być podglądem, a zaczyna być ekranem.
                        maxHeight: pageHeight * 0.9
                    )
                    // Bez `presentationDetents` — arkusz podaje własny,
                    // policzony z treści (patrz `PlanDayGoalSheet`).
                    .dashboardLiquidSheet()

                case .assistantIntro:
                    PlanAssistantIntroSheet(
                        members: members,
                        days: datesViewModel.dates,
                        // Sloty z ustawień, nie `visibleSlots(on:)`: tamte
                        // doliczają pory widoczne tylko dlatego, że akurat
                        // w wybranym dniu coś w nich stoi, i obietnica
                        // „21 posiłków" rosła do 28 po przełączeniu dnia.
                        slotsPerDay: sessionStore.mealSlots.enabled.count,
                        weekIsEmpty: isWeekEmpty,
                        onOpenAssistant: { openAssistantTabAfterSheet() }
                    )
                    .presentationDetents([.large])
                    .dashboardLiquidSheet()
                }
            }
            // Skrót z karty asystenta: przełączenie zakładki to za mało,
            // bo lista zakupów jest arkuszem wewnątrz tego ekranu.
            .onChange(of: sessionStore.opensShoppingList, initial: true) { _, wants in
                guard wants else { return }
                simpleSheet = .products
                sessionStore.opensShoppingList = false
            }
            .sheet(item: $pickerTarget) { target in
                PlanSlotPickerSheet(
                    date: target.date,
                    slot: target.slot,
                    weekStartISO: datesViewModel.weekStartISO,
                    members: members,
                    editing: target.editing,
                    // Planowanie przez soczewkę jednej osoby znaczy, że posiłek
                    // jest dla niej, dopóki nie powiesz inaczej.
                    defaultParticipantIds: profile.memberId.map { [$0] } ?? [],
                    // Po acku serwera, nie po dismissie — arkusz zamyka się
                    // przed końcem zapisu, a lista zakupów liczona ze starego
                    // planu byłaby do wyrzucenia.
                    onSaveCompleted: { refreshShoppingList() }
                )
                .presentationDetents([.large])
                .dashboardLiquidSheet()
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
                    // bo „nie ustawiono” to nie to samo co jedna porcja.
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

    /// Średnica pigułek akcji w nagłówku Planu — 34 pt, jak `P2Circle`
    /// w makiecie. Akcje są trzy (asystent, zakupy i „…”); tytuł schodzi
    /// wtedy o stopień pisma sam, przez `ViewThatFits` w `EditorialPageHeader`.
    private static let headerActionSize: CGFloat = 34

    private var headerRow: some View {
        EditorialPageHeader(title: "Plan tygodnia") {
            HStack(spacing: 6) {
                // Asystent stoi w nagłówku EKRANU, a nie w nagłówku dnia.
                //
                // Wcześniej był 44-punktową pigułką obok nazwy dnia — czyli
                // jedyną akcją, która wyglądała, jakby dotyczyła poniedziałku,
                // a otwierała planszę na cały tydzień. Tutaj mówi to samo, co
                // sąsiednie akcje: rzecz dotyczy tego planu, nie tej strony.
                // Podświetlona, bo to jedyna akcja nagłówka, która coś tworzy.
                EditorialIconButton(
                    icon: MenuConstans.Assistant.icon,
                    highlighted: true,
                    size: Self.headerActionSize,
                    tapTarget: 44
                ) {
                    simpleSheet = .assistantIntro
                }
                .accessibilityLabel("Zaplanuj z asystentem")

                // Lista zakupów wchodzi stąd, a nie z dolnego menu: powstaje
                // z TEGO planu i ogląda się ją zaraz po jego ułożeniu.
                //
                // Plakietka z liczbą jest ceną za to przeniesienie. Zakupy
                // przestały być zakładką, więc nic na ekranie nie mówiło, że
                // coś w nich zostało — żeby się dowiedzieć, trzeba było
                // otworzyć arkusz. Teraz koszyk niesie tę jedną liczbę, która
                // ma znaczenie: ile produktów czeka na kupienie.
                EditorialIconButton(
                    icon: MenuConstans.Products.icon,
                    size: Self.headerActionSize,
                    tapTarget: 44
                ) {
                    simpleSheet = .products
                }
                .scCountBadge(shoppingRemainingCount)
                .accessibilityLabel(shoppingAccessibilityLabel)

                overflowMenu
            }
        }
    }

    /// Wszystko, co dotyczy CAŁEGO tygodnia, plus wybór soczewki.
    ///
    /// Skoki po tygodniach wyprowadziły się stąd na pasek dni. Zamiast nich
    /// wszedł asystent (skrót prosto do zakładki, dla osoby, która szuka go
    /// w menu) i przełącznik profilu, który zszedł z nagłówka razem z pigułką.
    private var overflowMenu: some View {
        Menu {
            // Prosto do asystenta, bez planszy „co on właściwie robi”.
            // Kto szuka go w menu, ten już wie — planszę pokazuje pigułka
            // z iskierkami w nagłówku, na którą trafia się przypadkiem.
            Button {
                sessionStore.dashboardTab = .assistant
            } label: {
                Label("Zaplanuj tydzień z asystentem", systemImage: MenuConstans.Assistant.icon)
            }

            if members.count > 1 {
                Menu {
                    Button {
                        profile = .household
                    } label: {
                        Label(
                            "Cały dom",
                            systemImage: profile == .household ? "checkmark" : "house"
                        )
                    }

                    ForEach(members, id: \.id) { member in
                        Button {
                            profile = .member(member.id)
                        } label: {
                            Label(
                                HouseholdMemberStyle.shortName(member.displayName),
                                systemImage: profile.memberId == member.id ? "checkmark" : "person"
                            )
                        }
                    }
                } label: {
                    Label(profileMenuTitle, systemImage: "person.crop.circle")
                }
            }

            Divider()

            Button(role: .destructive) {
                showClearDayAlert = true
            } label: {
                Label(clearDayTitle, systemImage: "eraser")
            }
            Button(role: .destructive) {
                showClearWeekAlert = true
            } label: {
                Label("Wyczyść cały tydzień", systemImage: "trash")
            }
        } label: {
            // Ten sam krążek co `EditorialIconButton` obok, żeby akcje
            // nagłówka stały w jednym rytmie. 34 pt to rysunek; cel dotyku 44.
            SCCircleIconLabel(icon: "ellipsis", size: Self.headerActionSize, iconSize: 14)
                .scTapTarget(drawn: Self.headerActionSize)
        }
        .accessibilityLabel("Więcej opcji planu")
    }

    /// „Pokaż plan: cały dom” / „Pokaż plan: Ania”.
    private var profileMenuTitle: String {
        guard let id = profile.memberId,
              let member = members.first(where: { $0.id == id }) else {
            return "Pokaż plan: cały dom"
        }
        return "Pokaż plan: \(HouseholdMemberStyle.shortName(member.displayName))"
    }

    /// „Wyczyść poniedziałek”, „Wyczyść środę” — nazwa dnia w bierniku.
    ///
    /// Formy z `DateFormatter` są w mianowniku („środa”), a po „wyczyść” stoi
    /// biernik. Różnica dotyczy tylko trzech dni tygodnia, ale to akurat te,
    /// które najczęściej się czyści.
    private var clearDayTitle: String {
        let weekday = PlanWeek.calendar.component(.weekday, from: selectedDate)
        let names = [
            "niedzielę", "poniedziałek", "wtorek", "środę",
            "czwartek", "piątek", "sobotę"
        ]
        let index = max(0, min(names.count - 1, weekday - 1))
        return "Wyczyść \(names[index])"
    }

    /// Strona jednego dnia — oś czasu ze wszystkim, co w nim stoi.
    private func dayPage(for date: Date) -> some View {
        PlanDayTimeline(
            date: date,
            isToday: datesViewModel.isToday(date),
            isEditable: datesViewModel.isEditable(date),
            profile: profile,
            members: members,
            slots: visibleSlots(on: date),
            meals: { slot in visibleMeals(date: date, slot: slot) },
            extraSlots: extraSlots(on: date),
            // Wołanie o pusty tydzień tylko tam, gdzie da się coś dodać —
            // pusty tydzień z przeszłości jest po prostu pusty.
            weekIsEmpty: isWeekEmpty && datesViewModel.isEditable(date),
            onTapMeal: { slot, meal in openDetail(date: date, slot: slot, meal: meal) },
            onAddMeal: { slot in
                pickerTarget = PickerTarget(date: date, slot: slot, editing: nil)
            },
            onEditMeal: { slot, meal in
                pickerTarget = PickerTarget(date: date, slot: slot, editing: meal)
            },
            onRemoveMeal: { slot, meal in
                removeMeal(date: date, slot: slot, meal: meal)
            },
            onAssistant: { simpleSheet = .assistantIntro },
            onPickExtraSlot: { slot in
                pickerTarget = PickerTarget(date: date, slot: slot, editing: nil)
            }
        )
        // Strona trzyma wspólny margines strony.
        .padding(.horizontal, SCPageMetrics.horizontal)
        // Przeszłość jest tylko do czytania — i ma to być widać, zanim
        // użytkownik dotknie wiersza i nic się nie stanie. 0,82, nie 0,72:
        // przygaszenie nakłada się na już przygaszone `scMuted` w metadanych
        // wiersza („60 min · 604 kcal") i przy 0,72 schodziły one poniżej
        // progu czytelności. Przełączenie tej wartości nie jest animowane
        // celowo — dzieje się między zjazdem a wjazdem strony w `DayPager`,
        // czyli poza ekranem.
        .opacity(datesViewModel.isEditable(date) ? 1 : 0.82)
    }

    // MARK: - Actions

    /// Zakładka przełącza się DOPIERO po zjeździe arkusza.
    ///
    /// Arkusz wisi na ekranie Planu, a `TabView` trzyma ekrany zakładek przy
    /// życiu — przełączenie w tej samej klatce, w której arkusz zjeżdża, urywa
    /// jego animację w połowie i asystent wchodzi zza wpół zamkniętej planszy.
    /// 280 ms to tyle, ile trwa systemowe zamknięcie arkusza.
    private func openAssistantTabAfterSheet() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            sessionStore.dashboardTab = .assistant
        }
    }

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
        // Policzone PRZED kasowaniem — po nim nie ma już czego liczyć, a to
        // jedyna liczba, która mówi, czy zniknęło to, co miało zniknąć.
        // Alert zapytać o to nie mógł: nikt tych posiłków wcześniej nie liczył.
        // Liczymy SLOTY, nie warianty: `allMeals` rozbija posiłek na osobne
        // wpisy dla każdego podziału audytorium, więc tydzień z codzienną
        // kolacją dla dwojga meldowałby czternaście posiłków tam, gdzie plan
        // pokazuje siedem. Reszta aplikacji też liczy slotami.
        let removed = datesViewModel.dates
            .map { mealStore.plan(for: $0).plannedSlots.count }
            .reduce(0, +)
        Task { @MainActor in
            let cleared = await mealStore.clearWeekFromBackend(
                weekStart: datesViewModel.weekStartISO,
                dates: datesViewModel.dates
            )
            // Sześć z siedmiu skasowanych dni jest poza ekranem: użytkownik
            // widzi, jak pustoszeje jeden, i gasnące kropki na pasku dni.
            if cleared {
                if removed > 0 {
                    toasts.success("Tydzień wyczyszczony", "Zniknęło \(PolishPlural.meals(removed)).")
                } else {
                    // „Zniknęło 0 posiłków" to zdanie, którego nikt by nie napisał.
                    toasts.success("Tydzień był już pusty")
                }
            } else {
                // Bez potwierdzenia przy nieudanym kasowaniu użytkownik zostaje
                // po alercie z niczym: przy braku sieci `errorMessage` jest
                // puste, więc most z korzenia też milczy.
                toasts.error("Nie udało się wyczyścić tygodnia", "Plan został bez zmian.")
            }
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
// Ten sam prywatny pomocnik, co na każdym ekranie v2 (Kalendarz, Przepisy,
// Produkty, Ustawienia): warstwa paska narzędzi zostaje żywa, więc systemowe
// rozmycie przy przewijaniu dalej działa, ale przestaje łapać dotknięcia na
// swojej ~44-punktowej wysokości — inaczej zjadałaby stuknięcia w akcje
// nagłówka i strzałki tygodnia, które siedzą pod nią.
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
