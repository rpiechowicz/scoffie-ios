import Foundation
import Observation

/// Stan zgód użytkownika — źródłem prawdy jest serwer, telefon tylko
/// pokazuje i dopisuje zdarzenia.
///
/// Asystent wymaga DWÓCH zgód naraz (`AI_ASSISTANT` i `AGE_16`; serwer
/// odpowiada 403 `AI_CONSENT_REQUIRED` bez którejkolwiek), więc „włącz
/// asystenta" zapisuje oba zdarzenia, a „cofnij" — jedno (wiek nie
/// przestaje być prawdą).
@Observable
@MainActor
final class ConsentStore {
    private(set) var statuses: [ConsentStatusDTO] = []
    private(set) var isLoaded = false
    private(set) var isBusy = false

    private let client: ConsentsAPIClient

    init(client: ConsentsAPIClient) {
        self.client = client
        // Ostatni znany stan z telefonu: bez sieci przy starcie ktoś ze
        // zgodą widział hero i bramkę, a „Włącz asystenta" kończyło się
        // błędem. Serwer i tak nadpisze to przy pierwszej odpowiedzi.
        let cached = Self.loadCache()
        if !cached.isEmpty {
            statuses = cached
            isLoaded = true
        }
    }

    // MARK: - Pamięć podręczna

    private static let cacheKey = "consents.status.cache.v1"

    private static func loadCache() -> [ConsentStatusDTO] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return [] }
        return (try? JSONDecoder().decode([ConsentStatusDTO].self, from: data)) ?? []
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(statuses) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }

    /// Przy wylogowaniu — stan zgód jest per konto.
    static func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }

    /// Wersja dokumentów, na którą użytkownik się zgadza — ta sama, co w
    /// stopce logowania (`LegalDocMeta`) i w `legal-documents.ts` na serwerze.
    static let documentVersion = LegalDocMeta.documentVersionISO

    func granted(_ kind: String) -> Bool {
        statuses.first { $0.kind == kind }?.granted ?? false
    }

    var assistantGranted: Bool {
        granted(ConsentKind.aiAssistant) && granted(ConsentKind.age16)
    }

    func refresh() async {
        do {
            statuses = try await client.status()
            isLoaded = true
            saveCache()
        } catch {
            // Brak sieci nie może „cofać" zgody w oczach użytkownika —
            // zostaje poprzedni stan (albo nieznany, gdy to pierwszy odczyt).
        }
    }

    /// Oddaje komunikat błędu albo `nil` przy sukcesie.
    func grantAssistant(source: String) async -> String? {
        await record(
            [(ConsentKind.age16, ConsentAction.granted), (ConsentKind.aiAssistant, ConsentAction.granted)],
            source: source
        )
    }

    func revokeAssistant(source: String) async -> String? {
        await record([(ConsentKind.aiAssistant, ConsentAction.revoked)], source: source)
    }

    private func record(_ events: [(kind: String, action: String)], source: String) async -> String? {
        guard !isBusy else { return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            for event in events {
                statuses = try await client.record(
                    kind: event.kind,
                    action: event.action,
                    documentVersion: Self.documentVersion,
                    source: source
                )
            }
            isLoaded = true
            saveCache()
            return nil
        } catch {
            // Kod błędu do komunikatu: przy diagnozie „nie zapisuje się" liczy
            // się, czy to VALIDATION_ERROR, UNAUTHORIZED czy brak sieci.
            if case let BackendAPIError.backend(code, status, message) = error {
                return "\(message ?? UserFacingErrorMapper.message(from: error)) [\(code) \(status)]"
            }
            return UserFacingErrorMapper.inlineMessage(from: error)
        }
    }
}
