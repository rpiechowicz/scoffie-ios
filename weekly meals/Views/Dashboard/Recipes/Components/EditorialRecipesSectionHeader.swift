import SwiftUI

// Section header for the "Tasting menu" lists below the carousel on
// Przepisy v2. Source: design/Weekly Meals - Przepisy.html → recipes-v2.jsx
// W4SectionHeader.
//   Outer padding `22px 20px 12px`, items aligned to flex-end.
//   Accent rod 5×36 with `0 0 18px accent` glow.
//   Eyebrow 11pt 700 tracking 1.4 uppercase accent color.
//   Title — 22pt 700, tracking -0.3, label color.
//   Trailing chevron pill — 32pt circle, `color-mix(in oklch, accent,
//   transparent 82%)` fill + border. Chevron 14pt accent.
//
// Tapping the chevron / row opens the category sheet (RecipeCategorySheet).
struct EditorialRecipesSectionHeader: View {
    let eyebrow: String
    let title: String
    let accent: Color
    var action: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Capsule(style: .continuous)
                .fill(accent)
                .frame(width: 5, height: 36)
                .shadow(color: accent.opacity(scheme == .dark ? 0.55 : 0.32), radius: 10, x: 0, y: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(accent)
                    .lineLimit(1)

                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let action {
                Button(action: action) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(accent)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(accent.opacity(scheme == .dark ? 0.18 : 0.12))
                        )
                        .overlay(
                            Circle().stroke(accent.opacity(scheme == .dark ? 0.32 : 0.24), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zobacz wszystkie – \(title)")
            }
        }
    }
}

// Cozy Kitchen accent per recipe category — single source of truth used by
// the section headers and editorial covers across the Przepisy v2 surface.
// Mirrors `RecipeDetailPalette.accent(for:)` in RecipeDetail.swift, which
// stayed private because the detail view didn't need an exported version.
enum RecipeAccent {
    static func accent(for category: RecipesCategory) -> Color {
        switch category {
        case .breakfast: return WMPalette.butter
        case .lunch:     return WMPalette.sage
        case .dinner:    return WMPalette.indigo
        case .favourite: return WMPalette.terracotta
        case .all:       return WMPalette.terracotta
        }
    }

    /// Akcent dla poziomu trudności — używany przez chipy w arkuszu filtrów.
    static func accent(for difficulty: Difficulty) -> Color {
        switch difficulty {
        case .easy:   return WMPalette.sage
        case .medium: return WMPalette.butter
        case .hard:   return WMPalette.terracotta
        }
    }

    /// Akcent dla tagu profilu odżywczego — chipy w arkuszu filtrów.
    static func accent(for tag: RecipeNutritionTag) -> Color {
        switch tag {
        case .highProtein: return WMPalette.terracotta
        case .lowCarb:     return WMPalette.indigo
        case .lowFat:      return WMPalette.butter
        case .highFiber:   return WMPalette.sage
        case .lowSalt:     return WMPalette.indigo
        }
    }

    /// Polish "eyebrow" tagline above the section title — matches the
    /// design's "Na dobry start / Na środek dnia / Na spokojny wieczór"
    /// rhythm and falls back to the category name for filter pseudo-cats.
    static func eyebrow(for category: RecipesCategory) -> String {
        switch category {
        case .breakfast: return "Na dobry start"
        case .lunch:     return "Na środek dnia"
        case .dinner:    return "Na spokojny wieczór"
        case .favourite: return "Smaki na dziś"
        case .all:       return "Wszystkie smaki"
        }
    }
}
