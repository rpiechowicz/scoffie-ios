import Foundation

/// Translates between domain-shaped Repository calls and the raw socket layer
/// by emitting/awaiting the actual `recipes:*` events with their backend DTOs.
final class WebSocketRecipeTransportClient: RecipeTransportClient {
    private let socket: RecipeSocketClient
    private let userId: String
    private let householdId: String?

    init(socket: RecipeSocketClient, userId: String, householdId: String? = nil) {
        self.socket = socket
        self.userId = userId
        self.householdId = householdId
    }

    func fetchRecipes(page: Int, limit: Int) async throws -> [BackendRecipeDTO] {
        var payload: [String: Any] = [
            "userId": userId,
            "filters": [
                "page": page,
                "limit": limit
            ]
        ]
        if let householdId, var filters = payload["filters"] as? [String: Any] {
            filters["householdId"] = householdId
            payload["filters"] = filters
        }

        let envelope: WsEnvelope<[BackendRecipeDTO]> = try await socket.emitWithAck(
            event: "recipes:findAll",
            payload: payload,
            as: WsEnvelope<[BackendRecipeDTO]>.self
        )
        if envelope.ok, let data = envelope.data {
            return data
        }
        throw envelope.failure(fallback: "Nieznany błąd recipes:findAll.")
    }

    func fetchRecipeById(recipeId: String) async throws -> BackendRecipeDTO {
        var payload: [String: Any] = [
            "userId": userId,
            "id": recipeId
        ]
        if let householdId {
            payload["householdId"] = householdId
        }

        let envelope: WsEnvelope<BackendRecipeDTO> = try await socket.emitWithAck(
            event: "recipes:findById",
            payload: payload,
            as: WsEnvelope<BackendRecipeDTO>.self
        )
        if envelope.ok, let data = envelope.data {
            return data
        }
        throw envelope.failure(fallback: "Nieznany błąd recipes:findById.")
    }

    func setFavorite(recipeId: String, isFavorite: Bool) async throws {
        guard let householdId, !householdId.isEmpty else {
            throw RecipeDataError.serverError(message: "Brak gospodarstwa do zapisu ulubionych.")
        }
        let envelope: WsEnvelope<BackendRecipeDTO> = try await socket.emitWithAck(
            event: "recipes:setFavorite",
            payload: [
                "userId": userId,
                "data": [
                    "recipeId": recipeId,
                    "householdId": householdId,
                    "isFavorite": isFavorite
                ]
            ],
            as: WsEnvelope<BackendRecipeDTO>.self
        )
        if envelope.ok {
            return
        }
        throw envelope.failure(fallback: "Nieznany błąd recipes:setFavorite.")
    }

    func observeFavoritesChanges(_ onChange: @escaping (_ recipeId: String, _ isFavorite: Bool) -> Void) {
        socket.off(event: "recipes:favoritesChanged")
        socket.on(event: "recipes:favoritesChanged") { [weak self] items in
            guard let self else { return }
            guard let first = items.first,
                  JSONSerialization.isValidJSONObject(first),
                  let data = try? JSONSerialization.data(withJSONObject: first),
                  let event = try? JSONDecoder().decode(BackendFavoritesChangedDTO.self, from: data)
            else { return }

            if let householdId = self.householdId, event.householdId != householdId {
                return
            }
            onChange(event.recipeId, event.isFavorite)
        }
    }

    func observeRealtimeReconnect(_ onReconnect: @escaping () -> Void) {
        socket.observeConnection { isConnected in
            guard isConnected else { return }
            onReconnect()
        }
    }
}

// MARK: - Internal DTO (only used by the transport client above)

private struct BackendFavoritesChangedDTO: Codable {
    let householdId: String
    let recipeId: String
    let isFavorite: Bool
    let changedByUserId: String?
}
