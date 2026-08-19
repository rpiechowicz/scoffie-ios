import SwiftUI

// One page of the Plan v2 day carousel: a single day with all its meal slots.
//
// Today gets the terracotta treatment (filled date tile, warm radial glow,
// coloured border + drop shadow, "DZIŚ" badge); past days render at 0.72
// opacity and are read-only.
//
// A slot holding several variants stacks them as plain rows; the „kto co je"
// comparison lives in `PlanDaySplitsSection`, directly under this card.
struct PlanDayCard: View {
    let date: Date
    let isToday: Bool
    let isPast: Bool
    let isEditable: Bool
    let profile: PlanProfile
    let members: [HouseholdMemberSnapshot]
    /// Variants planned for that slot, already filtered to the active profile.
    let meals: (MealSlot) -> [PlanMeal]
    let onTapMeal: (MealSlot, PlanMeal) -> Void
    let onAddMeal: (MealSlot) -> Void
    let onEditMeal: (MealSlot, PlanMeal) -> Void
    let onRemoveMeal: (MealSlot, PlanMeal) -> Void

    @Environment(\.colorScheme) private var scheme

    private static let rowGap: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Same gap between every row — a slot's second variant shouldn't
            // sit tighter than the next slot does.
            VStack(spacing: Self.rowGap) {
                ForEach(MealSlot.allCases) { slot in
                    slotContent(slot)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    isToday
                        ? WMPalette.terracotta.opacity(scheme == .dark ? 0.45 : 0.30)
                        : Color.wmCardStroke(scheme),
                    lineWidth: 1
                )
        )
        // Light mode lifts the card with a warm ambient shadow instead of a
        // darker fill: on cream a tinted surface reads as dirt, elevation reads
        // as a card. Dark mode keeps the terracotta halo on today only.
        .shadow(color: cardShadow, radius: isToday ? 22 : 14, x: 0, y: isToday ? 12 : 7)
        .shadow(color: cardContactShadow, radius: 2, x: 0, y: 1)
        .opacity(isPast ? 0.72 : 1)
    }

    // MARK: - Slots

    @ViewBuilder
    private func slotContent(_ slot: MealSlot) -> some View {
        let slotMeals = meals(slot)

        if slotMeals.isEmpty {
            row(slot: slot, meal: nil, in: [])
        } else {
            // Variants stack plainly here; who-eats-what is spelled out in
            // `PlanDaySplitsSection` below, where there is room for names
            // instead of a 22pt avatar.
            VStack(spacing: Self.rowGap) {
                ForEach(slotMeals) { meal in
                    row(slot: slot, meal: meal, in: slotMeals)
                }
            }
        }
    }

    private func row(slot: MealSlot, meal: PlanMeal?, in slotMeals: [PlanMeal]) -> some View {
        PlanMealSlotRow(
            slot: slot,
            meal: meal,
            members: members,
            badgeAudience: meal.map { badgeAudience(for: $0, in: slotMeals) } ?? [],
            showsWhoBadge: profile == .household,
            isEditable: isEditable,
            onTap: { if let meal { onTapMeal(slot, meal) } },
            onAdd: { onAddMeal(slot) },
            onEdit: { if let meal { onEditMeal(slot, meal) } },
            onAddVariant: { onAddMeal(slot) },
            onRemove: { if let meal { onRemoveMeal(slot, meal) } }
        )
    }

    private func badgeAudience(for meal: PlanMeal, in slotMeals: [PlanMeal]) -> [String] {
        slotMeals.effectiveAudience(for: meal, allMemberIds: members.map(\.id))
    }

    // MARK: - Background

    @ViewBuilder
    private var cardBackground: some View {
        if isToday {
            ZStack {
                Color.wmCardSurface(scheme)
                // Kept faint in light mode — over a white surface anything
                // stronger turns the card pink instead of warm.
                RadialGradient(
                    colors: [WMPalette.terracotta.opacity(scheme == .dark ? 0.30 : 0.09), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 320
                )
            }
        } else {
            Color.wmCardSurface(scheme)
        }
    }

    /// Ambient shadow: terracotta halo for today, neutral warm lift otherwise.
    /// Non-today cards cast nothing in dark mode — there the surface is already
    /// lighter than the canvas.
    private var cardShadow: Color {
        if isToday {
            return WMPalette.terracotta.opacity(scheme == .dark ? 0.32 : 0.16)
        }
        return scheme == .dark ? .clear : WMPalette.labelLight.opacity(0.07)
    }

    /// Tight contact shadow — light mode only, where it gives the white surface
    /// a crisp edge against the cream canvas.
    private var cardContactShadow: Color {
        scheme == .dark ? .clear : WMPalette.labelLight.opacity(0.05)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            dateTile

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(Self.longDayFormatter.string(from: date).capitalized)
                        .font(.system(size: 19, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if isToday { todayBadge }
                }

                Text(summaryText)
                    .font(.system(size: 12.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.wmMuted(scheme))
            }

            Spacer(minLength: 0)
        }
    }

    private var dateTile: some View {
        VStack(spacing: 0) {
            Text(shortDayLabel)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(isToday ? .white.opacity(0.85) : Color.wmMuted(scheme))

            Text(Self.dayNumberFormatter.string(from: date))
                .font(.system(size: 24, weight: .heavy))
                .tracking(-0.4)
                .foregroundStyle(isToday ? .white : Color.wmLabel(scheme))
        }
        .frame(width: 56, height: 64)
        .background(dateTileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isToday ? .white.opacity(0.18) : Color.wmTileStroke(scheme),
                    lineWidth: 1
                )
        )
        .shadow(
            color: isToday ? WMPalette.terracotta.opacity(0.35) : .clear,
            radius: 7, x: 0, y: 6
        )
    }

    @ViewBuilder
    private var dateTileBackground: some View {
        if isToday {
            LinearGradient(
                colors: [WMPalette.terracotta, WMPalette.terracotta.mix(black: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            scheme == .dark
                ? Color.wmLabel(scheme).opacity(0.06)
                : Color.wmInsetSurface(scheme)
        }
    }

    private var todayBadge: some View {
        Text("DZIŚ")
            .font(.system(size: 10, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(WMPalette.terracotta)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(WMPalette.terracotta.opacity(scheme == .dark ? 0.30 : 0.16))
            )
    }

    // MARK: - Derived

    /// "PON", "WT" — `pl_PL` abbreviates weekdays with a trailing period
    /// ("pon."), which the design's date tile doesn't carry.
    private var shortDayLabel: String {
        Self.shortDayFormatter.string(from: date)
            .replacingOccurrences(of: ".", with: "")
            .uppercased()
    }

    private var visibleMeals: [PlanMeal] {
        MealSlot.allCases.flatMap { meals($0) }
    }

    /// "3 posiłki · 1010 kcal", or "Brak planu" when nothing is visible in the
    /// active profile.
    private var summaryText: String {
        let planned = visibleMeals
        guard !planned.isEmpty else { return "Brak planu" }

        let kcal = planned.reduce(0) { $0 + Int($1.recipe.nutritionPerServing.kcal) }
        return "\(planned.count) \(Self.mealsPlural(planned.count)) · \(kcal) kcal"
    }

    /// Polish plural for "posiłek": 1 → posiłek, 2–4 → posiłki, else posiłków
    /// (with the 12–14 exception).
    private static func mealsPlural(_ count: Int) -> String {
        if count == 1 { return "posiłek" }
        let lastTwo = count % 100
        let last = count % 10
        if (2...4).contains(last) && !(12...14).contains(lastTwo) { return "posiłki" }
        return "posiłków"
    }

    private static let longDayFormatter = plFormatter("EEEE")
    private static let shortDayFormatter = plFormatter("EE")
    private static let dayNumberFormatter = plFormatter("d")

    private static func plFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = format
        return f
    }
}
