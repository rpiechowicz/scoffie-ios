import SwiftUI

// Recipe detail v2 — "Szczegóły Posiłku" Cozy Kitchen variant F.
// Source: design/Weekly Meals - Szczegoly Posilku.html (RecipeDetailF).
//
// 320pt hero photo that fades into the page canvas (no visible seam at the
// photo boundary), a glass heart pinned top-leading and an xmark close in
// top-trailing — same xmark-on-chip pattern as `EditorialSheetHeader` so
// every v2 sheet has a consistent dismiss affordance. Below the photo:
// eyebrow row with the category pill and the prep-time stamp, the title
// and lede, then three editorial sections — `Wartości odżywcze` (1.4 : 1
// asymmetric grid with a hero kcal tile + 3 macro chips), `Przygotowanie`
// (sage accent, numbered steps) and `Składniki` (indigo accent, ingredient
// rows). The ScrollView ignores top safe area so the photo runs edge to
// edge; the heart + close buttons sit on the parent ZStack via overlays
// that respect the sheet's top safe area.
struct RecipeDetailView: View {
    @Environment(\.colorScheme) private var scheme

    let recipe: Recipe
    var onToggleFavorite: (() -> Void)?
    var onClose: (() -> Void)?

    var body: some View {
        ZStack(alignment: .top) {
            WMPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroPhoto

                    EditorialEyebrowRow(
                        category: recipe.category,
                        prepTimeMinutes: recipe.prepTimeMinutes
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    titleAndDescription
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                    nutritionSection
                        .padding(.horizontal, 16)
                        .padding(.top, 20)

                    if !recipe.preparationSteps.isEmpty {
                        preparationSection
                            .padding(.horizontal, 20)
                            .padding(.top, 22)
                    }

                    if !recipe.ingredients.isEmpty {
                        ingredientsSection
                            .padding(.horizontal, 20)
                            .padding(.top, 22)
                    }

                    Color.clear.frame(height: 28)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(.container, edges: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            heartButton
                .padding(.leading, 16)
                .padding(.top, 12)
        }
        .overlay(alignment: .topTrailing) {
            closeButton
                .padding(.trailing, 16)
                .padding(.top, 12)
        }
    }

    // MARK: - Hero photo

    private var heroPhoto: some View {
        // 320pt design height, edge-to-edge, fades into the canvas at the
        // bottom 60pt and into a darker scrim at the top 120pt so the heart
        // and close chips read on any photo.
        Color.clear
            .frame(height: 320)
            .background(photoLayer)
            .overlay(topScrim, alignment: .top)
            .overlay(bottomFade, alignment: .bottom)
            .clipped()
            .ignoresSafeArea(edges: .top)
    }

    private var photoLayer: some View {
        Group {
            if let url = recipe.imageURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        photoFallback
                    @unknown default:
                        photoFallback
                    }
                }
            } else {
                photoFallback
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var photoFallback: some View {
        // Editorial shimmer that matches the design's `Skel` primitive —
        // warm canvas-tinted track with a left-to-right highlight pass.
        // The pre-v2 placeholder was a category-gradient + glyph, which
        // read like a different design language on this surface.
        EditorialShimmerBlock(cornerRadius: 0)
    }

    private var topScrim: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(scheme == .dark ? 0.55 : 0.30),
                Color.black.opacity(0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 120)
        .allowsHitTesting(false)
    }

    private var bottomFade: some View {
        // Matches the WMPageBackground base color at Y≈320 so the photo
        // melts into the canvas — no visible boundary line.
        let target = scheme == .dark
            ? Color(red: 12 / 255, green: 8 / 255, blue: 6 / 255)
            : Color(red: 251 / 255, green: 245 / 255, blue: 234 / 255)
        return LinearGradient(
            colors: [target.opacity(0), target],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 80)
        .allowsHitTesting(false)
    }

    // MARK: - Top chrome (heart + close)

    private var heartButton: some View {
        let liked = recipe.favourite
        let glassFill: Color = scheme == .dark
            ? Color(red: 15 / 255, green: 10 / 255, blue: 8 / 255).opacity(0.55)
            : Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.85)
        let glassStroke: Color = scheme == .dark
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.16)

