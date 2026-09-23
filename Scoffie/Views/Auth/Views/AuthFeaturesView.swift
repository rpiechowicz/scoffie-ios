import SwiftUI

/// Co jest w aplikacji — te same nazwy, co w zakładkach i Ustawieniach.
/// Asystent stoi osobno, na całą szerokość i w akcencie, bo to on spina
/// resztę; pod nim siatka 2 × 3 z kolorowymi kaflami ikon jak w Ustawieniach.
struct AuthFeaturesView: View {
    /// Niski ekran: kafle bez podpisów, żeby całość zmieściła się bez scrolla.
    var compact: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private struct Feature: Identifiable {
        let symbol: String
        let color: Color
        let title: String
        let caption: String
        var id: String { title }
    }

    private let features: [Feature] = [
        Feature(symbol: "calendar", color: SCPalette.sage, title: "Plan tygodnia", caption: "Dla całego domu"),
        Feature(symbol: "cart.fill", color: SCPalette.indigo, title: "Lista zakupów", caption: "Sama z planu"),
        Feature(symbol: "book.closed.fill", color: SCPalette.butter, title: "Przepisy", caption: "Z kcal i makro"),
        Feature(symbol: "target", color: SCPalette.terracotta, title: "Cele i makro", caption: "Pod Twój cel"),
        Feature(symbol: "person.2.fill", color: SCPalette.indigo, title: "Wspólny dom", caption: "Jeden plan"),
        Feature(symbol: "bell.fill", color: SCPalette.sage, title: "Przypomnienia", caption: "O posiłkach"),
    ]

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 8) {
            staged(0, assistantTile)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                    staged(1 + index / 2, tile(feature))
                }
            }
        }
        .onAppear { appeared = true }
    }

    /// Wejście kaskadą, rzędami od góry.
    private func staged<Content: View>(_ row: Int, _ content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 10)
            .animation(
                reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.5).delay(0.15 + Double(row) * 0.07),
                value: appeared
            )
    }

    private var assistantTile: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [SCPalette.terracotta, SCPalette.terracotta.mix(black: 0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                SCMarkShape()
                    .fill(Color.white)
                    .frame(width: 17, height: 17)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Asystent Scoffie")
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Color.scLabel(colorScheme))
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SCPalette.terracotta)
                }
                if !compact {
                    Text("Ułoży tydzień, podmieni danie, policzy makro.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.scMuted(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 9 : 12)
        .scSoftSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func tile(_ feature: Feature) -> some View {
        HStack(spacing: 10) {
            EditorialSettingsTileIcon(icon: feature.symbol, color: feature.color, size: 30, radius: 9)

            VStack(alignment: .leading, spacing: 1) {
                Text(feature.title)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scLabel(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if !compact {
                    Text(feature.caption)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.scMuted(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, compact ? 8 : 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.scTileBg(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.scTileStroke(colorScheme), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview("Dark") {
    AuthFeaturesView()
        .padding()
        .background(Color.scCanvas(.dark))
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    AuthFeaturesView()
        .padding()
        .background(Color.scCanvas(.light))
        .preferredColorScheme(.light)
}

#Preview("Compact") {
    AuthFeaturesView(compact: true)
        .padding()
        .background(Color.scCanvas(.dark))
        .preferredColorScheme(.dark)
}
