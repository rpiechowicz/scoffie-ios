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

    /// Top-N najlepszych kandydatów do karuzeli featured. Ulubione wygrywają,
    /// potem krótszy `prepTime`, potem większy `servings`, potem alfabetycznie.
    private var featuredRecipes: [Recipe] {
        // Gdy cel porządkuje katalog, `visibleRecipes` są już ułożone od
        // najlepiej dopasowanych — drugie sortowanie po `prepTime` tylko by to
        // zepsuło. Bez celu zostaje dotychczasowa heurystyka.
        let ranked = (personalization.isEnabled && personalization.ranksCatalog)
            ? visibleRecipes
            : visibleRecipes.sorted(by: isFeaturedRecipePreferred(_:_:))

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
                    recipe: selected,
                    onToggleFavorite: {
                        Task {
                            await recipeCatalogStore.toggleFavorite(recipeId: selected.id)
                            selectedRecipe = recipeCatalogStore.recipes.first(where: { $0.id == selected.id })
                        }
                    },
                    onClose: { selectedRecipe = nil },
                    // Katalog nie zna żadnego slotu, więc szczegół otwiera się
                    // na jednej porcji i to stepper decyduje, ile ich będzie.
                    onAddedToPlan: { _, _ in selectedRecipe = nil }
                )
                .presentationDetents([.large])
                .dashboardLiquidSheet()
            }
            .sheet(item: $categorySheetSelection) { category in
                let inCategory = personalization.apply(
                    to: recipeCatalogStore.recipes.filter { $0.category == category }
                )
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
                    hasActiveFilters: filters.activeCount > 0,
                    isPersonalized: personalization.isEnabled && personalization.restrictsCatalog,
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
                VStack(spacing: 0) {
                    ForEach(Array(section.recipes.enumerated()), id: \.element.id) { idx, recipe in
                        EditorialRecipeRow(
                            recipe: recipe,
                            action: { openDetail(for: recipe) }
                        )
                        .task {
                            await recipeCatalogStore.loadNextPageIfNeeded(
                                currentItemId: recipe.id,
                                threshold: 8
                            )
                        }

                        if idx < section.recipes.count - 1 {
                            Rectangle()
                                .fill(Color.scRule(scheme))
                                .frame(height: 1)
                                .padding(.leading, pageHorizontalPadding + 48 + 14)
                                .padding(.trailing, pageHorizontalPadding)
                        }
                    }
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

// Sheet pełnoekranowy z listą przepisów w danej kategorii. Source:
// recipes-v2.jsx W3SectionSheet — header z kolorowym pionem, search,
// scrollowana lista RowC.
private struct RecipeCategorySheetView: View {
    let category: RecipesCategory
    let recipes: [Recipe]
    /// Przepisy kategorii przed jej własnymi filtrami — do arkusza filtrów.
    let pool: [Recipe]
    @Binding var categoryFilter: RecipeCategoryFilter
    /// Czy działają filtry WSZYSTKICH przepisów (z arkusza „Filtry”).
    let hasActiveFilters: Bool
    /// Czy pula przyszła już zawężona dietą / alergenami. Zmienia tylko
    /// treść notki — dopasowanie zdejmuje się na ekranie listy, nie tutaj.
    let isPersonalized: Bool
    let onClearFilters: () -> Void

    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var searchText = ""
    @State private var selectedRecipe: Recipe?
    @State private var isFilterSheetPresented = false

    private var accent: Color { RecipeAccent.accent(for: category) }

    private var filteredRecipes: [Recipe] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let source: [Recipe]
        if trimmed.isEmpty {
            source = recipes
        } else {
            source = recipes.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.description.localizedCaseInsensitiveContains(trimmed)
            }
        }
        return source.sorted { lhs, rhs in
            if lhs.favourite != rhs.favourite { return lhs.favourite && !rhs.favourite }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    // Uchwyt rysuje `presentationDragIndicator` z
                    // `dashboardLiquidSheet()`; własna kapsułka dokładała nad
                    // nim drugą belkę. Odstęp jak w pozostałych arkuszach.
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                sheetSearchPill
                    .padding(.horizontal, 20)
                    .padding(.bottom, (hasActiveFilters || isPersonalized) ? 14 : 12)

                if hasActiveFilters || isPersonalized {
                    activeFiltersNote
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }

                if filteredRecipes.isEmpty {
                    emptyState
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredRecipes.enumerated()), id: \.element.id) { idx, recipe in
                                EditorialRecipeRow(
                                    recipe: recipe,
                                    action: { openDetail(for: recipe) }
                                )

                                if idx < filteredRecipes.count - 1 {
                                    Rectangle()
                                        .fill(Color.scRule(scheme))
                                        .frame(height: 1)
                                        .padding(.leading, 20 + 48 + 14)
                                        .padding(.trailing, 20)
                                }
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    .scrollIndicators(.hidden)
                    .scScrollEdgeFade()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // Szczegół otwiera się NAD tym arkuszem — jak AddToPlanSheet nad
        // szczegółem przepisu. Zamknięcie szczegółu wraca na listę kategorii,
        // zamiast wyrzucać użytkownika na sam ekran Przepisów.
        .sheet(item: $selectedRecipe) { selected in
            RecipeDetailView(
                recipe: selected,
                onToggleFavorite: {
                    Task {
                        await recipeCatalogStore.toggleFavorite(recipeId: selected.id)
                        selectedRecipe = recipeCatalogStore.recipes.first(where: { $0.id == selected.id })
                    }
                },
                onClose: { selectedRecipe = nil },
                onAddedToPlan: { _, _ in selectedRecipe = nil }
            )
            .presentationDetents([.large])
            .dashboardLiquidSheet()
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

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Capsule(style: .continuous)
                .fill(accent)
                .frame(width: 5, height: 36)
                .shadow(color: accent.opacity(scheme == .dark ? 0.55 : 0.32), radius: 10, x: 0, y: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(RecipeAccent.eyebrow(for: category).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(accent)

                Text(RecipesConstants.displayName(for: category))
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Color.scLabel(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Filtry tej kategorii — ten sam krążek co krzyżyk, glif jak na
            // przycisku filtrów na Przepisach; zawężona kategoria świeci
            // akcentem i nosi liczbę zaznaczonych opcji.
            SCSheetIconButton(
                systemName: "line.3.horizontal.decrease",
                tint: categoryFilter.isActive ? accent : nil,
                accessibilityLabel: categoryFilter.isActive
                    ? "Filtry kategorii, zaznaczone: \(categoryFilter.activeCount)"
                    : "Filtry kategorii"
            ) {
                isFilterSheetPresented = true
            }
            .scCountBadge(categoryFilter.activeCount, color: accent)

            SCSheetCloseButton { dismiss() }
        }
    }

    // Bez tej notki znikające przepisy wyglądałyby na brakujące dane, a nie
    // na skutek filtra ustawionego ekran wyżej.
    private var activeFiltersNote: some View {
        HStack(spacing: 8) {
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease" : "wand.and.stars")
                .font(.system(size: 11, weight: .bold))

            Text(activeFiltersNoteTitle)
                .font(.system(size: 12, weight: .semibold))

            Spacer(minLength: 8)

            if hasActiveFilters {
                Button(action: onClearFilters) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .heavy))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.22 : 0.14)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wyczyść filtry")
            }
        }
        .foregroundStyle(SCPalette.terracotta)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.16 : 0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SCPalette.terracotta.opacity(0.28), lineWidth: 1)
        )
    }

    private var activeFiltersNoteTitle: String {
        switch (hasActiveFilters, isPersonalized) {
        case (true, true):   return "Lista zawężona filtrami i Twoją dietą"
        case (true, false):  return "Lista zawężona filtrami"
        default:             return "Lista zawężona Twoją dietą"
        }
    }

    private var sheetSearchPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.scMuted(scheme).opacity(0.7))

            TextField(text: $searchText) {
                Text("Szukaj w \(RecipesConstants.displayName(for: category).lowercased())")
                    .foregroundStyle(Color.scMuted(scheme).opacity(0.7))
            }
            .font(.system(size: 15))
            .tracking(-0.2)
            .foregroundStyle(Color.scLabel(scheme))
            .submitLabel(.search)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous).fill(Color.scTileBg(scheme))
        )
        .overlay(
            Capsule(style: .continuous).stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.scMuted(scheme))

            Text("Brak wyników")
                .font(.system(size: 16, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(Color.scLabel(scheme))

            Text((hasActiveFilters || isPersonalized || categoryFilter.isActive)
                 && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? "Żaden przepis w tej kategorii nie przechodzi przez filtry i Twoje preferencje."
                 : "Spróbuj innej frazy wyszukiwania.")
                .font(.system(size: 13))
                .foregroundStyle(Color.scMuted(scheme))
                .multilineTextAlignment(.center)

            if categoryFilter.isActive {
                Button {
                    withAnimation(.smooth(duration: 0.2)) { categoryFilter = RecipeCategoryFilter() }
                } label: {
                    Text("Wyczyść filtry kategorii")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .scSoftCapsule(accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
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
