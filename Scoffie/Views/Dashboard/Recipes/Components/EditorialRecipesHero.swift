import SwiftUI

// Editorial hero block above the featured carousel on Przepisy v2.
// Source: design/Scoffie - Przepisy.html → recipes-v2.jsx RecipesV2_W3
// ("Polecane · Smaki na dziś" block).
//   Outer padding `4px 20px 14px`, accent rod 6×44 with terracotta glow.
//   Eyebrow — 11pt 700, tracking 1.4, uppercase, terracotta.
//   Title — 28pt 700, tracking -0.5, line-height 32pt, label color.
//
// `title` swaps to "Najlepsze dopasowanie" while the user is actively
// searching, mirroring the v1 behaviour so the carousel doesn't silently
// re-label itself.
struct EditorialRecipesHero: View {
    let eyebrow: String
    let title: String
    var accent: Color = SCPalette.terracotta

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Capsule(style: .continuous)
                .fill(accent)
                .frame(width: 6, height: 44)
                .shadow(color: accent.opacity(scheme == .dark ? 0.65 : 0.35), radius: 12, x: 0, y: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(accent)
                    .lineLimit(1)

                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
