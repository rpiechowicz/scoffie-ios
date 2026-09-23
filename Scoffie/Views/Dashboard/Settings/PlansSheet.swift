import StoreKit
import SwiftUI

/// „Wybierz plan" — trzy pełne karty jedna pod drugą.
///
/// Na górze stan: jaki plan dom MA (z serwera) albo że nie ma żadnego.
/// Liczba domowników tylko PODPOWIADA plan („Polecany”) — nigdy nie udaje,
/// że coś jest kupione. Dawniej plan zgodny z Gospodarstwem nosił dopisek
/// „Twój dom” z domkiem i był zaznaczony, więc dom z dwiema osobami na
/// próbie widział „We dwoje” jak własny plan.
///
/// Każda karta mówi trzy rzeczy: dla kogo (liczba osób), ile daje (dwa
/// limity) i o co więcej niż tańszy plan. Przycisk na dole powtarza nazwę i cenę wybranego
/// planu, bo cena przy zakupie to wymóg App Store 3.1.2, a nazwa oszczędza
/// spojrzenia z powrotem na listę.
///
/// Wjeżdża NA „Asystent i plan" (albo z linijki „Zobacz plany" w rozmowie)
/// i sam się zamyka po udanym zakupie — arkusz pod spodem odświeża stan.
struct PlansSheet: View {
    /// Po zakupie PRZYJĘTYM przez serwer — arkusz pod spodem przeładowuje
    /// stan, zanim ten się zamknie.
    var onPurchased: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.toasts) private var toasts
    @Environment(\.colorScheme) private var scheme
    @Environment(\.sessionStore) private var sessionStore

    /// Awaryjny egzemplarz na wypadek ekranu bez sesji — bez klienta, więc
    /// niczego nie kupi. Normalnie używamy tego z `SessionStore`.
    @State private var fallbackSubscriptions = SubscriptionStore()
    @State private var selected = SubscriptionCatalog.recommended
    @State private var notice: String?
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var isRestoring = false

    private var subscriptions: SubscriptionStore {
        sessionStore.subscriptionStore ?? fallbackSubscriptions
    }

    var body: some View {
        NavigationStack {
            // Ten sam szkielet co arkusze asystenta (eyebrow · tytuł · X,
            // stopka nad gradientem). Bez `GeometryReader`: pierwszy przebieg
            // układu dostawał szerokość zero i treść rysowała się „od boku”,
            // zanim arkusz dojechał na miejsce.
            AssistantSheetScaffold(
                eyebrow: "Plany · miesięcznie",
                title: "Wybierz plan",
                subtitle: "Pula wspólna dla całego domu, odnawia się co miesiąc.",
                onClose: { dismiss() },
                footer: { footer }
            ) {
                // Trzy kafle do wyboru, jedna karta szczegółów: przy
                // zmianie planu liczby i paski przeliczają się w miejscu,
                // zamiast kazać porównywać trzy karty po kawałku.
                currentStatus
                    .padding(.top, 14)

                HStack(spacing: 8) {
                    ForEach(SubscriptionCatalog.all) { plan in
                        PlanTile(
                            plan: plan,
                            price: price(for: plan),
                            isSelected: plan.id == selected.id,
                            isCurrent: plan.id == currentPlan?.id,
                            isSuggested: plan.id == suggestedPlan?.id && plan.id != currentPlan?.id
                        ) {
                            select(plan)
                        }
                    }
                }
                .padding(.top, 12)

                PlanDetailCard(
                    plan: selected,
                    price: price(for: selected),
                    isCurrent: selected.id == currentPlan?.id,
                    suggestion: selected.id == suggestedPlan?.id && selected.id != currentPlan?.id
                        ? suggestionText
                        : nil
                )
                .padding(.top, 10)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: selected.id)
        .sheet(isPresented: $showTerms) {
            LegalDocumentSheet(title: "Regulamin") { TermsOfServiceContent() }
        }
        .sheet(isPresented: $showPrivacy) {
            LegalDocumentSheet(title: "Polityka prywatności") { PrivacyPolicyContent() }
        }
        .task {
            // Na wejściu: plan polecany dla domu, a gdy go nie ma — obecny.
            // Tylko raz, żeby nie przestawiać wyboru komuś, kto już stuknął
            // inną kartę. To jest ZAZNACZENIE kafla, nie stan zakupu.
            if let initial = suggestedPlan ?? currentPlan { selected = initial }
            // Najpierw pytamy serwer, czy zakupy są w ogóle włączone —
            // przycisk ma być nieaktywny, dopóki nie umiemy potwierdzić
            // płatności, a nie dopiero po jej pobraniu.
            await subscriptions.refreshState()
            await subscriptions.loadProducts()
        }
    }

    // MARK: - Dom

    private var householdSize: Int {
        sessionStore.householdMembers.count
    }

    /// Plan pasujący do liczby domowników — PODPOWIEDŹ, nie stan zakupu.
    private var suggestedPlan: SubscriptionPlan? {
        Self.plan(forHousehold: householdSize)
    }

    private var suggestionText: String {
        "polecany dla \(householdSize) \(householdSize == 1 ? "osoby" : "osób")"
    }

    /// Plan, który dom MA teraz — wyłącznie z serwera. Najpierw subskrypcja
    /// tej osoby (dokładny identyfikator produktu), potem stan domu z licznika
    /// asystenta (domownik, za którego płaci ktoś inny). Próba, nadanie od nas
    /// i brak danych = brak planu.
    private var currentPlan: SubscriptionPlan? {
        if let alive = subscriptions.state?.subscriptions.first(where: { $0.alive }),
           let plan = SubscriptionCatalog.all.first(where: { $0.id == alive.productId }) {
            return plan
        }
        guard let usage = sessionStore.agentStore?.usage,
              !usage.isTrial,
              usage.source == "SUBSCRIPTION"
        else { return nil }
        return SubscriptionCatalog.plan(named: usage.product)
    }

    /// Wiersz stanu nad kaflami: co dom ma teraz. Bez tego jedyną
    /// informacją był zaznaczony kafel — a zaznaczenie to wybór, nie zakup.
    private var currentStatus: some View {
        let plan = currentPlan
        let usage = sessionStore.agentStore?.usage

        return HStack(spacing: 12) {
            Image(systemName: plan == nil ? "circle.dashed" : "checkmark.seal.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(plan == nil ? Color.scMuted(scheme) : SCPalette.sage)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.map { "Twój plan: \($0.name)" } ?? "Nie masz jeszcze planu")
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scLabel(scheme))
                Text(currentStatusDetail(plan: plan, usage: usage))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(plan == nil ? Color.scTileBg(scheme) : SCPalette.sage.opacity(scheme == .dark ? 0.12 : 0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(plan == nil ? Color.scTileStroke(scheme) : SCPalette.sage.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private func currentStatusDetail(plan: SubscriptionPlan?, usage: AgentUsageDTO?) -> String {
        guard plan != nil else {
            return usage?.isTrial == true
                ? "Teraz korzystasz z jednorazowej puli próbnej."
                : "Wybierz plan, żeby asystent działał co miesiąc."
        }
        if let usage, !usage.isThePayer, let payer = usage.payerName, !payer.isEmpty {
            return "Opłaca \(HouseholdMemberStyle.shortName(payer)) — pula jest wspólna dla całego domu."
        }
        return "Pula wspólna dla całego domu, odnawia się co miesiąc."
    }

    /// Plan o etykiecie zgodnej z liczbą domowników. Liczba osób jest
    /// ETYKIETĄ, nie bramką — to tylko domyślne zaznaczenie i dopisek.
    static func plan(forHousehold size: Int) -> SubscriptionPlan? {
        switch size {
        case ..<1: return nil
        case 1: return SubscriptionCatalog.solo
        case 2: return SubscriptionCatalog.duet
        default: return SubscriptionCatalog.family
        }
    }

    // MARK: - Ceny

    /// Prawdę o cenie mówi App Store (waluta i podatek kupującego); cennik
    /// jest zapasem na brak sieci albo nieopublikowany produkt.
    private func price(for plan: SubscriptionPlan) -> String {
        subscriptions.product(for: plan)?.displayPrice ?? plan.fallbackPrice
    }

    private func select(_ plan: SubscriptionPlan) {
        guard plan != selected else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            selected = plan
        }
    }

    // MARK: - Stopka i zakup

    private var footer: some View {
        VStack(spacing: 10) {
            // Wynik zakupu i „Przywróć zakupy" ląduje TU, przy przyciskach,
            // które go wywołały — nie gdzieś w treści, gdzie trzeba by go
            // szukać przewijaniem.
            if let notice {
                Text(notice)
                    .font(.system(size: 12.5))
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.scMuted(scheme))
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }

            AssistantPrimaryButton(
                action: AssistantCardAction(title: purchaseTitle, icon: "arrow.right") { buy() },
                isBusy: subscriptions.isPurchasing
            )
            .disabled(!canPurchase)
            .opacity(canPurchase ? 1 : 0.5)

            // WARUNKI ODNOWIENIA MUSZĄ STAĆ PRZY PRZYCISKU ZAKUPU, a nie tylko
            // w regulaminie — App Store 3.1.2 wymaga, żeby przed pobraniem
            // pieniędzy widać było okres, automatyczne odnawianie, miejsce
            // rezygnacji oraz regulamin i politykę prywatności.
            Text(Self.renewalTerms)
                .font(.system(size: 11.5))
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.scFaint(scheme))
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            PlanLegalLinks(
                isRestoring: isRestoring,
                onTerms: { showTerms = true },
                onPrivacy: { showPrivacy = true },
                onRestore: restore
            )
        }
        .animation(.smooth(duration: 0.22), value: notice)
    }

    /// Skrót warunków odnowienia pod przyciskiem zakupu. Pełne brzmienie
    /// („co najmniej 24 godziny przed końcem okresu", „usunięcie aplikacji
    /// nie anuluje") stoi w regulaminie (sekcja 5) i w opisie produktu w App
    /// Store Connect — ta linijka ma je skracać, nigdy się z nimi kłócić.
    private static let renewalTerms =
        "Odnawia się automatycznie co miesiąc, dopóki nie anulujesz w Ustawieniach iOS. "
        + "Opłatę pobiera Apple."

    /// Zakup wolno zacząć dopiero, gdy SERWER potwierdzi, że umie
    /// zweryfikować transakcję. Inaczej Apple pobrałoby pieniądze za dostęp,
    /// którego nie mielibyśmy jak nadać.
    private var canPurchase: Bool {
        SubscriptionCatalog.purchasesEnabled
            && subscriptions.purchasesEnabled
            && subscriptions.product(for: selected) != nil
            && !subscriptions.isPurchasing
            && selected.id != currentPlan?.id
    }

    private var purchaseTitle: String {
        // Ten sam plan drugi raz nie ma czego odblokować.
        if selected.id == currentPlan?.id { return "To Twój obecny plan" }
        guard canPurchase else { return "Zakupy wkrótce" }
        return "Plan \(selected.name) · \(price(for: selected)) / mies."
    }

    private func buy() {
        guard let product = subscriptions.product(for: selected) else { return }
        // Kolejka do stałej PRZED zadaniem: arkusz da się zsunąć palcem, gdy
        // zgłoszenie do serwera jeszcze trwa, a wtedy odczyt ze środowiska
        // trafiłby w domyślną kolejkę podglądu i potwierdzenie przepadłoby.
        let toasts = toasts
        Task {
            switch await subscriptions.purchase(product) {
            case .purchased:
                // Serwer JUŻ potwierdził — inaczej nie byłoby `.purchased`.
                //
                // Potwierdzenie idzie do toastu, bo `notice` znikało razem
                // z arkuszem, który sam je zamykał: użytkownik wracał właśnie
                // z systemowego okna Apple, wodząc wzrokiem za tamtym oknem
                // w dół, a jedyne „udało się" mieszkało w stopce, której
                // zostało 1,2 s życia. Kapsuła przeżywa `dismiss()` i ląduje
                // nad „Asystent i plan" już w nowym stanie. Własnej haptyki
                // nie ma tu po co trzymać — `SCToastHost` bije swoją.
                // „Plan" bez dopowiedzenia myliłoby się z zakładką Plan
                // (tygodnia). Mówimy o tym, co się realnie odblokowało.
                toasts.success("Asystent odblokowany", "Pytania są już dostępne dla całego domu.")
                onPurchased?()
                dismiss()
            case .pending:
                // „Poproś o zakup" (Chmura Rodzinna) albo zgłoszenie, którego
                // serwer chwilowo nie przyjął. Pieniądze mogły już pójść, więc
                // nie mówimy „nie udało się".
                notice = subscriptions.lastError
                    ?? "Zakup czeka na zatwierdzenie. Plan włączy się sam, gdy przejdzie."
            case .cancelled:
                notice = nil
            case let .failed(message):
                notice = message
            }
        }
    }

    private func restore() {
        guard !isRestoring else { return }
        isRestoring = true
        Task {
            await subscriptions.restore()
            notice = subscriptions.lastError ?? "Sprawdziliśmy zakupy w App Store."
            isRestoring = false
        }
    }
}

// MARK: - Kafel wyboru

/// Kafel planu: nazwa, dla ilu osób, cena. Trzy obok siebie mieszczą się
/// na jednym ekranie, więc wybór nie wymaga przewijania.
struct PlanTile: View {
    let plan: SubscriptionPlan
    let price: String
    let isSelected: Bool
    /// Kupiony — z serwera.
    let isCurrent: Bool
    /// Pasuje do liczby domowników — podpowiedź, nie stan zakupu.
    let isSuggested: Bool
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var scheme

    private static let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Text(plan.name)
                        .font(.system(size: 15, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    // To samo kółko co przy celu i diecie w Ustawieniach,
                    // tylko mniejsze — trzy kafle stoją w jednym rzędzie.
                    SCRadioMark(isOn: isSelected, size: 18)
                }
                Text(plan.seatsLabel)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(price)
                    .font(.system(size: 14.5, weight: .bold))
                    .tracking(-0.3)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? SCPalette.terracotta : Color.scLabel(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 6)

                // Stała wysokość znacznika we wszystkich kaflach — rząd trzech
                // kafli nie może skakać zależnie od tego, który coś niesie.
                tag
                    .frame(height: 16, alignment: .leading)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Self.shape.fill(isSelected ? Color.scAccentTint(scheme) : Color.scTileBg(scheme)))
            .overlay(
                Self.shape.strokeBorder(
                    isSelected ? SCPalette.terracotta : Color.scTileStroke(scheme),
                    lineWidth: isSelected ? 1.5 : 1
                )
            )
            .contentShape(Self.shape)
        }
        .buttonStyle(PlanPressButtonStyle())
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plan \(plan.name), \(plan.seatsLabel), \(price) miesięcznie"
            + (isCurrent ? ", Twój obecny plan" : isSuggested ? ", polecany dla Twojego domu" : ""))
        .accessibilityAddTraits(traits)
    }

    @ViewBuilder
    private var tag: some View {
        if isCurrent {
            Label("Twój plan", systemImage: "checkmark.seal.fill")
                .font(.system(size: 10.5, weight: .bold))
                .labelStyle(PlanTagLabelStyle())
                .foregroundStyle(SCPalette.sage)
        } else if isSuggested {
            Label("Polecany", systemImage: "sparkles")
                .font(.system(size: 10.5, weight: .bold))
                .labelStyle(PlanTagLabelStyle())
                .foregroundStyle(SCPalette.terracotta)
        } else {
            Color.clear
        }
    }

    private var traits: AccessibilityTraits {
        var result: AccessibilityTraits = .isButton
        if isSelected { _ = result.insert(.isSelected) }
        return result
    }
}

