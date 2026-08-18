import SwiftUI

// One meal "article" on Kalendarz v2.
// Numbered folio (01/02/03) on the left, hero overlay card on the right.
// Locked days fall through to the regular assigned/empty rendering, but tap is disabled.
struct EditorialMealCard: View {
    let slot: MealSlot
    let number: Int
    /// One variant of the slot — a slot can hold several when the household
    /// splits the meal, and Kalendarz stacks them.
    let meal: PlanMeal?
    let members: [HouseholdMemberSnapshot]
    /// Sourced from the recipe catalog — the meal store snapshots `favourite`
    /// at plan-save time and never re-syncs, so we read the live value here.
    let isFavourite: Bool
    let isEditable: Bool
    let onTap: () -> Void
    let onAssign: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            FolioNumber(number: number, color: slot.cozyAccent)

            VStack(alignment: .leading, spacing: 8) {
                EyebrowRow(slot: slot)

                // Hero/empty body re-mounts when the recipe identity changes
                // (i.e. user swaps days). The transition cross-fades + slightly
                // scales so the photo, title and badges swap together as a unit.
                Group {
                    if let meal {
                        AssignedHero(
                            recipe: meal.recipe,
                            participantIds: meal.participantIds,
                            members: members,
                            isFavourite: isFavourite,
                            slot: slot,
                            isEditable: isEditable,
                            onTap: onTap,
                            onToggleFavorite: onToggleFavorite
                        )
                    } else {
                        EmptyHero(
                            slot: slot,
                            isEditable: isEditable,
                            onAssign: onAssign
                        )
                    }
                }
                .id(contentIdentity)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)),
                        removal: .opacity
                    )
                )
            }
        }
        .animation(.smooth(duration: 0.22), value: contentIdentity)
    }

    private var contentIdentity: String {
        if let meal {
            return "\(slot.id).meal.\(meal.id)"
        }
        return "\(slot.id).empty"
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

// MARK: - Folio (numbered circle)

private struct FolioNumber: View {
    let number: Int
    let color: Color

    var body: some View {
        Text(String(format: "%02d", number))
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
            .overlay(
                Circle().stroke(color, lineWidth: 1.5)
            )
            .padding(.top, 2)
    }
}

// MARK: - Eyebrow (slot label · time)

private struct EyebrowRow: View {
    let slot: MealSlot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // `display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 8` — design.
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(slot.title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundStyle(slot.cozyAccent)

            Text(slot.time)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Color.wmMuted(scheme))
        }
    }
}

// MARK: - Assigned hero overlay

