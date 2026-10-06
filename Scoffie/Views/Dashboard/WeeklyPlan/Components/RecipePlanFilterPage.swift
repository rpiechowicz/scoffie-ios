import SwiftUI

// Filtry wyboru przepisu do planu („Wybierz przepis” w Planie) — podstrona
// wpychana w stos arkusza wyboru przyciskiem filtrów obok krzyżyka
// (6.10.2026: push zamiast drugiego arkusza na arkuszu). Systemowy pasek
// z tytułem, „wstecz” i „Wyczyść”; zmiany idą od razu do listy wyboru, a
// „Gotowe” wraca do niej.
//
// Filtry są WŁASNE dla tego wyboru, nie z Przepisów: kafelek „Ulubione”
// i aspekty kategorii pory (`slot.baseCategory`: smak, rodzaj dania, mięso)
// bez „Pory w planie” — pora jest już wybrana. Kuchnia i okazje stoją
// wierszami „Więcej filtrów”, a ich kafelki są kolejną podstroną. Świeci
// kolorem i ikoną pory. Wcześniej to był `RecipeCategoryFilterSheet`,
// wspólny z listą kategorii na Przepisach; Przepisy mają teraz sekcję
// kategorii w swoich „Filtrach”.
struct RecipePlanFilterPage: View {
    let slot: MealSlot
    /// Aspekty kategorii pory — smak, rodzaj dania, mięso, kuchnia, okazje.
    @Binding var filter: RecipeCategoryFilter
    /// „Tylko ulubione” wyboru do planu.
    @Binding var favouritesOnly: Bool
    /// Przepisy pory po dopasowaniu, PRZED filtrami i „tylko ulubionymi” —
    /// na nich liczą się kafelki.
    let recipes: [Recipe]
    /// „Gotowe” — powrót do listy wyboru (zamyka też podstronę aspektu).
    let onDone: () -> Void

    init(
        slot: MealSlot,
        filter: Binding<RecipeCategoryFilter>,
        favouritesOnly: Binding<Bool>,
        recipes: [Recipe],
        onDone: @escaping () -> Void
    ) {
        self.slot = slot
        self._filter = filter
        self._favouritesOnly = favouritesOnly
        self.recipes = recipes
        self.onDone = onDone
    }

    @State private var valuesBox = ValuesBox()
    /// Aspekt wpchnięty z „Więcej filtrów” (kuchnia, okazje i sezon).
    @State private var openFacet: RecipeFacetKind?

    private var category: RecipesCategory { slot.baseCategory }
    private var facets: [RecipeFacet] { RecipeCategoryFacets.facets(forPicking: category, slot: slot) }
    private var shownFacets: [RecipeFacet] { facets.filter { !visibleOptions($0).isEmpty } }
    /// Aspekty rodzaju, smaku i mięsa — kafelkami na wierzchu strony.
    private var inlineFacets: [RecipeFacet] { shownFacets.filter { !$0.kind.hidesEmptyOptions } }
    /// Kuchnia, okazje i sezon — wierszami w karcie „Więcej filtrów”.
    private var pickerFacets: [RecipeFacet] { shownFacets.filter { $0.kind.hidesEmptyOptions } }
    private var accent: Color { slot.cozyAccent }

    /// Wartości aspektów każdego przepisu puli — liczone raz na otwarcie.
    /// W aspektach kategorii PORY, także dla dań z innej — w wyborze do planu
    /// stoją obok siebie (owsianka w II śniadaniu).
    private var values: [[RecipeFacetKind: Set<String>]] {
        if let values = valuesBox.values { return values }
        let facetCategory = category
        let values = recipes.map { RecipeFilterFactsCache.facetValues(for: $0, in: facetCategory) }
        valuesBox.values = values
        return values
    }

    /// Zdjęcia kafelków — przykład dania dla każdej opcji, raz na otwarcie.
    private var covers: RecipeFacetCovers {
        if let covers = valuesBox.covers { return covers }
        let covers = RecipeFacetCovers(facets: facets, recipes: recipes, values: values)
        valuesBox.covers = covers
        return covers
    }

