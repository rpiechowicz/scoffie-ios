import SwiftUI

/// Arkusz po kciuku w dół — podpowiedź „co nie zagrało” (27.09.2026).
///
/// To NIE zgłoszenie (`AssistantReportSheet`: błąd, zagrożenie, obraza —
/// sprawa do decyzji), tylko sygnał jakości: idzie tym samym
/// `PUT agent/messages/:id/feedback` co kciuk, z `rating: DOWN`, `tags`
/// (`AGENT_FEEDBACK_TAGS`) i `comment`, i trafia do działu „Oceny” w panelu.
/// Działa także przy odpowiedzi już zgłoszonej.
///
/// Runda 5, od nowa (Rafał: „dodaj jakiś tekst, daj sheet na cały ekran,
/// popraw to całkowicie od nowa — raz a dobrze”). Pełny ekran, zwykły nagłówek
/// arkusza i od góry:
/// 1. jedno zdanie: ocena JUŻ jest zapisana, podpowiedź trafia do zespołu
///    (prawda — nie obiecujemy, że asystent „się uczy”);
/// 2. cytat ocenianej odpowiedzi — wiadomo, czego dotyczy podpowiedź, i widać,
///    co zostanie wysłane razem z nią (serwer bierze migawkę tylko wtedy);
/// 3. „Co nie zagrało” — cztery powody w jednej karcie: krążek w kolorze
///    powodu, nazwa, jedno zdanie opisu, `SCCheckbox` (bez `withAnimation`
///    i podmiany glifu — „animacje check za wolne”);
/// 4. „Jak powinno być” — pole na kilka linii z przykładem;
/// 5. stopka: „Pomiń” (sama ocena zostaje) i „Wyślij”; po wysłaniu arkusz
///    na chwilę pokazuje podziękowanie i sam się zamyka.
/// Kciuk w dół otwiera ten arkusz sam; istniejąca podpowiedź otwiera się do
/// poprawienia (z „⋯”).
///
/// Ten sam arkusz przy kciuku W GÓRĘ („analogicznie dla sytuacji”): „Dobra
/// odpowiedź · Co było dobre?”, cztery powody-lustra (zrozumiał pytanie,
/// trafione dania, krótko i konkretnie, szybko) i pole „Co jeszcze”. Kciuk
/// w górę otwiera go po krótkim „wybuchu” w pasku, żeby animacja zdążyła
/// zagrać.
struct AssistantSuggestionSheet: View {
    let message: AgentChatMessage
    /// Kierunek oceny — od niego nagłówek, zdanie, powody i pole.
    var rating: AgentFeedback = .down
    /// Oddaje komunikat błędu albo `nil` przy sukcesie.
    let onSubmit: (_ tags: [String], _ comment: String?) async -> String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tags: Set<String> = []
    @State private var comment = ""
    @State private var didPrefill = false
    @State private var isSending = false
    @State private var isDone = false
    @State private var errorMessage: String?
    @FocusState private var commentFocused: Bool

    private static let commentLimit = 1000

    private var isEditing: Bool { message.feedbackNote != nil && message.feedback == rating }
    private var isPraise: Bool { rating == .up }

    private enum Tone { case butter, indigo, terra, sage }

    private struct Option: Identifiable {
        let id: String
        let title: String
        let detail: String
        let icon: String
        let tone: Tone
    }

    /// Powody „co nie zagrało” — `AGENT_FEEDBACK_DOWN_TAGS` na serwerze.
    private static let downOptions: [Option] = [
        Option(id: "NOT_WHAT_I_ASKED", title: "Nie o to pytałem", detail: "Odpowiedź minęła się z pytaniem", icon: "questionmark.bubble", tone: .indigo),
        Option(id: "BAD_DISHES", title: "Nietrafione dania", detail: "Nie w moim guście, porze albo diecie", icon: "fork.knife", tone: .terra),
        Option(id: "TOO_LONG", title: "Za długo", detail: "Za dużo tekstu, trudno znaleźć konkret", icon: "text.alignleft", tone: .butter),
        Option(id: "TOO_SLOW", title: "Za wolno", detail: "Za długo czekałem na odpowiedź", icon: "tortoise", tone: .sage),
    ]

