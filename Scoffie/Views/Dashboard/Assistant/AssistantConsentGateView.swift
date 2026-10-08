import SwiftUI

/// „Zanim zaczniemy" — ostatni krok wprowadzenia Asystenta (v2, 24.09.2026:
/// Powitanie → Planowanie → Ty decydujesz → Zgoda), stan zakładki zamiast
/// rozmowy, dopóki nie ma zgody. Ten sam widok jako arkusz z menu ⋯ →
/// „Prywatność i zgoda": wtedy pokazuje stan zgody, wygaszone potwierdzenia
/// i „Cofnij zgodę".
///
/// Serwer wymaga DWÓCH zgód (wiek 16+ i przetwarzanie danych o diecie
/// w asystencie), więc „Włącz Asystenta" odblokowuje się dopiero po dwóch
/// stuknięciach — licznik „0 z 2” roluje przy każdym. Treść „co wysyłamy /
/// czego nie" jest przepisana z sekcji 6 polityki prywatności — ekran nie
/// obiecuje ani mniej, ani więcej.
struct AssistantConsentGateView: View {
    enum Presentation {
        /// Krok wprowadzenia w zakładce — nagłówek kroku, stopkę składa rodzic.
        case inline
        /// Arkusz z menu — z nagłówkiem i przyciskiem zamknięcia.
        case sheet
    }

    let consents: ConsentStore
    let source: String
    var presentation: Presentation = .inline
    var onGranted: (() -> Void)? = nil
    /// Potwierdzenia i błąd zapisu od rodzica — w zakładce trzyma je
    /// `AssistantView`, bo stopka z „Włącz Asystenta" stoi poza tym widokiem
    /// (`AssistantView.introFooter`). Arkusz z menu podaje `nil` i ma własne.
    var draft: Binding<AssistantConsentDraft>? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var localDraft = AssistantConsentDraft()
    /// Nagłówek kroku już się napisał — zdanie, które wraca po błędzie
    /// zapisu, stoi od razu, zamiast pisać się drugi raz.
    @State private var headerTyped = false
    @State private var showPrivacyPolicy = false
    @State private var confirmsRevoke = false

    private var draftBinding: Binding<AssistantConsentDraft> { draft ?? $localDraft }
    private var currentDraft: AssistantConsentDraft { draftBinding.wrappedValue }

    private var isGranted: Bool { consents.assistantGranted }
    private var canGrant: Bool { Self.canGrant(currentDraft) }
    private var isUnderage: Bool { Self.isUnderage }
    private var ageFromProfile: Bool { Self.ageFromProfile }

    /// Wiek po roku urodzenia z profilu (kreator, krok 1). `nil` = brak roku.
    /// Poniżej 16 blokujemy; od 17 ptaszek „mam 16 lat" jest z góry —
    /// dokładnie 16 po roku może jeszcze nie mieć urodzin, więc pyta.
    static var profileAgeByYear: Int? {
        let year = SCProtectedSettings.shared.integer(forKey: "settings.profile.yearOfBirth")
        guard year > 0 else { return nil }
        return Calendar.current.component(.year, from: Date()) - year
    }

    static var isUnderage: Bool { (profileAgeByYear ?? 99) < 16 }
    static var ageFromProfile: Bool { (profileAgeByYear ?? 0) >= 17 }

    static func canGrant(_ draft: AssistantConsentDraft) -> Bool {
        draft.confirmsAge && draft.confirmsData && !isUnderage
    }

    /// Zapis zgody — wspólny dla stopki w zakładce i arkusza z menu.
    /// Zwraca `true` po udanym zapisie; błąd ląduje w `draft.errorMessage`.
    @MainActor
    static func grant(consents: ConsentStore, source: String, draft: Binding<AssistantConsentDraft>) async -> Bool {
        draft.wrappedValue.errorMessage = nil
        if let message = await consents.grantAssistant(source: source) {
            // Pełny komunikat z serwera — bez niego „nie udało się" nie mówi,
            // czy to sieć, walidacja czy stara wersja aplikacji.
            draft.wrappedValue.errorMessage = message.isEmpty
                ? "Nie udało się zapisać zgody. Spróbuj ponownie."
                : "Nie udało się zapisać zgody: \(message)"
            return false
        }
        return true
    }

