import SwiftUI

/// Główne CTA arkuszy Ustawień — terakota w wariancie „soft" (tint +
/// obwódka, jak `SCSoftButton`), w kompaktowej wysokości arkusza.
/// Ten sam kształt co `editorialPrimaryButton` wewnątrz `SettingsView`
/// (tam pozostał prywatny); wyniesiony do komponentu, żeby arkusze spoza
/// monolitu — jak Cookidoo — nie kopiowały stylu po swojemu. Dodatkowo
/// umie stan ładowania: spinner w miejscu ikony, treść zostaje.
struct EditorialPrimaryActionButton: View {
    let title: String
    let icon: String
    /// Barwa przycisku. Terakota domyślnie — bo tak wygląda akcja główna.
    /// Neutralną (`Color.scLabel`) bierze druga akcja stojąca OBOK głównej:
    /// dwa terakotowe przyciski w jednym rzędzie kłóciłyby się o to, który
    /// z nich jest tym właściwym.
    var accent: Color = SCPalette.terracotta
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    private var isInteractive: Bool { isEnabled && !isLoading }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(accent)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .heavy))
                }
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.1)
                    // Dwa przyciski w rzędzie dzielą szerokość po połowie,
                    // a „Otwórz Plan” bywa od niej szersze na wąskim
                    // telefonie — ma wtedy zjechać skalą, a nie urwać się
                    // wielokropkiem w połowie słowa.
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .scSoftCapsule(accent)
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        // Jak w `SCSoftButton`: wygaszamy za brak danych, spinner zostaje
        // w pełnej mocy.
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.smooth(duration: 0.18), value: isEnabled)
    }
}
