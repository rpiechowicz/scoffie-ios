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

    /// `catalog:snapshot` — publiczny katalog stronami (backend Etap 4A).
    /// `revision` = znacznik z PIERWSZEJ strony tego przebiegu (nil na pierwszej).
    func fetchCatalogSnapshot(revision: String?, cursor: String?, limit: Int) async throws -> BackendCatalogSnapshotPageDTO {
        var payload: [String: Any] = ["userId": userId, "limit": limit]
        if let revision { payload["revision"] = revision }
        if let cursor { payload["cursor"] = cursor }
        let envelope: WsEnvelope<BackendCatalogSnapshotPageDTO> = try await socket.emitWithAck(
            event: "catalog:snapshot",
            payload: payload,
            as: WsEnvelope<BackendCatalogSnapshotPageDTO>.self
        )
        if envelope.ok, let data = envelope.data {
            return data
        }
        throw envelope.failure(fallback: "Nieznany błąd catalog:snapshot.")
    }

    /// `catalog:changes` — zmiany od rewizji klienta (backend Etap 4A).
    func fetchCatalogChanges(sinceRevision: String, untilRevision: String?, cursor: String?, limit: Int) async throws -> BackendCatalogChangesPageDTO {
        var payload: [String: Any] = [
            "userId": userId,
            "sinceRevision": sinceRevision,
            "limit": limit
        ]
        if let untilRevision { payload["untilRevision"] = untilRevision }
        if let cursor { payload["cursor"] = cursor }
        let envelope: WsEnvelope<BackendCatalogChangesPageDTO> = try await socket.emitWithAck(
            event: "catalog:changes",
            payload: payload,
            as: WsEnvelope<BackendCatalogChangesPageDTO>.self
        )
        if envelope.ok, let data = envelope.data {
            return data
        }
        throw envelope.failure(fallback: "Nieznany błąd catalog:changes.")
    }

    /// `recipes:householdState` — przepisy gospodarstwa i ulubione.
    func fetchHouseholdRecipeState() async throws -> BackendHouseholdRecipeStateDTO {
        guard let householdId, !householdId.isEmpty else {
            throw RecipeDataError.serverError(message: "Brak gospodarstwa do odczytu przepisów domu.")
        }
        let envelope: WsEnvelope<BackendHouseholdRecipeStateDTO> = try await socket.emitWithAck(
            event: "recipes:householdState",
            payload: ["userId": userId, "householdId": householdId],
            as: WsEnvelope<BackendHouseholdRecipeStateDTO>.self
        )
        if envelope.ok, let data = envelope.data {
            return data
        }
        throw envelope.failure(fallback: "Nieznany błąd recipes:householdState.")
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

    /// `recipes:changed` — od Fazy 1 przepis gospodarstwa potrafi zmienić się
    /// bez udziału tego telefonu: edytuje go domownik albo asystent AI.
    func observeRecipeChanges(_ onChange: @escaping () -> Void) {
        socket.off(event: "recipes:changed")
        socket.on(event: "recipes:changed") { [weak self] items in
            guard let self else { return }
            guard let first = items.first,
                  JSONSerialization.isValidJSONObject(first),
                  let data = try? JSONSerialization.data(withJSONObject: first),
                  let event = try? JSONDecoder().decode(BackendRecipeChangedDTO.self, from: data)
            else { return }

            if let householdId = self.householdId, event.householdId != householdId {
                return
            }
            onChange()
        }
    }

    func observeRealtimeReconnect(_ onReconnect: @escaping () -> Void) {
        socket.observeConnection { isConnected in
            guard isConnected else { return }
            onReconnect()
        }
    }

    // MARK: - Udostępnianie
    //
    // Płaski ładunek jak `recipes:householdState`: serwer bierze tożsamość
    // z socketu, a `householdId` sprawdza członkostwem — cudzy dom to
    // `NOT_HOUSEHOLD_MEMBER`, cudzy przepis bez tokenu `RECIPE_NOT_FOUND`.

    func createShareLink(recipeId: String) async throws -> BackendRecipeShareLinkDTO {
        try await emitHouseholdEvent(
            "recipes:shareLink",
            fields: ["recipeId": recipeId],
            as: BackendRecipeShareLinkDTO.self
        )
    }

    func revokeShareLink(recipeId: String) async throws -> BackendRecipeRevokeShareDTO {
        try await emitHouseholdEvent(
            "recipes:revokeShare",
            fields: ["recipeId": recipeId],
            as: BackendRecipeRevokeShareDTO.self
        )
    }

    func markRecipeShared(recipeId: String) async throws {
        _ = try await emitHouseholdEvent(
            "recipes:shared",
            fields: ["recipeId": recipeId],
            as: BackendRecipeSharedAckDTO.self
        )
    }

    func openSharedRecipe(slug: String?, token: String?) async throws -> BackendOpenSharedRecipeDTO {
        var fields: [String: Any] = [:]
        if let token {
            fields["token"] = token
        } else if let slug {
            fields["slug"] = slug
        }
        return try await emitHouseholdEvent(
            "recipes:openShared",
            fields: fields,
            as: BackendOpenSharedRecipeDTO.self
        )
    }

    func saveSharedRecipe(token: String) async throws -> BackendSaveSharedRecipeDTO {
        try await emitHouseholdEvent(
            "recipes:saveShared",
            fields: ["token": token],
            as: BackendSaveSharedRecipeDTO.self
        )
    }

    /// Scenariusz trybu Gotuj — bramka członkostwa po stronie serwera, więc
    /// zdarzenie domu (`householdId` obowiązkowe).
    func fetchCookScenario(recipeId: String) async throws -> CookScenarioResponse {
        try await emitHouseholdEvent(
            "recipes:cookScenario",
            fields: ["recipeId": recipeId],
            as: CookScenarioResponse.self
        )
    }

    /// Ocena gotowania — zdarzenie domu, jak scenariusz (bramka członkostwa).
    func sendCookFeedback(data: [String: Any]) async throws -> CookFeedbackAck {
        try await emitHouseholdEvent(
            "recipes:cookFeedback",
            fields: ["data": data],
            as: CookFeedbackAck.self
        )
    }

    /// Zdarzenie gospodarstwa: `userId` + `householdId` + pola zdarzenia,
    /// odpowiedź z koperty albo błąd z jej kodem.
    private func emitHouseholdEvent<T: Decodable>(
        _ event: String,
        fields: [String: Any],
        as type: T.Type
    ) async throws -> T {
        guard let householdId, !householdId.isEmpty else {
            throw RecipeDataError.serverError(message: "Brak gospodarstwa dla \(event).")
        }
        var payload = fields
        payload["userId"] = userId
        payload["householdId"] = householdId
        let envelope: WsEnvelope<T> = try await socket.emitWithAck(
            event: event,
            payload: payload,
            as: WsEnvelope<T>.self
        )
        if envelope.ok, let data = envelope.data {
            return data
        }
        throw envelope.failure(fallback: "Nieznany błąd \(event).")
    }
}

// MARK: - Internal DTO (only used by the transport client above)

private struct BackendRecipeChangedDTO: Codable {
    let householdId: String
    let recipeId: String
    /// `CREATED` (kopia z „Zapisz u siebie”), `UPDATED` (także nowy albo
    /// wyłączony link) albo `DELETED` — nie rozróżniamy: każda, również
    /// nieznana, kończy się przeładowaniem stanu domu. Dlatego `String`,
    /// a nie wyliczenie — nowa wartość z serwera nie może zgubić zdarzenia.
    let action: String
    let changedByUserId: String?
}

private struct BackendFavoritesChangedDTO: Codable {
    let householdId: String
    let recipeId: String
    let isFavorite: Bool
    let changedByUserId: String?
}
