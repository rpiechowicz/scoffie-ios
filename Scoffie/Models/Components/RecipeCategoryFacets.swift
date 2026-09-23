import Foundation

// Filtry „tylko w tej kategorii” — arkusz otwierany przyciskiem obok
// krzyżyka w liście kategorii (Śniadania, Obiady, …). Każda kategoria ma
// swoje aspekty: śniadanie wybiera się po smaku i rodzaju dania, obiad po
// rodzaju dania i mięsie, przekąskę po smaku, rodzaju i porze.
//
// Katalog nie niesie tagów „na słodko”, „zupa” czy „drób”, więc wartości
// liczą się tu z nazwy dania i składników. Reguły powstały na pełnym
// katalogu (495 przepisów z `prisma/catalog` backendu, 23.09.2026) i dają
// pełne pokrycie tam, gdzie dało się je dać: każdy deser i każda przekąska
// ma rodzaj, każde śniadanie poza jednym — też. Dania, których nie da się
// uczciwie przypisać (np. „Golonka z kapustą” w rodzaju obiadu), nie mają
// wartości w tym aspekcie: wypadają przy zawężeniu rodzaju, ale zostają,
// gdy rodzaj jest dowolny.

// MARK: - Aspekty

enum RecipeFacetKind: String, Hashable, CaseIterable {
    /// Na słodko / na słono.
    case taste
    /// Rodzaj dania — zupa, makaron, owsianka, ciasto…
    case dish
    /// Drób, wieprzowina, wołowina, ryby albo bez mięsa.
    case protein
    /// Pora z planu (II śniadanie, podwieczorek, przekąska) — tylko przekąski.
    case slot
}

struct RecipeFacetOption: Identifiable, Hashable {
    let id: String
    let title: String
}

struct RecipeFacet: Identifiable {
    let kind: RecipeFacetKind
    let title: String
    let options: [RecipeFacetOption]

    var id: RecipeFacetKind { kind }
}

// MARK: - Wybór w jednej kategorii

/// Zaznaczone opcje w arkuszu filtrów kategorii. W obrębie aspektu opcje
/// łączą się przez LUB („zupy albo makarony”), między aspektami — przez I
/// („zupy z drobiem”). Tak działa każdy sklep z filtrami i tego oczekuje
/// ręka: druga zaznaczona opcja w tym samym rzędzie POSZERZA wynik.
struct RecipeCategoryFilter: Equatable {
    var picks: [RecipeFacetKind: Set<String>] = [:]

    var isActive: Bool { picks.values.contains { !$0.isEmpty } }

    /// Liczba zaznaczonych opcji — plakietka na przycisku filtrów kategorii.
    var activeCount: Int { picks.values.reduce(0) { $0 + $1.count } }

    func contains(_ option: String, in kind: RecipeFacetKind) -> Bool {
        picks[kind]?.contains(option) ?? false
    }

    func matches(_ values: [RecipeFacetKind: Set<String>]) -> Bool {
        for (kind, chosen) in picks where !chosen.isEmpty {
            guard let have = values[kind], !have.isDisjoint(with: chosen) else { return false }
        }
        return true
    }

    mutating func toggle(_ option: String, in kind: RecipeFacetKind) {
        var set = picks[kind] ?? []
        if set.contains(option) { set.remove(option) } else { set.insert(option) }
        picks[kind] = set.isEmpty ? nil : set
    }

    /// Ten sam wybór z dołożoną opcją — do liczby „ile zostanie” na kafelku.
    func adding(_ option: String, in kind: RecipeFacetKind) -> RecipeCategoryFilter {
        var next = self
        next.picks[kind, default: []].insert(option)
        return next
    }
}

// MARK: - Definicje i reguły

