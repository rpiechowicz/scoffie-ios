import Foundation
import Observation
import StoreKit

/// Produkty subskrypcji w App Store Connect. Identyfikatory są umową
/// z panelem Apple — zmiana tutaj bez zmiany tam = pusty paywall.
enum SubscriptionCatalog {
    /// PRO dla gospodarstwa, odnawiane co miesiąc.
    static let proMonthly = "pl.weeklymeals.pro.monthly"
    static let all = [proMonthly]

    /// Zakup przechodzi dopiero, gdy serwer umie zweryfikować transakcję
    /// i nadać PRO (App Store Server API). Do tego czasu paywall pokazuje
    /// ofertę i cenę z App Store, ale nie pobiera pieniędzy za nic.
    static let purchasesEnabled = false
}

/// StoreKit 2: produkty, zakup, przywracanie i nasłuch transakcji.
///
/// Uprawnienie (PRO) NIE jest liczone na telefonie — źródłem prawdy jest
/// serwer (`GET /agent/usage` → `tier`/`source`), bo pula jest wspólna dla
/// domu, a subskrypcję kupuje jedna osoba. Telefon tylko zgłasza transakcję
/// serwerowi i odświeża stan.
@Observable
@MainActor
final class SubscriptionStore {
    enum PurchaseOutcome { case purchased, pending, cancelled, failed(String) }

    private(set) var products: [StoreKit.Product] = []
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var lastError: String?

    private var updatesTask: Task<Void, Never>?

    var proMonthly: StoreKit.Product? {
        products.first { $0.id == SubscriptionCatalog.proMonthly }
    }

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handle(result)
            }
        }
    }

    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await StoreKit.Product.products(for: SubscriptionCatalog.all)
            lastError = nil
        } catch {
            // Brak produktów to najczęściej brak konfiguracji w App Store
            // Connect albo brak sieci — paywall pokazuje ofertę bez ceny.
            lastError = "Nie udało się pobrać ceny z App Store."
        }
    }

    func purchase(_ product: StoreKit.Product) async -> PurchaseOutcome {
        guard SubscriptionCatalog.purchasesEnabled else {
            return .failed("Zakupy pojawią się razem z aktywacją PRO po stronie serwera.")
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
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

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case let .verified(transaction) = result else { return }
        // Zgłoszenie transakcji serwerowi (nadanie PRO gospodarstwu) dojdzie
        // razem z weryfikacją po stronie backendu; do tego czasu transakcja
        // jest tylko domykana, żeby nie wracała przy każdym starcie.
        await transaction.finish()
    }
}
