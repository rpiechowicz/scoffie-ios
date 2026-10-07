import SwiftUI

/// Półarkusz po kciuku w dół — podpowiedź „co nie zagrało” (27.09.2026).
///
/// To NIE zgłoszenie (`AssistantReportSheet`: błąd, zagrożenie, obraza —
/// sprawa do decyzji), tylko sygnał jakości: idzie tym samym
/// `PUT agent/messages/:id/feedback` co kciuk, z `rating: DOWN`, `tags`
/// (`AGENT_FEEDBACK_TAGS`) i `comment`, i trafia do działu „Oceny” w panelu.
/// Działa także przy odpowiedzi już zgłoszonej.
///
/// 6.10.2026 („jak od Apple” — mniej ceremonii): PÓŁARKUSZ zamiast pełnego
/// ekranu. Kompaktowy nagłówek (jak „Jak pracowałem”), cztery powody w jednej
/// karcie (krążek w kolorze powodu · nazwa · `SCCheckbox`), jedno pole
/// i „Wyślij” w stopce. Bez zdania wstępu, bez cytatu odpowiedzi i bez ekranu
/// podziękowania — po wysłaniu arkusz się zamyka, a „Dzięki za podpowiedź”
/// mówi toast. Krzyżyk zostawia sam kciuk (ocena zapisała się przy
/// stuknięciu). Kciuk W GÓRĘ arkusza nie otwiera wcale — dawny kierunek
/// „Co było dobre?” odpadł razem z tym ekranem.
///
/// Kciuk w dół otwiera ten arkusz sam; istniejąca podpowiedź otwiera się
/// z „⋯” („Popraw podpowiedź”) z wypełnionymi polami.
///
/// 7.10.2026 (nowy język arkuszy): powody to lista Ustawień —
/// `EditorialSettingsCardGroup` + `EditorialSettingsRow` (pełny kafelek
/// w kolorze powodu, nazwa, `SCCheckbox`) zamiast własnej karty z krążkami
/// w tincie i kreską `AssistantLook.hair`; pole w karcie o tym samym
/// promieniu (18) co lista.
struct AssistantSuggestionSheet: View {
    let message: AgentChatMessage
    /// Oddaje komunikat błędu albo `nil` przy sukcesie.
    let onSubmit: (_ tags: [String], _ comment: String?) async -> String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.toasts) private var toasts

    @State private var tags: Set<String> = []
    @State private var comment = ""
    @State private var didPrefill = false
    @State private var isSending = false
    @State private var errorMessage: String?
    /// Pół ekranu na powody; pisanie rozwija arkusz na całą wysokość —
    /// klawiatura w połowie ekranu zostawiałaby na pole jedną linijkę.
    @State private var detent: PresentationDetent = .medium
    @FocusState private var commentFocused: Bool

    private static let commentLimit = 1000

    /// Poprawiamy podpowiedź, która już jest (z „⋯”).
    private var isEditing: Bool { message.feedback == .down && message.feedbackNote != nil }

    private struct Reason: Identifiable {
        let id: String
        let title: String
        let icon: String
        /// Kolor kafelka — głęboki wariant palety, jak w Ustawieniach.
        let color: Color
    }

    /// Powody — `AGENT_FEEDBACK_DOWN_TAGS` na serwerze. Bez linijki opisu pod
    /// nazwą, więc nazwy mówią same za siebie: „Za dużo tekstu” i „Za długo
    /// czekałem” zamiast dwuznacznych „Za długo” / „Za wolno”.
    private static let reasons: [Reason] = [
        Reason(id: "NOT_WHAT_I_ASKED", title: "Nie o to pytałem", icon: "questionmark.bubble.fill", color: SCPalette.indigo),
        Reason(id: "BAD_DISHES", title: "Nietrafione dania", icon: "fork.knife", color: SCPalette.terracotta),
        Reason(id: "TOO_LONG", title: "Za dużo tekstu", icon: "text.alignleft", color: SCPalette.butter),
        Reason(id: "TOO_SLOW", title: "Za długo czekałem", icon: "tortoise.fill", color: SCPalette.sage),
    ]

    private var accent: Color { AssistantLook.terra(scheme) }

    private var trimmedComment: String {
        comment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !tags.isEmpty || !trimmedComment.isEmpty
    }

    var body: some View {
        AssistantSheetScaffold(
            eyebrow: "Słaba odpowiedź",
            title: isEditing ? "Popraw podpowiedź" : "Co nie zagrało?",
            icon: "hand.thumbsdown",
            accent: accent,
            compact: true,
            onClose: { dismiss() },
            footer: { footer }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                reasonList
                commentField
                if let errorMessage {
                    SCInlineErrorText(errorMessage)
                }
            }
            // Oddech pod nagłówkiem — karta nie klei się do tytułu.
            .padding(.top, 10)
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(40)
        .presentationBackground(Color.scPageBase(scheme))
        .interactiveDismissDisabled(isSending)
        .onChange(of: commentFocused) { _, focused in
            if focused { detent = .large }
        }
        .onAppear(perform: prefill)
    }

    // MARK: - Powody

    private var reasonList: some View {
        EditorialSettingsCardGroup {
            ForEach(Array(Self.reasons.enumerated()), id: \.element.id) { index, reason in
                row(reason, isLast: index == Self.reasons.count - 1)
            }
        }
    }

    private func row(_ reason: Reason, isLast: Bool) -> some View {
        let isOn = tags.contains(reason.id)
        return EditorialSettingsRow(
            icon: reason.icon,
            iconColor: reason.color,
            title: reason.title,
            isLast: isLast,
            action: {
                if isOn { tags.remove(reason.id) } else { tags.insert(reason.id) }
            }
        ) {
            SCCheckbox(on: isOn, accent: accent, size: 22)
        }
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    // MARK: - Komentarz

    private var commentField: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(alignment: .trailing, spacing: 8) {
            TextField(
                "Jak powinno być? Np. krócej, obiad do 30 minut",
                text: $comment,
                axis: .vertical
            )
            .lineLimit(3...8)
            .font(.sc(size: 15.5))
            .focused($commentFocused)
            .onChange(of: comment) { _, value in
                if value.count > Self.commentLimit {
                    comment = String(value.prefix(Self.commentLimit))
                }
            }

            // Licznik dopiero pod koniec limitu — wcześniej to szum.
            if comment.count > Self.commentLimit - 100 {
                Text("\(comment.count)/\(Self.commentLimit)")
                    .font(.sc(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(AssistantLook.faint(scheme))
            }
        }
        .padding(16)
        .background(shape.fill(Color.scTileBg(scheme)))
        .overlay(
            shape.strokeBorder(
                commentFocused ? accent.opacity(0.45) : Color.scTileStroke(scheme),
                lineWidth: commentFocused ? 1.2 : 1
            )
        )
        .contentShape(shape)
        .onTapGesture { commentFocused = true }
    }

    // MARK: - Stopka

    /// Jeden przycisk — zamyka krzyżyk (sama ocena zostaje).
    private var footer: some View {
        AssistantPrimaryButton(
            action: AssistantCardAction(
                title: isEditing ? "Zapisz" : "Wyślij",
                icon: "paperplane",
                action: submit
            ),
            isBusy: isSending
        )
        .disabled(!canSend)
        .opacity(canSend ? 1 : 0.45)
    }

    // MARK: - Logika

    /// Istniejąca podpowiedź wchodzi do pól RAZ — jak w arkuszu zgłoszenia
    /// (bez własnego `init` z `State(initialValue:)`).
    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        // Tylko podpowiedź do kciuka w dół — wiadomość po 👍 może nieść
        // starą notatkę z historii (dawne „Co było dobre?”).
        guard message.feedback == .down, let note = message.feedbackNote else { return }
        tags = Set(note.tags)
        comment = note.comment ?? ""
    }

    private func submit() {
        guard canSend, !isSending else { return }
        isSending = true
        errorMessage = nil
        commentFocused = false
        // Tylko znane powody, w kolejności z listy — panel liczy je tak samo,
        // serwer i tak odrzuca obce, a lokalna notatka nie może ich zapamiętać.
        let ordered = Self.reasons.map(\.id).filter { tags.contains($0) }
        let text = trimmedComment
        Task { @MainActor in
            let failure = await onSubmit(ordered, text.isEmpty ? nil : text)
            isSending = false
            if let failure {
                errorMessage = failure
                return
            }
            toasts.success("Dzięki za podpowiedź")
            dismiss()
        }
    }
}
