import SwiftUI

// MARK: - Stopka arkusza

/// Stopka z przyciskami na dole arkusza — JEDNA w całej aplikacji.
///
/// Wzór to dolny pasek szczegółów posiłku: pod szklanymi przyciskami rozmyty
/// pas (`SCFooterScrim`), w którym przewijana treść chowa się i gaśnie
/// (od 4.10.2026 — wcześniej kryjąca płyta z cieniem krawędzi). Bez twardej
/// kreski nad przyciskiem: kreska z półprzezroczystym tłem rysowała granicę
/// w innym miejscu na każdym arkuszu.
///
/// Dawniej ten sam pomysł żył w kilku kopiach: `AssistantStickyFooter`
/// (szczegóły posiłku, wprowadzenie asystenta), `AssistantSheetFooter`
/// (arkusze asystenta), szklana kapsuła filtrów przepisów i własne stopki
/// „Dodaj do planu”, „Wybierz posiłek”, „Na dziś” z kreską nad przyciskiem.
/// Każda miała inne odstępy i inny gradient. Teraz wszystkie idą przez ten
/// widok — od rundy 14 także kreator, przewodnik i wprowadzenie Asystenta
/// (`SCStepFooter` w `SCStepFlow.swift`, z paskiem kroków nad przyciskiem).
///
/// Dwa sposoby użycia:
/// - `.scSheetFooter { … }` na przewijanej treści — przez `safeAreaInset`
///   i z cieniem WLICZONYM w wysokość stopki: przewinięta do końca treść
///   kończy się nad cieniem, a nie w nim, bez ręcznych „zapasów” na dole;
/// - `SCSheetFooter { … }` jako ostatnie dziecko `VStack` pod listą — cień
///   wystaje wtedy nad stopkę i leży na liście, więc lista musi mieć na dole
///   zapas `SCEdgeShade.bottomHeight`.
struct SCSheetFooter<Content: View>: View {
    /// Kolor tła arkusza pod stopką. Musi być DOKŁADNIE ten sam, co dół tła
    /// arkusza — inaczej nad przyciskiem wraca twarda linia. Domyślnie
    /// `scPageBase`, czyli dół `SCPageBackground`.
    var base: Color? = nil
    var horizontalPadding: CGFloat = SCPageMetrics.horizontal
    /// Czy miejsce na cień wchodzi w wysokość stopki (`safeAreaInset`).
    var reservesShade: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if reservesShade {
                // Przezroczysty i nieklikalny — dotyk trafia w treść pod nim.
                Color.clear
                    .frame(height: SCEdgeShade.bottomHeight)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 10) { content() }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
                .background { SCFooterScrim(base: base) }
        }
    }
}

/// Tło stopki: rozmyty pas (`SCScrollEdgeBlur`) od `SCEdgeShade.bottomHeight`
/// NAD stopką do krawędzi ekranu. Nad stopką gęstnieje od zera, pod
/// przyciskami jest w pełni gęsty — przewijana treść chowa się pod szklanymi
/// przyciskami, rozmyta i przygaszona, jak w Telegramie (Liquid Glass
/// runda 3, 4.10.2026: „shadow na detail meal dolny też popraw”).
///
/// Dawniej kryjąca płyta w kolorze tła + cień krawędzi nad nią: treść
/// urywała się ścianą, a szklane przyciski nie miały nad czym być szkłem.
/// Tło nad rozmyciem jest tu gęstsze niż pod menu (0,62), bo na pasie
/// stoi tekst — zdanie nad przyciskiem, liczby obok niego.
struct SCFooterScrim: View {
    var base: Color? = nil

    var body: some View {
        let shade = SCEdgeShade.bottomHeight
        GeometryReader { proxy in
            SCScrollEdgeBlur(
                edge: .bottom,
                solidFraction: max(0, min(1, 1 - shade / max(proxy.size.height, 1))),
                base: base,
                baseOpacity: 0.62
            )
        }
        .padding(.top, -shade)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Przypina stopkę do dołu przewijanej treści arkusza (`safeAreaInset`):
    /// treść kończy się nad nią i nad jej cieniem, a przewijane wiersze giną
    /// w cieniu.
    ///
    /// Przyciski w środku biorą się z komponentów aplikacji: pełna szerokość
    /// to `EditorialPrimaryActionButton`, obok liczb — `RecipeFilterFooterButton`.
    func scSheetFooter<Footer: View>(
        base: Color? = nil,
        horizontalPadding: CGFloat = SCPageMetrics.horizontal,
        @ViewBuilder _ footer: @escaping () -> Footer
    ) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            SCSheetFooter(
                base: base,
                horizontalPadding: horizontalPadding,
                reservesShade: true,
                content: footer
            )
        }
    }
}
