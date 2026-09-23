import SwiftUI

// Dwa arkusze nad arkuszem „Filtry”, oba piszą do jego kopii roboczej:
//
// - `RecipeExcludeCategorySheet` — stuknięcie w dział („Warzywa”): na górze
//   wykluczone z „Przywróć”, pod nimi reszta od najczęstszych w przepisach.
//   Źródło: `FFCategory` w `components/filtry-final.jsx`.
// - `RecipeExcludeSearchSheet` — stuknięcie w pole „Szukaj składnika”: pasek
//   „Wykluczone” u góry, wyniki od drugiej litery, po „Wyklucz” chip dochodzi
//   do paska, a nad klawiaturą stoi „Cofnij”. Źródło: `FFSearch`.
//
// Odejście od makiety: makieta ma w arkuszu kategorii strzałkę „wstecz”.
// W aplikacji arkusz się ZAMYKA, a nie cofa (`SCSheetCloseButton`), więc
// stoi krzyżyk — tak samo jak na każdym innym arkuszu nałożonym na arkusz.

// MARK: - Kategoria

struct RecipeExcludeCategorySheet: View {
    let department: IngredientDepartment
    let index: RecipeFilterIndex
    @Binding var filters: RecipeFilterOptions
    let fit: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var query = ""
    @State private var expandedGroups: Set<String> = []
    @FocusState private var isSearchFocused: Bool

    private var excludedHere: [IngredientExclusion] {
        department.excluded(in: filters.excludedIngredients)
    }

