import Foundation

struct ShoppingItem: Identifiable, Codable, Hashable {
    var id: String { productKey }
    let productKey: String
    var name: String
    var totalAmount: Double
    var unit: String
    var department: String
    var isChecked: Bool

    /// Ilość z jednostką gotowa do pokazania: „480 g", „2 szt", a dla
    /// śladowych przypraw „do smaku" — zamiast „Sól 0 g", które dawało
    /// zaokrąglanie do liczby całkowitej.
    var displayAmount: String {
        let mappedUnit = IngredientUnit(rawValue: unit) ?? .other
        return KitchenAmount.format(
            amount: totalAmount,
            unit: mappedUnit,
            rawUnit: unit,
            department: department
        )
    }
}
