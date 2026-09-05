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
                        .tint(SCPalette.terracotta)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .heavy))
                }
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.1)
            }
            .foregroundStyle(SCPalette.terracotta)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .scSoftCapsule()
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        // Jak w `SCSoftButton`: wygaszamy za brak danych, spinner zostaje
        // w pełnej mocy.
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.smooth(duration: 0.18), value: isEnabled)
    }
}
