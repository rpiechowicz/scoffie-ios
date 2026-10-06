import SwiftUI

/// Karta wyniku nieudanej tury — spokojnie, bez alertu i bez czerwieni.
///
/// Od 27.09.2026 (Rafał: „dopracuj design i żeby nie przeskakiwało”) w stroju
/// nagłówków arkuszy: kafelek z ikoną sytuacji · cichy eyebrow · tytuł
/// w pierwszej osobie, bez kropki. Pod spodem JEDNO zdanie — dawniej tytuł
/// „Nie udało się dokończyć.”, pogrubione „Nic nie zmieniłem w planie.”
/// i zdanie z mappera „…nie mógł dokończyć zadania” mówiły trzy razy to samo,
/// a eyebrow i plakietka „Przerwane” — dwa razy. „Nic nie zmieniłem w planie”
/// jest teraz etykietą w szałwii („Plan bez zmian”, tylko gdy to prawda),
/// a „Spróbuj ponownie” — główną akcją w wariancie „soft”, bez kreski nad nią.
/// Przy przekroczonym czasie i „Stop” — pigułki z mniejszym zakresem.
///
/// Wejście (łagodne, z opóźnieniem po zwinięciu wiersza „myślę”) ustawia
/// slot tury w `AssistantView`, nie karta.
struct AssistantOutcomeCard: View {
    /// Kod porażki tury (`AgentStore.lastTurnErrorCode`); `nil` = błąd
    /// wysyłki, nie tury.
    let code: String?
    /// Zdanie z mappera — opis pod tytułem, gdy karta nie ma własnego.
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

    private var icon: String {
        switch shape {
        case .timeout: return "hourglass"
        case .cancelled: return "pause.fill"
        case .limited: return "gauge.with.dots.needle.33percent"
        case .failed: return "exclamationmark.bubble"
        case .delivery: return "wifi.exclamationmark"
        }
    }

    private var eyebrow: String {
        switch shape {
        case .timeout: return "Przekroczony czas"
        case .cancelled: return "Zatrzymano"
        case .limited: return "Limit"
        case .failed: return "Przerwane"
        case .delivery: return "Wysyłka"
        }
    }

    private var headline: String {
        switch shape {
        case .timeout: return "To trwało za długo"
        case .cancelled: return "Zatrzymałem się"
        case .limited: return "Pula wykorzystana"
        case .failed: return "Nie dokończyłem odpowiedzi"
        case .delivery: return "Wiadomość nie doszła"
        }
    }

    /// Porażka po stronie serwera bez konkretu dla użytkownika — zdanie
    /// z mappera powtarzałoby tytuł („nie mógł dokończyć zadania”).
    private static let genericFailures: Set<String> = ["AI_PROVIDER_ERROR", "INTERNAL_ERROR"]

    /// JEDNO zdanie pod tytułem.
    private var detail: String? {
        switch shape {
        case .timeout, .cancelled:
            return "Spróbujmy mniejszego zakresu."
        case .failed where Self.genericFailures.contains(code ?? ""):
            return "Coś zacięło się po mojej stronie. Spróbuj jeszcze raz za chwilę."
        case .failed, .limited, .delivery:
            return message.isEmpty ? nil : message
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

    /// „Spróbuj ponownie” — wysyłka, która nie doszła, albo nowa tura.
    private var retryAction: AssistantCardAction? {
        if let onRetry {
            return AssistantCardAction(title: "Spróbuj ponownie", icon: "arrow.clockwise", action: onRetry)
        }
        if let onAskAgain, shape != .limited {
            return AssistantCardAction(title: "Spróbuj ponownie", icon: "arrow.clockwise", action: onAskAgain)
        }
        return nil
    }

    var body: some View {
        let action = retryAction
        AssistantCard {
            VStack(alignment: .leading, spacing: 0) {
                header

                if let detail {
                    Text(detail)
                        .font(.sc(size: 15))
                        .lineSpacing(3)
                        .foregroundStyle(AssistantLook.muted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }

                if !wrote {
                    SCTag(title: "Plan bez zmian", icon: "checkmark.shield.fill", accent: SCPalette.sage)
                        .padding(.top, 12)
                        .accessibilityLabel("Nic nie zmieniłem w planie")
                }

                if offersSmallerScope {
                    AssistantQuickReplies(items: scopePrompts) { onAsk(Self.prompt(for: $0)) }
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .accessibilityElement(children: .combine)

            if let action {
                // Główna, nie poboczna: na karcie porażki to jest TA akcja.
                // Wprost w treści, bez stopki `AssistantCardActions` — jej
                // pas tła ma sens tylko z kreską nad nim, a kreska dzieliła
                // tę małą kartę na dwie.
                AssistantPrimaryButton(action: action, size: .compact)
                    .padding(.horizontal, AssistantCardMetrics.inset)
                    .padding(.bottom, AssistantCardMetrics.inset)
            }
        }
    }

    /// Kafelek z ikoną sytuacji, eyebrow i tytuł — jak nagłówek arkusza.
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AssistantLook.quietTint(scheme))
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: icon)
                        .font(.sc(size: 16, weight: .semibold))
                        .foregroundStyle(AssistantLook.muted(scheme))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow.uppercased())
                    .font(.sc(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(AssistantLook.faint(scheme))
                    .lineLimit(1)
                Text(headline)
                    .font(.sc(size: 17, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(AssistantLook.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
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
