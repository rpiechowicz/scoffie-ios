import Foundation

/// Para tokenów z `POST /auth/refresh`.
struct TokenPairDTO: Decodable {
    let accessToken: String
    let refreshToken: String
}

enum AuthAPIError: Error, Equatable {
    /// Refresh token odrzucony (unieważniony, wygasły, replay, konto usunięte)
    /// — sesji nie da się uratować, trzeba się zalogować ponownie.
    case unauthorized
    /// Nie doszło do odpowiedzi HTTP (offline, timeout) — sesja może żyć dalej.
    case network
    case http(Int)
}

/// Klient tras `/auth/*`, które nie wymagają nagłówka `Authorization`
/// (obie przyjmują refresh token w body).
///
/// Od Fazy 0 access token żyje krócej niż refresh (30 d vs 60 d), a refresh
/// jest jednorazowy z wykrywaniem ponownego użycia: replay starego tokenu
/// unieważnia całą rodzinę. Stąd `SessionStore.refreshSessionTokens()` jest
/// single-flight — dwa równoległe odświeżenia tym samym tokenem wylogowałyby
/// użytkownika.
final class AuthAPIClient: Sendable {
    private let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func refresh(refreshToken: String) async throws -> TokenPairDTO {
        try await post(path: "auth/refresh", body: ["refreshToken": refreshToken])
    }

    /// Best-effort przy wylogowaniu: unieważnia refresh token po stronie
    /// serwera. Serwer zawsze odpowiada 200 (`{revoked: Bool}`).
    func logout(refreshToken: String) async throws {
        struct LogoutResponse: Decodable { let revoked: Bool }
        let _: LogoutResponse = try await post(path: "auth/logout", body: ["refreshToken": refreshToken])
    }

    private func post<Response: Decodable>(path: String, body: [String: String]) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthAPIError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthAPIError.network
        }
        if http.statusCode == 401 {
            throw AuthAPIError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw AuthAPIError.http(http.statusCode)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
