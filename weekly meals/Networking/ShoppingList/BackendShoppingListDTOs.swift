import Foundation

// MARK: - Backend DTOs (aligned with backend ShoppingList model)

struct BackendShoppingItemDTO: Codable {
    let productKey: String
    let name: String
    let unit: String
    let department: String
    let totalAmount: Double
    let isChecked: Bool
}

struct BackendShoppingListArchiveItemDTO: Codable {
    let productKey: String
    let name: String
    let unit: String
    let department: String
    let totalAmount: Double
    let isChecked: Bool
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
            isChecked: isChecked
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
            isChecked: isChecked
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
