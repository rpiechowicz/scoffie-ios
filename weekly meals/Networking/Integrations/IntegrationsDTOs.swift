import Foundation

// DTO-sy REST-owych endpointów `integrations/cookidoo` (NestJS,
// `integrations.controller.ts`). Osobno od DTO-sów socketowych: to jedyna
// część aplikacji, która rozmawia z backendem po HTTP z tokenem — patrz
// `IntegrationsAPIClient`.

struct CookidooStatusDTO: Decodable {
    /// `false` = integracja wyłączona flagą na serwerze (klient chowa wiersz).
    /// Opcjonalne — starszy serwer bez pola znaczy „włączona".
    let enabled: Bool?
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

// DTO-sy `integrations/health` (kroki z HealthKit) — patrz
// `health-steps.controller.ts` po stronie backendu.

struct HealthStepsEntryDTO: Codable, Equatable {
    /// "yyyy-MM-dd" liczona w strefie telefonu — serwer (UTC) jej nie rusza.
    let date: String
    let steps: Int
    /// Zrzut celu z dnia wysyłki — przyszłe statystyki znają ówczesny cel.
    let stepsGoal: Int
    /// `StepsSource.rawValue`: APPLE_HEALTH | GARMIN.
    let source: String
}

struct HealthStepsSyncRequestDTO: Encodable {
    let entries: [HealthStepsEntryDTO]
}

struct HealthStepsSyncResponseDTO: Decodable {
    let ok: Bool
    let synced: Int
}

/// Kształt błędu z backendu: od plastra C zawsze
/// `{code, message, details?, requestId}` (globalny filtr). Dekodujemy
/// pobłażliwie — starszy backend potrafił oddać `{message: [...], statusCode}`
/// z ValidationPipe albo `{message, statusCode}` z guardu JWT.
struct BackendHttpErrorDTO: Decodable {
    let code: String?
    let message: String?
    let details: [String]?
    let requestId: String?

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case details
        case requestId
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
        details = try? container.decodeIfPresent([String].self, forKey: .details)
        requestId = try? container.decodeIfPresent(String.self, forKey: .requestId)
    }
}
