import Foundation

/// Ilości w trybie Gotuj: skalowanie do porcji sesji, zaokrąglenie do
/// odmierzalnych wartości (§5.4) i podstawienie liczby sztuk w tekście kroku.
///
/// Czysta logika (Foundation + `KitchenAmount`) — sprawdzian:
/// `sh Scripts/cook-logic-check.sh`.
enum CookAmounts {
    /// Mnożnik ilości scenariusza: porcje sesji ÷ porcje, dla których pisano.
    static func factor(portions: Int, basePortions: Int) -> Double {
        Double(max(1, portions)) / Double(max(1, basePortions))
    }

    /// Ilość po skalowaniu, zaokrąglona do tego, co da się odmierzyć (§5.4):
    /// - przy porcjach scenariusza (mnożnik 1) nic nie ruszamy — liczby mają
    ///   się zgadzać z przepisem co do grama;
    /// - sztuki — do całości, od połowy w górę, co najmniej jedna
    ///   (3 porcje: 1,5 jajka → 2);
    /// - gramy i mililitry — co 5 poniżej 100, co 10 od 100 (375 g → 380 g);
    ///   poniżej 10 zostaje dokładność `KitchenAmount.rounded`, bo „7,5 g”
    ///   koperku to wciąż informacja, a „5 g” byłoby kłamstwem o połowę;
    /// - reszta jednostek — jak w szczegółach przepisu (`KitchenAmount.rounded`).
    /// Przyprawy nie przechodzą tędy: ich drabina miar żyje w `KitchenAmount.format`.
    static func scaled(_ amount: Double, unit: IngredientUnit, factor: Double) -> Double {
        guard amount > 0 else { return amount }
        guard abs(factor - 1) > 0.000_1 else { return amount }
        let value = amount * factor
        switch unit {
        case .piece:
            return max(1, (value).rounded(.toNearestOrAwayFromZero))
        case .gram, .milliliter:
            if value < 10 { return KitchenAmount.rounded(value, unit: unit) }
            let step: Double = value < 100 ? 5 : 10
            return max(step, (value / step).rounded(.toNearestOrAwayFromZero) * step)
        default:
            return KitchenAmount.rounded(value, unit: unit)
        }
    }

    /// Tekst ilości przy kroku: „30 g”, „2 szt”, „szczypta”, „½ łyżeczki”.
    ///
    /// Przyprawy idą miarą kuchenną z NIEzaokrąglonej ilości — drabina
    /// łyżeczek sama wybiera najbliższą miarę, a zaokrąglenie gramów przed nią
    /// zrobiłoby z 1,5 g soli 0 albo 5 g.
    static func amountText(
        amount: Double,
        unit rawUnit: String,
        department: String?,
        measure: KitchenMeasure?,
        factor: Double
    ) -> String {
        let unit = IngredientUnit(rawValue: rawUnit) ?? .other
        let isSpice = department == KitchenAmount.spicesDepartment
        let value = isSpice ? amount * factor : scaled(amount, unit: unit, factor: factor)
        return KitchenAmount.format(
            amount: value,
            unit: unit,
            rawUnit: unit == .other ? rawUnit : nil,
            department: department,
            measure: measure
        )
    }

    /// Podpis części przy składniku: „połowa”, „reszta”; `nil` = sama ilość.
    static func partLabel(_ part: CookIngredientPart) -> String? {
        switch part {
        case .half: "połowa"
        case .rest: "reszta"
        case .all, .part: nil
        }
    }

    /// Liczba sztuk dania („kotlety”, „wałeczki”) dla porcji sesji — porcje
    /// zaokrąglone w górę, po jednej na porcję (prompt systemu pisania).
    static func pieceCount(portions: Double) -> Int {
        max(1, Int(portions.rounded(.up)))
    }

