import StoreKit
import SwiftUI

/// „Asystent i plan" — spokojny dom całej sprawy z subskrypcją.
///
/// DLACZEGO W USTAWIENIACH, A NIE TYLKO W ASYSTENCIE. Decyzja z 4.09.2026:
/// aplikacja odzywa się o pieniądzach z własnej inicjatywy dokładnie raz, w
/// momencie wyczerpania puli, i to jedną linijką. Cała reszta — stan planu,
/// zużycie, oferta — leży tutaj i czeka, aż ktoś sam po nią przyjdzie.
/// Ten ekran zamyka też wymóg App Store 3.1.2(a): stan subskrypcji musi dać
/// się zobaczyć w aplikacji, a nie tylko w ustawieniach systemu.
///
/// Cztery stany, ta sama kolejność w każdym (plakietka → zużycie → reszta),
/// żeby powrót na ekran nie wymagał ponownego czytania:
///   • `trial`   — pula próbna, dwa pierścienie i oferta;
///   • `paying`  — płacący: zużycie domu i „Zarządzaj subskrypcją";
///   • `member`  — domownik: to samo zużycie, ale zamiast oferty informacja,
///                 kto opłaca. Ta osoba MA pełny dostęp i nic nie dokupuje;
///   • `granted` — nadanie od nas, bez oferty i bez zarządzania.
struct PlanAccessSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @Environment(\.sessionStore) private var sessionStore

    @State private var usage: AgentUsageDTO?
    @State private var isLoading = true
    /// Awaryjny egzemplarz na wypadek ekranu bez sesji — bez klienta, więc
    /// niczego nie kupi. Normalnie używamy tego z `SessionStore`, bo tylko on
    /// żyje wystarczająco długo, żeby złapać odnowienie subskrypcji.
    @State private var fallbackSubscriptions = SubscriptionStore()
    @State private var selected = SubscriptionCatalog.recommended
    @State private var notice: String?
    @State private var showTerms = false
    @State private var showPrivacy = false

    /// NIE `State` — ta nazwa wewnątrz `View` przesłania `SwiftUI.State`
    /// i psuje każde `@State` w tym typie.
    enum AccessState { case trial, paying, member, granted }

    private var subscriptions: SubscriptionStore {
        sessionStore.subscriptionStore ?? fallbackSubscriptions
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                SCPageBackground(scheme: scheme).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        EditorialSheetHeader(eyebrow: "Konto", title: "Asystent i plan") {
                            dismiss()
                        }

                        if let usage {
                            badge(for: usage)
                                .padding(.top, 12)

                            switch accessState(for: usage) {
                            case .trial: trialBody(usage)
                            case .paying: payingBody(usage)
                            case .member: memberBody(usage)
                            case .granted: grantedBody(usage)
                            }
                        } else if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 48)
                        } else {
                            Text("Nie udało się pobrać stanu planu. Spróbuj ponownie za chwilę.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.scMuted(scheme))
                                .padding(.top, 24)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, footerReserve)
                }
                .scrollIndicators(.hidden)

                if let usage, accessState(for: usage) == .trial {
                    AssistantStickyFooter {
                        SCSoftButton(
                            title: purchaseTitle,
                            leadingIcon: "sparkles",
                            trailingIcon: nil,
                            isEnabled: canPurchase,
                            isLoading: subscriptions.isPurchasing
                        ) {
                            buy()
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showTerms) {
            LegalDocumentSheet(title: "Regulamin") { TermsOfServiceContent() }
        }
        .sheet(isPresented: $showPrivacy) {
            LegalDocumentSheet(title: "Polityka prywatności") { PrivacyPolicyContent() }
        }
        .onChange(of: subscriptions.state) { _, _ in
            // TRANSAKCJA POTRAFI DOJŚĆ, GDY ARKUSZ JEST OTWARTY: odnowienie,
            // zatwierdzone „Poproś o zakup", zgłoszenie ponowione po powrocie
            // sieci. `SubscriptionStore` odświeża wtedy swój stan sam, a ten
            // ekran do tej poprawki został na danych sprzed zakupu — człowiek
            // patrzył na „próba wyczerpana" mając już opłacony plan.
            Task { usage = await sessionStore.agentStore?.loadUsage() }
        }
        .task {
            usage = await sessionStore.agentStore?.loadUsage()
            isLoading = false
            // Najpierw pytamy serwer, czy zakupy są w ogóle włączone —
            // przycisk ma być nieaktywny, dopóki nie umiemy potwierdzić
            // płatności, a nie dopiero po jej pobraniu.
            await subscriptions.refreshState()
            await subscriptions.loadProducts()
        }
    }

    private var footerReserve: CGFloat {
        guard let usage, accessState(for: usage) == .trial else { return 28 }
        return 120
    }

    // MARK: - Który stan

    private func accessState(for usage: AgentUsageDTO) -> AccessState {
        if usage.isTrial { return .trial }
        guard usage.source == "SUBSCRIPTION" else { return .granted }
        return usage.isThePayer ? .paying : .member
    }

    /// Etykieta plakietki. Osobno od widoku i bez domknięcia: `switch`
    /// w wielolinijkowym domknięciu z wnioskowaną krotką to klasyczny powód
    /// „unable to infer complex closure return type".
    private func badgeText(_ usage: AgentUsageDTO) -> String {
        switch accessState(for: usage) {
        case .trial:
            return "Dostęp próbny"
        case .granted:
            return "Plan domu"
        case .paying, .member:
            guard let product = usage.product else { return "Plan domu" }
            return "Plan " + product
        }
    }

    private func badgeColor(_ usage: AgentUsageDTO) -> Color {
        switch accessState(for: usage) {
        case .trial: return SCPalette.butter
        case .granted: return SCPalette.indigo
        case .paying, .member: return SCPalette.sage
        }
    }

    private func badge(for usage: AgentUsageDTO) -> some View {
        PlanBadge(label: badgeText(usage), color: badgeColor(usage))
    }

    // MARK: - 1. Pula próbna

    @ViewBuilder
    private func trialBody(_ usage: AgentUsageDTO) -> some View {
        PlanSectionLabel("Pula próbna")
            .padding(.top, 20)

        AssistantSurfaceCard {
            HStack(spacing: 0) {
                trialRing(title: "Wiadomości", quota: usage.messages)
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(width: 1)
                    .padding(.vertical, 12)
                trialRing(title: "Zapisy planu", quota: usage.plans)
            }
        }

        // Zdanie o SKUTKU, nie o sprzedaży: zdejmuje lęk („stracę plany?"),
        // zamiast go budować.
        Text("Kiedy pula się skończy, rozmowy i zapisane plany zostają w aplikacji. Nowe wiadomości wracają z planem.")
            .font(.system(size: 13.5))
            .lineSpacing(3)
            .foregroundStyle(Color.scMuted(scheme))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 11)

        PlanSectionLabel("Plany · miesięcznie")
            .padding(.top, 22)

        planCarousel

        // Wymóg App Store i uczciwość wobec kogoś, kto już kiedyś kupił.
        // Drobne i ciche — to nie jest element sprzedażowy.
        HStack(spacing: 14) {
            Button("Przywróć zakupy") {
                Task {
                    await subscriptions.restore()
                    notice = subscriptions.lastError ?? "Sprawdziliśmy zakupy w App Store."
                }
            }
            Button("Regulamin") { showTerms = true }
            Button("Prywatność") { showPrivacy = true }
        }
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(SCPalette.terracotta)
        .padding(.horizontal, 4)
        .padding(.top, 16)

        if let notice {
            Text(notice)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.scMuted(scheme))
                .padding(.horizontal, 4)
                .padding(.top, 8)
        }

        // Dwa zdania stopki w JEDNYM kontenerze, a nie obok siebie: `@ViewBuilder`
        // przyjmuje najwyżej dziesięcioro dzieci, a ten był już przy dziewięciu.
        // Przekroczenie limitu daje „unable to infer complex closure return
        // type" wskazane kilkadziesiąt linii obok właściwego miejsca.
        VStack(spacing: 10) {
            Text("Liczba osób to podpowiedź, nie limit. Pula jest wspólna dla całego domu.")
                .font(.system(size: 12))
            // WARUNKI ODNOWIENIA MUSZĄ STAĆ PRZY PRZYCISKU ZAKUPU, a nie tylko
            // w regulaminie — App Store 3.1.2 wymaga, żeby przed pobraniem
            // pieniędzy widać było długość okresu, cenę, automatyczne
            // odnawianie i miejsce, w którym się je wyłącza. Brak tego zdania
            // to jedna z częstszych przyczyn odrzucenia przy pierwszej recenzji.
            Text(Self.renewalTerms)
                .font(.system(size: 11.5))
        }
        .lineSpacing(2)
        .multilineTextAlignment(.center)
        .foregroundStyle(Color.scFaint(scheme))
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
        .padding(.top, 14)
    }

    /// Jedno miejsce na warunki odnowienia — powtórzone w regulaminie (sekcja 5)
    /// i w opisie produktu w App Store Connect. Trzy kopie muszą się zgadzać.
    private static let renewalTerms =
        "Subskrypcja odnawia się automatycznie co miesiąc, dopóki jej nie anulujesz "
        + "co najmniej 24 godziny przed końcem okresu. Opłatę pobiera Apple. "
        + "Możesz zrezygnować w Ustawieniach iOS → Apple ID → Subskrypcje; "
        + "usunięcie aplikacji nie anuluje subskrypcji."

    private func trialRing(title: String, quota: AgentQuotaDTO) -> some View {
        VStack(spacing: 9) {
            PlanRing(remaining: quota.remaining, limit: quota.limit, color: SCPalette.butter, size: 84)
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.scLabel(scheme))
                Text("\(quota.used) z \(quota.limit) użyte")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Color.scFaint(scheme))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): zostało \(quota.remaining) z \(quota.limit)")
    }

    /// Karuzela planów: karty wystają poza krawędź, więc widać, że jest ich
    /// więcej. Żadnej nie wyróżniamy etykietą „polecany" — to lista do
    /// przejrzenia, nie ranking.
    private var selectedIndex: Int {
        SubscriptionCatalog.all.firstIndex(where: { $0.id == selected.id }) ?? 0
    }

    private var planCarousel: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(SubscriptionCatalog.all) { plan in
                        PlanCarouselCard(
                            plan: plan,
                            price: subscriptions.product(for: plan)?.displayPrice ?? plan.fallbackPrice,
                            isSelected: plan.id == selected.id
                        )
                        .id(plan.id)
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.18)) { selected = plan }
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)

            PlanCarouselDots(count: SubscriptionCatalog.all.count, active: selectedIndex)
                .padding(.top, 12)
        }
    }

    // MARK: - 2. Płacący

    @ViewBuilder
    private func payingBody(_ usage: AgentUsageDTO) -> some View {
        sharedUsage(usage, color: SCPalette.sage)

        PlanSectionLabel("Subskrypcja")
            .padding(.top, 20)

        // CO SERWER MÓWI O TEJ SUBSKRYPCJI. Telefon pobierał ten stan i nie
        // pokazywał z niego ANI JEDNEGO pola — więc nieudana płatność (łaska
        // płatnicza), wyłączone odnawianie i ręczne odebranie dostępu przez
        // obsługę były na tym ekranie niewidoczne. Człowiek dowiadywał się
        // o nich dopiero wtedy, gdy asystent przestawał odpowiadać.
        if let line = subscriptionStatusLine {
            Text(line)
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .foregroundStyle(Color.scMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.top, 8)
        }

        AssistantSurfaceCard {
            Button {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Zarządzaj subskrypcją")
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(SCPalette.terracotta)
                        Text("Otworzy się w Ustawieniach iOS")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.scFaint(scheme))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.scFaint(scheme))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
    }

    /// Jedno zdanie o subskrypcji tej osoby, złożone z tego, co oddaje serwer.
    /// Kolejność jest kolejnością pilności: blokada obsługi, łaska płatnicza,
    /// wyłączone odnawianie, zwykłe odnowienie.
    private var subscriptionStatusLine: String? {
        guard let sub = subscriptions.state?.subscriptions.first(where: { $0.alive })
            ?? subscriptions.state?.subscriptions.first
        else { return nil }

        if let hold = sub.operatorHold {
            return hold.isEmpty
                ? "Dostęp został wstrzymany przez obsługę. Napisz do nas, żeby to wyjaśnić."
                : "Dostęp został wstrzymany przez obsługę: \(hold)"
        }
        if let grace = Self.dayMonth(sub.graceExpiresAt), sub.status == "GRACE" {
            return "Ostatnia płatność się nie powiodła. App Store spróbuje ponownie — asystent działa do \(grace)."
        }
        if sub.autoRenews == false, let end = Self.dayMonth(sub.expiresAt) {
            return "Odnawianie jest wyłączone. Plan działa do \(end)."
        }
        if let end = Self.dayMonth(sub.expiresAt) {
            return sub.alive
                ? "Odnawia się \(end)."
                : "Plan wygasł \(end)."
        }
        return nil
    }

    /// „3 października" z daty ISO od serwera; `nil`, gdy nie da się odczytać.
    ///
    /// `withFractionalSeconds` jest konieczne: serwer oddaje `toISOString()`,
    /// czyli z milisekundami, a goły `ISO8601DateFormatter` zwraca wtedy `nil`
    /// — zdanie o stanie subskrypcji po prostu by się nie pokazało.
    private static let isoParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMMM"
        return formatter
    }()

    private static func dayMonth(_ iso: String?) -> String? {
        guard let iso, let date = isoParser.date(from: iso) else { return nil }
        return dayMonthFormatter.string(from: date)
    }

    // MARK: - 3. Domownik

    @ViewBuilder
    private func memberBody(_ usage: AgentUsageDTO) -> some View {
        sharedUsage(usage, color: SCPalette.sage)

        PlanSectionLabel("Kto opłaca")
            .padding(.top, 20)

        AssistantSurfaceCard {
            HStack(spacing: 13) {
                payerAvatar(usage.payerName ?? "?")
                VStack(alignment: .leading, spacing: 2) {
                    Text(usage.payerName ?? "Ktoś z domu")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.scLabel(scheme))
                    Text(payerSubtitle(usage))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            // Najważniejsze zdanie na tym ekranie dla domownika: NIE musisz
            // nic kupować. Bez niego widok wygląda jak zapowiedź opłaty.
            Text("Pula jest wspólna — masz do niej pełny dostęp i nie musisz nic dokupować.")
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .foregroundStyle(Color.scMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlay(alignment: .top) { Rectangle().fill(Color.scRule(scheme)).frame(height: 1) }
        }
    }

    /// „Plan Rodzina · dom Kowalskich". Osobno, bo złożenie tablicy opcjonali
    /// z `compactMap` i `joined` w środku `Text(...)` potrafi położyć
    /// sprawdzanie typów SwiftUI na łopatki.
    private func payerSubtitle(_ usage: AgentUsageDTO) -> String {
        var parts: [String] = []
        if let product = usage.product { parts.append("Plan \(product)") }
        if let household = sessionStore.currentHouseholdName { parts.append(household) }
        return parts.joined(separator: " · ")
    }

    private func payerAvatar(_ name: String) -> some View {
        Group {
            // Dopasowanie po imieniu, bo serwer oddaje imię płatnika, a nie
            // jego identyfikator — celowo, żeby nie wydawać id osoby, której
            // pytający i tak nie potrzebuje. Przy dwóch osobach o tym samym
            // imieniu spadamy na inicjał i to jest w porządku.
            if let member = sessionStore.householdMembers.first(where: { $0.displayName == name }) {
                MemberAvatar(member: member, members: sessionStore.householdMembers, size: 38)
            } else {
                Circle()
                    .fill(Color.scSageTint(scheme))
                    .overlay(
                        Text(String(name.prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(SCPalette.sage)
                    )
                    .frame(width: 38, height: 38)
            }
        }
    }

    // MARK: - 4. Nadanie

    @ViewBuilder
    private func grantedBody(_ usage: AgentUsageDTO) -> some View {
        sharedUsage(usage, color: SCPalette.indigo, showMembers: false)

        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 14))
                .foregroundStyle(SCPalette.indigo)
                .padding(.top, 1)
            Text("Dostęp do asystenta jest nadany przez Scoffie. Nic nie płacisz w aplikacji.")
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .foregroundStyle(Color.scLabel(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.scIndigoTint(scheme)))
        .padding(.top, 20)
    }

    // MARK: - Wspólne zużycie (stany 2–4)

    @ViewBuilder
    private func sharedUsage(_ usage: AgentUsageDTO, color: Color, showMembers: Bool = true) -> some View {
        // Wyliczone przed widokiem: warunek z opcjonalem i `nil` w argumencie
        // to dokładnie ten rodzaj wyrażenia, na którym SwiftUI potrafi się
        // zaciąć przy sprawdzaniu typów.
        let members: [AgentUsageByUserDTO] = showMembers ? (usage.byUser ?? []) : []
        let membersDetail: String? = members.isEmpty
            ? nil
            : "Kto ile wykorzystał w tym okresie:"

        PlanSectionLabel("Ten okres · pula wspólna")
            .padding(.top, 20)

        VStack(spacing: 10) {
            PlanUsageCard(
                eyebrow: "Wiadomości",
                quota: usage.messages,
                color: color,
                detail: membersDetail,
                members: members
            )
            PlanUsageCard(
                eyebrow: "Zapisy planu",
                quota: usage.plans,
                color: color,
                detail: "Każde „Dodaj do planu” z rozmowy.",
                members: []
            )
        }

        Text("Pula odnawia się \(usage.resetsAt.map(AssistantUsageSheet.resetLabel) ?? "przy kolejnej opłacie").")
            .font(.system(size: 13))
            .foregroundStyle(Color.scFaint(scheme))
            .padding(.horizontal, 4)
            .padding(.top, 11)
    }

    // MARK: - Zakup

    /// Zakup wolno zacząć dopiero, gdy SERWER potwierdzi, że umie
    /// zweryfikować transakcję. Inaczej Apple pobrałoby pieniądze za dostęp,
    /// którego nie mielibyśmy jak nadać.
    private var canPurchase: Bool {
        SubscriptionCatalog.purchasesEnabled
            && subscriptions.purchasesEnabled
            && subscriptions.product(for: selected) != nil
            && !subscriptions.isPurchasing
    }

    private var purchaseTitle: String {
        canPurchase ? "Wybierz plan" : "Zakupy wkrótce"
    }

    private func buy() {
        guard let product = subscriptions.product(for: selected) else { return }
        Task {
            switch await subscriptions.purchase(product) {
            case .purchased:
                // Serwer JUŻ potwierdził — inaczej nie byłoby `.purchased`.
                notice = "Dziękujemy! Plan jest włączony."
                usage = await sessionStore.agentStore?.loadUsage()
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
}

// MARK: - Elementy wspólne

/// Plakietka stanu dostępu. Jedno słowo odpowiada na pytanie, po które ktoś
/// tu wszedł: „co ja właściwie mam?".
struct PlanBadge: View {
    let label: String
    let color: Color

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Capsule().fill(color.opacity(scheme == .dark ? 0.15 : 0.10)))
            .lineLimit(1)
    }
}

struct PlanSectionLabel: View {
    let text: String

    @Environment(\.colorScheme) private var scheme

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(Color.scFaint(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.bottom, 9)
    }
}

/// Pierścień z liczbą, która ZOSTAŁA — nie z tą, która poszła. Minimum 3 %
/// wypełnienia, żeby pusta pula nie wyglądała na błąd ładowania.
struct PlanRing: View {
    let remaining: Int
    let limit: Int
    let color: Color
    var size: CGFloat = 92

    @Environment(\.colorScheme) private var scheme

    private var fraction: Double {
        guard limit > 0 else { return 0 }
        return max(0.03, min(1, Double(remaining) / Double(limit)))
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.scBarTrack(scheme), lineWidth: size * 0.1)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(remaining)")
                    .font(.system(size: size > 88 ? 26 : 21, weight: .bold))
                    .tracking(-0.6)
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))
                Text("ZOSTAŁO")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.scMuted(scheme))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Karta zużycia: pierścień + opis, opcjonalnie rozkład na domowników.
