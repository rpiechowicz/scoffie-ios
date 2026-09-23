import Foundation

/// Profil odżywczy przepisu — progi, na których stoją kafelki „Cechy”
/// w arkuszu filtrów.
///
/// Progi są absolutne i liczone **na porcję** (`Recipe.nutritionPerServing`),
/// nie na 100 g. Tak liczy je użytkownik patrzący na talerz, a na 100 g i tak
/// nie da się ich policzyć bez wagi gotowego dania, której model nie trzyma.
/// Wartości trzymają się okolic progów oświadczeń żywieniowych UE,
/// przeskalowanych na typową porcję posiłku.
enum RecipeNutritionTag: String, CaseIterable, Identifiable, Codable {
    case highProtein
    case lowCarb
    case lowFat
    case highFiber
    case lowSalt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highProtein: return "Wysokobiałkowe"
        case .lowCarb:     return "Niskowęglowodanowe"
        case .lowFat:      return "Niskotłuszczowe"
        case .highFiber:   return "Bogate w błonnik"
        case .lowSalt:     return "Mało soli"
        }
    }

    var icon: String {
        switch self {
        case .highProtein: return "figure.strengthtraining.traditional"
        case .lowCarb:     return "chart.line.downtrend.xyaxis"
        case .lowFat:      return "drop"
        case .highFiber:   return "leaf"
        case .lowSalt:     return "aqi.low"
        }
    }

    /// Opis progu — żeby „wysokobiałkowe” nie było magiczną obietnicą bez
    /// liczby (VoiceOver czyta go przy kafelku).
    var thresholdDescription: String {
        switch self {
        case .highProtein: return "białko ≥ 20 g"
        case .lowCarb:     return "węglowodany ≤ 20 g"
        case .lowFat:      return "tłuszcz ≤ 10 g"
        case .highFiber:   return "błonnik ≥ 6 g"
        case .lowSalt:     return "sól ≤ 1 g"
        }
    }

    func matches(_ recipe: Recipe) -> Bool {
        // Bez policzonych makr nie ma czego obiecywać — przepis z pustą
        // tabelą wartości odżywczych wypadłby inaczej jako „niskotłuszczowy”
        // tylko dlatego, że tłuszcz wynosi 0 z braku danych.
        guard recipe.hasNutritionData else { return false }

        let nutrition = recipe.nutritionPerServing
        switch self {
        case .highProtein: return nutrition.protein >= 20
        case .lowCarb:     return nutrition.carbs <= 20
        case .lowFat:      return nutrition.fat <= 10
        case .highFiber:   return nutrition.fiber >= 6
        case .lowSalt:     return nutrition.salt <= 1
        }
    }
}

// MARK: - Dieta

/// Kafelki „Dieta” w arkuszu filtrów. Zaznaczone łączą się przez AND.
///
/// Filtr jest ostrzejszy niż profil z Ustawień: profil przepuszcza przepis
/// bez składników (nie ma dowodu, że jest mięsny), a kafelek „Wege” go nie
/// pokazuje — kto zaznacza dietę, prosi o przepisy, o których WIADOMO, że
/// ją spełniają.
enum RecipeDietFilter: String, CaseIterable, Identifiable {
    case lactoseFree
    case vegetarian
    case vegan
    case withFish
    case glutenFree
    case keto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lactoseFree: return "Bez laktozy"
        case .vegetarian:  return "Wege"
        case .vegan:       return "Wegańska"
        case .withFish:    return "Z rybą"
        case .glutenFree:  return "Bez glutenu"
        case .keto:        return "Keto"
        }
    }

    /// Kafelki, których nie ma po co zaznaczać, bo tę samą rzecz trzyma już
    /// profil z Ustawień („Dopasowane do Ciebie”) — rysują się z kłódką.
    static func lockedByProfile(_ personalization: RecipePersonalization) -> Set<RecipeDietFilter> {
        var locked: Set<RecipeDietFilter> = []
        switch personalization.diet {
        case .vegetarian: locked.insert(.vegetarian)
        case .vegan:      locked.insert(.vegan)
        case .keto:       locked.insert(.keto)
        default:          break
        }
        if personalization.avoidedAllergens.contains(.lactose) { locked.insert(.lactoseFree) }
        if personalization.avoidedAllergens.contains(.gluten) { locked.insert(.glutenFree) }
        return locked
    }

    @MainActor
    func matches(_ recipe: Recipe) -> Bool {
        let profile = recipe.dietProfile
        switch self {
        case .lactoseFree: return profile.hasIngredientData && profile.avoids([.lactose])
        case .vegetarian:  return profile.hasIngredientData && profile.satisfies(.vegetarian, recipe: recipe)
        case .vegan:       return profile.hasIngredientData && profile.satisfies(.vegan, recipe: recipe)
        case .withFish:    return profile.containsFish
        case .glutenFree:  return profile.hasIngredientData && profile.avoids([.gluten])
        // Ten sam próg co „Ketogeniczna” w Ustawieniach — dwa miejsca
        // w aplikacji nie mogą obiecywać czegoś innego pod tą samą nazwą.
        case .keto:        return profile.satisfies(.keto, recipe: recipe)
        }
    }
}

