import Combine
import SwiftUI

// Przepisy v2 — "Story carousel + Tasting menu" (W3 z handoff design'u).
// Source: design/Scoffie - Przepisy.html → recipes-v2.jsx RecipesV2_W3.
//
// Layout (top → bottom):
//   1. EditorialRecipesHeader  — tytuł "Przepisy" + pigułka wyszukiwarki
//   2. EditorialRecipesHero    — eyebrow + "Smaki na dziś" z terakotowym pionem
//   3. Karuzela kart-story     — pełna szerokość, paging, kropki
//   4. Sekcje Tasting menu     — po jednej na `RecipesCategory.catalogSections`
//      (Śniadania / Obiady / Kolacje / Przekąski i desery), każda z
//      EditorialRecipesSectionHeader nad listą EditorialRecipeRow
//
// Stylistyka i paddings idą za pozostałymi widokami v2 (Ustawienia, Produkty,
// Kalendarz): `SCPageBackground`, `pageTopPadding=78`, `pageHorizontalPadding=20`,
// `pageBottomPadding=40`, hide-and-passthrough na NavigationBar.
struct RecipesView: View {
    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

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

    /// Ile przepisów zabrała sama dieta / alergeny — do podpisu w banerze.
    private var hiddenByPersonalizationCount: Int {
        personalization.hiddenCount(in: searchedRecipes)
    }

    /// Czy lista jest w ogóle zawężona — steruje tekstem pustego stanu i
    /// zwijaniem pustych sekcji Tasting menu.
    private var isNarrowed: Bool {
        !debouncedSearchText.isEmpty
            || filters.isActive
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

    /// Karty karuzeli: zamrożona kolejność (`featuredOrder`) z bieżącymi
    /// danymi przepisów. Przepis, który zniknął z listy (np. odlubiony przy
    /// filtrze „Ulubione”), znika też z karuzeli.
    private var featuredRecipes: [Recipe] {
        let visible = visibleRecipes
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
        if !debouncedSearchText.isEmpty { return "Najlepsze dopasowanie" }
        if filters.isActive { return "Twoje filtry" }
        if personalization.isEnabled, personalization.ranksCatalog {
            return "Pod cel: \(personalization.goal.title)"
        }
        return "Polecane"
    }

    private var heroTitle: String {
        if !debouncedSearchText.isEmpty { return "Pasujące do wyszukiwania" }
        if filters.isActive { return "Wybrane dla Ciebie" }
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
                ImagePrefetcher.prefetch(recipeCatalogStore.recipes.compactMap(\.imageURL))
                resyncFeaturedSelectionIfNeeded()
            }
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    debouncedSearchText = newValue
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
                .presentationDetents([.large])
                .dashboardLiquidSheet(cornerRadius: 40)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialRecipesHeader(
                    searchText: $searchText,
                    activeFilterCount: filters.activeCount,
                    onSubmit: { debouncedSearchText = searchText },
                    onOpenFilters: { isFilterSheetPresented = true }
                )
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.top, pageTopPadding)
                .padding(.bottom, 18)

                // Szkielet → dane przenika, nie skacze (pierwsze wejście
                // po uruchomieniu aplikacji).
                Group {
                    if shouldShowSkeleton {
                        skeletonState
                            .transition(.opacity)
                    } else if !hasVisibleRecipes {
                        emptyState
                            .padding(.horizontal, pageHorizontalPadding)
                            .padding(.top, 8)
                            .transition(.opacity)
                    } else {
                        body(forRecipes: visibleRecipes)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.3), value: shouldShowSkeleton)

                if recipeCatalogStore.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                }
            }
            .padding(.bottom, pageBottomPadding)
        }
        .scrollIndicators(.hidden)
        // Kierunek przewijania steruje zwijaniem dolnego menu.
        .scTracksTabBarCompaction()
        .ignoresSafeArea(.container, edges: .top)
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
                action: section.recipes.isEmpty ? nil : {
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
                        .background(Capsule().fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.18 : 0.10)))
                        .overlay(Capsule().stroke(SCPalette.terracotta.opacity(0.32), lineWidth: 1))
                }
                .buttonStyle(.plain)
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
        let categoryRecipes = visibleRecipes.filter { $0.category == category }
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
            totalCount: categoryRecipes.count
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
        featuredOrder = rankedFeaturedRecipes(from: visibleRecipes).map(\.id)
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
            .presentationDetents([.large])
            .dashboardLiquidSheet(cornerRadius: 40)
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
        guard shown != total else { return PolishPlural.recipes(total) }
        return "\(shown) z \(total) \(total == 1 ? "przepisu" : "przepisów")"
    }

    // MARK: - Karta kontekstu

    /// Co zawęża tę listę spoza arkusza: dieta z Ustawień i filtry
    /// z Przepisów. Bez tego znikające przepisy wyglądałyby na brakujące
    /// dane, a nie na skutek ustawienia z innego ekranu.
    private var contextRows: [RecipeListContextCard.Row] {
        let rows: [RecipeListContextCard.Row?] = [
            .personalization(personalization, hidden: hiddenByPersonalization),
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
