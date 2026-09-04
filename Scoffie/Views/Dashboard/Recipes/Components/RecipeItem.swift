import SwiftUI

struct RecipeItemView: View {
    let recipe: Recipe
    var isInPlanningMode: Bool = false
    var isSelected: Bool = false
    var badgeCount: Int = 0
    var availabilityBadgeText: String? = nil
    var availabilityBadgeColor: Color = .green
    @Environment(\.colorScheme) private var colorScheme
    private let cardCornerRadius: CGFloat = 18
    private let imageHeight: CGFloat = 140
    private let titleBlockHeight: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                if let imageURL = recipe.imageURL {
                    Color(.secondarySystemFill)
                        .frame(height: imageHeight)
                        .overlay(
                            CachedAsyncImage(url: imageURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                case .failure:
                                    Image(systemName: "fork.knife.circle")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.secondary)
                                case .empty:
                                    ProgressView()
                                @unknown default:
                                    Image(systemName: "fork.knife.circle")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    recipePlaceholder
                }

                if let availabilityBadgeText {
                    Text(availabilityBadgeText)
                        .font(.caption)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(availabilityBadgeColor, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
                        )
                        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                        .padding(8)
                } else if badgeCount > 1 {
                    Text("\(badgeCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(.blue, in: Circle())
                        .padding(8)
                }
            }
            .frame(height: imageHeight)

            HStack(alignment: .center, spacing: 8) {
                categoryPill

                Spacer(minLength: 8)

                if isSelected {
                    statusIconBadge(systemName: "checkmark.circle.fill", foreground: .green)
                } else if recipe.favourite {
                    statusIconBadge(systemName: "heart.fill", foreground: .pink)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .leading)

            Text(recipe.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, minHeight: titleBlockHeight, maxHeight: titleBlockHeight, alignment: .topLeading)

            HStack(spacing: 6) {
                infoPill(icon: "clock", text: "\(recipe.prepTimeMinutes) min")
                infoPill(icon: "flame.fill", text: "\(Int(recipe.nutritionPerServing.kcal)) kcal")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(cardFill, in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(
                    isSelected
                        ? Color.green.opacity(colorScheme == .dark ? 0.8 : 0.65)
                        : DashboardPalette.neutralBorder(colorScheme, opacity: 0.12),
                    lineWidth: isSelected ? 2 : 1
                )
        )
    }

    private var recipePlaceholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.secondarySystemFill))
            .frame(height: imageHeight)
            .overlay(
                Image(systemName: "fork.knife.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            )
    }

    private var categoryPill: some View {
        RecipeCategoryBadge(category: recipe.category)
    }

    private func statusIconBadge(systemName: String, foreground: Color) -> some View {
        RecipeStatusCircle(systemName: systemName, tint: foreground)
    }

    private func infoPill(icon: String, text: String) -> some View {
        RecipeMetricBadge(icon: icon, text: text)
    }

    private var cardFill: Color {
        if isSelected {
            return DashboardPalette.tintFill(.green, scheme: colorScheme, dark: 0.12, light: 0.13)
        }

        return DashboardPalette.surface(colorScheme, level: .secondary)
    }
}


#Preview {
    RecipeItemView(recipe: RecipesMock.omelette)
}
