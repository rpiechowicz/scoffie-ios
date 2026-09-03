import SwiftUI

/// Zgoda na asystenta — arkusz blokujący przy 403 `AI_CONSENT_REQUIRED`
/// i ten sam arkusz z Ustawień (włącz / cofnij).
///
/// Serwer wymaga DWÓCH zgód (wiek 16+ i przekazanie danych o diecie do
/// Anthropic), więc przycisk włącza się dopiero po dwóch stuknięciach.
/// Treść „co jest wysyłane / co nie" jest przepisana z sekcji 6 polityki
/// prywatności — arkusz nie obiecuje ani mniej, ani więcej niż dokument.
struct AssistantConsentSheet: View {
    let consents: ConsentStore
    /// Skąd przyszło stuknięcie — do dziennika zgód (`source`).
    let source: String
    /// Po udanym włączeniu (arkusz blokujący wraca do rozmowy).
    var onGranted: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var confirmsAge = false
    @State private var confirmsData = false
    @State private var errorMessage: String?
    @State private var showPrivacyPolicy = false
    @State private var confirmsRevoke = false

    private var isGranted: Bool { consents.assistantGranted }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EditorialSheetHeader(
                        eyebrow: "Asystent AI",
                        title: isGranted ? "Zgoda na asystenta" : "Zanim zaczniemy"
                    ) {
                        dismiss()
                    }

                    if isGranted {
                        statusCard
                    }

                    EditorialSheetSectionLabel(title: "Co wysyłamy do modelu")
                    infoCard(
                        icon: "paperplane.fill",
                        tint: WMPalette.indigo,
                        lines: [
                            "treść Twojej wiadomości i dotychczasowej rozmowy,",
                            "Twoje imię, dietę, alergeny, wykluczone składniki, cel, wyliczone zapotrzebowanie kaloryczne i makro, maksymalny czas gotowania,",
                            "te same dane pozostałych domowników — wyłącznie tych, którzy sami wyrazili zgodę,",
                            "nazwę gospodarstwa, aktualny plan tygodnia i notatki pamięci,",
                            "wspólny katalog przepisów.",
                        ]
                    )

                    EditorialSheetSectionLabel(title: "Czego nie wysyłamy")
                    infoCard(
                        icon: "lock.fill",
                        tint: WMPalette.sage,
                        lines: [
                            "wzrostu, wagi, płci, roku urodzenia,",
                            "kroków ze Zdrowia, adresu e-mail, poświadczeń Cookidoo.",
                        ]
                    )

                    Text("Model językowy Claude dostarcza Anthropic, PBC (Stany Zjednoczone) na zlecenie administratora; przekazanie danych poza EOG odbywa się na podstawie standardowych klauzul umownych. Asystent to program — może się mylić i nie zastępuje dietetyka ani lekarza. Zgodę cofniesz w każdej chwili w menu asystenta.")
                        .font(.system(size: 12.5))
                        .lineSpacing(2)
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        showPrivacyPolicy = true
                    } label: {
                        Label("Polityka prywatności, sekcja 6", systemImage: "doc.text")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(WMPalette.terracotta)
                    }
                    .buttonStyle(.plain)

                    if !isGranted {
                        EditorialSheetSectionLabel(title: "Twoje potwierdzenia")
                        checkCard {
                            checkRow(
                                isOn: $confirmsAge,
                                title: "Mam ukończone 16 lat",
                                detail: "Aplikacja i asystent są dla osób od 16. roku życia."
                            )
                            Rectangle().fill(Color.wmRule(scheme)).frame(height: 1)
                            checkRow(
                                isOn: $confirmsData,
                                title: "Zgadzam się na przekazanie moich danych o diecie i alergiach do Anthropic",
                                detail: "Wyraźna zgoda z art. 9 ust. 2 lit. a RODO — tylko w zakresie opisanym wyżej."
                            )
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WMPalette.terracotta)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isGranted {
                        Button(role: .destructive) {
                            confirmsRevoke = true
                        } label: {
                            Text(consents.isBusy ? "Cofam…" : "Cofnij zgodę")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .foregroundStyle(WMPalette.terracotta)
                                .background(Capsule().fill(WMPalette.terracotta.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .disabled(consents.isBusy)
                    } else {
                        Button(action: grant) {
                            HStack(spacing: 8) {
                                if consents.isBusy {
                                    ProgressView().controlSize(.small).tint(Color.wmPageBase(scheme))
                                } else {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                Text("Włącz asystenta")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundStyle(Color.wmPageBase(scheme))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Capsule().fill(WMPalette.terracotta))
                            .opacity(canGrant ? 1 : 0.45)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canGrant || consents.isBusy)
                        .accessibilityHint(canGrant ? "" : "Najpierw zaznacz oba potwierdzenia")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(WMPageBackground(scheme: scheme).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
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

    private var canGrant: Bool { confirmsAge && confirmsData }

    private func grant() {
        errorMessage = nil
        Task { @MainActor in
            if let message = await consents.grantAssistant(source: source) {
                errorMessage = message
            } else {
                onGranted?()
                dismiss()
            }
        }
    }

    private func revoke() {
        errorMessage = nil
        Task { @MainActor in
            if let message = await consents.revokeAssistant(source: source) {
                errorMessage = message
            } else {
                dismiss()
            }
        }
    }

    // MARK: - Klocki

    private var statusCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(WMPalette.sage.opacity(0.2))
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(WMPalette.sage)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Zgoda włączona")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.wmLabel(scheme))
                Text("Wersja dokumentów \(LegalDocMeta.version) · \(LegalDocMeta.effectiveDate)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.wmMuted(scheme))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.wmTileBg(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.wmTileStroke(scheme), lineWidth: 1))
    }

    private func infoCard(icon: String, tint: Color, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                    Text(line)
                        .font(.system(size: 13.5))
                        .lineSpacing(2)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.wmTileBg(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.wmTileStroke(scheme), lineWidth: 1))
    }

    private func checkCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.wmTileBg(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.wmTileStroke(scheme), lineWidth: 1))
    }

    private func checkRow(isOn: Binding<Bool>, title: String, detail: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isOn.wrappedValue ? WMPalette.terracotta : Color.clear)
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isOn.wrappedValue ? WMPalette.terracotta : Color.wmTileStroke(scheme), lineWidth: 1.5)
                    if isOn.wrappedValue {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Color.wmPageBase(scheme))
                    }
                }
                .frame(width: 24, height: 24)
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Color.wmLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn.wrappedValue ? [.isSelected] : [])
        .accessibilityLabel(title)
    }
}
