import Foundation

/// Translates between domain-shaped Repository calls and the raw socket layer
/// for the `weeklyPlans:*ShoppingList*` event family.
///
/// Owns household-id resolution: if the caller didn't pass one in, we try to
/// match `preferredHouseholdName` against `households:findAll`, falling back
/// to the first household. Result is cached behind a lock.
final class WebSocketShoppingListTransportClient: ShoppingListTransportClient {
    private let socket: RecipeSocketClient
    private let userId: String
    private let householdId: String?
    private let preferredHouseholdName: String?
    private var resolvedHouseholdId: String?
    private let stateLock = NSLock()

    init(
        socket: RecipeSocketClient,
        userId: String,
        householdId: String? = nil,
        preferredHouseholdName: String? = "Home"
    ) {
        self.socket = socket
        self.userId = userId
        self.householdId = householdId
        self.preferredHouseholdName = preferredHouseholdName
    }

    private func makePayload<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoded = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: encoded, options: [])
        guard let dictionary = object as? [String: Any] else {
            throw RecipeDataError.serverError(message: "Nie udało się zbudować payloadu JSON.")
        }
        return dictionary
    }

    private func resolveHouseholdId() async throws -> String {
        stateLock.lock()
        let currentResolved = resolvedHouseholdId
        stateLock.unlock()

        if let currentResolved {
            return currentResolved
        }
        if let householdId, !householdId.isEmpty {
            stateLock.lock()
            resolvedHouseholdId = householdId
            stateLock.unlock()
            return householdId
        }

        let payload = try makePayload(HouseholdListPayload(userId: userId))
        let envelope: WsEnvelope<[BackendHouseholdDTO]> = try await socket.emitWithAck(
            event: "households:findAll",
            payload: payload,
            as: WsEnvelope<[BackendHouseholdDTO]>.self
        )

        guard envelope.ok, let households = envelope.data else {
            throw envelope.failure(fallback: "Nie udało się pobrać gospodarstw.")
        }

        if let preferredHouseholdName,
           let matched = households.first(where: { $0.name.lowercased() == preferredHouseholdName.lowercased() }) {
            stateLock.lock()
            resolvedHouseholdId = matched.id
            stateLock.unlock()
            return matched.id
        }

        guard let first = households.first else {
            throw RecipeDataError.serverError(message: "Brak gospodarstwa dla użytkownika.")
        }
        stateLock.lock()
        resolvedHouseholdId = first.id
        stateLock.unlock()
        return first.id
    }

    func fetchShoppingListState(weekStart: String) async throws -> BackendShoppingListStateDTO {
        let householdId = try await resolveHouseholdId()
        let payload = try makePayload(
            ShoppingListPayload(
                userId: userId,
                householdId: householdId,
                weekStart: weekStart
            )
        )
        let envelope: WsEnvelope<BackendShoppingListStateDTO> = try await socket.emitWithAck(
            event: "weeklyPlans:getShoppingListState",
            payload: payload,
            as: WsEnvelope<BackendShoppingListStateDTO>.self
        )

        if envelope.ok, let data = envelope.data {
            return data
        }
        throw envelope.failure(fallback: "Nieznany błąd weeklyPlans:getShoppingListState.")
    }

    func setChecked(weekStart: String, productKey: String, isChecked: Bool) async throws {
        let householdId = try await resolveHouseholdId()
        let payload = try makePayload(
            SetCheckedPayload(
                userId: userId,
                householdId: householdId,
                weekStart: weekStart,
                data: SetCheckedDataPayload(
                    productKey: productKey,
                    isChecked: isChecked
                )
            )
        )
        let envelope: WsEnvelope<BackendShoppingItemCheckDTO> = try await socket.emitWithAck(
            event: "weeklyPlans:setShoppingItemChecked",
            payload: payload,
            as: WsEnvelope<BackendShoppingItemCheckDTO>.self
        )

        if envelope.ok {
            return
        }
        throw envelope.failure(fallback: "Nieznany błąd weeklyPlans:setShoppingItemChecked.")
    }

    func archiveShoppingList(weekStart: String, weekLabel: String) async throws {
        let householdId = try await resolveHouseholdId()
        let payload = try makePayload(
            ArchiveShoppingListPayload(
                userId: userId,
                householdId: householdId,
                weekStart: weekStart,
                weekLabel: weekLabel
            )
        )
        let envelope: WsEnvelope<BackendMutationResultDTO> = try await socket.emitWithAck(
            event: "weeklyPlans:archiveShoppingList",
            payload: payload,
            as: WsEnvelope<BackendMutationResultDTO>.self
        )

        if envelope.ok {
            return
        }
        throw envelope.failure(fallback: "Nieznany błąd weeklyPlans:archiveShoppingList.")
    }

    func deleteArchivedList(archiveId: String) async throws {
        let householdId = try await resolveHouseholdId()
        let payload = try makePayload(
            ArchiveSelectionPayload(
                userId: userId,
                householdId: householdId,
                archiveId: archiveId
            )
        )
        let envelope: WsEnvelope<BackendMutationResultDTO> = try await socket.emitWithAck(
            event: "weeklyPlans:deleteShoppingListArchive",
            payload: payload,
            as: WsEnvelope<BackendMutationResultDTO>.self
        )

        if envelope.ok {
            return
        }
        throw envelope.failure(fallback: "Nieznany błąd weeklyPlans:deleteShoppingListArchive.")
    }

    func deleteAllArchivedLists(weekStart: String) async throws {
        let householdId = try await resolveHouseholdId()
        let payload = try makePayload(
            DeleteAllArchivedListsPayload(
                userId: userId,
                householdId: householdId,
                weekStart: weekStart
            )
        )
        let envelope: WsEnvelope<BackendMutationResultDTO> = try await socket.emitWithAck(
            event: "weeklyPlans:deleteAllShoppingListArchives",
            payload: payload,
            as: WsEnvelope<BackendMutationResultDTO>.self
        )

        if envelope.ok {
            return
        }
        throw envelope.failure(fallback: "Nieznany błąd weeklyPlans:deleteAllShoppingListArchives.")
    }

    func observeShoppingListChanges(_ onChange: @escaping (_ event: BackendShoppingListChangedDTO) -> Void) {
        socket.off(event: "weeklyPlans:shoppingListChanged")
        socket.on(event: "weeklyPlans:shoppingListChanged") { [weak self] items in
            guard let self else { return }
            guard let first = items.first,
                  JSONSerialization.isValidJSONObject(first),
                  let data = try? JSONSerialization.data(withJSONObject: first),
                  let event = try? JSONDecoder().decode(BackendShoppingListChangedDTO.self, from: data)
            else { return }

            self.stateLock.lock()
            let cachedHouseholdId = self.resolvedHouseholdId
            self.stateLock.unlock()
            let expectedHouseholdId = cachedHouseholdId ?? self.householdId
            if let expectedHouseholdId, event.householdId != expectedHouseholdId {
                return
            }

            onChange(event)
        }
    }

    func observeRealtimeReconnect(_ onReconnect: @escaping () -> Void) {
        socket.observeConnection { isConnected in
            guard isConnected else { return }
            onReconnect()
        }
    }
}

// MARK: - Internal request payloads (only used by the transport client above)

private struct ArchiveShoppingListPayload: Encodable {
    let userId: String
    let householdId: String
    let weekStart: String
    let weekLabel: String
}

private struct ArchiveSelectionPayload: Encodable {
    let userId: String
    let householdId: String
    let archiveId: String
}

private struct DeleteAllArchivedListsPayload: Encodable {
    let userId: String
    let householdId: String
    let weekStart: String
}

private struct HouseholdListPayload: Encodable {
    let userId: String
}

private struct ShoppingListPayload: Encodable {
    let userId: String
    let householdId: String
    let weekStart: String
}

private struct SetCheckedDataPayload: Encodable {
    let productKey: String
    let isChecked: Bool
}

private struct SetCheckedPayload: Encodable {
    let userId: String
    let householdId: String
    let weekStart: String
    let data: SetCheckedDataPayload
}