        return Button(action: { onToggleFavorite?() }) {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(liked ? WMPalette.terracotta : Color.wmLabel(scheme))
                .frame(width: 44, height: 44)
                .background {
                    if liked {
                        Circle().fill(WMPalette.terracotta.opacity(scheme == .dark ? 0.30 : 0.22))
                    } else {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().fill(glassFill))
                    }
                }
                .overlay(
                    Circle().stroke(
                        liked ? WMPalette.terracotta.opacity(0.55) : glassStroke,
                        lineWidth: 1
                    )
                )
                .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.18), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .opacity(onToggleFavorite == nil ? 0 : 1)
        .disabled(onToggleFavorite == nil)
        .accessibilityLabel(liked ? "Usuń z ulubionych" : "Dodaj do ulubionych")
    }

    private var closeButton: some View {
        Button(action: { onClose?() }) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.wmLabel(scheme))
                .frame(width: 36, height: 36)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(
                            scheme == .dark
                                ? Color(red: 15 / 255, green: 10 / 255, blue: 8 / 255).opacity(0.55)
                                : Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.85)
                        ))
                }
                .overlay(
                    Circle().stroke(
                        scheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.14),
                        lineWidth: 1
                    )
                )
                .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.16), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zamknij")
    }

    // MARK: - Title + description

    private var titleAndDescription: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recipe.name)
                .font(.system(size: 30, weight: .heavy))
                .tracking(-0.8)
                .foregroundStyle(Color.wmLabel(scheme))
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if !recipe.description.isEmpty {
                Text(recipe.description)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sections

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSectionTitle(
                title: "Wartości odżywcze",
                eyebrow: nil,
                accent: WMPalette.terracotta
            )

            EditorialNutritionGrid(nutrition: recipe.nutritionPerServing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var preparationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSectionTitle(
                title: "Przygotowanie",
                eyebrow: "Krok po kroku",
                accent: WMPalette.sage
            )

            VStack(spacing: 0) {
                let sortedSteps = recipe.preparationSteps.sorted(by: { $0.stepNumber < $1.stepNumber })
                ForEach(Array(sortedSteps.enumerated()), id: \.element.id) { idx, step in
                    EditorialStepRow(
                        index: idx + 1,
                        text: step.instruction,
                        isLast: idx == sortedSteps.count - 1
                    )
                }
            }
            .background(Color.wmTileBg(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSectionTitle(
                title: "Składniki",
                eyebrow: "Lista zakupów",
                accent: WMPalette.indigo
            )

            VStack(spacing: 0) {
                ForEach(Array(recipe.ingredients.enumerated()), id: \.element.id) { idx, ingredient in
                    EditorialIngredientRow(
                        ingredient: ingredient,
                        isLast: idx == recipe.ingredients.count - 1
                    )
                }
            }
            .background(Color.wmTileBg(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var categoryAccent: Color {
        RecipeDetailPalette.accent(for: recipe.category)
    }
}

// MARK: - Eyebrow row (category pill + divider + prep-time stamp)

private struct EditorialEyebrowRow: View {
    let category: RecipesCategory
    let prepTimeMinutes: Int

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            categoryPill

            Rectangle()
                .fill(Color.wmRule(scheme))
                .frame(height: 1)
                .frame(maxWidth: .infinity)

            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .bold))
                Text(verbatim: "\(prepTimeMinutes) MIN")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .monospacedDigit()
            }
            .foregroundStyle(Color.wmMuted(scheme))
        }
    }

    private var categoryPill: some View {
        let accent = RecipeDetailPalette.accent(for: category)
        let fill = accent.opacity(scheme == .dark ? 0.22 : 0.16)
        let stroke = accent.opacity(scheme == .dark ? 0.45 : 0.30)

        return HStack(spacing: 6) {
            Image(systemName: RecipesConstants.icon(for: category))
                .font(.system(size: 11, weight: .bold))
            Text(RecipesConstants.displayName(for: category).uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.7)
                .lineLimit(1)
        }
        .foregroundStyle(accent)
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(fill))
        .overlay(Capsule().stroke(stroke, lineWidth: 1))
        .fixedSize()
    }
}

// MARK: - Section title (accent bar + optional eyebrow + title)

