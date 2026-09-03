import Foundation
import Observation
import StoreKit

/// Plan PRO w App Store — trzy stopnie drabiny nazwanej wielkością domu.
///
/// Liczby MUSZĄ być identyczne z `src/config/subscription-products.ts` na
/// serwerze i z opisem produktu w App Store Connect: Apple wymaga podania
/// konkretnych ilości przed zakupem (3.1.2(c)), a liczba na paywallu staje
/// się obietnicą. Serwer jest źródłem prawdy o tym, ile komu zostało —
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

    var quantityLine: String {
        "\(messages) wiadomości i \(plans) zapisów planu w miesiącu"
    }
}

enum SubscriptionCatalog {
    static let solo = SubscriptionPlan(
        id: "pl.weeklymeals.pro.solo.monthly",
        name: "Solo",
        seatsLabel: "1 osoba",
        messages: 40,
        plans: 6
    )
    static let duet = SubscriptionPlan(
        id: "pl.weeklymeals.pro.duet.monthly",
        name: "Duet",
        seatsLabel: "2 osoby",
        messages: 60,
        plans: 8
    )
    static let family = SubscriptionPlan(
        id: "pl.weeklymeals.pro.family.monthly",
        name: "Rodzina",
        seatsLabel: "3 osoby i więcej",
        messages: 100,
        plans: 14
    )

    /// Kolejność jak na paywallu; `duet` jest preselekcjonowany.
    static let all: [SubscriptionPlan] = [solo, duet, family]
    static let identifiers = all.map(\.id)
    static let recommended = duet

    /// Zakup przechodzi dopiero, gdy serwer umie zweryfikować transakcję
    /// i nadać PRO (App Store Server API). Do tego czasu paywall pokazuje
    /// ofertę i cenę z App Store, ale nie pobiera pieniędzy za nic.
    static let purchasesEnabled = false
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

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handle(result)
            }
        }
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