    var body: some View {
        Group {
            switch presentation {
            case .inline:
                content
            case .sheet:
                NavigationStack {
                    content
                        .toolbar(.hidden, for: .navigationBar)
                        // Polityka w arkuszu z menu = PUSH w jego stosie
                        // (7.10.2026, „najwyżej jeden arkusz”), jak dokumenty
                        // w „Prywatność i regulamin”. Dawniej drugi arkusz
                        // (`LegalDocumentSheet`) na arkuszu zgody.
                        .navigationDestination(isPresented: $showPrivacyPolicy) {
                            LegalDocumentPage(title: "Polityka prywatności") {
                                PrivacyPolicyContent()
                            }
                        }
                }
                .presentationDragIndicator(.visible)
            }
        }
        .interactiveDismissDisabled(consents.isBusy)
        .onAppear { if ageFromProfile { draftBinding.wrappedValue.confirmsAge = true } }
        .task { await consents.refresh() }
        // W zakładce (krok wprowadzenia) nad zgodą nie stoi żaden arkusz —
        // tam polityka zostaje jedynym arkuszem.
        .sheet(isPresented: inlinePolicySheet) {
            LegalDocumentSheet(title: "Polityka prywatności", icon: "hand.raised.fill", accent: SCPalette.indigo) {
                PrivacyPolicyContent()
            }
        }
        .alert("Cofnąć zgodę?", isPresented: $confirmsRevoke) {
            Button("Anuluj", role: .cancel) {}
            Button("Cofnij zgodę", role: .destructive) { revoke() }
        } message: {
            Text("Asystent przestanie dla Ciebie działać, a Twoje dane o diecie nie będą już wysyłane do Anthropic. Zapisane rozmowy zostają, dopóki ich nie usuniesz.")
        }
    }

    /// Arkusz polityki tylko w zakładce; w arkuszu z menu polityka wjeżdża
    /// pushem (`navigationDestination` wyżej).
    private var inlinePolicySheet: Binding<Bool> {
        Binding(
            get: { presentation == .inline && showPrivacyPolicy },
            set: { showPrivacyPolicy = $0 }
        )
    }

