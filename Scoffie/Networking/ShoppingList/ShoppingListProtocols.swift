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
    func archiveShoppingList(weekStart: String, weekLabel: String) async throws
    func selectArchivedList(archiveId: String) async throws
    func deleteArchivedList(archiveId: String) async throws
    func deleteAllArchivedLists(weekStart: String) async throws
    func observeShoppingListChanges(_ onChange: @escaping (_ event: BackendShoppingListChangedDTO) -> Void)
    func observeRealtimeReconnect(_ onReconnect: @escaping () -> Void)
}

protocol ShoppingListTransportClient {
    func fetchShoppingListState(weekStart: String) async throws -> BackendShoppingListStateDTO
    func setChecked(weekStart: String, productKey: String, isChecked: Bool) async throws
    func archiveShoppingList(weekStart: String, weekLabel: String) async throws
    func selectArchivedList(archiveId: String) async throws
    func deleteArchivedList(archiveId: String) async throws
    func deleteAllArchivedLists(weekStart: String) async throws
    func observeShoppingListChanges(_ onChange: @escaping (_ event: BackendShoppingListChangedDTO) -> Void)
    func observeRealtimeReconnect(_ onReconnect: @escaping () -> Void)
}