enum RecipeCategoryFacets {
    /// Aspekty kategorii w kolejności, w jakiej stoją w arkuszu.
    static func facets(for category: RecipesCategory) -> [RecipeFacet] {
        switch category {
        case .breakfast:
            return [tasteFacet, RecipeFacet(kind: .dish, title: "Rodzaj dania", options: [
                .init(id: "porridge", title: "Owsianki i kasze"),
                .init(id: "eggs", title: "Jajka i omlety"),
                .init(id: "bread", title: "Kanapki i tosty"),
                .init(id: "pancakes", title: "Placki i naleśniki"),
                .init(id: "yogurt", title: "Jogurty i smoothie")
            ])]
        case .lunch:
            return [RecipeFacet(kind: .dish, title: "Rodzaj dania", options: [
                .init(id: "soup", title: "Zupy"),
                .init(id: "potatoes", title: "Z ziemniakami"),
                .init(id: "grains", title: "Z ryżem lub kaszą"),
                .init(id: "pasta", title: "Makarony"),
                .init(id: "dumplings", title: "Pierogi i kluski"),
                .init(id: "stew", title: "Gulasze i curry")
            ]), proteinFacet]
        case .dinner:
            return [RecipeFacet(kind: .dish, title: "Rodzaj dania", options: [
                .init(id: "salad", title: "Sałatki"),
                .init(id: "sandwich", title: "Kanapki i wrapy"),
                .init(id: "bake", title: "Zapiekanki i pizza"),
                .init(id: "grains", title: "Makaron, ryż, kasze"),
                .init(id: "potatoes", title: "Z ziemniakami"),
                .init(id: "soup", title: "Zupy i kremy")
            ]), proteinFacet]
        case .snacks:
            return [tasteFacet, RecipeFacet(kind: .dish, title: "Rodzaj", options: [
                .init(id: "bake", title: "Ciasta i wypieki"),
                .init(id: "spoon", title: "Desery"),
                .init(id: "crunchy", title: "Chrupiące"),
                .init(id: "bites", title: "Małe przekąski"),
                .init(id: "dip", title: "Dipy i pasty"),
                .init(id: "drink", title: "Koktajle")
            ]), RecipeFacet(kind: .slot, title: "Pora w planie", options: [
                MealSlot.secondBreakfast, .afternoonSnack, .snack
            ].map { RecipeFacetOption(id: $0.rawValue, title: $0.title) })]
        case .all, .favourite:
            return []
        }
    }

    private static let tasteFacet = RecipeFacet(kind: .taste, title: "Smak", options: [
        .init(id: "sweet", title: "Na słodko"),
        .init(id: "savory", title: "Na słono")
    ])

    private static let proteinFacet = RecipeFacet(kind: .protein, title: "Mięso i ryby", options: [
        .init(id: "poultry", title: "Drób"),
        .init(id: "pork", title: "Wieprzowina"),
        .init(id: "beef", title: "Wołowina"),
        .init(id: "fish", title: "Ryby i owoce morza"),
        .init(id: "veg", title: "Bez mięsa i ryb")
    ])

    /// Wartości przepisu w aspektach jego kategorii. Liczone raz na przepis
    /// (`RecipeFilterFactsCache`), bo arkusz przelicza liczniki przy każdym
    /// stuknięciu.
    static func values(for recipe: Recipe) -> [RecipeFacetKind: Set<String>] {
        let title = " " + RecipeDietClassifier.normalize(recipe.name) + " "
        let ingredients = recipe.ingredients.map {
            FoldedIngredient(name: RecipeDietClassifier.normalize($0.name), department: $0.department ?? "")
        }

        var values: [RecipeFacetKind: Set<String>] = [:]
        switch recipe.category {
        case .breakfast:
            values[.taste] = [taste(title: title, ingredients: ingredients)]
            if let dish = firstMatch(in: title, table: breakfastDishes) { values[.dish] = [dish] }
        case .lunch:
            if let dish = lunchDish(title: title, ingredients: ingredients) { values[.dish] = [dish] }
            values[.protein] = proteins(ingredients)
        case .dinner:
            if let dish = dinnerDish(title: title, ingredients: ingredients) { values[.dish] = [dish] }
            values[.protein] = proteins(ingredients)
        case .snacks:
            values[.taste] = [taste(title: title, ingredients: ingredients)]
            if let dish = firstMatch(in: title, table: snackDishes) { values[.dish] = [dish] }
            let slots = recipe.effectiveSlots.filter { $0.baseCategory == .snacks }.map(\.rawValue)
            values[.slot] = Set(slots)
        case .all, .favourite:
            break
        }
        return values
    }

