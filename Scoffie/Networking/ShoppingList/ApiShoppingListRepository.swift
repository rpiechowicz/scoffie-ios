import Foundation

/// Domain-level shopping list repository. Hides the DTO layer from
/// `ShoppingListStore` and sorts archives by recency on the way out.
final class ApiShoppingListRepository: ShoppingListRepository {
    private let client: ShoppingListTransportClient

    init(client: ShoppingListTransportClient) {
        self.client = client
    }

    func fetchShoppingListState(weekStart: String) async throws -> ShoppingListState {
        let state = try await client.fetchShoppingListState(weekStart: weekStart)
        return ShoppingListState(
            items: state.items.map { $0.toAppModel() },
            archives: state.archives
                .map { $0.toAppModel() }
                .sorted { $0.archivedAt > $1.archivedAt },
            recentProducts: state.recentProducts
        )
    }

    func fetchProductCatalog(revision: String?) async throws -> (revision: String, products: [ShoppingProduct]?) {
        let catalog = try await client.fetchProductCatalog(revision: revision)
        return (catalog.revision, catalog.products?.map { $0.toAppModel() })
    }

    func addProducts(weekStart: String, drafts: [ShoppingProductDraft], mutationId: UUID) async throws -> Int {
        try await client.addProducts(
            weekStart: weekStart,
            clientMutationId: mutationId.uuidString.lowercased(),
            items: drafts.map(ShoppingProductInputPayload.init(draft:))
        ).added
    }

    func setProductAmount(weekStart: String, productKey: String, amount: ShoppingAmount?) async throws {
        _ = try await client.setProductAmount(
            weekStart: weekStart,
            productKey: productKey,
            amount: amount?.value,
            unit: amount?.unit.rawValue
        )
    }

    func setChecked(weekStart: String, productKey: String, isChecked: Bool) async throws {
        try await client.setChecked(weekStart: weekStart, productKey: productKey, isChecked: isChecked)
    }

    func addRecipeExtras(weekStart: String, recipeId: String, servings: Int, ingredientIds: [String]) async throws -> Int {
        try await client.addRecipeExtras(
            weekStart: weekStart,
            recipeId: recipeId,
            servings: servings,
            ingredientIds: ingredientIds
        ).added
    }

    func removeExtra(weekStart: String, productKey: String) async throws {
        try await client.removeExtra(weekStart: weekStart, productKey: productKey)
    }

    func archiveShoppingList(weekStart: String, weekLabel: String) async throws {
        try await client.archiveShoppingList(weekStart: weekStart, weekLabel: weekLabel)
    }

    func deleteArchivedList(archiveId: String) async throws {
        try await client.deleteArchivedList(archiveId: archiveId)
    }

    func deleteAllArchivedLists(weekStart: String) async throws {
        try await client.deleteAllArchivedLists(weekStart: weekStart)
    }

    func observeShoppingListChanges(_ onChange: @escaping (_ event: BackendShoppingListChangedDTO) -> Void) {
        client.observeShoppingListChanges(onChange)
    }

    func observeRealtimeReconnect(_ onReconnect: @escaping () -> Void) {
        client.observeRealtimeReconnect(onReconnect)
    }
}
