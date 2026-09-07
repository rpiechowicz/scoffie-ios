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
