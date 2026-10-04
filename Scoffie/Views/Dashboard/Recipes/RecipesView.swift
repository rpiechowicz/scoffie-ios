import Combine
import SwiftUI

// Przepisy v2 — "Story carousel + Tasting menu" (W3 z handoff design'u).
// Source: design/Scoffie - Przepisy.html → recipes-v2.jsx RecipesV2_W3.
//
// Layout (top → bottom):
//   1. EditorialPageHeader     — tytuł "Przepisy"
//   2. EditorialRecipesHero    — eyebrow + "Smaki na dziś" z terakotowym pionem
//   3. Karuzela kart-story     — pełna szerokość, paging, kropki
//   4. Sekcje Tasting menu     — po jednej na `RecipesCategory.catalogSections`
//      (Śniadania / Obiady / Kolacje / Przekąski i desery), każda z
//      EditorialRecipesSectionHeader nad listą EditorialRecipeRow
//   Na dole, nad menu: `RecipesSearchBar` (filtry + szukanie, jak Poczta).
//   Szukanie albo filtry z „Filtrów” = STAN WYNIKÓW: `RecipeResultsHeader`
//   i jedna płaska lista — bez karuzeli i sekcji (4.10.2026).
//
// Stylistyka i paddings idą za pozostałymi widokami v2 (Ustawienia, Produkty,
// Kalendarz): `SCPageBackground`, `pageTopPadding=78`, `pageHorizontalPadding=20`,
// `pageBottomPadding=40`, hide-and-passthrough na NavigationBar.
struct RecipesView: View {
    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.scTabBarChrome) private var tabBarChrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Co dziesięć minut — wystarczy, żeby zestaw zmienił się najdalej dziesięć
    /// minut po piątej, a nie budzi widoku częściej niż trzeba.
    private let mealDayTicker = Timer.publish(every: 600, on: .main, in: .common).autoconnect()

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var selectedRecipe: Recipe?
    @State private var categorySheetSelection: RecipesCategory?
    @State private var featuredSelectionId: UUID?
    /// Kolejność kart karuzeli zamrożona od ostatniego ułożenia.
    ///
    /// Ranking karuzeli stawia ulubione na przodzie, więc polubienie przepisu
    /// przestawiało karty — pod palcem stawała inna karta i następne stuknięcie
    /// otwierało inny przepis niż ten, który był przed chwilą na ekranie
    /// (Rafał, 23.09.2026). Karuzela układa się od nowa tylko przy zmianie
    /// wyszukiwania, filtrów, dopasowania, doby albo katalogu — patrz
    /// `resyncFeaturedSelectionIfNeeded`. `nil` = jeszcze nie ułożona.
    @State private var featuredOrder: [UUID]?
    @State private var filters = RecipeFilterOptions()
    /// Zakładka kategorii nad treścią (`RecipeScopeTabs`); `nil` = wszystkie.
    @State private var scope: RecipesCategory?
    /// Kierunek ostatniej zmiany zakładki — lista wjeżdża z tej strony,
    /// w którą poszedł wybór (w prawo = z prawej).
    @State private var scopeForward = true
    /// Zwykły widok (karuzela + sekcje) STOI w drzewie także pod wynikami —
    /// przezroczysty, więc karuzela nie buduje się od nowa i nie przeskakuje
    /// przy powrocie. Po zgaśnięciu dostaje zerową wysokość, żeby lista
    /// wyników nie miała pod sobą pustego przewijania.
    @State private var browseLayerCollapsed = false
    @State private var isFilterSheetPresented = false

    /// Numer doby posiłkowej — ziarno codziennej rotacji propozycji.
    /// Trzymany w stanie, a nie liczony w locie z `Date()`, żeby przewijanie
    /// listy nie przeliczało go przy każdej klatce.
    @State private var mealDay = DailyRecipeRotation.mealDay()

    // Preferencje żywieniowe właściciela ekranu — te same klucze, które
    // zapisuje Ustawienia → „Dieta i alergeny”. Czytamy je przez
    // `@AppStorage`, więc zmiana w Ustawieniach przestawia listę od razu po
    // powrocie na tę zakładkę, bez żadnego odświeżania.
    @AppStorage(RecipePersonalization.Keys.diet)
    private var dietPreferenceRaw: String = DietPreference.none.rawValue
    @AppStorage(RecipePersonalization.Keys.allergens)
    private var allergensRaw: String = ""
    @AppStorage(RecipePersonalization.Keys.goal)
    private var goalRaw: String = UserGoal.healthy.rawValue
    @AppStorage(RecipePersonalization.Keys.calorieGoal)
    private var calorieGoal: Int = RecipePersonalization.defaultCalorieGoal
    @AppStorage(RecipePersonalization.Keys.enabled)
    private var isPersonalizationEnabled: Bool = true

    // Sections rendered below the carousel — matches the W3 "Tasting menu"
    // rhythm. Empty sections are filtered out when the user is actively
    // searching so the list collapses to the relevant categories.
    private struct RecipeSection: Identifiable {
        let category: RecipesCategory
        let title: String
        let eyebrow: String
        let accent: Color
        let recipes: [Recipe]          // displayed inline (cap = sectionPreviewLimit)
        let totalCount: Int            // full count for this category (sheet badge)
        let filterCount: Int           // filtry tej kategorii (plakietka strzałki)

        var id: RecipesCategory { category }
        var hasMore: Bool { totalCount > recipes.count }
    }

    /// Max liczba przepisów pokazywanych inline w każdej sekcji Tasting menu.
    /// Reszta dostępna pod chevronem (→ `RecipeCategorySheetView`).
    private static let sectionPreviewLimit = 5

    private var pageTopPadding: CGFloat { 78 }
    private var pageHorizontalPadding: CGFloat { 20 }
    private var pageBottomPadding: CGFloat { 40 }

    // MARK: - Derived state

    /// Przepisy po samym wyszukiwaniu — baza dla filtrów i dla licznika
    /// podglądu w arkuszu „Filtry”.
    private var searchedRecipes: [Recipe] {
        guard !debouncedSearchText.isEmpty else { return recipeCatalogStore.recipes }
        return recipeCatalogStore.recipes.filter { recipe in
            recipe.name.localizedCaseInsensitiveContains(debouncedSearchText) ||
            recipe.description.localizedCaseInsensitiveContains(debouncedSearchText)
        }
    }

    /// Preferencje w formie, którą da się nałożyć na katalog.
    private var personalization: RecipePersonalization {
        RecipePersonalization(
            dietRaw: dietPreferenceRaw,
            allergensRaw: allergensRaw,
            goalRaw: goalRaw,
            calorieGoal: calorieGoal,
            isEnabled: isPersonalizationEnabled
        )
    }

    /// Przepisy po wyszukiwarce i po preferencjach — dieta i alergeny tną,
    /// cel przestawia kolejność. Filtry z arkusza idą dopiero na to, żeby
    /// licznik „Pokaż N przepisów” w arkuszu liczył się w tym samym świecie,
    /// który użytkownik widzi na liście.
    private var personalizedRecipes: [Recipe] {
        personalization.apply(to: searchedRecipes)
    }

    /// Wszystkie przepisy przefiltrowane po debounced query, preferencjach
    /// i po filtrach z arkusza.
    private var visibleRecipes: [Recipe] {
        filters.apply(to: personalizedRecipes)
    }

    /// Pula ZWYKŁEGO widoku (karuzela i sekcje): dieta z profilu i filtry
    /// kategorii — bez frazy i bez filtrów z „Filtrów”, które należą do stanu
    /// wyników. Dzięki temu szukanie nie przestawia kart karuzeli pod spodem
    /// i powrót z wyników trafia na ten sam widok, który się zostawiło.
    private var browseRecipes: [Recipe] {
        var categoryOnly = RecipeFilterOptions()
        categoryOnly.categoryFilters = filters.categoryFilters
        return categoryOnly.apply(to: personalization.apply(to: recipeCatalogStore.recipes))
    }

    /// Ile przepisów zabrała sama dieta / alergeny — do podpisu w banerze.
    private var hiddenByPersonalizationCount: Int {
        personalization.hiddenCount(in: searchedRecipes)
    }

    /// Czy lista jest w ogóle zawężona — steruje tekstem pustego stanu i
    /// zwijaniem pustych sekcji Tasting menu.
    private var isNarrowed: Bool {
        filters.hasCategoryFilters
            || (personalization.isEnabled && personalization.restrictsCatalog)
    }

    /// Sekcje Tasting menu — jedna na kategorię katalogu, w kolejności
    /// `RecipesCategory.catalogSections`. Dołożenie kategorii tam dokłada
    /// sekcję tutaj; ta lista niczego już nie wymienia z nazwy.
    private var mealSections: [RecipeSection] {
        let base = RecipesCategory.catalogSections.map(makeSection(category:))
        return isNarrowed ? base.filter { !$0.recipes.isEmpty } : base
    }

    private var hasVisibleRecipes: Bool {
        mealSections.contains { !$0.recipes.isEmpty }
    }

    /// Stan wyników: fraza albo filtry z arkusza „Filtry” (Rafał 4.10.2026:
    /// „jak już się wyszuka, nie może być karuzeli i takiego mocnego podziału
    /// na sekcje”; „jak filtrujemy globalnie, karuzela też może zniknąć”).
    /// Dieta z profilu i filtry jednej kategorii zostają w zwykłym widoku —
    /// to stałe ustawienia, nie szukanie (filtry kategorii mówi plakietka na
    /// strzałce sekcji).
    private var isResultsMode: Bool {
        isSearchingOrFiltering
    }

    /// Fraza albo filtry — wtedy zakładki kategorii pokazują liczby trafień.
    private var isSearchingOrFiltering: Bool {
        !debouncedSearchText.isEmpty || filters.activeCount > 0
    }

    /// Wyniki w zakresie wybranej zakładki.
    private var resultRecipes: [Recipe] {
        guard let scope else { return unscopedResults }
        return unscopedResults.filter { RecipeScopeTabs.contains($0, in: scope) }
    }

    /// Ile trafień leży w każdej zakładce — przy frazie / filtrach.
    private var scopeCounts: [RecipesCategory: Int]? {
        guard isSearchingOrFiltering else { return nil }
        let results = unscopedResults
        return Dictionary(uniqueKeysWithValues: RecipeScopeTabs.scopes.map { scope in
            (scope, results.reduce(0) { $0 + (RecipeScopeTabs.contains($1, in: scope) ? 1 : 0) })
        })
    }

    /// Wyniki w jednej liście. Przy frazie najpierw nazwy, które się nią
    /// ZACZYNAJĄ, potem te, w których słowo się nią zaczyna, potem reszta
    /// nazw, na końcu trafienia w samym opisie; w obrębie grupy kolejność
    /// zostaje (dopasowanie do celu).
    private var unscopedResults: [Recipe] {
        let visible = visibleRecipes
        let query = debouncedSearchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return visible }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        func rank(_ recipe: Recipe) -> Int {
            let name = recipe.name
            if name.range(of: query, options: options.union(.anchored)) != nil { return 0 }
            if name.split(separator: " ").contains(where: {
                String($0).range(of: query, options: options.union(.anchored)) != nil
            }) { return 1 }
            if name.range(of: query, options: options) != nil { return 2 }
            return 3
        }
        return visible.enumerated()
            .map { (rank: rank($0.element), index: $0.offset, recipe: $0.element) }
            .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
            .map(\.recipe)
    }

    /// Wyjście ze stanu wyników — fraza i filtry z „Filtrów” (filtry
    /// kategorii zostają; czyści je ich własny arkusz).
    private func clearResults() {
        searchDebounceTask?.cancel()
        withAnimation(.smooth(duration: 0.3)) {
            searchText = ""
            debouncedSearchText = ""
            filters.resetGlobal()
            scope = nil
        }
    }

    /// Karty karuzeli: zamrożona kolejność (`featuredOrder`) z bieżącymi
    /// danymi przepisów. Przepis, który zniknął z listy (np. odlubiony przy
    /// filtrze „Ulubione”), znika też z karuzeli.
    private var featuredRecipes: [Recipe] {
        let visible = browseRecipes
        if let order = featuredOrder {
            let byId = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let frozen = order.compactMap { byId[$0] }
            if !frozen.isEmpty { return frozen }
        }
        return rankedFeaturedRecipes(from: visible)
    }

    /// Top-N najlepszych kandydatów do karuzeli featured. Ulubione wygrywają,
    /// potem krótszy `prepTime`, potem większy `servings`, potem alfabetycznie.
    private func rankedFeaturedRecipes(from visible: [Recipe]) -> [Recipe] {
        // Gdy cel porządkuje katalog, `visibleRecipes` są już ułożone od
        // najlepiej dopasowanych — drugie sortowanie po `prepTime` tylko by to
        // zepsuło. Bez celu zostaje dotychczasowa heurystyka.
        let ranked = (personalization.isEnabled && personalization.ranksCatalog)
            ? visible
            : visible.sorted(by: isFeaturedRecipePreferred(_:_:))

        // Przy aktywnym wyszukiwaniu albo filtrach karuzela ma pokazać
        // najlepsze trafienia, a nie codzienną propozycję — użytkownik czegoś
        // wtedy szuka i rotacja tylko by mu to mieszała.
        guard !isNarrowed else {
            return Array(ranked.prefix(DailyRecipeRotation.featuredCount))
        }

        return DailyRecipeRotation.pick(from: ranked, day: mealDay)
    }

    private var heroEyebrow: String {
        if personalization.isEnabled, personalization.ranksCatalog {
            return "Pod cel: \(personalization.goal.title)"
        }
        return "Polecane"
    }

    private var heroTitle: String {
        if personalization.isEnabled, personalization.hasAnyPreference {
            return "Dopasowane do Ciebie"
        }
        return "Smaki na dziś"
    }

    /// Rotacja wchodzi o 5 rano, ale aplikacja bywa otwarta przez tę godzinę.
    /// Bez odświeżania stanu użytkownik oglądałby wczorajszy zestaw do
    /// następnego zimnego startu.
    private func refreshMealDayIfNeeded() {
        let current = DailyRecipeRotation.mealDay()
        guard current != mealDay else { return }
        mealDay = current
        resyncFeaturedSelectionIfNeeded()
    }

    private var shouldShowSkeleton: Bool {
        recipeCatalogStore.isLoading && recipeCatalogStore.recipes.isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                SCPageBackground(scheme: scheme)
                    .ignoresSafeArea()

                content
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
            .background(NavBarHitTestPassthrough())
            .task {
                debouncedSearchText = searchText
                await recipeCatalogStore.loadIfNeeded()
                resyncFeaturedSelectionIfNeeded()
            }
            .onChange(of: recipeCatalogStore.recipes.count) { _, _ in
                // Cały katalog tylko na dysk — pamięć mieści ~256 miniatur
                // i wypchnęłoby się to, co właśnie widać (`warmDisk`).
                ImagePrefetcher.warmDisk(recipeCatalogStore.recipes.compactMap(\.imageURL))
                resyncFeaturedSelectionIfNeeded()
            }
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.smooth(duration: 0.3)) {
                        debouncedSearchText = newValue
                    }
                    resyncFeaturedSelectionIfNeeded()
                }
            }
            .onChange(of: filters) { _, _ in
                resyncFeaturedSelectionIfNeeded()
            }
            // Karta zniknęła z zamrożonej karuzeli (np. odlubiona przy filtrze
            // „Ulubione”) — zaznaczenie przechodzi na pierwszą, bez układania
            // kart od nowa.
            .onChange(of: featuredRecipes.map(\.id)) { _, ids in
                if let current = featuredSelectionId, ids.contains(current) { return }
                featuredSelectionId = ids.first
            }
            .onChange(of: personalization) { _, _ in
                resyncFeaturedSelectionIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshMealDayIfNeeded() }
            }
            .onReceive(mealDayTicker) { _ in
                refreshMealDayIfNeeded()
            }
            .onDisappear { searchDebounceTask?.cancel() }
            .sheet(isPresented: $isFilterSheetPresented) {
                // Pula PRZED dopasowaniem: przełącznik „Dopasowane do Ciebie”
                // siedzi w arkuszu i liczby muszą się dać przeliczyć w obie
                // strony.
                RecipeFilterSheet(
                    filters: $filters,
                    isPersonalizationEnabled: $isPersonalizationEnabled,
                    recipes: searchedRecipes,
                    personalization: personalization
                )
                    .presentationDetents([.large])
                    .dashboardLiquidSheet()
            }
            .sheet(item: $selectedRecipe) { selected in
                RecipeDetailView(
                    // Żywy przepis z katalogu, nie kopia z chwili otwarcia —
                    // serce nadąża za zapisem z karuzeli, a zapis z arkusza
                    // nie musi niczego podmieniać w `selectedRecipe`
                    // (przypisanie otwierało zamknięty już arkusz).
                    recipe: recipeCatalogStore.recipes.first(where: { $0.id == selected.id }) ?? selected,
                    onSetFavourite: { value in
                        Task { await recipeCatalogStore.setFavourite(recipeId: selected.id, to: value) }
                    },
                    onClose: { selectedRecipe = nil },
                    // Katalog nie zna żadnego slotu, więc szczegół otwiera się
                    // na jednej porcji i to stepper decyduje, ile ich będzie.
                    onAddedToPlan: { _, _ in selectedRecipe = nil }
                )
                .recipeDetailSheet()
            }
            .sheet(item: $categorySheetSelection) { category in
                let categoryRecipes = recipeCatalogStore.recipes.filter { $0.category == category }
                let inCategory = personalization.apply(to: categoryRecipes)
                RecipeCategorySheetView(
                    category: category,
                    // Filtry z arkusza „Filtry” obowiązują też tutaj — inaczej
                    // chevron „zobacz wszystkie” cofałby zawężenie i pokazywał
                    // przepisy, które użytkownik przed chwilą odsiał.
                    // Wyszukiwarka zostaje poza tym celowo: ten arkusz ma
                    // własną, do przeszukiwania kategorii.
                    recipes: filters.apply(to: inCategory),
                    // Pula dla filtrów kategorii: wszystko poza nimi samymi,
                    // żeby kafelki liczyły „ile zostanie po zaznaczeniu”.
                    pool: filters.withoutCategoryFilter(for: category).apply(to: inCategory),
                    categoryFilter: categoryFilterBinding(for: category),
                    filterLabels: filters.summaryLabels,
                    personalization: personalization,
                    hiddenByPersonalization: personalization.hiddenCount(in: categoryRecipes),
                    onClearFilters: { withAnimation(.smooth(duration: 0.2)) { filters.resetGlobal() } }
                )
                .presentationDetents([.large])
                .dashboardLiquidSheet()
            }
        }
    }

    // MARK: - Content tree

    private var content: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialPageHeader("Przepisy")
                    .id(Self.topAnchor)
                    .padding(.horizontal, pageHorizontalPadding)
                    .padding(.top, pageTopPadding)
                    .padding(.bottom, 12)

                // Zakładki tylko tam, gdzie jest z czego wybierać — nie nad
                // pustym stanem (Rafał 4.10.2026).
                if showsScopeTabs {
                    let counts = scopeCounts
                    RecipeScopeTabs(
                        selection: scopeBinding,
                        counts: counts,
                        total: counts == nil ? nil : unscopedResults.count
                    )
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }

                // Stany leżą NA SOBIE (`ZStack` od góry), nie pod sobą: przy
                // przenikaniu w `VStack` wchodzący stał chwilę pod wychodzącym
                // i podskakiwał na górę, kiedy tamten znikał.
                ZStack(alignment: .top) {
                    if showsBrowseLayer {
                        // JEDEN widok: `body(forRecipes:)` oddaje kilka
                        // (nagłówek, karuzela, kropki, sekcje) — w `ZStack`
                        // bez `VStack` każdy stawał osobną warstwą na górze
                        // i wszystko nakładało się na siebie.
                        VStack(alignment: .leading, spacing: 0) {
                            body(forRecipes: browseRecipes)
                        }
                            .opacity(isResultsMode ? 0 : 1)
                            .scaleEffect(isResultsMode ? 0.97 : 1, anchor: .top)
                            .allowsHitTesting(!isResultsMode)
                            .accessibilityHidden(isResultsMode)
                            .frame(height: browseLayerCollapsed ? 0 : nil, alignment: .top)
                            .transition(.opacity)
                    }

                    if shouldShowSkeleton {
                        skeletonState
                            .transition(.opacity)
                    } else if isResultsMode {
                        resultsState
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 14)),
                                removal: .opacity.combined(with: .offset(y: 8))
                            ))
                    } else if !hasVisibleRecipes {
                        emptyState
                            .padding(.horizontal, pageHorizontalPadding)
                            .padding(.top, 8)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.3), value: shouldShowSkeleton)
                .animation(Self.stateMotion, value: isResultsMode)

                if recipeCatalogStore.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                }
            }
            .padding(.bottom, pageBottomPadding)
            .animation(Self.stateMotion, value: showsScopeTabs)
        }
        .scrollIndicators(.hidden)
        // Przewinięcie listy chowa klawiaturę — jak w Poczcie.
        .scrollDismissesKeyboard(.immediately)
        // Kierunek przewijania steruje zwijaniem dolnego menu.
        .scTracksTabBarCompaction()
        // Duży tytuł zjechał — pod paskiem stanu staje szklana kapsuła.
        .scReportsCompactTitle("Przepisy", for: .recipes)
        .ignoresSafeArea(.container, edges: .top)
        // Nowa fraza albo wejście w wyniki / wyjście z nich — od góry
        // (wyniki mogły zacząć się wysoko nad miejscem, w którym się było).
        .onChange(of: debouncedSearchText) { _, _ in proxy.scrollTo(Self.topAnchor, anchor: .top) }
        .onChange(of: isResultsMode) { _, entering in
            proxy.scrollTo(Self.topAnchor, anchor: .top)
            if entering {
                // Zwykły widok zwija się dopiero po zgaśnięciu.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(420))
                    guard isResultsMode else { return }
                    var instant = Transaction()
                    instant.disablesAnimations = true
                    withTransaction(instant) { browseLayerCollapsed = true }
                }
            } else {
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { browseLayerCollapsed = false }
            }
        }
        .onChange(of: scope) { _, _ in proxy.scrollTo(Self.topAnchor, anchor: .top) }
        // Zakres kategorii żyje tylko w wynikach — bez frazy i filtrów wraca
        // do „Wszystkie”, żeby następne szukanie nie startowało zawężone.
        .onChange(of: isSearchingOrFiltering) { _, active in
            if !active { scope = nil }
        }
        }
        // Pasek szukania wchodzi bezpiecznym obszarem jak pigułka „Cel dnia”
        // w Planie: lista przejeżdża pod szkłem, ale kończy się nad nim.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RecipesSearchBar(
                text: $searchText,
                activeFilterCount: filters.activeCount,
                onSubmit: { debouncedSearchText = searchText },
                onOpenFilters: { isFilterSheetPresented = true }
            )
            .padding(.horizontal, pageHorizontalPadding)
            // Zwija się RAZEM z dolnym menu i tak jak ono (Rafał 4.10.2026:
            // „navigation bar ładnie się zmniejsza, a filters bar już nie”):
            // mniejszy i węższy o tyle, o ile menu, opada o jego spadek.
            // Skala, nie inna wysokość — lista nad paskiem nie skacze.
            .scaleEffect(tabBarChrome.isCompact ? 0.84 : 1, anchor: .bottom)
            .offset(y: tabBarChrome.isCompact ? SCFloatingTabBar.compactionDrop : 0)
            .animation(SCFloatingTabBar.compaction(reduceMotion: reduceMotion), value: tabBarChrome.isCompact)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            // Treść chowa się pod paskiem i menu — rozmyty pas od 28 pt nad
            // paskiem do krawędzi ekranu (`NavigationMenu.ownBottomEdge`).
            .background(alignment: .top) {
                SCScrollEdgeBlur(edge: .bottom, solidFraction: 0.6)
                    .padding(.top, -28)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
        }
    }

    private static let topAnchor = "recipes-top"

    /// Wybór zakładki razem z kierunkiem — oba w tej samej transakcji
    /// (`RecipeScopeTabs` ustawia wybór w `withAnimation`), więc wjazd listy
    /// zna już nowy kierunek.
    private var scopeBinding: Binding<RecipesCategory?> {
        Binding(
            get: { scope },
            set: { newValue in
                scopeForward = Self.scopeIndex(newValue) >= Self.scopeIndex(scope)
                scope = newValue
            }
        )
    }

    private static func scopeIndex(_ scope: RecipesCategory?) -> Int {
        guard let scope, let index = RecipeScopeTabs.scopes.firstIndex(of: scope) else { return 0 }
        return index + 1
    }

    /// Jeden ruch przejść między zwykłym widokiem a wynikami.
    private static let stateMotion: Animation = .smooth(duration: 0.38)

    private var showsBrowseLayer: Bool {
        !shouldShowSkeleton && hasVisibleRecipes
    }

    /// Zakładki kategorii TYLKO w stanie wyników — także nad pustym stanem
    /// (Rafał 4.10.2026: „na głównym widoku nie ma być tab kategorii, tylko
    /// na filtrach globalnych”; „na pustym brakuje mi tab kategorii”).
    private var showsScopeTabs: Bool {
        !shouldShowSkeleton && isResultsMode
    }

    // MARK: - Wyniki

    @ViewBuilder
    private var resultsState: some View {
        let results = resultRecipes
        ZStack(alignment: .top) {
            if results.isEmpty {
                // Pusto: bez nagłówka z „0 przepisów” — tytuł pustego stanu
                // sam mówi, czego szukano.
                resultsEmptyState
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    RecipeResultsHeader(
                        count: results.count,
                        query: debouncedSearchText,
                        filterLabels: filters.summaryLabels,
                        scopeTitle: scope.map(RecipeScopeTabs.title(for:)),
                        onClear: clearResults
                    )
                    .padding(.horizontal, pageHorizontalPadding)
                    .padding(.bottom, 10)

                    // Zmiana zakładki = nowa lista, nie przestawianie wierszy
                    // starej (Rafał 4.10.2026: „przeskakuje, jak się zmienia”):
                    // nowa wjeżdża z kierunku wyboru i przenika nad starą.
                    ZStack(alignment: .top) {
                        RecipeRowStack(recipes: results) { recipe in
                            openDetail(for: recipe)
                        }
                        .id(scope)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(x: scopeForward ? 32 : -32)),
                            removal: .opacity
                        ))
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(Self.stateMotion, value: results.isEmpty)
    }

    /// Pusto w wynikach — najpierw to, co realnie pomaga: trafienia w innych
    /// kategoriach, potem przepisy schowane przez dietę, na końcu
    /// zdejmowanie filtrów i frazy.
    private var resultsEmptyState: some View {
        let query = debouncedSearchText
        let hasQuery = !query.isEmpty
        let hasFilters = filters.activeCount > 0
        let elsewhere = scope == nil ? 0 : unscopedResults.count
        let hiddenByDiet: Int = {
            guard personalization.isEnabled, personalization.restrictsCatalog else { return 0 }
            let withoutDiet = filters.apply(to: searchedRecipes)
            guard let scope else { return withoutDiet.count }
            return withoutDiet.filter { RecipeScopeTabs.contains($0, in: scope) }.count
        }()

        var actions: [RecipeNoResultsView.Action] = []
        if elsewhere > 0 {
            actions.append(.init(
                title: "Wszystkie kategorie · \(elsewhere)",
                icon: "square.grid.2x2"
            ) {
                withAnimation(Self.stateMotion) { scope = nil }
            })
        }
        if hiddenByDiet > 0 {
            actions.append(.init(title: "Pokaż mimo diety", icon: "leaf") {
                withAnimation(Self.stateMotion) { isPersonalizationEnabled = false }
            })
        }
        if hasFilters {
            actions.append(.init(title: "Wyczyść filtry", icon: "line.3.horizontal.decrease") {
                withAnimation(Self.stateMotion) { filters.resetGlobal() }
            })
        }
        if hasQuery {
            actions.append(.init(title: "Wyczyść frazę", icon: "xmark") {
                searchDebounceTask?.cancel()
                withAnimation(Self.stateMotion) {
                    searchText = ""
                    debouncedSearchText = ""
                }
            })
        }
        let onlyScope = !hasQuery && !hasFilters
        if onlyScope, scope != nil {
            actions.append(.init(title: "Wszystkie przepisy", icon: "square.grid.2x2") {
                withAnimation(Self.stateMotion) { scope = nil }
            })
        }

        let title: String
        let message: String
        let icon: String
        if onlyScope {
            icon = RecipesConstants.icon(for: scope ?? .all)
            title = scope == .favourite ? "Brak ulubionych" : "Pusta kategoria"
            message = scope == .favourite
                ? "Serce przy przepisie doda go tutaj."
                : "Nic tu jeszcze nie ma."
        } else {
            icon = hasQuery ? "magnifyingglass" : "line.3.horizontal.decrease"
            title = hasQuery ? "Nic dla „\(query)”" : "Żaden przepis nie pasuje"
            if elsewhere > 0 {
                message = "Są trafienia w innych kategoriach."
            } else if hiddenByDiet > 0 {
                message = "Pasujące przepisy ukrywa Twoja dieta."
            } else if hasQuery && hasFilters {
                message = "Spróbuj innej frazy albo poluzuj filtry."
            } else if hasQuery {
                message = "Wpisz krócej — na przykład sam składnik."
            } else {
                message = "Poluzuj filtry, żeby zobaczyć więcej."
            }
        }

        return RecipeNoResultsView(
            icon: icon,
            accent: scope.map(RecipeScopeTabs.accent(for:)) ?? SCPalette.terracotta,
            title: title,
            message: message,
            actions: actions
        )
        // Nowy powód = nowy widok (krążek podskakuje znowu).
        .id("\(title)|\(message)")
    }

    @ViewBuilder
    private func body(forRecipes _: [Recipe]) -> some View {
        if !featuredRecipes.isEmpty {
            EditorialRecipesHero(eyebrow: heroEyebrow, title: heroTitle)
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.bottom, 14)

            featuredCarousel
                .padding(.bottom, 6)

            if featuredRecipes.count > 1 {
                EditorialRecipesPageDots(
                    count: featuredRecipes.count,
                    activeId: featuredSelectionId,
                    ids: featuredRecipes.map(\.id)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                Color.clear.frame(height: 8)
            }
        }

        VStack(alignment: .leading, spacing: 0) {
            ForEach(mealSections) { section in
                sectionView(section)
            }
        }
    }

    // MARK: - Featured carousel

    private var featuredCarousel: some View {
        // Paging przez `ScrollView(.horizontal)` + `.viewAligned`, NIE przez
        // `TabView(.page)`. TabView pod spodem to UIPageViewController, który
        // ignoruje padding zewnętrzny i rysuje strony w pełnej szerokości
        // ekranu — trzeba mu było wmusić szerokość karty z
        // `UIScreen.main.bounds.width`, czyli zgadywać rozmiar kontenera
        // zamiast go zmierzyć. Stąd gutter karuzeli rozjeżdżał się z
        // rytmem 20pt reszty strony.
        //
        // Każdy element listy to pełnoszerokościowa STRONA (`pageWidth`), a
        // gutter siedzi jako padding WEWNĄTRZ strony. Dzięki temu `.paging`
        // przyciąga do granic stron i karta zawsze ma symetryczne 20pt —
        // przy pierwszej, ostatniej i każdej środkowej tak samo:
        //
        //   ┌──────── strona (= kontener) ────────┐
        //   │←20→│──── karta (page − 2·20) ────│←20→│
        //
        // `GeometryReader` mierzy kontener zamiast go zgadywać, więc rytm
        // trzyma się też przy rotacji, na iPadzie i w Preview. Wysokość jest
        // znana z góry (`cardHeight`), więc greedy GeometryReader nie psuje
        // layoutu pionowego.
        GeometryReader { proxy in
            let pageWidth = proxy.size.width

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(featuredRecipes, id: \.id) { recipe in
                        Button {
                            openDetail(for: recipe)
                        } label: {
                            EditorialRecipeStoryCard(recipe: recipe)
                                .frame(height: EditorialRecipeStoryCard.cardHeight)
                        }
                        .buttonStyle(.plain)
                        // Przytrzymanie → „Udostępnij”; podgląd w kształcie karty.
                        .contentShape(
                            .contextMenuPreview,
                            RoundedRectangle(cornerRadius: EditorialRecipeStoryCard.cornerRadius, style: .continuous)
                        )
                        .recipeShareContextMenu(recipe)
                        // Serce NAD przyciskiem karty, a nie w nim: stuknięcie
                        // przełącza ulubione i nie otwiera szczegółów. Wcześniej
                        // było samym obrazkiem — trafiało w kartę.
                        .overlay(alignment: .topTrailing) {
                            RecipeFavouriteButton(isFavourite: recipe.favourite, style: .photo) { value in
                                Task { await recipeCatalogStore.setFavourite(recipeId: recipe.id, to: value) }
                            }
                            .padding(.top, 8)
                            .padding(.trailing, 8)
                        }
                        .padding(.horizontal, pageHorizontalPadding)
                        .frame(width: pageWidth)
                        .task {
                            await recipeCatalogStore.loadNextPageIfNeeded(
                                currentItemId: recipe.id,
                                threshold: 8
                            )
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $featuredSelectionId)
            .scrollIndicators(.hidden)
        }
        .frame(height: EditorialRecipeStoryCard.cardHeight)
    }

    // MARK: - Section block

    @ViewBuilder
    private func sectionView(_ section: RecipeSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            EditorialRecipesSectionHeader(
                eyebrow: section.eyebrow,
                title: section.title,
                accent: section.accent,
                filterCount: section.filterCount,
                // Sekcję wyzerowaną przez JEJ filtry dalej da się otworzyć —
                // tam się je zdejmuje.
                action: section.recipes.isEmpty && section.filterCount == 0 ? nil : {
                    categorySheetSelection = section.category
                }
            )
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, 22)
            .padding(.bottom, 12)

            if section.recipes.isEmpty {
                emptySectionCard
                    .padding(.horizontal, pageHorizontalPadding)
            } else {
                // Te same wiersze z kreskami (i to samo doczytywanie
                // katalogu), co w liście kategorii i w wyborze do planu.
                RecipeRowStack(recipes: section.recipes) { recipe in
                    openDetail(for: recipe)
                }
            }
        }
    }

    private var emptySectionCard: some View {
        Text("Brak przepisów w tej sekcji.")
            .font(.system(size: 13))
            .foregroundStyle(Color.scMuted(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
    }

    // MARK: - Empty / error / skeleton states

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.18 : 0.10))
                Image(systemName: "fork.knife.circle")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(SCPalette.terracotta)
            }
            .frame(width: 78, height: 78)

            VStack(spacing: 8) {
                Text(isNarrowed ? "Brak wyników" : "Brak przepisów")
                    .font(.system(size: 18, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Color.scLabel(scheme))
                    .multilineTextAlignment(.center)

                Text(emptyStateMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.scMuted(scheme))
                    .multilineTextAlignment(.center)
            }

            if isEmptyBecauseOfPersonalization {
                // Przełącznik „Dopasowane do Ciebie” mieszka w Filtrach, ale
                // pusty ekran przez dietę to jedyna sytuacja, w której trzeba
                // go szukać — więc wyłącza się go stąd jednym stuknięciem.
                Button {
                    withAnimation(.smooth(duration: 0.2)) { isPersonalizationEnabled = false }
                } label: {
                    Text("Pokaż wszystkie przepisy")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(SCPalette.sage)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .scSoftCapsule(SCPalette.sage)
                }
                .buttonStyle(.plain)
            }

            if filters.isActive {
                Button {
                    withAnimation(.smooth(duration: 0.2)) { filters.reset() }
                } label: {
                    Text("Wyczyść filtry")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(SCPalette.terracotta)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        // Wariant „soft” = szkło w tincie terakoty (4.10.2026).
                        .scSoftCapsule()
                }
                .buttonStyle(PlanPressStyle(scale: 0.95))
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
    }

    /// Pusto wyłącznie przez dietę i alergeny z profilu — bez wyszukiwania
    /// i bez filtrów, które same mogłyby wszystko odsiać.
    private var isEmptyBecauseOfPersonalization: Bool {
        !filters.isActive
            && debouncedSearchText.isEmpty
            && personalization.isEnabled
            && personalization.restrictsCatalog
            && hiddenByPersonalizationCount > 0
    }

    private var emptyStateMessage: String {
        if filters.isActive && !debouncedSearchText.isEmpty {
            return "Żaden przepis nie pasuje do frazy i wybranych filtrów."
        }
        if filters.isActive {
            return "Poluzuj filtry, żeby zobaczyć więcej przepisów."
        }
        if !debouncedSearchText.isEmpty {
            return "Spróbuj wpisać inną frazę wyszukiwania."
        }
        // Pusto po samej personalizacji to inny problem niż pusta baza —
        // podpowiadamy przełącznik zamiast kazać czekać na przepisy.
        if isEmptyBecauseOfPersonalization {
            return "Żaden przepis w katalogu nie mieści się w Twojej diecie i alergenach. Dopasowanie wyłączysz tu albo w Filtrach."
        }
        return "Ta baza jest jeszcze pusta — wróć za chwilę."
    }

    private var skeletonState: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Hero placeholder
            HStack(alignment: .center, spacing: 14) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.scTileBg(scheme))
                    .frame(width: 6, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.scTileBg(scheme))
                        .frame(width: 90, height: 11)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.scTileBg(scheme))
                        .frame(width: 200, height: 24)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, pageHorizontalPadding)

            // Story card placeholder
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.scTileBg(scheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.scTileStroke(scheme), lineWidth: 1)
                )
                .frame(height: EditorialRecipeStoryCard.cardHeight)
                .padding(.horizontal, pageHorizontalPadding)
                .redacted(reason: .placeholder)

            // Two section row placeholders
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { _ in
                            HStack(spacing: 14) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.scTileBg(scheme))
                                    .frame(width: 48, height: 48)
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.scTileBg(scheme))
                                        .frame(maxWidth: .infinity, maxHeight: 14, alignment: .leading)
                                        .frame(height: 14)
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.scTileBg(scheme))
                                        .frame(width: 120, height: 10)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, pageHorizontalPadding)
                            .padding(.vertical, 10)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .redacted(reason: .placeholder)
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func makeSection(category: RecipesCategory) -> RecipeSection {
        let categoryRecipes = browseRecipes.filter { $0.category == category }
        let preview = Array(categoryRecipes.prefix(Self.sectionPreviewLimit))
        let categoryFilterCount = filters.categoryFilters[category]?.activeCount ?? 0
        return RecipeSection(
            category: category,
            title: RecipesConstants.displayName(for: category),
            // Zawężona sekcja mówi o tym zamiast hasła — inaczej krótsza
            // lista wyglądałaby na brak przepisów.
            eyebrow: categoryFilterCount > 0
                ? "\(categoryFilterCount) \(PolishPlural.form(categoryFilterCount, one: "filtr", few: "filtry", many: "filtrów")) w tej kategorii"
                : RecipeAccent.eyebrow(for: category),
            accent: RecipeAccent.accent(for: category),
            recipes: preview,
            totalCount: categoryRecipes.count,
            filterCount: categoryFilterCount
        )
    }

    private func openDetail(for recipe: Recipe) {
        Task { @MainActor in
            selectedRecipe = await recipeCatalogStore.loadRecipeDetail(recipeId: recipe.id) ?? recipe
        }
    }

    /// Filtry jednej kategorii jako wiązanie do słownika w `filters` — pusty
    /// wybór znika ze słownika, żeby `isActive` nie widziało pustych wpisów.
    private func categoryFilterBinding(for category: RecipesCategory) -> Binding<RecipeCategoryFilter> {
        Binding(
            get: { filters.categoryFilters[category] ?? RecipeCategoryFilter() },
            set: { newValue in
                withAnimation(.smooth(duration: 0.25)) {
                    filters.categoryFilters[category] = newValue.isActive ? newValue : nil
                }
            }
        )
    }

    /// Stable ordering for the featured carousel.
    private func isFeaturedRecipePreferred(_ lhs: Recipe, _ rhs: Recipe) -> Bool {
        if lhs.favourite != rhs.favourite {
            return lhs.favourite && !rhs.favourite
        }
        if lhs.prepTimeMinutes != rhs.prepTimeMinutes {
            return lhs.prepTimeMinutes < rhs.prepTimeMinutes
        }
        if lhs.servings != rhs.servings {
            return lhs.servings > rhs.servings
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    /// Po przeładowaniu listy / zmianie filtra przewija karuzelę na pierwszą
    /// kartę, jeśli aktualnie wybrana zniknęła z featured. `featuredSelectionId`
    /// jest bindingiem `.scrollPosition`, więc sam zapis wystarcza — dopóki
    /// wybrany przepis nadal jest na liście, zostawiamy pozycję nietkniętą.
    private func resyncFeaturedSelectionIfNeeded() {
        featuredOrder = rankedFeaturedRecipes(from: browseRecipes).map(\.id)
        let ids = featuredRecipes.map(\.id)
        if let current = featuredSelectionId, ids.contains(current) { return }
        featuredSelectionId = ids.first
    }
}

// MARK: - Page dots

// Kropki paginujące pod karuzelą — `8pt` cienki passive, `22pt` szerszy
// aktywny pill w `scLabel`. Source: recipes-v2.jsx W3Dots.
struct EditorialRecipesPageDots: View {
    let count: Int
    let activeId: UUID?
    let ids: [UUID]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { idx in
                let isActive = ids.indices.contains(idx) && ids[idx] == activeId
                Capsule(style: .continuous)
                    .fill(isActive ? Color.scLabel(scheme) : Color.scFaint(scheme))
                    .frame(width: isActive ? 22 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.22), value: activeId)
            }
        }
    }
}

