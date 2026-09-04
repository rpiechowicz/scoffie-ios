import Foundation

/// Co przepis „zawiera” z punktu widzenia diety i alergenów.
///
/// Od plastra D źródłem prawdy są tagi policzone na serwerze z kuratorowanych
/// tagów składników (`Recipe.allergens` / `Recipe.dietTags`) — profil buduje
/// `RecipeDietProfile.fromServerTags`. Heurystyka po nazwach składników
/// (`RecipeDietClassifier`) zostaje WYŁĄCZNIE jako fallback, gdy serwer tagów
/// nie przysłał (stary backend, cache sprzed zmiany, mocki): dział daje
/// zgrubny sygnał („Mięso” → mięso), a słowniki nazw go doprecyzowują.
///
/// Zasada bezpieczeństwa jest asymetryczna i celowo taka zostaje:
/// - **alergen** wykrywamy nadmiarowo (owies liczy się jako gluten, masło jako
///   laktoza) — fałszywy alarm tylko coś ukryje, przeoczenie może zaszkodzić;
/// - **dieta** blokuje tylko na dowodzie — przepis bez składników (stary cache,
///   mock) nie zostaje uznany za mięsny, bo nie ma z czego tego orzec.
struct RecipeDietProfile: Equatable {
    /// Alergeny wykryte w składnikach.
    var allergens: Set<Allergen> = []

    /// Czy w przepisie jest mięso / wędlina / smalec / bulion mięsny.
    var containsMeat: Bool = false

    /// Ryby i owoce morza (dla pescetariańskiej rozdzielone od mięsa).
    var containsFish: Bool = false

    /// Nabiał — bez roślinnych „mlek” i margaryny.
    var containsDairy: Bool = false

    /// Jaja, również te ukryte w majonezie.
    var containsEggs: Bool = false

    /// Produkty odzwierzęce spoza powyższych: miód, żelatyna, kolagen.
    var containsOtherAnimal: Bool = false

    /// Zboża i pieczywo — blokada dla paleo.
    var containsGrains: Bool = false

    /// Strączki — blokada dla paleo.
    var containsLegumes: Bool = false

    /// Cukier i przetworzone słodycze / przekąski / wędliny — blokada dla paleo.
    var containsProcessed: Bool = false

    /// Czy w ogóle było na czym pracować. `false` = przepis przyszedł bez
    /// listy składników, więc każde „nie zawiera” jest niewiedzą, nie faktem.
    var hasIngredientData: Bool = false

    /// Czy przepis pasuje do wybranego sposobu odżywiania.
    ///
    /// Keto idzie po makrach, nie po składnikach — „bardzo niska zawartość
    /// węglowodanów” to liczba, a nie lista produktów. Próg jest ten sam co w
    /// chipie „Niskowęglowodanowe” w arkuszu filtrów (≤ 20 g / porcję), żeby
    /// dwa miejsca w aplikacji nie obiecywały czegoś innego.
    func satisfies(_ diet: DietPreference, recipe: Recipe) -> Bool {
        switch diet {
        case .none:
            return true

        case .vegetarian:
            guard hasIngredientData else { return true }
            return !containsMeat && !containsFish

        case .vegan:
            guard hasIngredientData else { return true }
            return !containsMeat && !containsFish && !containsDairy
                && !containsEggs && !containsOtherAnimal

        case .pescatarian:
            guard hasIngredientData else { return true }
            return !containsMeat

        case .keto:
            guard recipe.hasNutritionData else { return false }
            return recipe.nutritionPerServing.carbs <= 20

        case .paleo:
            guard hasIngredientData else { return true }
            return !containsGrains && !containsLegumes && !containsDairy && !containsProcessed

        case .highProtein:
            // Udział energii z białka, nie same gramy. 20 % to próg
            // oświadczenia „wysoka zawartość białka" z rozporządzenia UE
            // 1924/2006 i jedyna definicja, która działa niezależnie od
            // wielkości porcji.
            //
            // Chip „Wysokobiałkowe" w arkuszu filtrów mierzy co innego
            // (≥ 20 g na porcję) i tak zostaje: tam chodzi o odsianie
            // konkretnego posiłku, tu o styl odżywiania. 300-kalorycznemu
            // śniadaniu z 18 g białka bliżej do wysokobiałkowego niż
            // obiadowi z 22 g przy 900 kcal.
            guard recipe.hasNutritionData else { return false }
            let nutrition = recipe.nutritionPerServing
            guard nutrition.kcal > 0 else { return false }
            return (nutrition.protein * 4) / nutrition.kcal >= 0.20
        }
    }

