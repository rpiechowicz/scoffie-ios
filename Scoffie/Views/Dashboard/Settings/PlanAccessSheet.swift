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
/// Układ z artefaktu „Ustawienia Scoffie”, sekcja 5, wersja 3 (6.10.2026 —
/// Rafał: „znacznie lepiej”): na górze JEDNA karta stanu w kolorze stanu
/// (plakietka, duża liczba tego, co zostało, obie pule po jednym wierszu),
/// pod nią to, co w tym stanie da się zrobić:
///   • `trial`   — trzy kafle planów, konkrety wybranego i zakup od razu
///                 tutaj (bez przechodzenia do osobnego ekranu planów);
///   • `paying`  — płacący: plan („Zmień” = push `PlansSheet`) i „Zarządzaj
///                 subskrypcją";
///   • `member`  — domownik: kto opłaca. Ta osoba MA pełny dostęp i nic nie
///                 dokupuje;
///   • `granted` — nadanie od nas, bez oferty i bez zarządzania.
///
/// To, co dom MA, bierze się wyłącznie z serwera (`AgentUsageDTO`,
/// `BillingStateDTO`); liczba domowników tylko PODPOWIADA plan („Polecany”).
struct PlanAccessSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @Environment(\.toasts) private var toasts
    @Environment(\.sessionStore) private var sessionStore

    @State private var usage: AgentUsageDTO?
    @State private var isLoading = true
    /// Awaryjny egzemplarz na wypadek ekranu bez sesji — bez klienta, więc
    /// niczego nie kupi. Normalnie używamy tego z `SessionStore`, bo tylko on
    /// żyje wystarczająco długo, żeby złapać odnowienie subskrypcji.
    @State private var fallbackSubscriptions = SubscriptionStore()
    /// Kafel stuknięty w próbie; `nil` = polecany (z liczby domowników).
    @State private var pickedPlan: SubscriptionPlan?
    /// „Zmień” płacącego — ekran wyboru wepchnięty w stos tego arkusza.
    @State private var showsPlans = false
    @State private var showTerms = false
    @State private var showPrivacy = false
    /// Wynik zakupu i „Przywróć zakupy" — przy przycisku, który go wywołał.
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
            AssistantSheetScaffold(
                eyebrow: "Konto",
                title: "Asystent i plan",
                // Glif wiersza „Asystent i plan” w Ustawieniach.
                icon: MenuConstans.Assistant.icon,
                onClose: { dismiss() },
                footer: {
                    if let usage, accessState(for: usage) == .trial {
                        purchaseFooter
                    }
                }
            ) {
                content
                    // Wczytany stan zastępuje spinner przenikaniem; potem
                    // animują się już tylko zmiany (liczby rolują).
                    .animation(SCMotion.textRoll, value: usage)
            }
            .toolbar(.hidden, for: .navigationBar)
            // Plany i dokumenty to kolejne ekrany TEGO arkusza (push), nie
            // arkusze na arkuszu. Wewnątrz stosu, na jego pierwszym ekranie.
            .navigationDestination(isPresented: $showsPlans) {
                PlansSheet(isPushed: true, onPurchased: {
                    Task { usage = await sessionStore.agentStore?.loadUsage() }
                })
            }
            .navigationDestination(isPresented: $showTerms) {
                LegalDocumentPage(title: "Regulamin") { TermsOfServiceContent() }
            }
            .navigationDestination(isPresented: $showPrivacy) {
                LegalDocumentPage(title: "Polityka prywatności") { PrivacyPolicyContent() }
            }
        }
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: pickedPlan?.id)
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
            // Stan z serwera i ceny z App Store — kafle planów i wiersz planu
            // płacącego pokazują cenę z App Store, nie z cennika.
            await subscriptions.refreshState()
            await subscriptions.loadProducts()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let usage {
            VStack(alignment: .leading, spacing: 0) {
                PlanStatusHero(
                    badge: badgeText(usage),
                    badgeColor: badgeColor(usage),
                    note: heroNote(usage),
                    accent: heroColor(usage),
                    isTrial: usage.isTrial,
                    messages: usage.messages,
                    plans: usage.plans,
                    members: heroMembers(usage),
                    resetsOn: usage.isTrial ? nil : usage.resetsAt.map(Self.resetLabel)
                )
                .padding(.top, 6)

                switch accessState(for: usage) {
                case .trial: trialBody
                case .paying: payingBody(usage)
                case .member: memberBody(usage)
                case .granted: grantedBody
                }
            }
            .transition(.opacity)
        } else if isLoading {
            ProgressView()
                .tint(SCPalette.terracotta)
                .frame(maxWidth: .infinity)
                .padding(.top, 64)
        } else {
            Text("Nie udało się pobrać stanu planu. Spróbuj ponownie za chwilę.")
                .font(.sc(size: 14))
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

    /// Plakietka próby jest w maśle (jak licznik puli w rozmowie), karta
    /// stanu — w terakocie akcji; płatny i domownik w szałwii, nadanie w indygo.
    private func badgeColor(_ usage: AgentUsageDTO) -> Color {
        switch accessState(for: usage) {
        case .trial: return AssistantLook.butter(scheme)
        case .granted: return SCPalette.indigo
        case .paying, .member: return SCPalette.sage
        }
    }

    private func heroColor(_ usage: AgentUsageDTO) -> Color {
        switch accessState(for: usage) {
        case .trial: return SCPalette.terracotta
        case .granted: return SCPalette.indigo
        case .paying, .member: return SCPalette.sage
        }
    }

    /// Domownicy na pasku wiadomości — kolor osoby z aplikacji
    /// (`HouseholdMemberStyle`, czyli `avatarColor` z serwera). Ktoś, kto już
    /// wyszedł z domu, a zużył pulę w tym okresie, dostaje kolor liczony z id,
    /// jak awatar konta bez przydziału.
    private func heroMembers(_ usage: AgentUsageDTO) -> [PlanStatusHero.Member] {
        guard accessState(for: usage) == .paying || accessState(for: usage) == .member else { return [] }
        let roster = sessionStore.householdMembers
        return (usage.byUser ?? []).map { entry -> PlanStatusHero.Member in
            let color: Color
            if let member = roster.first(where: { $0.id == entry.userId }) {
                color = HouseholdMemberStyle.color(for: member)
            } else {
                color = ProfileAvatar.baseColor(index: nil, seed: entry.userId)
            }
            return PlanStatusHero.Member(
                id: entry.userId,
                name: HouseholdMemberStyle.shortName(entry.displayName),
                messages: entry.messages,
                color: color
            )
        }
    }

    /// Krótka notka obok plakietki: próba jest jednorazowa, płatny plan
    /// mówi, kiedy się odnawia (albo kończy, gdy odnawianie jest wyłączone).
    private func heroNote(_ usage: AgentUsageDTO) -> String? {
        switch accessState(for: usage) {
        case .trial:
            return "jednorazowy"
        case .paying:
            if let sub = currentSubscription, sub.status != "GRACE", sub.operatorHold == nil,
               let end = Self.parseISO(sub.expiresAt) {
                return sub.autoRenews == false
                    ? "kończy się \(Self.relativeDay(end))"
                    : "odnawia się \(Self.relativeDay(end))"
            }
            return Self.parseISO(usage.resetsAt).map { "odnawia się \(Self.relativeDay($0))" }
        case .member, .granted:
            return Self.parseISO(usage.resetsAt).map { "odnawia się \(Self.relativeDay($0))" }
        }
    }

    private var currentSubscription: BillingSubscriptionDTO? {
        subscriptions.state?.subscriptions.first(where: { $0.alive })
            ?? subscriptions.state?.subscriptions.first
    }

    // MARK: - 1. Próba: plany od razu tutaj

    /// Plan polecany z liczby domowników — PODPOWIEDŹ, nie stan zakupu.
    private var recommendedPlan: SubscriptionPlan {
        PlansSheet.plan(forHousehold: sessionStore.householdMembers.count) ?? SubscriptionCatalog.recommended
    }

    private var selectedPlan: SubscriptionPlan {
        pickedPlan ?? recommendedPlan
    }

    @ViewBuilder
    private var trialBody: some View {
        PlanSectionLabel("Plan miesięczny")
            .padding(.top, 22)

        HStack(spacing: 8) {
            ForEach(SubscriptionCatalog.all) { plan in
                PlanOfferTile(
                    plan: plan,
                    price: price(for: plan),
                    isSelected: plan.id == selectedPlan.id,
                    isRecommended: plan.id == recommendedPlan.id
                ) {
                    select(plan)
                }
            }
        }
        // Miejsce na plakietkę „Polecany” wystającą nad górną krawędź kafla.
        .padding(.top, 8)

        PlanOfferFacts(plan: selectedPlan)
            .padding(.top, 10)
    }

    /// Prawdę o cenie mówi App Store (waluta i podatek kupującego); cennik
    /// jest zapasem na brak sieci albo nieopublikowany produkt.
    private func price(for plan: SubscriptionPlan) -> String {
        subscriptions.product(for: plan)?.displayPrice ?? plan.fallbackPrice
    }

    private func select(_ plan: SubscriptionPlan) {
        guard plan.id != selectedPlan.id else { return }
        // Ta sama krzywa co każdy rolujący tekst w aplikacji (`SCMotion.textRoll`)
        // — sprężyna z odbiciem rozjeżdżała cyfry kafla, konkretów i przycisku.
        withAnimation(SCMotion.textRoll) {
            pickedPlan = plan
            notice = nil
        }
    }

    private var canPurchase: Bool {
        PlanPurchase.canStart(selectedPlan, in: subscriptions)
    }

    private var purchaseTitle: String {
        guard canPurchase || subscriptions.isPurchasing else { return "Zakupy wkrótce" }
        return "Wybierz \(selectedPlan.name) · \(price(for: selectedPlan)) / mies."
    }

    /// Zakup, warunki odnowienia i odnośniki prawne — App Store 3.1.2 chce
    /// ich PRZY przycisku zakupu, a przywrócenie jest uczciwością wobec kogoś,
    /// kto już kiedyś kupił.
    private var purchaseFooter: some View {
        VStack(spacing: 10) {
            if let notice {
                Text(notice)
                    .font(.sc(size: 12.5))
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.scMuted(scheme))
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }

            PlanSolidButton(
                title: purchaseTitle,
                isBusy: subscriptions.isPurchasing,
                isEnabled: canPurchase,
                action: buy
            )

            Text("Odnawia się automatycznie co miesiąc, opłatę pobiera Apple. Anulujesz w Ustawieniach iOS.")
                .font(.sc(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.scFaint(scheme))
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)

            PlanLegalLinks(
                isRestoring: isRestoring,
                onTerms: { showTerms = true },
                onPrivacy: { showPrivacy = true },
                onRestore: restore
            )
        }
        .animation(.smooth(duration: 0.22), value: notice)
    }

    private func buy() {
        // Kolejka do stałej PRZED zadaniem — arkusz da się zsunąć palcem,
        // gdy zgłoszenie do serwera jeszcze trwa.
        let toasts = toasts
        let plan = selectedPlan
        Task {
            switch await PlanPurchase.run(plan, in: subscriptions, toasts: toasts) {
            case .purchased:
                // Arkusz zostaje: ta sama karta stanu przechodzi w płatny
                // plan na oczach, bez szukania potwierdzenia.
                notice = nil
                usage = await sessionStore.agentStore?.loadUsage()
            case let .notice(message):
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
            usage = await sessionStore.agentStore?.loadUsage()
            isRestoring = false
        }
    }

    // MARK: - 2. Płacący

    @ViewBuilder
    private func payingBody(_ usage: AgentUsageDTO) -> some View {
        PlanSectionLabel("Subskrypcja")
            .padding(.top, 22)

        AssistantSurfaceCard {
            PlanAccessRow(
                icon: "checkmark.seal.fill",
                color: SCPalette.sage,
                title: paidPlanName(usage),
                subtitle: paidPlanSubtitle(usage),
                value: "Zmień",
                trailingIcon: "chevron.right",
                action: { showsPlans = true }
            )
            PlanAccessRow(
                icon: "arrow.up.forward.app.fill",
                color: SettingsAccent.slate,
                title: "Zarządzaj subskrypcją",
                titleColor: SCPalette.terracotta,
                subtitle: "W Ustawieniach iOS",
                trailingIcon: "arrow.up.right",
                isLast: true,
                action: openSubscriptions
            )
        }

        // CO SERWER MÓWI O TEJ SUBSKRYPCJI, gdy to coś niezwykłego. Nieudana
        // płatność (łaska płatnicza), wyłączone odnawianie i ręczne odebranie
        // dostępu przez obsługę muszą być tu widoczne — inaczej człowiek
        // dowiaduje się o nich dopiero wtedy, gdy asystent przestaje odpowiadać.
        if let line = subscriptionStatusLine {
            Text(line)
                .font(.sc(size: 12.5))
                .lineSpacing(2)
                .foregroundStyle(Color.scMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.top, 10)
        }
    }

    private func openSubscriptions() {
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            openURL(url)
        }
    }

    /// Plan płacącego: najpierw jego subskrypcja (dokładny produkt), potem
    /// nazwa z licznika asystenta.
    private func paidPlan(_ usage: AgentUsageDTO) -> SubscriptionPlan? {
        if let sub = currentSubscription,
           let plan = SubscriptionCatalog.all.first(where: { $0.id == sub.productId }) {
            return plan
        }
        return SubscriptionCatalog.plan(named: usage.product)
    }

    private func paidPlanName(_ usage: AgentUsageDTO) -> String {
        paidPlan(usage)?.name ?? usage.product ?? "Twój plan"
    }

    private func paidPlanSubtitle(_ usage: AgentUsageDTO) -> String {
        guard let plan = paidPlan(usage) else { return "opłacasz Ty" }
        return "\(price(for: plan)) / mies. · opłacasz Ty"
    }

    /// Jedno zdanie o subskrypcji tej osoby, złożone z tego, co oddaje serwer —
    /// TYLKO gdy dzieje się coś niezwykłego (zwykłe odnowienie mówi notka
    /// w karcie stanu). Kolejność jest kolejnością pilności: blokada obsługi,
    /// łaska płatnicza, wyłączone odnawianie, wygasły plan.
    private var subscriptionStatusLine: String? {
        guard let sub = currentSubscription else { return nil }

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
        if !sub.alive, let end = Self.dayMonth(sub.expiresAt) {
            return "Plan wygasł \(end)."
        }
        return nil
    }

    // MARK: - 3. Domownik

    @ViewBuilder
    private func memberBody(_ usage: AgentUsageDTO) -> some View {
        PlanSectionLabel("Kto opłaca")
            .padding(.top, 22)

        AssistantSurfaceCard {
            HStack(spacing: 12) {
                payerAvatar(usage.payerName ?? "?")
                VStack(alignment: .leading, spacing: 2) {
                    Text(usage.payerName ?? "Ktoś z domu")
                        .font(.sc(size: 15, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(scheme))
                    Text(payerSubtitle(usage))
                        .font(.sc(size: 12.5))
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 58)

            // Najważniejsze zdanie na tym ekranie dla domownika: NIE musisz
            // nic kupować. Bez niego widok wygląda jak zapowiedź opłaty.
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.sc(size: 15, weight: .semibold))
                    .foregroundStyle(SCPalette.sage)
                Text("Masz pełny dostęp do wspólnej puli. Nic nie dokupujesz.")
                    .font(.sc(size: 13))
                    .lineSpacing(2)
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                MemberAvatar(member: member, members: sessionStore.householdMembers, size: 30)
            } else {
                Circle()
                    .fill(Color.scSageTint(scheme))
                    .overlay(
                        Text(String(name.prefix(1)).uppercased())
                            .font(.sc(size: 13, weight: .bold))
                            .foregroundStyle(SCPalette.sage)
                    )
                    .frame(width: 30, height: 30)
            }
        }
    }

    // MARK: - 4. Nadanie

    private var grantedBody: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "gift.fill")
                .font(.sc(size: 14))
                .foregroundStyle(SCPalette.indigo)
                .padding(.top, 1)
            Text("Dostęp nadany przez Scoffie. Nic nie płacisz w aplikacji.")
                .font(.sc(size: 13.5))
                .lineSpacing(3)
                .foregroundStyle(Color.scLabel(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.scIndigoTint(scheme)))
        .padding(.top, 16)
    }

    // MARK: - Daty

    /// Daty ISO od serwera. `withFractionalSeconds` jest konieczne: serwer
    /// oddaje `toISOString()`, czyli z milisekundami, a goły
    /// `ISO8601DateFormatter` zwraca wtedy `nil`. Bez ułamków — zapas na
    /// datę zapisaną inną drogą.
    private static let isoParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoParserWhole: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func parseISO(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return isoParser.date(from: iso) ?? isoParserWhole.date(from: iso)
    }

    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMMM"
        return formatter
    }()

    /// „3 października" z daty ISO od serwera; `nil`, gdy nie da się odczytać.
    private static func dayMonth(_ iso: String?) -> String? {
        parseISO(iso).map { dayMonthFormatter.string(from: $0) }
    }

    /// „1 października" z ISO odnowienia puli; sam napis ISO, gdy nie da
    /// się sparsować.
    static func resetLabel(_ iso: String) -> String {
        guard let date = parseISO(iso) else { return iso }
        return dayMonthFormatter.string(from: date)
    }

    /// „dziś” / „jutro” / „za 28 dni” — liczone po dniach kalendarza
    /// telefonu, nie po 24-godzinnych odcinkach.
    private static func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        switch days {
        case ...0: return "dziś"
        case 1: return "jutro"
        default: return "za \(days) dni"
        }
    }
}

