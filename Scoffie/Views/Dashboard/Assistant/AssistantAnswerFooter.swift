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
/// półarkusz „Co nie zagrało?” — PODPOWIEDŹ (powody + zdanie,
/// `AssistantSuggestionSheet`), a nie zgłoszenie: zgłoszenie to błąd,
/// zagrożenie albo obraza i żyje w „⋯”, więc podpowiedź działa także przy
/// odpowiedzi już zgłoszonej (27.09.2026). Bez „Zgłoszone — dzięki” („bez
/// sensu”).
///
/// Runda 3 (27.09.2026, „przeskakuje, jak zmieniam like”): kciuk w dół SAM
/// otwiera arkusz podpowiedzi — pigułka „Co poprawić?”, która wjeżdżała
/// w pasek i przestawiała go (`ViewThatFits`), odpadła. Pasek ma zawsze ten
/// sam układ; poprawić podpowiedź można z „⋯”.
///
/// 6.10.2026 („jak od Apple” — ocena bez formularza): kciuk w górę to SAM
/// stan kciuka (szałwia), haptyka i „wybuch” kropek — ocena zapisuje się od
/// razu i żaden arkusz się nie otwiera (dawne „Co było dobre?” po 0,55 s
/// odpadło). Prawa krawędź ma to samo wcięcie co lewa:
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
    /// Kciuk w dół ma już podpowiedź — w „⋯” stoi „Popraw podpowiedź”.
    var hasSuggestion: Bool = false
    /// Półarkusz „Co nie zagrało?” — po kciuku w dół i z „⋯”; `nil` = bez
    /// podpowiedzi.
    var onSuggest: (() -> Void)? = nil
    /// Kciuki i „⋯” — tylko pod odpowiedzią modelu; potwierdzenie zapisu
    /// ma sam podpis (albo nic).
    var showsActions: Bool = true

    @Environment(\.colorScheme) private var scheme
    /// Podbicie = kciuk w górę właśnie wstawiony — gra „wybuch” kropek.
    @State private var cheer = 0

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

    var body: some View {
        HStack(spacing: 2) {
            leading
            Spacer(minLength: 8)
            if showsActions {
                actions
            }
        }
        .padding(.leading, Self.textInset)
        .padding(.trailing, Self.trailingInset)
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
                .font(.sc(size: 10.5, weight: .semibold))
                .foregroundStyle(AssistantLook.terra(scheme).opacity(0.8))
                .accessibilityHidden(true)
            Text(label)
                .font(.sc(size: 12.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(AssistantLook.faint(scheme))
                .lineLimit(1)
            if opens {
                Image(systemName: "chevron.right")
                    .font(.sc(size: 9, weight: .bold))
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
                tint: AssistantLook.sage(scheme),
                label: "Dobra odpowiedź",
                bounce: feedback == .up
            ) {
                // W górę = sama ocena: kciuk, kropki i haptyka, bez arkusza.
                // Drugie stuknięcie zdejmuje ocenę.
                if feedback == .up {
                    onRate(nil)
                } else {
                    cheer += 1
                    onRate(.up)
                }
            }
            .overlay { ThumbCheer(trigger: cheer, tint: AssistantLook.sage(scheme)) }
            .sensoryFeedback(.success, trigger: cheer)
            .accessibilityAddTraits(feedback == .up ? .isSelected : [])

            iconButton(
                feedback == .down ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                active: feedback == .down,
                tint: AssistantLook.terra(scheme),
                label: "Słaba odpowiedź",
                bounce: feedback == .down
            ) {
                // W dół = ocena od razu + półarkusz „Co nie zagrało?”
                // (podpowiedź nieobowiązkowa — krzyżyk zostawia sam kciuk).
                // Drugie stuknięcie zdejmuje ocenę, jak przy kciuku w górę.
                if feedback == .down {
                    onRate(nil)
                } else {
                    onRate(.down)
                    onSuggest?()
                }
            }
            .accessibilityAddTraits(feedback == .down ? .isSelected : [])

            Menu {
                if !text.isEmpty {
                    ShareLink(item: text) {
                        Label("Udostępnij", systemImage: "square.and.arrow.up")
                    }
                }
                // Podpowiedź tylko do kciuka w dół — ten sam półarkusz,
                // przy istniejącej podpowiedzi z wypełnionymi polami.
                if feedback == .down, let onSuggest {
                    Button(action: onSuggest) {
                        Label(
                            hasSuggestion ? "Popraw podpowiedź" : "Co nie zagrało?",
                            systemImage: "lightbulb"
                        )
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
        tint: Color? = nil,
        label: String,
        bounce: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            iconLabel(symbol, active: active, tint: tint)
                .symbolEffect(.bounce.up.byLayer, value: bounce)
        }
        .buttonStyle(PlanPressStyle(scale: 0.9))
        .accessibilityLabel(label)
    }

    /// Zaznaczony kciuk w kolorze systemu (27.09.2026: „zmień kolor like na
    /// nasz systemowy”) — w górę szałwia (jak „zapisane”), w dół terakota.
    private func iconLabel(_ symbol: String, active: Bool, tint: Color? = nil) -> some View {
        Image(systemName: symbol)
            .font(.sc(size: 14.5, weight: .medium))
            .foregroundStyle(active ? (tint ?? AssistantLook.ink(scheme)) : AssistantLook.faint(scheme))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: Self.iconFrame, height: 30)
            .contentShape(Rectangle())
            .scTapHeight(drawn: 30)
    }
}

/// „Wybuch” pod kciukiem w górę: sześć kropek w szałwii rozlatuje się
/// z krążka i gaśnie (0,5 s), razem z podskokiem glifu i haptyką sukcesu.
/// Trwałe widoki z `keyframeAnimator` na liczniku (wzór `BurstHeart`
/// w ulubionych), nie wstawiane z `Task.sleep`. Przy Reduce Motion nie gra.
struct ThumbCheer: View {
    let trigger: Int
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Burst {
        var spread: CGFloat = 0
        var opacity: Double = 0
        var scale: CGFloat = 0.4
    }

    var body: some View {
        if !reduceMotion {
            ZStack {
                ForEach(0..<6, id: \.self) { index in
                    dot(index)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func dot(_ index: Int) -> some View {
        let angle = Double(index) * .pi / 3 - .pi / 2
        let size: CGFloat = index.isMultiple(of: 2) ? 4 : 3
        return Circle()
            .fill(tint)
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: Burst(), trigger: trigger) { content, burst in
                content
                    .scaleEffect(burst.scale)
                    .offset(
                        x: CGFloat(cos(angle)) * burst.spread,
                        y: CGFloat(sin(angle)) * burst.spread
                    )
                    .opacity(burst.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.spread) {
                    MoveKeyframe(0)
                    CubicKeyframe(15, duration: 0.42)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0)
                    LinearKeyframe(1, duration: 0.06)
                    LinearKeyframe(1, duration: 0.18)
                    LinearKeyframe(0, duration: 0.26)
                }
                KeyframeTrack(\.scale) {
                    MoveKeyframe(0.4)
                    SpringKeyframe(1, duration: 0.3, spring: .snappy)
                }
            }
    }
}