private struct AssignedHero: View {
    let recipe: Recipe
    let participantIds: [String]
    let members: [HouseholdMemberSnapshot]
    let isFavourite: Bool
    let slot: MealSlot
    let isEditable: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        // Hero card — `height: 260, borderRadius: 14, boxShadow: '0 10px 28px rgba(0,0,0,0.45)'`.
        //
        // Layout strategy:
        //   1. `Color.clear.frame(height: 260)` is the size anchor — exactly 260pt tall.
        //   2. `.background(heroImage)` paints the photo behind it, clipped to the frame.
        //   3. `.overlay(bottomScrim)` paints the readability gradient over the photo.
        //   4. `.overlay(alignment: .bottom)` pins the title+badges row to the bottom.
        //   5. `.overlay(alignment: .topTrailing)` pins the heart button.
        //   6. `.clipShape` rounds the corners; the bottom-aligned overlay sits inside
        //      the rounded rect so its bottom 16pt of padding is preserved.
        //
        // Earlier attempts using `.frame(maxHeight: .infinity, alignment: .bottom)`
        // on a child of a fixed-height ZStack didn't size correctly and the title
        // overflowed the card's clip region.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .background(
                heroImage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            )
            .overlay(bottomScrim)
            .overlay(alignment: .topLeading) { badgeColumn }
            .overlay(alignment: .topTrailing) { heartButton }
            .overlay(alignment: .bottom) { titleOnly }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 10)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture { onTap() }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(slot.title): \(recipe.name), \(recipe.prepTimeMinutes) minut, \(Int(recipe.nutritionPerServing.kcal)) kalorii")
    }

    private var heroImage: some View {
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
    }

    private var gradientFallback: some View {
        ZStack {
            LinearGradient(
                colors: [
                    slot.cozyTint,
                    slot.cozyTint.mix(with: .black, by: 0.40)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: slot.icon)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    private var bottomScrim: some View {
        // Stronger than design's `0.55/0.85` because real food photos are much
        // brighter than the mock's tinted gradient. Bumped to `0.65/0.95` and
        // pulled the gradient up to 80% of the card so the title is readable.
        let dark = Color(red: 12 / 255, green: 8 / 255, blue: 6 / 255)
        return LinearGradient(
            stops: [
                .init(color: dark.opacity(0),    location: 0.20),
                .init(color: dark.opacity(0.65), location: 0.65),
                .init(color: dark.opacity(0.95), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    /// Title pinned to the bottom of the card — full width, no badges next to it.
    private var titleOnly: some View {
        Text(recipe.name)
            .font(.system(size: 22, weight: .bold))
            .tracking(-0.5)
            .foregroundStyle(.white)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .allowsTightening(true)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: .black.opacity(0.45), radius: 7, x: 0, y: 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
    }

    /// Badge row pinned to the top-leading corner — clock and flame side by
    /// side, plus who the meal is for when it isn't shared. A house glyph on
    /// every card would be noise, so shared meals stay unbadged.
    private var badgeColumn: some View {
        HStack(spacing: 6) {
            GlassBadge(icon: "clock",      value: recipe.prepTimeMinutes,               unit: " min")
            GlassBadge(icon: "flame.fill", value: Int(recipe.nutritionPerServing.kcal), unit: " kcal")

            if !participantIds.isEmpty {
                PlanWhoBadge(participantIds: participantIds, members: members, size: 26)
            }
        }
        .fixedSize()
        .padding(.top, 12)
        .padding(.leading, 12)
    }

    private var heartButton: some View {
        // `position: 'absolute', top: 12, right: 12, width: 36, height: 36, borderRadius: 99`.
        // Anchored top-trailing by an `.overlay(alignment: .topTrailing)` on the card.
        //
        // Favourited state needs a high-contrast background — terracotta on a
        // food photo with ultraThinMaterial alone blends in (the icon disappears).
        // Solid terracotta fill + white heart pops cleanly in any photo.
        Button {
            onToggleFavorite()
        } label: {
            Image(systemName: isFavourite ? "heart.fill" : "heart")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background {
                    if isFavourite {
                        Circle().fill(WMPalette.terracotta)
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    Circle().stroke(
                        .white.opacity(isFavourite ? 0.28 : 0.12),
                        lineWidth: 1
                    )
                )
                .shadow(
                    color: .black.opacity(isFavourite ? 0.25 : 0),
                    radius: 6, x: 0, y: 2
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .padding(.trailing, 12)
        .accessibilityLabel(isFavourite ? "Usuń z ulubionych" : "Dodaj do ulubionych")
    }
}

// MARK: - Glass badge (clock / flame)

private struct GlassBadge: View {
    let icon: String
    let value: Int
    let unit: String   // e.g. " min", " kcal" — leading space for visual gap

    var body: some View {
        // `padding: '6px 10px', borderRadius: 99, gap: 6`.
        // Icon `size: 12, weight: 2`. Text `fontSize: 11, fontWeight: 700, letterSpacing: 0.2`.
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))

            Text(verbatim: "\(value)\(unit)")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.2)
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // Design spec: `rgba(20,14,10,0.55)` + `backdropFilter: blur(14px)`.
        // `.ultraThinMaterial` alone picks up cream tones from light food
        // photos and the white badge text disappears against it. Layering
        // an explicit dark-warm tint (#140E0A @ 55%) on top of the material
        // keeps the frosted-blur backdrop while guaranteeing readable
        // contrast on bright shots.
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().fill(Color(red: 20 / 255, green: 14 / 255, blue: 10 / 255).opacity(0.55))
                )
        }
        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - Empty state

private struct EmptyHero: View {
    let slot: MealSlot
    let isEditable: Bool
    let onAssign: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: { if isEditable { onAssign() } }) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.wmChipBg(scheme))

                // Diagonal hatch — subtle "empty space" suggestion
                HatchPattern(color: Color.wmRule(scheme))
                    .opacity(0.5)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    iconCircle
                        .padding(.top, 18)
                        .padding(.leading, 18)

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(promptText)
                            .font(.system(size: 18, weight: .bold))
                            .tracking(-0.3)
                            .foregroundStyle(Color.wmLabel(scheme))

                        if isEditable {
                            HStack(spacing: 6) {
                                Text("Wybierz z biblioteki")
                                    .font(.system(size: 12, weight: .semibold))
                                    .tracking(0.2)
                                    .foregroundStyle(WMPalette.terracotta)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(WMPalette.terracotta)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Dzień nieedytowalny")
                                    .font(.system(size: 12, weight: .semibold))
                                    .tracking(0.2)
                            }
                            .foregroundStyle(Color.wmMuted(scheme))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                }
            }
            // Same 260pt height as the assigned card so the meal stack
            // doesn't shift when slots flip between filled / empty.
            .frame(height: 260)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isEditable ? "\(promptText). Stuknij, aby wybrać przepis." : "\(slot.title) — dzień nieedytowalny")
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

    private var iconCircle: some View {
        Image(systemName: slot.icon)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Color.wmMuted(scheme))
            .frame(width: 44, height: 44)
            .background(
                Circle()
                    .fill(scheme == .dark
                        ? Color(red: 12 / 255, green: 8 / 255, blue: 6 / 255)
                        : Color(red: 251 / 255, green: 245 / 255, blue: 234 / 255))
            )
            .overlay(Circle().stroke(Color.wmRule(scheme), lineWidth: 1))
    }
}

// MARK: - Diagonal hatch pattern (used behind empty cards)

private struct HatchPattern: View {
    let color: Color
    var spacing: CGFloat = 14

    var body: some View {
        Canvas { context, size in
            let diag = size.width + size.height
            var x: CGFloat = -size.height
            while x < diag {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                context.stroke(path, with: .color(color), lineWidth: 1)
                x += spacing
            }
        }
    }
}

// `Color.mix(with:by:)` lives in
// Views/Dashboard/Products/Components/EditorialShoppingHero.swift
// (alongside the `mix(black:)` / `mix(white:)` helpers) — a single
// internal extension shared across editorial v2 surfaces.
