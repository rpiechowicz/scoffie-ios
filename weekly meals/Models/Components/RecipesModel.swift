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

    /// Dział z katalogu backendu („Mięso”, „Nabiał”, „Ryby”, …). Opcjonalny,
    /// bo starsze wpisy w cache'u i mocki go nie mają — klasyfikator diety
    /// traktuje `nil` jak brak wskazówki i schodzi wtedy do samej nazwy.
    var department: String?

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        unit: IngredientUnit,
        department: String? = nil
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.unit = unit
        self.department = department
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

    /// Kategoria bazowa — steruje sekcją na Przepisach, okładką i akcentem.
    /// Zawsze jedna.
    let category: RecipesCategory

    /// Sloty, w których danie faktycznie da się zaplanować.
    ///
    /// To nie to samo co `category`. Owsianka „należy" do śniadań, ale nadaje
    /// się też na drugie śniadanie i na przekąskę — i to ta lista decyduje,
    /// co widać po stuknięciu „Dodaj" w konkretnym slocie planu. Dzięki temu
    /// jedno danie obsługuje kilka pór dnia, zamiast zmuszać do wprowadzania
    /// tego samego przepisu drugi raz „na podwieczorek".
    ///
    /// Pusta lista znaczy „tylko slot wynikający z `category`" — tak wyglądają
    /// przepisy z cache'u sprzed tej zmiany i mocki. Czytać przez
    /// `effectiveSlots`, nie wprost.
    var suitableSlots: [MealSlot]

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
        suitableSlots: [MealSlot] = [],
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
        self.suitableSlots = suitableSlots.sortedByDay
        self.servings = max(servings, 1)
        self.prepTimeMinutes = max(prepTimeMinutes, 0)
        self.difficulty = difficulty
        self.imageURL = imageURL
        self.ingredients = ingredients
        self.preparationSteps = preparationSteps
        self.nutrition = nutrition
    }
}

// MARK: - Recipe legacy decoding
//
// Przepisy zapisane w cache'u przed dodaniem dodatkowych posiłków nie mają
// klucza `suitableSlots`. Syntetyzowany dekoder wywaliłby na nim cały plan
// tygodnia, więc brak klucza czytamy jako pustą listę — czyli „pasuje tylko
// do swojej kategorii".
extension Recipe {
    private enum CodingKeys: String, CodingKey {
        case id, name, description, favourite, category, suitableSlots
        case servings, prepTimeMinutes, difficulty, imageURL
        case ingredients, preparationSteps, nutrition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        favourite = try container.decodeIfPresent(Bool.self, forKey: .favourite) ?? false
        category = try container.decode(RecipesCategory.self, forKey: .category)
        suitableSlots = (try container.decodeIfPresent([MealSlot].self, forKey: .suitableSlots) ?? [])
            .sortedByDay
        servings = try container.decodeIfPresent(Int.self, forKey: .servings) ?? 1
        prepTimeMinutes = try container.decodeIfPresent(Int.self, forKey: .prepTimeMinutes) ?? 0
        difficulty = try container.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? .easy
        imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
        ingredients = try container.decodeIfPresent([Ingredient].self, forKey: .ingredients) ?? []
        preparationSteps = try container
            .decodeIfPresent([PreparationStep].self, forKey: .preparationSteps) ?? []
        nutrition = try container.decodeIfPresent(Nutrition.self, forKey: .nutrition) ?? .zero
    }
}

extension Recipe {
    /// Sloty, w których to danie da się zaplanować — z rozwinięciem reguły
    /// „pusta lista = tylko kategoria bazowa".
    var effectiveSlots: [MealSlot] {
        if !suitableSlots.isEmpty { return suitableSlots }
        return category.toMealSlot.map { [$0] } ?? []
    }

    /// Czy danie pasuje do konkretnego slotu planu.
    func fits(_ slot: MealSlot) -> Bool {
        effectiveSlots.contains(slot)
    }

    /// Sloty poza kategorią bazową — do plakietki „Pasuje też na…"
    /// w szczegółach przepisu.
    var additionalSlots: [MealSlot] {
        guard let base = category.toMealSlot else { return effectiveSlots }
        return effectiveSlots.filter { $0 != base }
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