    /// Czy przepis jest wolny od wszystkich zaznaczonych alergenów.
    func avoids(_ avoided: Set<Allergen>) -> Bool {
        guard !avoided.isEmpty else { return true }
        return allergens.isDisjoint(with: avoided)
    }

    /// Alergeny z przepisu, których użytkownik unika — do plakietek
    /// ostrzegawczych, gdy personalizacja jest wyłączona.
    func conflicting(with avoided: Set<Allergen>) -> [Allergen] {
        Allergen.allCases.filter { allergens.contains($0) && avoided.contains($0) }
    }

    /// Profil z tagów serwera — parytet z `src/common/diet-tags.ts` i
    /// `src/recipes/diet-rules.util.ts` w backendzie. Nieznane id (nowszy
    /// serwer) są pomijane: alergen, którego enum nie zna, i tak nie ma chipa.
    ///
    /// `hasIngredientData` jest prawdą, gdy przepis ma składniki ALBO jakikolwiek
    /// tag — projekcja listy potrafi przyjść bez składników, a tagi już
    /// dowodzą, że było na czym pracować.
    static func fromServerTags(
        allergens serverAllergens: [String],
        dietTags: [String],
        hasIngredients: Bool
    ) -> RecipeDietProfile {
        let tags = Set(dietTags)
        var profile = RecipeDietProfile()
        profile.allergens = Set(serverAllergens.compactMap(Allergen.init(rawValue:)))
        profile.containsMeat = tags.contains("MEAT")
        profile.containsFish = tags.contains("FISH") || tags.contains("CRUSTACEAN")
        profile.containsDairy = tags.contains("DAIRY")
        profile.containsEggs = tags.contains("EGG")
        profile.containsOtherAnimal = tags.contains("ANIMAL_OTHER")
        profile.containsGrains = tags.contains("GRAIN") || tags.contains("GLUTEN_GRAIN")
        profile.containsLegumes = tags.contains("LEGUME")
        profile.containsProcessed = tags.contains("PROCESSED")
        profile.hasIngredientData = hasIngredients || !tags.isEmpty || !serverAllergens.isEmpty
        return profile
    }
}

// MARK: - Klasyfikator

enum RecipeDietClassifier {
    /// Normalizacja pod dopasowanie: małe litery, bez polskich znaków,
    /// interpunkcja zamieniona na spacje. „Mleko kokosowe z puszki” →
    /// „mleko kokosowe z puszki”, „Ser feta” → „ser feta”.
    static func normalize(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(raw.count)

        for scalar in raw.lowercased().unicodeScalars {
            switch scalar {
            case "ą": out.append("a")
            case "ć": out.append("c")
            case "ę": out.append("e")
            case "ł": out.append("l")
            case "ń": out.append("n")
            case "ó": out.append("o")
            case "ś": out.append("s")
            case "ź", "ż": out.append("z")
            default:
                if CharacterSet.alphanumerics.contains(scalar) {
                    out.unicodeScalars.append(scalar)
                } else {
                    out.append(" ")
                }
            }
        }

        return out
    }

    static func profile(for recipe: Recipe) -> RecipeDietProfile {
        var profile = RecipeDietProfile()
        profile.hasIngredientData = !recipe.ingredients.isEmpty

        for ingredient in recipe.ingredients {
            let name = normalize(ingredient.name)
            let words = name.split(separator: " ").map(String.init)
            let department = ingredient.department.map(normalize) ?? ""

            classify(name: name, words: words, department: department, into: &profile)
        }

        return profile
    }

    // MARK: - Pojedynczy składnik

