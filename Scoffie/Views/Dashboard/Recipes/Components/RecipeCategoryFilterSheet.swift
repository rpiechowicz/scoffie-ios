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
//
// Ten sam arkusz otwiera wybór przepisu do planu (`slot`): wtedy świeci
// kolorem i ikoną pory, aspekt „Pora w planie” znika (pora jest już
// wybrana), a na górze staje kafelek „Ulubione” — w wyborze do planu to on
// zastąpił pigułkę pod szukaniem. Pigułek w listach nie ma od rundy 10
// (Rafał: „od tego mamy filtry”), więc wszystko, czym zawęża się listę,
// mieszka tutaj.
struct RecipeCategoryFilterSheet: View {
    let category: RecipesCategory
    @Binding var filter: RecipeCategoryFilter
    /// Pora z planu, gdy arkusz otwiera wybór przepisu do planu.
    let slot: MealSlot?
    /// „Tylko ulubione” wyboru do planu. `nil` = bez kafelka (lista
    /// kategorii — tam ulubione ma arkusz „Filtry”).
    private let favouritesOnly: Binding<Bool>?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var draft: RecipeCategoryFilter
    @State private var draftFavourites: Bool
    @State private var valuesBox: ValuesBox

    /// Przepisy tej kategorii po dopasowaniu i filtrach wszystkich przepisów,
    /// ale PRZED filtrami tej kategorii — na nich liczą się kafelki.
    private let recipes: [Recipe]

    init(
        category: RecipesCategory,
        recipes: [Recipe],
        filter: Binding<RecipeCategoryFilter>,
        slot: MealSlot? = nil,
        favouritesOnly: Binding<Bool>? = nil
    ) {
        self.category = category
        self.recipes = recipes
        self.slot = slot
        self.favouritesOnly = favouritesOnly
        self._filter = filter
        self._draft = State(initialValue: filter.wrappedValue)
        self._draftFavourites = State(initialValue: favouritesOnly?.wrappedValue ?? false)
        self._valuesBox = State(initialValue: ValuesBox())
    }

    private var facets: [RecipeFacet] { RecipeCategoryFacets.facets(forPicking: category, slot: slot) }
    private var accent: Color { slot?.cozyAccent ?? RecipeAccent.accent(for: category) }

    /// Wartości aspektów każdego przepisu puli — liczone raz na otwarcie
    /// (patrz `IndexBox` w `RecipeFilterSheet`: `init` odpala się przy każdym
    /// przerysowaniu listy pod arkuszem). W aspektach TEJ kategorii, także
    /// dla dań z innej — w wyborze do planu stoją obok siebie.
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

    /// Ile przepisów puli przejdzie przez wybór — z „Ulubionymi” albo bez.
    private func count(_ filter: RecipeCategoryFilter, favourites: Bool) -> Int {
        var total = 0
        // `zip`, nie indeks: wartości są policzone raz na otwarcie, a lista
        // przepisów przychodzi na nowo z każdym przerysowaniem rodzica —
        // przeładowany w tle katalog bywa krótszy i indeks wypadłby poza nią.
        for (recipe, recipeValues) in zip(recipes, values) where filter.matches(recipeValues) {
            if !favourites || recipe.favourite { total += 1 }
        }
        return total
    }

    private var resultCount: Int { count(draft, favourites: draftFavourites) }

    /// Czy cokolwiek jest zaznaczone — aspekty albo „Ulubione”.
    private var isDraftActive: Bool { draft.isActive || draftFavourites }

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
                        if favouritesOnly != nil {
                            favouritesSection
                        }

                        ForEach(Array(facets.enumerated()), id: \.element.id) { index, facet in
                            facetSection(facet, top: index == 0 && favouritesOnly == nil ? 8 : 24)
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
        .animation(.smooth(duration: 0.22), value: isDraftActive)
        .sensoryFeedback(.selection, trigger: draft)
        .sensoryFeedback(.selection, trigger: draftFavourites)
    }

    // MARK: - Nagłówek

    private var header: some View {
        RecipeFilterHeader(
            icon: slot?.icon ?? RecipesConstants.icon(for: category),
            eyebrow: slot == nil ? "Filtry kategorii" : "Filtry",
            title: slot?.title ?? RecipesConstants.displayName(for: category),
            scope: scopeLine,
            accent: accent,
            canClear: isDraftActive,
            onClear: { clearAll() },
            onClose: { dismiss() }
        )
    }

    /// Gdzie działają — w liście kategorii razem z filtrami wszystkich
    /// przepisów, w wyborze do planu tylko w tym wyborze.
    private var scopeLine: String {
        guard let slot else { return "Tylko w tej kategorii — razem z filtrami wszystkich przepisów" }
        return "Zawężają listę przepisów na \(slot.accusativeName)"
    }

    // MARK: - Sekcje

    /// „Ulubione” w wyborze do planu — jeden kafelek, jak opcje aspektów:
    /// zdjęcie ulubionego dania i liczba tego, co zostanie po zaznaczeniu.
    private var favouritesSection: some View {
        RecipeFilterSection(title: "Twoje przepisy", top: 8) {
            RecipeFilterTileGrid(items: [FavouritesOption()]) { _ in
                RecipeFilterOptionTile(
                    title: "Ulubione",
                    count: count(draft, favourites: true),
                    mark: draftFavourites ? .on : .off,
                    accent: SCPalette.terracotta,
                    cover: recipes.first { $0.favourite && $0.imageURL != nil },
                    icon: "heart.fill",
                    accessibilityDetail: "przepisy z serduszkiem"
                ) {
                    withAnimation(.smooth(duration: 0.18)) { draftFavourites.toggle() }
                }
            }
        }
    }

    /// Jedyna pozycja siatki „Twoje przepisy” — siatka chce `Identifiable`,
    /// a ta sama siatka trzyma kafelek w pół szerokości, jak wszystkie inne.
    private struct FavouritesOption: Identifiable {
        let id = "favourites"
    }

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
                    count: count(draft.adding(option.id, in: facet.kind), favourites: draftFavourites),
                    mark: draft.contains(option.id, in: facet.kind) ? .on : .off,
                    accent: accent,
                    cover: covers.cover(for: option.id, in: facet.kind),
                    icon: slot?.icon ?? RecipesConstants.icon(for: category)
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

                    Text(verbatim: "z \(total) \(totalContext)")
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
            .accessibilityLabel("Zostaje \(PolishPlural.recipes(count)) z \(total) \(totalContext)")

            RecipeFilterFooterButton(title: "Pokaż", isEnabled: count > 0, action: apply)
        }
        .padding(.leading, 4)
    }

    /// Z czego liczy się stopka — kategoria albo pula wyboru do planu.
    private var totalContext: String {
        slot == nil ? "w tej kategorii" : "do wyboru"
    }

    // MARK: - Akcje

    private func clearAll() {
        withAnimation(.smooth(duration: 0.25)) {
            draft = RecipeCategoryFilter()
            draftFavourites = false
            filter = draft
            favouritesOnly?.wrappedValue = false
        }
    }

    private func apply() {
        filter = draft
        favouritesOnly?.wrappedValue = draftFavourites
        dismiss()
    }

    /// Pudełko na wartości aspektów i zdjęcia — klasa, żeby zapamiętanie
    /// wyniku w trakcie `body` nie było zmianą stanu.
    private final class ValuesBox {
        var values: [[RecipeFacetKind: Set<String>]]?
        var covers: RecipeFacetCovers?
    }
}
