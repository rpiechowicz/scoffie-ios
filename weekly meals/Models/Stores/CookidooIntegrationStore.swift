import Foundation
import Observation

/// Stan integracji Cookidoo (Thermomix) dla bieżącego gospodarstwa.
///
/// Wisi na `SessionStore` jak pozostałe store'y (budowany w
/// `bootstrapSession`, czyszczony przy wylogowaniu). Odświeżany przy starcie
/// sesji, żeby ekran przepisu wiedział, czy pokazać „Gotuj w Thermomixie",
/// zanim ktokolwiek otworzy Ustawienia.
@MainActor
@Observable
final class CookidooIntegrationStore {
    enum Status: Equatable {
        /// Jeszcze nie wiemy — brak odpowiedzi serwera (zimny start, offline).
        case unknown
        case notConnected
        case connected(login: String)
        /// Hasło do Cookidoo przestało działać — wiersz w Ustawieniach ma
        /// pokazać „Błąd logowania", a przycisk wysyłki zniknąć.
        case authFailed(login: String)
    }

    enum SendOutcome: Equatable {
        case sent
        /// Backendowe okno idempotencji (60 s) — dla użytkownika to sukces.
        case alreadySent
        case failed(message: String)
    }

    private(set) var status: Status = .unknown
    private(set) var lastVerifiedAt: Date?
    private(set) var isBusy = false
    /// Konto połączone, ale subskrypcja Cookidoo wygasła — ostrzeżenie,
    /// nie blokada (wiemy to tylko z odpowiedzi `connect`).
    private(set) var subscriptionInactive = false

    private let client: IntegrationsAPIClient

    init(client: IntegrationsAPIClient) {
        self.client = client
    }

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    var loginForDisplay: String? {
        switch status {
        case .connected(let login), .authFailed(let login):
            return login
        case .unknown, .notConnected:
            return nil
        }
    }

    func refresh() async {
        do {
            apply(try await client.fetchStatus())
        } catch {
            // Zostawiamy poprzedni stan: chwilowy brak sieci nie może
            // „rozłączać" integracji w oczach użytkownika.
        }
    }

    /// Zwraca komunikat błędu do pokazania inline albo `nil` przy sukcesie.
    func connect(email: String, password: String) async -> String? {
        guard !isBusy else { return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            let response = try await client.connect(email: email, password: password)
            status = .connected(login: response.login ?? email)
            lastVerifiedAt = Self.parseDate(response.lastVerifiedAt)
            subscriptionInactive = response.subscription.map { !$0.active } ?? false
            return nil
        } catch {
            return Self.message(for: error, context: .connect)
        }
    }

    /// Zwraca komunikat błędu albo `nil` przy sukcesie.
    func disconnect() async -> String? {
        guard !isBusy else { return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.disconnect()
            status = .notConnected
            lastVerifiedAt = nil
            return nil
        } catch {
            return Self.message(for: error, context: .disconnect)
        }
    }

    func sendToWeek(recipeId: String, date: String) async -> SendOutcome {
        do {
            let response = try await client.sendToWeek(recipeId: recipeId, date: date)
            return response.alreadySent ? .alreadySent : .sent
        } catch {
            if case IntegrationsAPIError.backend(let code, _) = error,
               code == "COOKIDOO_AUTH_FAILED" || code == "COOKIDOO_NOT_CONNECTED" {
                // Serwer oznaczył integrację jako zepsutą — dociągamy stan,
                // żeby Ustawienia i przycisk wysyłki mówiły to samo.
                await refresh()
            }
            return .failed(message: Self.message(for: error, context: .send))
        }
    }

    // MARK: - Mapowanie

    private func apply(_ dto: CookidooStatusDTO) {
        if dto.connected {
            let login = dto.login ?? ""
            status = dto.status == "AUTH_FAILED" ? .authFailed(login: login) : .connected(login: login)
        } else {
            status = .notConnected
        }
        lastVerifiedAt = Self.parseDate(dto.lastVerifiedAt)
    }

    private enum ErrorContext {
        case connect
        case disconnect
        case send
    }

    private static func message(for error: Error, context: ErrorContext) -> String {
        switch error {
        case IntegrationsAPIError.notAuthenticated:
            return "Sesja wygasła. Zaloguj się ponownie do aplikacji."
        case IntegrationsAPIError.network:
            return "Brak połączenia z serwerem. Sprawdź internet i spróbuj ponownie."
        case IntegrationsAPIError.backend(let code, _):
            switch code {
            case "COOKIDOO_AUTH_FAILED":
                return context == .connect
                    ? "Nieprawidłowy e-mail lub hasło Cookidoo."
                    : "Połączenie z Cookidoo wygasło. Zaloguj się ponownie w Ustawieniach."
            case "COOKIDOO_NOT_CONNECTED":
                return "Gospodarstwo nie ma połączonego konta Cookidoo. Połącz je w Ustawieniach."
            case "COOKIDOO_RECIPE_NOT_LINKED", "COOKIDOO_RECIPE_NOT_FOUND":
                return "Ten przepis nie ma wersji na Thermomixa."
            case "COOKIDOO_SERVICE_UNAVAILABLE":
                return "Usługa Cookidoo jest chwilowo niedostępna. Spróbuj ponownie za kilka minut."
            case "UNAUTHORIZED":
                return "Sesja wygasła. Zaloguj się ponownie do aplikacji."
            default:
                return "Coś poszło nie tak. Spróbuj ponownie."
            }
        default:
            return "Coś poszło nie tak. Spróbuj ponownie."
        }
    }

    /// Nest serializuje `Date` do ISO 8601 z milisekundami; parsujemy oba
    /// warianty, bo `lastVerifiedAt` bywa też czystym `Z`-owym znacznikiem.
    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