// MARK: - Karta stanu

/// „Hero” arkusza: plakietka i notka, DUŻA liczba wiadomości, które
/// zostały, i obie pule po jednym wierszu. Cała w kolorze stanu — próba
/// w terakocie, płatny plan w szałwii, nadanie w indygo.
///
/// Wskaźnik w PRÓBIE to kropki (sztuka na kropkę, pełne = zostało), bo przy
/// 5 wiadomościach i 2 zapisach liczy się każda; przy limicie ponad 12 —
/// ciągły pasek tego, co zostało. W płatnym planie pasek pokazuje ZUŻYCIE,
/// dzielone kolorami domowników, a liczba obok mówi „ile poszło z ilu” —
/// tak, żeby zgadzała się z legendą pod spodem („Ania · 12, Marek · 6”).
struct PlanStatusHero: View {
    struct Member: Identifiable, Equatable {
        let id: String
        let name: String
        let messages: Int
        let color: Color
    }

    let badge: String
    let badgeColor: Color
    let note: String?
    let accent: Color
    let isTrial: Bool
    let messages: AgentQuotaDTO
    let plans: AgentQuotaDTO
    var members: [Member] = []
    /// „3 listopada” — kiedy pula wraca; `nil` na próbie.
    var resetsOn: String?

    @Environment(\.colorScheme) private var scheme