    private static func classify(
        name: String,
        words: [String],
        department: String,
        into profile: inout RecipeDietProfile
    ) {
        let isPlantAlternative = contains(name, anyOf: Keywords.plantAlternativePhrases)
        let isGlutenFreeVariant = contains(name, anyOf: Keywords.glutenFreePhrases)

        // ── Mięso ──
        if department == Department.meat
            || hasWord(words, prefixedBy: Keywords.meatStems)
            || contains(name, anyOf: Keywords.meatPhrases) {
            profile.containsMeat = true
            if hasWord(words, prefixedBy: Keywords.processedMeatStems) {
                profile.containsProcessed = true
            }
        }

        // ── Ryby i owoce morza ──
        if department == Department.fish
            || hasWord(words, prefixedBy: Keywords.fishStems)
            || contains(name, anyOf: Keywords.seafoodPhrases) {
            profile.containsFish = true
            profile.allergens.insert(.fish)
        }
        // Skorupiaki nie mają osobnego alergenu — jedyna pozycja katalogu to
        // krewetka, siedząca w dziale „Ryby". Wykrywanie zostaje, bo
        // `containsFish` decyduje o diecie wegetariańskiej, ale alergen jest
        // wspólny: „Ryby i owoce morza".
        if hasWord(words, prefixedBy: Keywords.shellfishStems)
            || hasWord(words, equalTo: Keywords.shellfishWords)
            || contains(name, anyOf: Keywords.seafoodPhrases) {
            profile.containsFish = true
            profile.allergens.insert(.fish)
        }

        // ── Nabiał ──
        // Dział „Nabiał” zbiera też napoje roślinne i jajka, więc sam dział nie
        // wystarcza — stąd wyjątek na „mleko owsiane / migdałowe / …” i osobna
        // gałąź na jajko niżej.
        if hasWord(words, prefixedBy: Keywords.dairyStems), !isPlantAlternative {
            profile.containsDairy = true
            // „bez laktozy” zdejmuje sam alergen — produkt nadal jest nabiałem.
            if !contains(name, anyOf: ["bez laktozy", "bezlaktozow"]) {
                profile.allergens.insert(.lactose)
            }
        }

        // ── Jaja ──
        if hasWord(words, prefixedBy: Keywords.eggStems) {
            profile.containsEggs = true
            profile.allergens.insert(.eggs)
        }

        // ── Pozostałe produkty odzwierzęce ──
        if hasWord(words, prefixedBy: Keywords.otherAnimalStems) {
            profile.containsOtherAnimal = true
        }

        // ── Zboża glutenowe i wypieki ──
        if department == Department.bakery
            || hasWord(words, prefixedBy: Keywords.glutenGrainStems)
            || hasWord(words, equalTo: Keywords.glutenGrainWords) {
            profile.containsGrains = true
            if !isGlutenFreeVariant {
                profile.allergens.insert(.gluten)
            }
        }

        // Zboża bezglutenowe (ryż, gryka, jaglana, komosa, kukurydza) to nadal
        // zboża — paleo je odrzuca, filtr glutenu nie.
        if department == Department.grains
            || hasWord(words, prefixedBy: Keywords.glutenFreeGrainStems) {
            profile.containsGrains = true
        }

        // ── Strączki ──
        if hasWord(words, prefixedBy: Keywords.legumeStems) {
            profile.containsLegumes = true
        }

        // ── Orzechy / orzeszki ziemne ──
        // Kolejność ma znaczenie: „orzeszki ziemne” i „masło orzechowe” to
        // arachidy, nie orzechy drzewne — inaczej wpadłyby w rdzeń „orzech”.
        if hasWord(words, prefixedBy: Keywords.peanutStems)
            || contains(name, anyOf: Keywords.peanutPhrases) {
            profile.allergens.insert(.peanuts)
        } else if hasWord(words, prefixedBy: Keywords.nutStems) {
            profile.allergens.insert(.nuts)
        }

        // ── Soja ──
        if hasWord(words, prefixedBy: Keywords.soyStems) {
            profile.allergens.insert(.soy)
            profile.containsLegumes = true
            // Sos sojowy warzy się na pszenicy — to najczęstsze ukryte źródło
            // glutenu w kuchni domowej.
            if contains(name, anyOf: ["sos sojowy"]), !isGlutenFreeVariant {
                profile.allergens.insert(.gluten)
                profile.containsGrains = true
            }
        }

        // ── Przetworzone / cukier ──
        if department == Department.sweets
            || department == Department.confectionery
            || hasWord(words, prefixedBy: Keywords.processedStems) {
            profile.containsProcessed = true
        }
    }

    // MARK: - Dopasowanie

    /// Czy któreś ze słów nazwy zaczyna się od danego rdzenia. Prefiks na
    /// słowie, a nie `contains` na całym stringu — inaczej „ser” trafiałby w
    /// „konserwa”, a „ryb” w „porzeczka”.
    private static func hasWord(_ words: [String], prefixedBy stems: [String]) -> Bool {
        for word in words {
            for stem in stems where word.hasPrefix(stem) {
                return true
            }
        }
        return false
    }

    /// Dopasowanie na całe słowo — dla krótkich nazw, przy których prefiks
    /// łapałby za dużo („maca” vs „maczanka”, „pita” vs „jogurt pitny”).
    private static func hasWord(_ words: [String], equalTo exact: [String]) -> Bool {
        words.contains { exact.contains($0) }
    }

