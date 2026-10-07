import SwiftUI

/// „Zgłoś odpowiedź" — cztery powody z serwera (`AGENT_REPORT_REASONS`)
/// i opcjonalny komentarz. Zgłoszenie idzie na `POST /agent/messages/:id/report`;
/// serwer zapisuje treść zgłoszonej odpowiedzi razem z powodem.
///
/// Jedno zgłoszenie na odpowiedź (27.09.2026): gdy już jest
/// (`message.report`), arkusz otwiera się jako „Popraw zgłoszenie” z tym
/// samym powodem i komentarzem, a wysłanie je poprawia — drugiego nie ma.
///
/// 7.10.2026 (nowy język arkuszy): szkielet arkuszy Asystenta
/// (`AssistantSheetScaffold` — przypięty nagłówek, stopka w `safeAreaBar`),
/// powody jako lista Ustawień (`EditorialSettingsCardGroup` +
/// `EditorialSettingsRow`: kafelek powodu, nazwa, opis w podpisie,
/// `SCRadioMark`), a „Wyślij zgłoszenie” to `EditorialPrimaryActionButton`
/// w stopce zamiast własnej kapsuły na końcu przewijanej treści.
struct AssistantReportSheet: View {
    let message: AgentChatMessage
    /// Oddaje komunikat błędu albo `nil` przy sukcesie.
    let onSubmit: (_ reason: String, _ comment: String?) async -> String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var reason: String = "WRONG"
    @State private var comment: String = ""
    @State private var didPrefill = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var isDone = false

    private var isEditing: Bool { message.report != nil }

    private struct Reason {
        let code: String
        let title: String
        let detail: String
        let icon: String
        let color: Color
    }

    private static let reasons: [Reason] = [
        Reason(code: "WRONG", title: "Błąd merytoryczny", detail: "Zły przepis, zła liczba, zignorowany alergen.", icon: "exclamationmark.triangle.fill", color: SCPalette.butter),
        Reason(code: "UNSAFE", title: "Może zaszkodzić zdrowiu", detail: "Rada, której nie powinno się stosować.", icon: "cross.case.fill", color: SCPalette.terracotta),
        Reason(code: "OFFENSIVE", title: "Obraźliwe albo nie na temat", detail: "Treść niezwiązana z planowaniem posiłków.", icon: "hand.raised.fill", color: SCPalette.indigo),
        Reason(code: "OTHER", title: "Coś innego", detail: "Opisz w komentarzu.", icon: "ellipsis", color: SettingsAccent.slate),
    ]

    var body: some View {
        NavigationStack {
            // Nagłówek przypięty nad treścią — przy otwartej klawiaturze
            // krzyżyk nie ucieka w górę. Flaga — ta sama, co „Zgłoś
            // odpowiedź” w menu dymka.
            AssistantSheetScaffold(
                title: isEditing ? "Popraw zgłoszenie" : "Zgłoś odpowiedź",
                icon: "flag.fill",
                onClose: { dismiss() },
                footer: { footer }
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(message.text)
                        .font(.sc(size: 13))
                        .lineLimit(4)
                        .foregroundStyle(Color.scMuted(scheme))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.scTileBg(scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))

                    EditorialSheetSectionLabel(title: "Co jest nie tak")
                        .padding(.top, 20)
                    EditorialSettingsCardGroup {
                        ForEach(Array(Self.reasons.enumerated()), id: \.element.code) { index, item in
                            EditorialSettingsRow(
                                icon: item.icon,
                                iconColor: item.color,
                                title: item.title,
                                subtitle: item.detail,
                                isLast: index == Self.reasons.count - 1,
                                action: { reason = item.code }
                            ) {
                                SCRadioMark(isOn: reason == item.code)
                            }
                            .accessibilityAddTraits(reason == item.code ? [.isSelected] : [])
                        }
                    }

                    EditorialSheetSectionLabel(title: "Komentarz (opcjonalnie)")
                        .padding(.top, 20)
                    TextField("Co powinno być inaczej?", text: $comment, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.sc(size: 15))
                        .tint(SCPalette.terracotta)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.scTileBg(scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))

                    if let errorMessage {
                        SCInlineErrorText(errorMessage)
                            .padding(.horizontal, 6)
                            .padding(.top, 10)
                    }

                    Text(isEditing
                         ? "Poprawione zgłoszenie zastąpi poprzednie i wróci do administratora. Nie zmienia planu ani rozmowy."
                         : "Zgłoszenie trafia do administratora razem z treścią tej odpowiedzi. Nie zmienia planu ani rozmowy.")
                        .font(.sc(size: 12.5))
                        .foregroundStyle(Color.scFaint(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                        .padding(.top, 10)
                }
                .padding(.top, 12)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
        .onAppear(perform: prefillExistingReport)
    }

    /// Jeden przycisk w stopce — po wysłaniu w szałwii z ptaszkiem, zanim
    /// arkusz zjedzie.
    private var footer: some View {
        EditorialPrimaryActionButton(
            title: isDone ? (isEditing ? "Poprawiono" : "Zgłoszono") : (isEditing ? "Zapisz zmiany" : "Wyślij zgłoszenie"),
            icon: isDone ? "checkmark" : "flag.fill",
            accent: isDone ? SCPalette.sage : SCPalette.terracotta,
            isLoading: isSending,
            action: submit
        )
    }

    /// Istniejące zgłoszenie wchodzi do pól RAZ, przy pierwszym pojawieniu się.
    /// Celowo nie przez własny `init` z `State(initialValue:)`: z nim wysyłka
    /// padała w `AgentAPIClient.reportMessage` na nieczytelnym `reason`
    /// (27.09.2026) — arkusz wrócił do inicjalizatora generowanego przez
    /// Swifta, z którym działał wcześniej.
    private func prefillExistingReport() {
        guard !didPrefill else { return }
        didPrefill = true
        guard let report = message.report else { return }
        reason = report.reason
        comment = report.comment ?? ""
    }

    private func submit() {
        guard !isSending, !isDone else { return }
        isSending = true
        errorMessage = nil
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            let failure = await onSubmit(reason, trimmed.isEmpty ? nil : trimmed)
            isSending = false
            if let failure {
                errorMessage = failure
            } else {
                // Tytuł roluje się na „Zgłoszono” (`numericText` w przycisku
                // działa tylko w animowanej transakcji).
                withAnimation(SCMotion.textRoll) { isDone = true }
                try? await Task.sleep(for: .milliseconds(700))
                dismiss()
            }
        }
    }
}
