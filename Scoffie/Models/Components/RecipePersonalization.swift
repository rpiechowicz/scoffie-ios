import SwiftUI

/// Preferencje z Ustawień → „Dieta i alergeny” w postaci, w której da się je
/// nałożyć na katalog przepisów.
///
/// Podział ról jest celowy i widoczny w UI:
/// - **dieta i alergeny odsiewają** — przepis niezgodny znika z listy, bo
///   pokazywanie wegetarianinowi schabowego jest po prostu błędem;
/// - **cel tylko porządkuje** — „Schudnąć” przesuwa lżejsze i bardziej
///   białkowe przepisy na górę, ale nic nie ukrywa. Cel jest miękką
///   preferencją, a nie zakazem, i twarde cięcie po kaloriach wywalałoby
///   z listy sensowne dania za 30 kcal ponad próg.
///
/// Całość da się wyłączyć jednym przełącznikiem na widoku Przepisów — bez
/// tego użytkownik nie miałby jak zobaczyć, czego nie widzi.
struct RecipePersonalization: Equatable {
    var diet: DietPreference = .none
    var avoidedAllergens: Set<Allergen> = []
    var goal: UserGoal = .healthy
    var dailyCalorieGoal: Int = 2000

    /// Przełącznik z banera na Przepisach. `false` = pokazuj cały katalog.
    var isEnabled: Bool = true

    // MARK: - Odczyt z UserDefaults

    /// Klucze `@AppStorage` współdzielone z Ustawieniami i ekranem powitalnym.
    enum Keys {
        static let diet = "settings.diet.preference"
        static let allergens = "settings.diet.allergens"
        static let goal = "settings.diet.goal"
        static let calorieGoal = "settings.diet.calorieGoal"
        static let enabled = "recipes.personalization.enabled"
    }

    static let defaultCalorieGoal = 2000

    init(
        diet: DietPreference = .none,
        avoidedAllergens: Set<Allergen> = [],
        goal: UserGoal = .healthy,
        dailyCalorieGoal: Int = RecipePersonalization.defaultCalorieGoal,
        isEnabled: Bool = true
    ) {
        self.diet = diet
        self.avoidedAllergens = avoidedAllergens
        self.goal = goal
        self.dailyCalorieGoal = dailyCalorieGoal
        self.isEnabled = isEnabled
    }

    /// Buduje zestaw z surowych wartości `@AppStorage`. Nieznane / puste
    /// wartości schodzą do domyślnych, więc świeża instalacja niczego nie tnie.
    init(dietRaw: String, allergensRaw: String, goalRaw: String, calorieGoal: Int, isEnabled: Bool) {
        self.init(
            diet: DietPreference(rawValue: dietRaw) ?? .none,
            avoidedAllergens: Self.allergens(from: allergensRaw),
            goal: UserGoal(rawValue: goalRaw) ?? .healthy,
            dailyCalorieGoal: calorieGoal > 0 ? calorieGoal : Self.defaultCalorieGoal,
            isEnabled: isEnabled
        )
    }

    /// „eggs,gluten,nuts” → zbiór alergenów. Nieznane wpisy są pomijane, żeby
    /// starszy zapis z innej wersji aplikacji nie wysypywał odczytu.
    static func allergens(from raw: String) -> Set<Allergen> {
        Set(raw
            .split(separator: ",")
            .compactMap { Allergen(rawValue: String($0).trimmingCharacters(in: .whitespaces)) })
    }

    // MARK: - Stan

    /// Czy ustawienia w ogóle coś usuwają z listy.
    var restrictsCatalog: Bool {
        diet != .none || !avoidedAllergens.isEmpty
    }

    /// Czy cel ma jak wpłynąć na kolejność. „Lepiej planować posiłki” nie
    /// niesie żadnej informacji o kaloriach, więc nie miesza w sortowaniu.
    var ranksCatalog: Bool {
        goal != .plan
    }

    /// Czy personalizacja realnie coś robi z katalogiem.
    var isActive: Bool {
        isEnabled && (restrictsCatalog || ranksCatalog)
    }

    /// Czy jest co pokazać w banerze — nawet po wyłączeniu, żeby dało się
    /// wrócić.
    var hasAnyPreference: Bool {
        restrictsCatalog || ranksCatalog
    }

    // MARK: - Odsiew

    /// Czy przepis wypada z listy przez dietę lub alergen.
    @MainActor
    func excludes(_ recipe: Recipe) -> Bool {
        guard isEnabled, restrictsCatalog else { return false }
        let profile = recipe.dietProfile
        if !profile.satisfies(diet, recipe: recipe) { return true }
        if !profile.avoids(avoidedAllergens) { return true }
        return false
    }

    /// Przepisy po odsiewie i uszeregowane pod cel.
    @MainActor
    func apply(to recipes: [Recipe]) -> [Recipe] {
        guard isEnabled else { return recipes }

        let kept = restrictsCatalog ? recipes.filter { !excludes($0) } : recipes
        guard ranksCatalog else { return kept }

        // Wynik dopasowania zaokrąglony do dwóch miejsc, żeby drobne różnice
        // makr nie przestawiały listy przy każdym doładowaniu strony — przy
        // remisie decyduje ulubione, potem nazwa, czyli kolejność stabilna.
        return kept
            .map { (recipe: $0, score: (goalScore(for: $0) * 100).rounded() / 100) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.recipe.favourite != rhs.recipe.favourite {
                    return lhs.recipe.favourite && !rhs.recipe.favourite
                }
                return lhs.recipe.name.localizedCaseInsensitiveCompare(rhs.recipe.name) == .orderedAscending
            }
            .map(\.recipe)
    }