/// Znacznik kafla planu: glif i słowo w jednym rzędzie, ciasno.
private struct PlanTagLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
                .font(.system(size: 9, weight: .bold))
            configuration.title
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Karta szczegółów

/// Co daje wybrany plan. Liczby przeliczają się w miejscu, a paski
/// pokazują pulę na tle największego planu — widać, o ile rośnie, bez
/// odejmowania w głowie. Na dole to, co jest w KAŻDYM planie, żeby wybór
/// dotyczył tylko wielkości puli.
struct PlanDetailCard: View {
    let plan: SubscriptionPlan
    let price: String
    /// Kupiony — z serwera.
    let isCurrent: Bool
    /// „polecany dla 2 osób” — podpowiedź z liczby domowników, albo `nil`.
    let suggestion: String?

    @Environment(\.colorScheme) private var scheme

    /// Największy plan wyznacza 100 % paska.
    private static let maxMessages = SubscriptionCatalog.all.map(\.messages).max() ?? 1
    private static let maxPlans = SubscriptionCatalog.all.map(\.plans).max() ?? 1

    var body: some View {
        AssistantSurfaceCard {
            VStack(alignment: .leading, spacing: 0) {
                head
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 14)

                VStack(alignment: .leading, spacing: 14) {
                    quotaRow("Wiadomości", value: plan.messages, max: Self.maxMessages, noun: "wiadomości")
                    quotaRow("Zapisy planu", value: plan.plans, max: Self.maxPlans, noun: "\(Self.savesNoun(Self.perWeek(plan.plans))) planu")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .overlay(alignment: .top) { rule }

                Text(plan.audience)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { rule }

                VStack(alignment: .leading, spacing: 8) {
                    included("Wspólna pula dla całego domu")
                    included("Odnawia się co miesiąc, anulujesz w Ustawieniach iOS")
                    included("Rozmowy i zapisane plany zostają po wygaśnięciu")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .overlay(alignment: .top) { rule }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: plan.id)
    }

    private var head: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("Plan \(plan.name)".uppercased())
                    if isCurrent {
                        Text("· Twój plan".uppercased())
                            .foregroundStyle(SCPalette.sage)
                    } else if let suggestion {
                        Text("· \(suggestion)".uppercased())
                            .foregroundStyle(SCPalette.terracotta.opacity(0.75))
                    }
                }
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(SCPalette.terracotta)
                .lineLimit(1)
                .contentTransition(.opacity)
                Text(plan.seatsLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.scMuted(scheme))
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(price)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.6)
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))
                    .contentTransition(.numericText())
                Text("/ mies.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.scFaint(scheme))
            }
            .lineLimit(1)
        }
    }

    /// Jedna pula: etykieta, liczba, pasek na tle największego planu i
    /// przeliczenie na tydzień. Liczba i pasek animują się razem.
    private func quotaRow(_ label: String, value: Int, max: Int, noun: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.scLabel(scheme))
                Spacer(minLength: 0)
                Text("ok. \(Self.perWeek(value)) \(noun) w tygodniu")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Color.scFaint(scheme))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                Text("\(value)")
                    .font(.system(size: 18, weight: .bold))
                    .tracking(-0.4)
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))
                    .contentTransition(.numericText())
                    .frame(minWidth: 28, alignment: .trailing)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.scBarTrack(scheme))
                    Capsule()
                        .fill(SCPalette.terracotta)
                        .frame(width: geometry.size.width * CGFloat(value) / CGFloat(Swift.max(1, max)))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) miesięcznie")
    }

    private func included(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(SCPalette.sage)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.scSageTint(scheme)))
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            Text(text)
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundStyle(Color.scLabel(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rule: some View {
        Rectangle().fill(Color.scRule(scheme)).frame(height: 1)
    }

    /// Limit miesięczny na tydzień, przez średnią długość miesiąca.
    static func perWeek(_ monthly: Int) -> Int {
        Swift.max(1, Int((Double(monthly) / 4.345).rounded()))
    }

    /// „zapisy" dla 2–4 (poza 12–14), inaczej „zapisów".
    static func savesNoun(_ count: Int) -> String {
        let unit = count % 10
        let tens = count % 100
        let isFew = (2...4).contains(unit) && !(12...14).contains(tens)
        return isFew ? "zapisy" : "zapisów"
    }
}

#Preview("Wybierz plan") {
    PlansSheet()
}
