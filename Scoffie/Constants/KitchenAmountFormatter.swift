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

    /// Tekst ilości z jednostką, np. „320 g", „2 szczypty", „½ łyżeczki".
    ///
    /// Przyprawy idą miarą kuchenną (`spiceText`): „1 g soli" nie jest do
    /// odmierzenia, „szczypta" jest. Bez miary z backendu (starszy serwer,
    /// przyprawa spoza tabeli) przyprawa poniżej grama to „do smaku" — zamiast
    /// „Sól 0 g". Dotyczy tylko działu przypraw, żeby 0,5 g drożdży czy
    /// szafranu nie zniknęło za tym napisem.
    static func format(
        amount: Double,
        unit: IngredientUnit,
        rawUnit: String? = nil,
        department: String? = nil,
        measure: KitchenMeasure? = nil
    ) -> String {
        if department == spicesDepartment {
            if let text = spiceText(amount: amount, unit: unit, measure: measure) {
                return text
            }
            if unit == .gram || unit == .milliliter, amount < 1 {
                return "do smaku"
            }
        }

        let value = rounded(amount, unit: unit)
        let number = numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(number) \(unitLabel(unit, rawUnit: rawUnit, amount: value))"
    }

    /// Przyprawa miarą kuchenną albo `nil` (pokaż jak dotąd). Gramy/ml —
    /// przez `measure` z backendu; łyżeczki i łyżki z przepisu — wprost, bo po
    /// skalowaniu porcji „0,33 łyżeczki" też ma być do odmierzenia.
    static func spiceText(amount: Double, unit: IngredientUnit, measure: KitchenMeasure?) -> String? {
        guard amount > 0 else { return nil }
        switch unit {
        case .teaspoon:
            return spoonText(teaspoons: amount)
        case .tablespoon:
            return spoonText(teaspoons: amount * teaspoonsPerTablespoon)
        case .gram, .milliliter:
            guard let measure, measure.per > 0 else { return nil }
            switch measure.kind {
            case KitchenMeasure.spoon:
                return spoonText(teaspoons: amount / measure.per)
            case KitchenMeasure.piece:
                return pieceText(pieces: amount / measure.per, measure: measure)
            default:
                return nil
            }
        default:
            return nil
        }
    }

    /// Łyżeczki → tekst drabiną miar, które da się odmierzyć: szczypta, ¼, ½,
    /// 1, 1½, 2 łyżeczki, potem łyżki co pół do `maxTablespoons`. Więcej =
    /// `nil` (270 g cukru się waży). Ta sama drabina na Androidzie
    /// (`KitchenAmount.spoonText`) — progi zmieniaj w obu naraz.
    static func spoonText(teaspoons: Double) -> String? {
        switch teaspoons {
        case ...0: return nil
        case ..<0.1875: return "szczypta"
        case ..<0.375: return "¼ łyżeczki"
        case ..<0.75: return "½ łyżeczki"
        case ..<1.25: return "1 łyżeczka"
        case ..<1.75: return "1½ łyżeczki"
        case ..<2.5: return "2 łyżeczki"
        // Od 12,75 łyżeczki połówka łyżki zaokrągla się powyżej 4 łyżek (jak
        // na Androidzie); osobny przypadek chroni też `Int(...)` przed liczbą
        // spoza zakresu.
        case 12.75...: return nil
        default:
            let halves = max(2, Int((teaspoons / teaspoonsPerTablespoon * 2).rounded()))
            guard halves <= maxTablespoons * 2 else { return nil }
            if halves % 2 == 1 {
                return "\(halves / 2)½ łyżki"
            }
            let whole = halves / 2
            return "\(whole) \(PolishPlural.form(whole, one: "łyżka", few: "łyżki", many: "łyżek"))"
        }
    }

    /// Sztuki przyprawy („2 liście") — całe, co najmniej jedna.
    private static func pieceText(pieces: Double, measure: KitchenMeasure) -> String? {
        guard let one = measure.one, let few = measure.few, let many = measure.many else {
            return nil
        }
        // Górna granica tylko po to, żeby `Int(...)` nie wywróciło aplikacji
        // przy zepsutych danych (`per` bliskie zera).
        let count = max(1, Int(min(pieces, 1_000).rounded()))
        return "\(count) \(PolishPlural.form(count, one: one, few: few, many: many))"
    }

    private static let teaspoonsPerTablespoon = 3.0
    private static let maxTablespoons = 4

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
