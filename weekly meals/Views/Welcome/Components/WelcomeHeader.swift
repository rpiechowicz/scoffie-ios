import SwiftUI

// Per-step header used on every welcome page — accent badge icon, eyebrow,
// large title, and an optional subtitle. The badge carries a soft glow in
// the step's accent color so each page feels distinct without changing the
// canvas background.
struct WelcomeStepHeader: View {
    let icon: String
    let accent: Color
    let eyebrow: String
    let title: String
    let subtitle: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.95),
                                accent.opacity(0.72),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: accent.opacity(0.32), radius: 16, x: 0, y: 8)

                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(WMPalette.terracotta)

                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.wmLabel(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.wmMuted(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("Header") {
    VStack(alignment: .leading, spacing: 32) {
        WelcomeStepHeader(
            icon: "person.fill",
            accent: WMPalette.terracotta,
            eyebrow: "Witaj w Weekly Meals",
            title: "Zacznijmy od Ciebie",
            subtitle: "Te dane pomogą nam dopasować propozycje. Zmienisz je później w ustawieniach."
        )
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(WMPalette.canvasDark)
    .preferredColorScheme(.dark)
}