    private var foldedQuery: String {
        IngredientSearch.fold(query).trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    EditorialSheetHeader(eyebrow: "Wyklucz składniki", title: department.name) {
                        dismiss()
                    }

                    Text(verbatim: summary)
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                        .contentTransition(.numericText())
                        .padding(.top, 6)

                    RecipeFilterSearchField(
                        prompt: department.searchPrompt,
                        text: $query,
                        focus: $isSearchFocused,
                        isActive: isSearchFocused
                    )
                    .padding(.top, 16)

                    if foldedQuery.isEmpty {
                        browseList
                    } else {
                        searchList
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
                .containerRelativeFrame(.horizontal)
                .animation(.smooth(duration: 0.25), value: filters.excludedIngredients)
                .animation(.smooth(duration: 0.25), value: expandedGroups)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
            }
        }
        .sensoryFeedback(.selection, trigger: filters.excludedIngredients)
    }

    private var summary: String {
        let count = excludedHere.count
        let excluded = count == 0 ? "Nic nie wykluczone" : PolishPlural.excluded(count)
        return "\(excluded) · \(PolishPlural.ingredients(department.ingredientCount))"
    }

    // MARK: Przeglądanie

    @ViewBuilder
    private var browseList: some View {
        let excluded = excludedHere
        let available = department.entries.filter { !filters.excludedIngredients.contains($0.exclusion) }

        if !excluded.isEmpty {
            sectionLabel("Wykluczone")
            VStack(spacing: 0) {
                ForEach(Array(excluded.enumerated()), id: \.element.id) { offset, exclusion in
                    excludedRow(exclusion, isLast: offset == excluded.count - 1)
                }
            }
            .transition(.opacity)
        }

        if !available.isEmpty {
            sectionLabel("Najczęściej w przepisach")
            VStack(spacing: 0) {
                ForEach(Array(available.enumerated()), id: \.element.id) { offset, entry in
                    entryRows(entry, isLast: offset == available.count - 1)
                }
            }
        }
    }

    @ViewBuilder
    private func excludedRow(_ exclusion: IngredientExclusion, isLast: Bool) -> some View {
        let found = department.lookup(exclusion)
        if let group = found.group {
            groupRows(group, isLast: isLast)
        } else if let item = found.item {
            itemRow(item, parent: found.parent, isLast: isLast)
        }
    }

    @ViewBuilder
    private func entryRows(_ entry: IngredientEntry, isLast: Bool) -> some View {
        switch entry {
        case .item(let item):
            itemRow(item, parent: nil, isLast: isLast)
        case .group(let group):
            groupRows(group, isLast: isLast)
        }
    }

    /// Grupa i — po rozwinięciu — jej rodzaje, wcięte pod nią.
    @ViewBuilder
    private func groupRows(_ group: IngredientGroup, isLast: Bool) -> some View {
        let isExpanded = expandedGroups.contains(group.id)
        let state = filters.rowState(of: group.exclusion)

        RecipeFilterIngredientRow(
            title: group.title,
            subtitle: "\(PolishPlural.kinds(group.members.count)) · \(PolishPlural.inRecipes(group.recipeCount))",
            state: state,
            isGroup: true,
            expandTitle: state == .available ? "Rodzaje" : "Wybierz rodzaje",
            isExpanded: isExpanded,
            showsRule: !isLast || isExpanded,
            onToggle: { filters.toggle(group: group) },
            onExpand: { toggleExpanded(group) }
        )

        if isExpanded {
            ForEach(Array(group.members.enumerated()), id: \.element.id) { offset, member in
                RecipeFilterIngredientRow(
                    title: member.title,
                    subtitle: PolishPlural.inRecipes(member.recipeCount),
                    state: filters.rowState(of: member.exclusion, parent: group),
                    indent: 16,
                    showsRule: !(isLast && offset == group.members.count - 1),
                    onToggle: { filters.toggle(item: member, in: group) }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func itemRow(_ item: IngredientItem, parent: IngredientGroup?, isLast: Bool, highlight: IngredientSearch.Match? = nil) -> some View {
        RecipeFilterIngredientRow(
            title: item.title,
            subtitle: PolishPlural.inRecipes(item.recipeCount),
            state: filters.rowState(of: item.exclusion, parent: parent),
            highlight: highlight.map { (offset: $0.offset, length: $0.length) },
            showsRule: !isLast,
            onToggle: { filters.toggle(item: item, in: parent) }
        )
    }

    private func toggleExpanded(_ group: IngredientGroup) {
        if expandedGroups.contains(group.id) {
            expandedGroups.remove(group.id)
        } else {
            expandedGroups.insert(group.id)
        }
    }

    // MARK: Szukanie w dziale

    @ViewBuilder
    private var searchList: some View {
        let results = IngredientSearch.results(for: query, in: department.entries)

        sectionLabel("Wyniki")
        if results.isEmpty {
            Text("W tym dziale nie ma takiego składnika.")
                .font(.system(size: 13.5))
                .foregroundStyle(Color.scMuted(scheme))
                .padding(.horizontal, 6)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { offset, result in
                    let isLast = offset == results.count - 1
                    switch result.kind {
                    case .item(let item, let parent):
                        itemRow(item, parent: parent, isLast: isLast, highlight: result.match)
                    case .group(let group):
                        RecipeFilterIngredientRow(
                            title: group.title,
                            subtitle: "\(PolishPlural.kinds(group.members.count)) · \(PolishPlural.inRecipes(group.recipeCount))",
                            state: filters.rowState(of: group.exclusion),
                            isGroup: true,
                            highlight: result.match.map { (offset: $0.offset, length: $0.length) },
                            showsRule: !isLast,
                            onToggle: { filters.toggle(group: group) }
                        )
                    }
                }
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        EditorialSheetSectionLabel(title: title)
            .padding(.top, 22)
            .padding(.bottom, 2)
    }

    // MARK: Stopka

    private var footer: some View {
        let count = excludedHere.count
        let hidden = index.hiddenCount(by: filters.excludedIngredients, fit: fit)

        return RecipeFilterFloatingBar {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: count == 0 ? "Nic nie wykluczasz" : PolishPlural.excluded(count))
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.3)
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))
                    .contentTransition(.numericText(value: Double(count)))

                Text(verbatim: hidden == 0
                     ? "Wszystkie przepisy zostają"
                     : "łącznie ukrywa \(PolishPlural.recipes(hidden))")
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(Color.scMuted(scheme))
                    .contentTransition(.numericText(value: Double(hidden)))
                    .lineLimit(1)
            }
            .animation(.smooth(duration: 0.25), value: hidden)
            .accessibilityElement(children: .combine)
        } trailing: {
            RecipeFilterFooterButton(title: "Gotowe", trailingIcon: nil) { dismiss() }
        }
    }
}

// MARK: - Szukanie

struct RecipeExcludeSearchSheet: View {
    let index: RecipeFilterIndex
    @Binding var filters: RecipeFilterOptions
    let fit: Bool
    /// Alergeny i dieta z profilu — w pasku „Wykluczone” z kłódką.
    let profileChips: [RecipeFilterChipLine.Chip]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var query = ""
    @FocusState private var isFocused: Bool
    /// Kolejność chipów w pasku: stare po kolei, nowe na końcu — `Set` nie
    /// ma własnej, a chip dochodzący do paska nie może wskoczyć w środek.
    @State private var chipOrder: [IngredientExclusion] = []
    @State private var freshChip: IngredientExclusion?
    @State private var undo: Undo?
    @State private var showsAllChips = false
    @State private var undoTask: Task<Void, Never>?

