import SwiftUI

/// „Zanim zaczniemy" — stan zakładki Asystent zamiast rozmowy, dopóki nie
/// ma zgody (projekt „Asystent Zgoda", 3.09.2026). Ten sam widok jako arkusz
/// z menu ⋯ → „Prywatność i zgoda": wtedy pokazuje pasek statusu, wygaszone
/// potwierdzenia i „Cofnij zgodę".
///
/// Serwer wymaga DWÓCH zgód (wiek 16+ i przekazanie danych o diecie do
/// Anthropic), więc „Włącz asystenta" odblokowuje się dopiero po dwóch
/// stuknięciach. Treść „co wysyłamy / czego nie" jest przepisana z sekcji 6
/// polityki prywatności — ekran nie obiecuje ani mniej, ani więcej.
struct AssistantConsentGateView: View {
    enum Presentation {
        /// W zakładce, pod nagłówkiem „Asystent"; bez własnego nagłówka.
        case inline
        /// Arkusz z menu — z nagłówkiem i przyciskiem zamknięcia.
        case sheet
    }

    let consents: ConsentStore
    let source: String
    var presentation: Presentation = .inline
    var onGranted: (() -> Void)? = nil
    var onShowCapabilities: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var confirmsAge = false
    @State private var confirmsData = false
    @State private var errorMessage: String?
    @State private var showPrivacyPolicy = false
    @State private var confirmsRevoke = false

    private var isGranted: Bool { consents.assistantGranted }
    private var canGrant: Bool { confirmsAge && confirmsData }

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

