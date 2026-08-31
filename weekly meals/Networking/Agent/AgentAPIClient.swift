import Foundation

/// Klient REST asystenta AI (`/agent/*` w backendzie).
///
/// Cała domena jedzie u nas socketem — asystent nie, i to jest świadome po
/// obu stronach: tura trwa dziesiątki sekund i musi przeżyć telefon
/// wchodzący w tło, a ack Socket.IO wygasa po kilku sekundach. Serwer
/// przyjmuje wiadomość (`202`), oddaje identyfikator tury, a my odpytujemy
/// `GET /agent/turns/:id`, aż tura się domknie.
///
/// Uwierzytelnienie i obsługa `401` jak w `IntegrationsAPIClient`: token
/// z Keychain czytany PER ŻĄDANIE (wylogowanie unieważnia klienta bez
/// sprzątania), pierwszy `401` uruchamia jednorazowe odświeżenie sesji
/// i ponowienie, drugi wraca do wywołującego.
final class AgentAPIClient {
    private let baseURL: URL
    private let tokenProvider: () -> String?
    /// `true` = para tokenów odświeżona, można ponowić żądanie.
    private let refreshSession: (() async -> Bool)?

    init(
        baseURL: URL,
        tokenProvider: @escaping () -> String?,
        refreshSession: (() async -> Bool)? = nil
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.refreshSession = refreshSession
    }

    func createConversation(householdId: String) async throws -> AgentConversationDTO {
        try await perform(
            path: "agent/conversations",
            method: "POST",
            bodyData: try JSONEncoder().encode(
                AgentCreateConversationRequestDTO(householdId: householdId)
            )
        )
    }

    func listConversations() async throws -> [AgentConversationDTO] {
        try await perform(path: "agent/conversations", method: "GET", bodyData: nil)
    }

    /// Historia rozmowy. `after` to kursor po id ostatniej pokazanej
    /// wiadomości — dwie wiadomości tej samej tury potrafią mieć identyczny
    /// znacznik czasu, więc kursor po czasie gubiłby jedną z nich.
    func messages(conversationId: String, after: String? = nil) async throws -> [AgentMessageDTO] {
        let response: AgentMessagesResponseDTO = try await perform(
            path: "agent/conversations/\(conversationId)/messages",
            method: "GET",
            bodyData: nil,
            query: after.map { [URLQueryItem(name: "after", value: $0)] } ?? []
        )
        return response.messages
    }

    func postMessage(
        conversationId: String,
        request: AgentPostMessageRequestDTO
    ) async throws -> AgentAcceptedTurnDTO {
        try await perform(
            path: "agent/conversations/\(conversationId)/messages",
            method: "POST",
            bodyData: try JSONEncoder().encode(request)
        )
    }

    func turn(id: String) async throws -> AgentTurnDTO {
        try await perform(path: "agent/turns/\(id)", method: "GET", bodyData: nil)
    }

    /// Kasuje JEDNĄ rozmowę — porządki na liście, nie RODO.
    @discardableResult
    func deleteConversation(id: String) async throws -> Int {
        struct DeletedDTO: Decodable { let deleted: Int }
        let response: DeletedDTO = try await perform(
            path: "agent/conversations/\(id)",
            method: "DELETE",
            bodyData: nil
        )
        return response.deleted
    }

    /// Co asystent pamięta o gospodarstwie — pamięć jest wspólna dla domu.
    func memory(householdId: String) async throws -> [AgentMemoryNoteDTO] {
        try await perform(
            path: "agent/memory",
            method: "GET",
            bodyData: nil,
            query: [URLQueryItem(name: "householdId", value: householdId)]
        )
    }

    func forgetMemory(noteId: String) async throws {
        struct EmptyDTO: Decodable {}
        let _: EmptyDTO = try await perform(
            path: "agent/memory/\(noteId)",
            method: "DELETE",
            bodyData: nil
        )
    }

    /// „Usuń moje rozmowy z asystentem" (RODO). Działa też przy wyłączonym
    /// asystencie — dlatego nie chowamy tej akcji za flagą dostępności.
    @discardableResult
    func deleteAllConversations() async throws -> Int {
        struct DeletedDTO: Decodable { let deleted: Int }
        let response: DeletedDTO = try await perform(
            path: "agent/conversations",
            method: "DELETE",
            bodyData: nil
        )
        return response.deleted
    }

    // MARK: - Rdzeń

    private func perform<Response: Decodable>(
        path: String,
        method: String,
        bodyData: Data?,
        query: [URLQueryItem] = [],
        isRetryAfterRefresh: Bool = false
    ) async throws -> Response {
        guard let token = tokenProvider(), !token.isEmpty else {
            throw BackendAPIError.notAuthenticated
        }

        // Kursor idzie przez `URLComponents`, a nie doklejony do ścieżki:
        // `appendingPathComponent` zakodowałoby „?" jako część nazwy zasobu
        // i serwer dostałby ścieżkę, której nie ma.
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else {
            throw BackendAPIError.network
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }
        // Odpytywanie tury jest krótkie; sama wysyłka wiadomości też — czekanie
        // na odpowiedź modelu dzieje się PO stronie serwera, nie w tym żądaniu.
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BackendAPIError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw BackendAPIError.network
        }

        if http.statusCode == 401, !isRetryAfterRefresh, let refreshSession {
            if await refreshSession() {
                return try await perform(
                    path: path,
                    method: method,
                    bodyData: bodyData,
                    query: query,
                    isRetryAfterRefresh: true
                )
            }
        }

        guard (200...299).contains(http.statusCode) else {
            let decoded = try? JSONDecoder().decode(BackendHttpErrorDTO.self, from: data)
            let code = decoded?.code
                ?? (http.statusCode == 401 ? "UNAUTHORIZED" : "HTTP_ERROR")
            throw BackendAPIError.backend(
                code: code,
                status: http.statusCode,
                message: decoded?.message
            )
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }
}
