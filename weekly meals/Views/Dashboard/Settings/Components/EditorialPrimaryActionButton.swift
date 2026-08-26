import SwiftUI

/// Główne CTA arkuszy Ustawień — terakotowa kapsuła z białym napisem.
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

    @Environment(\.colorScheme) private var scheme

    private var isInteractive: Bool { isEnabled && !isLoading }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .heavy))
                }
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: isInteractive
                                ? [WMPalette.terracotta, WMPalette.terracotta.mix(black: 0.18)]
                                : [Color.wmFaint(scheme), Color.wmFaint(scheme)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(Capsule().stroke(.white.opacity(isInteractive ? 0.22 : 0), lineWidth: 1))
            .shadow(
                color: WMPalette.terracotta.opacity(isInteractive ? 0.28 : 0),
                radius: 8, x: 0, y: 4
            )
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .opacity(isInteractive ? 1 : 0.7)
    }
}
