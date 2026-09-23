import SwiftUI

// MARK: - Wjazd sekcji

/// Sekcja wjeżdża z dołu i rozjaśnia się — kaskadą, w tych samych liczbach
/// co treść arkusza wyboru posiłku u Asystenta (`AssistantOptionsStorySheet`).
/// Wzór: szczegóły posiłku; tak samo wchodzi „Dodaj do planu” (runda 14).
///
/// Użycie: `hasAppeared` przestawiane w `.task` po ~80 ms (klatka oddechu —
/// w `onAppear` padało w klatce wstawienia i nic nie grało), a każda sekcja
/// dostaje swój numer: `.scReveal(hasAppeared, order: n)`.
///
/// `geometryGroup()`: blok podjeżdża jako JEDNA całość. Bez tego elementy
/// z własną animacją w środku (pierścienie makro, liczące cyfry) jechałyby
/// każdy swoim tempem i przez chwilę stały na różnych wysokościach.
struct SCReveal: ViewModifier {
    let isVisible: Bool
    let order: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .geometryGroup()
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 14)
            .animation(
                reduceMotion
                    ? .easeInOut(duration: 0.2)
                    : .smooth(duration: 0.55).delay(0.10 + Double(order) * 0.05),
                value: isVisible
            )
    }
}

extension View {
    /// Sekcje wchodzą po kolei — góra pierwsza.
    func scReveal(_ isVisible: Bool, order: Int) -> some View {
        modifier(SCReveal(isVisible: isVisible, order: order))
    }
}
