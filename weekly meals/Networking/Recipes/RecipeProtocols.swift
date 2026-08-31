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
    /// Serwer odmówił uwierzytelnienia socketu (`connect_error` z kodem
    /// `UNAUTHORIZED` albo `auth:expired` w trakcie sesji). `reason`:
    /// `missing` / `invalid` / `expired` / `user_gone`. Klient sam zatrzymuje
    /// auto-reconnect — bez tego stary token biłby w serwer co 1–5 s bez końca.
    func observeAuthFailure(_ handler: @escaping (_ reason: String) -> Void)
    /// Połącz ponownie z AKTUALNYM tokenem z `tokenProvider` — po udanym
    /// `POST /auth/refresh`. Biblioteka przy własnym reconnect wysyła token
    /// zapamiętany przy pierwszym `connect`, więc świeży trzeba podać jawnie.
    func reconnectWithFreshToken()
    /// Zamknij połączenie na dobre (wylogowanie) — także auto-reconnect.
    func disconnect()
}

extension RecipeSocketClient {
    func reconnectIfNeeded() {}
    func observeAuthFailure(_ handler: @escaping (_ reason: String) -> Void) {}
    func reconnectWithFreshToken() {}
    func disconnect() {}
}

// MARK: - WebSocket envelope

/// Standard wrapper our backend uses for socket ACK responses.
///
/// Od plastra C koperta błędu niesie też `message` (== `error`), `details`
/// i `requestId`. Pola dekodujemy pobłażliwie: obcy kształt któregokolwiek
/// z nich nie może położyć całej koperty, bo wtedy udany ack wyglądałby jak
/// błąd transportu.
struct WsEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
    /// Komunikat błędu — pole historyczne; nowy backend wysyła też `message`.
    let error: String?
    let message: String?
    let code: String?
    let status: Int?
    let details: [String]?
    let requestId: String?

    private enum CodingKeys: String, CodingKey {
        case ok, data, error, message, code, status, details, requestId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        data = try container.decodeIfPresent(T.self, forKey: .data)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
        message = try? container.decodeIfPresent(String.self, forKey: .message)
        code = try? container.decodeIfPresent(String.self, forKey: .code)
        status = try? container.decodeIfPresent(Int.self, forKey: .status)
        details = try? container.decodeIfPresent([String].self, forKey: .details)
        requestId = try? container.decodeIfPresent(String.self, forKey: .requestId)
    }

    init(
        ok: Bool,
        data: T? = nil,
        error: String? = nil,
        message: String? = nil,
        code: String? = nil,
        status: Int? = nil,
        details: [String]? = nil,
        requestId: String? = nil
    ) {
        self.ok = ok
        self.data = data
        self.error = error
        self.message = message
        self.code = code
        self.status = status
        self.details = details
        self.requestId = requestId
    }

    /// Błąd dla koperty `ok:false`. Komunikat: `message` (nowy backend),
    /// potem `error` (stary), na końcu `fallback`. Z kodem → `.server`, po
    /// którym decyduje `UserFacingErrorMapper`; bez kodu → błąd transportu.
    func failure(fallback: String) -> RecipeDataError {
        let text = [message, error]
            .compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? fallback
        guard let code, !code.isEmpty else {
            return .serverError(message: text)
        }
        return .server(code: code, message: text, status: status, requestId: requestId)
    }
}

// MARK: - Errors

enum RecipeDataError: LocalizedError {
    case invalidRecipeId
    case transportNotConfigured
    /// Błąd transportu/klienta (brak ACK, martwy socket) albo odpowiedź, której
    /// nie umiemy odczytać. Serwer odmawiający z kodem to `.server`.
    case serverError(message: String)
    /// Odmowa serwera z kodem — po nim decyduje `UserFacingErrorMapper`;
    /// `requestId` pozwala odnaleźć wpis w logu backendu.
    case server(code: String, message: String, status: Int?, requestId: String?)

    var errorDescription: String? {
        switch self {
        case .invalidRecipeId:
            return "Nieprawidłowe ID przepisu."
        case .transportNotConfigured:
            return "Transport WebSocket nie jest jeszcze skonfigurowany."
        case let .serverError(message):
            return message
        case let .server(_, message, _, _):
            return message
        }
    }
}