    private var content: some View {
        VStack(spacing: 0) {
            if presentation == .sheet {
                EditorialSheetHeader(eyebrow: "Asystent AI", title: isGranted ? "Zgoda na asystenta" : "Zanim zaczniemy") {
                    dismiss()
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }

            if isGranted {
                statusBar
                    .padding(.horizontal, WMPageMetrics.horizontal)
                    .padding(.top, presentation == .sheet ? 12 : 0)
                    .padding(.bottom, 4)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if presentation == .inline {
                        VStack(alignment: .leading, spacing: 4) {
                            if !isGranted {
                                AssistantSectionLabel(text: "Asystent AI", color: WMPalette.terracotta)
                            }
                            Text("Zanim zaczniemy")
                                .font(.system(size: 26, weight: .bold))
                                .tracking(-0.6)
                                .foregroundStyle(Color.wmLabel(scheme))
                            if !isGranted, errorMessage == nil {
                                Text("Asystent układa plan tygodnia, podmienia dania i pilnuje alergenów całego domu. Zanim wyśle cokolwiek do modelu, potrzebuje Twojej zgody.")
                                    .font(.system(size: 13.5))
                                    .lineSpacing(2)
                                    .foregroundStyle(Color.wmMuted(scheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    // Jeden wiersz-link zamiast trzech kafli „co potrafi" —
                    // odzyskane miejsce trzyma potwierdzenia nad zgięciem.
                    if let onShowCapabilities {
                        Button(action: onShowCapabilities) {
                            HStack(spacing: 12) {
                                AssistantIconTile(icon: "sparkles", accent: .terracotta, size: 36, radius: 11)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Co potrafi asystent")
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .tracking(-0.25)
                                        .foregroundStyle(Color.wmLabel(scheme))
                                    Text("Plan tygodnia, podmiany, makro, zakupy — 14 rzeczy")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.wmMuted(scheme))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.wmFaint(scheme))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.wmTileBg(scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.wmTileStroke(scheme), lineWidth: 1))
                    }

                    dataCard

                    AssistantSurfaceCard {
                        HStack(alignment: .center) {
                            AssistantSectionLabel(text: "Twoje potwierdzenia")
                            Spacer()
                            confirmationsBadge
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                        confirmRow(
                            isOn: isGranted ? .constant(true) : $confirmsAge,
                            title: "Mam ukończone 16 lat",
                            caption: nil,
                            first: true
                        )
                        confirmRow(
                            isOn: isGranted ? .constant(true) : $confirmsData,
                            title: "Zgadzam się, żeby Weekly Meals przetwarzał moje dane o diecie i alergiach w asystencie AI",
                            caption: "Wyraźna zgoda (art. 9 ust. 2 lit. a RODO) w zakresie opisanym wyżej; model językowy dostarcza Anthropic jako podmiot przetwarzający.",
                            first: false
                        )
                    }
                    .opacity(isGranted ? 0.85 : 1)
                    .disabled(isGranted)

                    Text("Model Claude dostarcza Anthropic, PBC (USA); przekazanie poza EOG odbywa się na podstawie standardowych klauzul umownych. Asystent to program, może się mylić i nie zastępuje dietetyka ani lekarza. Zgodę cofniesz w każdej chwili w menu asystenta.")
                        .font(.system(size: 11.5))
                        .lineSpacing(2)
                        .foregroundStyle(Color.wmFaint(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        showPrivacyPolicy = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("Polityka prywatności, sekcja 6")
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WMPalette.terracotta)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, presentation == .sheet ? 20 : WMPageMetrics.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            AssistantStickyFooter { footer }
                .padding(.bottom, presentation == .sheet ? 12 : 0)
        }
        .background(presentation == .sheet ? AnyView(WMPageBackground(scheme: scheme).ignoresSafeArea()) : AnyView(Color.clear))
    }

    // MARK: - Klocki

    /// Licznik zamiast napisu „oba wymagane": 0 z 2 → 1 z 2 → 2 z 2 (zielone),
    /// po zapisie „Zapisane” z ptaszkiem. Mówi to samo, ale zmienia się razem
    /// z tym, co użytkownik robi, zamiast go pouczać.
    private var confirmationsBadge: some View {
        let done = isGranted ? 2 : (confirmsAge ? 1 : 0) + (confirmsData ? 1 : 0)
        let complete = done == 2
        return HStack(spacing: 4) {
            if complete {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
            }
            Text(isGranted ? "Zapisane" : "\(done) z 2")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(complete ? WMPalette.sage : Color.wmFaint(scheme))
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(complete ? Color.wmSageTint(scheme) : Color.wmChipBg(scheme)))
        .animation(.easeInOut(duration: 0.18), value: done)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WMPalette.sage)
            (Text("Zgoda włączona").fontWeight(.semibold)
                + Text(" · wersja dokumentów \(LegalDocMeta.version) z \(LegalDocMeta.effectiveDate)").foregroundColor(Color.wmMuted(scheme)))
                .font(.system(size: 12))
                .foregroundStyle(Color.wmLabel(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.wmSageTint(scheme)))
    }

    private var dataCard: some View {
        AssistantSurfaceCard(padding: 0) {
            HStack(alignment: .top, spacing: 14) {
                dataList(
                    label: "Co wysyłamy do modelu",
                    color: WMPalette.sage,
                    dot: true,
                    items: ["Treść wiadomości i rozmowy", "Twoje imię, dietę, alergeny, wykluczenia", "Cel, zapotrzebowanie i makro, maks. czas gotowania", "Te same dane domowników, tylko za ich zgodą", "Nazwę domu, plan tygodnia, notatki pamięci", "Katalog przepisów"]
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                dataList(
                    label: "Czego nie wysyłamy",
                    color: Color.wmFaint(scheme),
                    dot: false,
                    items: ["Wzrost, waga, płeć", "Rok urodzenia", "Kroki", "E-mail", "Hasło Cookidoo"]
                )
                .frame(width: 118, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 11)
        }
    }

    private func dataList(label: String, color: Color, dot: Bool, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AssistantSectionLabel(text: label, color: color)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 7) {
                        Circle().fill(color).opacity(dot ? 1 : 0.55).frame(width: 5, height: 5).padding(.top, 5)
                        Text(item)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.wmLabel(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func confirmRow(isOn: Binding<Bool>, title: String, caption: String?, first: Bool) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .tracking(-0.25)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caption {
                        Text(caption)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.wmMuted(scheme))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().fill(isOn.wrappedValue ? WMPalette.terracotta : Color.clear)
                    Circle().stroke(isOn.wrappedValue ? Color.clear : Color.wmFaint(scheme), lineWidth: 1.5)
                    if isOn.wrappedValue {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Color.wmPageBase(scheme))
                    }
                }
                .frame(width: 28, height: 28)
                .shadow(color: isOn.wrappedValue ? WMPalette.terracotta.opacity(0.35) : .clear, radius: 6, y: 3)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            // Dół odrobinę większy: zaznaczony wiersz ma tło i bez tego
            // wyglądał na przyklejony do krawędzi karty.
            .padding(.bottom, 16)
            .background(isOn.wrappedValue ? WMPalette.terracotta.opacity(0.07) : Color.clear)
            .overlay(alignment: .top) {
                if !first { Rectangle().fill(Color.wmRule(scheme)).frame(height: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn.wrappedValue ? [.isSelected] : [])
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(errorMessage)
                        .font(.system(size: 12.5, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(WMPalette.terracotta)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(WMPalette.terracotta.opacity(0.12)))
            }

            if isGranted {
                AssistantTextButton(title: consents.isBusy ? "Cofam…" : "Cofnij zgodę", role: .destructive) {
                    confirmsRevoke = true
                }
                .disabled(consents.isBusy)
            } else {
                WMSoftButton(
                    title: "Włącz asystenta",
                    leadingIcon: "sparkles",
                    isEnabled: canGrant && !consents.isBusy,
                    isLoading: consents.isBusy,
                    action: grant
                )
                .accessibilityHint(canGrant ? "" : "Najpierw zaznacz oba potwierdzenia")
            }
        }
    }

    // MARK: - Akcje

    private func grant() {
        errorMessage = nil
        Task { @MainActor in
            if let message = await consents.grantAssistant(source: source) {
                // Pełny komunikat z serwera — bez niego „nie udało się" nie mówi,
                // czy to sieć, walidacja czy stara wersja aplikacji.
                errorMessage = message.isEmpty ? "Nie udało się zapisać zgody. Spróbuj ponownie." : "Nie udało się zapisać zgody: \(message)"
            } else {
                onGranted?()
                if presentation == .sheet { dismiss() }
            }
        }
    }

    private func revoke() {
        errorMessage = nil
        Task { @MainActor in
            if let message = await consents.revokeAssistant(source: source) {
                errorMessage = message
            } else if presentation == .sheet {
                dismiss()
            }
        }
    }
}
