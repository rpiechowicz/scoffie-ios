import Foundation

/// Zdjęcia do kafelków filtrów: dla każdego kafelka jeden przepis, który ma
/// tę cechę — „Z rybą” pokazuje rybę, „Zupy” zupę, „Ulubione” jedno z Twoich
/// ulubionych.
///
/// Wybór zapada raz na otwarcie arkusza, z puli PRZED filtrami, więc zdjęcie
/// nie przeskakuje, gdy ktoś zaznacza kafelki obok. Każdy przepis trafia do
/// jednego kafelka: sześć kafelków z tym samym daniem nic by nie mówiło.
/// Dopiero gdy wszystkie pasujące są już zajęte, kafelek bierze powtórkę —
/// zdjęcie jest wtedy i tak lepsze niż sam glif.
///
/// Dania, które profil ukrywa (dieta, alergeny z Ustawień), idą na kafelek
/// dopiero, gdy żadne inne nie pasuje: kafelek „Wysokobiałkowe” nie może
/// pokazać kurczaka w sosie orzechowym komuś uczulonemu na orzechy. Zostaje
/// tylko tam, gdzie cecha sama jest tym daniem („Z rybą” u wegetarianina).
///
/// Kolejność puli to kolejność listy Przepisów, więc na kafelkach stoją
/// dania, które i tak widać na górze listy.
struct RecipeFilterCovers {
    private(set) var diets: [RecipeDietFilter: Recipe] = [:]
    private(set) var traits: [RecipeTraitFilter: Recipe] = [:]

    /// `isAvoided(i)` — przepis `recipes[i]` ukrywa profil.
    @MainActor
    init(recipes: [Recipe], isAvoided: @escaping (Int) -> Bool = { _ in false }) {
        let facts = recipes.map { RecipeFilterFactsCache.facts(for: $0) }
        var picker = RecipeCoverPicker(recipes: recipes, isAvoided: isAvoided)
        for diet in RecipeDietFilter.allCases {
            diets[diet] = picker.pick { facts[$0].diets.contains(diet) }
        }
        for trait in RecipeTraitFilter.allCases {
            traits[trait] = picker.pick { facts[$0].traits.contains(trait) }
        }
    }
}

/// To samo dla filtrów kategorii: aspekt → opcja → przepis. Pula arkusza
/// kategorii jest już po dopasowaniu do profilu (o ile jest włączone), więc
/// tu nic nie trzeba omijać.
struct RecipeFacetCovers {
    private var covers: [RecipeFacetKind: [String: Recipe]] = [:]

    /// `values[i]` to wartości aspektów przepisu `recipes[i]`.
    init(facets: [RecipeFacet], recipes: [Recipe], values: [[RecipeFacetKind: Set<String>]]) {
        var picker = RecipeCoverPicker(recipes: recipes, isAvoided: { _ in false })
        for facet in facets {
            var byOption: [String: Recipe] = [:]
            for option in facet.options {
                byOption[option.id] = picker.pick { index in
                    index < values.count && values[index][facet.kind]?.contains(option.id) == true
                }
            }
            covers[facet.kind] = byOption
        }
    }

    func cover(for option: String, in kind: RecipeFacetKind) -> Recipe? {
        covers[kind]?[option]
    }
}

/// Po jednym przepisie ze zdjęciem na kafelek, bez powtórzeń, dopóki się da.
private struct RecipeCoverPicker {
    let recipes: [Recipe]
    let isAvoided: (Int) -> Bool
    private var used: Set<UUID> = []

    init(recipes: [Recipe], isAvoided: @escaping (Int) -> Bool) {
        self.recipes = recipes
        self.isAvoided = isAvoided
    }

    /// Najpierw przepisy, których profil nie ukrywa: pierwszy pasujący, który
    /// nie stoi jeszcze na innym kafelku, a gdy takich brak — powtórka.
    /// Ukryte przez profil dopiero wtedy, gdy żaden inny nie pasuje wcale.
    mutating func pick(where matches: (Int) -> Bool) -> Recipe? {
        for avoided in [false, true] {
            var repeated: Recipe?
            for index in recipes.indices where recipes[index].imageURL != nil && isAvoided(index) == avoided && matches(index) {
                let recipe = recipes[index]
                if used.insert(recipe.id).inserted { return recipe }
                if repeated == nil { repeated = recipe }
            }
            if let repeated { return repeated }
        }
        return nil
    }
}
