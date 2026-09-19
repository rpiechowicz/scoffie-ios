import SwiftUI

/// Pusta rozmowa z asystentem: powitanie, JEDNA karta briefingu i najwyżej
/// dwie podpowiedzi pod nią.
///
/// Ten sam szkielet dla każdej sytuacji (pusty tydzień, brakująca kolacja,
/// bilans, wyczerpana pula) — zmienia się treść i ilustracja karty, nie
/// układ. Zmiana briefingu (plan się zapisał, minęła godzina kolacji)
/// przenika w miejscu z lekkim uniesieniem; przy Reduce Motion samym kryciem.
struct AssistantEmptyState: View {
    let briefing: AssistantBriefing
    let onAction: (AssistantBriefing.Action) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var transition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 8)),
                removal: .opacity
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AssistantMarkBadge(size: 44)
                Text(briefing.greeting)
                    .font(.system(size: 19, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            ZStack {
                AssistantBriefingCard(briefing: briefing, onAction: onAction)
                    .id(briefing.kind)
                    .transition(transition)
            }
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.3), value: briefing.kind)

            if !briefing.secondary.isEmpty {
                AssistantBriefingSecondaryActions(actions: briefing.secondary, onAction: onAction)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