    @ViewBuilder
    private var content: some View {
        if presentation == .sheet {
            // „20 · Zgoda na asystenta”: nagłówek Prywatność · tytuł · X,
            // status w szałwii, „co wysyłamy” jako lista, „czego nie” jedną
            // linią, potwierdzenia jako wiersze z zaznaczeniem, „Cofnij
            // zgodę” w stopce.
            AssistantSheetScaffold(
                eyebrow: "Prywatność",
                title: isGranted ? "Zgoda na asystenta" : "Zanim zaczniemy",
                // Ten sam kafelek, co nagłówek kroku zgody w zakładce
                // (`SCStepHeader` niżej): prywatność w szałwii, nie funkcja.
                icon: "lock.shield.fill",
                accent: SCPalette.sage,
                onClose: { dismiss() },
                footer: { footer }
            ) {
                if isGranted {
                    statusBar
                        .padding(.top, 10)
                }
                sections
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Nagłówek kroku jak na stronach wprowadzenia i w kreatorze
                    // (`SCStepHeader`) — tytuł i zdanie PISZĄ SIĘ, jak na
                    // pozostałych krokach. Kafelek w szałwii: prywatność, nie
                    // funkcja. Zdanie pod tytułem gaśnie przy błędzie zapisu —
                    // błąd stoi wtedy w stopce, nad przyciskiem, i nie spycha
                    // potwierdzeń.
                    SCStepHeader(
                        icon: "lock.shield.fill",
                        accent: SCPalette.sage,
                        eyebrow: "Prywatność",
                        title: "Zanim zaczniemy",
                        subtitle: isGranted || currentDraft.errorMessage != nil
                            ? nil
                            : "Zanim Asystent wyśle cokolwiek do modelu Claude firmy Anthropic, potrzebuje Twojej zgody.",
                        typing: isGranted || headerTyped ? nil : 0
                    )
                    .padding(.bottom, 8)
                    .task {
                        try? await Task.sleep(for: .seconds(1.2))
                        if !Task.isCancelled { headerTyped = true }
                    }

                    sections
                }
                .padding(.horizontal, SCPageMetrics.horizontal)
                // Od góry jak strony wprowadzenia — nad krokiem nie stoi
                // nagłówek zakładki.
                .padding(.top, AssistantIntroLayout.top)
                // Zapas na cień stopki (`SCEdgeShade`), który leży na treści.
                .padding(.bottom, AssistantIntroLayout.bottom)
            }
            .scrollIndicators(.hidden)
            .scScrollEdgeFade()
        }
    }

    /// Wspólne sekcje zakładki i arkusza — od 7.10.2026 na klockach list
    /// Ustawień: karta `EditorialSettingsCardGroup`, etykieta sekcji
    /// `EditorialSheetSectionLabel`, wiersze `EditorialSettingsRow` (kafelek,
    /// zdanie, `SCCheckbox` po prawej). Dawne `AssistantGroup`/`AssistantRow`
    /// i terakotowy odnośnik do polityki odpadły; treść bez zmian.
    @ViewBuilder
    private var sections: some View {
        dataCard
            .padding(.top, 14)

        if isUnderage, !isGranted {
            underageNotice
                .padding(.top, 14)
        }

        confirmationsHeader
            .padding(.top, 20)
        EditorialSettingsCardGroup {
            confirmRow(
                isOn: isGranted ? .constant(true) : draftBinding.confirmsAge,
                icon: "person.fill.checkmark",
                color: SCPalette.indigo,
                title: "Mam ukończone 16 lat",
                caption: ageFromProfile ? "Zaznaczone według roku urodzenia z Twojego profilu" : nil,
                isLast: false
            )
            confirmRow(
                isOn: isGranted ? .constant(true) : draftBinding.confirmsData,
                icon: "hand.raised.fill",
                color: SCPalette.sage,
                title: "Zgadzam się, żeby Scoffie wysyłał moje dane o diecie i alergiach do Anthropic (model Claude, USA), by Asystent mógł odpowiadać",
                caption: "Wyraźna zgoda (art. 9 ust. 2 lit. a RODO) w zakresie opisanym wyżej.",
                isLast: true
            )
        }
        .opacity(isGranted || isUnderage ? 0.9 : 1)
        .disabled(isGranted || isUnderage)

        // Polityka jak dokument w „Prywatność i regulamin” — wiersz listy
        // z kafelkiem, nie terakotowy odnośnik.
        EditorialSettingsCardGroup {
            EditorialSettingsRow(
                icon: "doc.text.fill",
                iconColor: SettingsAccent.slate,
                title: "Polityka prywatności",
                value: "Sekcja 6",
                isLast: true,
                action: { showPrivacyPolicy = true }
            )
        }
        .padding(.top, 14)

        // Od 7.10.2026 ekran NAZYWA odbiorcę danych: Anthropic, model Claude,
        // USA (karta „Co wysyłamy” i potwierdzenie wyżej) — App Review 5.1.2(i)
        // wymaga, żeby zgoda na przekazanie danych osobowych zewnętrznemu AI
        // mówiła, komu je dajemy. Dawniej celowo bez nazw firm trzecich.
        // Podstawa przekazania poza EOG i lista podwykonawców zostają
        // w polityce prywatności (sekcja 6, wiersz wyżej).
        Text("Asystent to program — może się mylić i nie zastępuje dietetyka ani lekarza. Zgodę cofniesz w każdej chwili w menu asystenta.")
            .font(.sc(size: 12.5))
            .lineSpacing(3)
            .foregroundStyle(Color.scFaint(scheme))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.top, 10)
    }

    /// Etykieta sekcji potwierdzeń z licznikiem „0 z 2” po prawej.
    private var confirmationsHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            EditorialSheetSectionLabel(title: "Twoje potwierdzenia")
            confirmationsBadge
                .padding(.trailing, 6)
                .padding(.bottom, 6)
        }
    }

    // MARK: - Klocki

    /// Rok urodzenia z profilu mówi „mniej niż 16" — potwierdzenia są
    /// wygaszone, przycisk nieaktywny. Serwer sprawdza to samo przy zapisie.
    private var underageNotice: some View {
        // Karta jak każda inna (jeden kolor kart) — ostrzeżenie mówi
        // terakotowy kafelek, nie tło w tincie.
        EditorialSettingsCardGroup {
            EditorialSettingsRow(
                icon: "person.crop.circle.badge.exclamationmark",
                iconColor: SCPalette.terracotta,
                title: "Asystent jest dostępny od 16 lat",
                subtitle: "Według roku urodzenia w Twoim profilu to jeszcze nie ten wiek. Jeśli rok jest błędny, popraw go w Ustawieniach → Profil i wróć tutaj.",
                isLast: true,
                wrapsText: true,
                action: nil
            ) {
                EmptyView()
            }
        }
    }

    /// Licznik zamiast napisu „oba wymagane": 0 z 2 → 1 z 2 → 2 z 2 (zielone),
    /// po zapisie „Zapisane” z ptaszkiem. Mówi to samo, ale zmienia się razem
    /// z tym, co użytkownik robi, zamiast go pouczać.
    ///
    /// Cyfra ROLUJE przy każdym stuknięciu (`numericText`, krzywa tekstu
    /// aplikacji `SCMotion.textRoll`) — ta sama animacja liczb, co w reszcie
    /// Asystenta, zamiast podmiany w klatce.
    private var confirmationsBadge: some View {
        let done = isGranted ? 2 : (currentDraft.confirmsAge ? 1 : 0) + (currentDraft.confirmsData ? 1 : 0)
        let complete = done == 2
        return Text(isGranted ? "Zapisane" : "\(done) z 2")
            .font(.sc(size: 12, weight: complete ? .bold : .semibold))
            .monospacedDigit()
            .foregroundStyle(complete ? AssistantLook.sage(scheme) : AssistantLook.faint(scheme))
            .contentTransition(.numericText(value: Double(done)))
            .animation(SCMotion.textRoll, value: done)
    }

    /// Stan zgody: wiersz listy z kafelkiem tarczy w szałwii, „Zgoda włączona”
    /// i wersją dokumentu w podpisie — w karcie jak każda inna (7.10.2026;
    /// dawniej osobna płyta w tincie szałwii).
    private var statusBar: some View {
        EditorialSettingsCardGroup {
            EditorialSettingsRow(
                icon: "checkmark.shield.fill",
                iconColor: SCPalette.sage,
                title: "Zgoda włączona",
                subtitle: "Wersja \(LegalDocMeta.version) z \(LegalDocMeta.effectiveDate)",
                isLast: true,
                action: nil
            ) {
                EmptyView()
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// „Co wysyłamy do modelu” — kto dostaje dane (Anthropic, model Claude)
    /// i lista z kropkami szałwii; „Czego nie wysyłamy” jedną linią na
    /// półce `wash`.
    private var dataCard: some View {
        EditorialSettingsCardGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text("Co wysyłamy do modelu")
                    .font(.sc(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(AssistantLook.sage(scheme))
                // Odbiorca wprost (App Review 5.1.2(i)) — jak w sekcji 6
                // polityki: model Claude, Anthropic, Stany Zjednoczone.
                Text("Asystent działa na modelu Claude firmy Anthropic (USA). Przy każdej wiadomości wysyłamy tam:")
                    .font(.sc(size: 13.5))
                    .lineSpacing(3)
                    .foregroundStyle(AssistantLook.muted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Self.sentItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(AssistantLook.sage(scheme))
                                .frame(width: 6, height: 6)
                                .padding(.top, 7)
                            Text(item)
                                .font(.sc(size: 14.5))
                                .tracking(-0.2)
                                .lineSpacing(2)
                                .foregroundStyle(AssistantLook.ink(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 5) {
                Text("Czego nie wysyłamy")
                    .font(.sc(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(AssistantLook.faint(scheme))
                Text(Self.notSentItems.joined(separator: " · "))
                    .font(.sc(size: 13.5))
                    .lineSpacing(3)
                    .foregroundStyle(AssistantLook.muted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 11)
            .padding(.bottom, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AssistantLook.wash(scheme))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
            }
        }
    }

    /// Treść przepisana z sekcji 6 polityki prywatności — ekran nie
    /// obiecuje ani mniej, ani więcej.
    private static let sentItems = [
        "Treść wiadomości i rozmowy",
        "Twoje imię, dietę, alergeny",
        "Cel, zapotrzebowanie i makro",
        "Te same dane domowników, tylko za ich zgodą",
        "Nazwę domu, plan tygodnia, notatki pamięci",
        "Katalog przepisów",
    ]
    /// Kroki i hasło Cookidoo tylko wtedy, gdy te funkcje są widoczne
    /// (`FeatureFlags`) — nie mówimy o czymś, czego w aplikacji nie ma.
    private static let notSentItems: [String] = ["Wzrost, waga, płeć", "Rok urodzenia"]
        + (FeatureFlags.health ? ["Kroki"] : [])
        + ["E-mail"]
        + (FeatureFlags.thermomix ? ["Hasło Cookidoo"] : [])

    /// Potwierdzenie = wiersz listy (`EditorialSettingsRow`): kafelek, zdanie
    /// i podpis z zawijaniem, po prawej pole wyboru aplikacji (`SCCheckbox`)
    /// w szałwii. Potwierdzenia są dwa i niezależne, więc to pole wyboru,
    /// a nie kółko.
    private func confirmRow(
        isOn: Binding<Bool>,
        icon: String,
        color: Color,
        title: String,
        caption: String?,
        isLast: Bool
    ) -> some View {
        EditorialSettingsRow(
            icon: icon,
            iconColor: color,
            title: title,
            subtitle: caption,
            isLast: isLast,
            wrapsText: true,
            action: { isOn.wrappedValue.toggle() }
        ) {
            SCCheckbox(on: isOn.wrappedValue, accent: SCPalette.sage)
        }
        .accessibilityAddTraits(isOn.wrappedValue ? [.isSelected] : [])
        .accessibilityLabel(title)
    }

    /// Stopka ARKUSZA z menu. W zakładce stopkę przepływu składa
    /// `AssistantView` (`introFooter`).
    ///
    /// Przyciski z tych samych klocków, co w całej aplikacji: włączenie jak
    /// akcja główna kroku (`EditorialPrimaryActionButton`, ta sama, co
    /// w stopce wprowadzenia), cofnięcie jak każda akcja nieodwracalna
    /// (`SCDestructiveButton` — tylko otwiera potwierdzenie). Wcześniej goły
    /// terakotowy tekst „Cofnij zgodę”, który czytał się jak odnośnik.
    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 10) {
            // Ten sam błąd nad przyciskiem, co w każdym formularzu aplikacji
            // (`SCInlineErrorText`), zamiast własnej plakietki z wykrzyknikiem.
            if let errorMessage = currentDraft.errorMessage {
                SCInlineErrorText(errorMessage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
            }

            if isGranted {
                SCDestructiveButton(
                    title: consents.isBusy ? "Cofam…" : "Cofnij zgodę",
                    icon: "arrow.uturn.backward",
                    isLoading: consents.isBusy
                ) {
                    confirmsRevoke = true
                }
            } else {
                EditorialPrimaryActionButton(
                    title: "Włącz Asystenta",
                    icon: "sparkles",
                    isEnabled: canGrant,
                    isLoading: consents.isBusy,
                    action: grant
                )
                .accessibilityHint(canGrant ? "" : "Najpierw zaznacz oba potwierdzenia")
            }
        }
    }

    // MARK: - Akcje

    private func grant() {
        Task { @MainActor in
            if await Self.grant(consents: consents, source: source, draft: draftBinding) {
                onGranted?()
                if presentation == .sheet { dismiss() }
            }
        }
    }

    private func revoke() {
        draftBinding.wrappedValue.errorMessage = nil
        Task { @MainActor in
            if let message = await consents.revokeAssistant(source: source) {
                draftBinding.wrappedValue.errorMessage = message
            } else if presentation == .sheet {
                dismiss()
            }
        }
    }
}
