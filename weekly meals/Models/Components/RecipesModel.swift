import Foundation

enum RecipesCategory: String, CaseIterable, Identifiable, Codable {
    case all = "Wszystkie"
    case favourite = "Ulubione"
    case breakfast = "Śniadania"
    case lunch = "Obiady"
    case dinner = "Kolacje"

    var id: String { rawValue }

    /// Mapuje kategorię przepisu na slot posiłku.
    /// Zwraca nil dla kategorii filtrujących (.all, .favourite).
    var toMealSlot: MealSlot? {
        switch self {
        case .breakfast: .breakfast
        case .lunch:     .lunch
        case .dinner:    .dinner
        case .all, .favourite: nil
        }
    }
}

/// Poziom trudności przepisu
enum Difficulty: String, CaseIterable, Identifiable, Codable {
    case easy = "Łatwy"
    case medium = "Średni"
    case hard = "Trudny"

    var id: String { rawValue }
}

/// Jednostki dla składników (ilość produktu w przepisie)
enum IngredientUnit: String, CaseIterable, Codable, Identifiable {
    case gram = "g"
    case kilogram = "kg"
    case milliliter = "ml"
    case liter = "l"
    case piece = "szt"
    case teaspoon = "łyżeczka"
    case tablespoon = "łyżka"
    case cup = "szklanka"

    var id: String { rawValue }
}

/// Pojedynczy składnik przepisu (produkt + ilość)
struct Ingredient: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var amount: Double
    var unit: IngredientUnit

    init(id: UUID = UUID(), name: String, amount: Double, unit: IngredientUnit) {
        self.id = id
        self.name = name
        self.amount = amount
        self.unit = unit
    }
}

/// Pojedynczy krok przygotowania posiłku
struct PreparationStep: Identifiable, Codable, Hashable {
    let id: UUID
    var stepNumber: Int
    var instruction: String

    init(id: UUID = UUID(), stepNumber: Int, instruction: String) {
        self.id = id
        self.stepNumber = stepNumber
        self.instruction = instruction
    }
}

/// Wartości odżywcze (domyślnie dla całego przepisu lub porcji – patrz `servings`)
struct Nutrition: Codable, Hashable {
    /// Energia w kilokaloriach
    var kcal: Double
    /// Białko w gramach
    var protein: Double
    /// Tłuszcz w gramach
    var fat: Double
    /// Węglowodany w gramach
    var carbs: Double
    /// Błonnik w gramach
    var fiber: Double
    /// Sól w gramach
    var salt: Double

    static let zero = Nutrition(kcal: 0, protein: 0, fat: 0, carbs: 0, fiber: 0, salt: 0)
}

struct Recipe: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var favourite: Bool
    let category: RecipesCategory

    /// Liczba porcji. Jeśli > 0, to `nutritionPerServing` wylicza wartości na 1 porcję.
    var servings: Int

    /// Czas przygotowania w minutach.
    var prepTimeMinutes: Int

    /// Poziom trudności przepisu.
    var difficulty: Difficulty

    /// Ścieżka/URL do zdjęcia (lokalny lub zdalny).
    var imageURL: URL?

    /// Lista składników wchodzących w skład przepisu.
    var ingredients: [Ingredient]

    /// Kroki przygotowania posiłku.
    var preparationSteps: [PreparationStep]

    /// Wartości odżywcze dla całego przepisu (chyba że aplikacja przyjmie, że to wartości na porcję – wtedy zmień opis zgodnie z potrzebą).
    var nutrition: Nutrition

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        favourite: Bool = false,
        category: RecipesCategory,
        servings: Int = 1,
        prepTimeMinutes: Int = 0,
        difficulty: Difficulty = .easy,
        imageURL: URL? = nil,
        ingredients: [Ingredient] = [],
        preparationSteps: [PreparationStep] = [],
        nutrition: Nutrition = .zero
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.favourite = favourite
        self.category = category
        self.servings = max(servings, 1)
        self.prepTimeMinutes = max(prepTimeMinutes, 0)
        self.difficulty = difficulty
        self.imageURL = imageURL
        self.ingredients = ingredients
        self.preparationSteps = preparationSteps
        self.nutrition = nutrition
    }
}

extension Recipe {
    /// Czy przepis ma w ogóle policzone makra. Backend nie zawsze je dowozi,
    /// a `Nutrition.zero` jest nieodróżnialne od realnego zera — dlatego
    /// filtry po profilu odżywczym pytają o to przed porównaniem progów.
    var hasNutritionData: Bool {
        nutrition.kcal > 0 ||
        nutrition.protein > 0 ||
        nutrition.fat > 0 ||
        nutrition.carbs > 0
    }

    /// Wartości odżywcze w przeliczeniu na 1 porcję.
    var nutritionPerServing: Nutrition {
        guard servings > 0 else { return nutrition }
        let factor = 1.0 / Double(servings)
        return Nutrition(
            kcal: nutrition.kcal * factor,
            protein: nutrition.protein * factor,
            fat: nutrition.fat * factor,
            carbs: nutrition.carbs * factor,
            fiber: nutrition.fiber * factor,
            salt: nutrition.salt * factor
        )
    }
}

