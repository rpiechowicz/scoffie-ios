import SwiftUI

// „Kto co je” i „co się zmieni” w propozycji planu (27.09.2026, Rafał: „jak
// wchodzi więcej dań, więcej osób, to robi się totalne zamieszanie i user
// gubi się w sekundę” oraz „»Zniknie z planu« jest nieczytelne — pokaż
// dokładnie, co się zmieni na co”).
//
// Klocki wspólne dla karty w rozmowie, arkusza przeglądu dań
// (`AssistantOptionsStorySheet`) i półarkusza zmian: JEDNA etykieta „dla kogo”
// (`ProposalAudience`), JEDNA pigułka z awatarami (`ProposalAudiencePill`,
// na `PlanWhoBadge` z Planu), filtr osób (`ProposalPersonFilter`) i model
// zmian (`ProposalChanges`).

// MARK: - Dla kogo

/// „Cały dom” / „Ty” / „Ania” / „Ty i Ania” / „Ania, Tomek i Ty” — z
/// `participantIds` dania (puste = cały dom). W domu jednoosobowym `nil`:
/// nie ma kogo rozróżniać, więc żadnego „dla kogo” na ekranie.
enum ProposalAudience {
    static func label(
        _ participantIds: [String],
        members: [HouseholdMemberSnapshot],
        me: String?
    ) -> String? {
        guard members.count > 1 else { return nil }
        let named = members.filter { participantIds.contains($0.id) }
        if participantIds.isEmpty || named.isEmpty || named.count == members.count {
            return "Cały dom"
        }
        // „Ty” na końcu — po polsku „Ania i Ty”, nie „Ty i Ania”.
        let ordered = named.filter { $0.id != me } + named.filter { $0.id == me }
        let names = ordered.map { $0.id == me ? "Ty" : HouseholdMemberStyle.shortName($0.displayName) }
        switch names.count {
        case 1: return names[0]
        case 2: return "\(names[0]) i \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " i " + (names.last ?? "")
        }
    }

    /// Czy danie jest dla całego domu (albo dom ma jedną osobę).
    static func isShared(_ participantIds: [String], members: [HouseholdMemberSnapshot]) -> Bool {
        let named = members.filter { participantIds.contains($0.id) }
        return participantIds.isEmpty || named.isEmpty || named.count == members.count
    }

    /// Czy osoba `person` je to danie; `nil` = wszyscy.
    static func eats(_ participantIds: [String], person: String?) -> Bool {
        guard let person else { return true }
        return participantIds.isEmpty || participantIds.contains(person)
    }
}

