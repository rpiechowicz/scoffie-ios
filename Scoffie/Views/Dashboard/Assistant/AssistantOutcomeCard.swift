import SwiftUI

/// Karta wyniku nieudanej tury — czas, „Stop”, odmowa, limit.
///
/// Bez czerwonego alertu: przekroczony czas to najczęstsza porażka
/// i najczęściej znaczy „za duży zakres”, a nie awarię. Karta mówi trzy
/// rzeczy w tej kolejności: co się stało, czy plan został nietknięty
/// (tylko gdy to prawda) i co zrobić mniejszego. Podpowiedzi zakresu
/// przychodzą z serwera (`suggestions`); bez nich są dwie własne.
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
        AssistantCard(tone: .muted) {
            AssistantCardHead(
                eyebrow: eyebrow,
                eyebrowColor: Color.scMuted(scheme),
                title: headline,
                subtitle: showsMessage ? message : nil
            )

            VStack(alignment: .leading, spacing: 6) {
                if !wrote {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SCPalette.sage)
                        Text("Nic nie zmieniłem w planie.")
                            .font(.system(size: 14, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(Color.scLabel(scheme))
                    }
                }
                if offersSmallerScope {
                    Text("Spróbujmy mniejszy zakres.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color.scMuted(scheme))
                }
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.bottom, offersSmallerScope ? 10 : AssistantCardMetrics.section)
            .accessibilityElement(children: .combine)

            if offersSmallerScope {
                AssistantQuickReplies(items: scopePrompts) { onAsk(Self.prompt(for: $0)) }
                    .padding(.horizontal, AssistantCardMetrics.inset)
                    .padding(.bottom, AssistantCardMetrics.section)
            }

            if let onRetry {
                AssistantCardActions(
                    primary: AssistantCardAction(title: "Spróbuj ponownie", icon: "arrow.clockwise", action: onRetry)
                )
            } else if let onAskAgain, shape != .limited {
                AssistantCardActions(
                    primary: AssistantCardAction(title: "Spróbuj ponownie", icon: "arrow.clockwise", action: onAskAgain),
                    style: .navigation
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
