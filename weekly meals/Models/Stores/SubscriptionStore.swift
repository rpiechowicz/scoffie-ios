import Foundation
import Observation
import StoreKit

/// Plan PRO w App Store — trzy stopnie drabiny nazwanej wielkością domu.
///
/// Liczby MUSZĄ być identyczne z `src/config/subscription-products.ts` na
/// serwerze i z opisem produktu w App Store Connect: Apple wymaga podania
/// konkretnych ilości przed zakupem (3.1.2(c)), a liczba na ekranie staje
/// się OBIETNICĄ — podnieść ją wolno w każdej chwili, obniżyć obecnym
/// subskrybentom nie (to zmiana warunków umowy w trakcie jej trwania). Serwer jest źródłem prawdy o tym, ile komu zostało —
/// te wartości służą wyłącznie do opisania oferty przed zakupem.
///
/// Liczba osób jest ETYKIETĄ, nie bramką: nikt nie liczy domowników. Większy
/// dom po prostu zużywa pulę szybciej, więc wybiera wyższy plan.
struct SubscriptionPlan: Identifiable, Equatable {
    let id: String
    let name: String
    let seatsLabel: String
    let messages: Int
    let plans: Int
    /// Cena z decyzji cennikowej — WYŁĄCZNIE jako zapas, gdy App Store nie
    /// odda produktów (brak sieci, produkt jeszcze nieopublikowany). Prawdę
    /// o cenie mówi zawsze `StoreKit.Product.displayPrice`, bo tylko ono zna
    /// walutę i podatek kupującego.
    let pricePln: Double

    var quantityLine: String {
        "\(messages) wiadomości i \(plans) zapisów planu w miesiącu"
    }

    var fallbackPrice: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.numberStyle = .currency
        formatter.currencyCode = "PLN"
        return formatter.string(from: NSNumber(value: pricePln)) ?? "\(pricePln) zł"
    }
}

enum SubscriptionCatalog {
    static let solo = SubscriptionPlan(
        id: "app.scoffie.pro.solo.monthly",
        name: "Solo",
        seatsLabel: "1 osoba",
        messages: 30,
        plans: 8,
        pricePln: 29.99
    )
    static let duet = SubscriptionPlan(
        id: "app.scoffie.pro.duet.monthly",
        name: "We dwoje",
        seatsLabel: "2 osoby",
        messages: 50,
        plans: 12,
        pricePln: 39.99
    )
    static let family = SubscriptionPlan(
        id: "app.scoffie.pro.family.monthly",
        name: "Rodzina",
        seatsLabel: "3 osoby i więcej",
        messages: 75,
        plans: 18,
        pricePln: 49.99
    )

    /// Kolejność jak w karuzeli planów; `duet` jest preselekcjonowany.
    static let all: [SubscriptionPlan] = [solo, duet, family]
    static let identifiers = all.map(\.id)
    static let recommended = duet

    /// Lokalny bezpiecznik. Prawdziwą bramką jest `SubscriptionStore.
    /// purchasesEnabled`, którą oddaje SERWER — dopóki backend nie ma klucza
    /// do App Store Server API, przyjęcie pieniędzy skończyłoby się płatnością
    /// bez nadanego dostępu. Ta stała pozwala wyłączyć zakupy z aplikacji
    /// nawet wtedy, gdy serwer jest gotowy.
    static let purchasesEnabled = true
}

/// StoreKit 2: produkty, zakup, przywracanie i nasłuch transakcji.
///
/// Uprawnienie (PRO) NIE jest liczone na telefonie — źródłem prawdy jest
/// serwer (`GET /agent/usage` → `tier`/`source`/`product`), bo pula jest
/// wspólna dla domu, a subskrypcję kupuje jedna osoba. Telefon tylko zgłasza
/// transakcję serwerowi i odświeża stan.
@Observable
@MainActor
final class SubscriptionStore {
    enum PurchaseOutcome { case purchased, pending, cancelled, failed(String) }

