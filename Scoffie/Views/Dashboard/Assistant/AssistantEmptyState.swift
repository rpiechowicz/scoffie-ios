import SwiftUI

/// Pusta rozmowa z asystentem: JEDNA karta briefingu pod nagłówkiem
/// zakładki — jak na makiecie, bez osobnego powitania i bez ikony nad kartą.
///
/// Ten sam szkielet dla każdej sytuacji (pusty tydzień, brakująca kolacja,
/// bilans, wyczerpana pula) — zmienia się treść i ilustracja karty, nie
/// układ. Zmiana briefingu (plan się zapisał, minęła godzina kolacji)
/// przenika w miejscu z lekkim uniesieniem; przy Reduce Motion samym kryciem.
struct AssistantEmptyState: View {
    let briefing: AssistantBriefing
    let onAction: (AssistantBriefing.Action) -> Void

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
        ZStack {
            AssistantBriefingCard(briefing: briefing, onAction: onAction)
                .id(briefing.kind)
                .transition(transition)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.3), value: briefing.kind)
        .frame(maxWidth: .infinity)
    }
}
