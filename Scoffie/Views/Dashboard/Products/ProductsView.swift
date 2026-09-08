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
// • Alejkę można zwinąć, a kupiona w całości zwija się sama. Kupione produkty
//   spadają na dół swojej alejki.
// • Wiersz „Na dziś” otwiera arkusz z dzisiejszymi daniami, a z arkusza da się
//   zawęzić listę do dzisiejszych produktów.
// • „Kupione” i „Zamknij listę” zeszły z karty hero do menu „…” i do jednej
//   pigułki na końcu listy, która pojawia się dopiero wtedy, gdy jest co
//   zamykać.
struct ProductsView: View {
    /// Odsunięcie tytułu od góry. Na pełnym ekranie odsuwa go od Dynamic
    /// Island; w arkuszu (wejście z nagłówka Planu tygodnia) taki margines
    /// zostawiałby pod uchwytem pustą, niczym nieuzasadnioną przestrzeń.
    var topPadding: CGFloat = SCPageMetrics.top

    @Environment(\.shoppingListStore) private var shoppingListStore
    @Environment(\.mealCalendarStore) private var mealStore
    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.colorScheme) private var scheme

    @State private var archivePendingDeletion: ArchivedShoppingList?
    @State private var showDeleteAllHistoryAlert = false
    @State private var previewArchiveId: String?

    /// Arkusze bez własnego celu — historia list i „Na dziś”.
    ///
    /// Jeden `@State` na oba, a nie dwa niezależne `Bool`-e z osobnymi
    /// `.sheet(isPresented:)`: SwiftUI potrafi zgubić wcześniejszy
    /// `.sheet(isPresented:)` w łańcuchu modyfikatorów tego samego widoku,
    /// a ten ekran ma jeszcze arkusz podglądu archiwum. Ta sama zasada, co
    /// w `WeeklyPlanView`.
    @State private var infoSheet: InfoSheet?

    private enum InfoSheet: String, Identifiable {
        case history
        case today
        var id: String { rawValue }
    }

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

    private var previewedArchive: ArchivedShoppingList? {
        guard let previewArchiveId else { return nil }
        return shoppingListStore.archivedLists.first { $0.archiveId == previewArchiveId }
    }

    private var previewedArchiveItems: [ShoppingItem] {
        guard let previewArchiveId else { return [] }
        return shoppingListStore.archiveDisplayItems(archiveId: previewArchiveId)
    }

    private var previewArchiveSheetBinding: Binding<ArchivedShoppingList?> {
        Binding(
            get: { previewedArchive },
            set: { updatedValue in
                previewArchiveId = updatedValue?.archiveId
            }
        )
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
        groupItemsByDepartment(activeItems)
    }

    /// Alejki widoczne na ekranie. W trybie „Na dziś” zostają wyłącznie
    /// produkty dzisiejszych dań — razem z już kupionymi, żeby wiersz nie
    /// znikał spod palca w chwili odhaczenia.
    private var visibleGroups: [(department: String, items: [ShoppingItem])] {
        guard todayOnly else { return groupedByDepartment }
        return groupItemsByDepartment(activeItems.filter { dishIndex.isForToday($0) })
    }

    private var groupedPreviewItemsByDepartment: [(department: String, items: [ShoppingItem])] {
        groupItemsByDepartment(previewedArchiveItems)
    }

    private func groupItemsByDepartment(_ items: [ShoppingItem]) -> [(department: String, items: [ShoppingItem])] {
        let departmentOrder: [String: Int] = [
            ProductConstants.Department.vegetables: 1,
            ProductConstants.Department.fruits: 2,
            ProductConstants.Department.meat: 3,
            ProductConstants.Department.fish: 4,
            ProductConstants.Department.dairy: 5,
            ProductConstants.Department.bakery: 6,
            ProductConstants.Department.grains: 7,
            ProductConstants.Department.canned: 8,
            ProductConstants.Department.spices: 9,
            ProductConstants.Department.oils: 10,
            ProductConstants.Department.alcohols: 11,
            ProductConstants.Department.beverages: 12,
            ProductConstants.Department.snacks: 13,
            ProductConstants.Department.frozen: 14,
            ProductConstants.Department.bakerySweets: 15,
            ProductConstants.Department.household: 16,
            ProductConstants.Department.other: 99
        ]
        let normalizedOther = ProductConstants.Department.other
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return Dictionary(grouping: items, by: \.department)
            .sorted {
                let leftKey = $0.key.trimmingCharacters(in: .whitespacesAndNewlines)
                let rightKey = $1.key.trimmingCharacters(in: .whitespacesAndNewlines)

                let leftIsOther = leftKey.lowercased() == normalizedOther
                let rightIsOther = rightKey.lowercased() == normalizedOther
                if leftIsOther != rightIsOther {
                    return !leftIsOther
                }

                let leftRank = departmentOrder[leftKey] ?? 999
                let rightRank = departmentOrder[rightKey] ?? 999
                if leftRank != rightRank { return leftRank < rightRank }
                return leftKey < rightKey
            }
            .map { (department: $0.key, items: $0.value) }
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

    var body: some View {
        NavigationStack {
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
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            .background(NavBarHitTestPassthrough())
            // Odhaczenie produktu jest jedyną czynnością na tym ekranie i robi
            // się je z ręką w koszyku, często nie patrząc — stuknięcie w palec
            // potwierdza je szybciej niż animacja kółka.
            .sensoryFeedback(.selection, trigger: boughtCount)
            // Domknięcie całej listy zasługuje na mocniejszy sygnał niż każdy
            // pojedynczy produkt; przy cofnięciu ptaszka nie ma czego świętować.
            .sensoryFeedback(trigger: canCloseCurrentList) { _, isReady in
                isReady ? .success : nil
            }
            .alert("Usunąć listę z historii?", isPresented: archiveDeleteAlertBinding) {
                Button("Anuluj", role: .cancel) {
                    archivePendingDeletion = nil
                }
                Button("Usuń", role: .destructive) {
                    if let archivePendingDeletion {
                        if previewArchiveId == archivePendingDeletion.archiveId {
                            previewArchiveId = nil
                        }
                        shoppingListStore.deleteArchivedList(archiveId: archivePendingDeletion.id)
                    }
                    archivePendingDeletion = nil
                }
            } message: {
                Text("Ta operacja usunie zapisany wpis historyczny dla wybranego tygodnia.")
            }
            .alert("Usunąć całą historię list?", isPresented: $showDeleteAllHistoryAlert) {
                Button("Anuluj", role: .cancel) { }
                Button("Usuń wszystko", role: .destructive) {
                    previewArchiveId = nil
                    shoppingListStore.deleteAllArchivedLists()
                }
            } message: {
                Text("Ta operacja usunie wszystkie zapisane listy produktów z historii.")
            }
            .task(id: datesViewModel.weekStartISO) {
                previewArchiveId = nil
                todayOnly = false
                await shoppingListStore.load(weekStart: datesViewModel.weekStartISO)
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
            .onChange(of: completedAisles, initial: true) { _, current in
                if !didSeedCollapsedAisles {
                    didSeedCollapsedAisles = true
                    // Wejście na listę, w której coś już jest kupione: alejki
                    // domknięte wcześniej (także na innym telefonie) startują
                    // zwinięte, zamiast rozwijać się na sekundę i zwijać same.
                    collapsedAisles = current
                    completedAislesSnapshot = current
                    return
                }
                collapsedAisles.formUnion(current.subtracting(completedAislesSnapshot))
                collapsedAisles.subtract(completedAislesSnapshot.subtracting(current))
                completedAislesSnapshot = current
            }
            .sheet(item: previewArchiveSheetBinding) { archive in
                archivePreview(archive)
                    .presentationDetents([.large])
                    .dashboardLiquidSheet()
            }
            .sheet(item: $infoSheet) { which in
                switch which {
                case .history:
                    historySheet
                        .presentationDetents([.medium, .large])
                        .dashboardLiquidSheet()
                case .today:
                    todaySheet
                        .presentationDetents([.large])
                        .dashboardLiquidSheet()
                }
            }
        }
    }

    // MARK: - Header (shared across states)

    private var editorialHeader: some View {
        // „Zakupy”, nie „Produkty”: ekran wchodzi koszykiem z nagłówka Planu
        // i mówi o jednej czynności — kupowaniu na ten tydzień. „Produkty”
        // brzmiało jak katalog, którym ten ekran nigdy nie był.
        EditorialPageHeader(title: "Zakupy") {
            overflowMenu
        }
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.top, pageTopPadding)
    }

    /// Wszystko, co dotyczy CAŁEJ listy: masowe odhaczenie, zamknięcie
    /// i historia. Wcześniej dwie pierwsze akcje dzieliły jeden przycisk
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

            if !shoppingListStore.archivedLists.isEmpty {
                Divider()

                Button {
                    infoSheet = .history
                } label: {
                    Label("Historia list", systemImage: "clock.arrow.circlepath")
                }

                Button(role: .destructive) {
                    showDeleteAllHistoryAlert = true
                } label: {
                    Label("Usuń całą historię", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.scLabel(scheme))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.scTileBg(scheme)))
                .overlay(Circle().stroke(Color.scTileStroke(scheme), lineWidth: 1))
                .scTapTarget(drawn: 34)
        }
        .accessibilityLabel("Więcej opcji listy zakupów")
    }

    /// Eyebrow tygodnia i meta „10 dań · 29 produktów”.
    private var weekRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(weekEyebrow)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.scMuted(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            if listState == .content {
                Text(weekMeta)
                    .font(.system(size: 12.5, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(Color.scFaint(scheme))
                    .lineLimit(1)
                    // Meta ustępuje miejsca eyebrow, a nie odwrotnie —
                    // data tygodnia jest tu ważniejsza od liczby dań.
                    .layoutPriority(-1)
                    .transition(.opacity)
            }
        }
        .frame(minHeight: 22)
        .padding(.horizontal, pageHorizontalPadding)
        .padding(.top, 20)
    }

    // MARK: - Active shopping list

    private var shoppingListContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let errorMessage = shoppingListStore.errorMessage, !errorMessage.isEmpty {
                Text(verbatim: errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, pageHorizontalPadding)
                    .padding(.top, 12)
            }

            ShoppingProgressHeader(
                bought: boughtCount,
                total: activeItems.count,
                segments: progressSegments
            )
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, 16)

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

            if showsTodayRow {
                ShoppingTodayRow(
                    missing: todayMissingItems.count,
                    dishes: todayMissingDishCount,
                    isFiltered: todayOnly,
                    action: { handleTodayTap() }
                )
                .padding(.horizontal, pageHorizontalPadding)

                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    .padding(.horizontal, pageHorizontalPadding)
            }

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
        .animation(.easeInOut(duration: 0.24), value: todayOnly)
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
                        onToggleItem: { handleToggle($0) }
                    )
                }
            }
            .padding(.horizontal, pageHorizontalPadding)
        }
    }

    @ViewBuilder
    private var emptyGroupsNote: some View {
        if todayOnly {
            noteCard(
                icon: "checkmark.seal.fill",
                tint: SCPalette.sage,
                title: "Na dzisiejsze dania masz wszystko",
                subtitle: "Wróć do całej listy, żeby dokupić resztę tygodnia."
            )
        } else if hasOpenRevision {
            noteCard(
                icon: "checkmark.seal.fill",
                tint: SCPalette.sage,
                title: "Brak nowych produktów do kupienia",
                subtitle: "Zmiany w planie nie dodały nowych zakupów na ten tydzień."
            )
        } else {
            noteCard(
                icon: "basket",
                tint: Color.scMuted(scheme),
                title: "Brak aktywnej listy",
                subtitle: "Zapisz plan tygodniowy, aby wygenerować produkty."
            )
        }
    }

    private func noteCard(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color.scLabel(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.scMuted(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }

    // MARK: - Akcje

    private func toggleAisle(_ department: String) {
        if collapsedAisles.contains(department) {
            collapsedAisles.remove(department)
        } else {
            collapsedAisles.insert(department)
        }
    }

    /// Stuknięcie w wiersz „Na dziś”: z pełnej listy otwiera arkusz z daniami,
    /// z trybu filtra wraca do całej listy.
    private func handleTodayTap() {
        if todayOnly {
            todayOnly = false
        } else {
            infoSheet = .today
        }
    }

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
                    infoSheet = nil
                    todayOnly = true
                },
                onClose: { infoSheet = nil }
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

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.18 : 0.10))
                Image(systemName: "basket.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(SCPalette.terracotta)
            }
            .frame(width: 78, height: 78)

            VStack(spacing: 8) {
                Text("Lista zakupów jest jeszcze pusta")
                    .font(.system(size: 18, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Color.scLabel(scheme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Dodaj posiłki do planu tygodniowego, a produkty pojawią się tutaj automatycznie.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.scMuted(scheme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                emptyHintChip(icon: "calendar.badge.plus", title: "Dodaj plan")
                emptyHintChip(icon: "cart", title: "Lista pojawi się sama")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 28)
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
    }

    private func emptyHintChip(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.scMuted(scheme))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.scChipBg(scheme)))
    }

    // MARK: - Archived state
    //
    // Bez karty statusu i bez powtórzonej daty: eyebrow nad listą mówi już,
    // o którym tygodniu mowa, a status domyka jedna wyśrodkowana kreska
    // (ten sam wzorzec, co pusta oś w Kalendarzu). Każdy wiersz historii
    // pokazuje folio, etykietę rewizji i licznik.
    private var archivedState: some View {
        VStack(alignment: .leading, spacing: 0) {
            weekClosedRule
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.top, 16)
                .padding(.bottom, 18)

            if !currentWeekArchives.isEmpty {
                archiveRowsContainer(currentWeekArchives)
                    .padding(.horizontal, pageHorizontalPadding)

                deleteAllHistoryButton
                    .padding(.horizontal, pageHorizontalPadding)
                    .padding(.top, 14)
            }
        }
    }

    /// Archives that belong to the currently-viewed week — sorted by
    /// revision ascending so the displayed folios run 01 → 02 → 03 in
    /// the same direction as `Lista 1 → Lista 2 → Lista 3`.
    private var currentWeekArchives: [ArchivedShoppingList] {
        let weekStart = datesViewModel.weekStartISO
        return shoppingListStore.archivedLists
            .filter { $0.weekStart == weekStart }
            .sorted { $0.revision < $1.revision }
    }

    /// Cross-week history feed — newest week first, then oldest revision
    /// first within each week (so revision folios still read ascending).
    private var sortedAllArchives: [ArchivedShoppingList] {
        shoppingListStore.archivedLists.sorted { lhs, rhs in
            if lhs.weekStart != rhs.weekStart {
                return lhs.weekStart > rhs.weekStart
            }
            return lhs.revision < rhs.revision
        }
    }

    /// Calendar-style centered rule: hairline — „8–14 WRZ · ZAMKNIĘTE” —
    /// hairline.
    private var weekClosedRule: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.scRule(scheme))
                .frame(height: 1)
                .frame(maxWidth: .infinity)

            Text("\(weekRangeShort.uppercased()) · ZAMKNIĘTE")
                .font(.system(size: 9, weight: .bold))
                .tracking(2)
                .foregroundStyle(SCPalette.indigo)
                .lineLimit(1)
                .fixedSize()

            Rectangle()
                .fill(Color.scRule(scheme))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Archive history (sheet + inline rows)

    /// Rounded container with hairline separators between archive rows.
    private func archiveRowsContainer(_ archives: [ArchivedShoppingList]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(archives.enumerated()), id: \.element.id) { idx, archive in
                archiveRow(archive)

                if idx < archives.count - 1 {
                    Rectangle()
                        .fill(Color.scRule(scheme))
                        .frame(height: 1)
                        .padding(.leading, 60)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Subtle, full-width red pill — same look as on the history sheet so
    /// the destructive affordance reads consistently across surfaces.
    private var deleteAllHistoryButton: some View {
        Button {
            showDeleteAllHistoryAlert = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                Text("Usuń całą historię")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(-0.1)
                    .lineLimit(1)
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.red.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Usuń całą historię")
    }

    private var historySheet: some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("HISTORIA LIST")
                                .font(.system(size: 10.5, weight: .bold))
                                .tracking(1.4)
                                .foregroundStyle(SCPalette.terracotta)
                                .lineLimit(1)
                            Text("Zamknięte listy")
                                .font(.system(size: 22, weight: .heavy))
                                .foregroundStyle(Color.scLabel(scheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 8)
                        Button {
                            infoSheet = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.scMuted(scheme))
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.scChipBg(scheme)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Zamknij")
                    }

                    if shoppingListStore.archivedLists.isEmpty {
                        Text("Brak zapisanych list.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.scMuted(scheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        archiveRowsContainer(sortedAllArchives)

                        deleteAllHistoryButton
                            .padding(.top, 8)
                    }
                }
                .padding(SCPageMetrics.horizontal)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// One archive row — single line, no date repetition. Folio italic uses
    /// the actual revision number so it always matches the „Lista N” label.
    private func archiveRow(_ archive: ArchivedShoppingList) -> some View {
        let counts = shoppingListStore.archiveDisplayCounts(archiveId: archive.archiveId)
        let folio = archive.revision < 10
            ? String(format: "0%d", archive.revision)
            : "\(archive.revision)"
        let isCurrentWeek = archive.weekStart == datesViewModel.weekStartISO

        return HStack(alignment: .center, spacing: 14) {
            Button {
                previewArchiveId = archive.archiveId
                infoSheet = nil
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    Text(folio)
                        .font(.system(size: 24, weight: .heavy))
                        .italic()
                        .tracking(-0.8)
                        .foregroundStyle(SCPalette.indigo.opacity(scheme == .dark ? 0.65 : 0.55))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 0) {
                            Text("Lista \(archive.revision)")
                                .font(.system(size: 15, weight: .heavy))
                                .tracking(-0.3)
                                .foregroundStyle(Color.scLabel(scheme))

                            Text(verbatim: " · ")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.scMuted(scheme))

                            Text("\(counts.bought)/\(counts.total) kupione")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.scMuted(scheme))
                                .monospacedDigit()
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                        if !isCurrentWeek {
                            Text(archive.weekLabel)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.scMuted(scheme).opacity(0.8))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pokaż listę \(archive.revision), \(archive.weekLabel)")

            HStack(spacing: 6) {
                archiveIconButton(
                    icon: "eye",
                    tint: Color.scMuted(scheme),
                    fill: Color.scChipBg(scheme),
                    label: "Pokaż listę \(archive.revision)"
                ) {
                    previewArchiveId = archive.archiveId
                    infoSheet = nil
                }

                archiveIconButton(
                    icon: "trash",
                    tint: .red.opacity(0.85),
                    fill: Color.red.opacity(0.10),
                    label: "Usuń z historii"
                ) {
                    archivePendingDeletion = archive
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func archiveIconButton(
        icon: String,
        tint: Color,
        fill: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Archive preview sheet

    private func archivePreview(_ archive: ArchivedShoppingList) -> some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LISTA \(archive.revision)")
                                .font(.system(size: 10.5, weight: .bold))
                                .tracking(1.4)
                                .foregroundStyle(SCPalette.terracotta)
                                .lineLimit(1)
                            Text(archive.weekLabel)
                                .font(.system(size: 22, weight: .heavy))
                                .foregroundStyle(Color.scLabel(scheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 8)
                        Button {
                            previewArchiveId = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.scMuted(scheme))
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.scChipBg(scheme)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Zamknij")
                    }

                    if groupedPreviewItemsByDepartment.isEmpty {
                        noteCard(
                            icon: "basket",
                            tint: Color.scMuted(scheme),
                            title: "Pusta lista",
                            subtitle: "Ta zamknięta lista nie ma żadnych produktów."
                        )
                        .padding(.top, 18)
                    } else {
                        ForEach(Array(groupedPreviewItemsByDepartment.enumerated()), id: \.element.department) { _, group in
                            ShoppingAisleSection(
                                department: group.department,
                                items: group.items,
                                mode: .readOnly,
                                // Dania pod produktem tylko dla OGLĄDANEGO
                                // tygodnia. Indeks jest zbudowany z jego planu,
                                // więc przy liście sprzed miesiąca dopisałby
                                // „Pomidorom" dzisiejszą zupę — czyli danie,
                                // którego w tamtym tygodniu nie było.
                                dishSummary: { item in
                                    archive.weekStart == datesViewModel.weekStartISO
                                    ? dishIndex.dishSummary(for: item)
                                    : nil
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, SCPageMetrics.horizontal)
                .padding(.top, 24)
                .padding(.bottom, SCPageMetrics.bottom)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var archiveDeleteAlertBinding: Binding<Bool> {
        Binding(
            get: { archivePendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    archivePendingDeletion = nil
                }
            }
        )
    }
}

// MARK: - Nav bar hit-test pass-through (shared with CalendarView)
//
// SwiftUI's `NavigationStack` keeps the toolbar layer "live" so the auto-blur
// material can fade in on scroll, but that layer also captures touches across
// its full ~44pt height — even when the toolbar is visually empty. That blocks
// the editorial header's icon buttons once the layout extends under it via
// `.ignoresSafeArea(.container, edges: .top)`.
//
// We don't have any real toolbar items here (just the invisible 1×1 placeholder
// that keeps the bar from collapsing). Disabling user interaction on the
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

#Preview {
    ProductsView()
}
