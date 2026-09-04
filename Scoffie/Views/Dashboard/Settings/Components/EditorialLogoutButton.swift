import SwiftUI

// Full-width destructive button at the bottom of Ustawienia v2.
//
// Source: settings.jsx → trailing `<button>`.
//   `padding: '14px 16px', borderRadius: 14`.
//   Background: `rgba(212,82,71,0.14)` dark / `rgba(212,82,71,0.10)` light.
//   Foreground: `oklch(0.76 0.14 28)` dark / `oklch(0.58 0.18 28)` light.
//   Icon: door-arrow (logout) + "Wyloguj się" 15.5pt 600.
//
// Centralised in its own component so SettingsView can drop it in at
// the end of the scroll without rebuilding the destructive treatment.
struct EditorialLogoutButton: View {
    var isLoading: Bool = false
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme

    private static let destructiveDark = Color(red: 233 / 255, green: 145 / 255, blue: 117 / 255) // oklch(0.76 0.14 28)
    private static let destructiveLight = Color(red: 184 / 255, green: 70 / 255, blue: 38 / 255)  // oklch(0.58 0.18 28)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isLoading ? "hourglass" : "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 15, weight: .heavy))
                    .contentTransition(.symbolEffect(.replace))

                Text("Wyloguj się")
                    .font(.system(size: 15.5, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(background)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .opacity(isLoading ? 0.65 : 1)
        .accessibilityLabel("Wyloguj się")
    }

    private var foreground: Color {
        scheme == .dark ? Self.destructiveDark : Self.destructiveLight
    }

    private var background: Color {
        // 14% / 10% wash of a fixed terracotta-red so the button reads
        // destructive against both canvases without leaning on the brand
        // accent (which is also used elsewhere in the screen).
        let base = Color(red: 212 / 255, green: 82 / 255, blue: 71 / 255)
        return base.opacity(scheme == .dark ? 0.14 : 0.10)
    }
}
