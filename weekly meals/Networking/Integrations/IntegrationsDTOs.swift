import Foundation

// DTO-sy REST-owych endpointów `integrations/cookidoo` (NestJS,
// `integrations.controller.ts`). Osobno od DTO-sów socketowych: to jedyna
// część aplikacji, która rozmawia z backendem po HTTP z tokenem — patrz
// `IntegrationsAPIClient`.

struct CookidooStatusDTO: Decodable {
    let connected: Bool
    let login: String?
    let status: String?
    let connectedById: String?
    let lastVerifiedAt: String?
}

struct CookidooSubscriptionDTO: Decodable {
    let active: Bool
    let type: String?
    let expiresAt: String?
}

struct CookidooConnectRequestDTO: Encodable {
    let email: String
    let password: String
}

struct CookidooConnectResponseDTO: Decodable {
    let connected: Bool
    let login: String?
    let status: String?
    let lastVerifiedAt: String?
    let subscription: CookidooSubscriptionDTO?
}

struct CookidooSendToWeekRequestDTO: Encodable {
    let recipeId: String
    let date: String
}

struct CookidooSendToWeekResponseDTO: Decodable {
    let ok: Bool
    let date: String
    let alreadySent: Bool
}

/// Kształt błędu z backendu. `AppException` daje `{code, message}`,
/// globalny ValidationPipe — `{message: [...], statusCode}`, a guard JWT —
/// `{message, statusCode}`. Dekodujemy pobłażliwie i składamy w jedno.
struct BackendHttpErrorDTO: Decodable {
    let code: String?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case code
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        if let single = try? container.decodeIfPresent(String.self, forKey: .message) {
            message = single
        } else if let many = try? container.decodeIfPresent([String].self, forKey: .message) {
            message = many.first
        } else {
            message = nil
        }
    }
}
