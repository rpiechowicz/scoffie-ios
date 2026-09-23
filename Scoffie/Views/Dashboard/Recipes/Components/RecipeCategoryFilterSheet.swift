import SwiftUI

// Filtry „tylko w tej kategorii” — arkusz otwierany przyciskiem obok
// krzyżyka w liście kategorii (Śniadania, Obiady, Kolacje, Przekąski
// i desery). Makieta nazywała to „piętrem” kategorii nad piętrem
// „Wszystkie przepisy” (`RF2FloorB` w `components/rf2-kit.jsx`).
//
// Układ celowo jak w arkuszu „Filtry”: przypięty nagłówek z „Wyczyść” obok
// krzyżyka, wiersz zasięgu, sekcje kafelków 2 × N ze zdjęciem dania i liczbą
// przepisów po zaznaczeniu, stopka z liczbą i „Pokaż”. Kto zna jeden arkusz,
// obsłuży drugi. Różni się kolor — kafelki świecą akcentem kategorii
// (śniadania masłem, obiady szałwią…), tak jak jej sekcja na Przepisach.
//
// Zmiany idą na kopię roboczą — „Pokaż” zapisuje, zamknięcie gestem nie.
// „Wyczyść” działa od razu, jak w arkuszu „Filtry”.
struct RecipeCategoryFilterSheet: View {
    let category: RecipesCategory
    @Binding var filter: RecipeCategoryFilter

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var draft: RecipeCategoryFilter
    @State private var valuesBox: ValuesBox

    /// Przepisy tej kategorii po dopasowaniu i filtrach wszystkich przepisów,
    /// ale PRZED filtrami tej kategorii — na nich liczą się kafelki.
    private let recipes: [Recipe]

    init(category: RecipesCategory, recipes: [Recipe], filter: Binding<RecipeCategoryFilter>) {
        self.category = category
        self.recipes = recipes
        self._filter = filter
        self._draft = State(initialValue: filter.wrappedValue)
        self._valuesBox = State(initialValue: ValuesBox())
    }

    private var facets: [RecipeFacet] { RecipeCategoryFacets.facets(for: category) }
    private var accent: Color { RecipeAccent.accent(for: category) }

    /// Wartości aspektów każdego przepisu puli — liczone raz na otwarcie
    /// (patrz `IndexBox` w `RecipeFilterSheet`: `init` odpala się przy każdym
    /// przerysowaniu listy pod arkuszem).
    private var values: [[RecipeFacetKind: Set<String>]] {
        if let values = valuesBox.values { return values }
        let values = recipes.map { RecipeFilterFactsCache.facts(for: $0).facetValues }
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

    private func count(_ filter: RecipeCategoryFilter) -> Int {
        values.reduce(into: 0) { total, recipe in
            if filter.matches(recipe) { total += 1 }
        }
    }

    private var resultCount: Int { count(draft) }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Przypięty — tak samo jak w „Filtrach”.
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(facets.enumerated()), id: \.element.id) { index, facet in
                            facetSection(facet, top: index == 0 ? 8 : 24)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .containerRelativeFrame(.horizontal)
                }
                .scrollIndicators(.hidden)
                .scScrollEdgeFade()
                .scSheetFooter { footer }
            }
        }
        .animation(.smooth(duration: 0.22), value: draft.isActive)
        .sensoryFeedback(.selection, trigger: draft)
    }

    // MARK: - Nagłówek

    private var header: some View {
        RecipeFilterHeader(
            icon: RecipesConstants.icon(for: category),
            eyebrow: "Filtry kategorii",
            title: RecipesConstants.displayName(for: category),
            scope: "Tylko w tej kategorii — razem z filtrami wszystkich przepisów",
            activeSummary: activeSummary,
            accent: accent,
            canClear: draft.isActive,
            onClear: { clearAll() },
            onClose: { dismiss() }
        )
    }

    /// Które aspekty zawężają teraz kategorię — „Aktywne: smak, rodzaj dania”.
    private var activeSummary: String? {
        let names = facets
            .filter { !(draft.picks[$0.kind]?.isEmpty ?? true) }
            .map { $0.title.lowercased() }
        return names.isEmpty ? nil : "Aktywne: " + names.joined(separator: ", ")
    }

    // MARK: - Sekcje

    private func facetSection(_ facet: RecipeFacet, top: CGFloat) -> some View {
        let picked = draft.picks[facet.kind]?.count ?? 0

        return RecipeFilterSection(title: facet.title, top: top) {
            if picked > 1 {
                // Dwie opcje w jednym rzędzie poszerzają wynik — mówimy to,
                // zanim ktoś zdziwi się, że liczba urosła.
                Text("dowolna z zaznaczonych")
                    .transition(.opacity)
            }
        } content: {
            RecipeFilterTileGrid(items: facet.options) { option in
                RecipeFilterOptionTile(
                    title: option.title,
                    count: count(draft.adding(option.id, in: facet.kind)),
                    mark: draft.contains(option.id, in: facet.kind) ? .on : .off,
                    accent: accent,
                    cover: covers.cover(for: option.id, in: facet.kind),
                    icon: RecipesConstants.icon(for: category)
                ) {
                    withAnimation(.smooth(duration: 0.18)) {
                        draft.toggle(option.id, in: facet.kind)
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.2), value: picked > 1)
    }

    // MARK: - Stopka

    private var footer: some View {
        let count = resultCount
        let total = recipes.count

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "\(count)")
                        .font(.system(size: 15, weight: .bold))
                        .tracking(-0.3)
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(scheme))
                        .contentTransition(.numericText(value: Double(count)))

                    Text(verbatim: "z \(total) w tej kategorii")
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                }

                // Ten sam pasek co w stopce „Filtrów”, tylko jeden — ile
                // z kategorii zostaje po zaznaczeniu.
                GeometryReader { proxy in
                    Capsule(style: .continuous)
                        .fill(accent.opacity(0.2))
                        .overlay(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(accent)
                                .frame(width: total == 0 || count == 0
                                       ? 0
                                       : max(5, proxy.size.width * CGFloat(count) / CGFloat(total)))
                        }
                }
                .frame(height: 5)
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.3), value: count)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Zostaje \(PolishPlural.recipes(count)) z \(total) w tej kategorii")

            RecipeFilterFooterButton(title: "Pokaż", isEnabled: count > 0, action: apply)
        }
        .padding(.leading, 4)
    }

    // MARK: - Akcje

    private func clearAll() {
        withAnimation(.smooth(duration: 0.25)) {
            draft = RecipeCategoryFilter()
            filter = draft
        }
    }

    private func apply() {
        filter = draft
        dismiss()
    }

    /// Pudełko na wartości aspektów i zdjęcia — klasa, żeby zapamiętanie
    /// wyniku w trakcie `body` nie było zmianą stanu.
    private final class ValuesBox {
        var values: [[RecipeFacetKind: Set<String>]]?
        var covers: RecipeFacetCovers?
    }
}
