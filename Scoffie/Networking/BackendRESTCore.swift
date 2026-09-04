import Foundation

/// Wspólny rdzeń uwierzytelnionych wywołań REST — trzeci klient (zgody,
/// eksport danych) nie kopiuje już po raz kolejny tej samej pętli „token z
/// Keychain, jedno odświeżenie po 401, błąd w kształcie `{code, message}`".
///
/// `IntegrationsAPIClient` i `AgentAPIClient` mają własne kopie z czasów,
/// gdy były jedyne — celowo nietknięte (działają i są przetestowane ręcznie);
/// nowe klienty budują się na tym rdzeniu.
final class BackendRESTCore {
    private let baseURL: URL
    private let tokenProvider: () -> String?
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

    func request<Response: Decodable>(path: String, method: String) async throws -> Response {
        let data = try await perform(path: path, method: method, bodyData: nil)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        let data = try await perform(path: path, method: method, bodyData: JSONEncoder().encode(body))
        return try JSONDecoder().decode(Response.self, from: data)
    }

    /// Surowe bajty odpowiedzi — dla plików (eksport danych), które nie mają
    /// stałego kształtu do zdekodowania.
    func raw(path: String, method: String = "GET") async throws -> Data {
        try await perform(path: path, method: method, bodyData: nil)
    }

    private func perform(
        path: String,
        method: String,
        bodyData: Data?,
        isRetryAfterRefresh: Bool = false
    ) async throws -> Data {
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
        return data
    }
}
