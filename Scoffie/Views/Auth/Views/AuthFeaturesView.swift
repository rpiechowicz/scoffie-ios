import SwiftUI

struct AuthFeaturesView: View {
    @Environment(\.colorScheme) private var colorScheme

    private struct Feature {
        let symbol: String
        let text: String
    }

    private let features: [Feature] = [
        Feature(symbol: "calendar", text: "Ułóż menu na cały tydzień"),
        Feature(symbol: "cart.fill", text: "Automatyczna lista zakupów"),
        Feature(symbol: "leaf.fill", text: "Zbilansowane propozycje posiłków"),
        Feature(symbol: "bell.fill", text: "Przypomnienia o posiłkach")
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(features, id: \.text) { feature in
                row(feature)
            }
        }
    }

    private func row(_ feature: Feature) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.wmAccentTint(colorScheme))
                Image(systemName: feature.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WMPalette.terracotta)
            }
            .frame(width: 28, height: 28)

            Text(feature.text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.wmLabel(colorScheme))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.wmFeatureRowBg(colorScheme))
        )
    }
}

#Preview("Dark") {
    AuthFeaturesView()
        .padding()
        .background(Color.wmCanvas(.dark))
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    AuthFeaturesView()
        .padding()
        .background(Color.wmCanvas(.light))
        .preferredColorScheme(.light)
}
