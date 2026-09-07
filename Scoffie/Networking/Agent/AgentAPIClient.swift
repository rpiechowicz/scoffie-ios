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

    /// Jedna rozmowa z `activeTurnId` — po powrocie do rozmowy w trakcie tury
    /// telefon wie, którą turę dalej odpytywać, bez pobierania całej listy.
    func conversation(id: String) async throws -> AgentConversationDTO {
        try await perform(path: "agent/conversations/\(id)", method: "GET", bodyData: nil)
    }

    /// „Ile mi zostało" — do ekranu limitów; działa też przy wyłączonym asystencie.
    func usage(householdId: String) async throws -> AgentUsageDTO {
        try await perform(
            path: "agent/usage",
            method: "GET",
            bodyData: nil,
            query: [URLQueryItem(name: "householdId", value: householdId)]
        )
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

    /// Poprawienie pytania — nowa tura zamiast zmiany tekstu w miejscu.
    ///
    /// Serwer wycofuje poprawianą wiadomość i wszystko, co po niej, więc po
    /// tym wywołaniu historia w telefonie jest nieaktualna od tego miejsca
    /// w dół.
    func editMessage(
        conversationId: String,
        request: AgentEditMessageRequestDTO
    ) async throws -> AgentAcceptedTurnDTO {
        try await perform(
            path: "agent/conversations/\(conversationId)/messages/edit",
            method: "POST",
            bodyData: try JSONEncoder().encode(request)
        )
    }

    func turn(id: String) async throws -> AgentTurnDTO {
        try await perform(path: "agent/turns/\(id)", method: "GET", bodyData: nil)
    }

    /// „Stop" — przerwanie biegnącej tury. Serwer domyka ją jako
    /// `AI_CANCELLED` i oddaje kwotę; odpowiedź niesie już stan końcowy.
    /// Idempotentne: tura domknięta wraca bez zmian.
    func cancelTurn(id: String) async throws -> AgentTurnDTO {
        try await perform(path: "agent/turns/\(id)/cancel", method: "POST", bodyData: nil)
    }

    /// Zatwierdzenie propozycji — jedyny moment, w którym asystent zmienia plan.
    ///
    /// Bez udziału modelu, czyli bez kosztu: klient odsyła sam `proposalId`,
    /// a serwer ma u siebie stan docelowy policzony w turze. Ponowne kliknięcie
    /// oddaje ten sam wynik, nie drugi zapis — więc podwójne dotknięcie
    /// przycisku nie jest sytuacją wyjątkową i nie trzeba go blokować na siłę.
    func applyProposal(id: String, force: Bool = false) async throws -> AgentProposalActionResultDTO {
        // Ciało tylko przy `force`: starszy serwer bez ciała odpowiada jak
        // dotąd, a z pustym obiektem też — więc nic nie tracimy.
        let body = force
            ? try JSONEncoder().encode(AgentApplyProposalRequestDTO(force: true))
            : nil
        return try await perform(path: "agent/proposals/\(id)/apply", method: "POST", bodyData: body)
    }

    /// „Zgłoś odpowiedź" — `POST /agent/messages/:id/report`. Serwer zapisuje
    /// treść zgłoszonej odpowiedzi razem z powodem; przyjmuje także, gdy
    /// asystent jest akurat wyłączony.
    func reportMessage(id: String, reason: String, comment: String?) async throws {
        struct ReportRequestDTO: Encodable {
            let reason: String
            let comment: String?
        }
        struct ReportResponseDTO: Decodable {
            let id: String?
        }
        let body = try JSONEncoder().encode(ReportRequestDTO(reason: reason, comment: comment))
        let _: ReportResponseDTO = try await perform(
            path: "agent/messages/\(id)/report",
            method: "POST",
            bodyData: body
        )
    }

    /// Cofnięcie zapisu. Serwer odmówi, jeśli ktoś w domu ruszył plan PO
    /// zatwierdzeniu — cofnięcie nie ma prawa skasować cudzej zmiany.
    func undoProposal(id: String) async throws -> AgentProposalActionResultDTO {
        try await perform(path: "agent/proposals/\(id)/undo", method: "POST", bodyData: nil)
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

    @discardableResult
    func forgetMemory(noteId: String) async throws -> Int {
        // Serwer oddaje `{deleted}` — pusta odpowiedź wywróciłaby dekoder.
        struct DeletedDTO: Decodable { let deleted: Int }
        let response: DeletedDTO = try await perform(
            path: "agent/memory/\(noteId)",
            method: "DELETE",
            bodyData: nil
        )
        return response.deleted
    }

    /// „Usuń wszystkie notatki" z ekranu pamięci — notatki są wspólne dla
    /// domu, więc kasuje je każdy domownik, tak jak może skasować pojedynczo.
    @discardableResult
    func forgetAllMemory(householdId: String) async throws -> Int {
        struct DeletedDTO: Decodable { let deleted: Int }
        let response: DeletedDTO = try await perform(
            path: "agent/memory",
            method: "DELETE",
            bodyData: nil,
            query: [URLQueryItem(name: "householdId", value: householdId)]
        )
        return response.deleted
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