    private static let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    /// Kropki do tej liczby sztuk; powyżej — ciągły pasek.
    private static let maxPips = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                PlanBadge(label: badge, color: badgeColor)
                if let note {
                    Text(note)
                        .font(.sc(size: 13))
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .contentTransition(.numericText())
                }
            }

            bigNumber
                .padding(.top, 10)
                .padding(.bottom, 12)

            quotaLine("Wiadomości", quota: messages, splitByMembers: true)
            quotaLine("Zapisy planu", quota: plans, splitByMembers: false)

            if isTrial {
                footNote
            } else if !members.isEmpty || resetsOn != nil {
                legend
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, isTrial || !members.isEmpty || resetsOn != nil ? 0 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { heroSurface }
        .clipShape(Self.shape)
        .overlay(Self.shape.strokeBorder(accent.opacity(scheme == .dark ? 0.32 : 0.26), lineWidth: 1))
        .animation(SCMotion.textRoll, value: messages)
        .animation(SCMotion.textRoll, value: plans)
        .animation(SCMotion.textRoll, value: note)
    }

    /// Strój kafla z delikatnym tintem stanu i poświatą z prawego górnego rogu.
    private var heroSurface: some View {
        ZStack {
            Self.shape.fill(Color.scTileBg(scheme))
            Self.shape.fill(accent.opacity(scheme == .dark ? 0.07 : 0.05))
            Self.shape.fill(
                RadialGradient(
                    colors: [accent.opacity(scheme == .dark ? 0.2 : 0.16), accent.opacity(0)],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 280
                )
            )
        }
    }

    // MARK: Duża liczba

    private var bigNumber: some View {
        let left = max(0, messages.remaining)
        return HStack(alignment: .center, spacing: 10) {
            Text("\(left)")
                .font(.sc(size: 56, weight: .heavy))
                .tracking(-2)
                .monospacedDigit()
                .foregroundStyle(accent)
                .contentTransition(.numericText(value: Double(left)))
                .lineLimit(1)
            // Każde słowo roluje się samo — przy „1 ↔ 2” zmienia się tylko
            // końcówka, a nie cały blok naraz.
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.messagesNoun(left))
                    .contentTransition(.numericText(value: Double(left)))
                Text(Self.leftVerb(left))
                    .contentTransition(.numericText(value: Double(left)))
            }
            .font(.sc(size: 15, weight: .bold))
            .foregroundStyle(Color.scLabel(scheme))
            .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(left) \(Self.messagesNoun(left)) \(Self.leftVerb(left))")
    }

    /// „wiadomość” / „wiadomości” — mianownik po liczbie.
    static func messagesNoun(_ count: Int) -> String {
        PolishPlural.form(count, one: "wiadomość", few: "wiadomości", many: "wiadomości")
    }

    /// „została” / „zostały” / „zostało” — zgoda z liczbą.
    static func leftVerb(_ count: Int) -> String {
        PolishPlural.form(count, one: "została", few: "zostały", many: "zostało")
    }

    // MARK: Wiersze puli

    private func quotaLine(_ label: String, quota: AgentQuotaDTO, splitByMembers: Bool) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.sc(size: 13.5, weight: .semibold))
                .foregroundStyle(Color.scLabel(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 92, alignment: .leading)

            indicator(quota: quota, splitByMembers: splitByMembers)
                .frame(maxWidth: .infinity)

            Text(valueText(quota))
                .font(.sc(size: 13))
                .monospacedDigit()
                .foregroundStyle(Color.scMuted(scheme))
                .contentTransition(.numericText())
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { rule }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): zostało \(max(0, quota.remaining)) z \(quota.limit)")
    }

    /// Próba: ile ZOSTAŁO (jak kropki). Płatny: ile POSZŁO (jak pasek i legenda).
    private func valueText(_ quota: AgentQuotaDTO) -> String {
        isTrial
            ? "\(max(0, quota.remaining)) z \(quota.limit)"
            : "\(min(quota.used, quota.limit)) z \(quota.limit)"
    }

    @ViewBuilder
    private func indicator(quota: AgentQuotaDTO, splitByMembers: Bool) -> some View {
        if isTrial {
            if quota.limit > 0, quota.limit <= Self.maxPips {
                pips(quota)
            } else {
                PlanUsageBar(segments: [
                    PlanUsageBar.Segment(id: "left", fraction: Self.fraction(quota.remaining, of: quota.limit), color: accent),
                ])
            }
        } else {
            PlanUsageBar(segments: usageSegments(quota: quota, splitByMembers: splitByMembers))
        }
    }

    private func pips(_ quota: AgentQuotaDTO) -> some View {
        let left = max(0, quota.remaining)
        // Pełne = zostało, od PRAWEJ — zużyte sztuki „odchodzą” z lewej,
        // jak w makiecie (4 blade, 1 pełna).
        let firstFull = quota.limit - min(left, quota.limit)
        return HStack(spacing: 4) {
            ForEach(0..<quota.limit, id: \.self) { index in
                Capsule()
                    .fill(index >= firstFull ? accent : accent.opacity(scheme == .dark ? 0.2 : 0.16))
                    .frame(height: 8)
            }
        }
    }

    private func usageSegments(quota: AgentQuotaDTO, splitByMembers: Bool) -> [PlanUsageBar.Segment] {
        let used = members.filter { $0.messages > 0 }
        guard splitByMembers, !used.isEmpty else {
            return [PlanUsageBar.Segment(id: "used", fraction: Self.fraction(quota.used, of: quota.limit), color: accent)]
        }
        return used.map { member in
            PlanUsageBar.Segment(id: member.id, fraction: Self.fraction(member.messages, of: quota.limit), color: member.color)
        }
    }

    private static func fraction(_ value: Int, of limit: Int) -> Double {
        guard limit > 0 else { return 0 }
        return min(max(Double(value) / Double(limit), 0), 1)
    }

    // MARK: Stopka karty

    private var footNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.sc(size: 14, weight: .regular))
                .foregroundStyle(Color.scFaint(scheme))
                .padding(.top, 1)
            Text("Liczy się wysłana wiadomość i „Dodaj do planu”. Oglądanie propozycji nic nie kosztuje.")
                .font(.sc(size: 12.5))
                .lineSpacing(2)
                .foregroundStyle(Color.scMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { rule }
        .padding(.horizontal, -16)
    }

    private var legend: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            ForEach(members) { member in
                HStack(spacing: 6) {
                    Circle()
                        .fill(member.color)
                        .frame(width: 8, height: 8)
                    Text("\(member.name) · \(member.messages)")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let resetsOn {
                Text("pula wraca \(resetsOn)")
                    .foregroundStyle(Color.scFaint(scheme))
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .font(.sc(size: 12.5))
        .foregroundStyle(Color.scMuted(scheme))
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { rule }
        .padding(.horizontal, -16)
    }

    private var rule: some View {
        Rectangle().fill(Color.scRule(scheme)).frame(height: 1)
    }
}

/// Pasek puli: kolejne odcinki od lewej (zużycie domowników albo jedna
/// barwa) na torze. Odcinki to kształty z animowanym POCZĄTKIEM i KOŃCEM,
/// nie `GeometryReader` z ramką — szerokość z pierwszego przebiegu układu
/// (zero, zanim arkusz dojedzie) nie jest animowana, rusza się tylko pula.
struct PlanUsageBar: View {
    struct Segment: Identifiable, Equatable {
        let id: String
        let fraction: Double
        let color: Color
    }

    let segments: [Segment]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Capsule()
            .fill(Color.scBarTrack(scheme))
            .overlay {
                ZStack {
                    ForEach(spans) { span in
                        PlanBarSpan(start: span.start, end: span.end, gap: spans.count > 1 ? 1 : 0)
                            .fill(span.color)
                    }
                }
            }
            .clipShape(Capsule())
            .frame(height: 8)
            .accessibilityHidden(true)
    }

    private struct Span: Identifiable {
        let id: String
        let start: Double
        let end: Double
        let color: Color
    }

    /// Odcinki jeden za drugim, przycięte do całego toru.
    private var spans: [Span] {
        var cursor = 0.0
        var result: [Span] = []
        for segment in segments {
            let start = min(cursor, 1)
            let end = min(cursor + max(segment.fraction, 0), 1)
            result.append(Span(id: segment.id, start: start, end: end, color: segment.color))
            cursor = end
        }
        return result
    }
}

