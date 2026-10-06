import SwiftUI

// Zakupy v2 — lista tygodnia w języku Planu v2 i Kalendarza v2.
// Źródło: canvas claude.ai → „Weekly Meals - Zakupy v2.html”
// (`components/shop-v2-kit.jsx`, `components/shop-v2-final.jsx`).
//
// Co zmieniła wersja 2 względem „Produktów”:
// • Łuk postępu i szesnaście kart z folio zniknęły. Został JEDEN pasek
//   podzielony na segmenty w kolorach działów i wiersze bez kart — hairline
//   biegnie tylko pod treścią, więc kolumna kółek czyta się jako jedna
//   ścieżka do odhaczania.
// • Pod nazwą produktu stoją DANIA, z których się wziął. To jedyna rzecz,
//   której lista zakupów nigdy nie mówiła, a która decyduje przy półce:
//   „to jest do dzisiejszego obiadu” albo „to do czwartkowej kolacji”.
//   Powiązanie liczy się lokalnie z planu tygodnia (`ShoppingDishIndex`).
// • Alejkę można zwinąć, a kupiona w całości zwija się sama. Odhaczenie nie
//   przestawia produktu — wiersz zostaje tam, gdzie był.
// • „Na dziś” (szklany przycisk przyklejony do dołu, 4.10.2026) otwiera arkusz
//   z dzisiejszymi daniami, a z arkusza da się
//   zawęzić listę do dzisiejszych produktów.
// • „Kupione” i „Zamknij listę” zeszły z karty hero do menu „…” i do jednej
//   pigułki na końcu listy, która pojawia się dopiero wtedy, gdy jest co
//   zamykać.
struct ProductsView: View {
    /// Odsunięcie tytułu od góry. Na pełnym ekranie odsuwa go od Dynamic
    /// Island; w arkuszu (wejście z nagłówka Planu tygodnia) taki margines
    /// zostawiałby pod uchwytem pustą, niczym nieuzasadnioną przestrzeń.
    var topPadding: CGFloat = SCPageMetrics.top

    @Environment(\.toasts) private var toasts
    @Environment(\.shoppingListStore) private var shoppingListStore
    @Environment(\.mealCalendarStore) private var mealStore
    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    /// Arkusz „Na dziś” — jedyny arkusz nad Zakupami.
    @State private var showsTodaySheet = false

    /// Stos historii W arkuszu Zakupów: historia → miesiąc → lista to push
    /// z systemowym „wstecz” (6.10.2026), a nie trzy arkusze jeden na drugim.
    @State private var historyPath: [ShoppingHistoryRoute] = []

    /// Dania tygodnia stojące za produktami. Liczone z planu, nie z serwera —
    /// przeliczane dopiero, gdy plan naprawdę się zmieni (`planSignature`),
    /// bo przejście po całym tygodniu w każdym przebiegu `body` byłoby
    /// pracą wykonywaną przy każdym przesunięciu palca.
    @State private var dishIndex: ShoppingDishIndex = .empty

    /// Zwinięte alejki. Trzymane w pamięci ekranu, nie na dysku: zwijanie jest
    /// gestem „mam to z głowy” na czas jednej wizyty w sklepie, a nie
    /// ustawieniem listy.
    @State private var collapsedAisles: Set<String> = []
    /// Alejki kompletne przy poprzednim przebiegu — po nich poznajemy, że to
    /// WŁAŚNIE odhaczony produkt domknął alejkę i wolno ją zwinąć samą.
    @State private var completedAislesSnapshot: Set<String> = []
    @State private var didSeedCollapsedAisles = false

    /// Lista zawężona do produktów potrzebnych na dzisiejsze dania.
    @State private var todayOnly = false

