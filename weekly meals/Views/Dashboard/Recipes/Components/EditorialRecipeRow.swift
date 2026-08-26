import SwiftUI

// One recipe row inside a "Tasting menu" section on Przepisy v2.
// Source: design/Weekly Meals - Przepisy.html → recipes-v2.jsx RowC
// (chosen as the default row variant after the chat handoff).
//   Container — `padding: 10px 20px`, gap 14, items center.
//   Cover — 48×48 rounded 12, photo cover/center or tinted gradient
//   placeholder with the category glyph.
//   Title — 17pt 600, tracking -0.3, line-height 21pt, label color,
//   `textWrap: balance`, marginBottom 3pt.
//   Meta — 12pt 500 muted, "{time} min · {kcal} kcal · {protein} g białka"
//   with tabular nums.
//   Trailing — terracotta heart when favourite, then 14pt chevron in faint.
struct EditorialRecipeRow: View {
    let recipe: Recipe
    var action: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: { action?() }) {
            HStack(alignment: .center, spacing: 14) {
                EditorialRecipeCover(recipe: recipe, size: 48, cornerRadius: 12)

                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.name)
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(metaText)
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.wmMuted(scheme))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Dyskretny znacznik przed serduszkiem — sam glif, bez
                // kapsuły: wiersz ma 3 linie tekstu i każdy dodatkowy chip
                // rozpychałby stałą wysokość listy.
                if recipe.isThermomix {
                    Image(systemName: "cooktop.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WMPalette.sage)
                        .accessibilityLabel("Przepis na Thermomix")
                }

                if recipe.favourite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WMPalette.terracotta)
                        .accessibilityHidden(true)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.wmFaint(scheme))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var metaText: String {
        let nutrition = recipe.nutritionPerServing
        let kcal = Int(nutrition.kcal.rounded())
        let protein = Int(nutrition.protein.rounded())
        return "\(recipe.prepTimeMinutes) min · \(kcal) kcal · \(protein) g białka"
    }
}

// Square cover used by `EditorialRecipeRow` and the category sheet —
// renders the recipe photo when available, otherwise a category-tinted
// gradient placeholder with the category glyph.
//
// Kept separate from `RecipeCarouselCard` so the weekly-plan picker can
// keep using the v1 photo card (different size / overlay treatment) while
// the new editorial rows get the small editorial square.
struct EditorialRecipeCover: View {
    let recipe: Recipe
    var size: CGFloat = 48
    var cornerRadius: CGFloat = 12

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let url = recipe.imageURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.wmTileStroke(scheme), lineWidth: 1)
        )
    }

    private var placeholder: some View {
        let tint = RecipeAccent.accent(for: recipe.category)
        return ZStack {
            LinearGradient(
                colors: [
                    tint.opacity(scheme == .dark ? 0.85 : 0.40),
                    tint.opacity(scheme == .dark ? 0.45 : 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: RecipesConstants.icon(for: recipe.category))
                .font(.system(size: max(14, size * 0.42), weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
        }
    }
}