/// Odcinek paska od `start` do `end` (ułamki szerokości), z odstępem `gap`
/// po obu stronach, gdy obok stoi inny odcinek.
private struct PlanBarSpan: Shape {
    var start: Double
    var end: Double
    var gap: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(start, end) }
        set {
            start = newValue.first
            end = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let minX = rect.minX + rect.width * CGFloat(start) + (start > 0 ? gap : 0)
        let maxX = rect.minX + rect.width * CGFloat(end) - (end < 1 ? gap : 0)
        guard maxX > minX else { return Path() }
        return Path(CGRect(x: minX, y: rect.minY, width: maxX - minX, height: rect.height))
    }
}

// MARK: - Plany w próbie

/// Kafel planu w „Asystent i plan”: nazwa, dla ilu osób, cena; polecany ma
/// plakietkę na górnej krawędzi. Wybrany — tint terakoty z obwódką.
struct PlanOfferTile: View {
    let plan: SubscriptionPlan
    let price: String
    let isSelected: Bool
    /// Pasuje do liczby domowników — podpowiedź, nie stan zakupu.
    let isRecommended: Bool
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var scheme

    private static let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 2) {
                Text(plan.name)
                    .font(.sc(size: 14.5, weight: .heavy))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(Self.seats(plan))
                    .font(.sc(size: 11.5))
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(price)
                    .font(.sc(size: 16, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? SCPalette.terracotta : Color.scLabel(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 4)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .scChoiceSurface(
                Self.shape,
                isOn: isSelected,
                accent: SCPalette.terracotta,
                offFill: Color.scTileBg(scheme),
                style: .tile
            )
            .overlay(alignment: .top) {
                if isRecommended {
                    Text("POLECANY")
                        .font(.sc(size: 9.5, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(SCPalette.terracotta))
                        .fixedSize()
                        .offset(y: -8)
                }
            }
            .contentShape(Self.shape)
        }
        .buttonStyle(PlanPressButtonStyle())
        .animation(.easeInOut(duration: 0.22), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plan \(plan.name), \(plan.seatsLabel), \(price) miesięcznie"
            + (isRecommended ? ", polecany dla Twojego domu" : ""))
        .accessibilityAddTraits(traits)
    }

    private var traits: AccessibilityTraits {
        var result: AccessibilityTraits = .isButton
        if isSelected { _ = result.insert(.isSelected) }
        return result
    }

    /// Krótko, żeby trzy kafle zmieściły się w rzędzie: „3+ osób” zamiast
    /// „3 osoby i więcej”.
    static func seats(_ plan: SubscriptionPlan) -> String {
        plan.id == SubscriptionCatalog.family.id ? "3+ osób" : plan.seatsLabel
    }
}

/// Konkrety wybranego planu: ile wiadomości i zapisów, dla kogo, co zostaje.
/// Cyfry rolują przy zmianie kafla, reszta zostaje na miejscu.
struct PlanOfferFacts: View {
    let plan: SubscriptionPlan

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AssistantSurfaceCard {
            VStack(alignment: .leading, spacing: 9) {
                fact("bubble.left.fill") {
                    countLine(plan.messages, noun: "wiadomości w miesiącu")
                }
                fact("calendar.badge.plus") {
                    countLine(plan.plans, noun: PolishPlural.form(plan.plans, one: "zapis", few: "zapisy", many: "zapisów") + " planu")
                }
                fact("person.2.fill") {
                    Text(Self.audience(plan))
                        .contentTransition(.numericText())
                }
                fact("clock.arrow.circlepath") {
                    Text("Rozmowy i plany zostają, gdy pula się skończy")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .animation(SCMotion.textRoll, value: plan.id)
    }

    private func fact<Content: View>(_ icon: String, @ViewBuilder label: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.sc(size: 15, weight: .semibold))
                .foregroundStyle(SCPalette.terracotta)
                .frame(width: 22)
            label()
                .font(.sc(size: 14))
                .foregroundStyle(Color.scMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func countLine(_ value: Int, noun: String) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.sc(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.scLabel(scheme))
                .contentTransition(.numericText(value: Double(value)))
            Text(noun)
        }
    }

    /// „Tylko dla Ciebie” / „Pula wspólna dla 2 osób”.
    static func audience(_ plan: SubscriptionPlan) -> String {
        switch plan.id {
        case SubscriptionCatalog.solo.id: return "Tylko dla Ciebie"
        case SubscriptionCatalog.duet.id: return "Pula wspólna dla 2 osób"
        default: return "Pula wspólna dla 3 i więcej osób"
        }
    }
}

/// Przycisk zakupu: pełna terakota jako szkło, jak „Gotuj” — jedyny kryjący
/// przycisk na ekranie. Szkło NIE jest interaktywne (w etykiecie przycisku
/// przechwytywało stuknięcie); reakcję daje `PlanPressStyle`.
struct PlanSolidButton: View {
    let title: String
    var isBusy: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.scPageBase(scheme))
                }
                Text(title)
                    .font(.sc(size: 15.5, weight: .bold))
                    .tracking(-0.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
            }
            // Tytuł roluje się także wtedy, gdy zmianę przyniosła nie
            // animowana transakcja (ceny z App Store dochodzą po otwarciu).
            .animation(SCMotion.textRoll, value: title)
            .animation(SCMotion.textRoll, value: isBusy)
            .foregroundStyle(Color.scPageBase(scheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .scChromeGlass(in: Capsule(), tint: SCPalette.terracotta)
            .contentShape(Capsule())
        }
        .buttonStyle(PlanPressStyle(scale: 0.97))
        .disabled(!isEnabled || isBusy)
        .opacity(isEnabled || isBusy ? 1 : 0.5)
        .animation(.smooth(duration: 0.18), value: isEnabled)
    }
}

