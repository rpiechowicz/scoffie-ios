import SwiftUI

/// Miękki „cień w dół” pod przypiętym nagłówkiem arkusza — JEDEN w całej
/// aplikacji, zamiast kreski oddzielającej nagłówek od przewijanej treści.
///
/// Wzór to szczegóły posiłku: gdy treść wjeżdża pod pływające przyciski,
/// jej górny brzeg łagodnie gaśnie. Tutaj robi to maska na samej treści,
/// a nie gradient w kolorze tła — arkusze stoją na `SCPageBackground`
/// z terakotową poświatą u góry i gradient w jednolitym kolorze rysowałby
/// na niej pas. Maska przepuszcza dokładnie to tło, które jest pod spodem.
///
/// Kreska (`Rectangle` w `scRule`) stała dotąd pod nagłówkiem na stałe,
/// także gdy nic pod nim nie przejeżdżało, i ucinała treść w pół wiersza.
/// Przejście pokazuje się dopiero, gdy treść naprawdę wjedzie pod nagłówek.
///
/// Użycie: modyfikator na `ScrollView` stojącym POD nagłówkiem —
/// `.scScrollEdgeFade()`. Nagłówek nie przewija się razem z treścią: stoi
/// nad nią w `VStack`. Zwijany nagłówek („Filtry” miały taki — tytuł
/// przeskakiwał na środek) zniknął 23.09.2026 na prośbę Rafała.
struct SCScrollEdgeFade: ViewModifier {
    /// Wysokość przejścia.
    var height: CGFloat = 24

    @State private var isScrolled = false

    func body(content: Content) -> some View {
        content
            // Bool, nie przesunięcie: stan zmienia się raz przy przekroczeniu
            // progu, a nie w każdej klatce przewijania.
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 1
            } action: { _, isPast in
                withAnimation(.easeInOut(duration: 0.2)) { isScrolled = isPast }
            }
            .mask {
                VStack(spacing: 0) {
                    // Warstwa „czarna” nad gradientem gaśnie, gdy przejście
                    // ma być widoczne — krycie animuje się pewnie, kolory
                    // w gradiencie niekoniecznie.
                    ZStack {
                        LinearGradient(
                            colors: [.black.opacity(0), .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        Color.black.opacity(isScrolled ? 0 : 1)
                    }
                    .frame(height: height)

                    Color.black
                }
                // Maska układa się jak tło: w bezpiecznym obszarze. Przewijana
                // treść schodzi pod pasek domowy, więc bez tego urywałaby się
                // 34 pt nad krawędzią ekranu, zamiast przejeżdżać pod paskiem.
                .ignoresSafeArea(edges: .bottom)
            }
    }
}

extension View {
    /// Na `ScrollView` pod przypiętym nagłówkiem: górny brzeg treści gaśnie,
    /// gdy wjeżdża pod nagłówek — zamiast kreski. Patrz `SCScrollEdgeFade`.
    func scScrollEdgeFade(height: CGFloat = 24) -> some View {
        modifier(SCScrollEdgeFade(height: height))
    }
}
