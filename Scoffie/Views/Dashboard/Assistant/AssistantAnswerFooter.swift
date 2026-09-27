import SwiftUI

/// Pasek pod odpowiedzią asystenta (27.09.2026 — Rafał: „pod każdą odpowiedzią
/// możliwość polubienia, zgłoszenia itd., tak jak inne chaty AI”).
///
/// Po lewej „✦ Myślałem 42 s ›” — z serwera także w historii; stuknięcie
/// otwiera półarkusz z przebiegiem tury krok po kroku
/// (`AssistantThinkingSheet`, 27.09.2026 wieczorem — „historia, jak asystent
/// myślał”). Rozwijana karta z krokami W ROZMOWIE odpadła wcześniej tego
/// dnia („do usunięcia”) i nie wraca — kroki mieszkają w arkuszu. Kopiowanie
/// też odpadło („co nam to daje realnego?” — tekst i tak da
/// się zaznaczyć, a „Kopiuj” zostaje pod przytrzymaniem dymka). Po prawej:
/// kciuk w górę, kciuk w dół i „⋯” (udostępnij, zgłoś / popraw zgłoszenie —
/// serwer trzyma JEDNO zgłoszenie na osobę i odpowiedź). Kciuk w dół otwiera
/// pod paskiem „Co poprawić? Podpowiedz” — PODPOWIEDŹ (powody + zdanie,
/// `AssistantSuggestionSheet`), a nie zgłoszenie: zgłoszenie to błąd,
/// zagrożenie albo obraza i żyje w „⋯”, więc podpowiedź działa także przy
/// odpowiedzi już zgłoszonej (27.09.2026). Po wysłaniu wiersz znika — bez
/// „Zgłoszone — dzięki” („bez sensu”); poprawić ją można z „⋯”.
///
/// Runda 2 (27.09.2026): „Co poprawić?” to PIGUŁKA obok kciuków (soft
/// terakota z żarówką), a nie zdanie z odnośnikiem — gdy się nie mieści,
/// schodzi pod kciuki, do prawej. Prawa krawędź ma to samo wcięcie co lewa:
/// „Myślałem” stoi 28 pt od brzegu (kolumna tekstu), więc glif „⋯” też
/// kończy się 28 pt od brzegu (`trailingInset` liczy zapas ramki ikony).
///
/// Wcięty do kolumny tekstu (znak marki 18 pt + 10 pt). Wchodzi dopiero, gdy
/// odpowiedź się dopisze (`MessageBubble`).
struct AssistantAnswerFooter: View {
    let text: String
    let thinking: AgentThinkingSummary?
    let feedback: AgentFeedback?
    /// Użytkownik już zgłosił tę odpowiedź — „Zgłoś” staje się „Popraw”.
    let isReported: Bool
    let onRate: (AgentFeedback?) -> Void
    let onReport: () -> Void
    /// Otwiera przebieg tury; `nil` = sam podpis.
    var onShowThinking: (() -> Void)? = nil
    /// Kciuk w dół ma już podpowiedź — wiersz „Co poprawić?” znika.
    var hasSuggestion: Bool = false
    /// „Podpowiedz” / „Popraw podpowiedź”; `nil` = bez podpowiedzi.
    var onSuggest: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    /// Kolumna tekstu odpowiedzi — patrz `AssistantVoice`.
    static let textInset: CGFloat = 28
    /// Ramka ikony akcji i glif w niej — z nich zapas po prawej.
    private static let iconFrame: CGFloat = 34
    private static let glyphWidth: CGFloat = 16
    /// Glif ostatniej akcji kończy się `textInset` od brzegu — symetrycznie
    /// do „Myślałem” po lewej.
    private static var trailingInset: CGFloat {
        textInset - (iconFrame - glyphWidth) / 2
    }

