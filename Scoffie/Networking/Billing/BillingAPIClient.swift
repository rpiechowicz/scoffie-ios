import Foundation

/// Subskrypcja w odpowiedzi serwera. Telefon NICZEGO tu nie liczy — stan
/// bierze się z App Store Server API po stronie backendu, bo transakcja
/// z telefonu nic nie wie o zwrocie pieniędzy sprzed godziny.
struct BillingSubscriptionDTO: Decodable, Equatable {
    let id: String
    let productId: String
    /// Nazwa planu (Solo / We dwoje / Rodzina); `nil` przy nieznanym produkcie.
    let productName: String?
    let status: String
    /// Czy daje dostęp TERAZ — łącznie z łaską płatniczą i zwrotem pieniędzy.
    let alive: Bool
    let expiresAt: String?
    let graceExpiresAt: String?
    let autoRenews: Bool?
    let environment: String?
    let messagesLimit: Int?
    let plansLimit: Int?
    /// Powód ręcznego odebrania dostępu przez obsługę; `nil` = bez blokady.
    /// Bez tego pola ekran pokazywałby „nieaktywna" bez jednego słowa dlaczego.
    let operatorHold: String?
}

/// Odpowiedź `GET /billing/subscription`.
struct BillingStateDTO: Decodable, Equatable {
    /// Czy serwer umie POTWIERDZIĆ zakup. To jest jedyna bramka na przycisk
    /// zakupu: dopóki backend nie ma klucza do App Store Server API, przyjęcie
    /// pieniędzy skończyłoby się płatnością bez nadanego dostępu.
    let purchasesEnabled: Bool
    let environment: String
    let subscriptions: [BillingSubscriptionDTO]
}

struct BillingRegisterRequestDTO: Encodable {
    let signedTransaction: String
}

struct BillingRegisterResponseDTO: Decodable {
    let subscription: BillingSubscriptionDTO
}

/// Płatności App Store po stronie telefonu — dwa żądania i tyle.
///
/// Telefon ZGŁASZA transakcję, nie nadaje dostępu. Podpisana transakcja jest
/// dla serwera wyłącznie wskazówką „sprawdź tę subskrypcję"; stan i tak
/// pochodzi z App Store Server API. Dlatego tu nie ma żadnej logiki poza
/// przekazaniem podpisu dalej.
final class BillingAPIClient {
    private let core: BackendRESTCore

    init(core: BackendRESTCore) {
        self.core = core
    }

    /// Stan subskrypcji tej osoby i informacja, czy zakupy są w ogóle włączone.
    func state() async throws -> BillingStateDTO {
        try await core.request(path: "billing/subscription", method: "GET")
    }

    /// Zgłoszenie zakupu. Wołane po KAŻDEJ transakcji ze StoreKit, także po
    /// odnowieniu i po „Przywróć zakupy" — serwer jest idempotentny, a
    /// zgubione zgłoszenie znaczy opłacony dostęp, którego nikt nie włączył.
    func register(signedTransaction: String) async throws -> BillingSubscriptionDTO {
        let response: BillingRegisterResponseDTO = try await core.request(
            path: "billing/apple/transaction",
            method: "POST",
            body: BillingRegisterRequestDTO(signedTransaction: signedTransaction)
        )
        return response.subscription
    }
}