/// Wiersz grupy w arkuszu — klocek wiersza Ustawień (kafelek 30 pt, tytuł 15
/// semibold, kreska od tytułu), z podpisem pod tytułem i wartością po prawej.
struct PlanAccessRow: View {
    let icon: String
    let color: Color
    let title: String
    var titleColor: Color? = nil
    var subtitle: String? = nil
    var value: String? = nil
    var trailingIcon: String? = nil
    var isLast: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                EditorialSettingsTileIcon(icon: icon, color: color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.sc(size: 15, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(titleColor ?? Color.scLabel(scheme))
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.sc(size: 12.5))
                            .foregroundStyle(Color.scMuted(scheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let value {
                    Text(value)
                        .font(.sc(size: 15))
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                }
                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.sc(size: 11, weight: .bold))
                        .foregroundStyle(Color.scFaint(scheme))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressButtonStyle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    // Kreska zaczyna się pod tytułem, nie pod kafelkiem.
                    .padding(.leading, 12 + 30 + 12)
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
            .font(.sc(size: 12, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(scheme == .dark ? 0.16 : 0.18)))
            .lineLimit(1)
    }
}

/// Etykieta sekcji — krój `EditorialSheetSectionLabel` (10,5 pt, tracking
/// 1,4), jak w każdym arkuszu; odstępy zostają pod wcięcie tekstów tego
/// arkusza (4 pt).
struct PlanSectionLabel: View {
    let text: String

    @Environment(\.colorScheme) private var scheme

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.sc(size: 10.5, weight: .bold))
            .tracking(1.4)
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
        .font(.sc(size: 13.5, weight: .semibold))
        .foregroundStyle(AssistantLook.terra(scheme))
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
