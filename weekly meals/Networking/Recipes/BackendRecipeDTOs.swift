import Foundation

// MARK: - Recipe DTOs (aligned with backend Recipe model)

struct BackendRecipeIngredientDTO: Codable {
    let id: String
    let recipeId: String
    let name: String
    let amount: Double
    let unit: String
    /// Dział katalogu. Opcjonalny — starsze wersje backendu nie dowoziły go
    /// na liście przepisów, a wtedy dekodowanie całej listy padało na
    /// brakującym kluczu zamiast po prostu zgubić jedną podpowiedź.
    let department: String?
}

struct BackendRecipeDTO: Codable {
    let id: String
    let title: String
    let description: String?
    let mealType: String
    /// Sloty, w których danie ma sens. Opcjonalny — starszy backend go nie
    /// dowozi, a wtedy odczytujemy je z samego `mealType`.
    let suitableMealTypes: [String]?
    let difficulty: String
    let prepTimeMinutes: Int
    let servings: Int
    let imageUrl: String?
    let nutritionKcal: Double
    let nutritionProtein: Double
    let nutritionFat: Double
    let nutritionCarbs: Double
    let nutritionFiber: Double
    let nutritionSalt: Double
    let isActive: Bool
    let isFavorite: Bool?
    let ingredients: [BackendRecipeIngredientDTO]
    let sourceInstructions: [BackendRecipeInstructionDTO]?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case mealType
        case suitableMealTypes
        case difficulty
        case prepTimeMinutes
        case servings
        case imageUrl
        case nutritionKcal
        case nutritionProtein
        case nutritionFat
        case nutritionCarbs
        case nutritionFiber
        case nutritionSalt
        case isActive
        case isFavorite
        case ingredients
        case sourceInstructions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        mealType = try container.decode(String.self, forKey: .mealType)
        suitableMealTypes = try container.decodeIfPresent([String].self, forKey: .suitableMealTypes)
        difficulty = try container.decode(String.self, forKey: .difficulty)
        prepTimeMinutes = try container.decode(Int.self, forKey: .prepTimeMinutes)
        servings = try container.decode(Int.self, forKey: .servings)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        nutritionKcal = try container.decode(Double.self, forKey: .nutritionKcal)
        nutritionProtein = try container.decode(Double.self, forKey: .nutritionProtein)
        nutritionFat = try container.decode(Double.self, forKey: .nutritionFat)
        nutritionCarbs = try container.decode(Double.self, forKey: .nutritionCarbs)
        nutritionFiber = try container.decode(Double.self, forKey: .nutritionFiber)
        nutritionSalt = try container.decode(Double.self, forKey: .nutritionSalt)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite)
        ingredients = try container.decodeIfPresent([BackendRecipeIngredientDTO].self, forKey: .ingredients) ?? []
        sourceInstructions = try container.decodeIfPresent([BackendRecipeInstructionDTO].self, forKey: .sourceInstructions)
    }
}

struct BackendRecipeInstructionDTO: Codable {
    let stepNumber: Int?
    let step_number: Int?
    let text: String?
    let instruction: String?
}

// MARK: - DTO -> domain mapping

extension BackendRecipeDTO {
    private static let apiBaseURL = AppEnvironment.apiBaseURL

    private func displayIngredientName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        return String(first).uppercased(with: Locale(identifier: "pl_PL")) + trimmed.dropFirst()
    }

    private func resolvedImageURL() -> URL? {
        guard let raw = imageUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        if let absolute = URL(string: raw), absolute.scheme != nil {
            return absolute
        }

        if raw.hasPrefix("/") {
            return URL(string: raw, relativeTo: Self.apiBaseURL)?.absoluteURL
        }

        return URL(string: "/" + raw, relativeTo: Self.apiBaseURL)?.absoluteURL
    }

    var appCategory: RecipesCategory? {
        switch mealType.uppercased() {
        case "BREAKFAST": .breakfast
        case "LUNCH": .lunch
        case "DINNER": .dinner
        default: nil
        }
    }

    /// Sloty planu, do których danie pasuje.
    ///
    /// Slot bazowy dokładamy zawsze — backend go już normalizuje, ale przepis
    /// zapisany przez starszego klienta może wrócić z pustą listą i wtedy
    /// zniknąłby z wyboru posiłku, zamiast po prostu nie mieć dodatkowych pór.
    var appSuitableSlots: [MealSlot] {
        var slots = (suitableMealTypes ?? []).compactMap { MealSlot(backendMealType: $0) }
        if let base = MealSlot(backendMealType: mealType) {
            slots.append(base)
        }
        return slots.sortedByDay
    }

    var appDifficulty: Difficulty {
        switch difficulty.uppercased() {
        case "EASY": .easy
        case "MEDIUM": .medium
        case "HARD": .hard
        default: .easy
        }
    }

    func toAppRecipe() -> Recipe? {
        guard let uuid = UUID(uuidString: id), let category = appCategory else {
            return nil
        }

        let mappedIngredients = ingredients.compactMap { item -> Ingredient? in
            let unit = IngredientUnit(rawValue: item.unit)
            guard let mappedUnit = unit else { return nil }
            return Ingredient(
                id: UUID(uuidString: item.id) ?? UUID(),
                name: displayIngredientName(item.name),
                amount: item.amount,
                unit: mappedUnit,
                department: item.department
            )
        }

        let mappedPreparationSteps: [PreparationStep] = (sourceInstructions ?? [])
            .enumerated()
            .compactMap { index, step in
                let content = (step.text ?? step.instruction ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { return nil }
                let stepNumber = step.step_number ?? step.stepNumber ?? (index + 1)
                return PreparationStep(stepNumber: stepNumber, instruction: content)
            }
            .sorted(by: { $0.stepNumber < $1.stepNumber })

        return Recipe(
            id: uuid,
            name: title,
            description: description ?? "",
            favourite: isFavorite ?? false,
            category: category,
            suitableSlots: appSuitableSlots,
            servings: servings,
            prepTimeMinutes: prepTimeMinutes,
            difficulty: appDifficulty,
            imageURL: resolvedImageURL(),
            ingredients: mappedIngredients,
            preparationSteps: mappedPreparationSteps,
            nutrition: Nutrition(
                kcal: nutritionKcal,
                protein: nutritionProtein,
                fat: nutritionFat,
                carbs: nutritionCarbs,
                fiber: nutritionFiber,
                salt: nutritionSalt
            )
        )
    }
}
