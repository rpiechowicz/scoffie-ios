import SwiftUI

// Cała kategoria (Śniadania, Obiady, Kolacje, Przekąski i desery) jako
// ekran WPCHNIĘTY do stosu Przepisów — nagłówek sekcji na Przepisach
// (6.10.2026, „jak od Apple”: najwyżej jeden arkusz, dalsze kroki to push).
// Wcześniej był to arkusz z własnym polem szukania i własnym przyciskiem
// filtrów, a szczegół przepisu otwierał się NAD nim drugim arkuszem, „Dodaj
// do planu” trzecim.
//
// Systemowy pasek nawigacji z dużym tytułem i „wstecz”. Pod nim liczba
// przepisów (z dopiskiem o diecie, gdy coś ukrywa), żeton „Bez dopasowania”,
// karta filtrów i ta sama lista, co w sekcjach (`RecipeRowStack`). Na dole ten
// sam pływający pasek szukania, co na korzeniu Przepisów — tu szuka W TEJ
// KATEGORII, a przycisk filtrów otwiera wspólne „Filtry” z sekcją tej
// kategorii (rodzaj dania, smak, mięso). Szczegół przepisu
// to jeden arkusz, otwierany przez korzeń (`onOpenRecipe`), jak z głównej listy.
struct RecipeCategoryScreen: View {
    let category: RecipesCategory
    @Binding var filters: RecipeFilterOptions
    /// Fraza tej kategorii — trzyma ją `RecipesView` (czyści przy wyjściu).
    @Binding var searchText: String
    let onOpenRecipe: (Recipe) -> Void
    let onOpenFilters: () -> Void