    /// Powody „co było dobre” — `AGENT_FEEDBACK_UP_TAGS`, lustro powyższych.
    private static let upOptions: [Option] = [
        Option(id: "UNDERSTOOD", title: "Zrozumiał, o co chodzi", detail: "Odpowiedź trafiła w pytanie", icon: "checkmark.bubble", tone: .indigo),
        Option(id: "GOOD_DISHES", title: "Trafione dania", detail: "W moim guście, porze i diecie", icon: "fork.knife", tone: .terra),
        Option(id: "CONCISE", title: "Krótko i konkretnie", detail: "Bez zbędnego tekstu", icon: "text.justify.left", tone: .butter),
        Option(id: "FAST", title: "Szybko", detail: "Odpowiedź bez czekania", icon: "hare", tone: .sage),
    ]

    private var options: [Option] { isPraise ? Self.upOptions : Self.downOptions }

    private func color(_ tone: Tone) -> Color {
        switch tone {
        case .butter: return AssistantLook.butter(scheme)
        case .indigo: return AssistantLook.indigo(scheme)
        case .terra: return AssistantLook.terra(scheme)
        case .sage: return AssistantLook.sage(scheme)
        }
    }

    /// Kolor kierunku: pochwała w szałwii, podpowiedź w terakocie.
    private var accent: Color {
        isPraise ? AssistantLook.sage(scheme) : AssistantLook.terra(scheme)
    }

    private var trimmedComment: String {
        comment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !tags.isEmpty || !trimmedComment.isEmpty
    }