/// Pula jest wspólna, więc ktoś zawsze pyta „kto to zużył".
struct PlanUsageCard: View {
    let eyebrow: String
    let quota: AgentQuotaDTO
    let color: Color
    var detail: String?
    var members: [AgentUsageByUserDTO] = []

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AssistantSurfaceCard {
            HStack(spacing: 15) {
                PlanRing(remaining: quota.remaining, limit: quota.limit, color: color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(color)
                    Text("\(quota.used) z \(quota.limit) w tym okresie")
                        .font(.system(size: 16, weight: .bold))
                        .tracking(-0.35)
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(scheme))
                    if let detail {
                        Text(detail)
                            .font(.system(size: 12.5))
                            .lineSpacing(2)
                            .foregroundStyle(Color.scMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(eyebrow): zostało \(quota.remaining) z \(quota.limit)")

            if !members.isEmpty {
                VStack(spacing: 9) {
                    ForEach(members, id: \.userId) { member in
                        PlanMemberBar(member: member, total: quota.used, color: color)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .overlay(alignment: .top) { Rectangle().fill(Color.scRule(scheme)).frame(height: 1) }
            }
        }
    }
}

struct PlanMemberBar: View {
    let member: AgentUsageByUserDTO
    let total: Int
    let color: Color

    @Environment(\.colorScheme) private var scheme
    @Environment(\.sessionStore) private var sessionStore

    var body: some View {
        HStack(spacing: 9) {
            if let profile = sessionStore.householdMembers.first(where: { $0.id == member.userId }) {
                MemberAvatar(member: profile, members: sessionStore.householdMembers, size: 20)
            } else {
                Circle()
                    .fill(color.opacity(0.15))
                    .overlay(
                        Text(String(member.displayName.prefix(1)).uppercased())
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(color)
                    )
                    .frame(width: 20, height: 20)
            }
            Text(HouseholdMemberStyle.shortName(member.displayName))
                .font(.system(size: 12.5))
                .foregroundStyle(Color.scLabel(scheme))
                .frame(width: 58, alignment: .leading)
                .lineLimit(1)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.scBarTrack(scheme))
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * (total > 0 ? Double(member.messages) / Double(total) : 0))
                }
            }
            .frame(height: 4)
            Text("\(member.messages)")
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.scMuted(scheme))
                .frame(width: 22, alignment: .trailing)
        }
    }
}

