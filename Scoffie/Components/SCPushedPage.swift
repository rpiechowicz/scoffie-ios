import SwiftUI

// Ekran WEPCHNIĘTY w stos nawigacji arkusza (6.10.2026, „jak od Apple”).
//
// Arkusz ma najwyżej JEDEN poziom: dalszy krok z jego wnętrza (dokument,
// wybór alergenów, „Twoje dane”, plany, miesiąc historii zakupów) to push
// w `NavigationStack` arkusza, a nie kolejny arkusz na arkuszu. Pierwszy
// ekran arkusza zostaje przy swoim nagłówku (`EditorialSheetHeader`, pasek
// systemu schowany), a ekran wepchnięty dostaje SYSTEMOWY pasek: „wstecz”
// i tytuł w linii — jak Ustawienia iOS.
//
// Arkusze stoją na przezroczystym tle prezentacji (`dashboardLiquidSheet`),
// więc ekran wepchnięty ma własne tło strony — bez niego w trakcie wjazdu
// prześwitywałby ekran spod arkusza.

extension View {
    /// Ekran wepchnięty w stos arkusza: tło strony, systemowy pasek z tytułem
    /// w linii i „wstecz” w kolorze aplikacji.
    func scPushedPage(_ title: String) -> some View {
        modifier(SCPushedPageModifier(title: title))
    }
}

private struct SCPushedPageModifier: ViewModifier {
    let title: String

    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(SCPageBackground(scheme: scheme).ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .tint(SCPalette.terracotta)
    }
}