    // MARK: Składniki

    private struct FoldedIngredient {
        /// Nazwa po `RecipeDietClassifier.normalize` — małe litery, bez polskich znaków.
        let name: String
        /// Dział sklepu z backendu („Mięso”, „Ryby”, „Owoce”…).
        let department: String
    }

    private static func contains(_ text: String, anyOf words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }

    // MARK: Rodzaj dania — pierwszy trafiony wyraz w nazwie

    /// Rodzaj dania to zwykle pierwszy rzeczownik nazwy: „Tost z jajkiem” to
    /// kanapka, „Jajka na miękko z grzankami” — jajka. Wygrywa więc słowo
    /// kluczowe, które stoi w nazwie NAJWCZEŚNIEJ, a nie to, które stoi
    /// wyżej w tabeli.
    private static func firstMatch(in title: String, table: [(String, [String])]) -> String? {
        var best: String?
        var bestOffset = Int.max
        for (kind, words) in table {
            for word in words {
                guard let range = title.range(of: word) else { continue }
                let offset = title.distance(from: title.startIndex, to: range.lowerBound)
                if offset < bestOffset {
                    best = kind
                    bestOffset = offset
                }
            }
        }
        return best
    }

    private static let breakfastDishes: [(String, [String])] = [
        ("porridge", [" owsiank", " jaglank", " kasza", " kasze", " ryz na mleku", " musli", " kuskus", " zupa mleczna", " granol"]),
        ("eggs", [" jajecznic", " omlet", " jajk", " frittat", " szakszuk", " tofucznic", " sniadanie po angielsku"]),
        ("bread", [" kanapk", " tost", " grzank", " bulecz", " bulka", " bajgiel", " wrap", " tortill", " rogalik", " pasta ", " chleb", " zapiekanka chlebowa", " parowk", " pieczarki na toscie"]),
        ("pancakes", [" placusz", " placki", " nalesnik", " pancake", " racuch", " gofr", " syrnik", " leniwe", " serniczki"]),
        ("yogurt", [" jogurt", " skyr", " twaroz", " serek", " parfait", " smoothie", " pudding"])
    ]

    private static let lunchDishes: [(String, [String])] = [
        ("soup", [" zupa", " krem z", " rosol", " barszcz", " zurek", " kapusniak", " grochowk", " kartoflank", " krupnik", " minestrone", " chlodnik", " gazpacho"]),
        ("dumplings", [" pierog", " kopytk", " klusk", " knedl", " lazank", " gnocchi", " placki ziemniaczane", " placki po wegiersku", " krokiet"]),
        ("pasta", [" makaron", " spaghetti", " penne", " tagliatelle", " lasagne", " cannelloni", " tortellini", " mac and cheese", " udon"]),
        ("salad", [" salatk", " tabbouleh"]),
        ("stew", [" gulasz", " curry", " leczo", " bigos", " chili ", " strogonow", " potrawk", " paprykarz", " tikka", " po bretonsku", " kung pao"])
    ]