    /// Opcje aspektu na kafelkach. Kuchnia i okazje chowają opcje, których
    /// w puli nie ma wcale (tajska wśród śniadań) — zaznaczona zostaje
    /// zawsze, żeby dało się ją odznaczyć.
    private func visibleOptions(_ facet: RecipeFacet) -> [RecipeFacetOption] {
        Self.visibleOptions(facet, filter: filter, values: values)
    }

    static func visibleOptions(
        _ facet: RecipeFacet,
        filter: RecipeCategoryFilter,
        values: [[RecipeFacetKind: Set<String>]]
    ) -> [RecipeFacetOption] {
        guard facet.kind.hidesEmptyOptions else { return facet.options }
        return facet.options.filter { option in
            filter.contains(option.id, in: facet.kind)
                || values.contains { $0[facet.kind]?.contains(option.id) == true }
        }
    }

    /// Ile przepisów puli przejdzie przez wybór — z „Ulubionymi” albo bez.
    static func count(
        _ filter: RecipeCategoryFilter,
        favourites: Bool,
        recipes: [Recipe],
        values: [[RecipeFacetKind: Set<String>]]
    ) -> Int {
        var total = 0
        // `zip`, nie indeks: wartości są policzone raz na otwarcie, a lista
        // przepisów przychodzi na nowo z każdym przerysowaniem rodzica —
        // przeładowany w tle katalog bywa krótszy i indeks wypadłby poza nią.
        for (recipe, recipeValues) in zip(recipes, values) where filter.matches(recipeValues) {
            if !favourites || recipe.favourite { total += 1 }
        }
        return total
    }

    private func count(_ filter: RecipeCategoryFilter, favourites: Bool) -> Int {
        Self.count(filter, favourites: favourites, recipes: recipes, values: values)
    }

    // MARK: - Body

    var body: some View {
        RecipeFilterPage(
            title: "Filtry",
            accent: accent,
            hint: "Zawężają listę przepisów na \(slot.accusativeName)",
            selectedCount: filter.activeCount + (favouritesOnly ? 1 : 0),
            resultCount: count(filter, favourites: favouritesOnly),
            totalCount: recipes.count,
            totalContext: "do wyboru",
            onClear: {
                filter = RecipeCategoryFilter()
                favouritesOnly = false
            },
            onDone: onDone
        ) {
            favouritesSection

            ForEach(inlineFacets) { facet in
                RecipeFacetTilesSection(
                    facet: facet,
                    title: facet.title,
                    accent: accent,
                    icon: slot.icon,
                    isOn: { filter.contains($0, in: facet.kind) },
                    count: { count(filter.adding($0, in: facet.kind), favourites: favouritesOnly) },
                    cover: { covers.cover(for: $0, in: facet.kind) },
                    onToggle: { filter.toggle($0, in: facet.kind) }
                )
            }

            if !pickerFacets.isEmpty {
                moreSection
            }
        }
        .sensoryFeedback(.selection, trigger: filter)
        .sensoryFeedback(.selection, trigger: favouritesOnly)
        .navigationDestination(item: $openFacet) { kind in
            // Z pełnej listy, nie z `pickerFacets`: aspekt widoczny tylko dzięki
            // zaznaczonej opcji znika z karty po jej odznaczeniu — otwarta
            // podstrona nie może wtedy zostać pusta.
            if let facet = facets.first(where: { $0.kind == kind }) {
                RecipePlanFacetPane(
                    facet: facet,
                    eyebrowTitle: slot.title,
                    accent: accent,
                    filter: $filter,
                    favouritesOnly: favouritesOnly,
                    recipes: recipes,
                    values: values,
                    covers: covers,
                    onDone: onDone
                )
            }
        }
    }

    // MARK: - Sekcje

    /// „Ulubione” — jeden kafelek, jak opcje aspektów: zdjęcie ulubionego
    /// dania i liczba tego, co zostanie po zaznaczeniu.
    private var favouritesSection: some View {
        RecipeFilterSection(title: "Twoje przepisy", top: 8) {
            RecipeFilterTileGrid(items: [FavouritesOption()]) { _ in
                RecipeFilterOptionTile(
                    title: "Ulubione",
                    count: count(filter, favourites: true),
                    mark: favouritesOnly ? .on : .off,
                    accent: SCPalette.terracotta,
                    cover: recipes.first { $0.favourite && $0.imageURL != nil },
                    icon: "heart.fill",
                    accessibilityDetail: "przepisy z serduszkiem"
                ) {
                    withAnimation(.smooth(duration: 0.18)) { favouritesOnly.toggle() }
                }
            }
        }
    }

