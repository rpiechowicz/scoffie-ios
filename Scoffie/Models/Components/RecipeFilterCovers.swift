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
/// dania, które i tak widać na górze listy. Kuchnie (kółka na wierzchu
/// filtrów wszystkich przepisów) mają zdjęcia wybrane ręcznie
/// (`RecipeFilterCoverPicks`) i wybierają PIERWSZE, zanim przepisy zajmą
/// kafelki diet i cech na podstronach; diety, cechy i okazje też biorą
/// najpierw wybrane ręcznie, a automat tylko, gdy wybranego nie ma w puli
/// albo ukrywa go profil.
struct RecipeFilterCovers {
    private(set) var diets: [RecipeDietFilter: Recipe] = [:]
    private(set) var traits: [RecipeTraitFilter: Recipe] = [:]
    private(set) var cuisines: [RecipeCuisine: Recipe] = [:]
    private(set) var moments: [RecipeMoment: Recipe] = [:]

    /// `isAvoided(i)` — przepis `recipes[i]` ukrywa profil.
    @MainActor
    init(recipes: [Recipe], isAvoided: @escaping (Int) -> Bool = { _ in false }) {
        let facts = recipes.map { RecipeFilterFactsCache.facts(for: $0) }
        var picker = RecipeCoverPicker(recipes: recipes, isAvoided: isAvoided)
        for cuisine in RecipeCuisine.allCases {
            cuisines[cuisine] = picker.pick(preferring: RecipeFilterCoverPicks.ids("cuisine:\(cuisine.rawValue)")) {
                facts[$0].cuisine == cuisine
            }
        }
        for diet in RecipeDietFilter.allCases {
            diets[diet] = picker.pick(preferring: RecipeFilterCoverPicks.ids("diet:\(diet.rawValue)")) {
                facts[$0].diets.contains(diet)
            }
        }
        for trait in RecipeTraitFilter.allCases {
            traits[trait] = picker.pick(preferring: RecipeFilterCoverPicks.ids("trait:\(trait.rawValue)")) {
                facts[$0].traits.contains(trait)
            }
        }
        for moment in RecipeMoment.allCases {
            moments[moment] = picker.pick(preferring: RecipeFilterCoverPicks.ids("moment:\(moment.rawValue)")) {
                facts[$0].moments.contains(moment)
            }
        }
    }
}

/// To samo dla filtrów kategorii: aspekt → opcja → przepis. Pula arkusza
/// kategorii jest już po dopasowaniu do profilu (o ile jest włączone), więc
/// tu nic nie trzeba omijać. Rodzaj dania, smak, mięso i pora w planie biorą
/// najpierw zdjęcia wybrane ręcznie (`RecipeFilterCoverPicks`) — o ile są
/// w puli i pasują.
struct RecipeFacetCovers {
    private var covers: [RecipeFacetKind: [String: Recipe]] = [:]

    /// `values[i]` to wartości aspektów przepisu `recipes[i]`. `category` —
    /// kategoria aspektów (klucz ręcznie wybranych zdjęć); `nil` = sam automat.
    init(
        facets: [RecipeFacet],
        recipes: [Recipe],
        values: [[RecipeFacetKind: Set<String>]],
        category: RecipesCategory? = nil
    ) {
        var picker = RecipeCoverPicker(recipes: recipes, isAvoided: { _ in false })
        for facet in facets {
            var byOption: [String: Recipe] = [:]
            for option in facet.options {
                let preferred = category
                    .flatMap { RecipeFilterCoverPicks.key(facet.kind, in: $0, option: option.id) }
                    .map { RecipeFilterCoverPicks.ids($0) } ?? []
                byOption[option.id] = picker.pick(preferring: preferred) { index in
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
    /// Id przepisu (i UUID z nazwy pliku zdjęcia) → miejsce w puli — do zdjęć
    /// wybranych ręcznie.
    private let positions: [String: Int]

    init(recipes: [Recipe], isAvoided: @escaping (Int) -> Bool) {
        self.recipes = recipes
        self.isAvoided = isAvoided
        var positions: [String: Int] = [:]
        for (index, recipe) in recipes.enumerated() {
            positions[recipe.id.uuidString.lowercased()] = index
            // Plik zdjęcia katalogu = „<uuid przepisu>-<skrót>.webp”.
            if let file = recipe.imageURL?.lastPathComponent, file.count >= 36 {
                let uuid = String(file.prefix(36)).lowercased()
                if positions[uuid] == nil { positions[uuid] = index }
            }
        }
        self.positions = positions
    }

    /// Najpierw przepisy wybrane ręcznie (`ids`, po kolei): ten, który jest
    /// w puli, ma zdjęcie, pasuje, nie ukrywa go profil i nie stoi już na
    /// innym kafelku. Gdy żaden — zwykły wybór (`pick(where:)`).
    mutating func pick(preferring ids: [String], where matches: (Int) -> Bool) -> Recipe? {
        for id in ids {
            guard let index = positions[id.lowercased()] else { continue }
            let recipe = recipes[index]
            guard recipe.imageURL != nil, !isAvoided(index), matches(index) else { continue }
            if used.insert(recipe.id).inserted { return recipe }
        }
        return pick(where: matches)
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