// MARK: - Cechy

/// Kafelki „Cechy” w arkuszu filtrów. Zaznaczone łączą się przez AND.
///
/// Makieta miała tu „Jedno naczynie”, „Do pudełka”, „Budżetowe” i „Na zimno”
/// — katalog tych cech nie niesie, więc kafelek niczego by nie odsiał albo
/// odsiał na zgadywanie. Stoją tu cechy, które da się policzyć z danych.
/// „Niskowęglowodanowe” nie ma osobnego kafelka, bo to ten sam próg co
/// „Keto” w Diecie.
enum RecipeTraitFilter: String, CaseIterable, Identifiable {
    case highProtein
    case lowFat
    case highFiber
    case lowSalt
    case favourites
    case thermomix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highProtein: return RecipeNutritionTag.highProtein.title
        case .lowFat:      return RecipeNutritionTag.lowFat.title
        case .highFiber:   return RecipeNutritionTag.highFiber.title
        case .lowSalt:     return RecipeNutritionTag.lowSalt.title
        case .favourites:  return "Ulubione"
        case .thermomix:   return "Thermomix"
        }
    }

    /// Doprecyzowanie dla VoiceOver — na ekranie pod nazwą stoi liczba.
    var accessibilityDetail: String? {
        switch self {
        case .highProtein: return RecipeNutritionTag.highProtein.thresholdDescription + " na porcję"
        case .lowFat:      return RecipeNutritionTag.lowFat.thresholdDescription + " na porcję"
        case .highFiber:   return RecipeNutritionTag.highFiber.thresholdDescription + " na porcję"
        case .lowSalt:     return RecipeNutritionTag.lowSalt.thresholdDescription + " na porcję"
        case .favourites:  return "przepisy z serduszkiem"
        case .thermomix:   return "przepisy z odpowiednikiem w Cookidoo"
        }
    }

    func matches(_ recipe: Recipe) -> Bool {
        switch self {
        case .highProtein: return RecipeNutritionTag.highProtein.matches(recipe)
        case .lowFat:      return RecipeNutritionTag.lowFat.matches(recipe)
        case .highFiber:   return RecipeNutritionTag.highFiber.matches(recipe)
        case .lowSalt:     return RecipeNutritionTag.lowSalt.matches(recipe)
        case .favourites:  return recipe.favourite
        case .thermomix:   return recipe.isThermomix
        }
    }
}

// MARK: - Wykluczone składniki

