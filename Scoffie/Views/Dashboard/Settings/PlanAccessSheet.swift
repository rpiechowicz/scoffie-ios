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
/// Ten sam arkusz otwiera „Limity asystenta" z rozmowy — limity i plan to
/// jedna sprawa i jedno miejsce, a nie dwa ekrany z tymi samymi liczbami.
///
/// Odpowiada na „co mam?": stan, pula i jeden wiersz wejścia do planów.
/// Wybór planu ma własny arkusz (`PlansSheet`), który wjeżdża NA ten —
/// karuzela chowała dwa z trzech planów i kazała porównywać ceny kawałkami.
///
/// Cztery stany, ta sama kolejność w każdym (plakietka → zużycie → reszta),
/// żeby powrót na ekran nie wymagał ponownego czytania:
///   • `trial`   — pula próbna, dwa pierścienie i wejście do planów;
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
    /// „Wybierz plan" — arkusz wyboru NA tym arkuszu, nie zamiast niego.
    @State private var showsPlans = false
    @State private var showTerms = false
    @State private var showPrivacy = false
    /// Wynik „Przywróć zakupy" — przy odnośniku, który go wywołał.
    @State private var notice: String?
    @State private var isRestoring = false

    /// NIE `State` — ta nazwa wewnątrz `View` przesłania `SwiftUI.State`
    /// i psuje każde `@State` w tym typie.
    enum AccessState { case trial, paying, member, granted }

    private var subscriptions: SubscriptionStore {
        sessionStore.subscriptionStore ?? fallbackSubscriptions
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    EditorialSheetHeader(eyebrow: "Konto", title: "Asystent i plan") {
                        dismiss()
                    }
                    content
                }
                .padding(.horizontal, SCPageMetrics.horizontal)
                .padding(.top, 18)
                .padding(.bottom, 28)
                // Treść wjeżdża po wczytaniu, zamiast wskakiwać pod spinner.
                .animation(.smooth(duration: 0.3), value: usage)
            }
            .scrollIndicators(.hidden)
            .background(SCPageBackground(scheme: scheme).ignoresSafeArea())
            // Stopka jako wstawka w strefie bezpiecznej, nie warstwa nad
            // scrollem: treść dostaje dokładnie tyle miejsca, ile stopka
            // zajmuje, więc nic nie chowa się pod nią i nic nie jest ucięte.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let usage, accessState(for: usage) == .trial {
                    legalFooter
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showsPlans) {
            PlansSheet(onPurchased: {
                Task { usage = await sessionStore.agentStore?.loadUsage() }
            })
        }
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
            // Stan z serwera i ceny z App Store — wiersz „Wybierz plan"
            // pokazuje cenę „od", a arkusz planów otwiera się już z cenami.
            await subscriptions.refreshState()
            await subscriptions.loadProducts()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let usage {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    badge(for: usage)
                    if usage.isTrial {
                        // Próba nie odnawia się — to jedyna rzecz, którą
                        // trzeba wiedzieć obok plakietki.
                        Text("jednorazowo, bez odnowienia")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.scMuted(scheme))
                            .lineLimit(1)
                    }
                }
                .padding(.top, 12)

                switch accessState(for: usage) {
                case .trial: trialBody(usage)
                case .paying: payingBody(usage)
                case .member: memberBody(usage)
                case .granted: grantedBody(usage)
                }
            }
            .transition(.opacity.combined(with: .offset(y: 6)))
        } else if isLoading {
            ProgressView()
                .tint(SCPalette.terracotta)
                .frame(maxWidth: .infinity)
                .padding(.top, 64)
        } else {
            Text("Nie udało się pobrać stanu planu. Spróbuj ponownie za chwilę.")
                .font(.system(size: 14))
                .foregroundStyle(Color.scMuted(scheme))
                .padding(.top, 24)
        }
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
            .padding(.top, 24)

        AssistantSurfaceCard {
            HStack(spacing: 0) {
                trialRing(title: "Wiadomości", quota: usage.messages)
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(width: 1)
                    .padding(.vertical, 14)
                trialRing(title: "Zapisy planu", quota: usage.plans)
            }

            // Co zjada pulę — jedno zdanie zamiast tabeli zasad. To jedyna
            // rzecz, o którą ludzie pytają: „Zmień" to wiadomość, oglądanie
            // propozycji jest darmowe.
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.scFaint(scheme))
                Text("Liczy się każda wysłana wiadomość i każde „Dodaj do planu”. Oglądanie propozycji jest darmowe.")
                    .font(.system(size: 12.5))
                    .lineSpacing(2)
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Color.scRule(scheme)).frame(height: 1) }
        }

        // Zdanie o SKUTKU, nie o sprzedaży: zdejmuje lęk („stracę plany?"),
        // zamiast go budować.
        Text("Kiedy pula się skończy, rozmowy i zapisane plany zostają w aplikacji. Nowe wiadomości wracają z planem.")
            .font(.system(size: 13.5))
            .lineSpacing(3)
            .foregroundStyle(Color.scMuted(scheme))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 12)

        // Bez nagłówka „Plan" — planu jeszcze NIE MA i sekcja o nazwie
        // „Plan" sugerowała coś przeciwnego. Wiersz mówi wprost, co tu jest
        // do zrobienia.
        PlanSectionLabel("Plan miesięczny")
            .padding(.top, 26)

        plansEntry
    }

    private func trialRing(title: String, quota: AgentQuotaDTO) -> some View {
        // Wyczerpana pula schodzi na terakotę: przy zerze musztardowy
        // pierścień był prawie niewidoczny, a zero wyglądało na brak danych.
        let exhausted = quota.remaining <= 0
        return VStack(spacing: 11) {
            PlanRing(
                remaining: quota.remaining,
                limit: quota.limit,
                color: exhausted ? SCPalette.terracotta : SCPalette.butter,
                size: 100
            )
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scLabel(scheme))
                Text(exhausted ? "\(quota.limit) z \(quota.limit) · wyczerpane" : "\(quota.used) z \(quota.limit) użyte")
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(exhausted ? SCPalette.terracotta : Color.scFaint(scheme))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): zostało \(quota.remaining) z \(quota.limit)")
    }

    /// Wejście do planów — zwykły wiersz, jak w Ustawieniach. Cena „od"
    /// z App Store, a gdy jej jeszcze nie ma, z cennika.
    private var plansEntry: some View {
        AssistantSurfaceCard {
            Button {
                showsPlans = true
            } label: {
                HStack(spacing: 13) {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.scAccentTint(scheme))
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(SCPalette.terracotta)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Wybierz plan")
                            .font(.system(size: 15.5, weight: .semibold))
                            .tracking(-0.3)
                            .foregroundStyle(Color.scLabel(scheme))
                        Text(plansEntrySubtitle)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.scMuted(scheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.scFaint(scheme))
                }
                .padding(.leading, 15)
                .padding(.trailing, 14)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlanPressButtonStyle())
            .accessibilityHint("Otwiera wybór planu")
        }
    }

    private var plansEntrySubtitle: String {
        let solo = SubscriptionCatalog.solo
        let from = subscriptions.product(for: solo)?.displayPrice ?? solo.fallbackPrice
        let names = SubscriptionCatalog.all.map(\.name).joined(separator: ", ")
        return "Od \(from) / mies. · \(names) · wspólna pula domu"
    }

    /// Odnośniki prawne i „Przywróć zakupy" — App Store wymaga ich tam,
    /// gdzie mowa o subskrypcji, a przywrócenie jest uczciwością wobec
    /// kogoś, kto już kiedyś kupił.
    private var legalFooter: some View {
        AssistantStickyFooter {
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
            PlanLegalLinks(
                isRestoring: isRestoring,
                onTerms: { showTerms = true },
                onPrivacy: { showPrivacy = true },
                onRestore: restore
            )
        }
        .animation(.smooth(duration: 0.22), value: notice)
    }

    private func restore() {
        guard !isRestoring else { return }
        isRestoring = true
        Task {
            await subscriptions.restore()
            notice = subscriptions.lastError ?? "Sprawdziliśmy zakupy w App Store."
            usage = await sessionStore.agentStore?.loadUsage()
            isRestoring = false
        }
    }

    // MARK: - 2. Płacący

    @ViewBuilder
    private func payingBody(_ usage: AgentUsageDTO) -> some View {
        sharedUsage(usage, color: SCPalette.sage)

        PlanSectionLabel("Subskrypcja")
            .padding(.top, 20)

        // CO SERWER MÓWI O TEJ SUBSKRYPCJI. Nieudana płatność (łaska
        // płatnicza), wyłączone odnawianie i ręczne odebranie dostępu przez
        // obsługę muszą być tu widoczne — inaczej człowiek dowiaduje się
        // o nich dopiero wtedy, gdy asystent przestaje odpowiadać.
        if let line = subscriptionStatusLine {
            Text(line)
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .foregroundStyle(Color.scMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.bottom, 10)
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
                .contentShape(Rectangle())
            }
            .buttonStyle(PlanPressButtonStyle())
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

    /// „1 października" z ISO odnowienia puli; sam napis ISO, gdy nie da
    /// się sparsować.
    static func resetLabel(_ iso: String) -> String {
        guard let date = AgentStore.parseTimestamp(iso) else { return iso }
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

        Text("Pula odnawia się \(usage.resetsAt.map(Self.resetLabel) ?? "przy kolejnej opłacie").")
            .font(.system(size: 13))
            .foregroundStyle(Color.scFaint(scheme))
            .padding(.horizontal, 4)
            .padding(.top, 11)
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

/// Wiersz w karcie reaguje na dotyk lekkim przygaszeniem i skalą — wiersze
/// Ustawień robią to samo, a bez tego karta nie mówi, że jest przyciskiem.
struct PlanPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// Odnośniki pod treścią o subskrypcji: regulamin, prywatność, przywrócenie
/// zakupów. Przygaszone — nie konkurują z przyciskiem zakupu nad nimi.
struct PlanLegalLinks: View {
    var isRestoring: Bool = false
    let onTerms: () -> Void
    let onPrivacy: () -> Void
    let onRestore: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            Button("Regulamin", action: onTerms)
            separator
            Button("Prywatność", action: onPrivacy)
            separator
            Button(action: onRestore) {
                HStack(spacing: 5) {
                    if isRestoring {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Color.scMuted(scheme))
                    }
                    Text("Przywróć zakupy")
                }
            }
            .disabled(isRestoring)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(Color.scMuted(scheme))
        .frame(maxWidth: .infinity)
        .frame(minHeight: 28)
        .animation(.smooth(duration: 0.2), value: isRestoring)
    }

    private var separator: some View {
        Circle()
            .fill(Color.scFaint(scheme))
            .frame(width: 3, height: 3)
            .padding(.horizontal, 9)
    }
}

