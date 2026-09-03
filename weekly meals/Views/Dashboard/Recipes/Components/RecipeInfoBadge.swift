import SwiftUI

enum RecipeCategoryBadgeStyle {
    case subtle
    case overlayDark
}

enum RecipeBadgeSize {
    case regular
    case compact
}

struct RecipeInfoBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let text: String
    var color: Color = .secondary
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(badgeFill, in: Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var badgeFill: Color {
        colorScheme == .dark
            ? DashboardPalette.surface(colorScheme, level: .secondary)
            : Color.white.opacity(0.9)
    }

    private var borderColor: Color {
        DashboardPalette.neutralBorder(colorScheme, opacity: colorScheme == .dark ? 0.12 : 0.08)
    }
}

struct RecipeMetricBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 11)

            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.9)
        }
        .foregroundStyle(labelColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(badgeFill, in: Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var badgeFill: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.09)
        }

        return Color(red: 0.88, green: 0.89, blue: 0.92)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
    }

    private var labelColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.78)
            : Color.black.opacity(0.58)
    }
}

struct RecipeCategoryBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let category: RecipesCategory
    var style: RecipeCategoryBadgeStyle = .subtle
    var size: RecipeBadgeSize = .regular

    var body: some View {
        HStack(spacing: horizontalSpacing) {
            Image(systemName: RecipesConstants.icon(for: category))
                .font(.system(size: iconFontSize, weight: .semibold))
                .foregroundStyle(iconColor)

            Text(RecipesConstants.shortDisplayName(for: category))
                .lineLimit(1)
                .foregroundStyle(labelColor)
        }
        .font(.system(size: labelFontSize, weight: .semibold))
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(backgroundFill, in: Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 0.9)
        )
        .shadow(color: shadowColor, radius: colorScheme == .dark ? 8 : 5, x: 0, y: 2)
    }

    private var tint: Color {
        RecipesConstants.tint(for: category)
    }

    private var iconFontSize: CGFloat {
        size == .compact ? 10 : 11
    }

    private var labelFontSize: CGFloat {
        size == .compact ? 10 : 11
    }

    private var horizontalSpacing: CGFloat {
        size == .compact ? 5 : 6
    }

    private var horizontalPadding: CGFloat {
        size == .compact ? 9 : 10
    }

    private var verticalPadding: CGFloat {
        size == .compact ? 5 : 6
    }

    private var backgroundFill: Color {
        switch style {
        case .subtle:
            if colorScheme == .dark {
                return DashboardPalette.tintFill(tint, scheme: colorScheme, dark: 0.2, light: 0.14)
            }

            return DashboardPalette.tintFill(tint, scheme: colorScheme, dark: 0.2, light: 0.14)
        case .overlayDark:
            return Color.black.opacity(colorScheme == .dark ? 0.38 : 0.48)
        }
    }

    private var borderColor: Color {
        switch style {
        case .subtle:
            return tint.opacity(colorScheme == .dark ? 0.24 : 0.16)
        case .overlayDark:
            return Color.white.opacity(colorScheme == .dark ? 0.12 : 0.16)
        }
    }

    private var labelColor: Color {
        switch style {
        case .subtle:
            return tint.opacity(colorScheme == .dark ? 0.96 : 0.9)
        case .overlayDark:
            return Color.white.opacity(0.94)
        }
    }

    private var iconColor: Color {
        switch style {
        case .subtle:
            return tint.opacity(colorScheme == .dark ? 0.98 : 0.9)
        case .overlayDark:
            return tint.opacity(0.96)
        }
    }

    private var shadowColor: Color {
        switch style {
        case .subtle:
            return colorScheme == .dark ? .black.opacity(0.18) : .clear
        case .overlayDark:
            return .black.opacity(colorScheme == .dark ? 0.24 : 0.16)
        }
    }
}

struct RecipeStatusCircle: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(
                DashboardPalette.surface(colorScheme, level: .secondary),
                in: Circle()
            )
            .overlay(
                Circle()
                    .stroke(DashboardPalette.neutralBorder(colorScheme, opacity: 0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}

struct RecipeFavoriteBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let isFavorite: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 11, weight: .semibold))

            Text(isFavorite ? "Ulubione" : "Do ulubionych")
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(labelColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundFill, in: Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var backgroundFill: Color {
        if isFavorite {
            return DashboardPalette.tintFill(.pink, scheme: colorScheme, dark: 0.2, light: 0.14)
        }

        return DashboardPalette.surface(colorScheme, level: .secondary)
    }

    private var borderColor: Color {
        if isFavorite {
            return Color.pink.opacity(colorScheme == .dark ? 0.34 : 0.28)
        }

        return DashboardPalette.neutralBorder(colorScheme, opacity: 0.12)
    }

    private var labelColor: Color {
        if isFavorite {
            return .pink.opacity(colorScheme == .dark ? 0.95 : 0.88)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.84)
            : Color.black.opacity(0.72)
    }
}

s
#Preview {
    VStack(spacing: 12) {
        RecipeInfoBadge(icon: "clock", text: "30 min")
        RecipeInfoBadge(icon: "person.2", text: "2 porcje")
        RecipeInfoBadge(icon: "star", text: "łatwe", color: .green)
        RecipeInfoBadge(icon: "star.leadinghalf.filled", text: "średnie", color: .orange)
        RecipeInfoBadge(icon: "star.fill", text: "trudne", color: .red)
        RecipeMetricBadge(icon: "clock", text: "30 min")
        RecipeMetricBadge(icon: "flame.fill", text: "380 kcal")
        RecipeCategoryBadge(category: .dinner)
        RecipeCategoryBadge(category: .dinner, style: .overlayDark)
        RecipeStatusCircle(systemName: "heart.fill", tint: .pink)
        RecipeFavoriteBadge(isFavorite: true)
        RecipeFavoriteBadge(isFavorite: false)
    }
    .padding()
}
