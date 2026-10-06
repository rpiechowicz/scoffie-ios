import SwiftUI

/// Kafelek ikony wiersza listy — JEDEN w całej aplikacji (6.10.2026, „jak od
/// Apple”, artefakt „Ustawienia Scoffie”): Ustawienia, lista w Filtrach
/// (`RecipeFilterListRowLabel`), arkusze Ustawień, logowanie i kreator.
/// Płaski zaokrąglony kwadrat 30 pt w kolorze akcentu z białym glifem, jak
/// ikony w Ustawieniach iOS — bez gradientu i białej poświaty z makiety
/// „settings.jsx” (`TileIcon` 32 pt), które odpadły.
///
/// Kolor zawsze w GŁĘBOKIM wariancie (jasnego motywu), także w ciemnym:
/// ciemne warianty palety są jasne, strojone pod tekst na czerni, i biały glif
/// ginął na jasnej szałwii czy maśle. iOS robi tak samo — kafle Ustawień mają
/// te same nasycone kolory w obu motywach.
struct EditorialSettingsTileIcon: View {
    let icon: String
    let color: Color

    var size: CGFloat = 30
    var radius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color)
            // Rozwiązanie koloru w jasnym motywie = głęboki wariant palety.
            .environment(\.colorScheme, .light)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(.sc(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}
