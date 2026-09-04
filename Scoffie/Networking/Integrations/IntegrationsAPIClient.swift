import Foundation

/// Błąd uwierzytelnionego wywołania REST, już po przetłumaczeniu na kod
/// backendu (`AppErrorCode` z `app-error-code.ts`).
///
/// Nazwa mówiła kiedyś „integracje", bo to był jedyny taki klient. Od
/// asystenta AI (`AgentAPIClient`) jest ich dwa i kształt błędu jest ten sam
/// dla każdego uwierzytelnionego zasobu — stąd nazwa bez nazwy funkcji.
enum BackendAPIError: Error, Equatable {
    /// Brak access tokenu w Keychain — sesja nie istnieje.
    case notAuthenticated
    /// Backend odpowiedział błędem aplikacyjnym (`{code, message, requestId}`).
    case backend(code: String, status: Int, message: String?)
    /// Nie doszło do odpowiedzi HTTP (offline, timeout, DNS).
    case network
}

/// Pierwszy uwierzytelniony klient REST w aplikacji.
///
/// Poświadczenia Cookidoo i kroki wymagają prawdziwej autoryzacji — token
/// z Keychain idzie w `Authorization: Bearer`, a tożsamość ustala serwer z JWT.
/// Celowo feature-scoped (nie „wielki generyczny klient"): jak dojdą kolejne
/// uwierzytelnione zasoby, wtedy będzie z czego uogólniać.
///
/// Od Fazy 0 pierwszy 401 uruchamia jednorazowe odświeżenie sesji
/// (`refreshSession`, single-flight w `SessionStore`) i ponowienie żądania;
/// drugi 401 wraca do wywołującego jako `UNAUTHORIZED`.
final class IntegrationsAPIClient {
    private let baseURL: URL
    /// Token czytany per żądanie, nie trzymany — Keychain jest źródłem prawdy
    /// i wylogowanie unieważnia klienta bez dodatkowego sprzątania.
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

    func fetchStatus() async throws -> CookidooStatusDTO {
        try await request(path: "integrations/cookidoo/status", method: "GET")
    }

    func connect(email: String, password: String) async throws -> CookidooConnectResponseDTO {
        try await request(
            path: "integrations/cookidoo/connect",
            method: "POST",
            body: CookidooConnectRequestDTO(email: email, password: password)
        )
    }

    func disconnect() async throws {
        struct DisconnectResponse: Decodable { let connected: Bool }
        let _: DisconnectResponse = try await request(
            path: "integrations/cookidoo",
            method: "DELETE"
        )
    }

    func sendToWeek(recipeId: String, date: String) async throws -> CookidooSendToWeekResponseDTO {
        try await request(
            path: "integrations/cookidoo/send-to-week",
            method: "POST",
            body: CookidooSendToWeekRequestDTO(recipeId: recipeId, date: date)
        )
    }

    /// PUT, nie POST — idempotentny zapis kroczącego okna dziennych kroków;
    /// ta sama paczka wysłana dwa razy zostawia bazę w identycznym stanie.
    func syncHealthSteps(entries: [HealthStepsEntryDTO]) async throws -> HealthStepsSyncResponseDTO {
        try await request(
            path: "integrations/health/steps",
            method: "PUT",
            body: HealthStepsSyncRequestDTO(entries: entries)
        )
    }

    /// Wyłączenie synchronizacji kasuje kopię kroków na serwerze (polityka §7).
    func deleteHealthSteps() async throws {
        struct DeletedResponse: Decodable { let deleted: Int? }
        let _: DeletedResponse = try await request(
            path: "integrations/health/steps",
            method: "DELETE"
        )
    }

    // MARK: - Rdzeń

    private func request<Response: Decodable>(
        path: String,
        method: String
    ) async throws -> Response {
        try await perform(path: path, method: method, bodyData: nil)
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        try await perform(path: path, method: method, bodyData: JSONEncoder().encode(body))
    }

    private func perform<Response: Decodable>(
        path: String,
        method: String,
        bodyData: Data?,
        isRetryAfterRefresh: Bool = false
    ) async throws -> Response {
        guard let token = tokenProvider(), !token.isEmpty else {
            throw BackendAPIError.notAuthenticated
        }

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }
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