    init(
        category: RecipesCategory,
        filters: Binding<RecipeFilterOptions>,
        searchText: Binding<String>,
        onOpenRecipe: @escaping (Recipe) -> Void,
        onOpenFilters: @escaping () -> Void
    ) {
        self.category = category
        self._filters = filters
        self._searchText = searchText
        self.onOpenRecipe = onOpenRecipe
        self.onOpenFilters = onOpenFilters
    }

    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.colorScheme) private var scheme

    // Te same klucze, co na korzeniu Przepisów — ekran czyta je sam, więc
    // zmiana dopasowania (żeton, różdżka w Filtrach) przelicza go od razu.
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

    private var accent: Color { RecipeAccent.accent(for: category) }

    private var personalization: RecipePersonalization {
        RecipePersonalization(
            dietRaw: dietPreferenceRaw,
            allergensRaw: allergensRaw,
            goalRaw: goalRaw,
            calorieGoal: calorieGoal,
            isEnabled: isPersonalizationEnabled
        )
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Grupy filtrów, które zawężają TĘ listę (filtry wszystkich przepisów
    /// i aspekty tej kategorii) — plakietka na przycisku filtrów.
    private var activeFilterCount: Int {
        filters.activeCount(in: category)
    }

    /// Czy filtry cokolwiek tu zawężają.
    private var hasFilters: Bool { activeFilterCount > 0 }

    // MARK: - Body

    var body: some View {
        let all = recipeCatalogStore.recipes.filter { $0.category == category }
        let fitted = personalization.apply(to: all)
        let rows = RecipeTextSearch.ordered(
            filters.apply(to: RecipeTextSearch.filter(fitted, query: query)),
            query: query
        )

        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(countLine(shown: rows.count, total: fitted.count, hidden: personalization.hiddenCount(in: all)))
                        .font(.sc(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.scMuted(scheme))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    if personalization.isBypassed {
                        RecipeFitOffChip {
                            withAnimation(.smooth(duration: 0.3)) { isPersonalizationEnabled = true }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topLeading)))
                    }

                    if let filtersRow = filtersContextRow {
                        RecipeListContextCard(rows: [filtersRow])
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                            .transition(.opacity)
                    }

                    if rows.isEmpty {
                        emptyState(categoryIsEmpty: all.isEmpty, fittedIsEmpty: fitted.isEmpty)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .transition(.opacity)
                    } else {
                        RecipeRowStack(recipes: rows, accent: accent) { recipe in
                            onOpenRecipe(recipe)
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 24)
                .animation(.smooth(duration: 0.3), value: rows.isEmpty)
                .animation(.smooth(duration: 0.3), value: personalization.isBypassed)
            }
            .scrollIndicators(.hidden)
            // Przewinięcie listy chowa klawiaturę — jak na korzeniu.
            .scrollDismissesKeyboard(.immediately)
            // Pod systemowym paskiem — miękka krawędź, bez kreski.
            .scrollEdgeEffectStyle(.soft, for: .top)
            // Ten sam pływający pasek, przyczepiony tą samą drogą co na korzeniu
            // Przepisów (`recipesSearchDock`).
            .recipesSearchDock(
                RecipesSearchBar(
                    text: $searchText,
                    prompt: RecipesConstants.searchPrompt(for: category),
                    activeFilterCount: activeFilterCount,
                    onOpenFilters: onOpenFilters
                ),
                horizontalPadding: 20
            )
        }
        .navigationTitle(RecipesConstants.displayName(for: category))
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
    }

    // MARK: - Liczba

    /// „132 przepisy”, a gdy szukanie albo filtry zawężają — „24 z 132
    /// przepisów” (po „z” dopełniacz). Dieta z Ustawień stoi tu dopiskiem
    /// („· dieta wegetariańska”), a nie osobną kartą — runda 12, Rafał: „usuń
    /// info o dieta, wrzuć to jakoś inaczej”.
    private func countLine(shown: Int, total: Int, hidden: Int) -> String {
        let count = shown == total
            ? PolishPlural.recipes(total)
            : "\(shown) z \(total) \(total == 1 ? "przepisu" : "przepisów")"
        guard personalization.isEnabled, personalization.restrictsCatalog, hidden > 0 else { return count }
        if personalization.diet != .none {
            return count + " · dieta " + personalization.diet.title.lowercased()
        }
        return count + " · bez Twoich alergenów"
    }

    // MARK: - Karta filtrów

    /// KAŻDY filtr, który zawęża tę listę (także rodzaj dania czy smak tej
    /// kategorii), i „Wyczyść”, które zdejmuje je wszystkie. `nil`, gdy nic.
    private var filtersContextRow: RecipeListContextCard.Row? {
        RecipeListContextCard.Row.filters(filters.summaryLabels(in: category)) {
            withAnimation(.smooth(duration: 0.25)) { filters.reset(in: category) }
        }
    }

    // MARK: - Pusty stan

    /// Co opróżniło listę i jak to zdjąć — ten sam układ, co w wyborze
    /// przepisu do planu (`RecipeListEmptyState`).
    private func emptyState(categoryIsEmpty: Bool, fittedIsEmpty: Bool) -> some View {
        let clearFilters = RecipeListEmptyState.Action(title: "Wyczyść filtry") {
            withAnimation(.smooth(duration: 0.25)) { filters.reset(in: category) }
        }

        if categoryIsEmpty {
            return RecipeListEmptyState(
                icon: RecipesConstants.icon(for: category),
                accent: accent,
                title: "Pusta kategoria",
                message: "Nic tu jeszcze nie ma."
            )
        }
        if !query.isEmpty {
            var actions = [RecipeListEmptyState.Action(title: "Wyczyść frazę", icon: "xmark") {
                withAnimation(.smooth(duration: 0.25)) { searchText = "" }
            }]
            if hasFilters { actions.append(clearFilters) }
            return RecipeListEmptyState(
                icon: "magnifyingglass",
                accent: accent,
                title: "Nic dla \u{201E}\(query)\u{201D}",
                message: "Nic w tej kategorii nie pasuje do frazy. Spróbuj innej.",
                actions: actions
            )
        }
        if fittedIsEmpty {
            return RecipeListEmptyState(
                icon: personalization.diet == .none ? "exclamationmark.shield" : personalization.diet.icon,
                accent: personalization.diet == .none ? SCPalette.terracotta : personalization.diet.accent,
                title: personalization.diet == .none ? "Alergeny ukrywają wszystko" : "Dieta ukrywa wszystko",
                message: "Żaden przepis w tej kategorii nie mieści się w Twojej diecie i alergenach.",
                actions: [
                    .init(title: "Pokaż mimo diety", icon: "leaf") {
                        withAnimation(.smooth(duration: 0.25)) { isPersonalizationEnabled = false }
                    }
                ]
            )
        }
        return RecipeListEmptyState(
            icon: "line.3.horizontal.decrease",
            accent: accent,
            title: "Nic nie pasuje",
            message: "Żaden przepis w tej kategorii nie przechodzi przez filtry.",
            actions: hasFilters ? [clearFilters] : []
        )
    }
}

// MARK: - Szukanie po nazwie i opisie

/// Szukanie przepisów frazą — jedna reguła dla korzenia Przepisów i ekranu
/// kategorii: trafia nazwa albo opis, a kolejność to najpierw nazwy, które
/// się frazą ZACZYNAJĄ, potem te, w których słowo się nią zaczyna, potem
/// reszta nazw, na końcu trafienia w samym opisie.
enum RecipeTextSearch {
    static func filter(_ recipes: [Recipe], query: String) -> [Recipe] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return recipes }
        return recipes.filter { recipe in
            recipe.name.localizedCaseInsensitiveContains(query) ||
            recipe.description.localizedCaseInsensitiveContains(query)
        }
    }

    /// Kolejność trafień przy frazie (w obrębie grupy — kolejność wejścia).
    static func ranked(_ recipes: [Recipe], query: String) -> [Recipe] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return recipes }
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
        return recipes.enumerated()
            .map { (rank: rank($0.element), index: $0.offset, recipe: $0.element) }
            .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
            .map(\.recipe)
    }

    /// Lista kategorii: bez frazy ulubione na górze, potem alfabetycznie
    /// (jak dawny arkusz kategorii); z frazą — kolejność trafień.
    static func ordered(_ recipes: [Recipe], query: String) -> [Recipe] {
        let alphabetical = recipes.sorted { lhs, rhs in
            if lhs.favourite != rhs.favourite { return lhs.favourite && !rhs.favourite }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return ranked(alphabetical, query: query)
    }
}
