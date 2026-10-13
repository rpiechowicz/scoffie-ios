import Foundation

// MARK: - Backend DTOs (aligned with backend ShoppingList model)

struct BackendShoppingItemDTO: Codable {
    let productKey: String
    let name: String
    let unit: String
    let department: String
    let totalAmount: Double
    let isChecked: Bool
    /// Tytuły przepisów, z których coś do pozycji DOPISANO („brakuje mi”
    /// ze szczegółu przepisu). Opcjonalne — starszy backend pola nie zna.
    let addedFrom: [String]?
    /// Przyprawy: „1 łyżeczka” zamiast „6 g”. Starszy backend — `nil`.
    let kitchenMeasure: KitchenMeasure?
    /// Część dopisana ręcznie. Starszy backend — brak pola.
    let manual: ShoppingManualPart?
}

struct BackendShoppingListArchiveItemDTO: Codable {
    let productKey: String
    let name: String
    let unit: String
    let department: String
    let totalAmount: Double
    let isChecked: Bool
    let kitchenMeasure: KitchenMeasure?
}

struct BackendShoppingListArchiveDTO: Codable {
    let archiveId: String
    let weekStart: String
    let weekLabel: String
    let revision: Int
    let archivedAt: Double
    let isCurrentClosed: Bool
    let items: [BackendShoppingListArchiveItemDTO]
}

struct BackendShoppingListStateDTO: Codable {
    let items: [BackendShoppingItemDTO]
    let archives: [BackendShoppingListArchiveDTO]
    /// Ostatnio dopisywane w domu. Starszy backend — brak pola.
    let recentProducts: [ShoppingRecentProduct]?
}

/// Produkt katalogu z `weeklyPlans:shoppingProducts`.
struct BackendShoppingProductDTO: Codable {
    let id: String
    let name: String
    let department: String
    let pieceOnly: Bool
    let aliases: [String]
}

/// Katalog produktów; `products == nil` = telefon ma już tę rewizję.
struct BackendShoppingProductCatalogDTO: Codable {
    let revision: String
    let products: [BackendShoppingProductDTO]?
}

/// Ack `weeklyPlans:addShoppingProducts`.
struct BackendAddShoppingProductsResultDTO: Codable {
    let added: Int
}

/// Ack `weeklyPlans:setShoppingProductAmount` — klucz wiersza po zmianie.
struct BackendSetShoppingProductAmountResultDTO: Codable {
    let productKey: String
}

struct BackendHouseholdDTO: Codable {
    let id: String
    let name: String
    /// Sloty posiłków planowane przez gospodarstwo. Opcjonalne — starszy
    /// backend pola nie dowozi i wtedy klient zostaje przy trójce
    /// podstawowej zamiast wywalić się na dekodowaniu gospodarstwa.
    let enabledMealTypes: [String]?
    /// Pory posiłków: mapa `MealType → minuty od północy`. Opcjonalna z tego
    /// samego powodu co wyżej, a dodatkowo `null` ma własne znaczenie:
    /// gospodarstwo nie ruszało godzin, więc obowiązują domyślne.
    let mealSlotTimes: [String: Int]?
}

struct BackendShoppingItemCheckDTO: Codable {
    let id: String
    let productKey: String
    let isChecked: Bool
}

struct BackendShoppingListChangedDTO: Codable {
    let householdId: String
    let weekStart: String
    let action: String?
    let changedByUserId: String?
    let changedByDisplayName: String?
    let productKey: String?
    let isChecked: Bool?
    let changeVersion: Int64?
}

/// Ack `weeklyPlans:addRecipeExtras` — ile produktów trafiło na listę.
struct BackendAddRecipeExtrasResultDTO: Codable {
    let added: Int
    let productKeys: [String]
}

/// Generic mutation ack returned by archive/select/delete shopping-list events.
struct BackendMutationResultDTO: Codable {
    let success: Bool?
    let archiveId: String?
    let weekStart: String?
}

// MARK: - DTO -> domain mapping

extension BackendShoppingItemDTO {
    func toAppModel() -> ShoppingItem {
        ShoppingItem(
            productKey: productKey,
            name: name,
            totalAmount: totalAmount,
            unit: unit,
            department: department,
            isChecked: isChecked,
            addedFrom: addedFrom?.isEmpty == false ? addedFrom : nil,
            kitchenMeasure: kitchenMeasure,
            manual: manual
        )
    }
}

extension BackendShoppingProductDTO {
    func toAppModel() -> ShoppingProduct {
        ShoppingProduct(
            name: name,
            department: department,
            ingredientId: id,
            pieceOnly: pieceOnly,
            aliases: aliases
        )
    }
}

extension BackendShoppingListArchiveItemDTO {
    func toAppModel() -> ShoppingItem {
        ShoppingItem(
            productKey: productKey,
            name: name,
            totalAmount: totalAmount,
            unit: unit,
            department: department,
            isChecked: isChecked,
            kitchenMeasure: kitchenMeasure
        )
    }
}

extension BackendShoppingListArchiveDTO {
    func toAppModel() -> ArchivedShoppingList {
        ArchivedShoppingList(
            archiveId: archiveId,
            weekStart: weekStart,
            weekLabel: weekLabel,
            revision: revision,
            archivedAt: Date(timeIntervalSince1970: archivedAt / 1000),
            isCurrentClosed: isCurrentClosed,
            items: items.map { $0.toAppModel() }
        )
    }
}