/// Karta planu w karuzeli. Cena z App Store, ilości z katalogu — te same,
/// które egzekwuje serwer (App Store 3.1.2(c)).
struct PlanCarouselCard: View {
    let plan: SubscriptionPlan
    let price: String
    let isSelected: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text("Plan \(plan.name)")
                        .font(.system(size: 15.5, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(scheme))
                    Spacer(minLength: 0)
                    ZStack {
                        Circle()
                            .fill(isSelected ? SCPalette.terracotta : Color.clear)
                        if !isSelected {
                            Circle().stroke(Color.scRule(scheme), lineWidth: 1.5)
                        }
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(Color.scCanvas(scheme))
                        }
                    }
                    .frame(width: 20, height: 20)
                }
                Text(plan.seatsLabel)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.scFaint(scheme))
                    .padding(.top, 2)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(price)
                        .font(.system(size: 25, weight: .bold))
                        .tracking(-0.8)
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(scheme))
                    Text("/ mies.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.scFaint(scheme))
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 8) {
                quantity(plan.messages, "wiadomości")
                quantity(plan.plans, "zapisów planu")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Color.scRule(scheme)).frame(height: 1) }
        }
        .frame(width: 232, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isSelected ? Color.scAccentTint(scheme) : Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? SCPalette.terracotta : Color.scTileStroke(scheme),
                        lineWidth: isSelected ? 1.5 : 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plan \(plan.name), \(plan.seatsLabel), \(price) miesięcznie, \(plan.quantityLine)")
        .accessibilityAddTraits(traits)
    }

    private var traits: AccessibilityTraits {
        var result: AccessibilityTraits = .isButton
        if isSelected { result.insert(.isSelected) }
        return result
    }

    private func quantity(_ value: Int, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("\(value)")
                .font(.system(size: 15, weight: .bold))
                .tracking(-0.3)
                .monospacedDigit()
                .foregroundStyle(Color.scLabel(scheme))
                .frame(width: 26, alignment: .leading)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.scMuted(scheme))
        }
    }
}