    private static func contains(_ name: String, anyOf phrases: [String]) -> Bool {
        phrases.contains { name.contains($0) }
    }
}

// MARK: - Działy katalogu

/// Znormalizowane nazwy działów przypisywanych składnikom przez backend
/// (`scripts/load-ingredient-catalog.ts` → `CATEGORY_BY_FILE`).
private enum Department {
    static let meat = "mieso"
    static let fish = "ryby"
    static let bakery = "piekarnia"
    static let grains = "zboza i makarony"
    static let sweets = "przekaski i slodycze"
    static let confectionery = "cukiernia"
}

// MARK: - Słowniki

/// Rdzenie słów (dopasowanie po prefiksie) i frazy wielowyrazowe — wszystko
/// znormalizowane, bez polskich znaków, małymi literami.
///
/// Zestaw wyrósł z katalogu składników backendu
/// (`prisma/catalog/ingredients-*-pl-v1.txt`) i został poszerzony o produkty
/// spoza katalogu, które i tak trafiają do przepisów. Rdzenie są celowo
/// wydłużone tam, gdzie krótszy wariant zbierał sąsiadów — `miesn`, a nie
/// `mies`, bo to drugie łapie „mieszankę warzywną”.
private enum Keywords {
    static let meatStems = [
        "mieso", "miesn", "kurczak", "kurcze", "indyk", "wolow", "wieprz",
        "schab", "boczek", "szynk", "kielbas", "kabanos", "salami", "parowk",
        "baleron", "karkowk", "poledwic", "pasztet", "kaszank", "wedlin",
        "smalec", "udziec", "podudzie", "skrzydelk", "chorizo", "bekon",
        "baranin", "jagniec", "cielec", "cielic", "kaczk", "krolik",
        "dziczyzn", "drobiow", "mortadel", "lopatk"
    ]

    static let meatPhrases = [
        "noga z kurczaka", "noga z indyka", "bulion drobiowy",
        "bulion miesny", "bulion wolowy", "gulasz wolowy"
    ]

    static let processedMeatStems = [
        "kielbas", "kabanos", "salami", "mortadel", "wedlin", "pasztet",
        "parowk", "baleron", "chorizo", "kaszank"
    ]

    static let fishStems = [
        "ryb", "dorsz", "karp", "losos", "pstrag", "sandacz", "sledz",
        "tunczyk", "makrel", "halibut", "sardynk", "anchois", "morszczuk",
        "panga", "mintaj", "szprot", "kawior", "flader"
    ]

    static let shellfishStems = [
        "krewetk", "malz", "omulek", "kalmar", "osmiornic", "krab",
        "langust", "homar", "przegrzebk", "skorupiak"
    ]

    static let shellfishWords = ["rak", "raki", "raka"]

    static let seafoodPhrases = ["owoce morza", "owocow morza", "owocami morza"]

    static let dairyStems = [
        "mlek", "mlecz", "smietan", "smietank", "jogurt", "kefir", "maslank",
        "maslo", "ser", "serek", "serow", "twarog", "twarozek", "mozzarell",
        "feta", "fety", "parmezan", "ricott", "mascarpone", "halloumi",
        "camembert", "cheddar", "goud", "edamski", "skyr", "serwatk",
        "bryndz", "oscypek"
    ]

    /// Nazwy, które wpadają w rdzenie nabiału, ale nabiałem nie są.
    /// „Masło klarowane” tu nie trafia — to nadal produkt mleczny.
    static let plantAlternativePhrases = [
        "mleko owsiane", "mleko migdalowe", "mleko kokosowe", "mleko sojowe",
        "mleko ryzowe", "mleko roslinne", "mleko z orzechow",
        "napoj owsiany", "napoj sojowy", "napoj migdalowy", "napoj ryzowy",
        "napoj kokosowy", "napoj roslinny", "jogurt sojowy", "jogurt kokosowy",
        "jogurt roslinny", "ser weganski", "smietana roslinna",
        "smietana kokosowa", "margaryna roslinna", "maslo orzechowe",
        "maslo migdalowe", "maslo kokosowe", "serek weganski"
    ]

    static let eggStems = ["jaj", "zoltk", "majonez"]

    static let otherAnimalStems = ["miod", "zelatyn", "kolagen", "smalec"]

