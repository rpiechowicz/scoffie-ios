import SwiftUI

/// „Co poprawić?” — podpowiedź do kciuka w dół (27.09.2026, Rafał: „jak daję
/// łapkę w dół i mam już zgłoszenie, to chcę dodatkowe zgłoszenie albo nową
/// kategorię o sugestię”).
///
/// To NIE zgłoszenie (`AssistantReportSheet`: błąd, zagrożenie, obraza —
/// sprawa do decyzji), tylko sygnał jakości. Idzie tym samym
/// `PUT agent/messages/:id/feedback` co kciuk, z `rating: DOWN`, `tags`
/// (`AGENT_FEEDBACK_TAGS`) i `comment`, i trafia do działu „Oceny” w panelu.
///
/// Runda 2 tego samego dnia („uprość to i zrób ładniej”): półarkusz
/// z kompaktowym nagłówkiem, CZTERY kafle 2 × 2 (glif w krążku + jedno-dwa
/// słowa, zaznaczenie tintem `scChoiceSurface(.tile)` z ptaszkiem) i jedno pole
/// „Jak powinno być?”. „Coś innego” jako kafel odpadło — od tego jest pole.
/// Bez etykiet sekcji i zdań objaśnień. Istniejąca podpowiedź otwiera się do
/// poprawienia.
///
/// Runda 3: arkusz otwiera SAM kciuk w dół (ocena zapisuje się od razu,
/// podpowiedź jest nieobowiązkowa — krzyżyk zostawia sam kciuk). Nagłówek
/// „Słaba odpowiedź · Co poprawić?” z kciukiem w kafelku; każdy powód ma
/// własny kolor od razu (nie dopiero po zaznaczeniu) — zaznaczenie to tint
/// tego koloru i ptaszek w krążku.
///
/// Runda 4 („zmień układ tych wartości, usuń animacje z check, bo są za
/// wolne”): powody to LISTA w jednej karcie — krążek w kolorze powodu,
/// nazwa, `SCCheckbox` po prawej (wybór „wiele” w całej aplikacji), wiersze
/// rozdzielone włoskowatą kreską jak w Ustawieniach. Bez `withAnimation`
/// i bez podmiany glifu: pole wyboru ma własną krótką sprężynę (0,28 s),
/// reszta zmienia się w tej samej klatce.
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

    private enum Tone { case butter, indigo, terra, sage }

    private struct Option: Identifiable {
        let id: String
        let title: String
        let icon: String
        let tone: Tone
    }

    private static let options: [Option] = [
        Option(id: "TOO_LONG", title: "Za długo", icon: "text.alignleft", tone: .butter),
        Option(id: "NOT_WHAT_I_ASKED", title: "Nie o to pytałem", icon: "questionmark.bubble", tone: .indigo),
        Option(id: "BAD_DISHES", title: "Nietrafione dania", icon: "fork.knife", tone: .terra),
        Option(id: "TOO_SLOW", title: "Za wolno", icon: "tortoise", tone: .sage),
    ]

    private func color(_ tone: Tone) -> Color {
        switch tone {
        case .butter: return AssistantLook.butter(scheme)
        case .indigo: return AssistantLook.indigo(scheme)
        case .terra: return AssistantLook.terra(scheme)
        case .sage: return AssistantLook.sage(scheme)
        }
    }

    private var trimmedComment: String {
        comment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !tags.isEmpty || !trimmedComment.isEmpty
    }

    var body: some View {
        AssistantSheetScaffold(
            eyebrow: "Słaba odpowiedź",
            title: isEditing ? "Popraw podpowiedź" : "Co poprawić?",
            icon: "hand.thumbsdown",
            compact: true,
            onClose: { dismiss() },
            footer: { sendButton }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                reasonList

                TextField("Jak powinno być? (opcjonalnie)", text: $comment, axis: .vertical)
                    .lineLimit(2...5)
                    .font(.system(size: 15))
                    .focused($commentFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.scTileBg(scheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                commentFocused ? AssistantLook.terra(scheme).opacity(0.45) : Color.scTileStroke(scheme),
                                lineWidth: commentFocused ? 1.2 : 1
                            )
                    )
                    .animation(.smooth(duration: 0.2), value: commentFocused)

                if let errorMessage {
                    SCInlineErrorText(errorMessage)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(40)
        .presentationBackground(Color.scPageBase(scheme))
        .onAppear(perform: prefill)
    }

    /// Powody w jednej karcie, wiersz pod wierszem.
    private var reasonList: some View {
        let shape = RoundedRectangle(cornerRadius: AssistantCardMetrics.listRadius, style: .continuous)
        return VStack(spacing: 0) {
            ForEach(Array(Self.options.enumerated()), id: \.element.id) { index, option in
                if index > 0 {
                    Rectangle()
                        .fill(AssistantLook.hair(scheme))
                        .frame(height: 1)
                        .padding(.leading, 56)
                }
                row(option)
            }
        }
        .background(shape.fill(Color.scTileBg(scheme)))
        .overlay(shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
    }

    /// Wiersz powodu: krążek w kolorze powodu, nazwa, pole wyboru.
    private func row(_ option: Option) -> some View {
        let isOn = tags.contains(option.id)
        let accent = color(option.tone)
        return Button {
            if isOn { tags.remove(option.id) } else { tags.insert(option.id) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(accent.opacity(scheme == .dark ? 0.18 : 0.13))
                    Image(systemName: option.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .frame(width: 30, height: 30)

                Text(option.title)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(AssistantLook.ink(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)

                SCCheckbox(on: isOn, accent: AssistantLook.terra(scheme), size: 22)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private var sendButton: some View {
        AssistantPrimaryButton(
            action: AssistantCardAction(
                title: isDone ? "Dzięki!" : (isEditing ? "Zapisz podpowiedź" : "Wyślij"),
                icon: isDone ? "checkmark" : "paperplane",
                action: submit
            ),
            isBusy: isSending,
            tint: isDone ? AssistantLook.sage(scheme) : nil
        )
        .disabled(!canSend || isDone)
        .opacity(canSend || isDone ? 1 : 0.45)
        .animation(.easeOut(duration: 0.12), value: canSend)
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
        // Powód spoza kafli (stare „OTHER”) zostaje, jeśli był zaznaczony.
        let known = Self.options.map(\.id)
        let ordered = known.filter { tags.contains($0) } + tags.subtracting(known).sorted()
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