/// Awatary (albo domek) + imiona — „dla kogo” przy daniu. Rysuje się tylko
/// w domu z więcej niż jedną osobą.
struct ProposalAudiencePill: View {
    let participantIds: [String]
    let members: [HouseholdMemberSnapshot]
    let me: String?
    var size: CGFloat = 18
    /// Pigułka na tle (strona dania) albo sam wiersz (listy).
    var filled: Bool = true

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let label = ProposalAudience.label(participantIds, members: members, me: me) {
            HStack(spacing: 6) {
                PlanWhoBadge(participantIds: participantIds, members: members, size: size)
                Text(label)
                    .font(.system(size: filled ? 13.5 : 12.5, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(filled ? AssistantLook.ink(scheme) : AssistantLook.muted(scheme))
                    .lineLimit(1)
            }
            .padding(.leading, filled ? 5 : 0)
            .padding(.trailing, filled ? 10 : 0)
            .frame(height: filled ? 28 : nil)
            .background {
                if filled {
                    Capsule(style: .continuous).fill(AssistantLook.field(scheme))
                }
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dla: \(label)")
        }
    }
}

/// „Wszyscy · Ty · Ania · Tomek” — co je KONKRETNA osoba. Kapsuły z awatarem
/// i imieniem, zaznaczenie w kolorze osoby (`scChoiceSurface(.chip)`).
struct ProposalPersonFilter: View {
    let members: [HouseholdMemberSnapshot]
    let me: String?
    /// `nil` = wszyscy.
    @Binding var selection: String?

    @Environment(\.colorScheme) private var scheme

    /// Ty pierwszy — najczęściej pytasz, co JA jem.
    private var ordered: [HouseholdMemberSnapshot] {
        members.filter { $0.id == me } + members.filter { $0.id != me }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(id: nil, title: "Wszyscy", accent: AssistantLook.terra(scheme)) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AssistantLook.terra(scheme))
                        .frame(width: 20, height: 20)
                }
                ForEach(ordered) { member in
                    chip(
                        id: member.id,
                        title: member.id == me ? "Ty" : HouseholdMemberStyle.shortName(member.displayName),
                        accent: HouseholdMemberStyle.color(for: member)
                    ) {
                        MemberAvatar(member: member, members: members, size: 20)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func chip<Avatar: View>(
        id: String?,
        title: String,
        accent: Color,
        @ViewBuilder avatar: () -> Avatar
    ) -> some View {
        let isOn = selection == id
        return Button {
            withAnimation(.smooth(duration: 0.25)) { selection = id }
        } label: {
            HStack(spacing: 6) {
                avatar()
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(isOn ? accent : AssistantLook.ink(scheme))
                    .lineLimit(1)
            }
            .padding(.leading, 5)
            .padding(.trailing, 12)
            .frame(height: 32)
            .scChoiceSurface(Capsule(style: .continuous), isOn: isOn, accent: accent, style: .chip)
            .scTapHeight(drawn: 32)
        }
        .buttonStyle(PlanPressStyle(scale: 0.96))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Co się zmieni

/// Zmiany propozycji pora po porze: zamiana (stare → nowe), samo usunięcie
/// (z powodem od modelu) i nowe danie. Dania, które zostają (`KEPT`), nie
/// są zmianą — nie ma ich tutaj.
struct ProposalChanges {
    struct Dish: Identifiable {
        let id: String
        let title: String
        let imageURL: URL?
        let participantIds: [String]
    }

    enum Kind { case replace, remove, add }

    struct Meal: Identifiable {
        let id: String
        let slot: MealSlot?
        let mealLabel: String
        let removed: [Dish]
        let added: [Dish]
        /// Jedno słowo powodu od modelu („powtórka”, „ponad cel”).
        let reason: String?

        var kind: Kind {
            if removed.isEmpty { return .add }
            return added.isEmpty ? .remove : .replace
        }
    }

    struct Day: Identifiable {
        let id: String
        let label: String?
        let meals: [Meal]
    }

    let days: [Day]

    var replaced: Int { days.flatMap(\.meals).filter { $0.kind == .replace }.count }
    var removedOnly: Int { days.flatMap(\.meals).filter { $0.kind == .remove }.count }
    var added: Int { days.flatMap(\.meals).filter { $0.kind == .add }.count }

    /// „2 zamiany · 1 usunięcie · 3 nowe” — pod wierszem w karcie.
    var summary: String {
        var parts: [String] = []
        if replaced > 0 { parts.append("\(replaced) \(Self.word(replaced, "zamiana", "zamiany", "zamian"))") }
        if removedOnly > 0 { parts.append("\(removedOnly) \(Self.word(removedOnly, "usunięcie", "usunięcia", "usunięć"))") }
        if added > 0 { parts.append("\(added) \(Self.word(added, "nowe", "nowe", "nowych"))") }
        return parts.joined(separator: " · ")
    }

    private static func word(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        if count == 1 { return one }
        let tens = count % 100
        let units = count % 10
        return (2...4).contains(units) && !(12...14).contains(tens) ? few : many
    }

    /// Z dni propozycji (tydzień: `card.days`; dzień: jeden „dzień” z jego
    /// porami) i listy usunięć. Para usunięcie ↔ nowe danie = ta sama pora
    /// tego samego dnia. Zdjęcie usuwanego dania bierze się z katalogu.
    init(
        days: [(key: String, label: String?, slots: [PlanWeekCardSlotDTO])],
        removed: [PlanWeekCardRemovalDTO],
        image: (String?) -> URL?
    ) {
        var result: [Day] = []
        var usedRemovals = Set<Int>()
        for day in days {
            var meals: [Meal] = []
            var mealOrder: [String] = []
            var addedByMeal: [String: [Dish]] = [:]
            var labels: [String: (slot: MealSlot?, label: String)] = [:]
            for slot in day.slots where slot.isNew {
                if addedByMeal[slot.mealLabel] == nil { mealOrder.append(slot.mealLabel) }
                addedByMeal[slot.mealLabel, default: []].append(Dish(
                    id: "\(day.key)-\(slot.id)",
                    title: slot.title,
                    imageURL: slot.imageUrl.flatMap(URL.init(string:)),
                    participantIds: slot.participantIds
                ))
                labels[slot.mealLabel] = (MealSlot(backendMealType: slot.mealType), slot.mealLabel)
            }
            var removedByMeal: [String: [(Dish, String?)]] = [:]
            for (index, removal) in removed.enumerated() where !usedRemovals.contains(index) {
                guard day.label == nil || Self.sameDay(removal.dayLabel, day.label) else { continue }
                usedRemovals.insert(index)
                if addedByMeal[removal.mealLabel] == nil, removedByMeal[removal.mealLabel] == nil {
                    mealOrder.append(removal.mealLabel)
                }
                removedByMeal[removal.mealLabel, default: []].append((
                    Dish(
                        id: "\(day.key)-\(removal.id)",
                        title: removal.title,
                        imageURL: image(removal.recipeId),
                        participantIds: []
                    ),
                    removal.reason
                ))
                if labels[removal.mealLabel] == nil {
                    labels[removal.mealLabel] = (removal.mealType.flatMap(MealSlot.init(backendMealType:)), removal.mealLabel)
                }
            }
            // Porządek dnia: po porze (śniadanie → kolacja), gdy znana.
            let sortedOrder = mealOrder.enumerated().sorted { left, right in
                let a = labels[left.element]?.slot
                let b = labels[right.element]?.slot
                if let a, let b, a != b { return a < b }
                return left.offset < right.offset
            }.map { $0.element }
            for meal in sortedOrder {
                let removedHere = removedByMeal[meal] ?? []
                meals.append(Meal(
                    id: "\(day.key)-\(meal)",
                    slot: labels[meal]?.slot,
                    mealLabel: labels[meal]?.label ?? meal,
                    removed: removedHere.map { $0.0 },
                    added: addedByMeal[meal] ?? [],
                    reason: removedHere.compactMap { $0.1 }.first { !$0.isEmpty }
                ))
            }
            if !meals.isEmpty {
                result.append(Day(id: day.key, label: day.label, meals: meals))
            }
        }
        self.days = result
    }

    /// „Wtorek” z usunięcia vs „Wtorek” z dnia propozycji — bez wielkości liter.
    private static func sameDay(_ removal: String, _ day: String?) -> Bool {
        guard let day else { return true }
        return removal.compare(day, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

/// Półarkusz „Co się zmieni”: dzień → pora; zamiana to stare (szare,
/// przekreślone) nad nowym ze strzałką, usunięcie — przekreślone z powodem,
/// nowe danie — z plakietką „nowe”. Przy każdym daniu „dla kogo” (dom z kilku
/// osób). Tylko najważniejsze: bez akapitów, kolor i ikony mówią rodzaj zmiany.
struct AssistantPlanChangesSheet: View {
    let changes: ProposalChanges
    let members: [HouseholdMemberSnapshot]
    let me: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    private static let thumb: CGFloat = 40

    var body: some View {
        AssistantSheetScaffold(
            eyebrow: "Propozycja",
            title: "Co się zmieni",
            subtitle: changes.summary,
            icon: "arrow.left.arrow.right",
            compact: true,
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(changes.days.enumerated()), id: \.element.id) { order, day in
                    VStack(alignment: .leading, spacing: 8) {
                        if let label = day.label {
                            EditorialSheetSectionLabel(title: label)
                                .padding(.leading, 4)
                        }
                        dayCard(day)
                    }
                    .scReveal(appeared, order: min(order, 6))
                }
            }
            .padding(.top, 6)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(40)
        .presentationBackground(Color.scPageBase(scheme))
        .task {
            try? await Task.sleep(for: .milliseconds(60))
            appeared = true
        }
    }

    private func dayCard(_ day: ProposalChanges.Day) -> some View {
        let shape = RoundedRectangle(cornerRadius: AssistantCardMetrics.listRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(day.meals.enumerated()), id: \.element.id) { index, meal in
                if index > 0 {
                    Rectangle()
                        .fill(Color.scTileStroke(scheme))
                        .frame(height: 1)
                        .padding(.leading, 14)
                }
                mealBlock(meal)
            }
        }
        .background(shape.fill(Color.scTileBg(scheme)))
        .overlay(shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
    }

    private func mealBlock(_ meal: ProposalChanges.Meal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let slot = meal.slot {
                    Image(systemName: slot.icon)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(slot.cozyAccent)
                }
                Text((meal.slot?.title ?? meal.mealLabel).uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(meal.slot?.cozyAccent ?? AssistantLook.muted(scheme))
                Spacer(minLength: 8)
                kindTag(meal)
            }

            ForEach(meal.removed) { dish in
                dishRow(dish, removed: true)
            }
            if meal.kind == .replace {
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AssistantLook.faint(scheme))
                    .frame(width: Self.thumb)
                    .accessibilityHidden(true)
            }
            ForEach(meal.added) { dish in
                dishRow(dish, removed: false)
            }
        }
        .padding(14)
    }

    /// Rodzaj zmiany: zamiana (terakota), usunięcie z powodem (szary),
    /// nowe (szałwia).
    @ViewBuilder
    private func kindTag(_ meal: ProposalChanges.Meal) -> some View {
        switch meal.kind {
        case .replace:
            tag(meal.reason ?? "Zamiana", icon: "arrow.triangle.2.circlepath", color: AssistantLook.terra(scheme))
        case .remove:
            tag(meal.reason ?? "Usunięte", icon: "minus", color: AssistantLook.muted(scheme))
        case .add:
            tag("Nowe", icon: "plus", color: AssistantLook.sage(scheme))
        }
    }

    private func tag(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .bold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule(style: .continuous).fill(color.opacity(scheme == .dark ? 0.16 : 0.1)))
        .fixedSize()
    }

    private func dishRow(_ dish: ProposalChanges.Dish, removed: Bool) -> some View {
        HStack(spacing: 12) {
            AssistantThumbnail(url: dish.imageURL, size: Self.thumb, dimmed: removed)
                .saturation(removed ? 0 : 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(dish.title)
                    .font(.system(size: 15, weight: removed ? .regular : .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(removed ? AssistantLook.faint(scheme) : AssistantLook.ink(scheme))
                    .strikethrough(removed, color: AssistantLook.faint(scheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !removed {
                    ProposalAudiencePill(
                        participantIds: dish.participantIds,
                        members: members,
                        me: me,
                        size: 16,
                        filled: false
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(removed ? "Zniknie: \(dish.title)" : "Będzie: \(dish.title)")
    }
}
