import Foundation

// MARK: - Repository / Transport / Socket protocols
//
// Layering: View/Store -> RecipeRepository -> RecipeTransportClient -> RecipeSocketClient
//   - Repository: domain-level API working in app types (Recipe, UUID)
//   - Transport:  protocol-level API working in DTOs (Strings, BackendRecipeDTO)
//   - Socket:     raw event-level API working in JSON-compatible payloads

/// Jedna strona katalogu.
///
/// Dwie liczby zamiast jednej listy, bo to nie jest to samo: mapowanie DTO →
/// `Recipe` potrafi odrzucić wiersz (id spoza UUID), a stronicowanie musi
/// patrzeć na to, ILE SERWER PRZYSŁAŁ, nie na to, ile z tego zostało. Pętla
/// czytająca `recipes.count` brała jeden odrzucony wiersz na pełnej stronie za
/// koniec katalogu i reszta stron nigdy nie dojeżdżała — a użytkownik widział
/// „urwany" katalog bez śladu błędu.
struct RecipePage {
    let recipes: [Recipe]
    /// Liczba wierszy sprzed mapowania — po niej poznaje się ostatnią stronę.
    let receivedCount: Int
}

protocol RecipeRepository {
    func fetchRecipes(page: Int, limit: Int) async throws -> RecipePage
    func fetchRecipeById(_ recipeId: UUID) async throws -> Recipe
    func setFavorite(recipeId: UUID, isFavorite: Bool) async throws
    func observeFavoritesChanges(_ onChange: @escaping (_ recipeId: UUID, _ isFavorite: Bool) -> Void)
    func observeRealtimeReconnect(_ onReconnect: @escaping () -> Void)
}

protocol RecipeTransportClient {
    func fetchRecipes(page: Int, limit: Int) async throws -> [BackendRecipeDTO]
    func fetchRecipeById(recipeId: String) async throws -> BackendRecipeDTO
    func setFavorite(recipeId: String, isFavorite: Bool) async throws
    func observeFavoritesChanges(_ onChange: @escaping (_ recipeId: String, _ isFavorite: Bool) -> Void)
    func observeRealtimeReconnect(_ onReconnect: @escaping () -> Void)
}

protocol RecipeSocketClient {
    func emitWithAck<T: Decodable>(event: String, payload: [String: Any], as: T.Type) async throws -> T
    func on(event: String, handler: @escaping ([Any]) -> Void)
    func off(event: String)
    func observeConnection(_ handler: @escaping (_ isConnected: Bool) -> Void)
    /// Wznów zerwane połączenie (np. po powrocie aplikacji z tła).
    /// Domyślnie no-op — realny reconnect ma tylko klient Socket.IO.
    func reconnectIfNeeded()
}

extension RecipeSocketClient {
    func reconnectIfNeeded() {}
}

// MARK: - WebSocket envelope

/// Standard wrapper our backend uses for socket ACK responses.
struct WsEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
    let error: String?
    let code: String?
    let status: Int?
}

// MARK: - Errors

enum RecipeDataError: LocalizedError {
    case invalidRecipeId
    case transportNotConfigured
    case serverError(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidRecipeId:
            return "Nieprawidłowe ID przepisu."
        case .transportNotConfigured:
            return "Transport WebSocket nie jest jeszcze skonfigurowany."
        case let .serverError(message):
            return message
        }
    }
}
