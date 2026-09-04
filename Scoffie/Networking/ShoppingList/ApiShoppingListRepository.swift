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
                .sorted { $0.archivedAt > $1.archivedAt }
        )
    }

    func setChecked(weekStart: String, productKey: String, isChecked: Bool) async throws {
        try await client.setChecked(weekStart: weekStart, productKey: productKey, isChecked: isChecked)
    }

    func archiveShoppingList(weekStart: String, weekLabel: String) async throws {
        try await client.archiveShoppingList(weekStart: weekStart, weekLabel: weekLabel)
    }

    func selectArchivedList(archiveId: String) async throws {
        try await client.selectArchivedList(archiveId: archiveId)
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
