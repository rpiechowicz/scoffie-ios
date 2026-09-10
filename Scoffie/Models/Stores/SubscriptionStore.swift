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
    /// Dla kogo ten plan — jedno zdanie na karcie wyboru. Opisuje rozmiar
    /// domu, nie obiecuje niczego ponad limity.
    let audience: String

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
        pricePln: 29.99,
        audience: "Dla jednej osoby, która planuje tylko dla siebie."
    )
    static let duet = SubscriptionPlan(
        id: "app.scoffie.pro.duet.monthly",
        name: "We dwoje",
        seatsLabel: "2 osoby",
        messages: 50,
        plans: 12,
        pricePln: 39.99,
        audience: "Dla dwóch osób z jednym wspólnym planem tygodnia."
    )
    static let family = SubscriptionPlan(
        id: "app.scoffie.pro.family.monthly",
        name: "Rodzina",
        seatsLabel: "3 osoby i więcej",
        messages: 75,
        plans: 18,
        pricePln: 49.99,
        audience: "Dla domu od trzech osób, w którym plan zmienia się częściej."
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

    /// Co serwer zrobił ze zgłoszoną transakcją.
    ///
    /// Rozróżnienie jest istotne dla DWÓCH rzeczy naraz: co pokazać człowiekowi
    /// (zakup przeszedł czy nie) i czy domknąć transakcję w StoreKit (odmowa
    /// trwała — tak, chwilowa — nie, bo Apple ma o niej przypomnieć).
    enum ReportOutcome {
        case accepted
        /// Serwer ODPOWIEDZIAŁ odmową — komunikat jest zawsze.
        case rejected(String)
        /// Nie udało się dowieźć zgłoszenia. `nil` znaczy „to był brak sieci":
        /// mówi o nim pasek u góry, a nie komunikat przy przycisku.
        case postponed(String?)
    }

    private(set) var products: [StoreKit.Product] = []
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var lastError: String?
    /// Stan z serwera: czy zakupy są włączone i co ta osoba już ma.
    private(set) var state: BillingStateDTO?

    /// Powiadomienie o zdarzeniu, które zaszło BEZ EKRANU — zakup dogadany
    /// z Apple w tle. Zdejmuje je most w korzeniu aplikacji
    /// (`scBackgroundToast`) i od razu kasuje przez `clearBackgroundNotice()`.
    private(set) var backgroundNotice: SCToast?

    /// Kasowanie jest niezbędne, nie sprząta: `SCToast` porównuje się po
    /// treści, więc bez powrotu do `nil` drugie identyczne powiadomienie
    /// nie zmieniłoby wartości i przepadłoby po cichu.
    func clearBackgroundNotice() {
        backgroundNotice = nil
    }

    /// Transakcje, o których powiedział już ekran zakupu. Bez tego ta sama
    /// płatność potrafiłaby dać dwie kapsuły: jedną z `PlansSheet`, drugą
    /// z pętli `Transaction.updates`, gdyby StoreKit podał ją tam ponownie.
    private var announcedTransactionIDs: Set<UInt64> = []

    /// Mówi o zakupie, który doszedł do skutku POZA ekranem.
    ///
    /// Bramkujemy po `Transaction.reason`, a nie po tym, czy stan przed
    /// zgłoszeniem wyglądał na „bez dostępu". Tamten warunek był nie do
    /// obronienia: `state` jest `nil` aż do pierwszego `refreshState()`,
    /// czyli do otwarcia ekranu planu, a StoreKit odtwarza niedomknięte
    /// transakcje zaraz po starcie — więc comiesięczne odnowienie wyglądało
    /// jak wejście z braku dostępu w dostęp i mówiło „kupione" bez powodu.
    /// `reason` to fakt, który podaje sam StoreKit.
    private func announceIfApprovedInBackground(
        _ result: VerificationResult<Transaction>,
        outcome: ReportOutcome
    ) {
        guard case .accepted = outcome else { return }
        let transaction = result.unsafePayloadValue
        guard transaction.reason == .purchase else { return }
        guard !announcedTransactionIDs.contains(transaction.id) else { return }
        announcedTransactionIDs.insert(transaction.id)
        backgroundNotice = SCToast(
            style: .success,
            title: "Asystent odblokowany",
            message: "Zakup został zatwierdzony."
        )
    }

    /// Odnotowuje, że o tej płatności powiedział już ekran zakupu.
    private func noteAnnouncedOnScreen(_ result: VerificationResult<Transaction>) {
        announcedTransactionIDs.insert(result.unsafePayloadValue.id)
    }

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
                // Tędy wchodzi zakup zatwierdzony PÓŹNIEJ — dziecko poprosiło,
                // rodzic kliknął dwie godziny potem — i zgłoszenie, które Apple
                // ponowiło przy starcie. W obu przypadkach nie ma ekranu, na
                // którym dałoby się cokolwiek pokazać, więc powiadomienie idzie
                // do kolejki toastów przez most z korzenia aplikacji.
                let outcome = await self.handle(result)
                self.announceIfApprovedInBackground(result, outcome: outcome)
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
                // „DZIĘKUJEMY" DOPIERO PO PRZYJĘCIU PRZEZ SERWER. Apple pobrało
                // pieniądze, ale dostęp nadaje serwer — a on potrafi odmówić
                // (Chmura Rodzinna, zakup przypisany do innego konta, sandbox
                // na produkcji). Wcześniej ekran mówił „Dziękujemy" niezależnie
                // od tego, co odpowiedział serwer, więc człowiek widział
                // potwierdzenie zakupu i zero asystenta, bez żadnej wskazówki,
                // co dalej.
                switch await handle(verification) {
                case .accepted:
                    // O tej płatności powie ekran zakupu; pętla
                    // `Transaction.updates` ma o niej milczeć, gdyby StoreKit
                    // podał ją tam jeszcze raz.
                    noteAnnouncedOnScreen(verification)
                    return .purchased
                case let .rejected(message):
                    return .failed(message)
                case let .postponed(message):
                    // Pieniądze poszły, dostęp jeszcze nie — transakcja została
                    // otwarta, więc StoreKit przypomni o niej sam.
                    lastError = message
                    return .pending
                }
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
            lastError = nil
            try await AppStore.sync()
        } catch {
            // Odmowa logowania do App Store albo brak sieci. Uprawnienia i tak
            // warto przejrzeć — `currentEntitlements` czyta się lokalnie.
            lastError = "Nie udało się odświeżyć zakupów w App Store."
        }
        await reportEntitlements()
        await refreshState()
    }

    /// Zgłasza serwerowi WSZYSTKIE żywe uprawnienia tego Apple ID.
    ///
    /// TO JEST PRAWDZIWE „PRZYWRÓĆ ZAKUPY”. `Transaction.updates` oddaje
    /// wyłącznie transakcje NIEDOMKNIĘTE — raz domknięta nie wraca tam nigdy.
    /// Dopóki „Przywróć zakupy” opierało się tylko na `AppStore.sync()`,
    /// każda transakcja, którą telefon zdążył domknąć po odmowie serwera,
    /// przepadała bezpowrotnie: nie było w całej aplikacji ani jednego
    /// odwołania do `currentEntitlements`, czyli jedynego miejsca, które ją
    /// jeszcze widzi. Apple wprost każe czytać je po `sync()`.
    ///
    /// Jest to też siatka pod odmowy chwilowe: jeśli serwer nie przyjął zakupu,
    /// bo App Store go jeszcze nie widział, wystarczy tu wrócić.
    private func reportEntitlements() async {
        guard client != nil else { return }
        for await result in Transaction.currentEntitlements {
            _ = await handle(result)
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
    private func handle(_ result: VerificationResult<Transaction>) async -> ReportOutcome {
        // Brak klienta to nie brak sieci — sesja jeszcze nie zbudowała
        // warstwy zakupów. Dawne „Brak połączenia z serwerem." mówiło tu
        // nieprawdę i myliło się z jedynym miejscem, które od teraz mówi
        // o łączności.
        guard let client else { return .postponed("Zakupy nie są jeszcze gotowe. Spróbuj za chwilę.") }
        do {
            _ = try await client.register(signedTransaction: result.jwsRepresentation)
            await refreshState()
            if case let .verified(transaction) = result {
                await transaction.finish()
            }
            lastError = nil
            return .accepted
        } catch {
            let message = UserFacingErrorMapper.inlineMessage(from: error)
            if Self.isPermanentRefusal(error) {
                // ODMOWA TRWAŁA MUSI DOMKNĄĆ TRANSAKCJĘ. Otwarta transakcja
                // wraca w `Transaction.updates` przy KAŻDYM starcie aplikacji,
                // więc zgłoszenie, które serwer odrzuci i za tydzień, kręciłoby
                // się w nieskończoność: to samo żądanie, ten sam błąd, ten sam
                // komunikat przy każdym uruchomieniu. Domknięcie nie kasuje
                // subskrypcji w App Store — kończy tylko nasze przypominanie.
                if case let .verified(transaction) = result {
                    await transaction.finish()
                }
                lastError = message
                // Odmowa trwała zawsze przychodzi Z ODPOWIEDZI serwera, więc
                // `message` jest tu w praktyce zawsze — zapasowe zdanie stoi
                // tylko po to, żeby typ się domykał bez wykrzyknika.
                return .rejected(message ?? "Nie udało się potwierdzić zakupu.")
            }
            // Awaria sieci albo serwera: transakcja ZOSTAJE otwarta, żeby
            // Apple przypomniało o niej przy następnym starcie.
            lastError = message
            return .postponed(message)
        }
    }

    /// Kody, po których ponawianie nie ma sensu — i tylko one domykają transakcję.
    ///
    /// LISTA, NIE KLASA STATUSU. Wcześniej odmową trwałą było KAŻDE 4xx, a
    /// backend odsyłał 4xx także wtedy, gdy App Store Server API przez kilka
    /// minut nie widziało świeżo kupionej transakcji. Skutek był najgorszy
    /// z możliwych: telefon domykał transakcję, StoreKit przestawał o niej
    /// przypominać, a człowiek zostawał z pobraną opłatą i bez dostępu — bez
    /// ŻADNEJ ścieżki odzysku, bo domkniętej transakcji nie widzi już nawet
    /// „Przywróć zakupy”.
    ///
    /// Tutaj są wyłącznie odmowy, które są decyzją o TYM zakupie i nie zmienią
    /// się od powtórzenia: Chmura Rodzinna, obce środowisko, cudze konto,
    /// konto bez tożsamości zakupowej. Wszystko inne — łącznie z „Apple
    /// jeszcze tego nie widzi” — zostawia transakcję otwartą.
    private static let permanentRefusalCodes: Set<String> = [
        "BILLING_FAMILY_SHARING_UNSUPPORTED",
        "BILLING_ENVIRONMENT_MISMATCH",
        "BILLING_TRANSACTION_TAKEN",
        "BILLING_IDENTITY_MISSING",
    ]

    private static func isPermanentRefusal(_ error: Error) -> Bool {
        guard let apiError = error as? BackendAPIError else { return false }
        guard case let .backend(code, _, _) = apiError else { return false }
        return permanentRefusalCodes.contains(code)
    }
}
