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
        let year = UserDefaults.standard.integer(forKey: "settings.profile.yearOfBirth")
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
                }
                .presentationDragIndicator(.visible)
            }
        }
        .interactiveDismissDisabled(consents.isBusy)
        .onAppear { if ageFromProfile { draftBinding.wrappedValue.confirmsAge = true } }
        .task { await consents.refresh() }
        .sheet(isPresented: $showPrivacyPolicy) {
            LegalDocumentSheet(title: "Polityka prywatności") {
                PrivacyPolicyContent()
            }
        }
        .alert("Cofnąć zgodę?", isPresented: $confirmsRevoke) {
            Button("Anuluj", role: .cancel) {}
            Button("Cofnij zgodę", role: .destructive) { revoke() }
        } message: {
            Text("Asystent przestanie dla Ciebie działać, a Twoje dane o diecie nie będą już wysyłane do modelu. Zapisane rozmowy zostają, dopóki ich nie usuniesz.")
        }
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
                            : "Zanim Asystent wyśle cokolwiek do modelu, potrzebuje Twojej zgody.",
                        typing: isGranted ? nil : 0
                    )
                    .padding(.bottom, 8)

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

    /// Wspólne sekcje zakładki i arkusza.
    @ViewBuilder
    private var sections: some View {
        dataCard

        if isUnderage, !isGranted {
            underageNotice
                .padding(.top, 14)
        }

        AssistantGroup(title: "Twoje potwierdzenia", aside: { confirmationsBadge }) {
            confirmRow(
                isOn: isGranted ? .constant(true) : draftBinding.confirmsAge,
                title: "Mam ukończone 16 lat",
                caption: ageFromProfile ? "Zaznaczone według roku urodzenia z Twojego profilu" : nil,
                first: true
            )
            confirmRow(
                isOn: isGranted ? .constant(true) : draftBinding.confirmsData,
                title: "Zgadzam się, żeby Scoffie przetwarzał moje dane o diecie i alergiach w asystencie",
                caption: "Wyraźna zgoda (art. 9 ust. 2 lit. a RODO) w zakresie opisanym wyżej.",
                first: false
            )
        }
        .padding(.top, 2)
        .opacity(isGranted || isUnderage ? 0.9 : 1)
        .disabled(isGranted || isUnderage)

        // Dostawca i podwykonawcy zostają w polityce prywatności
        // (sekcja 6, link niżej) — na ekranie asystent występuje
        // jako Scoffie, bez nazw modeli i firm trzecich.
        Text("Asystent to program — może się mylić i nie zastępuje dietetyka ani lekarza. Zgodę cofniesz w każdej chwili w menu asystenta.")
            .font(.system(size: 12.5))
            .lineSpacing(3)
            .foregroundStyle(AssistantLook.faint(scheme))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.top, 14)

        Button {
            showPrivacyPolicy = true
        } label: {
            HStack(spacing: 5) {
                Text("Polityka prywatności, sekcja 6")
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(AssistantLook.terra(scheme))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Klocki

    /// Rok urodzenia z profilu mówi „mniej niż 16" — potwierdzenia są
    /// wygaszone, przycisk nieaktywny. Serwer sprawdza to samo przy zapisie.
    private var underageNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SCPalette.terracotta)
            VStack(alignment: .leading, spacing: 3) {
                Text("Asystent jest dostępny od 16 lat")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Color.scLabel(scheme))
                Text("Według roku urodzenia w Twoim profilu to jeszcze nie ten wiek. Jeśli rok jest błędny, popraw go w Ustawieniach → Profil i wróć tutaj.")
                    .font(.system(size: 12.5))
                    .lineSpacing(2)
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SCPalette.terracotta.opacity(0.10)))
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
            .font(.system(size: 12, weight: complete ? .bold : .semibold))
            .monospacedDigit()
            .foregroundStyle(complete ? AssistantLook.sage(scheme) : AssistantLook.faint(scheme))
            .contentTransition(.numericText(value: Double(done)))
            .animation(SCMotion.textRoll, value: done)
    }

    /// Stan zgody w tincie szałwii: kafelek z tarczą, „Zgoda włączona” i pod
    /// spodem wersja dokumentu — ten sam układ, co kafelek z tytułem
    /// w wierszach Ustawień, zamiast jednej linijki ściśniętej do 85 %.
    private var statusBar: some View {
        HStack(spacing: 12) {
            SCHeaderIconWell(icon: "checkmark.shield.fill", accent: SCPalette.sage, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Zgoda włączona")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AssistantLook.sage(scheme))
                Text("Wersja \(LegalDocMeta.version) z \(LegalDocMeta.effectiveDate)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(AssistantLook.muted(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AssistantLook.sageTint(scheme)))
        .accessibilityElement(children: .combine)
    }

    /// „Co wysyłamy do modelu” jako lista z kropkami szałwii; „Czego nie
    /// wysyłamy” jedną linią na półce `wash`.
    private var dataCard: some View {
        AssistantGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text("Co wysyłamy do modelu")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(AssistantLook.sage(scheme))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Self.sentItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(AssistantLook.sage(scheme))
                                .frame(width: 6, height: 6)
                                .padding(.top, 7)
                            Text(item)
                                .font(.system(size: 14.5))
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
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(AssistantLook.faint(scheme))
                Text(Self.notSentItems.joined(separator: " · "))
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .foregroundStyle(AssistantLook.muted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 11)
            .padding(.bottom, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AssistantLook.wash(scheme))
            .overlay(alignment: .top) { AssistantCardRule() }
        }
    }

    /// Treść przepisana z sekcji 6 polityki prywatności — ekran nie
    /// obiecuje ani mniej, ani więcej.
    private static let sentItems = [
        "Treść wiadomości i rozmowy",
        "Twoje imię, dietę, alergeny, wykluczenia",
        "Cel, zapotrzebowanie i makro, maks. czas gotowania",
        "Te same dane domowników, tylko za ich zgodą",
        "Nazwę domu, plan tygodnia, notatki pamięci",
        "Katalog przepisów",
    ]
    private static let notSentItems = ["Wzrost, waga, płeć", "Rok urodzenia", "Kroki", "E-mail", "Hasło Cookidoo"]

    /// `ConsentRow`: tytuł i podpis z zawijaniem, po prawej pole wyboru
    /// aplikacji (`SCCheckbox`) w szałwii. Potwierdzenia są dwa i niezależne,
    /// więc to pole wyboru, a nie kółko — kółko z ptaszkiem 28 pt było
    /// jedynym takim znacznikiem w aplikacji.
    private func confirmRow(isOn: Binding<Bool>, title: String, caption: String?, first: Bool) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            AssistantRow(
                title: title,
                subtitle: caption,
                first: first,
                subtitleWraps: true,
                verticalPadding: 12,
                alignment: .top,
                leading: { EmptyView() },
                trailing: {
                    SCCheckbox(on: isOn.wrappedValue, accent: SCPalette.sage)
                        .padding(.top, 1)
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
