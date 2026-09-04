import SwiftUI

/// „Zgłoś odpowiedź" — cztery powody z serwera (`AGENT_REPORT_REASONS`)
/// i opcjonalny komentarz. Zgłoszenie idzie na `POST /agent/messages/:id/report`;
/// serwer zapisuje treść zgłoszonej odpowiedzi razem z powodem.
struct AssistantReportSheet: View {
    let message: AgentChatMessage
    /// Oddaje komunikat błędu albo `nil` przy sukcesie.
    let onSubmit: (_ reason: String, _ comment: String?) async -> String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var reason: String = "WRONG"
    @State private var comment: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var isDone = false

    private static let reasons: [(code: String, title: String, detail: String)] = [
        ("WRONG", "Błąd merytoryczny", "Zły przepis, zła liczba, zignorowany alergen."),
        ("UNSAFE", "Może zaszkodzić zdrowiu", "Rada, której nie powinno się stosować."),
        ("OFFENSIVE", "Obraźliwe albo nie na temat", "Treść niezwiązana z planowaniem posiłków."),
        ("OTHER", "Coś innego", "Opisz w komentarzu."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EditorialSheetHeader(eyebrow: "Asystent", title: "Zgłoś odpowiedź") {
                        dismiss()
                    }

                    Text(message.text)
                        .font(.system(size: 13))
                        .lineLimit(4)
                        .foregroundStyle(Color.scMuted(scheme))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.scTileBg(scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.scTileStroke(scheme), lineWidth: 1))

                    EditorialSheetSectionLabel(title: "Co jest nie tak")
                    VStack(spacing: 0) {
                        ForEach(Array(Self.reasons.enumerated()), id: \.element.code) { index, item in
                            Button {
                                reason = item.code
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.system(size: 14.5, weight: .semibold))
                                            .foregroundStyle(Color.scLabel(scheme))
                                        Text(item.detail)
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(Color.scMuted(scheme))
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: reason == item.code ? "largecircle.fill.circle" : "circle")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(reason == item.code ? SCPalette.terracotta : Color.scTileStroke(scheme))
                                }
                                .padding(14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(reason == item.code ? [.isSelected] : [])
                            if index < Self.reasons.count - 1 {
                                Rectangle().fill(Color.scRule(scheme)).frame(height: 1)
                            }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.scTileBg(scheme)))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.scTileStroke(scheme), lineWidth: 1))

                    EditorialSheetSectionLabel(title: "Komentarz (opcjonalnie)")
                    TextField("Co powinno być inaczej?", text: $comment, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.system(size: 14.5))
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.scTileBg(scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.scTileStroke(scheme), lineWidth: 1))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SCPalette.terracotta)
                    }

                    Button(action: submit) {
                        HStack(spacing: 8) {
                            if isSending {
                                ProgressView().controlSize(.small).tint(Color.scPageBase(scheme))
                            } else {
                                Image(systemName: isDone ? "checkmark" : "flag.fill")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            Text(isDone ? "Zgłoszono" : "Wyślij zgłoszenie")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundStyle(Color.scPageBase(scheme))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Capsule().fill(isDone ? SCPalette.sage : SCPalette.terracotta))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending || isDone)

                    Text("Zgłoszenie trafia do administratora razem z treścią tej odpowiedzi. Nie zmienia planu ani rozmowy.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.scFaint(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(SCPageBackground(scheme: scheme).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
    }

    private func submit() {
        guard !isSending else { return }
        isSending = true
        errorMessage = nil
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            let failure = await onSubmit(reason, trimmed.isEmpty ? nil : trimmed)
            isSending = false
            if let failure {
                errorMessage = failure
            } else {
                isDone = true
                try? await Task.sleep(for: .milliseconds(700))
                dismiss()
            }
        }
    }
}