    private static let dinnerDishes: [(String, [String])] = [
        ("salad", [" salatk", " tabbouleh"]),
        ("soup", [" zupa", " krem z", " chlodnik", " gazpacho"]),
        ("sandwich", [" kanapk", " wrap", " tortill", " quesadill", " burrito", " taco", " fajit", " enchilad", " pita ", " panini", " tost", " bruschett", " grzank", " burger", " hot dog", " pulled pork", " sajgonk", " gofry"]),
        ("bake", [" pizz", " calzone", " lahmacun", " focaccia", " zapiek", " gratin", " parmigiana", " faszerowan"])
    ]

    private static let snackDishes: [(String, [String])] = [
        ("drink", [" koktajl", " smoothie", " lemoniad", " shake"]),
        ("spoon", [" pudding", " budyn", " kisiel", " panna cotta", " tiramisu", " mus ", " lody", " deser", " pucharek", " galaretk", " parfait", " salatka owocowa", " pieczone jablka"]),
        ("bake", [" ciast", " ciesc", " sernik", " brownie", " blondie", " babka", " murzynek", " szarlotk", " muffin", " piernik", " tarta", " cynamonk", " rogalik", " chlebek", " kokosank", " crumble", " wisniowiec", " blok ", " batonik", " kulki", " bulecz", " pizz", " chleb ", " pierozk", " krakers"]),
        ("dip", [" hummus", " guacamole", " tzatziki", " pasta z", " salsa", " dipem z", " dip "]),
        ("crunchy", [" chips", " fryt", " paluszk", " nachos", " krazk", " prazon", " skrzydel", " orzech", " edamame"]),
        ("bites", [" mini ", " klops", " roladk", " koreczk", " szaszl", " jajka faszerowane", " slimaczk", " wrap", " kurczak", " salatka z", " camembert", " jajka"])
    ]

    /// Dania z garnkiem na zapleczu: ryż i kasze w nazwie albo w składzie.
    private static let grainTitles = [" risotto", " pilaw", " kaszotto", " paella", " peczotto", " bowl"]

    private static func sides(_ ingredients: [FoldedIngredient]) -> (grains: Bool, potatoes: Bool, pasta: Bool) {
        var grains = false, potatoes = false, pasta = false
        for ingredient in ingredients {
            let name = ingredient.name
            if name.hasPrefix("makaron") || contains(name, anyOf: ["spaghetti", "gnocchi", "tortellini"]) {
                pasta = true
            }
            // „kaszanka” zaczyna się od „kasza”, a kaszą nie jest.
            if name.hasPrefix("ryz") || name == "kasza" || name.hasPrefix("kasza ")
                || contains(name, anyOf: ["kuskus", "bulgur", "peczak", "komosa", "quinoa"]) {
                grains = true
            }
            if name.hasPrefix("ziemniak") || name.hasPrefix("frytk") {
                potatoes = true
            }
        }
        return (grains, potatoes, pasta)
    }

    private static func lunchDish(title: String, ingredients: [FoldedIngredient]) -> String? {
        if let dish = firstMatch(in: title, table: lunchDishes) { return dish }
        if contains(title, anyOf: grainTitles) { return "grains" }
        let side = sides(ingredients)
        if side.pasta { return "pasta" }
        if side.grains { return "grains" }
        if side.potatoes { return "potatoes" }
        return nil
    }

    private static func dinnerDish(title: String, ingredients: [FoldedIngredient]) -> String? {
        if let dish = firstMatch(in: title, table: dinnerDishes) { return dish }
        if contains(title, anyOf: grainTitles) { return "grains" }
        let side = sides(ingredients)
        if side.pasta || side.grains { return "grains" }
        if side.potatoes { return "potatoes" }
        return nil
    }

    // MARK: Mięso

    private static let poultryWords = ["kurczak", "indyk", "drob", "kacz", "udko", "podudzie", "skrzydel"]
    private static let porkWords = ["wieprz", "schab", "karkow", "zeberk", "boczek", "kielbas", "szynk", "golonk", "kaszank", "salami", "parowk", "skwark", "chorizo", "slonin", "smalec", "pancett", "bekon"]
    private static let beefWords = ["wolow", "stek", "antrykot", "rostbef", "cielec"]
    private static let fishWords = ["losos", "dorsz", "mintaj", "pstrag", "makrel", "tunczyk", "sardyn", "krewet", "sledz", "halibut", "tilapi", "owoce morza", "kalmar", "malz"]