private struct EditorialSectionTitle: View {
    let title: String
    let eyebrow: String?
    let accent: Color

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // No `.shadow()` here — the accent bar sits 16pt above the
            // nutrition grid's terracotta-tinted hero tile, and any glow
            // from this bar bleeds straight onto that tile's top-left
            // corner. A flat fill reads cleanly without the smudge.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accent)
                .frame(width: 5, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(accent)
                }
                Text(title)
                    .font(.system(size: 22, weight: .heavy))
                    .tracking(-0.3)
                    .foregroundStyle(Color.wmLabel(scheme))
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Asymmetric nutrition grid (1 big kcal tile + 3 stacked macros)

private struct EditorialNutritionGrid: View {
    let nutrition: Nutrition

    var body: some View {
        // Design: `gridTemplateColumns: '1.4fr 1fr'`. SwiftUI doesn't have
        // a fractional grid template, so we split available width with a
        // GeometryReader and lay the two columns out manually.
        GeometryReader { geo in
            let gap: CGFloat = 10
            let usable = geo.size.width - gap
            let bigW = (usable * 1.4) / 2.4
            let smallW = (usable * 1.0) / 2.4

            HStack(alignment: .top, spacing: gap) {
                EditorialKcalTile(value: nutrition.kcal)
                    .frame(width: bigW, height: 168)

                VStack(spacing: gap) {
                    EditorialMacroTile(
                        label: "Białko",
                        value: nutrition.protein,
                        unit: "g",
                        icon: "sparkles",
                        accent: WMPalette.indigo
                    )
                    EditorialMacroTile(
                        label: "Węglowodany",
                        value: nutrition.carbs,
                        unit: "g",
                        icon: "leaf.fill",
                        accent: WMPalette.sage
                    )
                    EditorialMacroTile(
                        label: "Tłuszcze",
                        value: nutrition.fat,
                        unit: "g",
                        icon: "drop.fill",
                        accent: WMPalette.terracottaDeep
                    )
                }
                .frame(width: smallW, height: 168)
            }
        }
        .frame(height: 168)
    }
}

private struct EditorialKcalTile: View {
    let value: Double

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let accent = WMPalette.terracotta
        let formatted = RecipeDetailFormat.integer(value)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    // Icon chip uses `tint(accent, 0.65)` for fill and
                    // `tintBorder(accent, 0.40)` for stroke — mapped to
                    // 0.35/0.60 dark and 0.53/0.80 light per the design's
                    // tint helpers.
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(scheme == .dark ? 0.35 : 0.53))
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(accent.opacity(scheme == .dark ? 0.60 : 0.80), lineWidth: 1)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accent)
                }
                .frame(width: 32, height: 32)

                Text("KALORIE")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.7)
                    .foregroundStyle(accent)
            }

            Spacer(minLength: 8)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(formatted)
                    .font(.system(size: 44, weight: .heavy))
                    .tracking(-1.4)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text("kcal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.wmMuted(scheme))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            // Top-left radial highlight — direct port of the design's
            // `radial-gradient(120% 80% at 0% 0%, tint(accent, 0.70) 0%, transparent 60%)`.
            // SwiftUI's `EllipticalGradient` already inherits the tile's
            // aspect ratio, so the falloff matches the design's 1.5:1
            // ellipse closely without a manual scaleEffect.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    EllipticalGradient(
                        stops: [
                            .init(color: accent.opacity(scheme == .dark ? 0.30 : 0.52), location: 0.0),
                            .init(color: accent.opacity(0),                              location: 0.60),
                            .init(color: accent.opacity(0),                              location: 1.0)
                        ],
                        center: UnitPoint(x: -0.05, y: -0.05),
                        startRadiusFraction: 0,
                        endRadiusFraction: 1.0
                    )
                )
        )
        .background(
            // Card base — dark gets a subtle vertical brighten from
            // `cardStrong` (6% cream) to `card` (4% cream) so the tile
            // lifts off the near-black canvas. Light mode lets the page
            // canvas show through (`.clear`) per user spec: the tile
            // should differ from the sheet only via the terracotta
            // gradient + border, not via a second cream tone.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: scheme == .dark
                            ? [
                                Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.06),
                                Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.04)
                            ]
                            : [
                                Color.clear,
                                Color.clear
                            ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            // Border opacities ported from the design's `tintBorder(accent, 0.55)`:
            // dark → 1 − 0.55 = 0.45; light → 1 − 0.35 = 0.65.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.opacity(scheme == .dark ? 0.45 : 0.65), lineWidth: 1)
        )
    }
}