/// Pierścień z liczbą, która ZOSTAŁA — nie z tą, która poszła. Minimum 3 %
/// wypełnienia, żeby pusta pula nie wyglądała na błąd ładowania. Na wejściu
/// rysuje się od zera do stanu — oko widzi, ILE zostało, zanim doczyta liczbę.
struct PlanRing: View {
    let remaining: Int
    let limit: Int
    let color: Color
    var size: CGFloat = 92

    @Environment(\.colorScheme) private var scheme
    @State private var revealed = false

    private var fraction: Double {
        guard limit > 0 else { return 0 }
        return max(0.03, min(1, Double(remaining) / Double(limit)))
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.scBarTrack(scheme), lineWidth: size * 0.1)
            Circle()
                .trim(from: 0, to: revealed ? fraction : 0.03)
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(remaining)")
                    .font(.system(size: size > 88 ? 26 : 21, weight: .bold))
                    .tracking(-0.6)
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))
                    .contentTransition(.numericText())
                Text("ZOSTAŁO")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.scMuted(scheme))
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.smooth(duration: 0.75).delay(0.12)) { revealed = true }
        }
        .animation(.smooth(duration: 0.5), value: remaining)
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

/// Plakietka puli w nagłówku rozmowy — kropki i liczba, bez wykrzyknika.
///
/// Sam rysunek mieszka w `SCPipsBadge` (Kalendarz liczy nim zjedzone posiłki);
/// tutaj zostaje to, co puli asystenta właściwe: ile kropek jest pełnych,
/// jak brzmi podpis i kiedy barwa się zmienia. Barwa zmienia się dopiero
/// przy zerze i nawet wtedy nie jest alarmem: pole tekstowe zostaje aktywne,
/// a plany są jedno stuknięcie dalej.
struct AssistantQuotaPips: View {
    let remaining: Int
    /// Cała pula próbna; z niej liczy się liczba kropek.
    var limit: Int = 5
    /// Kompaktowy pasek rozmowy ma obok jeszcze tytuł rozmowy i dwa
    /// przyciski — same kropki wystarczą, etykieta wraca dopiero przy zerze,
    /// bo wtedy kropek nie ma i bez słowa plakietka byłaby pusta.
    var showsLabel: Bool = true

    private var isEmpty: Bool { remaining <= 0 }
    private var color: Color { isEmpty ? SCPalette.terracotta : SCPalette.butter }

    private var label: String {
        if isEmpty { return "pula wyczerpana" }
        return remaining == 1 ? "1 wiadomość" : "\(remaining) wiadomości"
    }

    var body: some View {
        SCPipsBadge(
            filled: max(0, remaining),
            total: limit,
            color: color,
            // Kompaktowy pasek zjada podpis, ale przy pustej puli nie ma
            // czego zjadać — kropek już nie ma i plakietka bez słowa byłaby
            // pustą pigułką.
            label: (showsLabel || isEmpty) ? label : nil,
            showsPips: !isEmpty
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isEmpty
            ? "Pula wiadomości na próbę wyczerpana"
            : "Zostało \(remaining) z \(limit) wiadomości na próbę")
    }
}
