import Foundation

/// Dzienny cel — kalorie i makra — policzony JEDNĄ regułą dla wszystkich
/// ekranów, które go pokazują.
///
/// Reguła mieszkała dotąd wyłącznie w `SettingsView` (`effectiveMacros`),
/// bo tylko tam dało się cel obejrzeć. Plan tygodnia
/// potrzebuje dokładnie tej samej liczby: pasek nad dolnym menu i arkusz
/// „Cel dnia” porównują z nią dzień. Druga kopia rozjechałaby się przy
/// pierwszej zmianie wzoru — a wzór już raz się zmieniał, gdy makra przestały
/// zależeć wyłącznie od celu, a zaczęły też od liczby treningów.
struct DailyNutritionTargets: Equatable {
    /// Cel kaloryczny. Zawsze znany — suwak w Ustawieniach ma wartość domyślną.
    let kcal: Int

    /// Makra, albo `nil`, dopóki w profilu brakuje sylwetki. Bez wzrostu, wagi
    /// i roku urodzenia nie ma z czego policzyć białka na kilogram, a zmyślona
    /// liczba w celu jest gorsza niż brak liczby: użytkownik zobaczyłby pasek
    /// postępu do wartości, której nikt mu nie wyznaczył.
    let macros: MacroTargets?

    /// Klucze `UserDefaults` pod ręcznym nadpisaniem makr. `−1` znaczy „nie
    /// nadpisane, licz za mnie" — `@AppStorage` nie umie `nil` dla `Int`.
    enum Keys {
        static let proteinG = "settings.diet.proteinG"
        static let fatG = "settings.diet.fatG"
        static let carbsG = "settings.diet.carbsG"

        /// Wartość oznaczająca brak nadpisania.
        static let noOverride = -1
    }

    /// To, co realnie obowiązuje: ręczne nadpisanie, a w jego braku wyliczenie
    /// z sylwetki, celu i aktywności.
    static func resolve(
        calorieGoal: Int,
        goal: UserGoal,
        metrics: BodyMetrics?,
        proteinOverride: Int,
        fatOverride: Int,
        carbsOverride: Int
    ) -> DailyNutritionTargets {
        guard let computed = metrics?.macroTargets(for: goal, calories: calorieGoal) else {
            return DailyNutritionTargets(kcal: calorieGoal, macros: nil)
        }

        return DailyNutritionTargets(
            kcal: calorieGoal,
            macros: MacroTargets(
                proteinG: proteinOverride >= 0 ? proteinOverride : computed.proteinG,
                fatG: fatOverride >= 0 ? fatOverride : computed.fatG,
                carbsG: carbsOverride >= 0 ? carbsOverride : computed.carbsG
            )
        )
    }
}

// MARK: - Domyślna sylwetka domownika

extension DailyNutritionTargets {
    /// Sylwetka, z której liczymy cel osoby, o której nic nie wiemy:
    /// rocznik 2000, 70 kg, 170 cm, bez płci (BMR ze środka wzoru, −78),
    /// 2–3 treningi w tygodniu. Nie jest niczyim prawdziwym celem — ma tylko
    /// sprawić, że „Cel dnia” domownika bez danych wygląda tak samo jak
    /// każdy inny: kalorie i trzy makra z torami, zamiast wierszy bez prawej
    /// strony i arkusza, który zmienia wysokość przy przełączeniu osoby.
    static let fallbackMetrics = BodyMetrics(
        heightCm: 170,
        weightKg: 70,
        yearOfBirth: 2000,
        activityRaw: ActivityLevel.light.rawValue
    )

    /// Cel z domyślnej sylwetki: kalorie z niej (albo podane), makra z niej.
    static func fallback(kcal: Int? = nil, goal: UserGoal = .healthy) -> DailyNutritionTargets {
        guard let metrics = fallbackMetrics else {
            return DailyNutritionTargets(kcal: kcal ?? RecipePersonalization.defaultCalorieGoal, macros: nil)
        }
        let calories = kcal ?? metrics.suggestedCalories(for: goal)
        return DailyNutritionTargets(
            kcal: calories,
            macros: metrics.macroTargets(for: goal, calories: calories)
        )
    }

    /// Cel domownika zawsze pełny — JEDYNE miejsce, w którym brak danych
    /// zamienia się w domyślną sylwetkę. Brak celu (serwer nie podał, jeszcze
    /// nie przyszedł, domownik bez profilu) = cały cel z domyślnej sylwetki;
    /// kalorie bez makr = makra z domyślnej sylwetki przy JEGO kaloriach.
    static func forMember(_ targets: DailyNutritionTargets?) -> DailyNutritionTargets {
        guard let targets else { return fallback() }
        guard targets.macros == nil else { return targets }
        return fallback(kcal: targets.kcal)
    }
}
