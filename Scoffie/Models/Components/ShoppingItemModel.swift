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

    /// Czy na pozycji jest dopisana część, którą da się zdjąć z listy.
    var hasAddedPart: Bool { !(addedFrom ?? []).isEmpty }

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