    private static func proteins(_ ingredients: [FoldedIngredient]) -> Set<String> {
        var result: Set<String> = []
        for ingredient in ingredients {
            let name = ingredient.name
            if contains(name, anyOf: poultryWords) {
                result.insert("poultry")
            } else if contains(name, anyOf: porkWords) || (name.hasPrefix("poledwic") && !name.contains("indyk")) {
                // „polędwica z indyka” to wędlina drobiowa — łapie ją gałąź wyżej.
                result.insert("pork")
            }
            if contains(name, anyOf: beefWords) { result.insert("beef") }
            if ingredient.department == ProductConstants.Department.fish || contains(name, anyOf: fishWords) {
                result.insert("fish")
            }
        }
        // „Bez mięsa i ryb” tylko na dowodzie: przepis bez składników nie jest
        // wegetariański, tylko nieznany.
        if result.isEmpty, !ingredients.isEmpty { result.insert("veg") }
        return result
    }

    // MARK: Smak

    private static let sweetWords = ["cukier", "miod", "syrop", "dzem", "kakao", "czekolad", "budyn", "galaretk", "biszkopt", "herbatnik", "cynamon", "rodzyn", "wanili", "mascarpone", "granol", "maslo orzechowe", "nutell", "powidl", "konfitur", "bita smietan", "smietanka 30", "daktyl", "zurawin", "kisiel"]
    private static let savoryWords = ["cebul", "czosnek", "szczypior", "natka", "koperek", "pieprz", "pomidor", "papryka", "ogorek", "rzodkiew", "szpinak", "pieczark", "musztard", "majonez", "ketchup", "sos sojow", "oliwk", "rukol", "salat", "por", "kapust", "brokul", "cukini", "fasol", "ciecierzyc", "soczewic", "kukurydz", "awokado", "hummus", "chili", "kmin", "oregano", "bazyli", "tymianek", "majeranek", "curry"]
    private static let cheeseWords = ["ser zolty", "feta", "parmezan", "mozzarell", "gouda", "cheddar", "camembert", "halloumi", "gorgonzol", "ser plesniow", "ser kozi"]
    private static let sourFruit = ["cytryn", "limonk", "awokado"]

    /// Słodkie kontra słone — jawne „na słodko” / „na wytrawnie” w nazwie
    /// rozstrzyga od razu, w pozostałych przypadkach ważą składniki: mięso
    /// i ryby mocno, owoce i cukier średnio, warzywa, sery i zioła lekko.
    /// Remis idzie na stronę słoną — bezpieczniejszą pomyłką jest pokazać
    /// kanapkę wśród słonych niż deser wśród obiadowych przekąsek.
    private static func taste(title: String, ingredients: [FoldedIngredient]) -> String {
        if title.contains("na slodko") { return "sweet" }
        if title.contains("na wytrawnie") || title.contains("wytrawn") { return "savory" }

        var sweet = 0.0
        var savory = 0.0
        for ingredient in ingredients {
            let name = ingredient.name
            let department = ingredient.department
            if department == ProductConstants.Department.meat || department == ProductConstants.Department.fish {
                savory += 3
            }
            if department == ProductConstants.Department.fruits, !contains(name, anyOf: sourFruit) {
                sweet += 2
            }
            if contains(name, anyOf: sweetWords) { sweet += 2 }
            if contains(name, anyOf: savoryWords) { savory += 1 }
            if contains(name, anyOf: cheeseWords) { savory += 2 }
            if name == "jajko" { savory += 0.5 }
        }
        return sweet > savory ? "sweet" : "savory"
    }
}
