import SwiftUI

// MARK: - Stopka arkusza

/// Stopka z przyciskami na dole arkusza — JEDNA w całej aplikacji.
///
/// Od 4.10.2026 (Rafał: „każdy sheet, gdzie jest scrollowane i jest button —
/// natywnie jak w iOS, bez ciemnego shadow pod spodem, tylko button liquid”)
/// stopka NIE MA tła: ani kryjącej płyty, ani cienia krawędzi, ani rozmytego
/// pasa. Stoją same szklane przyciski, a przewijana treść płynnie przejeżdża
/// pod nimi. Przyklejona do przewijania (`.scSheetFooter`) idzie systemowym
/// `safeAreaBar` z iOS 26: treść kończy się nad stopką, a pod nią system
/// sam kładzie swój natywny, lekki efekt krawędzi — ten sam co pod paskami
/// narzędzi w aplikacjach Apple. Nie wracać do `SCEdgeShade` ani pasa
/// (`SCFooterScrim` usunięty).
///
/// Dawniej ten sam pomysł żył w kilku kopiach: `AssistantStickyFooter`
/// (wprowadzenie asystenta), `AssistantSheetFooter` (arkusze asystenta),
/// szklana kapsuła filtrów przepisów i własne stopki „Dodaj do planu”,
/// „Wybierz posiłek”, „Na dziś” z kreską nad przyciskiem. Teraz wszystkie
/// idą przez ten widok — także kreator, przewodnik i wprowadzenie Asystenta
/// (`SCStepFooter` w `SCStepFlow.swift`). Szczegóły posiłku mają własny
/// pasek na tej samej zasadzie (`RecipeDetail.primaryActionBar`).
///
/// Dwa sposoby użycia:
/// - `.scSheetFooter { … }` na przewijanej treści — `safeAreaBar`, treść
///   przejeżdża pod przyciskami i kończy się nad nimi;
/// - `SCSheetFooter { … }` jako ostatnie dziecko `VStack` pod listą albo
///   nakładka na dole.
struct SCSheetFooter<Content: View>: View {
    /// Zostawione dla zgodności wywołań — stopka nie ma już tła.
    var base: Color? = nil
    var horizontalPadding: CGFloat = SCPageMetrics.horizontal
    /// Dawniej miejsce na cień w wysokości stopki. Cienia nie ma — zostaje
    /// tylko oddech nad przyciskami.
    var reservesShade: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 10) { content() }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, reservesShade ? 16 : 12)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Przypina stopkę do dołu przewijanej treści arkusza systemowym
    /// `safeAreaBar` (iOS 26): treść przejeżdża pod szklanymi przyciskami
    /// i kończy się nad nimi, a efekt krawędzi kładzie system.
    ///
    /// Przyciski w środku biorą się z komponentów aplikacji: pełna szerokość
    /// to `EditorialPrimaryActionButton`, obok liczb — `RecipeFilterFooterButton`.
    func scSheetFooter<Footer: View>(
        base: Color? = nil,
        horizontalPadding: CGFloat = SCPageMetrics.horizontal,
        @ViewBuilder _ footer: @escaping () -> Footer
    ) -> some View {
        safeAreaBar(edge: .bottom, spacing: 0) {
            SCSheetFooter(
                base: base,
                horizontalPadding: horizontalPadding,
                reservesShade: true,
                content: footer
            )
        }
    }
}
