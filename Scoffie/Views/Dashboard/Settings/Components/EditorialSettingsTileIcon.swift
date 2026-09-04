import SwiftUI

// 32pt rounded square with a top-down accent gradient and a centered
// white SF Symbol — the leading element on every settings row.
//
// Source: settings.jsx → `TileIcon`.
//   `width: 32, height: 32, borderRadius: 9`.
//   Background: `linear-gradient(135deg, color → color-mix(color, #000 18%))`.
//   Inset highlight: `inset 0 1px 0 rgba(255,255,255,0.16)`.
//   Glyph: 56% of the tile size, weight 2.2, white.
struct EditorialSettingsTileIcon: View {
    let icon: String
    let color: Color

    var size: CGFloat = 32
    var radius: CGFloat = 9

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color, color.mix(black: 0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Inset top highlight — `inset 0 1px 0 rgba(255,255,255,0.16)`.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
                .blur(radius: 0.5)
                .mask(
                    LinearGradient(
                        colors: [.white, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Image(systemName: icon)
                .font(.system(size: size * 0.52, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

// Hollow "i" tile used by the "Wersja" row in the Informacje group —
// matches the design's bordered circle with the dim "i" glyph.
struct EditorialSettingsInfoTile: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.wmFeatureRowBg(scheme))

            Circle()
                .stroke(Color.wmFaint(scheme), lineWidth: 1.4)

            Text("i")
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(Color.wmFaint(scheme))
        }
        .frame(width: 32, height: 32)
    }
}