    private static let weekRangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private static let weekDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d"
        return formatter
    }()

    // MARK: - Derived state

    private var shoppingItems: [ShoppingItem] {
        shoppingListStore.items
    }

    private var archivedCurrentWeek: ArchivedShoppingList? {
        shoppingListStore.currentClosedArchive(for: datesViewModel.weekStartISO)
    }

    private var hasOpenRevision: Bool {
        shoppingListStore.hasOpenRevision(for: datesViewModel.weekStartISO)
    }

    private var isCurrentWeekArchived: Bool {
        archivedCurrentWeek != nil && !hasOpenRevision
    }

    /// Active list — pending items only when there's an open revision after
    /// a closed list. The previously-bought items are intentionally hidden:
    /// the active list shows only what the user can still buy this week.
    private var activeItems: [ShoppingItem] {
        shoppingListStore.activeItems(for: datesViewModel.weekStartISO)
    }

    private var groupedByDepartment: [(department: String, items: [ShoppingItem])] {
        ProductConstants.grouped(activeItems)
    }

    /// Alejki widoczne na ekranie. W trybie „Na dziś” zostają wyłącznie
    /// produkty dzisiejszych dań — razem z już kupionymi, żeby wiersz nie
    /// znikał spod palca w chwili odhaczenia.
    private var visibleGroups: [(department: String, items: [ShoppingItem])] {
        guard todayOnly else { return groupedByDepartment }
        return ProductConstants.grouped(activeItems.filter { dishIndex.isForToday($0) })
    }

    private var boughtCount: Int {
        activeItems.filter(\.isChecked).count
    }

    private var remainingCount: Int {
        max(0, activeItems.count - boughtCount)
    }

    /// Segmenty paska postępu — jeden na alejkę, szeroki proporcjonalnie do
    /// liczby produktów. Liczone zawsze z PEŁNEJ listy, także w trybie
    /// „Na dziś”: pasek mówi o całych zakupach tygodnia i nie ma prawa
    /// zmieniać się od przełączenia filtra.
    private var progressSegments: [ShoppingProgressSegment] {
        groupedByDepartment.map { group in
            ShoppingProgressSegment(
                id: group.department,
                bought: group.items.filter(\.isChecked).count,
                total: group.items.count,
                color: ProductConstants.departmentColor(for: group.department)
            )
        }
    }

    /// Alejki kupione w całości — z nich bierze się samoczynne zwijanie.
    private var completedAisles: Set<String> {
        Set(
            groupedByDepartment
                .filter { !$0.items.isEmpty && $0.items.allSatisfy(\.isChecked) }
                .map { $0.department }
        )
    }

    // MARK: - „Na dziś”

    private var todayDate: Date? {
        datesViewModel.dates.first { datesViewModel.isToday($0) }
    }

    private var todayDishes: [ShoppingDish] {
        dishIndex.todayDishes
    }

    private var todayItems: [ShoppingItem] {
        activeItems.filter { dishIndex.isForToday($0) }
    }

    private var todayMissingItems: [ShoppingItem] {
        todayItems.filter { !$0.isChecked }
    }

    /// Ilu dzisiejszych dań dotyczą braki — liczymy dania, nie produkty,
    /// bo to one mówią, co dziś nie wyjdzie.
    private var todayMissingDishCount: Int {
        let missing = todayMissingItems
        return todayDishes.filter { dish in
            missing.contains { dishIndex.dishes(for: $0).contains(dish) }
        }.count
    }

    /// Wiersz „Na dziś” pokazuje się tylko wtedy, gdy jest o czym mówić:
    /// oglądany tydzień zawiera dzisiaj i coś jest na dziś zaplanowane.
    private var showsTodayRow: Bool {
        todayDate != nil && !todayDishes.isEmpty && !todayItems.isEmpty
    }

    // MARK: - Etykiety tygodnia

    /// Etykieta zapisywana z archiwum — zostaje w dotychczasowym kształcie
    /// („8 wrz - 14 wrz”), bo trafia na serwer i widnieje w historii razem
    /// z wpisami sprzed tej zmiany.
    private var weekRangeText: String {
        guard let first = datesViewModel.dates.first,
              let last = datesViewModel.dates.last else {
            return "Bieżący tydzień"
        }
        return "\(Self.weekRangeFormatter.string(from: first)) - \(Self.weekRangeFormatter.string(from: last))"
    }

    /// Zakres do eyebrow nad listą — „8–14 WRZ”, a przez przełom miesiąca
    /// „29 WRZ – 5 PAŹ”. Krótszy od zapisywanego, bo stoi w jednej linijce
    /// obok liczby dań i produktów.
    private var weekRangeShort: String {
        guard let first = datesViewModel.dates.first,
              let last = datesViewModel.dates.last else {
            return "Bieżący tydzień"
        }
        let calendar = PlanWeek.calendar
        if calendar.isDate(first, equalTo: last, toGranularity: .month) {
            return "\(Self.weekDayFormatter.string(from: first))–\(Self.weekRangeFormatter.string(from: last))"
        }
        return "\(Self.weekRangeFormatter.string(from: first)) – \(Self.weekRangeFormatter.string(from: last))"
    }

    private var weekEyebrow: String {
        let range = weekRangeShort.uppercased()
        return datesViewModel.isCurrentWeek ? "TEN TYDZIEŃ · \(range)" : range
    }

    /// „10 dań · 29 produktów”. Bez planu w pamięci zostaje sama liczba
    /// produktów — zmyślonego licznika dań tu nie będzie.
    private var weekMeta: String {
        let products = PolishPlural.products(activeItems.count)
        guard !dishIndex.isEmpty else { return products }
        return "\(PolishPlural.dishes(dishIndex.dishes.count)) · \(products)"
    }

    // MARK: - Akcje listy

    private var canCloseCurrentList: Bool {
        if shoppingItems.isEmpty {
            return false
        }
        if hasOpenRevision {
            return shoppingItems.allSatisfy(\.isChecked)
        }
        return !activeItems.isEmpty && boughtCount == activeItems.count
    }

    private var isBusy: Bool {
        shoppingListStore.isBatchUpdating || shoppingListStore.isArchivePendingAfterBatch
    }

    private var canMarkAllChecked: Bool {
        !isBusy && remainingCount > 0
    }

    private var closeListTitle: String {
        if shoppingListStore.isArchivePendingAfterBatch { return "Zamykam…" }
        if shoppingListStore.isBatchUpdating { return "Zaznaczanie…" }
        return "Zamknij listę"
    }

    private var pageBottomPadding: CGFloat { SCPageMetrics.bottom }
    private var pageHorizontalPadding: CGFloat { SCPageMetrics.horizontal }
    private var pageTopPadding: CGFloat { topPadding }

    /// Który wariant treści pokazuje strona. Wyliczany raz na render i używany
    /// zarówno w `switch`, jak i jako wartość animacji przejścia między stanami.
    private enum ListState: Equatable {
        case loading, archived, empty, content
    }

    private var listState: ListState {
        if shoppingListStore.isLoading && shoppingItems.isEmpty {
            return .loading
        }
        if isCurrentWeekArchived {
            return .archived
        }
        if shoppingItems.isEmpty && !hasOpenRevision {
            return .empty
        }
        return .content
    }

    /// Zmienia się dokładnie wtedy, gdy plan tygodnia ma inne posiłki —
    /// wtedy i tylko wtedy przeliczamy powiązanie produktów z daniami.
    private var planSignature: String {
        datesViewModel.dates
            .map { mealStore.plan(for: $0).allMeals.map(\.id).joined(separator: ",") }
            .joined(separator: ";")
    }

    // MARK: - Body

    /// Pasek postępu zjechał pod górną krawędź — na górze stoi jego
    /// przypięta kopia (`pinnedProgress`).
    @State private var isProgressPinned = false
    /// Arkusz się ustawił — dopiero od tej chwili „Na dziś” pojawia się
    /// i chowa z animacją. Wcześniej przycisk wchodził w trakcie wjazdu
    /// arkusza (lista wczytuje się w tym samym czasie), dziedziczył jego
    /// animację i ramka rosła od zera — „wjeżdża od boku” (Rafał 4.10.2026).
    @State private var footerAnimates = false

    var body: some View {
        NavigationStack(path: $historyPath) {
            ZStack(alignment: .top) {
                SCPageBackground(scheme: scheme)
                    .ignoresSafeArea()

                // JEDEN ScrollView na wszystkie stany. Wcześniej każda gałąź
                // była osobnym ScrollView wewnątrz `if/else`, więc przejście
                // skeleton → lista niszczyło i budowało scroll od nowa: reset
                // pozycji, twarde cięcie bez animacji i remount wszystkich
                // liczników — czyli dokładnie to „przeskakiwanie" przy
                // ładowaniu. Teraz scroll i nagłówek zachowują tożsamość,
                // a podmienia się tylko treść pod nagłówkiem.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        editorialHeader
                        weekRow

                        switch listState {
                        case .loading:
                            loadingState
                        case .archived:
                            archivedState
                        case .empty:
                            emptyState
                        case .content:
                            shoppingListContent
                        }
                    }
                    .padding(.bottom, pageBottomPadding)
                    .animation(.easeInOut(duration: 0.2), value: listState)
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(.container, edges: .top)
                // „Na dziś” przyklejone do dołu (Rafał 4.10.2026: „produkty
                // na dziś osadź w buttonie, który będzie na dole przyklejony,
                // aby móc od razu zobaczyć”) — szklany przycisk nad listą,
                // lista przejeżdża pod nim.
                .scSheetFooter {
                    // Animacja zawężona do samego przycisku. Przypięta do
                    // całego ekranu animowała przy otwieraniu arkusza także
                    // jego układ (lista wczytywała się w trakcie wjazdu) —
                    // treść „wjeżdżała z lewej” (Rafał 4.10.2026).
                    VStack(spacing: 0) {
                        if listState == .content && showsTodayRow {
                            todayButton
                                .transition(.opacity)
                        }
                    }
                    // Do ustawienia się arkusza bez żadnej animacji — także
                    // tej odziedziczonej po jego wjeździe.
                    .transaction { transaction in
                        if !footerAnimates { transaction.animation = nil }
                    }
                    .animation(footerAnimates ? .smooth(duration: 0.3) : nil, value: listState == .content && showsTodayRow)
                }
                .task {
                    // Wjazd arkusza trwa ~0,35 s; potem stopka może już
                    // animować zmiany (odhaczenie ostatniego produktu na dziś).
                    try? await Task.sleep(for: .milliseconds(600))
                    footerAnimates = true
                }

                // Przypięty pasek postępu — wchodzi, gdy prawdziwy zjedzie
                // pod górną krawędź (Rafał: „jak scrolluję, przypnij do góry
                // górną sekcję z progress barem”). Przy górnej krawędzi
                // ARKUSZA, nie pod (ukrytym) paskiem nawigacji — „bardzo od
                // góry odstaje”.
                VStack(spacing: 0) {
                    if listState == .content && isProgressPinned {
                        pinnedProgress
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(.container, edges: .top)
                .animation(.smooth(duration: 0.25), value: isProgressPinned)
            }
            // Pasek nawigacji SCHOWANY (Rafał 4.10.2026: „na Zakupach nie da się
            // kliknąć X oraz ustawień”). Pusty, ale żywy pasek leżał dokładnie
            // na wierszu nagłówka i łapał stuknięcia; hak wyłączający mu dotyk
            // (`NavBarHitTestPassthrough`) bywał zawodny. Pasek jest schowany
            // TYLKO na tym pierwszym ekranie — wepchnięte ekrany historii mają
            // systemowy z „wstecz” (`scPushedPage`).
            .toolbar(.hidden, for: .navigationBar)
            // Historia, miesiąc i lista — kolejne ekrany tego arkusza.
            .navigationDestination(for: ShoppingHistoryRoute.self) { route in
                historyDestination(route)
            }
            // Skasowana lista albo miesiąc bez list — jego ekran schodzi ze
            // stosu sam, zamiast pokazywać coś, czego już nie ma.
            .onChange(of: shoppingListStore.archivedLists.map(\.archiveId)) { _, _ in
                pruneHistoryPath()
            }
            // Odhaczenie produktu jest jedyną czynnością na tym ekranie i robi
            // się je z ręką w koszyku, często nie patrząc — stuknięcie w palec
            // potwierdza je szybciej niż animacja kółka.
            .sensoryFeedback(.selection, trigger: boughtCount)
            // Domknięcie całej listy zasługuje na mocniejszy sygnał niż każdy
            // pojedynczy produkt; przy cofnięciu ptaszka nie ma czego świętować.
            .sensoryFeedback(trigger: canCloseCurrentList) { _, isReady in
                isReady ? .success : nil
            }
            .task(id: datesViewModel.weekStartISO) {
                todayOnly = false
                didSeedCollapsedAisles = false
                collapsedAisles = []

                await shoppingListStore.load(weekStart: datesViewModel.weekStartISO)

                // Stan wyjściowy zwinięć ustawia się PO wczytaniu, bez animacji:
                // alejka kupiona wcześniej (choćby na drugim telefonie) ma być
                // od razu złożona, a nie rozłożyć się i zwinąć pół sekundy
                // później, jakby ktoś właśnie coś odhaczył.
                completedAislesSnapshot = completedAisles
                collapsedAisles = completedAisles
                didSeedCollapsedAisles = true
            }
            // Powiązanie produktów z daniami przelicza się wraz z planem —
            // `initial: true`, bo przy pierwszym wejściu plan jest już
            // w pamięci (wczytuje go ekran Planu, z którego przychodzi arkusz).
            .onChange(of: planSignature, initial: true) { _, _ in
                dishIndex = ShoppingDishIndex.build(
                    dates: datesViewModel.dates,
                    isToday: { datesViewModel.isToday($0) },
                    mealsProvider: { date, slot in mealStore.meals(for: date, slot: slot) }
                )
            }
            // Alejka kupiona w całości zwija się sama — ale tylko w chwili,
            // w której się domknęła. Rozwiniętą potem ręcznie zostawiamy
            // rozwiniętą, bo to była decyzja użytkownika, a nie stan listy.
            //
            // Do czasu ustawienia stanu wyjściowego (patrz `.task` wyżej) nie
            // reagujemy w ogóle: zmiany z wczytywania listy to nie są niczyje
            // odhaczenia i nie mają prawa niczego składać na oczach użytkownika.
            .onChange(of: completedAisles) { _, current in
                guard didSeedCollapsedAisles else { return }

                // Zwłoka 0,45 s to nie ozdoba: alejka domyka się w tej samej
                // chwili, w której zapala się ostatni ptaszek. Bez niej wiersz
                // znikał razem ze stuknięciem i nie dawało się zobaczyć, że
                // odhaczenie w ogóle weszło. Kolejność jest teraz czytelna:
                // ptaszek → przekreślenie → alejka się składa.
                withAnimation(Self.foldAnimation.delay(0.45)) {
                    collapsedAisles.formUnion(current.subtracting(completedAislesSnapshot))
                    collapsedAisles.subtract(completedAislesSnapshot.subtracting(current))
                }
                completedAislesSnapshot = current
            }
            // „Na dziś” — arkusz nad Zakupami, bez zmian.
            .sheet(isPresented: $showsTodaySheet) {
                todaySheet
                    .presentationDetents([.large])
                    .dashboardLiquidSheet()
            }
        }
    }

    // MARK: - Header (shared across states)

    private var editorialHeader: some View {
        // „Zakupy”, nie „Produkty”: ekran wchodzi koszykiem z nagłówka Planu
        // i mówi o jednej czynności — kupowaniu na ten tydzień. „Produkty”
        // brzmiało jak katalog, którym ten ekran nigdy nie był.
        //
        // Ekran Zakupów sam jest arkuszem (wchodzi koszykiem z nagłówka
        // Planu), więc stoi na nagłówku arkuszy zakupów: kafelek z koszykiem
        // (ten sam glif, co przycisk na Planie), tytuł, „…” i ten sam
        // krzyżyk, co wszystko inne. Wcześniej jedyną drogą wyjścia było
        // przeciągnięcie w dół — działa, ale trzeba na nie wpaść.
        ShoppingSheetHeader(title: "Zakupy", icon: MenuConstans.Products.icon, onClose: { dismiss() }) {
            overflowMenu
        }
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.top, pageTopPadding)
    }

    /// Wszystko, co dotyczy CAŁEJ listy: masowe odhaczenie, zamknięcie
    /// i wejście do historii. Wcześniej dwie pierwsze akcje dzieliły jeden przycisk
    /// w karcie hero, który raz mówił „Kupione”, a raz „Zamknij” — a historia
    /// nie miała wejścia w ogóle (arkusz istniał w kodzie i nikt nie mógł go
    /// otworzyć).
    private var overflowMenu: some View {
        Menu {
            Button {
                shoppingListStore.markAllChecked()
            } label: {
                Label("Zaznacz wszystko jako kupione", systemImage: "checkmark.circle")
            }
            .disabled(!canMarkAllChecked)

            Button {
                shoppingListStore.archiveCurrentList(weekLabel: weekRangeText)
            } label: {
                Label("Zamknij listę", systemImage: "archivebox")
            }
            .disabled(!canCloseCurrentList || isBusy)

            // „Usuń całą historię” stoi w JEDNYM miejscu — w „…” ekranu
            // Historii, przy liście, którą kasuje.
            if !shoppingListStore.archivedLists.isEmpty {
                Divider()

                Button {
                    historyPath = [.history]
                } label: {
                    Label("Historia list", systemImage: "clock.arrow.circlepath")
                }
            }
        } label: {
            // 36, nie 34: stoi obok krzyżyka zamykającego arkusz i ma mieć
            // jego rozmiar. 34 jest rozmiarem akcji w nagłówku EKRANU
            // (Plan tygodnia), gdzie krzyżyka nie ma.
            SCCircleIconLabel(icon: "ellipsis", size: SCSheetIconLabel.size, iconSize: 14)
                .scTapTarget(drawn: SCSheetIconLabel.size)
        }
        .accessibilityLabel("Więcej opcji listy zakupów")
    }

    /// Eyebrow tygodnia i meta — „10 dań · 29 produktów” na aktywnej liście,
    /// „Lista zamknięta” po jej domknięciu.
    private var weekRow: some View {
        ShoppingEyebrowRow(eyebrow: weekEyebrow, meta: weekRowMeta)
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, 20)
    }

    private var weekRowMeta: String? {
        switch listState {
        case .content:          return weekMeta
        case .archived:         return "Lista zamknięta"
        case .loading, .empty:  return nil
        }
    }

    // MARK: - Active shopping list

    private var shoppingListContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShoppingProgressHeader(
                bought: boughtCount,
                total: activeItems.count,
                segments: progressSegments
            )
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, 16)
            // Położenie paska względem okna przewijania: gdy jego dół zjedzie
            // pod górę, przypinamy kopię (`pinnedProgress`). Bool, nie
            // przesunięcie — stan zmienia się raz na przekroczenie.
            .onGeometryChange(for: Bool.self) { proxy in
                // Przed pierwszym układem ramka ma zero wysokości i stoi na
                // górze — to nie jest przewinięcie.
                let frame = proxy.frame(in: .scrollView)
                return frame.height > 0 && frame.maxY < 8
            } action: { pinned in
                isProgressPinned = pinned
            }

            if hasOpenRevision {
                // Osobne zdanie, nie osobny wygląd listy: użytkownik ma
                // wiedzieć, dlaczego widzi krótszą listę niż tydzień temu.
                Text("Nowa lista po zmianie planu — same dołożone produkty.")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(Color.scFaint(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, pageHorizontalPadding)
                    .padding(.top, 10)
            }

            Rectangle()
                .fill(Color.scRule(scheme))
                .frame(height: 1)
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.top, 16)

            // „Na dziś” nie stoi już w liście — to przycisk przyklejony do
            // dołu (`todayButton`).

            aisles

            if canCloseCurrentList {
                SCSoftButton(
                    title: closeListTitle,
                    leadingIcon: "archivebox",
                    trailingIcon: nil,
                    accent: SCPalette.sage,
                    isEnabled: !isBusy,
                    isLoading: isBusy,
                    action: { shoppingListStore.archiveCurrentList(weekLabel: weekRangeText) }
                )
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.top, 26)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .animation(.easeInOut(duration: 0.24), value: canCloseCurrentList)
    }

    @ViewBuilder
    private var aisles: some View {
        let groups = visibleGroups

        if groups.isEmpty {
            emptyGroupsNote
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.top, 18)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.department) { _, group in
                    ShoppingAisleSection(
                        department: group.department,
                        items: group.items,
                        mode: todayOnly ? .today : .list,
                        isCollapsed: collapsedAisles.contains(group.department),
                        disablesTaps: shoppingListStore.isBatchUpdating,
                        dishSummary: { dishIndex.dishSummary(for: $0) },
                        isTodayItem: { dishIndex.isForToday($0) },
                        onToggleSection: { toggleAisle(group.department) },
                        onToggleItem: { handleToggle($0) },
                        onRemoveExtra: { item in
                            Task { @MainActor in
                                await shoppingListStore.removeExtra(item)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, pageHorizontalPadding)
        }
    }

    @ViewBuilder
    private var emptyGroupsNote: some View {
        if todayOnly {
            RecipeListEmptyState(
                icon: "checkmark",
                accent: SCPalette.sage,
                title: "Na dziś masz wszystko",
                message: "Reszta tygodnia czeka na całej liście.",
                actions: [
                    .init(title: "Pokaż całą listę", icon: "list.bullet") {
                        withAnimation(.smooth(duration: 0.3)) { todayOnly = false }
                    }
                ]
            )
        } else if hasOpenRevision {
            RecipeListEmptyState(
                icon: "checkmark",
                accent: SCPalette.sage,
                title: "Nic nowego do kupienia",
                message: "Zmiany w planie nie dodały zakupów."
            )
        } else {
            RecipeListEmptyState(
                icon: "basket",
                accent: SCPalette.terracotta,
                title: "Lista jest pusta",
                message: "Produkty z planu tygodnia pojawią się tu same."
            )
        }
    }

    /// Mała karta pustego stanu (historia) — ten sam klocek, co pusta lista
    /// i puste listy przepisów (`RecipeListEmptyState`), bez akcji.
    private func noteCard(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        RecipeListEmptyState(icon: icon, accent: tint, title: title, message: subtitle)
    }

    // MARK: - Akcje

    /// Zwinięcie alejki jedzie JEDNĄ transakcją na cały ekran, a nie
    /// animacją przypiętą do sekcji.
    ///
    /// Sekcja zna tylko własną wysokość; to, co pod nią stoi — kolejne alejki
    /// i pigułka „Zamknij listę” — należy do ekranu. `withAnimation` obejmuje
    /// jedno i drugie, więc sąsiedzi jadą w górę tą samą sprężyną, zamiast
    /// doskakiwać po zakończeniu animacji sekcji.
    private func toggleAisle(_ department: String) {
        withAnimation(Self.foldAnimation) {
            if collapsedAisles.contains(department) {
                collapsedAisles.remove(department)
            } else {
                collapsedAisles.insert(department)
            }
        }
    }

    /// Sprężyna bez odbicia — akordeon ma się złożyć, a nie sprężynować.
    private static let foldAnimation = Animation.spring(response: 0.34, dampingFraction: 0.92)

    /// „Na dziś” jako szklany przycisk przyklejony do dołu ekranu — ten sam
    /// wiersz (`ShoppingTodayRow`: braki dziś, „Cała lista” przy filtrze),
    /// tylko na szkle i zawsze pod ręką.
    private var todayButton: some View {
        ShoppingTodayRow(
            missing: todayMissingItems.count,
            dishes: todayMissingDishCount,
            isFiltered: todayOnly,
            action: { handleTodayTap() }
        )
        .padding(.horizontal, 18)
        .scChromeGlass(in: Capsule(style: .continuous))
    }

    /// Kopia paska postępu przypięta u góry na szkle — licznik i pasek
    /// alejek, nic więcej.
    private var pinnedProgress: some View {
        ShoppingProgressHeader(
            bought: boughtCount,
            total: activeItems.count,
            segments: progressSegments
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .scChromeGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        // Od górnej krawędzi arkusza — pod uchwytem.
        .padding(.top, 14)
    }

    /// Stuknięcie w wiersz „Na dziś”: z pełnej listy otwiera arkusz z daniami,
    /// z trybu filtra wraca do całej listy.
    private func handleTodayTap() {
        guard todayOnly else {
            showsTodaySheet = true
            return
        }
        withAnimation(Self.filterAnimation) { todayOnly = false }
    }

    /// Przełączenie filtra podmienia CAŁĄ listę alejek, więc jedzie łagodniej
    /// od zwijania jednej sekcji — szybka sprężyna na takiej zmianie czyta się
    /// jak mrugnięcie ekranu.
    private static let filterAnimation = Animation.easeInOut(duration: 0.28)

    private func handleToggle(_ item: ShoppingItem) {
        guard let target = activeItems.first(where: { $0.productKey == item.productKey }) else { return }
        Task { @MainActor in
            await shoppingListStore.toggleChecked(target)
        }
    }

    // MARK: - Arkusz „Na dziś”

    @ViewBuilder
    private var todaySheet: some View {
        if let todayDate {
            ShoppingTodaySheet(
                date: todayDate,
                dishes: todayDishes,
                items: activeItems,
                index: dishIndex,
                members: sessionStore.householdMembers,
                disablesTaps: shoppingListStore.isBatchUpdating,
                onToggleItem: { handleToggle($0) },
                onShowInList: {
                    showsTodaySheet = false
                    withAnimation(Self.filterAnimation) { todayOnly = true }
                },
                onClose: { showsTodaySheet = false }
            )
        }
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Przygotowuję listę zakupów")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.scLabel(scheme))
                Text("Pobieram aktualny stan dla tego tygodnia. Przy kolejnych wejściach aplikacja pokaże zapisany stan od razu.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, 16)

            VStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.scTileBg(scheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
                        )
                        .frame(height: 56)
                }
            }
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, 18)
            .redacted(reason: .placeholder)
        }
    }

    // MARK: - Empty state

    /// Czy w tygodniu stoi choć jeden posiłek — pusta lista znaczy wtedy
    /// „jeszcze się układa”, a bez planu „nie ma z czego jej ułożyć”.
    private var weekHasMeals: Bool {
        datesViewModel.dates.contains { !mealStore.plan(for: $0).allMeals.isEmpty }
    }

    /// Pusta lista tygodnia — ten sam klocek, co puste listy przepisów
    /// i karta pustego tygodnia w Planie (`RecipeListEmptyState`: kafelek
    /// powodu w tincie, etykieta, tytuł, jedno zdanie, akcja „soft”). Dawna
    /// karta z koszykiem 78 pt, tytułem 18 heavy i dwoma szarymi chipami
    /// („Dodaj plan”, „Lista pojawi się sama”) była ostatnim pustym stanem
    /// w starym kroju (24.09.2026).
    @ViewBuilder
    /// Pusty stan (Rafał 4.10.2026: „zrób trochę lepiej design pustego
    /// stanu”): `ShoppingEmptyHero` — szklany koszyk, wokół działy sklepu
    /// w swoich kolorach — tytuł, jedno zdanie i akcja. Dawniej karta
    /// `RecipeListEmptyState`, ta sama co w pustych listach przepisów.
    private var emptyState: some View {
        Group {
            if weekHasMeals {
                ShoppingEmptyHero(
                    title: "Lista jest pusta",
                    message: "Produkty z zaplanowanych dań pojawią się tu same."
                )
            } else {
                ShoppingEmptyHero(
                    title: "Tydzień bez planu",
                    message: "Lista ułoży się sama z dań w Planie.",
                    primaryTitle: "Ułóż z Asystentem",
                    primaryIcon: MenuConstans.Assistant.icon,
                    onPrimary: {
                        sessionStore.dashboardTab = .assistant
                        dismiss()
                    },
                    secondaryTitle: "Wróć do Planu",
                    onSecondary: { dismiss() }
                )
            }
        }
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.top, 28)
    }

    // MARK: - Historia
    //
    // Zamknięty tydzień to nie jest „stan pusty z komunikatem”. Lista jest
    // domknięta, nic na niej nie zostało do zrobienia i nowa ułoży się sama —
    // więc ekran oddaje miejsce jedynej rzeczy, która tu jeszcze coś znaczy:
    // historii. Stąd zdjęcia dań, jedno zdanie i wprost pod nim miesiące.
    //
    // Źródło: canvas → „Zakupy v2 · Historia · Final”, plansza 1.

    private var archivedState: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShoppingClosedHero(
                imageURLs: closedHeroImageURLs,
                bought: archivedCurrentWeekCounts.bought,
                total: archivedCurrentWeekCounts.total
            )
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, 36)

            Rectangle()
                .fill(Color.scRule(scheme))
                .frame(height: 1)
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.top, 32)

            if historyMonths.isEmpty {
                noteCard(
                    icon: "clock.arrow.circlepath",
                    tint: Color.scMuted(scheme),
                    title: "Historia jest pusta",
                    subtitle: "Zamknięte listy zakupów trafią tutaj same."
                )
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.top, 18)
            } else {
                ShoppingSectionTitle(
                    title: "Historia",
                    count: PolishPlural.lists(historyListCount)
                )
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, 4)

                // Miesiąc wprost z ekranu z zamkniętą listą — z pominięciem
                // ekranu historii, bo miesiące stoją już tutaj.
                ShoppingMonthList(months: historyMonths) { month in
                    historyPath.append(.month(month.key))
                }
                .padding(.horizontal, pageHorizontalPadding)
            }
        }
    }

    /// Licznik zamkniętej listy tygodnia. Ta sama reguła, co w wierszach
    /// historii (`archiveDisplayCounts`), żeby zdanie w nagłówku i liczba przy
    /// liście niżej nigdy nie mówiły dwóch różnych rzeczy o tej samej liście.
    private var archivedCurrentWeekCounts: (bought: Int, total: Int) {
        guard let archive = archivedCurrentWeek else { return (0, 0) }
        return shoppingListStore.archiveDisplayCounts(archiveId: archive.archiveId)
    }

    /// Zdjęcia dań tygodnia do pustego stanu — po jednym na przepis, cztery.
    ///
    /// Bierzemy je z planu, nie z listy zakupów: lista zna produkty, a na
    /// krążkach mają być DANIA, dla których się kupowało.
    private var closedHeroImageURLs: [URL] {
        var seen = Set<String>()
        var urls: [URL] = []
        for dish in dishIndex.dishes {
            guard let url = dish.imageURL, seen.insert(dish.title).inserted else { continue }
            urls.append(url)
            if urls.count == 4 { break }
        }
        return urls
    }

    /// Historia poukładana w miesiące. Liczniki idą przez
    /// `archiveDisplayCounts`, więc druga rewizja tygodnia nie dolicza po raz
    /// drugi tego samego jogurtu.
    private var historyMonths: [ShoppingHistoryMonth] {
        ShoppingHistory.months(
            archives: shoppingListStore.archivedLists,
            counts: { shoppingListStore.archiveDisplayCounts(archiveId: $0) },
            currentWeekStart: datesViewModel.weekStartISO
        )
    }

    private var historyListCount: Int {
        historyMonths.reduce(0) { $0 + $1.listCount }
    }

    // MARK: - Stos historii

    /// Ekran stosu historii. Dane wyszukiwane po kluczu przy każdym
    /// rysowaniu — skasowanie listy albo ostatniej listy miesiąca zdejmuje
    /// jego ekran ze stosu (`pruneHistoryPath`).
    @ViewBuilder
    private func historyDestination(_ route: ShoppingHistoryRoute) -> some View {
        switch route {
        case .history:
            ShoppingHistoryPage(
                months: historyMonths,
                onOpenMonth: { historyPath.append(.month($0.key)) },
                onDeleteAll: { deleteAllHistory() }
            )
        case .month(let key):
            if let month = historyMonths.first(where: { $0.key == key }) {
                ShoppingHistoryMonthPage(
                    month: month,
                    onOpenArchive: { historyPath.append(.archive($0.archiveId)) },
                    onDelete: { shoppingListStore.deleteArchivedList(archiveId: $0.archiveId) }
                )
            }
        case .archive(let archiveId):
            if let week = historyWeek(containing: archiveId),
               let entry = week.entries.first(where: { $0.archiveId == archiveId }) {
                ShoppingArchivePage(
                    entry: entry,
                    items: shoppingListStore.archiveDisplayItems(archiveId: archiveId),
                    weekRange: week.rangeLabel,
                    dishSummary: archiveDishSummary(isCurrentWeek: week.isCurrent),
                    onDelete: { shoppingListStore.deleteArchivedList(archiveId: archiveId) }
                )
            }
        }
    }

    /// Tydzień historii, w którym leży lista o tym id.
    private func historyWeek(containing archiveId: String) -> ShoppingHistoryWeek? {
        historyMonths
            .flatMap(\.weeks)
            .first { week in week.entries.contains { $0.archiveId == archiveId } }
    }

    /// Dania pod nazwą produktu tylko dla OGLĄDANEGO tygodnia — indeks dań
    /// jest zbudowany z jego planu, więc przy liście sprzed miesiąca
    /// dopisałby „Pomidorom” dzisiejszą zupę. Funkcja zamiast `cond ? … : …`
    /// z domknięciami (SE-0418).
    private func archiveDishSummary(isCurrentWeek: Bool) -> (ShoppingItem) -> String? {
        guard isCurrentWeek else { return { _ in nil } }
        return { item in dishSummary(for: item) }
    }

    /// Zdejmuje ze stosu ekrany rzeczy, których już nie ma: skasowaną listę
    /// i miesiąc, w którym nie została żadna. Historia zostaje (pusta mówi
    /// „Historia jest pusta”).
    private func pruneHistoryPath() {
        let months = historyMonths
        let monthKeys = Set(months.map(\.key))
        let archiveIds = Set(months.flatMap(\.entries).map(\.archiveId))
        let firstGone = historyPath.firstIndex { route in
            switch route {
            case .history:
                return false
            case .month(let key):
                return !monthKeys.contains(key)
            case .archive(let archiveId):
                return !archiveIds.contains(archiveId)
            }
        }
        guard let firstGone else { return }
        historyPath.removeSubrange(firstGone...)
    }

    /// Kasowanie historii jest nieodwracalne i wspólne dla całego domu, a po
    /// nim nie ma na czym zobaczyć skutku: alert się zamyka, arkusz znika,
    /// a użytkownik zostaje na ekranie, na którym historii w ogóle nie widać.
    /// Podtytuł niesie jedyny fakt, którego alert nie mówił — że listy znikają
    /// wszystkim, nie tylko tu.
    private func deleteAllHistory() {
        // Kolejka i store do stałych PRZED zadaniem — arkusz Zakupów bywa
        // zamykany w tej samej chwili, a wtedy jego środowisko już nie żyje.
        let toasts = toasts
        let store = shoppingListStore
        Task { @MainActor in
            if await store.deleteAllArchivedLists() {
                toasts.success("Historia usunięta", "Zamknięte listy zniknęły też u domowników.")
            } else {
                // Przy braku sieci `errorMessage` zostaje puste, a arkusz już
                // się zamknął — bez tego użytkownik nie dostaje po alercie nic.
                toasts.error("Nie udało się usunąć historii", "Listy zostały bez zmian.")
            }
        }
    }

    /// Dania pod nazwą produktu w liście z historii.
    ///
    /// Indeks jest zbudowany z planu OGLĄDANEGO tygodnia, więc przy liście
    /// sprzed miesiąca dopisałby „Pomidorom” dzisiejszą zupę. Historia
    /// zamkniętej listy z tego samego tygodnia dania ma — i to jest dokładnie
    /// ten przypadek, w którym ktoś do niej wraca.
    private func dishSummary(for item: ShoppingItem) -> String? {
        dishIndex.dishSummary(for: item)
    }
}

/// Ekrany historii wpychane w arkusz Zakupów (`ProductsView.historyPath`).
enum ShoppingHistoryRoute: Hashable {
    /// Wszystkie miesiące — z menu „…”.
    case history
    /// Jeden miesiąc (klucz `"2026-09"`) — z historii albo wprost z ekranu
    /// z zamkniętą listą.
    case month(String)
    /// Jedna zamknięta lista (`archiveId`).
    case archive(String)
}

#Preview {
    ProductsView()
}
