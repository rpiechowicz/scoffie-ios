import SwiftUI

// Przepisy v2 — "Story carousel + Tasting menu" (W3 z handoff design'u).
// Source: design/Weekly Meals - Przepisy.html → recipes-v2.jsx RecipesV2_W3.
//
// Layout (top → bottom):
//   1. EditorialRecipesHeader  — tytuł "Przepisy" + pigułka wyszukiwarki
//   2. EditorialRecipesHero    — eyebrow + "Smaki na dziś" z terakotowym pionem
//   3. Karuzela kart-story     — pełna szerokość, paging, kropki
//   4. Sekcje Tasting menu     — Śniadania / Obiady / Kolacje, każdy z
//      EditorialRecipesSectionHeader nad listą EditorialRecipeRow
//
// Stylistyka i paddings idą za pozostałymi widokami v2 (Ustawienia, Produkty,
// Kalendarz): `WMPageBackground`, `pageTopPadding=78`, `pageHorizontalPadding=20`,
// `pageBottomPadding=40`, hide-and-passthrough na NavigationBar.
struct RecipesView: View {
    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.colorScheme) private var scheme

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var selectedRecipe: Recipe?
    @State private var categorySheetSelection: RecipesCategory?
    @State private var featuredSelectionId: UUID?
    @State private var filters = RecipeFilterOptions()
    @State private var isFilterSheetPresented = false
    @State private var isPersonalizationSheetPresented = false

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

    /// Ile przepisów zabiera dieta / alergeny w CAŁYM katalogu. Arkusz
    /// „Dopasowanie” mówi o ustawieniu globalnym, więc jego liczby nie mogą
    /// się zmieniać, gdy ktoś wpisze coś w wyszukiwarkę.
    private var hiddenInCatalogCount: Int {
        personalization.hiddenCount(in: recipeCatalogStore.recipes)
    }

    /// Czy katalog w ogóle niesie składniki. Bez nich klasyfikator diety nie
    /// ma czego czytać i arkusz musi to powiedzieć wprost, zamiast twierdzić,
    /// że wszystko pasuje.
    private var hasIngredientCoverage: Bool {
        recipeCatalogStore.recipes.contains { !$0.ingredients.isEmpty }
    }

    /// Czy lista jest w ogóle zawężona — steruje tekstem pustego stanu i
    /// zwijaniem pustych sekcji Tasting menu.
    private var isNarrowed: Bool {
        !debouncedSearchText.isEmpty
            || filters.isActive
            || (personalization.isEnabled && personalization.restrictsCatalog)
    }

    private var mealSections: [RecipeSection] {
        let base: [RecipeSection] = [
            makeSection(category: .breakfast, title: "Śniadania"),
            makeSection(category: .lunch,     title: "Obiady"),
            makeSection(category: .dinner,    title: "Kolacje")
        ]
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
        if personalization.isEnabled, personalization.ranksCatalog {
            return Array(visibleRecipes.prefix(5))
        }
        return Array(
            visibleRecipes
                .sorted(by: isFeaturedRecipePreferred(_:_:))
                .prefix(5)
        )
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

    private var shouldShowSkeleton: Bool {
        recipeCatalogStore.isLoading && recipeCatalogStore.recipes.isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                WMPageBackground(scheme: scheme)
                    .ignoresSafeArea()

                content
            }
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
            .onDisappear { searchDebounceTask?.cancel() }
            .sheet(isPresented: $isFilterSheetPresented) {
                RecipeFilterSheet(filters: $filters, recipes: personalizedRecipes)
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
                    onClose: { selectedRecipe = nil }
                )
                .presentationDetents([.large])
                .dashboardLiquidSheet()
            }
            .sheet(item: $categorySheetSelection) { category in
                RecipeCategorySheetView(
                    category: category,
                    // Filtry z arkusza „Filtry” obowiązują też tutaj — inaczej
                    // chevron „zobacz wszystkie” cofałby zawężenie i pokazywał
                    // przepisy, które użytkownik przed chwilą odsiał.
                    // Wyszukiwarka zostaje poza tym celowo: ten arkusz ma
                    // własną, do przeszukiwania kategorii.
                    recipes: filters.apply(
                        to: personalization.apply(
                            to: recipeCatalogStore.recipes.filter { $0.category == category }
                        )
                    ),
                    hasActiveFilters: filters.isActive,
                    isPersonalized: personalization.isEnabled && personalization.restrictsCatalog,
                    onClearFilters: { withAnimation(.smooth(duration: 0.2)) { filters.reset() } },
                    onSelect: openDetail(for:)
                )
                .presentationDetents([.large])
                .dashboardLiquidSheet()
            }
            .sheet(isPresented: $isPersonalizationSheetPresented) {
                RecipePersonalizationSheet(
                    personalization: personalization,
                    catalog: recipeCatalogStore.recipes,
                    canEvaluateDiet: hasIngredientCoverage,
                    isEnabled: $isPersonalizationEnabled,
                    onClose: { isPersonalizationSheetPresented = false }
                )
                // Jedyny arkusz na tym ekranie, który nie jest listą — treści
                // jest na pół ekranu, więc `.large` zostawiałby pustą dolną
                // połowę. `.medium` otwiera go w rozmiarze treści, `.large`
                // zostaje na duży krój systemowy.
                .presentationDetents([.medium, .large])
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
                    isPersonalizationEnabled: isPersonalizationEnabled,
                    isPersonalizationActive: personalization.isActive,
                    hiddenRecipeCount: hiddenInCatalogCount,
                    onSubmit: { debouncedSearchText = searchText },
                    onOpenFilters: { isFilterSheetPresented = true },
                    onOpenPersonalization: { isPersonalizationSheetPresented = true }
                )
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.top, pageTopPadding)
                .padding(.bottom, 18)

                if let errorMessage = recipeCatalogStore.errorMessage, !errorMessage.isEmpty {
                    errorBanner(errorMessage)
                        .padding(.horizontal, pageHorizontalPadding)
                        .padding(.bottom, 12)
                }

                if shouldShowSkeleton {
                    skeletonState
                } else if !hasVisibleRecipes {
                    emptyState
                        .padding(.horizontal, pageHorizontalPadding)
                        .padding(.top, 8)
                } else {
                    body(forRecipes: visibleRecipes)
                }

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
                                .fill(Color.wmRule(scheme))
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
            .foregroundStyle(Color.wmMuted(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.wmTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
            )
    }

    // MARK: - Empty / error / skeleton states

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(WMPalette.terracotta.opacity(scheme == .dark ? 0.18 : 0.10))
                Image(systemName: "fork.knife.circle")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(WMPalette.terracotta)
            }
            .frame(width: 78, height: 78)

            VStack(spacing: 8) {
                Text(isNarrowed ? "Brak wyników" : "Brak przepisów")
                    .font(.system(size: 18, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .multilineTextAlignment(.center)

                Text(emptyStateMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .multilineTextAlignment(.center)
            }

            if filters.isActive {
                Button {
                    withAnimation(.smooth(duration: 0.2)) { filters.reset() }
                } label: {
                    Text("Wyczyść filtry")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WMPalette.terracotta)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(WMPalette.terracotta.opacity(scheme == .dark ? 0.18 : 0.10)))
                        .overlay(Capsule().stroke(WMPalette.terracotta.opacity(0.32), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
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
        if personalization.isEnabled, personalization.restrictsCatalog, hiddenByPersonalizationCount > 0 {
            return "Żaden przepis w katalogu nie mieści się w Twojej diecie i alergenach. Stuknij ikonę dopasowania obok tytułu, żeby je wyłączyć."
        }
        return "Ta baza jest jeszcze pusta — wróć za chwilę."
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.red.opacity(scheme == .dark ? 0.14 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.red.opacity(0.32), lineWidth: 1)
            )
    }

    private var skeletonState: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Hero placeholder
            HStack(alignment: .center, spacing: 14) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.wmTileBg(scheme))
                    .frame(width: 6, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.wmTileBg(scheme))
                        .frame(width: 90, height: 11)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.wmTileBg(scheme))
                        .frame(width: 200, height: 24)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, pageHorizontalPadding)

            // Story card placeholder
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.wmTileBg(scheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
                )
                .frame(height: 420)
                .padding(.horizontal, pageHorizontalPadding)
                .redacted(reason: .placeholder)

            // Two section row placeholders
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { _ in
                            HStack(spacing: 14) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.wmTileBg(scheme))
                                    .frame(width: 48, height: 48)
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.wmTileBg(scheme))
                                        .frame(maxWidth: .infinity, maxHeight: 14, alignment: .leading)
                                        .frame(height: 14)
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.wmTileBg(scheme))
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

    private func makeSection(category: RecipesCategory, title: String) -> RecipeSection {
        let categoryRecipes = visibleRecipes.filter { $0.category == category }
        let preview = Array(categoryRecipes.prefix(Self.sectionPreviewLimit))
        return RecipeSection(
            category: category,
            title: title,
            eyebrow: RecipeAccent.eyebrow(for: category),
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
// aktywny pill w `wmLabel`. Source: recipes-v2.jsx W3Dots.
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
                    .fill(isActive ? Color.wmLabel(scheme) : Color.wmFaint(scheme))
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
    let hasActiveFilters: Bool
    /// Czy pula przyszła już zawężona dietą / alergenami. Zmienia tylko
    /// treść notki — dopasowanie zdejmuje się na ekranie listy, nie tutaj.
    let isPersonalized: Bool
    let onClearFilters: () -> Void
    let onSelect: (Recipe) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var searchText = ""

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
            WMPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                grabber

                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
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
                                    action: {
                                        dismiss()
                                        // Defer the detail open so the sheet
                                        // dismissal can finish without the
                                        // detail sheet stacking on top.
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                            onSelect(recipe)
                                        }
                                    }
                                )

                                if idx < filteredRecipes.count - 1 {
                                    Rectangle()
                                        .fill(Color.wmRule(scheme))
                                        .frame(height: 1)
                                        .padding(.leading, 20 + 48 + 14)
                                        .padding(.trailing, 20)
                                }
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var grabber: some View {
        Capsule()
            .fill(Color.wmFaint(scheme))
            .frame(width: 38, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 6)
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
                    .foregroundStyle(Color.wmLabel(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color.wmLabel(scheme))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.wmFeatureRowBg(scheme)))
                    .overlay(Circle().stroke(Color.wmTileStroke(scheme), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zamknij")
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
                        .background(Circle().fill(WMPalette.terracotta.opacity(scheme == .dark ? 0.22 : 0.14)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wyczyść filtry")
            }
        }
        .foregroundStyle(WMPalette.terracotta)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WMPalette.terracotta.opacity(scheme == .dark ? 0.16 : 0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WMPalette.terracotta.opacity(0.28), lineWidth: 1)
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
                .foregroundStyle(Color.wmMuted(scheme).opacity(0.7))

            TextField(text: $searchText) {
                Text("Szukaj w \(RecipesConstants.displayName(for: category).lowercased())")
                    .foregroundStyle(Color.wmMuted(scheme).opacity(0.7))
            }
            .font(.system(size: 15))
            .tracking(-0.2)
            .foregroundStyle(Color.wmLabel(scheme))
            .submitLabel(.search)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous).fill(Color.wmTileBg(scheme))
        )
        .overlay(
            Capsule(style: .continuous).stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.wmMuted(scheme))

            Text("Brak wyników")
                .font(.system(size: 16, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(Color.wmLabel(scheme))

            Text((hasActiveFilters || isPersonalized) && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? "Żaden przepis w tej kategorii nie przechodzi przez filtry i Twoje preferencje."
                 : "Spróbuj innej frazy wyszukiwania.")
                .font(.system(size: 13))
                .foregroundStyle(Color.wmMuted(scheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
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
