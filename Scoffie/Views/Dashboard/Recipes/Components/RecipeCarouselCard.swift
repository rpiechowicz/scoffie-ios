import SwiftUI

/// Reużywalny kafelek przepisu w stylu "carousel".
/// Używany w Przepisach (rails + category sheet) oraz w Planie tygodnia (picker + wiersze wybranych pozycji).
struct RecipeCarouselCard: View {
    let recipe: Recipe
    let width: CGFloat
    var selectionCount: Int = 0
    var showsHeart: Bool = true
    var showsMetrics: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    private let cornerRadius: CGFloat = 22

    private var height: CGFloat {
        width * 1.28
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            thumbnail
                .frame(width: width, height: height)
                .clipped()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color.black.opacity(0.12), location: 0.38),
                    .init(color: Color.black.opacity(0.58), location: 0.78),
                    .init(color: Color.black.opacity(0.9), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            bottomContent
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // Bez tego obszarem dotyku jest suma NARYSOWANYCH warstw: gradient jest
        // wyłączony z hit-testu, a miniatura pojawia się dopiero po wczytaniu —
        // więc dopóki obrazka nie ma, klikalny bywał sam tytuł na dole.
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(selectionStroke, lineWidth: selectionCount > 0 ? 2 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if showsHeart {
                heartBadge
                    .padding(.top, 10)
                    .padding(.trailing, 10)
            }
        }
        .shadow(color: colorScheme == .dark ? .black.opacity(0.24) : .clear, radius: 10, x: 0, y: 6)
    }

    private var selectionStroke: Color {
        if selectionCount > 0 {
            return Color.green.opacity(colorScheme == .dark ? 0.8 : 0.7)
        }
        return DashboardPalette.neutralBorder(colorScheme, opacity: 0.14)
    }

    private var bottomContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recipe.name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)

            if showsMetrics {
                HStack(spacing: 8) {
                    RecipeOverlayMetricBadge(icon: "clock", text: "\(recipe.prepTimeMinutes) min", size: .compact)
                    RecipeOverlayMetricBadge(
                        icon: "flame.fill",
                        text: "\(Int(recipe.nutritionPerServing.kcal)) kcal",
                        size: .compact
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(width: width, alignment: .leading)
    }

    private var heartBadge: some View {
        Image(systemName: recipe.favourite ? "heart.fill" : "heart")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(recipe.favourite ? Color.pink : Color.white)
            .frame(width: 28, height: 28)
            .background(Color.black.opacity(colorScheme == .dark ? 0.38 : 0.34), in: Circle())
    }

    private var thumbnail: some View {
        Group {
            if let imageURL = recipe.imageURL {
                CachedAsyncImage(url: imageURL, variant: .large) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderThumb
                    case .empty:
                        ZStack {
                            placeholderThumb
                            ProgressView()
                        }
                    @unknown default:
                        placeholderThumb
                    }
                }
            } else {
                placeholderThumb
            }
        }
    }

    private var placeholderThumb: some View {
        ZStack {
            LinearGradient(
                colors: [
                    RecipesConstants.tint(for: recipe.category).opacity(colorScheme == .dark ? 0.42 : 0.28),
                    RecipesConstants.tint(for: recipe.category).opacity(colorScheme == .dark ? 0.22 : 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: RecipesConstants.icon(for: recipe.category))
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

struct RecipeOverlayMetricBadge: View {
    let icon: String
    let text: String
    var size: RecipeBadgeSize = .regular

    var body: some View {
        HStack(spacing: size == .compact ? 4 : 5) {
            Image(systemName: icon)
                .font(.system(size: size == .compact ? 10 : 11, weight: .semibold))
            Text(text)
                .font(.system(size: size == .compact ? 10 : 11, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(.white.opacity(0.94))
        .padding(.horizontal, size == .compact ? 9 : 10)
        .padding(.vertical, size == .compact ? 5 : 6)
        .background(Color.white.opacity(0.12), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}