/// Wykluczony składnik albo cała grupa jego rodzajów.
///
/// Składnik to nazwa z katalogu backendu (`RecipeIngredient.name`, w katalogu
/// już kanoniczna i unikalna). Grupa to wspólny pierwszy wyraz nazw w jednym
/// dziale — „papryka czerwona”, „papryka żółta” → „Papryka”. Dział jest
/// częścią grupy, bo „papryka” w Warzywach i „papryka słodka mielona”
/// w Przyprawach to dla kogoś, kto nie znosi świeżej papryki, dwie różne
/// rzeczy.
///
/// Klucz liczy się z samej nazwy i działu, bez katalogu — dzięki temu lista
/// Przepisów odsiewa po nim tak samo jak arkusz, który zna cały katalog.
struct IngredientExclusion: Hashable, Identifiable {
    enum Kind: Hashable { case item, group }

    let kind: Kind
    /// Nazwa składnika albo rdzeń grupy — małymi literami.
    let name: String
    /// Dział grupy. Składnik go nie potrzebuje: nazwy w katalogu są unikalne.
    let department: String?

    var id: String {
        switch kind {
        case .item:  return "item:\(name)"
        case .group: return "group:\(department ?? "")|\(name)"
        }
    }

    var isGroup: Bool { kind == .group }

    /// Nazwa na ekranie — z wielkiej litery, jak w szczególe przepisu.
    var title: String { Self.capitalized(name) }

    /// Etykieta chipa. Grupa dostaje dopisek, bo „Cebula” jako chip nie mówi,
    /// czy wykluczona jest zwykła cebula, czy każda.
    var chipTitle: String { isGroup ? "\(title) · wszystkie" : title }

    static func item(_ rawName: String) -> IngredientExclusion {
        IngredientExclusion(kind: .item, name: normalizedName(rawName), department: nil)
    }

    static func group(stem: String, department: String) -> IngredientExclusion {
        IngredientExclusion(kind: .group, name: stem, department: department)
    }

    // MARK: Liczenie kluczy

    /// Wyrazy, po których nazwa przestaje być „rodzajem” pierwszego wyrazu:
    /// „filet z kurczaka” i „filet z indyka” to nie dwa rodzaje filetu.
    private static let connectors: Set<Substring> = ["z", "ze", "w", "we", "do", "na", "bez", "od", "po"]