// MARK: - Category sheet

// Arkusz z całą kategorią (chevron przy sekcji). Stoi na tych samych
// klockach, co wybór przepisu do planu (`RecipeListKit.swift`): nagłówek
// z kafelkiem kategorii i liczbą przepisów, szukanie, karta kontekstu,
// wiersze `EditorialRecipeRow`; filtry kategorii pod przyciskiem w nagłówku. Wcześniej miał
// własny nagłówek z kolorowym pionem i poświatą, niższe pole szukania bez
// krzyżyka i podpowiedź „Szukaj w śniadania”.
private struct RecipeCategorySheetView: View {
    let category: RecipesCategory
    /// Przepisy kategorii po dopasowaniu i WSZYSTKICH filtrach, także tej
    /// kategorii — to, co pokazuje lista.
    let recipes: [Recipe]
    /// Przepisy kategorii przed jej własnymi filtrami — do arkusza filtrów
    /// i do „24 z 132” w nagłówku.
    let pool: [Recipe]
    @Binding var categoryFilter: RecipeCategoryFilter
    /// Co działa z arkusza „Filtry” (filtry WSZYSTKICH przepisów) — pusto,
    /// gdy nic. Opis do karty nad listą (`RecipeFilterOptions.summaryLabels`).
    let filterLabels: [String]
    /// Dieta i alergeny z Ustawień — do karty nad listą.
    let personalization: RecipePersonalization
    /// Ile przepisów kategorii ukrywa dieta i alergeny (0 = nic albo
    /// dopasowanie wyłączone). Zmienia tylko kartę — dopasowanie zdejmuje się
    /// w Filtrach, nie tutaj.
    let hiddenByPersonalization: Int
    let onClearFilters: () -> Void

    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var searchText = ""
    @State private var selectedRecipe: Recipe?
    @State private var isFilterSheetPresented = false

