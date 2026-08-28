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
    /// Znormalizowana ilość/jednostka (g / ml / szt). Backend dowozi je tylko
    /// w szczególe przepisu, na liście brak → `nil`.
    let normalizedAmount: Double?
    let normalizedUnit: String?
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
    /// Zewnętrzne źródło przepisu (Cookidoo: `"cookidoo"` + `"r907015"`).
    /// Opcjonalne — starszy backend nie dowozi tych pól w projekcjach.
    let sourceProvider: String?
    let sourceRecipeId: String?
    /// Tagi policzone na serwerze (plaster D). Opcjonalne: starszy backend ich
    /// nie dowozi i wtedy klient wraca do heurystyki po nazwach składników.
    /// Pusta lista to fakt, nie brak danych — dlatego `nil` ≠ `[]`.
    let allergens: [String]?
    let dietTags: [String]?

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
        case sourceProvider
        case sourceRecipeId
        case allergens
        case dietTags
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
        sourceProvider = try container.decodeIfPresent(String.self, forKey: .sourceProvider)
        sourceRecipeId = try container.decodeIfPresent(String.self, forKey: .sourceRecipeId)
        // Obcy kształt pola nie może położyć całego przepisu — wtedy po prostu
        // zostaje heurystyka.
        allergens = try? container.decodeIfPresent([String].self, forKey: .allergens)
        dietTags = try? container.decodeIfPresent([String].self, forKey: .dietTags)
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

    /// Kategoria bazowa przepisu — sekcja na Przepisach, okładka, akcent.
    ///
    /// Idzie przez `MealSlot`, a nie po własnej liście trzech napisów: backend
    /// zna sześć wartości `MealType` i te spoza trójki podstawowej gubiły tu
    /// kategorię, a wraz z nią cały przepis (patrz `toAppRecipe`). Regułę
    /// „sloty pomiędzy posiłkami idą do sekcji Przekąski i desery" trzyma
    /// `MealSlot.baseCategory`, więc dopisanie kolejnego slotu jest błędem
    /// kompilacji tam, a nie cichym zniknięciem dania tutaj.
    ///
    /// `nil` zostaje wyłącznie dla wartości, której klient w ogóle nie zna —
    /// tam nie ma czego zgadywać.
    var appCategory: RecipesCategory? {
        MealSlot(backendMealType: mealType)?.baseCategory
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

        // Nieznana jednostka NIE wyrzuca składnika — dawny `compactMap` gubił
        // każdą szczyptę (118 składników w 69 przepisach), więc telefon
        // pokazywał przepisy bez soli i pieprzu, a backend liczył je do listy.
        let mappedIngredients = ingredients.map { item -> Ingredient in
            let unit = IngredientUnit(rawValue: item.unit) ?? .other
            return Ingredient(
                id: UUID(uuidString: item.id) ?? UUID(),
                name: displayIngredientName(item.name),
                amount: item.amount,
                unit: unit,
                department: item.department,
                rawUnit: unit == .other ? item.unit : nil,
                normalizedAmount: item.normalizedAmount,
                normalizedUnit: item.normalizedUnit
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
            baseSlot: MealSlot(backendMealType: mealType),
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
            ),
            sourceProvider: sourceProvider,
            sourceRecipeId: sourceRecipeId,
            allergens: allergens,
            dietTags: dietTags
        )
    }
}
