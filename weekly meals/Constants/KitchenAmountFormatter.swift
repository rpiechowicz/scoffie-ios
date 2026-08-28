import Foundation

/// Jedno miejsce, w którym ilość składnika zamienia się w tekst dla kuchni —
/// szczegół przepisu i lista zakupów muszą pokazywać to samo, bo obie
/// liczby biorą się z tych samych gramatur (cały przepis ÷ porcje).
enum KitchenAmount {
    /// Dział katalogu, którego śladowe ilości nie są do odmierzenia.
    static let spicesDepartment = "Przyprawy i sosy"

    /// Ilość zaokrąglona do wartości, którą da się odmierzyć w kuchni.
    ///
    /// Skalowanie porcji dzieli gramatury przez liczbę porcji przepisu, więc
    /// z „5 szt" przy jednej porcji robi się 2,5, a z „100 g" — 33,33. Suche
    /// obcięcie do dwóch miejsc po przecinku daje listę zakupów, po której
    /// nikt nie gotuje. Reguła:
    /// — rzeczy liczone sztukami i miarkami idą do połówki, bo pół jajka
    ///   i pół łyżki da się odmierzyć, a 0,33 łyżki nie;
    /// — szczypta jest niepodzielna: zaokrąglamy do całych, minimum jedna;
    /// — gramy i mililitry od 10 w górę tną się do liczby całkowitej, bo przy
    ///   takiej masie ułamek grama to szum wagi kuchennej, a nie informacja;
    ///   poniżej 10 zostaje jedno miejsce, żeby „7,5 g drożdży" nie awansowało
    ///   na 8 g;
    /// — kilogramy i litry zostają z dwoma miejscami, bo w przepisach
    ///   występują właśnie jako ułamki (0,25 kg) i połówka zrobiłaby z ćwierć
    ///   kilo pół;
    /// — nieznana jednostka z backendu dostaje jedno miejsce po przecinku.
    /// Z niezerowej ilości nigdy nie wychodzi zero — składnik ma się pojawić
    /// na liście choćby w ilości śladowej.
    static func rounded(_ amount: Double, unit: IngredientUnit) -> Double {
        guard amount > 0 else { return amount }

        switch unit {
        case .piece, .teaspoon, .tablespoon, .cup:
            return max(0.5, (amount * 2).rounded() / 2)
        case .pinch:
            return max(1, amount.rounded())
        case .gram, .milliliter:
            return amount >= 10 ? amount.rounded() : max(0.1, (amount * 10).rounded() / 10)
        case .kilogram, .liter:
            return max(0.01, (amount * 100).rounded() / 100)
        case .other:
            return max(0.1, (amount * 10).rounded() / 10)
        }
    }

    /// Tekst ilości z jednostką, np. „320 g", „2 szczypty", „0,5 łyżeczki".
    ///
    /// Przyprawy poniżej grama (szczypta soli po normalizacji to 0,375 g)
    /// nie są do odmierzenia ani do kupienia w takiej ilości — zamiast
    /// „Sól 0 g" lista pokazuje „do smaku". Dotyczy tylko działu przypraw,
    /// żeby 0,5 g drożdży czy szafranu nie zniknęło za tym napisem.
    static func format(
        amount: Double,
        unit: IngredientUnit,
        rawUnit: String? = nil,
        department: String? = nil
    ) -> String {
        if department == spicesDepartment,
           unit == .gram || unit == .milliliter,
           amount < 1 {
            return "do smaku"
        }

        let value = rounded(amount, unit: unit)
        let number = numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(number) \(unitLabel(unit, rawUnit: rawUnit, amount: value))"
    }

    /// Etykieta jednostki odmieniona tam, gdzie to razi: „1 szczypta",
    /// „2 szczypty", „5 szczypt". Nieznana jednostka pokazuje to, co przysłał
    /// backend, zamiast kasować składnik.
    static func unitLabel(_ unit: IngredientUnit, rawUnit: String?, amount: Double) -> String {
        switch unit {
        case .pinch:
            let count = Int(amount.rounded())
            return PolishPlural.form(count, one: "szczypta", few: "szczypty", many: "szczypt")
        case .other:
            return rawUnit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? unit.rawValue
        default:
            return unit.rawValue
        }
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        return formatter
    }()
}
