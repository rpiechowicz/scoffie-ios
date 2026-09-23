import SwiftUI

// Filtry „tylko w tej kategorii” — arkusz otwierany przyciskiem obok
// krzyżyka w liście kategorii (Śniadania, Obiady, Kolacje, Przekąski
// i desery). Makieta nazywała to „piętrem” kategorii nad piętrem
// „Wszystkie przepisy” (`RF2FloorB` w `components/rf2-kit.jsx`).
//
// Układ celowo jak w arkuszu „Filtry”: nagłówek z „Wyczyść” obok krzyżyka,
// wiersz zasięgu, sekcje kafelków 2 × N z liczbą przepisów po zaznaczeniu,
// stopka z liczbą i „Pokaż”. Kto zna jeden arkusz, obsłuży drugi. Różni się
// kolor — kafelki świecą akcentem kategorii (śniadania masłem, obiady
// szałwią…), tak jak jej sekcja na Przepisach.
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

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    scopeRow
                        .padding(.top, 20)

                    ForEach(facets) { facet in
                        facetSection(facet)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
            .scSheetFooter { footer }
        }
        .animation(.smooth(duration: 0.22), value: draft.isActive)
        .sensoryFeedback(.selection, trigger: draft)
    }

    // MARK: - Nagłówek

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FILTRY KATEGORII")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(accent)

                Text(RecipesConstants.displayName(for: category))
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if draft.isActive {
                RecipeFilterClearButton(action: clearAll)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }

            SCSheetCloseButton { dismiss() }
        }
    }

    /// Zasięg: te filtry działają tylko tutaj i dokładają się do filtrów
    /// wszystkich przepisów — ten sam wiersz co „Wszystkie przepisy”
    /// w arkuszu „Filtry”, w kolorze kategorii.
    private var scopeRow: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(scheme == .dark ? 0.18 : 0.14))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: RecipesConstants.icon(for: category))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Tylko w tej kategorii")
                    .font(.system(size: 16.5, weight: .bold))
                    .tracking(-0.35)
                    .foregroundStyle(Color.scLabel(scheme))
                Text("Działają razem z filtrami wszystkich przepisów")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sekcje

    private let gridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private func facetSection(_ facet: RecipeFacet) -> some View {
        let picked = draft.picks[facet.kind]?.count ?? 0

        return RecipeFilterSection(title: facet.title) {
            if picked > 1 {
                // Dwie opcje w jednym rzędzie poszerzają wynik — mówimy to,
                // zanim ktoś zdziwi się, że liczba urosła.
                Text("dowolna z zaznaczonych")
                    .transition(.opacity)
            }
        } content: {
            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(facet.options) { option in
                    RecipeFilterOptionTile(
                        title: option.title,
                        count: count(draft.adding(option.id, in: facet.kind)),
                        mark: draft.contains(option.id, in: facet.kind) ? .on : .off,
                        accent: accent
                    ) {
                        withAnimation(.smooth(duration: 0.18)) {
                            draft.toggle(option.id, in: facet.kind)
                        }
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

    /// Pudełko na wartości aspektów — klasa, żeby zapamiętanie wyniku
    /// w trakcie `body` nie było zmianą stanu.
    private final class ValuesBox {
        var values: [[RecipeFacetKind: Set<String>]]?
    }
}
