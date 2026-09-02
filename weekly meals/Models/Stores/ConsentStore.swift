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
            return nil
        } catch {
            return UserFacingErrorMapper.message(from: error)
        }
    }
}
