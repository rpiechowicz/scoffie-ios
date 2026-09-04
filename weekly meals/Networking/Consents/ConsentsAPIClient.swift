import Foundation

// Zgody (`/me/consents`, backend `consents.controller.ts`). Dziennik jest
// tylko-dopisywalny: każde stuknięcie w „włącz"/„cofnij" to nowe zdarzenie
// z wersją dokumentu, a stan bieżący liczy serwer (`granted`).

/// Rodzaje zgód dokładnie jak w `src/common/legal-documents.ts`.
enum ConsentKind {
    static let terms = "TERMS"
    static let privacy = "PRIVACY"
    static let aiAssistant = "AI_ASSISTANT"
    static let age16 = "AGE_16"
    static let cookidoo = "COOKIDOO"
    static let healthData = "HEALTH_DATA"
}

enum ConsentAction {
    static let granted = "GRANTED"
    static let revoked = "REVOKED"
}

struct ConsentStatusDTO: Codable, Equatable {
    let kind: String
    let granted: Bool
    let documentVersion: String?
    let at: String?
    /// Wersja, którą serwer uważa za bieżącą (`YYYY-MM-DD`); starszy serwer jej nie oddaje.
    let currentVersion: String?
    /// Najstarsza wersja, którą serwer jeszcze honoruje.
    let minimumVersion: String?
}

struct RecordConsentRequestDTO: Encodable {
    let kind: String
    let action: String
    let documentVersion: String
    let source: String
    let appVersion: String?
}

final class ConsentsAPIClient {
    private let core: BackendRESTCore

    init(core: BackendRESTCore) {
        self.core = core
    }

    func status() async throws -> [ConsentStatusDTO] {
        try await core.request(path: "me/consents", method: "GET")
    }

    /// Zapisuje zdarzenie i oddaje świeży stan wszystkich zgód.
    func record(
        kind: String,
        action: String,
        documentVersion: String,
        source: String
    ) async throws -> [ConsentStatusDTO] {
        try await core.request(
            path: "me/consents",
            method: "POST",
            body: RecordConsentRequestDTO(
                kind: kind,
                action: action,
                documentVersion: documentVersion,
                source: source,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            )
        )
    }
}