    private(set) var products: [StoreKit.Product] = []
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var lastError: String?
    /// Stan z serwera: czy zakupy są włączone i co ta osoba już ma.
    private(set) var state: BillingStateDTO?

    /// Czy wolno pobrać pieniądze. Decyduje SERWER, bo tylko on wie, czy umie
    /// potwierdzić transakcję w App Store. Brak odpowiedzi = nie wolno.
    var purchasesEnabled: Bool { state?.purchasesEnabled == true }

    private let client: BillingAPIClient?
    /// Identyfikator konta wkładany w transakcję (`appAccountToken`). Dzięki
    /// niemu powiadomienie od Apple o subskrypcji, której serwer jeszcze nie
    /// zna, da się przypisać do właściciela bez czekania na telefon.
    private let accountToken: UUID?

    private var updatesTask: Task<Void, Never>?

    init(client: BillingAPIClient? = nil, userId: String? = nil) {
        self.client = client
        self.accountToken = userId.flatMap(UUID.init(uuidString:))
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handle(result)
            }
        }
    }

    /// Stan subskrypcji i zgoda serwera na zakupy. Wołane przy każdym
    /// otwarciu ekranu „Asystent i plan".
    @discardableResult
    func refreshState() async -> BillingStateDTO? {
        guard let client else { return nil }
        state = try? await client.state()
        return state
    }

    func product(for plan: SubscriptionPlan) -> StoreKit.Product? {
        products.first { $0.id == plan.id }
    }

    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await StoreKit.Product.products(for: SubscriptionCatalog.identifiers)
            lastError = nil
        } catch {
            // Brak produktów to najczęściej brak konfiguracji w App Store
            // Connect albo brak sieci — karty pokazują cenę zapasową.
            lastError = "Nie udało się pobrać ceny z App Store."
        }
    }

    func purchase(_ product: StoreKit.Product) async -> PurchaseOutcome {
        guard purchasesEnabled else {
            return .failed("Zakupy pojawią się, gdy serwer zacznie potwierdzać płatności.")
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            var options: Set<StoreKit.Product.PurchaseOption> = []
            if let accountToken {
                options.insert(.appAccountToken(accountToken))
            }
            let result = try await product.purchase(options: options)
            switch result {
            case let .success(verification):
                await handle(verification)
                return .purchased
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed("Nieznany wynik zakupu.")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// „Przywróć zakupy" — App Store odświeża uprawnienia; potem transakcje
    /// przechodzą przez `handle` jak każde inne.
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            lastError = "Nie udało się przywrócić zakupów."
        }
    }

    /// Każda transakcja ze StoreKit — zakup, odnowienie, przywrócenie,
    /// zatwierdzenie „Poproś o zakup".
    ///
    /// KOLEJNOŚĆ JEST WAŻNA: najpierw zgłoszenie serwerowi, dopiero potem
    /// `finish()`. Domknięta transakcja nie wróci w `Transaction.updates`, więc
    /// domknięcie przed zgłoszeniem zamienia awarię sieci w opłacony dostęp,
    /// którego nikt nie włączył. Gdy zgłoszenie się nie uda, zostawiamy
    /// transakcję otwartą — Apple przypomni o niej przy następnym starcie.
    ///
    /// Weryfikacji NIE robimy na telefonie: `.unverified` też zgłaszamy, bo
    /// jedynym miejscem, które ma prawo rozstrzygać o podpisie, jest serwer
    /// z łańcuchem do przypiętego korzenia Apple.
    private func handle(_ result: VerificationResult<Transaction>) async {
        guard let client else { return }
        do {
            _ = try await client.register(signedTransaction: result.jwsRepresentation)
            await refreshState()
            if case let .verified(transaction) = result {
                await transaction.finish()
            }
        } catch {
            lastError = "Nie udało się potwierdzić zakupu. Spróbujemy ponownie."
        }
    }
}
