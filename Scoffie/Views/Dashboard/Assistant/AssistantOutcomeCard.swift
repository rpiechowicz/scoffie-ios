import SwiftUI

/// Karta wyniku nieudanej tury — 1:1 z makietą „13 · Timeout”: spokojnie,
/// bez alertu i bez czerwieni. Znak marki w szarości, eyebrow, plakietka
/// „Przerwane”; tytuł mówi, co się stało; drugie zdanie — co się NIE
/// stało („Nic nie zmieniłem w planie.”, tylko gdy to prawda); trzecie —
/// „Spróbujmy mniejszy zakres.”; pigułki z mniejszym zakresem;
/// „Spróbuj ponownie” jako poboczna w stopce.
struct AssistantOutcomeCard: View {
    /// Kod porażki tury (`AgentStore.lastTurnErrorCode`); `nil` = błąd
    /// wysyłki, nie tury.
    let code: String?
    /// Zdanie z mappera — zostaje jako druga linia, gdy karta nie ma
    /// własnego nagłówka dla tego kodu.
    let message: String
    /// Czy tura zdążyła coś zapisać.
    let wrote: Bool
    /// Podpowiedzi z serwera (mniejszy zakres).
    var suggestions: [String] = []
    /// Wysyła podpowiedź jako wiadomość.
    let onAsk: (String) -> Void
    /// Ponowienie wysyłki, która nie doszła (ten sam klucz idempotencji).
    var onRetry: (() -> Void)? = nil
    /// Zadanie ostatniego pytania jeszcze raz (nowa tura).
    var onAskAgain: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    private enum Outcome { case timeout, cancelled, limited, failed, delivery }

    private var shape: Outcome {
        switch code ?? "" {
        case "AI_TIMEOUT", "LOCAL_TIMEOUT": return .timeout
        case "AI_CANCELLED", "LOCAL_ABANDONED": return .cancelled
        case "AI_QUOTA_EXCEEDED", "AI_PLAN_QUOTA_EXCEEDED", "AI_BUDGET_PAUSED": return .limited
        case "": return .delivery
        default: return .failed
        }
    }

    private var headline: String {
        switch shape {
        case .timeout: return "To trwało za długo."
        case .cancelled: return "Zatrzymane."
        case .limited: return "Pula wykorzystana."
        case .failed: return "Nie udało się dokończyć."
        case .delivery: return "Wiadomość nie doszła."
        }
    }

    private var eyebrow: String {
        switch shape {
        case .timeout: return "Przekroczony czas"
        case .cancelled: return "Zatrzymano"
        case .limited: return "Limit"
        case .failed: return "Nie dokończono"
        case .delivery: return "Wysyłka"
        }
    }

    private var badge: String {
        shape == .limited ? "Limit" : "Przerwane"
    }

    /// Czy pokazać własne zdanie z mappera pod nagłówkiem.
    private var showsMessage: Bool {
        switch shape {
        case .timeout, .cancelled: return false
        case .limited, .failed, .delivery: return true
        }
    }

    private var offersSmallerScope: Bool {
        shape == .timeout || shape == .cancelled
    }

    /// Podpowiedzi z serwera albo dwie własne — zawsze najwyżej trzy.
    private var scopePrompts: [String] {
        let fromServer = suggestions.filter { !$0.isEmpty }
        if !fromServer.isEmpty { return Array(fromServer.prefix(3)) }
        return ["Zaplanuj tylko obiady", "Zaplanuj 3 dni"]
    }

    private static func prompt(for suggestion: String) -> String {
        switch suggestion {
        case "Zaplanuj tylko obiady": return "Zaplanuj mi tylko obiady na ten tydzień"
        case "Zaplanuj 3 dni": return "Zaplanuj mi tylko trzy najbliższe dni"
        default: return suggestion
        }
    }

    var body: some View {
        AssistantCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    HStack(spacing: 8) {
                        SCMarkShape()
                            .fill(AssistantLook.ink(scheme).opacity(0.35))
                            .frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                        Text(eyebrow)
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.9)
                            .textCase(.uppercase)
                            .foregroundStyle(AssistantLook.faint(scheme))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(badge)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.3)
                        .foregroundStyle(AssistantLook.faint(scheme))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(AssistantLook.quietTint(scheme)))
                }

                Text(headline)
                    .font(.system(size: 21, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(AssistantLook.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                if !wrote {
                    Text("Nic nie zmieniłem w planie.")
                        .font(.system(size: 15.5, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(AssistantLook.ink(scheme))
                        .padding(.top, 6)
                }

                if showsMessage, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 14))
                        .lineSpacing(2)
                        .foregroundStyle(AssistantLook.muted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }

                if offersSmallerScope {
                    Text("Spróbujmy mniejszy zakres.")
                        .font(.system(size: 14))
                        .foregroundStyle(AssistantLook.muted(scheme))
                        .padding(.top, 2)

                    AssistantQuickReplies(items: scopePrompts) { onAsk(Self.prompt(for: $0)) }
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.vertical, 16)
            .accessibilityElement(children: .combine)

            if let onRetry {
                AssistantCardActions(
                    secondary: AssistantCardAction(title: "Spróbuj ponownie", icon: "arrow.clockwise", action: onRetry)
                )
            } else if let onAskAgain, shape != .limited {
                AssistantCardActions(
                    secondary: AssistantCardAction(title: "Spróbuj ponownie", icon: "arrow.clockwise", action: onAskAgain)
                )
            }
        }
    }
}

#if DEBUG
#Preview("Wynik tury") {
    ScrollView {
        VStack(spacing: 16) {
            AssistantOutcomeCard(code: "AI_TIMEOUT", message: "", wrote: false, onAsk: { _ in }, onAskAgain: {})
            AssistantOutcomeCard(code: "AI_CANCELLED", message: "", wrote: false, suggestions: ["Tylko obiady", "3 dni"], onAsk: { _ in }, onAskAgain: {})
            AssistantOutcomeCard(code: "AI_PROVIDER_ERROR", message: "Asystent nie mógł dokończyć zadania. Spróbuj ponownie za chwilę.", wrote: false, onAsk: { _ in }, onAskAgain: {})
            AssistantOutcomeCard(code: nil, message: "Nie udało się wysłać wiadomości.", wrote: false, onAsk: { _ in }, onRetry: {})
        }
        .padding(20)
    }
    .background(SCPageBackground(scheme: .light).ignoresSafeArea())
}
#endif