    /// Jedyna pozycja siatki „Twoje przepisy” — siatka chce `Identifiable`,
    /// a ta sama siatka trzyma kafelek w pół szerokości, jak wszystkie inne.
    private struct FavouritesOption: Identifiable {
        let id = "favourites"
    }

    private var moreSection: some View {
        RecipeFilterSection(title: "Więcej filtrów") {
            RecipeFilterPickerGroup {
                ForEach(Array(pickerFacets.enumerated()), id: \.element.id) { index, facet in
                    if index > 0 {
                        RecipeFilterPickerDivider()
                    }
                    RecipeFilterPickerRow(
                        icon: facet.kind.pickerIcon,
                        title: facet.title,
                        placeholder: RecipeFilterPickerRow.placeholder(
                            from: RecipeFilterPickerRow.sentence(visibleOptions(facet).map {
                                RecipeMoment(rawValue: $0.id)?.summaryTitle ?? $0.title.lowercased()
                            })
                        ),
                        chips: facet.options
                            .filter { filter.contains($0.id, in: facet.kind) }
                            .map { RecipeFilterChipLine.Chip(id: $0.id, title: $0.title) },
                        accent: accent
                    ) { openFacet = facet.kind }
                }
            }
        }
    }

    /// Pudełko na wartości aspektów i zdjęcia — klasa, żeby zapamiętanie
    /// wyniku w trakcie `body` nie było zmianą stanu.
    private final class ValuesBox {
        var values: [[RecipeFacetKind: Set<String>]]?
        var covers: RecipeFacetCovers?
    }
}

// MARK: - Podstrona aspektu

/// Kafelki jednego aspektu (kuchnia, okazje i sezon) na własnej podstronie —
/// te same, co sekcja na stronie filtrów, piszące od razu do filtra wyboru.
/// Czyta filtr przez wiązanie, więc liczby zmieniają się na żywo.
private struct RecipePlanFacetPane: View {
    let facet: RecipeFacet
    /// Pora — w opisie nad kafelkami.
    let eyebrowTitle: String
    let accent: Color
    @Binding var filter: RecipeCategoryFilter
    let favouritesOnly: Bool
    let recipes: [Recipe]
    let values: [[RecipeFacetKind: Set<String>]]
    let covers: RecipeFacetCovers
    let onDone: () -> Void

    private func count(_ filter: RecipeCategoryFilter) -> Int {
        RecipePlanFilterPage.count(filter, favourites: favouritesOnly, recipes: recipes, values: values)
    }

    var body: some View {
        let options = RecipePlanFilterPage.visibleOptions(facet, filter: filter, values: values)

        RecipeFilterPage(
            title: facet.title,
            accent: accent,
            hint: facet.kind == .moment
                ? "\(eyebrowTitle) · dowolna z zaznaczonych · pora roku to dania sezonowe"
                : "\(eyebrowTitle) · dowolna z zaznaczonych",
            selectedCount: filter.picks[facet.kind]?.count ?? 0,
            resultCount: count(filter),
            totalCount: recipes.count,
            totalContext: "do wyboru",
            onClear: { filter.picks[facet.kind] = nil },
            onDone: onDone
        ) {
            RecipeFilterTileGrid(items: options) { option in
                RecipeFilterOptionTile(
                    title: option.title,
                    count: count(filter.adding(option.id, in: facet.kind)),
                    mark: filter.contains(option.id, in: facet.kind) ? .on : .off,
                    accent: accent,
                    cover: covers.cover(for: option.id, in: facet.kind),
                    icon: RecipeCuisine(rawValue: option.id)?.tileIcon
                        ?? RecipeMoment(rawValue: option.id)?.tileIcon
                        ?? facet.kind.pickerIcon
                ) {
                    withAnimation(.smooth(duration: 0.18)) {
                        filter.toggle(option.id, in: facet.kind)
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: filter)
    }
}

// MARK: - Glify aspektów

private extension RecipeFacetKind {
    var pickerIcon: String {
        switch self {
        case .cuisine: return "globe.europe.africa.fill"
        case .moment:  return "calendar"
        default:       return "line.3.horizontal.decrease"
        }
    }
}