private struct EditorialMacroTile: View {
    let label: String
    let value: Double
    let unit: String
    let icon: String
    let accent: Color

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                // Icon chip per design: `tint(accent, 0.78)` fill +
                // `tintBorder(accent, 0.60)` stroke → 0.22/0.40 dark and
                // 0.40/0.60 light.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(scheme == .dark ? 0.22 : 0.40))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(accent.opacity(scheme == .dark ? 0.40 : 0.60), lineWidth: 1)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                // The longest Polish label is `WĘGLOWODANY` (11 chars with
                // an `Ę` ogonek that runs wider than a plain `E` at heavy
                // weight). On compact iPhones the small-tile content area
                // can dip under 80pt, so the heavy/wide glyphs truncate
                // before `minimumScaleFactor` engages. Drop a half-point
                // and let the system tighten + scale aggressively before
                // falling back to ellipsis.
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Color.wmMuted(scheme))
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.7)

                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(RecipeDetailFormat.macro(value))
                        .font(.system(size: 16, weight: .heavy))
                        .tracking(-0.3)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .monospacedDigit()
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.wmMuted(scheme))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
    }
}

// MARK: - Steps & ingredients rows

private struct EditorialStepRow: View {
    let index: Int
    let text: String
    let isLast: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(index)")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(WMPalette.sage)
                .monospacedDigit()
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .stroke(WMPalette.sage.opacity(scheme == .dark ? 0.55 : 0.40), lineWidth: 1.5)
                )

            Text(text)
                .font(.system(size: 14.5))
                .foregroundStyle(Color.wmLabel(scheme))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.wmRule(scheme).opacity(0.6))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }
        }
    }
}

private struct EditorialIngredientRow: View {
    let ingredient: Ingredient
    let isLast: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(RecipeDetailFormat.ingredientName(ingredient.name))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.wmLabel(scheme))
                .lineLimit(2)

            Spacer(minLength: 8)

            Text(RecipeDetailFormat.ingredientAmount(ingredient))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.wmMuted(scheme))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.wmRule(scheme).opacity(0.6))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Shimmer (matches design's `Skel` primitive)

private struct EditorialShimmerBlock: View {
    var cornerRadius: CGFloat = 0
    @Environment(\.colorScheme) private var scheme
    @State private var slide: CGFloat = -1

    var body: some View {
        let track = scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.06)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.06)
        let highlight = scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.10)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.10)

        GeometryReader { geo in
            ZStack {
                track

                LinearGradient(
                    stops: [
                        .init(color: track,     location: 0.0),
                        .init(color: highlight, location: 0.5),
                        .init(color: track,     location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 1.6)
                .offset(x: slide * geo.size.width * 1.3)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    slide = 1
                }
            }
        }
    }
}

// MARK: - Palette + formatters

private enum RecipeDetailPalette {
    /// Cozy Kitchen accent per recipe category. Mirrors the meal-slot
    /// mapping used by `EditorialMealCard` so a breakfast recipe surfaces
    /// in butter, lunch in sage, dinner in indigo across both screens.
    static func accent(for category: RecipesCategory) -> Color {
        switch category {
        case .breakfast: return WMPalette.butter
        case .lunch:     return WMPalette.sage
        case .dinner:    return WMPalette.indigo
        case .favourite: return WMPalette.terracotta
        case .all:       return WMPalette.terracotta
        }
    }
}

private enum RecipeDetailFormat {
    static func integer(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value.rounded()))"
    }

    static func macro(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func ingredientName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        return String(first).uppercased(with: Locale(identifier: "pl_PL")) + trimmed.dropFirst()
    }

    static func ingredientAmount(_ ingredient: Ingredient) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        let amount = formatter.string(from: NSNumber(value: ingredient.amount)) ?? "\(ingredient.amount)"
        return "\(amount) \(ingredient.unit.rawValue)"
    }
}

#Preview("Recipe Detail v2 — Dark") {
    RecipeDetailView(recipe: RecipesMock.chickenBowl, onToggleFavorite: {})
        .preferredColorScheme(.dark)
}

#Preview("Recipe Detail v2 — Light") {
    RecipeDetailView(recipe: RecipesMock.chickenBowl, onToggleFavorite: {})
        .preferredColorScheme(.light)
}