    private struct PopularItem: Identifiable {
        let item: IngredientItem
        let parent: IngredientGroup?
        var id: String { item.id }
    }

    private struct Undo: Equatable {
        let exclusion: IngredientExclusion
        let previous: Set<IngredientExclusion>
    }

    /// Ile chipów widać, zanim pasek zwinie resztę w „+N więcej”.
    private static let collapsedChipLimit = 5

    private var foldedQuery: String {
        IngredientSearch.fold(query).trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    RecipeFilterSearchField(
                        prompt: "Szukaj składnika",
                        text: $query,
                        focus: $isFocused,
                        isActive: isFocused
                    )

                    Button("Gotowe") { dismiss() }
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(SCPalette.terracotta)
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        strip
                        results
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .containerRelativeFrame(.horizontal)
                    .animation(.smooth(duration: 0.25), value: filters.excludedIngredients)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        // Nad klawiaturą — bezpieczny obszar arkusza kończy się na niej.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            toast
        }
        .sensoryFeedback(.selection, trigger: filters.excludedIngredients)
        .task {
            chipOrder = filters.excludedIngredients.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
            // Klawiatura dopiero po wjeździe arkusza — wcześniej fokus ginie
            // razem z przejściem.
            try? await Task.sleep(for: .milliseconds(350))
            isFocused = true
        }
        .onDisappear { undoTask?.cancel() }
    }

    // MARK: Pasek „Wykluczone”

    private var orderedExclusions: [IngredientExclusion] {
        let current = filters.excludedIngredients
        let known = chipOrder.filter { current.contains($0) }
        let newcomers = current.subtracting(known)
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        return known + newcomers
    }

    private var strip: some View {
        let exclusions = orderedExclusions
        let total = exclusions.count + profileChips.count
        let hidden = index.hiddenCount(by: filters.excludedIngredients, fit: fit)
        let isCollapsed = !showsAllChips && total > Self.collapsedChipLimit + 1
        let visibleProfile = isCollapsed ? Array(profileChips.prefix(Self.collapsedChipLimit)) : profileChips
        let visibleExclusions = isCollapsed
            ? Array(exclusions.prefix(max(0, Self.collapsedChipLimit - visibleProfile.count)))
            : exclusions
        let rest = total - visibleProfile.count - visibleExclusions.count

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Wykluczone")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.25)
                    .foregroundStyle(Color.scLabel(scheme))

                if total > 0 {
                    RecipeFilterCountBadge(count: total)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }

                Spacer(minLength: 8)

                if hidden > 0 {
                    (Text("ukrywa ")
                        + Text(verbatim: "\(hidden)").fontWeight(.semibold).foregroundStyle(Color.scLabel(scheme))
                        + Text(verbatim: " \(PolishPlural.recipesNoun(hidden))"))
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }

            if total == 0 {
                Text("Nic jeszcze nie wykluczasz. Wpisz składnik, którego nie jesz.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                AllergenChipFlow(spacing: 6) {
                    ForEach(visibleProfile) { chip in
                        RecipeFilterExclusionChip(title: chip.title, locked: true)
                            .accessibilityLabel("\(chip.title), z Twojego profilu")
                    }
                    ForEach(visibleExclusions) { exclusion in
                        Button {
                            withAnimation(.smooth(duration: 0.25)) {
                                _ = filters.excludedIngredients.remove(exclusion)
                            }
                        } label: {
                            RecipeFilterExclusionChip(title: exclusion.chipTitle, fresh: exclusion == freshChip)
                        }
                        .buttonStyle(PlanPressStyle(scale: 0.94))
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                        .accessibilityLabel("Przywróć \(exclusion.chipTitle)")
                    }
                    if rest > 0 {
                        Button {
                            withAnimation(.smooth(duration: 0.25)) { showsAllChips = true }
                        } label: {
                            RecipeFilterMoreChip(label: "+\(rest) więcej")
                        }
                        .buttonStyle(PlanPressStyle(scale: 0.94))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }

    // MARK: Wyniki

    @ViewBuilder
    private var results: some View {
        if foldedQuery.count < 2 {
            let popular = Array(index.allEntries
                .flatMap { entry -> [PopularItem] in
                    switch entry {
                    case .item(let item):   return [PopularItem(item: item, parent: nil)]
                    case .group(let group): return group.members.map { PopularItem(item: $0, parent: group) }
                    }
                }
                .filter { !filters.excludedIngredients.contains($0.item.exclusion) }
                .sorted { $0.item.recipeCount > $1.item.recipeCount }
                .prefix(8))

            EditorialSheetSectionLabel(title: "Najczęściej w przepisach")
                .padding(.top, 22)
                .padding(.bottom, 2)

            VStack(spacing: 0) {
                ForEach(Array(popular.enumerated()), id: \.element.id) { offset, popularItem in
                    itemRow(popularItem.item, parent: popularItem.parent, match: nil, isLast: offset == popular.count - 1)
                }
            }
        } else {
            let found = IngredientSearch.results(for: query, in: index.allEntries)

            EditorialSheetSectionLabel(title: "Wyniki dla „\(query.trimmingCharacters(in: .whitespaces))”")
                .padding(.top, 22)
                .padding(.bottom, 2)

            if found.isEmpty {
                Text("Żaden przepis nie ma takiego składnika.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.scMuted(scheme))
                    .padding(.horizontal, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(found.enumerated()), id: \.element.id) { offset, result in
                        let isLast = offset == found.count - 1
                        switch result.kind {
                        case .item(let item, let parent):
                            itemRow(item, parent: parent, match: result.match, isLast: isLast)
                        case .group(let group):
                            RecipeFilterIngredientRow(
                                title: group.title,
                                subtitle: "\(group.department) · \(PolishPlural.kinds(group.members.count)) · \(PolishPlural.inRecipes(group.recipeCount))",
                                state: filters.rowState(of: group.exclusion),
                                isGroup: true,
                                highlight: result.match.map { (offset: $0.offset, length: $0.length) },
                                showsRule: !isLast,
                                onToggle: { toggle(group.exclusion) { filters.toggle(group: group) } }
                            )
                        }
                    }
                }
            }
        }
    }

    private func itemRow(_ item: IngredientItem, parent: IngredientGroup?, match: IngredientSearch.Match?, isLast: Bool) -> some View {
        RecipeFilterIngredientRow(
            title: item.title,
            subtitle: "\(item.department) · \(PolishPlural.inRecipes(item.recipeCount))",
            state: filters.rowState(of: item.exclusion, parent: parent),
            highlight: match.map { (offset: $0.offset, length: $0.length) },
            showsRule: !isLast,
            onToggle: { toggle(item.exclusion) { filters.toggle(item: item, in: parent) } }
        )
    }

    // MARK: Wykluczanie i „Cofnij”

    /// Przełącza i — jeśli coś właśnie wykluczono — zapala chip w pasku
    /// i pokazuje „Cofnij” nad klawiaturą.
    private func toggle(_ exclusion: IngredientExclusion, change: () -> Void) {
        let before = filters.excludedIngredients
        withAnimation(.smooth(duration: 0.25)) { change() }
        let after = filters.excludedIngredients

        guard after.contains(exclusion), !before.contains(exclusion) else {
            // Przywrócenie nie potrzebuje „Cofnij” — to jest już cofnięcie.
            withAnimation(.smooth(duration: 0.2)) { undo = nil }
            return
        }

        if !chipOrder.contains(exclusion) { chipOrder.append(exclusion) }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            freshChip = exclusion
            undo = Undo(exclusion: exclusion, previous: before)
        }

        undoTask?.cancel()
        undoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.6)) { freshChip = nil }
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.25)) { undo = nil }
        }
    }

    private func performUndo() {
        guard let undo else { return }
        undoTask?.cancel()
        withAnimation(.smooth(duration: 0.25)) {
            filters.excludedIngredients = undo.previous
            freshChip = nil
            self.undo = nil
        }
    }

    @ViewBuilder
    private var toast: some View {
        ZStack {
            if let undo {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(SCPalette.terracotta)

                    (Text("Wykluczono: ") + Text(undo.exclusion.chipTitle).fontWeight(.bold))
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(1)

                    Button(action: performUndo) {
                        Text("Cofnij")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(SCPalette.terracotta)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .scSoftCapsule()
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(PlanPressStyle(scale: 0.94))
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .frame(height: 44)
                .glassEffect(
                    .regular.tint(Color.scPageBase(scheme).opacity(0.35)),
                    in: .capsule
                )
                .background(Color.scPageBase(scheme).opacity(0.72), in: .capsule)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(undo.exclusion.id)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
