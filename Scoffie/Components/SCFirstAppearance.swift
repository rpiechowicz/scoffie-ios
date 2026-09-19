import SwiftUI

/// Pierwsze wejście na ekran zakładki — RAZ na uruchomienie aplikacji.
///
/// Treść zakładki buduje się leniwie przy pierwszym wyborze i przez jedną
/// klatkę potrafi „skoczyć” (szkielet → dane, wcięcia bezpiecznego obszaru,
/// pasek u dołu). Zamiast pokazywać ten skok, ekran wyłania się delikatnie:
/// z 0 do pełnej widoczności i o 10 pt w górę, 0,5 s. Stan siedzi
/// w modyfikatorze, a `TabView` trzyma zakładkę przy życiu, więc kolejne
/// przełączenia są CIĘCIEM jak w systemie (patrz `NavigationMenu`).
/// Reduce Motion: bez ruchu, sam fade.
struct SCFirstAppearance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 10)
            .onAppear {
                guard !appeared else { return }
                // Klatka później: pierwszy układ (szkielet, safe area) ma się
                // policzyć w ukryciu, a nie w połowie animacji.
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.5)) {
                        appeared = true
                    }
                }
            }
    }
}

extension View {
    /// Delikatne wyłonienie ekranu przy pierwszym pokazaniu (raz na sesję widoku).
    func scFirstAppearance() -> some View {
        modifier(SCFirstAppearance())
    }
}