    private var showsSuggest: Bool {
        feedback == .down && !hasSuggestion && onSuggest != nil
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) {
                leading
                Spacer(minLength: 8)
                if showsSuggest {
                    suggestPill
                        .padding(.trailing, 6)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
                actions
            }

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 2) {
                    leading
                    Spacer(minLength: 8)
                    actions
                }
                if showsSuggest {
                    suggestPill
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
        }
        .padding(.leading, Self.textInset)
        .padding(.trailing, Self.trailingInset)
        .animation(.smooth(duration: 0.25), value: showsSuggest)
    }

    @ViewBuilder
    private var leading: some View {
        if let thinking {
            thinkingLabel(thinking)
        }
    }

    // MARK: - Myślałem

    @ViewBuilder
    private func thinkingLabel(_ thinking: AgentThinkingSummary) -> some View {
        if let onShowThinking {
            Button(action: onShowThinking) {
                thinkingText(thinking, opens: true)
                    .scTapHeight(drawn: 30)
            }
            .buttonStyle(PlanPressStyle(scale: 0.96))
            .accessibilityHint("Pokazuje krok po kroku, jak powstała odpowiedź")
        } else {
            thinkingText(thinking, opens: false)
        }
    }

    private func thinkingText(_ thinking: AgentThinkingSummary, opens: Bool) -> some View {
        let label = thinking.duration.map { "Myślałem \(AssistantThoughtLine.clock($0))" } ?? "Myślałem chwilę"
        return HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AssistantLook.terra(scheme).opacity(0.8))
                .accessibilityHidden(true)
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(AssistantLook.faint(scheme))
                .lineLimit(1)
            if opens {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AssistantLook.faint(scheme).opacity(0.8))
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Akcje

    private var actions: some View {
        HStack(spacing: 0) {
            iconButton(
                feedback == .up ? "hand.thumbsup.fill" : "hand.thumbsup",
                active: feedback == .up,
                label: "Dobra odpowiedź",
                bounce: feedback == .up
            ) {
                onRate(feedback == .up ? nil : .up)
            }
            .accessibilityAddTraits(feedback == .up ? .isSelected : [])

            iconButton(
                feedback == .down ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                active: feedback == .down,
                label: "Słaba odpowiedź",
                bounce: feedback == .down
            ) {
                onRate(feedback == .down ? nil : .down)
            }
            .accessibilityAddTraits(feedback == .down ? .isSelected : [])

            Menu {
                if !text.isEmpty {
                    ShareLink(item: text) {
                        Label("Udostępnij", systemImage: "square.and.arrow.up")
                    }
                }
                if feedback == .down, hasSuggestion, let onSuggest {
                    Button(action: onSuggest) {
                        Label("Popraw podpowiedź", systemImage: "lightbulb")
                    }
                }
                // Obiecane w FAQ i w regulaminie („Zgłoś odpowiedź”) — idzie na
                // `POST /agent/messages/:id/report`, nie zmienia rozmowy.
                Button(role: isReported ? nil : .destructive, action: onReport) {
                    Label(
                        isReported ? "Popraw zgłoszenie" : "Zgłoś odpowiedź",
                        systemImage: isReported ? "flag.fill" : "flag"
                    )
                }
            } label: {
                iconLabel("ellipsis", active: false)
            }
            .accessibilityLabel("Więcej")
        }
    }

    private func iconButton(
        _ symbol: String,
        active: Bool,
        label: String,
        bounce: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            iconLabel(symbol, active: active)
                .symbolEffect(.bounce, value: bounce)
        }
        .buttonStyle(PlanPressStyle(scale: 0.9))
        .accessibilityLabel(label)
    }

    private func iconLabel(_ symbol: String, active: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14.5, weight: .medium))
            .foregroundStyle(active ? AssistantLook.ink(scheme) : AssistantLook.faint(scheme))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: Self.iconFrame, height: 30)
            .contentShape(Rectangle())
            .scTapHeight(drawn: 30)
    }

    // MARK: - Po kciuku w dół

    /// „💡 Co poprawić?” — otwiera podpowiedź (`AssistantSuggestionSheet`).
    private var suggestPill: some View {
        Button {
            onSuggest?()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 11, weight: .bold))
                Text("Co poprawić?")
                    .font(.system(size: 12.5, weight: .semibold))
                    .tracking(-0.1)
                    .lineLimit(1)
            }
            .foregroundStyle(AssistantLook.terra(scheme))
            .padding(.horizontal, 11)
            .frame(height: 28)
            .scSoftCapsule(AssistantLook.terra(scheme))
            .fixedSize()
            .scTapHeight(drawn: 28)
        }
        .buttonStyle(PlanPressStyle(scale: 0.95))
        .accessibilityHint("Otwiera podpowiedź: co było nie tak i jak powinno być")
    }
}