    var body: some View {
        ZStack {
            AssistantSheetScaffold(
                eyebrow: isPraise ? "Dobra odpowiedź" : "Słaba odpowiedź",
                title: isEditing ? "Popraw podpowiedź" : (isPraise ? "Co było dobre?" : "Co nie zagrało?"),
                icon: isPraise ? "hand.thumbsup" : "hand.thumbsdown",
                accent: isPraise ? AssistantLook.sage(scheme) : AssistantLook.terra(scheme),
                onClose: { dismiss() },
                footer: { footer }
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(isEditing
                         ? "Nowa podpowiedź zastąpi poprzednią. Ocena zostaje bez zmian."
                         : (isPraise
                            ? "Dzięki, ocena jest już zapisana. Napisz, co zagrało — zespół Scoffie będzie wiedział, czego pilnować."
                            : "Ocena jest już zapisana. Napisz, co nie zagrało — trafi to do zespołu Scoffie i pomoże poprawić Asystenta."))
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .foregroundStyle(AssistantLook.muted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)

                    quote
                        .padding(.top, 18)

                    EditorialSheetSectionLabel(title: isPraise ? "Co zagrało" : "Co nie zagrało")
                        .padding(.top, 26)
                        .padding(.bottom, 10)
                    reasonList

                    EditorialSheetSectionLabel(title: isPraise ? "Co jeszcze" : "Jak powinno być")
                        .padding(.top, 26)
                        .padding(.bottom, 10)
                    commentField

                    if let errorMessage {
                        SCInlineErrorText(errorMessage)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 4)
            }
            .opacity(isDone ? 0 : 1)

            if isDone {
                thanks
                    .transition(.opacity)
            }
        }
        .background(SCPageBackground(scheme: scheme).ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(40)
        .presentationBackground(Color.scPageBase(scheme))
        .interactiveDismissDisabled(isSending)
        .onAppear(perform: prefill)
    }

    // MARK: - Cytat

    /// Oceniana odpowiedź — trzy linie, znak Asystenta, dopisek o migawce.
    private var quote: some View {
        let shape = RoundedRectangle(cornerRadius: AssistantCardMetrics.listRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SCMarkShape()
                    .fill(AssistantLook.terraFill(scheme))
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                Text("ODPOWIEDŹ ASYSTENTA")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(AssistantLook.faint(scheme))
            }
            Text(message.text.isEmpty ? "Odpowiedź z kartą" : message.text)
                .font(.system(size: 14.5))
                .lineSpacing(2)
                .foregroundStyle(AssistantLook.ink(scheme).opacity(0.8))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                Image(systemName: "lock")
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Wyślemy ją razem z podpowiedzią")
                    .font(.system(size: 12))
            }
            .foregroundStyle(AssistantLook.faint(scheme))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Color.scTileBg(scheme)))
        .overlay(shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
        .overlay(alignment: .leading) {
            // Pionowa kreska cytatu w terakocie.
            Capsule()
                .fill((isPraise ? AssistantLook.sage(scheme) : AssistantLook.terra(scheme)).opacity(0.55))
                .frame(width: 3)
                .padding(.vertical, 16)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Powody

    private var reasonList: some View {
        let shape = RoundedRectangle(cornerRadius: AssistantCardMetrics.listRadius, style: .continuous)
        return VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                if index > 0 {
                    Rectangle()
                        .fill(AssistantLook.hair(scheme))
                        .frame(height: 1)
                        .padding(.leading, 60)
                }
                row(option)
            }
        }
        .background(shape.fill(Color.scTileBg(scheme)))
        .overlay(shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
    }

    private func row(_ option: Option) -> some View {
        let isOn = tags.contains(option.id)
        let reasonColor = color(option.tone)
        return Button {
            if isOn { tags.remove(option.id) } else { tags.insert(option.id) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(reasonColor.opacity(scheme == .dark ? 0.18 : 0.13))
                    Image(systemName: option.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(reasonColor)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 15.5, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(AssistantLook.ink(scheme))
                    Text(option.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(AssistantLook.muted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SCCheckbox(on: isOn, accent: accent, size: 22)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    // MARK: - Komentarz

    private var commentField: some View {
        let shape = RoundedRectangle(cornerRadius: AssistantCardMetrics.listRadius, style: .continuous)
        return VStack(alignment: .trailing, spacing: 8) {
            TextField(
                isPraise
                    ? "Np. świetne szybkie kolacje, tak trzymaj"
                    : "Np. krócej i konkretniej, obiad do 30 minut, bez ryby",
                text: $comment,
                axis: .vertical
            )
            .lineLimit(4...8)
            .font(.system(size: 15.5))
            .focused($commentFocused)
            .onChange(of: comment) { _, value in
                if value.count > Self.commentLimit {
                    comment = String(value.prefix(Self.commentLimit))
                }
            }

            if !comment.isEmpty {
                Text("\(comment.count)/\(Self.commentLimit)")
                    .font(.system(size: 11.5, weight: .medium))
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

    private var footer: some View {
        AssistantActionPair(spacing: 8) {
            AssistantGhostButton(
                action: AssistantCardAction(title: isEditing ? "Anuluj" : "Pomiń") { dismiss() }
            )
            .disabled(isSending)

            AssistantPrimaryButton(
                action: AssistantCardAction(
                    title: isEditing ? "Zapisz" : "Wyślij",
                    icon: "paperplane",
                    action: submit
                ),
                isBusy: isSending,
                tint: isPraise ? AssistantLook.sage(scheme) : nil
            )
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.45)
        }
    }

    // MARK: - Po wysłaniu

    private var thanks: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(AssistantLook.sageTint(scheme))
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AssistantLook.sage(scheme))
            }
            .frame(width: 72, height: 72)
            .accessibilityHidden(true)

            Text("Dzięki!")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(Color.scLabel(scheme))
            Text(isPraise ? "Przekazane zespołowi Scoffie." : "Podpowiedź trafiła do zespołu Scoffie.")
                .font(.system(size: 15))
                .foregroundStyle(AssistantLook.muted(scheme))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Logika

    /// Istniejąca podpowiedź wchodzi do pól RAZ — jak w arkuszu zgłoszenia
    /// (bez własnego `init` z `State(initialValue:)`).
    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        // Tylko podpowiedź TEGO kierunku — po zmianie 👎 → 👍 wiadomość
        // (sprzed stuknięcia) niesie jeszcze notatkę „co nie zagrało”.
        guard message.feedback == rating, let note = message.feedbackNote else { return }
        tags = Set(note.tags)
        comment = note.comment ?? ""
    }

    private func submit() {
        guard canSend, !isSending, !isDone else { return }
        isSending = true
        errorMessage = nil
        commentFocused = false
        // Kolejność z listy, nie ze zbioru — panel liczy powody tak samo.
        // Powód spoza listy (stare „OTHER”) zostaje, jeśli był zaznaczony.
        // Tylko powody tego kierunku, w kolejności z listy — serwer i tak
        // odrzuca obce, a lokalna notatka nie może ich zapamiętać.
        let ordered = options.map(\.id).filter { tags.contains($0) }
        let text = trimmedComment
        Task { @MainActor in
            let failure = await onSubmit(ordered, text.isEmpty ? nil : text)
            isSending = false
            if let failure {
                errorMessage = failure
                return
            }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { isDone = true }
            try? await Task.sleep(for: .milliseconds(1100))
            dismiss()
        }
    }
}