    /// Zboża glutenowe i wypieki. Owies jest tu świadomie: w UE figuruje wśród
    /// zbóż glutenowych, a płatki owsiane z półki są prawie zawsze
    /// zanieczyszczone pszenicą.
    static let glutenGrainStems = [
        "maka", "pszen", "zytn", "zyto", "jeczmien", "orkisz", "chleb",
        "bulk", "bagietk", "tortill", "wrap", "makaron", "kuskus", "bulgur",
        "owsian", "owies", "grahamk", "kajzerk", "rogalik", "precel",
        "krakers", "biszkopt", "ciastk", "ciasto", "ciasta", "muffin",
        "paczek", "drozdzowk", "panierk", "grzank", "sucharek", "seitan",
        "kasza", "kaszy", "manna", "kuskus", "spaghetti", "penne", "lazani",
        // Granola i musli to płatki owsiane (plus często pszenica), zakwas na
        // żurek to mąka żytnia — bez tych rdzeni cztery dania z katalogu
        // przechodziły filtr bezglutenowy.
        "granol", "musli", "muesli", "zakwas"
    ]

    static let glutenGrainWords = ["maca", "pita", "pity", "bulka", "tost", "tosty"]

    static let glutenFreePhrases = [
        "bezglutenow", "bez glutenu", "maka ziemniaczana", "maka kukurydziana",
        "maka ryzowa", "maka gryczana", "maka migdalowa", "maka kokosowa",
        "makaron ryzowy", "makaron gryczany", "tortilla kukurydziana",
        "kasza gryczana", "kasza jaglana", "kasza kukurydziana"
    ]

    static let glutenFreeGrainStems = [
        "ryz", "gryczan", "gryk", "jaglan", "komos", "kukurydz", "quinoa",
        "amarantus", "tapiok"
    ]

    static let legumeStems = [
        "fasol", "ciecierzyc", "soczewic", "groszek", "groch", "bobu",
        "hummus", "edamame"
    ]

    static let nutStems = [
        "orzech", "orzesz", "migdal", "laskow", "nerkowc", "pistacj",
        "pekan", "makadami", "pinior"
    ]

    static let peanutStems = ["arachid", "fistasz"]

    static let peanutPhrases = [
        "orzeszek ziemny", "orzeszki ziemne", "orzeszkow ziemnych",
        "orzech ziemny", "maslo orzechowe", "maslem orzechowym"
    ]

    static let soyStems = ["soja", "soji", "soi", "sojow", "tofu", "tempeh", "edamame"]

    static let processedStems = [
        "cukier", "cukru", "syrop", "czekolad", "zelk", "baton", "chips",
        "wafel", "krakers", "paluszek", "popcorn", "draze", "ciastk",
        "biszkopt", "margaryn", "ketchup", "kisiel", "budyn", "galaretk",
        "chrupk"
    ]
}

// MARK: - Cache

/// Profil zależy tylko od listy składników i makr, a te w obrębie sesji się nie
/// zmieniają — za to `visibleRecipes` przelicza się przy każdym renderze listy.
/// Bez pamięci podręcznej każdy scroll przemielałby kilkaset nazw przez
/// normalizację i słowniki.
@MainActor
enum RecipeDietProfileCache {
    private static var storage: [UUID: (fingerprint: Int, profile: RecipeDietProfile)] = [:]

    static func profile(for recipe: Recipe) -> RecipeDietProfile {
        // Lista przepisów potrafi przyjść uboższa niż szczegóły, więc wpis musi
        // się unieważnić, gdy ten sam przepis wróci z pełniejszym składem —
        // albo gdy po przeładowaniu doszły tagi z serwera.
        var hasher = Hasher()
        hasher.combine(recipe.ingredients.count)
        hasher.combine(recipe.nutrition.carbs)
        hasher.combine(recipe.servings)
        hasher.combine(recipe.dietTags)
        hasher.combine(recipe.allergens)
        let fingerprint = hasher.finalize()

        if let cached = storage[recipe.id], cached.fingerprint == fingerprint {
            return cached.profile
        }

        // Tagi z serwera wygrywają z heurystyką; `nil` = serwer ich nie zna.
        let profile: RecipeDietProfile
        if let dietTags = recipe.dietTags {
            profile = RecipeDietProfile.fromServerTags(
                allergens: recipe.allergens ?? [],
                dietTags: dietTags,
                hasIngredients: !recipe.ingredients.isEmpty
            )
        } else {
            profile = RecipeDietClassifier.profile(for: recipe)
        }
        storage[recipe.id] = (fingerprint, profile)
        return profile
    }
}

extension Recipe {
    /// Profil dietetyczny przepisu — liczony leniwie i zapamiętywany.
    @MainActor
    var dietProfile: RecipeDietProfile {
        RecipeDietProfileCache.profile(for: self)
    }
}