    private var accent: Color { RecipeAccent.accent(for: category) }
    private var hasActiveFilters: Bool { !filterLabels.isEmpty }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredRecipes: [Recipe] {
        let query = trimmedSearch
        let source: [Recipe]
        if query.isEmpty {
            source = recipes
        } else {
            source = recipes.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.description.localizedCaseInsensitiveContains(query)
            }
        }
        return source.sorted { lhs, rhs in
            if lhs.favourite != rhs.favourite { return lhs.favourite && !rhs.favourite }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        let rows = filteredRecipes

        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Przypięta góra: nagłówek i szukanie. Uchwyt rysuje
                // `presentationDragIndicator` z `dashboardLiquidSheet()`.
                // Filtry kategorii tylko pod przyciskiem w nagłówku — pigułki
                // pod szukaniem zniknęły w rundzie 10 („od tego mamy filtry”).
                RecipeListSheetTop(
                    searchPrompt: RecipesConstants.searchPrompt(for: category),
                    searchText: $searchText
                ) {
                    EditorialSheetHeader(
                        eyebrow: RecipeAccent.eyebrow(for: category),
                        title: RecipesConstants.displayName(for: category),
                        icon: RecipesConstants.icon(for: category),
                        accent: accent,
                        subtitle: countLine(shown: rows.count),
                        onClose: { dismiss() }
                    ) {
                        RecipeListFilterButton(count: categoryFilter.activeCount, accent: accent) {
                            isFilterSheetPresented = true
                        }
                    }
                }

                ScrollView {
                    VStack(spacing: 0) {
                        let context = contextRows
                        if !context.isEmpty {
                            RecipeListContextCard(rows: context)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)
                        }

                        if rows.isEmpty {
                            emptyState
                                .padding(.horizontal, 20)
                                .padding(.top, 4)
                        } else {
                            RecipeRowStack(recipes: rows, accent: accent) { recipe in
                                openDetail(for: recipe)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .scScrollEdgeFade()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // Szczegół otwiera się NAD tym arkuszem — jak AddToPlanSheet nad
        // szczegółem przepisu. Zamknięcie szczegółu wraca na listę kategorii,
        // zamiast wyrzucać użytkownika na sam ekran Przepisów.
        .sheet(item: $selectedRecipe) { selected in
            RecipeDetailView(
                // Jak na Przepisach: żywy przepis z katalogu i zapis wartości.
                recipe: recipeCatalogStore.recipes.first(where: { $0.id == selected.id }) ?? selected,
                onSetFavourite: { value in
                    Task { await recipeCatalogStore.setFavourite(recipeId: selected.id, to: value) }
                },
                onClose: { selectedRecipe = nil },
                onAddedToPlan: { _, _ in selectedRecipe = nil }
            )
            .recipeDetailSheet()
        }
        .sheet(isPresented: $isFilterSheetPresented) {
            RecipeCategoryFilterSheet(category: category, recipes: pool, filter: $categoryFilter)
                .presentationDetents([.large])
                .dashboardLiquidSheet()
        }
    }

    private func openDetail(for recipe: Recipe) {
        Task { @MainActor in
            selectedRecipe = await recipeCatalogStore.loadRecipeDetail(recipeId: recipe.id) ?? recipe
        }
    }

    /// „132 przepisy”, a gdy filtry kategorii albo szukanie zawężają — „24 z 132
    /// przepisów” (po „z” dopełniacz).
    private func countLine(shown: Int) -> String {
        let total = pool.count
        let count = shown == total
            ? PolishPlural.recipes(total)
            : "\(shown) z \(total) \(total == 1 ? "przepisu" : "przepisów")"
        guard let diet = dietNote else { return count }
        return count + " · " + diet
    }

    /// Dieta z Ustawień jako dopisek w podtytule nagłówka („dieta
    /// wegetariańska”), a nie osobna karta nad listą — runda 12, Rafał:
    /// „usuń info o dieta, wrzuć to jakoś inaczej”. `nil`, gdy dopasowanie
    /// niczego w tej kategorii nie ukrywa.
    private var dietNote: String? {
        guard personalization.isEnabled, personalization.restrictsCatalog,
              hiddenByPersonalization > 0 else { return nil }
        if personalization.diet != .none {
            return "dieta " + personalization.diet.title.lowercased()
        }
        return "bez Twoich alergenów"
    }

    // MARK: - Karta kontekstu

    /// Co zawęża tę listę spoza arkusza: dieta z Ustawień i filtry
    /// z Przepisów. Bez tego znikające przepisy wyglądałyby na brakujące
    /// dane, a nie na skutek ustawienia z innego ekranu.
    private var contextRows: [RecipeListContextCard.Row] {
        // Dieta mieszka w podtytule nagłówka (`dietNote`); karta mówi już
        // tylko o filtrach z Przepisów, które da się stąd zdjąć.
        let rows: [RecipeListContextCard.Row?] = [
            .filters(filterLabels, onClear: onClearFilters)
        ]
        return rows.compactMap { $0 }
    }

    // MARK: - Pusty stan

    /// Co opróżniło listę i jak to zdjąć — ten sam układ, co w wyborze
    /// przepisu do planu (`RecipeListEmptyState`).
    private var emptyState: some View {
        var actions: [RecipeListEmptyState.Action] = []
        if categoryFilter.isActive {
            actions.append(.init(title: "Wyczyść filtry kategorii") {
                withAnimation(.smooth(duration: 0.2)) { categoryFilter = RecipeCategoryFilter() }
            })
        }
        if hasActiveFilters {
            actions.append(.init(title: "Wyczyść filtry z Przepisów", run: onClearFilters))
        }

        if !trimmedSearch.isEmpty {
            return RecipeListEmptyState(
                icon: "magnifyingglass",
                accent: accent,
                title: "Brak wyników",
                message: "Nic w tej kategorii nie pasuje do frazy. Spróbuj innej.",
                actions: actions
            )
        }
        return RecipeListEmptyState(
            icon: "line.3.horizontal.decrease",
            accent: accent,
            title: "Nic nie pasuje",
            message: "Żaden przepis w tej kategorii nie przechodzi przez filtry i Twoją dietę.",
            actions: actions
        )
    }
}

// MARK: - Nav bar passthrough

// Wyłącza interakcję `UINavigationBar` żeby tapy padały na content pod
// nim — taki sam shim jak w Kalendarzu / Produktach / Ustawieniach (każdy
// widok ma własną kopię, żeby uniknąć importu prywatnego pliku).
private struct NavBarHitTestPassthrough: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { BarUnlocker() }
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
    RecipesView()
}