    /// Tekst kroku z podstawionymi tokenami `{count:id|1|2–4|5+}` →
    /// „2 wałeczki”, „5 kotletów”. Token jest tylko w `body` (D38).
    ///
    /// Zepsuty token zostaje w tekście dosłownie — lepiej pokazać nawias,
    /// niż po cichu zgubić kawałek zdania.
    static func renderBody(_ body: String, portions: Double) -> String {
        let count = pieceCount(portions: portions)
        var result = ""
        var rest = Substring(body)
        while let open = rest.range(of: "{count:") {
            result += rest[rest.startIndex..<open.lowerBound]
            guard let close = rest[open.upperBound...].firstIndex(of: "}") else {
                result += rest[open.lowerBound...]
                return result
            }
            let inside = rest[open.upperBound..<close]
            let parts = inside.split(separator: "|", omittingEmptySubsequences: false)
            if parts.count == 4, !parts[0].isEmpty, parts.dropFirst().allSatisfy({ !$0.isEmpty }) {
                let form = PolishPlural.form(
                    count,
                    one: String(parts[1]),
                    few: String(parts[2]),
                    many: String(parts[3])
                )
                result += "\(count) \(form)"
            } else {
                result += rest[open.lowerBound...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        return result
    }
}

/// Jeden składnik kroku gotowy do pokazania: pigułka w kroku, wiersz
/// w arkuszu „Składniki”.
struct CookIngredientLine: Equatable, Identifiable {
    /// Krok + składnik — ten sam składnik bywa w kilku krokach (sól ×3).
    let id: String
    let stepId: String
    let ingredientId: String
    let name: String
    let amountText: String
    let partLabel: String?
    let part: CookIngredientPart
    let department: String?
}

extension CookPackage {
    /// Składniki kroku w ilościach dla `portions` porcji. Składnik, którego
    /// nie ma w przepisie (rozjazd danych), wypada — lepiej brak pigułki niż
    /// pigułka „? · 30 g”.
    func lines(for step: CookStep, portions: Int) -> [CookIngredientLine] {
        let factor = CookAmounts.factor(portions: portions, basePortions: scenario.basePortions)
        return step.ingredients.compactMap { item in
            guard let info = ingredient(item.ingredientId) else { return nil }
            return CookIngredientLine(
                id: "\(step.id)·\(info.ingredientId)",
                stepId: step.id,
                ingredientId: info.ingredientId,
                name: info.name,
                amountText: CookAmounts.amountText(
                    amount: item.amount,
                    unit: item.unit,
                    department: info.department,
                    measure: info.kitchenMeasure,
                    factor: factor
                ),
                partLabel: CookAmounts.partLabel(item.part),
                part: item.part,
                department: info.department
            )
        }
    }

    /// Cały przepis w ilościach sesji — arkusz „Cały przepis” i powitanie.
    /// Kolejność jak w przepisie; ilość to suma ze wszystkich kroków, a gdy
    /// składnik nie trafił do żadnego kroku — ilość z przepisu.
    func allLines(portions: Int) -> [CookIngredientLine] {
        let factor = CookAmounts.factor(portions: portions, basePortions: scenario.basePortions)
        var used: [String: Double] = [:]
        for step in scenario.steps {
            for item in step.ingredients {
                used[item.ingredientId.lowercased(), default: 0] += item.amount
            }
        }
        return ingredients.map { info in
            let base = used[info.ingredientId] ?? info.amount
            return CookIngredientLine(
                id: "all·\(info.ingredientId)",
                stepId: "",
                ingredientId: info.ingredientId,
                name: info.name,
                amountText: CookAmounts.amountText(
                    amount: base,
                    unit: info.unit,
                    department: info.department,
                    measure: info.kitchenMeasure,
                    factor: factor
                ),
                partLabel: nil,
                part: .all,
                department: info.department
            )
        }
    }

    /// Tekst „jak” kroku z liczbą sztuk dla porcji sesji.
    func body(for step: CookStep, portions: Int) -> String {
        CookAmounts.renderBody(step.body, portions: Double(portions))
    }

    /// Nota skali, gdy porcje sesji ją przekraczają.
    func scaleNote(for step: CookStep, portions: Int) -> String? {
        guard let note = step.scaleNote, portions >= note.fromPortions else { return nil }
        return note.text
    }

    /// Nazwy przywołanych składników („z talerzy z panierką”) — bez ilości.
    func mentionNames(for step: CookStep) -> [String] {
        step.mentions.compactMap { ingredient($0)?.name }
    }
}
