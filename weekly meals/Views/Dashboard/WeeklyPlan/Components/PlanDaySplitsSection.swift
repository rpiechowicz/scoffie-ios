import SwiftUI

// „Każdy je inaczej" — the per-day split summary that sits under the carousel.
// Source: design canvas → `DaySplitsInline` (components/plan-a2-fix.jsx),
// section "Plan tygodnia · Etap 2".
//
// The day card above shows *what* is planned; this section answers *who eats
// what differently today*. One card per meal slot that has personal variants,
// each row carrying the person's colour on its leading edge, their avatar and
// their name spelled out — which the compact badge in the card can't do.
//
// When the day has no splits it says so instead of disappearing: „wszyscy
// jedzą to samo" is the answer to "why does every profile show the same meals",
// and a silent empty section would leave that question hanging.
struct PlanDaySplitsSection: View {
    let date: Date
    /// Sloty do przejrzenia — ta sama lista, którą rysuje karta dnia nad
    /// sekcją. Gdyby każdy komponent liczył ją sobie sam, „wszyscy jedzą to
    /// samo" mogłoby dotyczyć innego zestawu posiłków niż ten wyżej.
    let slots: [MealSlot]
    /// All meals of the day, unfiltered — the section is a household-level view.
    let meals: (MealSlot) -> [PlanMeal]
    let members: [HouseholdMemberSnapshot]
    let onTapMeal: (MealSlot, PlanMeal) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.sessionStore) private var sessionStore

    private struct SplitRow: Identifiable {
        let meal: PlanMeal
        /// Who actually eats it — a shared dish alongside personal ones covers
        /// only the people those don't name.
        let audience: [String]
        var id: String { meal.id }
    }

    private struct SplitGroup: Identifiable {
        let slot: MealSlot
        let rows: [SplitRow]
        var id: String { slot.rawValue }
    }

    /// Slots where the household eats differently. The shared dish is listed
    /// too — badged with whoever the personal dishes leave over — because
    /// „kto je inaczej" is a comparison and one side of it is often „reszta".
    private var groups: [SplitGroup] {
        let memberIds = members.map(\.id)

        return slots.compactMap { slot in
            let slotMeals = meals(slot)
            guard slotMeals.contains(where: { !$0.isShared }) else { return nil }

            let rows = slotMeals.compactMap { meal -> SplitRow? in
                let audience = slotMeals.effectiveAudience(for: meal, allMemberIds: memberIds)
                // A shared dish nobody is left for adds nothing to compare.
                if meal.isShared && audience.isEmpty { return nil }
                return SplitRow(meal: meal, audience: audience)
            }
            // One personal dish is already a difference — that person eats
            // something the rest of the household isn't having. Requiring two
            // rows made the section claim „wszyscy jedzą to samo" while the
            // card above badged the very same meal with one person's avatar.
            guard !rows.isEmpty else { return nil }
            return SplitGroup(slot: slot, rows: rows)
        }
    }

    private var hasAnyMeal: Bool {
        slots.contains { !meals($0).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader

            if groups.isEmpty {
                sameForEveryone
            } else {
                ForEach(groups) { group in
                    groupCard(group)
                }
            }
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.wmMuted(scheme))

                Text("KAŻDY JE INACZEJ")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(Color.wmMuted(scheme))
            }

            Rectangle()
                .fill(Color.wmRule(scheme))
                .frame(height: 1)
                .frame(maxWidth: .infinity)

            if !groups.isEmpty {
                Text(PolishPlural.meals(groups.count))
                    .font(.system(size: 10.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.wmFaint(scheme))
            }
        }
    }

    // MARK: - Split card

    private func groupCard(_ group: SplitGroup) -> some View {
        VStack(spacing: 0) {
            slotStrip(group)

            // A hairline above every row separates them from each other and
            // from the meal-type strip.
            ForEach(group.rows) { row in
                personRow(slot: group.slot, row: row)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.wmTileStroke(scheme))
                            .frame(height: 1)
                    }
            }
        }
        .background(
            LinearGradient(
                colors: [
                    group.slot.cozyAccent.opacity(scheme == .dark ? 0.10 : 0.08),
                    Color.wmTileBg(scheme)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
    }

    private func slotStrip(_ group: SplitGroup) -> some View {
        HStack(spacing: 8) {
            Image(systemName: group.slot.icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(group.slot.cozyAccent)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(group.slot.cozyAccent.opacity(scheme == .dark ? 0.22 : 0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(group.slot.cozyAccent.opacity(0.4), lineWidth: 1)
                )

            Text(group.slot.title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Color.wmLabel(scheme))

            if let time = sessionStore.mealSlotSchedule.time(for: group.slot) {
                Text("· \(time)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.wmMuted(scheme))
            }

            Spacer(minLength: 4)

            Text("\(group.rows.count) \(Self.variantsPlural(group.rows.count))".uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Color.wmMuted(scheme))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func personRow(slot: MealSlot, row: SplitRow) -> some View {
        let meal = row.meal
        let named = members.filter { row.audience.contains($0.id) }
        let tint = named.first.map { HouseholdMemberStyle.color(for: $0.id, in: members) }
            ?? Color.wmMuted(scheme)

        return HStack(spacing: 10) {
            if let first = named.first {
                MemberAvatar(member: first, members: members, size: 26)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.recipe.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .tracking(-0.15)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .lineLimit(1)

                Text(metaLine(named: named, meal: meal))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.wmMuted(scheme))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            thumbnail(slot: slot, recipe: meal.recipe)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        // Person's colour on the leading edge — the fastest "whose is this?"
        // signal in a stack of otherwise identical rows.
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(tint)
                .frame(width: 3)
                .padding(.vertical, 6)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTapMeal(slot, meal) }
        .accessibilityElement(children: .combine)
    }

    /// „Ania · 22 min · 279 kcal", a przy ręcznie zmienionej liczbie porcji
    /// jeszcze „· 3 porcje".
    ///
    /// Kalorie to udział jednej osoby — sekcja porównuje, co kto je, więc
    /// wartość musi być porównywalna między wierszami, a nie zależeć od tego,
    /// ile porcji akurat ugotowano dla której grupy. Porcji nie dopisujemy przy
    /// wartości domyślnej: to, że coś jest domyślne, nie jest informacją.
    private func metaLine(named: [HouseholdMemberSnapshot], meal: PlanMeal) -> String {
        // `nil` znaczy „lista domowników jeszcze nie dojechała", a nie „dom
        // jednoosobowy". Bez tego rozróżnienia zapisane trzy porcje dzieliły
        // się przez zgadywaną jedną osobę i wiersz migał potrójnymi kaloriami.
        let memberCount: Int? = sessionStore.didLoadHouseholdMembers
            ? max(1, sessionStore.householdMembers.count)
            : nil
        let kcal = Int(
            meal.nutritionPerPerson(knownHouseholdMemberCount: memberCount).kcal.rounded()
        )

        // Imiona rozdziela przecinek, a nie kropka — inaczej „Ania · Marek"
        // czytałoby się jak dwie osobne pozycje meta, a nie jak jedna lista osób.
        let who = named.map { HouseholdMemberStyle.shortName($0.displayName) }
            .joined(separator: ", ")

        var parts: [String] = who.isEmpty ? [] : [who]
        parts.append("\(meal.recipe.prepTimeMinutes) min")
        parts.append("\(kcal) kcal")
        // Liczbę porcji dopisujemy wyłącznie przy świadomym odejściu od reguły
        // auto. Brak zapisanej wartości to nie ręczny wybór, więc posiłek
        // sprzed tej zmiany nie ma się chwalić plakietką „1 porcja".
        if let count = memberCount, meal.isCustomServings(householdMemberCount: count) {
            parts.append(PolishPlural.servings(meal.effectiveServings(householdMemberCount: count)))
        }
        return parts.joined(separator: " · ")
    }

    private func thumbnail(slot: MealSlot, recipe: Recipe) -> some View {
        Group {
            if let url = recipe.imageURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        gradientThumb(slot: slot)
                    @unknown default:
                        gradientThumb(slot: slot)
                    }
                }
            } else {
                gradientThumb(slot: slot)
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func gradientThumb(slot: MealSlot) -> some View {
        ZStack {
            LinearGradient(
                colors: [slot.cozyTint, slot.cozyTint.mix(black: 0.32)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: slot.icon)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - Empty state

    private var sameForEveryone: some View {
        HStack(spacing: 12) {
            Image(systemName: hasAnyMeal ? "checkmark" : "calendar.badge.plus")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(WMPalette.sage)
                .frame(width: 36, height: 36)
                .background(Circle().fill(WMPalette.sage.opacity(scheme == .dark ? 0.22 : 0.16)))
                .overlay(Circle().stroke(WMPalette.sage.opacity(0.4), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(hasAnyMeal ? "Wszyscy jedzą to samo" : "Nic jeszcze nie zaplanowane")
                    .font(.system(size: 13.5, weight: .bold))
                    .tracking(-0.15)
                    .foregroundStyle(Color.wmLabel(scheme))

                Text(
                    hasAnyMeal
                        ? "Wspólne posiłki tego dnia — brak rozjazdów"
                        : "Dodaj posiłek i wskaż, dla kogo jest"
                )
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.wmMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    Color.wmTileStroke(scheme),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
    }

    // MARK: - Plurals

    private static func variantsPlural(_ count: Int) -> String {
        PolishPlural.form(count, one: "wariant", few: "warianty", many: "wariantów")
    }
}
