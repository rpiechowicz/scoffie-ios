import SwiftUI

/// Pasek pod odpowiedzią asystenta (27.09.2026 — Rafał: „pod każdą odpowiedzią
/// możliwość polubienia, zgłoszenia itd., tak jak inne chaty AI”).
///
/// Po lewej „✦ Myślałem 42 s” — sam podpis, z serwera także w historii.
/// Rozwijana karta z krokami i kontekstem odpadła tego samego dnia („do
/// usunięcia”), kopiowanie też („co nam to daje realnego?” — tekst i tak da
/// się zaznaczyć, a „Kopiuj” zostaje pod przytrzymaniem dymka). Po prawej:
/// kciuk w górę, kciuk w dół i „⋯” (udostępnij, zgłoś / popraw zgłoszenie —
/// serwer trzyma JEDNO zgłoszenie na osobę i odpowiedź). Kciuk w dół otwiera
/// pod paskiem jedno zdanie z drogą do zgłoszenia z powodem.
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

    @Environment(\.colorScheme) private var scheme

    /// Kolumna tekstu odpowiedzi — patrz `AssistantVoice`.
    static let textInset: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                if let thinking {
                    thinkingLabel(thinking)
                }
                Spacer(minLength: 8)
                actions
            }

            if feedback == .down {
                improveRow
                    .transition(.opacity)
            }
        }
        .padding(.leading, Self.textInset)
        .animation(.smooth(duration: 0.25), value: feedback)
    }

    // MARK: - Myślałem

    private func thinkingLabel(_ thinking: AgentThinkingSummary) -> some View {
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
        }
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
            .frame(width: 36, height: 30)
            .contentShape(Rectangle())
            .scTapHeight(drawn: 30)
    }

    // MARK: - Po kciuku w dół

    private var improveRow: some View {
        HStack(spacing: 6) {
            Text(isReported ? "Zgłoszone — dzięki." : "Dzięki za ocenę. Co było nie tak?")
                .font(.system(size: 13))
                .foregroundStyle(AssistantLook.muted(scheme))
            Button(action: onReport) {
                Text(isReported ? "Popraw" : "Opisz")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AssistantLook.terra(scheme))
                    .scTapHeight(drawn: 20)
            }
            .buttonStyle(.plain)
            .accessibilityHint(isReported ? "Otwiera Twoje zgłoszenie do poprawienia" : "Otwiera zgłoszenie odpowiedzi z powodem")
        }
    }
}
