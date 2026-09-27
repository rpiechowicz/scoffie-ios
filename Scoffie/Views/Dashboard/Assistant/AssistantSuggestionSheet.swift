import SwiftUI

/// „Co poprawić?” — podpowiedź do kciuka w dół (27.09.2026, Rafał: „jak daję
/// łapkę w dół i mam już zgłoszenie, to chcę dodatkowe zgłoszenie albo nową
/// kategorię o sugestię”).
///
/// To NIE zgłoszenie (`AssistantReportSheet`: błąd, zagrożenie, obraza —
/// sprawa do decyzji), tylko sygnał jakości: szybkie powody
/// (`AGENT_FEEDBACK_TAGS` z serwera) i zdanie „jak powinno być”. Idzie tym
/// samym `PUT agent/messages/:id/feedback` co kciuk, z `rating: DOWN`, i trafia
/// do działu „Oceny” w panelu. Działa także przy odpowiedzi już zgłoszonej.
/// Istniejąca podpowiedź otwiera się do poprawienia.
struct AssistantSuggestionSheet: View {
    let message: AgentChatMessage
    /// Oddaje komunikat błędu albo `nil` przy sukcesie.
    let onSubmit: (_ tags: [String], _ comment: String?) async -> String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var tags: Set<String> = []
    @State private var comment = ""
    @State private var didPrefill = false
    @State private var isSending = false
    @State private var isDone = false
    @State private var errorMessage: String?
    @FocusState private var commentFocused: Bool

    private var isEditing: Bool { message.feedbackNote != nil }

    private static let options: [(code: String, title: String, icon: String)] = [
        ("TOO_LONG", "Za długo", "text.alignleft"),
        ("NOT_WHAT_I_ASKED", "Nie o to pytałem", "questionmark.bubble"),
        ("BAD_DISHES", "Nietrafione dania", "fork.knife"),
        ("TOO_SLOW", "Za wolno", "tortoise"),
        ("OTHER", "Coś innego", "ellipsis"),
    ]

    private var trimmedComment: String {
        comment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !tags.isEmpty || !trimmedComment.isEmpty
    }

    var body: some View {
        AssistantSheetScaffold(
            eyebrow: "Podpowiedź",
            title: isEditing ? "Popraw podpowiedź" : "Co poprawić?",
            icon: "lightbulb",
            onClose: { dismiss() },
            footer: { sendButton }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                EditorialSheetSectionLabel(title: "Co było nie tak")
                AllergenChipFlow(spacing: 8) {
                    ForEach(Self.options, id: \.code) { option in
                        let isOn = tags.contains(option.code)
                        AssistantChip(
                            title: option.title,
                            icon: isOn ? "checkmark" : option.icon,
                            highlighted: isOn
                        ) {
                            if isOn { tags.remove(option.code) } else { tags.insert(option.code) }
                        }
                        .accessibilityAddTraits(isOn ? [.isSelected] : [])
                    }
                }

                EditorialSheetSectionLabel(title: "Jak powinno być")
                    .padding(.top, 6)
                TextField("Np. krócej, bez ryby, szybsze dania", text: $comment, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(size: 15))
                    .focused($commentFocused)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.scTileBg(scheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                commentFocused ? AssistantLook.terra(scheme).opacity(0.5) : Color.scTileStroke(scheme),
                                lineWidth: 1
                            )
                    )

                if let errorMessage {
                    SCInlineErrorText(errorMessage)
                }
            }
            .padding(.top, 4)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(40)
        .presentationBackground(Color.scPageBase(scheme))
        .onAppear(perform: prefill)
    }

    private var sendButton: some View {
        AssistantPrimaryButton(
            action: AssistantCardAction(
                title: isDone ? "Wysłano" : (isEditing ? "Zapisz podpowiedź" : "Wyślij podpowiedź"),
                icon: isDone ? "checkmark" : "paperplane",
                action: submit
            ),
            isBusy: isSending,
            tint: isDone ? AssistantLook.sage(scheme) : nil
        )
        .disabled(!canSend || isDone)
        .opacity(canSend || isDone ? 1 : 0.45)
        .animation(.smooth(duration: 0.2), value: canSend)
    }

    /// Istniejąca podpowiedź wchodzi do pól RAZ — jak w arkuszu zgłoszenia
    /// (bez własnego `init` z `State(initialValue:)`).
    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        guard let note = message.feedbackNote else { return }
        tags = Set(note.tags)
        comment = note.comment ?? ""
    }

    private func submit() {
        guard canSend, !isSending, !isDone else { return }
        isSending = true
        errorMessage = nil
        commentFocused = false
        // Kolejność z listy, nie ze zbioru — panel liczy powody tak samo.
        let ordered = Self.options.map(\.code).filter { tags.contains($0) }
        let text = trimmedComment
        Task { @MainActor in
            let failure = await onSubmit(ordered, text.isEmpty ? nil : text)
            isSending = false
            if let failure {
                errorMessage = failure
            } else {
                withAnimation(.smooth(duration: 0.2)) { isDone = true }
                try? await Task.sleep(for: .milliseconds(700))
                dismiss()
            }
        }
    }
}
