import SwiftUI

// MARK: - Stopka arkusza

/// Stopka z przyciskami na dole arkusza — JEDNA w całej aplikacji.
///
/// Wzór to dolny pasek szczegółów posiłku: pod przyciskami kryjąca płyta
/// w kolorze tła arkusza, a nad nią 36 pt miękkiego przejścia, w którym
/// przewijana treść ginie. Bez twardej kreski nad przyciskiem i bez szkła:
/// szkło przepuszczało przewijane wiersze pod liczbami i przyciskiem
/// (filtry przepisów), a kreska z półprzezroczystym tłem rysowała granicę
/// w innym miejscu na każdym arkuszu.
///
/// Dawniej ten sam pomysł żył w kilku kopiach: `AssistantStickyFooter`
/// (szczegóły posiłku, wprowadzenie asystenta), `AssistantSheetFooter`
/// (arkusze asystenta), szklana kapsuła filtrów przepisów i własne stopki
/// „Dodaj do planu”, „Wybierz posiłek”, „Na dziś” z kreską nad przyciskiem.
/// Każda miała inne odstępy i inny gradient. Teraz wszystkie idą przez ten
/// widok. Kreator (`WelcomeFooter`) zostaje przy swoim układzie, bo niesie
/// kropki kroków i stoi na kanwie, ale działa na tej samej zasadzie.
///
/// Dwa sposoby użycia:
/// - `.scSheetFooter { … }` na przewijanej treści — przez `safeAreaInset`,
///   więc treść kończy się nad stopką sama, bez ręcznych „zapasów” na dole;
/// - `SCSheetFooter { … }` jako ostatnie dziecko `VStack` pod listą.
struct SCSheetFooter<Content: View>: View {
    /// Kolor tła arkusza pod stopką. Musi być DOKŁADNIE ten sam, co dół tła
    /// arkusza — inaczej nad przyciskiem wraca twarda linia. Domyślnie
    /// `scPageBase`, czyli dół `SCPageBackground`.
    var base: Color? = nil
    var horizontalPadding: CGFloat = SCPageMetrics.horizontal
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 10) { content() }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background { SCFooterScrim(base: base) }
    }
}

/// Tło stopki: kryjąca płyta przez strefę wskaźnika home i przejście NAD
/// stopką (ujemny offset), więc przejście nie zjada miejsca na przyciski,
/// a treść i tak w nim łagodnie ginie.
struct SCFooterScrim: View {
    var base: Color? = nil
    /// Wysokość przejścia nad stopką.
    var fade: CGFloat = 36

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let base = base ?? Color.scPageBase(scheme)
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: base.opacity(0), location: 0),
                    .init(color: base.opacity(0.7), location: 0.55),
                    .init(color: base, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fade)
            .offset(y: -fade)
            .padding(.bottom, -fade)

            base
        }
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Przypina stopkę do dołu przewijanej treści arkusza (`safeAreaInset`):
    /// treść kończy się nad nią, a przewijane wiersze giną w przejściu.
    ///
    /// Przyciski w środku biorą się z komponentów aplikacji: pełna szerokość
    /// to `EditorialPrimaryActionButton`, obok liczb — `RecipeFilterFooterButton`.
    func scSheetFooter<Footer: View>(
        base: Color? = nil,
        horizontalPadding: CGFloat = SCPageMetrics.horizontal,
        @ViewBuilder _ footer: @escaping () -> Footer
    ) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            SCSheetFooter(base: base, horizontalPadding: horizontalPadding, content: footer)
        }
    }
}
