import SwiftUI

// One meal variant inside a Plan v2 day card.
//
// Filled: 64pt full-height thumbnail on the left (recipe photo, or the design's
// tinted gradient + diagonal hatch when the recipe has no image), then the
// eyebrow (ŚNIADANIE · 08:00), title, and a `15 min · 380 kcal` meta line with
// the "who eats this" badge pinned to its trailing edge.
// Empty: same silhouette but dashed, with a `+ Dodaj` affordance on the right.
struct PlanMealSlotRow: View {
    let slot: MealSlot
    /// `nil` renders the dashed empty row.
    let meal: PlanMeal?
    let members: [HouseholdMemberSnapshot]
    /// Who the badge should name. Usually `meal.participantIds`, but a shared
    /// meal in a slot that also holds personal dishes is narrowed to the people
    /// those dishes don't cover — see `PlanDayCard.badgeAudience`.
    var badgeAudience: [String] = []
    /// Hidden when a single person's filter is active — the context is already
    /// obvious, and the design drops the badge in that mode.
    var showsWhoBadge: Bool = true
    /// Past days are read-only — `+ Dodaj` and the context menu are suppressed.
    let isEditable: Bool
    let onTap: () -> Void
    let onAdd: () -> Void
    let onEdit: () -> Void
    let onAddVariant: () -> Void
    let onRemove: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.sessionStore) private var sessionStore

    // Both states share one fixed height so a day card reads as an even
    // stack whether its slots are filled or empty. `minHeight` used to let the
    // empty row — whose icon well is greedy — grow well past the filled one.
    //
    // 72pt zamiast 88: przy komplecie sześciu slotów karta dnia z 88-punktowymi
    // wierszami nie mieściła się na ekranie iPhone'a i dzień trzeba było
    // doprzewijać, żeby zobaczyć kolację. Wiersz nadal utrzymuje trzy linie
    // tekstu obok miniatury — schodzi tylko powietrze.
    private static let rowHeight: CGFloat = 72
    private static let thumbWidth: CGFloat = 64

    var body: some View {
        if let meal {
            filled(meal)
        } else {
            empty
        }
    }

    // MARK: - Filled

    private func filled(_ meal: PlanMeal) -> some View {
        let recipe = meal.recipe

        return HStack(spacing: 0) {
            thumbnail(recipe)
                .frame(width: Self.thumbWidth)
                .frame(maxHeight: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 3) {
                eyebrow(labelColor: slot.cozyAccent, timeColor: Color.wmMuted(scheme))

                Text(recipe.name)
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(recipe.prepTimeMinutes) min · \(Int(recipe.nutritionPerServing.kcal)) kcal")
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.wmMuted(scheme))

                    Spacer(minLength: 0)

                    if showsWhoBadge {
                        PlanWhoBadge(
                            participantIds: badgeAudience,
                            members: members,
                            size: 20
                        )
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: Self.rowHeight)
        .background(Color.wmInsetSurface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { onTap() }
        .contextMenu {
            if isEditable {
                Button { onEdit() } label: {
                    Label("Zmień przepis lub osoby", systemImage: "person.2.badge.gearshape")
                }
                Button { onAddVariant() } label: {
                    Label("Dodaj drugi wariant", systemImage: "plus")
                }
                Button(role: .destructive) { onRemove() } label: {
                    Label("Usuń z dnia", systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: meal))
    }

    private func accessibilityLabel(for meal: PlanMeal) -> String {
        let recipe = meal.recipe
        let base = "\(slot.title): \(recipe.name), \(recipe.prepTimeMinutes) minut, \(Int(recipe.nutritionPerServing.kcal)) kalorii"
        guard showsWhoBadge else { return base }

        if badgeAudience.isEmpty { return base + ", wspólne" }

        let names = members
            .filter { badgeAudience.contains($0.id) }
            .map { HouseholdMemberStyle.shortName($0.displayName) }
        guard !names.isEmpty else { return base }
        return base + ", dla: " + names.joined(separator: ", ")
    }

    private func thumbnail(_ recipe: Recipe) -> some View {
        Group {
            if let url = recipe.imageURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        gradientThumb
                    @unknown default:
                        gradientThumb
                    }
                }
            } else {
                gradientThumb
            }
        }
    }

    /// Design fallback — `linear-gradient(135deg, tint → tint mix #000 32%)`
    /// with the 45° hatch and the slot glyph centred.
    private var gradientThumb: some View {
        ZStack {
            LinearGradient(
                colors: [slot.cozyTint, slot.cozyTint.mix(black: 0.32)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            PlanDiagonalHatch(color: .white.opacity(0.07))

            Image(systemName: slot.icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - Empty

    private var empty: some View {
        HStack(spacing: 0) {
            Image(systemName: slot.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(slot.cozyAccent)
                .frame(width: Self.thumbWidth)
                .frame(maxHeight: .infinity)
                .background(slot.cozyAccent.opacity(scheme == .dark ? 0.10 : 0.14))
                .overlay(alignment: .trailing) { dashedDivider }

            VStack(alignment: .leading, spacing: 2) {
                eyebrow(labelColor: Color.wmMuted(scheme), timeColor: Color.wmFaint(scheme))

                Text("Pusty slot")
                    .font(.system(size: 13.5, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(Color.wmFaint(scheme))
                    .padding(.top, 1)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isEditable {
                Text("+ Dodaj")
                    .font(.system(size: 12.5, weight: .bold))
                    .tracking(-0.1)
                    .foregroundStyle(WMPalette.terracotta)
                    .padding(.horizontal, 12)
                    .fixedSize()
            }
        }
        .frame(height: Self.rowHeight)
        .background(emptyRowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    Color.wmTileStroke(scheme),
                    style: StrokeStyle(lineWidth: 1.4, dash: [5, 4])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { if isEditable { onAdd() } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isEditable
                ? "\(slot.title): pusty slot. Stuknij, aby dodać przepis."
                : "\(slot.title): pusty slot, dzień nieedytowalny"
        )
    }

    /// Empty slots sit a shade lighter than filled rows, so the stack still
    /// reads „czegoś tu brakuje" instead of looking like three equal wells.
    /// Dark mode keeps them fully transparent, as the design has them.
    private var emptyRowBackground: Color {
        scheme == .dark ? .clear : Color.wmInsetSurface(scheme).opacity(0.5)
    }

    /// Vertical dashed rule separating the icon well from the text — the design
    /// carries the empty row's dashed outline through the divider too.
    private var dashedDivider: some View {
        let stroke = Color.wmTileStroke(scheme)
        return Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: size.width / 2, y: 0))
            path.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            context.stroke(
                path,
                with: .color(stroke),
                style: StrokeStyle(lineWidth: 1.4, dash: [5, 4])
            )
        }
        .frame(width: 1.4)
        .allowsHitTesting(false)
    }

    // MARK: - Shared

    private func eyebrow(labelColor: Color, timeColor: Color) -> some View {
        HStack(spacing: 8) {
            Text(slot.title.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(labelColor)

            // Slot bez ustawionej pory (domyślnie przekąska) gubi też kropkę,
            // żeby nie zostawić w wierszu wiszącego separatora bez treści.
            if let time = sessionStore.mealSlotSchedule.time(for: slot) {
                Circle()
                    .fill(Color.wmFaint(scheme))
                    .frame(width: 3, height: 3)

                Text(time)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.1)
                    .foregroundStyle(timeColor)
            }
        }
    }
}

// MARK: - 45° hatch

/// `repeating-linear-gradient(45deg, rgba(255,255,255,0.07) 0 2.5px, transparent 2.5px 11px)`
/// from the design tokens — the texture behind image-less meal thumbnails.
struct PlanDiagonalHatch: View {
    let color: Color
    var lineWidth: CGFloat = 2.5
    var spacing: CGFloat = 11

    var body: some View {
        Canvas { context, size in
            let diagonal = size.width + size.height
            var x: CGFloat = -size.height
            while x < diagonal {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(color), lineWidth: lineWidth)
                x += spacing
            }
        }
        .allowsHitTesting(false)
    }
}
