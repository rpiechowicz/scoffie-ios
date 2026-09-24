import SwiftUI

/// Wejście na zakładkę: treść delikatnie wyłania się z tła — krycie 0 → 1
/// i 8 pt z dołu, 0,28 s. Jeden mechanizm dla wszystkich zakładek poza
/// Asystentem, który przy każdym wejściu rysuje własne powitanie.
///
/// Gra przy ZMIANIE na aktywną, nie przy pierwszym renderze: zakładki budują
/// się pod loaderem startowym i wtedy nie ma czego pokazywać. Sam widok nie
/// jest wstawiany od nowa (zakładki żyją naraz w `NavigationMenu`), więc
/// przewinięcie i stan ekranu zostają. Wartość prowadzi `keyframeAnimator`
/// z licznikiem wejść — tor startuje od `MoveKeyframe(0)`, więc każde wejście
/// gra od zera, także gdy poprzednie jeszcze trwało.
private struct SCTabEntrance: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entrances = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 1.0, trigger: entrances) { view, progress in
                view
                    .opacity(progress)
                    .offset(y: (1 - progress) * 8)
            } keyframes: { _ in
                KeyframeTrack {
                    MoveKeyframe(0.0)
                    LinearKeyframe(1.0, duration: 0.28, timingCurve: .easeOut)
                }
            }
            .onChange(of: isActive) { _, active in
                if active, !reduceMotion { entrances += 1 }
            }
    }
}

extension View {
    /// Delikatne wejście treści przy przełączeniu na tę zakładkę.
    func scTabEntrance(isActive: Bool) -> some View {
        modifier(SCTabEntrance(isActive: isActive))
    }
}
