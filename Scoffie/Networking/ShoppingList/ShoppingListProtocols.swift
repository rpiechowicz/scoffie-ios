import Foundation

// MARK: - Repository / Transport protocols
//
// Layering: Store -> ShoppingListRepository -> ShoppingListTransportClient -> RecipeSocketClient
//   - Repository: domain-shaped API (ShoppingListState, ShoppingItem)
//   - Transport:  protocol-shaped API (BackendShoppingListStateDTO)
//
// The shopping list reuses `RecipeSocketClient` as the underlying socket
// transport — there is no separate ShoppingListSocketClient.

protocol ShoppingListRepository {
    func fetchShoppingListState(weekStart: String) async throws -> ShoppingListState
    func setChecked(weekStart: String, productKey: String, isChecked: Bool) async throws
    func addRecipeExtras(weekStart: String, recipeId: String, servings: Int, ingredientIds: [String]) async throws -> Int
    func removeExtra(weekStart: String, productKey: String) async throws
    /// Katalog produktów; `nil` = rewizja się nie zmieniła.
    func fetchProductCatalog(revision: String?) async throws -> (revision: String, products: [ShoppingProduct]?)
    func addProducts(weekStart: String, drafts: [ShoppingProductDraft], mutationId: UUID) async throws -> Int
    func setProductAmount(weekStart: String, productKey: String, amount: ShoppingAmount?) async throws
    func archiveShoppingList(weekStart: String, weekLabel: String) async throws
    func deleteArchivedList(archiveId: String) async throws
    func deleteAllArchivedLists(weekStart: String) async throws
    func observeShoppingListChanges(_ onChange: @escaping (_ event: BackendShoppingListChangedDTO) -> Void)
    func observeRealtimeReconnect(_ onReconnect: @escaping () -> Void)
}

protocol ShoppingListTransportClient {
    func fetchShoppingListState(weekStart: String) async throws -> BackendShoppingListStateDTO
    func setChecked(weekStart: String, productKey: String, isChecked: Bool) async throws
    func addRecipeExtras(weekStart: String, recipeId: String, servings: Int, ingredientIds: [String]) async throws -> BackendAddRecipeExtrasResultDTO
    func removeExtra(weekStart: String, productKey: String) async throws
    func fetchProductCatalog(revision: String?) async throws -> BackendShoppingProductCatalogDTO
    func addProducts(weekStart: String, clientMutationId: String, items: [ShoppingProductInputPayload]) async throws -> BackendAddShoppingProductsResultDTO
    func setProductAmount(weekStart: String, productKey: String, amount: Double?, unit: String?) async throws -> BackendSetShoppingProductAmountResultDTO
    func archiveShoppingList(weekStart: String, weekLabel: String) async throws
    func deleteArchivedList(archiveId: String) async throws
    func deleteAllArchivedLists(weekStart: String) async throws
    func observeShoppingListChanges(_ onChange: @escaping (_ event: BackendShoppingListChangedDTO) -> Void)
    func observeRealtimeReconnect(_ onReconnect: @escaping () -> Void)
}

/// Jeden produkt w `weeklyPlans:addShoppingProducts` — z katalogu
/// (`ingredientId`) albo własny (`name` + `department`); ilość razem z
/// jednostką albo wcale.
struct ShoppingProductInputPayload: Encodable {
    let ingredientId: String?
    let name: String?
    let department: String?
    let amount: Double?
    let unit: String?

    init(draft: ShoppingProductDraft) {
        ingredientId = draft.product.ingredientId
        name = draft.product.isCustom ? draft.product.name : nil
        department = draft.product.isCustom ? draft.product.department : nil
        amount = draft.amount?.value
        unit = draft.amount?.unit.rawValue
    }

    /// Pola `nil` nie idą w ogóle — serwer sprawdza „ilość z jednostką albo
    /// nic”, a `null` przy jednym z nich byłoby czytelne, ale zbędne.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(ingredientId, forKey: .ingredientId)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(department, forKey: .department)
        try container.encodeIfPresent(amount, forKey: .amount)
        try container.encodeIfPresent(unit, forKey: .unit)
    }

    private enum CodingKeys: String, CodingKey {
        case ingredientId, name, department, amount, unit
    }
}
