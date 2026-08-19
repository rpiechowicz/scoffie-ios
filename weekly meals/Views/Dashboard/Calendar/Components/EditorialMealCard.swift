import SwiftUI

// One meal on Kalendarz — compact row.
//
// Replaces the 260pt hero-photo card. Three of those filled more than two
// screens on an iPhone, so the day's actual shape — what you eat and whether
// you ate it — was never visible at once. This row is ~88pt, which puts all
// three meals plus the macro block above the fold.
//
// Layout: thumbnail · (eyebrow / title / meta) · (heart, eaten tick).
// The folio number (01/02/03) is gone with the hero — the slot eyebrow
// already says which meal this is, and three numbered circles cost 42pt of
// width to repeat it.
struct EditorialMealCard: View {
    let slot: MealSlot
    /// One variant of the slot — a slot can hold several when the household
    /// splits the meal, and Kalendarz stacks them.
    let meal: PlanMeal?
    /// Sourced from the recipe catalog — the meal store snapshots `favourite`
    /// at plan-save time and never re-syncs, so we read the live value here.
    let isFavourite: Bool
    /// Did the signed-in user mark this meal as eaten?
    let isEaten: Bool
    /// Future days have nothing to log yet, so the tick only appears from
    /// today backwards. Past days stay markable on purpose — logging
    /// yesterday's dinner in the evening is the normal case, and those days
    /// are read-only for *planning*, not for what already happened.
    let showsEatenToggle: Bool
    let isEditable: Bool
    let onTap: () -> Void
    let onAssign: () -> Void
    let onToggleFavorite: () -> Void
    let onToggleEaten: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let meal {
                assignedRow(meal)
            } else {
                emptyRow
            }
        }
        .id(contentIdentity)
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .center)),
                removal: .opacity
            )
        )
        .animation(.smooth(duration: 0.22), value: contentIdentity)
        .animation(.smooth(duration: 0.22), value: isEaten)
    }

    private var contentIdentity: String {
        if let meal {
            return "\(slot.id).meal.\(meal.id)"
        }
        return "\(slot.id).empty"
    }

    // MARK: - Assigned

    private func assignedRow(_ meal: PlanMeal) -> some View {
        HStack(alignment: .center, spacing: 12) {
            MealThumbnail(recipe: meal.recipe, slot: slot, isEaten: isEaten)

            VStack(alignment: .leading, spacing: 3) {
                EyebrowRow(slot: slot, isEaten: isEaten)

                Text(meal.recipe.name)
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                metaRow(meal.recipe)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actionColumn
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isEaten ? WMPalette.sage.opacity(scheme == .dark ? 0.14 : 0.09) : Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isEaten ? WMPalette.sage.opacity(0.38) : Color.wmTileStroke(scheme),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { onTap() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(slot.title): \(meal.recipe.name), \(meal.recipe.prepTimeMinutes) minut, "
            + "\(Int(meal.recipe.nutritionPerServing.kcal)) kalorii"
            + (isEaten ? ", zjedzone" : "")
        )
    }

    /// Czas · kcal, a po oznaczeniu — sam znacznik „Zjedzone". Kalorie
    /// przenoszą się wtedy do bloku makro na górze ekranu jako policzone,
    /// więc powtarzanie ich tutaj tylko dublowałoby liczbę.
    private func metaRow(_ recipe: Recipe) -> some View {
        HStack(spacing: 6) {
            if isEaten {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(WMPalette.sage)

                Text("Zjedzone · \(Int(recipe.nutritionPerServing.kcal)) kcal")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(WMPalette.sage)
                    .monospacedDigit()
            } else {
                Image(systemName: "clock")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.wmMuted(scheme))

                Text("\(recipe.prepTimeMinutes) min · \(Int(recipe.nutritionPerServing.kcal)) kcal")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
    }

    private var actionColumn: some View {
        VStack(spacing: 6) {
            Button(action: onToggleFavorite) {
                Image(systemName: isFavourite ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isFavourite ? WMPalette.terracotta : Color.wmMuted(scheme))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.wmChipBg(scheme)))
                    .overlay(Circle().stroke(Color.wmTileStroke(scheme), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavourite ? "Usuń z ulubionych" : "Dodaj do ulubionych")

            if showsEatenToggle {
                EatenToggle(isEaten: isEaten, action: onToggleEaten)
            }
        }
    }

    // MARK: - Empty

    private var emptyRow: some View {
        Button(action: { if isEditable { onAssign() } }) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: slot.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .frame(width: 64, height: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.wmChipBg(scheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.wmRule(scheme), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    EyebrowRow(slot: slot, isEaten: false)

                    Text(promptText)
                        .font(.system(size: 15, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .lineLimit(1)

                    if isEditable {
                        HStack(spacing: 4) {
                            Text("Wybierz z biblioteki")
                                .font(.system(size: 11.5, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(WMPalette.terracotta)
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Dzień nieedytowalny")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundStyle(Color.wmMuted(scheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.wmTileBg(scheme).opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        Color.wmTileStroke(scheme),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                isEditable
                    ? "\(promptText). Stuknij, aby wybrać przepis."
                    : "\(slot.title) — dzień nieedytowalny"
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
    }

    private var promptText: String {
        switch slot {
        case .breakfast: return "Co dziś na śniadanie?"
        case .lunch:     return "Co dziś na obiad?"
        case .dinner:    return "Co dziś na kolację?"
        }
    }
}

// MARK: - MealSlot palette mapping

extension MealSlot {
    /// Cozy Kitchen accent — overrides the default system colors for this design.
    var cozyAccent: Color {
        switch self {
        case .breakfast: return WMPalette.butter
        case .lunch:     return WMPalette.sage
        case .dinner:    return WMPalette.indigo
        }
    }

    /// Hero tint used when the recipe has no image.
    var cozyTint: Color {
        switch self {
        case .breakfast: return WMPalette.butter
        case .lunch:     return WMPalette.sage
        case .dinner:    return WMPalette.indigo
        }
    }
}

// MARK: - Eyebrow (slot label · time)

private struct EyebrowRow: View {
    let slot: MealSlot
    let isEaten: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(slot.title.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(isEaten ? WMPalette.sage : slot.cozyAccent)

            Text(slot.time)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.wmMuted(scheme))
        }
        .lineLimit(1)
    }
}

// MARK: - Thumbnail

private struct MealThumbnail: View {
    let recipe: Recipe
    let slot: MealSlot
    let isEaten: Bool

    var body: some View {
        Group {
            if let url = recipe.imageURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        gradientFallback
                    @unknown default:
                        gradientFallback
                    }
                }
            } else {
                gradientFallback
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Zjedzony posiłek przygasa — zdjęcie zostaje czytelne, ale przestaje
        // konkurować o uwagę z tym, co dopiero przed użytkownikiem.
        .saturation(isEaten ? 0.45 : 1)
        .opacity(isEaten ? 0.75 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var gradientFallback: some View {
        ZStack {
            LinearGradient(
                colors: [slot.cozyTint, slot.cozyTint.mix(with: .black, by: 0.40)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: slot.icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.white.opacity(0.65))
        }
    }
}

// MARK: - Eaten tick

// Główna nowa akcja na tym ekranie: „zjadłem". Pełny sage z białym ptaszkiem
// po zaznaczeniu, pusty okrąg przed — różnica musi być czytelna kątem oka,
// bo to ona odróżnia policzone kalorie od samych planów.
private struct EatenToggle: View {
    let isEaten: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(isEaten ? .white : Color.wmMuted(scheme))
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(
                        isEaten
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [WMPalette.sage, WMPalette.sage.mix(black: 0.18)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            : AnyShapeStyle(Color.wmChipBg(scheme))
                    )
                )
                .overlay(
                    Circle().stroke(
                        isEaten ? WMPalette.sage.opacity(0.45) : Color.wmTileStroke(scheme),
                        lineWidth: 1
                    )
                )
                .shadow(color: WMPalette.sage.opacity(isEaten ? 0.28 : 0), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isEaten ? "Cofnij oznaczenie zjedzenia" : "Oznacz jako zjedzone")
        .accessibilityAddTraits(isEaten ? [.isSelected, .isButton] : .isButton)
    }
}

// `Color.mix(with:by:)` lives in
// Views/Dashboard/Products/Components/EditorialShoppingHero.swift
// (alongside the `mix(black:)` / `mix(white:)` helpers) — a single
// internal extension shared across editorial v2 surfaces.