    /// Ile przepisów zniknęło z podanej puli przez dietę / alergeny.
    @MainActor
    func hiddenCount(in recipes: [Recipe]) -> Int {
        guard isEnabled, restrictsCatalog else { return 0 }
        return recipes.reduce(into: 0) { total, recipe in
            if excludes(recipe) { total += 1 }
        }
    }

    // MARK: - Dopasowanie do celu

    /// Orientacyjna wielkość porcji w danej kategorii, liczona jako udział
    /// dziennej puli kalorii. Śniadanie 25 %, obiad 40 %, kolacja 30 % — ten
    /// sam podział, którym operuje podpowiedź na Kalendarzu.
    ///
    /// To punkty odniesienia dla pojedynczego dania, a nie podział doby: dzień
    /// z podwieczorkiem po prostu przycina posiłki główne, więc udziały nie
    /// muszą sumować się do 100 %. Przekąska dostaje 15 %, bo tyle waży realny
    /// podwieczorek z katalogu (250–450 kcal na porcję) — przy 5 % „reszty po
    /// trzech posiłkach" każdy deser wyglądałby na wielokrotne przekroczenie
    /// celu i cel spychałby całą sekcję na koniec listy.
    func calorieShare(for category: RecipesCategory) -> Double {
        switch category {
        case .breakfast: return 0.25
        case .lunch:     return 0.40
        case .dinner:    return 0.30
        case .snacks:    return 0.15
        case .all, .favourite: return 0.33
        }
    }

    /// Docelowa kaloryczność jednej porcji w danej kategorii.
    func targetKcal(for category: RecipesCategory) -> Double {
        Double(dailyCalorieGoal) * calorieShare(for: category)
    }

    /// Dopasowanie przepisu do celu w skali 0…1. Wyżej = wcześniej na liście.
    ///
    /// Przepisy bez policzonych makr dostają 0.5 — środek stawki. Nie ma za co
    /// ich nagradzać, ale i nie ma dowodu, że są złe, więc nie lecą na koniec.
    @MainActor
    func goalScore(for recipe: Recipe) -> Double {
        guard ranksCatalog else { return 0.5 }
        guard recipe.hasNutritionData else { return 0.5 }

        let nutrition = recipe.nutritionPerServing
        let target = targetKcal(for: recipe.category)
        guard target > 0 else { return 0.5 }

        let ratio = nutrition.kcal / target
        // Białko liczone jako udział energii — 30 % kcal z białka to bardzo
        // dużo, więc to naturalna górna granica skali.
        let proteinShare = min(nutrition.protein * 4 / max(nutrition.kcal, 1), 0.30) / 0.30
        let fiberScore = min(nutrition.fiber / 8, 1)
        let saltScore = 1 - min(nutrition.salt / 3, 1)

        switch goal {
        case .lose:
            // Nagradzamy porcje mieszczące się w celu i sycące — białko trzyma
            // sytość, więc niskokaloryczny przepis bez białka nie wygrywa.
            let calorieScore = ratio <= 1 ? 1 : max(0, 1 - (ratio - 1) * 1.5)
            return calorieScore * 0.55 + proteinShare * 0.30 + fiberScore * 0.15

        case .gain:
            // Odwrotnie: karzemy porcje zauważalnie poniżej celu.
            let calorieScore = ratio >= 1 ? 1 : max(0, 1 - (1 - ratio) * 1.5)
            return calorieScore * 0.55 + proteinShare * 0.45

        case .maintain:
            // Im bliżej celu, tym lepiej — w obie strony tak samo.
            let calorieScore = max(0, 1 - abs(ratio - 1) * 1.5)
            return calorieScore * 0.70 + proteinShare * 0.30

        case .healthy:
            // Bez celu kalorycznego w centrum: błonnik, mniej soli, sensowna
            // porcja. Kalorie ważą najmniej z całej trójki.
            let calorieScore = max(0, 1 - abs(ratio - 1))
            return fiberScore * 0.40 + saltScore * 0.30 + proteinShare * 0.15 + calorieScore * 0.15

        case .plan:
            return 0.5
        }
    }

    // MARK: - Opis dla UI

    /// Krótkie etykiety do banera na Przepisach.
    var chips: [Chip] {
        var result: [Chip] = []

        if ranksCatalog {
            result.append(Chip(icon: goal.icon, title: goal.shortTitle, accent: goal.accent))
        }
        if diet != .none {
            result.append(Chip(icon: diet.icon, title: diet.title, accent: diet.accent))
        }
        if !avoidedAllergens.isEmpty {
            let ordered = Allergen.allCases.filter { avoidedAllergens.contains($0) }
            result.append(
                Chip(
                    icon: "exclamationmark.shield.fill",
                    title: "Bez: " + ordered.map(\.title).joined(separator: ", ").lowercased(),
                    accent: WMPalette.terracotta
                )
            )
        }

        return result
    }

    struct Chip: Identifiable, Equatable {
        let icon: String
        let title: String
        let accent: Color

        var id: String { icon + title }
    }
}
