import Foundation

/// Profil odżywczy przepisu — chipy „Wysokobiałkowe”, „Niskowęglowodanowe” itd.
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

    /// Opis progu pokazywany pod chipami, gdy tag jest zaznaczony — żeby
    /// „wysokobiałkowe” nie było magiczną obietnicą bez liczby.
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

/// Zestaw filtrów wybieranych w arkuszu „Filtry” na widoku Przepisów.
///
/// Świadomie trzyma tylko najpopularniejsze kryteria — kategorię posiłku,
/// trudność, czas przygotowania, kalorie na porcję i ulubione. Puste
/// kolekcje / `nil` znaczą „bez ograniczeń”, więc domyślna instancja
/// (`RecipeFilterOptions()`) niczego nie odsiewa.
struct RecipeFilterOptions: Equatable {
    /// Kategorie posiłku. Pusty zbiór = wszystkie.
    var categories: Set<RecipesCategory> = []

    /// Poziomy trudności. Pusty zbiór = wszystkie.
    var difficulties: Set<Difficulty> = []

    /// Górny limit czasu przygotowania w minutach. `nil` = bez limitu.
    var maxPrepTimeMinutes: Int?

    /// Górny limit kalorii na porcję. `nil` = bez limitu.
    var maxCaloriesPerServing: Int?

    /// Profil odżywczy (wysokobiałkowe, niskowęglowodanowe, …). Zaznaczone
    /// tagi łączą się przez AND — przepis musi spełnić każdy z nich.
    var nutritionTags: Set<RecipeNutritionTag> = []

    /// Pokazuj wyłącznie przepisy oznaczone jako ulubione.
    var favouritesOnly: Bool = false

    /// Pokazuj wyłącznie przepisy z odpowiednikiem w Cookidoo (Thermomix).
    var thermomixOnly: Bool = false

    // MARK: - Dostępne opcje

    /// Kategorie realnie przypisywane przepisom (`.all` / `.favourite` to
    /// pseudo-kategorie filtrujące, więc nie trafiają do chipów). Ta sama
    /// lista co sekcje na Przepisach — chip ma odpowiadać sekcji, którą
    /// użytkownik przed chwilą oglądał.
    static let selectableCategories: [RecipesCategory] = RecipesCategory.catalogSections

    /// Progi czasu przygotowania pokazywane jako chipy „do X min”.
    static let prepTimeChoices: [Int] = [15, 30, 60]

    /// Progi kaloryczne pokazywane jako chipy „do X kcal”.
    static let calorieChoices: [Int] = [300, 500, 800]

    // MARK: - Stan

    /// Liczba aktywnych grup filtrów — trafia na plakietkę przy przycisku
    /// filtra w nagłówku (jedna grupa = jedna „kropka”, niezależnie od tego
    /// ile chipów w niej zaznaczono).
    var activeCount: Int {
        var count = 0
        if !categories.isEmpty            { count += 1 }
        if !difficulties.isEmpty          { count += 1 }
        if maxPrepTimeMinutes != nil      { count += 1 }
        if maxCaloriesPerServing != nil   { count += 1 }
        if !nutritionTags.isEmpty         { count += 1 }
        if favouritesOnly                 { count += 1 }
        if thermomixOnly                  { count += 1 }
        return count
    }

    var isActive: Bool { activeCount > 0 }

    // MARK: - Filtrowanie

    func matches(_ recipe: Recipe) -> Bool {
        if favouritesOnly, !recipe.favourite { return false }

        if thermomixOnly, !recipe.isThermomix { return false }

        if !categories.isEmpty, !categories.contains(recipe.category) { return false }

        if !difficulties.isEmpty, !difficulties.contains(recipe.difficulty) { return false }

        if let maxPrepTimeMinutes, recipe.prepTimeMinutes > maxPrepTimeMinutes { return false }

        if let maxCaloriesPerServing {
            // Backend nie zawsze dowozi makra — przepis bez policzonych kcal
            // (0) zostaje na liście, zamiast zniknąć przez brak danych.
            let kcal = recipe.nutritionPerServing.kcal
            if kcal > 0, Int(kcal.rounded()) > maxCaloriesPerServing { return false }
        }

        for tag in nutritionTags where !tag.matches(recipe) { return false }

        return true
    }

    func apply(to recipes: [Recipe]) -> [Recipe] {
        guard isActive else { return recipes }
        return recipes.filter(matches(_:))
    }

    mutating func reset() {
        self = RecipeFilterOptions()
    }

    // MARK: - Mutacje pojedynczych chipów

    mutating func toggle(category: RecipesCategory) {
        if categories.contains(category) {
            categories.remove(category)
        } else {
            categories.insert(category)
        }
    }

    mutating func toggle(difficulty: Difficulty) {
        if difficulties.contains(difficulty) {
            difficulties.remove(difficulty)
        } else {
            difficulties.insert(difficulty)
        }
    }

    mutating func toggle(nutritionTag tag: RecipeNutritionTag) {
        if nutritionTags.contains(tag) {
            nutritionTags.remove(tag)
        } else {
            nutritionTags.insert(tag)
        }
    }

    /// Zaznaczone tagi w kolejności deklaracji enuma — `Set` nie ma własnej,
    /// a podpis pod chipami nie może skakać przy każdym renderze.
    var orderedNutritionTags: [RecipeNutritionTag] {
        RecipeNutritionTag.allCases.filter { nutritionTags.contains($0) }
    }

    /// Chipy progowe działają jak radio z odznaczaniem — ponowny tap na
    /// aktywny próg zdejmuje limit.
    mutating func toggle(maxPrepTime minutes: Int) {
        maxPrepTimeMinutes = (maxPrepTimeMinutes == minutes) ? nil : minutes
    }

    mutating func toggle(maxCalories kcal: Int) {
        maxCaloriesPerServing = (maxCaloriesPerServing == kcal) ? nil : kcal
    }
}
