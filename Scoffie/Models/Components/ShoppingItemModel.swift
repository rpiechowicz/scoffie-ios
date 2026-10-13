import Foundation

struct ShoppingItem: Identifiable, Codable, Hashable {
    var id: String { productKey }
    let productKey: String
    var name: String
    var totalAmount: Double
    var unit: String
    var department: String
    var isChecked: Bool
    /// Przepisy, z których produkt DOPISANO do listy spoza planu. `nil` =
    /// pozycja wyłącznie z planu. Opcjonalne, żeby lista z cache'u sprzed
    /// tego pola dalej się dekodowała.
    var addedFrom: [String]? = nil
    /// Przyprawy: jak pokazać ilość w kuchni. Opcjonalne jak `addedFrom`.
    var kitchenMeasure: KitchenMeasure? = nil
    /// Część dopisana RĘCZNIE z arkusza „Dodaj produkty” (13.10.2026).
    /// `nil` = nikt jej nie dopisał. Opcjonalne jak `addedFrom`.
    var manual: ShoppingManualPart? = nil

    /// Czy na pozycji jest dopisana część — z przepisu albo ręcznie — którą
    /// da się zdjąć z listy.
    var hasAddedPart: Bool { !(addedFrom ?? []).isEmpty || manual != nil }

    /// Wiersz bez ilości („kup chleb”) — nie ma czego pokazać w pigułce.
    var hasAmount: Bool { !unit.isEmpty }

    /// Ilość z jednostką gotowa do pokazania: „480 g", „2 szt", a dla
    /// śladowych przypraw „do smaku" — zamiast „Sól 0 g", które dawało
    /// zaokrąglanie do liczby całkowitej. Pusta dla wiersza bez ilości;
    /// od tysiąca gramów i mililitrów — kilogramy i litry („1,3 l”).
    var displayAmount: String {
        guard hasAmount else { return "" }
        if department != KitchenAmount.spicesDepartment,
           (unit == "g" || unit == "ml"), totalAmount >= 1000 {
            return ShoppingAmountText.list(totalAmount, unit: unit)
        }
        let mappedUnit = IngredientUnit(rawValue: unit) ?? .other
        return KitchenAmount.format(
            amount: totalAmount,
            unit: mappedUnit,
            rawUnit: unit,
            department: department,
            measure: kitchenMeasure
        )
    }
}