struct PlanCarouselDots: View {
    let count: Int
    let active: Int

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == active ? SCPalette.terracotta : Color.scBarTrack(scheme))
                    .frame(width: index == active ? 16 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

/// Plakietka puli w nagłówku rozmowy — kropki i liczba, bez wykrzyknika.
///
/// Kropki, a nie sam licznik, bo „2 z 10" każe liczyć, a dwie kropki widać
/// bez czytania. Barwa zmienia się dopiero przy zerze i nawet wtedy nie jest
/// alarmem: pole tekstowe zostaje aktywne, a plany są jedno stuknięcie dalej.
struct AssistantQuotaPips: View {
    let remaining: Int

    @Environment(\.colorScheme) private var scheme

    private var isEmpty: Bool { remaining <= 0 }
    private var color: Color { isEmpty ? SCPalette.terracotta : SCPalette.butter }

    private var label: String {
        if isEmpty { return "pula wyczerpana" }
        return remaining == 1 ? "1 wiadomość" : "\(remaining) wiadomości"
    }

    var body: some View {
        HStack(spacing: 7) {
            if !isEmpty {
                HStack(spacing: 3.5) {
                    ForEach(0..<min(5, remaining), id: \.self) { _ in
                        Circle().fill(color).frame(width: 6, height: 6)
                    }
                }
            }
            Text(label)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.leading, isEmpty ? 11 : 10)
        .padding(.trailing, 11)
        .frame(height: 28)
        .background(Capsule().fill(color.opacity(scheme == .dark ? 0.15 : 0.10)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isEmpty
            ? "Pula wiadomości na próbę wyczerpana"
            : "Zostało \(remaining) wiadomości na próbę")
    }
}