    static func normalizedName(_ raw: String) -> String {
        raw.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func normalizedDepartment(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ProductConstants.Department.other : trimmed
    }

    /// Rdzeń grupy dla nazwy już znormalizowanej, albo `nil`, gdy nazwa do
    /// żadnej grupy nie należy.
    static func groupStem(ofNormalized name: String) -> String? {
        let words = name.split(separator: " ")
        guard let first = words.first, first.count >= 3 else { return nil }
        if words.count >= 2, connectors.contains(words[1]) { return nil }
        return String(first)
    }

    /// Klucze, po których dany składnik przepisu da się wykluczyć: on sam
    /// i — jeśli ma — jego grupa.
    static func keys(forIngredientNamed rawName: String, department rawDepartment: String?) -> [IngredientExclusion] {
        let name = normalizedName(rawName)
        guard !name.isEmpty else { return [] }
        let item = IngredientExclusion(kind: .item, name: name, department: nil)
        guard let stem = groupStem(ofNormalized: name) else { return [item] }
        return [item, .group(stem: stem, department: normalizedDepartment(rawDepartment))]
    }

    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

// MARK: - Zestaw filtrów

/// Zestaw filtrów z arkusza „Filtry” na widoku Przepisów.
///
/// Puste kolekcje / `nil` znaczą „bez ograniczeń”, więc domyślna instancja
/// (`RecipeFilterOptions()`) niczego nie odsiewa. Filtry działają w każdej
/// kategorii naraz — kategorii jako filtra nie ma, bo Przepisy i tak stoją
/// sekcjami po kategoriach, a stopka arkusza pokazuje, ile zostaje w każdej.
struct RecipeFilterOptions: Equatable {
    /// Górny limit czasu przygotowania w minutach. `nil` = dowolny.
    var maxPrepTimeMinutes: Int?

    /// Górny limit kalorii na porcję. `nil` = bez limitu.
    var maxCaloriesPerServing: Int?

    /// Poziom trudności. `nil` = dowolny.
    var difficulty: Difficulty?

    var diets: Set<RecipeDietFilter> = []
    var traits: Set<RecipeTraitFilter> = []
    var excludedIngredients: Set<IngredientExclusion> = []

    /// Filtry „tylko w tej kategorii” — z arkusza otwieranego w liście
    /// kategorii. Mieszkają TU, a nie obok, żeby jedna reguła (`matches`)
    /// liczyła i listę, i stopkę Filtrów: „Pokaż 132” zawsze znaczy 132 na
    /// liście, także gdy śniadania są zawężone do słodkich.
    var categoryFilters: [RecipesCategory: RecipeCategoryFilter] = [:]

    // MARK: - Dostępne opcje

    /// Progi segmentu „Czas przygotowania” (obok „Dowolny”).
    static let prepTimeChoices: [Int] = [15, 30, 45]

    /// Linijka kalorii: od 0 do `calorieScaleMax` co `calorieStep`. Igła na
    /// samym końcu skali znaczy „bez limitu” (napis „1000+”).
    static let calorieScaleMax = 1000
    static let calorieStep = 50
    /// Najniższy limit, na jaki da się postawić igłę — „do 0 kcal” nie jest
    /// filtrem, tylko pustą listą.
    static let calorieMinimum = 100

    // MARK: - Stan

    /// Liczba aktywnych grup filtrów — plakietka przy przycisku filtra
    /// w nagłówku Przepisów. Jedna sekcja arkusza = jedna grupa, niezależnie
    /// od tego, ile kafelków w niej zaznaczono.
    var activeCount: Int {
        var count = 0
        if maxPrepTimeMinutes != nil       { count += 1 }
        if maxCaloriesPerServing != nil    { count += 1 }
        if difficulty != nil               { count += 1 }
        if !diets.isEmpty                  { count += 1 }
        if !traits.isEmpty                 { count += 1 }
        if !excludedIngredients.isEmpty    { count += 1 }
        return count
    }

    /// Czy cokolwiek zawęża listę — filtry wszystkich przepisów albo którejś
    /// kategorii. `activeCount` (plakietka w nagłówku Przepisów) liczy tylko
    /// te pierwsze; filtry kategorii mają plakietkę na swoim przycisku.
    var isActive: Bool { activeCount > 0 || hasCategoryFilters }

    var hasCategoryFilters: Bool { categoryFilters.values.contains { $0.isActive } }

    /// Co zawęża listę, krótko — „do 30 min”, „do 600 kcal”, „Wege” — do
    /// karty nad listą kategorii (`RecipeListContextCard`). Kolejność jak
    /// sekcje arkusza „Filtry”; filtrów kategorii tu nie ma — te widać na
    /// pigułkach w samej liście.
    var summaryLabels: [String] {
        var labels: [String] = []
        if let maxPrepTimeMinutes { labels.append("do \(maxPrepTimeMinutes) min") }
        if let maxCaloriesPerServing { labels.append("do \(maxCaloriesPerServing) kcal") }
        if let difficulty {
            switch difficulty {
            case .easy:   labels.append("łatwe")
            case .medium: labels.append("średnie")
            case .hard:   labels.append("trudne")
            }
        }
        // Małą literą, jak reszta zdania („do 30 min · wege · bez glutenu”);
        // Thermomix to nazwa własna.
        labels += RecipeDietFilter.allCases.filter { diets.contains($0) }.map { $0.title.lowercased() }
        labels += RecipeTraitFilter.allCases.filter { traits.contains($0) }.map {
            $0 == .thermomix ? $0.title : $0.title.lowercased()
        }
        if !excludedIngredients.isEmpty {
            let count = excludedIngredients.count
            labels.append(count == 1 ? "bez 1 składnika" : "bez \(count) składników")
        }
        return labels
    }

    /// Te same filtry bez zawężenia jednej kategorii — pula, na której arkusz
    /// tej kategorii liczy swoje kafelki.
    func withoutCategoryFilter(for category: RecipesCategory) -> RecipeFilterOptions {
        var next = self
        next.categoryFilters[category] = nil
        return next
    }

    // MARK: - Filtrowanie

    @MainActor
    func matches(_ recipe: Recipe) -> Bool {
        matches(RecipeFilterFactsCache.facts(for: recipe))
    }

    /// Jedyne miejsce z regułami filtra — liczy po nim i lista Przepisów,
    /// i liczniki w arkuszu, więc „Pokaż 132” zawsze znaczy 132 na liście.
    func matches(_ facts: RecipeFilterFacts) -> Bool {
        if let maxPrepTimeMinutes, facts.prepTimeMinutes > maxPrepTimeMinutes { return false }

        // Backend nie zawsze dowozi makra — przepis bez policzonych kcal (0)
        // zostaje na liście, zamiast zniknąć przez brak danych.
        if let maxCaloriesPerServing, facts.kcalPerServing > 0,
           facts.kcalPerServing > maxCaloriesPerServing { return false }

        if let difficulty, facts.difficulty != difficulty { return false }
        if !diets.isSubset(of: facts.diets) { return false }
        if !traits.isSubset(of: facts.traits) { return false }
        if !excludedIngredients.isDisjoint(with: facts.exclusionKeys) { return false }
        if let categoryFilter = categoryFilters[facts.category], categoryFilter.isActive,
           !categoryFilter.matches(facts.facetValues) { return false }
        return true
    }

    @MainActor
    func apply(to recipes: [Recipe]) -> [Recipe] {
        guard isActive else { return recipes }
        return recipes.filter { matches($0) }
    }

    mutating func reset() {
        self = RecipeFilterOptions()
    }

    /// „Wyczyść” w arkuszu Filtrów czyści tylko swoje piętro — filtry
    /// kategorii zostają, czyści je „Wyczyść” w arkuszu danej kategorii.
    mutating func resetGlobal() {
        let kept = categoryFilters
        self = RecipeFilterOptions()
        categoryFilters = kept
    }

    // MARK: - Mutacje

    mutating func toggle(diet: RecipeDietFilter) {
        if diets.contains(diet) { diets.remove(diet) } else { diets.insert(diet) }
    }

    mutating func toggle(trait: RecipeTraitFilter) {
        if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
    }

    /// Wyklucza albo przywraca. Przywrócenie jednego rodzaju z wykluczonej
    /// grupy rozbija grupę na pozostałe rodzaje — „wszystkie papryki poza
    /// czerwoną” — zamiast przywracać całą grupę naraz.
    mutating func toggle(exclusion: IngredientExclusion, groupMembers: [IngredientExclusion] = [], parentGroup: IngredientExclusion? = nil) {
        if excludedIngredients.contains(exclusion) {
            excludedIngredients.remove(exclusion)
            return
        }
        if let parentGroup, excludedIngredients.contains(parentGroup) {
            excludedIngredients.remove(parentGroup)
            for member in groupMembers where member != exclusion {
                excludedIngredients.insert(member)
            }
            return
        }
        excludedIngredients.insert(exclusion)
        // Grupa obejmuje już swoje rodzaje — pojedyncze wpisy pod nią tylko
        // mnożyłyby chipy mówiące to samo.
        if exclusion.isGroup {
            for member in groupMembers { excludedIngredients.remove(member) }
        }
    }
}

// MARK: - Fakty o przepisie

/// Wszystko, o co pyta filtr, policzone raz na przepis. Arkusz przelicza
/// kilkanaście liczników przy każdym stuknięciu (i przy każdym kroku igły
/// kalorii), a lista Przepisów filtruje w kilku miejscach jednego `body` —
/// bez tego każde z nich od nowa składałoby profil diety i klucze składników.
struct RecipeFilterFacts {
    let category: RecipesCategory
    let prepTimeMinutes: Int
    /// Zaokrąglone kcal na porcję; 0 = brak policzonych makr.
    let kcalPerServing: Int
    let difficulty: Difficulty
    let diets: Set<RecipeDietFilter>
    let traits: Set<RecipeTraitFilter>
    let exclusionKeys: Set<IngredientExclusion>
    /// Wartości w aspektach kategorii (smak, rodzaj dania, mięso, pora).
    let facetValues: [RecipeFacetKind: Set<String>]

    @MainActor
    init(_ recipe: Recipe) {
        category = recipe.category
        prepTimeMinutes = recipe.prepTimeMinutes
        kcalPerServing = Int(recipe.nutritionPerServing.kcal.rounded())
        difficulty = recipe.difficulty
        diets = Set(RecipeDietFilter.allCases.filter { $0.matches(recipe) })
        traits = Set(RecipeTraitFilter.allCases.filter { $0.matches(recipe) })
        exclusionKeys = Set(recipe.ingredients.flatMap {
            IngredientExclusion.keys(forIngredientNamed: $0.name, department: $0.department)
        })
        facetValues = RecipeCategoryFacets.values(for: recipe)
    }
}

enum RecipeFilterFactsCache {
    private static var storage: [UUID: (fingerprint: Int, facts: RecipeFilterFacts)] = [:]
    /// Wartości aspektów przepisu liczone w INNEJ kategorii niż jego własna
    /// (wybór do planu) — osobno, żeby nie mieszać ich z faktami przepisu.
    private static var foreignFacets: [ForeignKey: (fingerprint: Int, values: [RecipeFacetKind: Set<String>])] = [:]

    private struct ForeignKey: Hashable {
        let recipeId: UUID
        let category: RecipesCategory
    }

    @MainActor
    static func facts(for recipe: Recipe) -> RecipeFilterFacts {
        let stamp = fingerprint(of: recipe)
        if let cached = storage[recipe.id], cached.fingerprint == stamp {
            return cached.facts
        }
        let facts = RecipeFilterFacts(recipe)
        storage[recipe.id] = (stamp, facts)
        return facts
    }

    /// Wartości aspektów przepisu w aspektach podanej kategorii — patrz
    /// `RecipeCategoryFacets.values(for:in:)`. Przepis z tej samej kategorii
    /// bierze je z faktów.
    @MainActor
    static func facetValues(for recipe: Recipe, in category: RecipesCategory) -> [RecipeFacetKind: Set<String>] {
        guard recipe.category != category else { return facts(for: recipe).facetValues }
        let key = ForeignKey(recipeId: recipe.id, category: category)
        let stamp = fingerprint(of: recipe)
        if let cached = foreignFacets[key], cached.fingerprint == stamp {
            return cached.values
        }
        let values = RecipeCategoryFacets.values(for: recipe, in: category)
        foreignFacets[key] = (stamp, values)
        return values
    }

    @MainActor
    private static func fingerprint(of recipe: Recipe) -> Int {
        // Ulubione zmieniają się w trakcie sesji, a lista potrafi przyjść
        // uboższa niż szczegóły — każde z pól, z których liczą się fakty,
        // musi unieważniać wpis.
        var hasher = Hasher()
        // Nazwa i sloty wchodzą, bo z nich liczą się aspekty kategorii.
        hasher.combine(recipe.name)
        hasher.combine(recipe.baseSlot)
        hasher.combine(recipe.suitableSlots)
        hasher.combine(recipe.favourite)
        hasher.combine(recipe.prepTimeMinutes)
        hasher.combine(recipe.difficulty)
        hasher.combine(recipe.servings)
        hasher.combine(recipe.nutrition)
        hasher.combine(recipe.sourceProvider)
        hasher.combine(recipe.sourceRecipeId)
        hasher.combine(recipe.dietTags)
        hasher.combine(recipe.allergens)
        hasher.combine(recipe.ingredients.count)
        for ingredient in recipe.ingredients {
            hasher.combine(ingredient.name)
            hasher.combine(ingredient.department)
        }
        return hasher.finalize()
    }
}
