import SwiftUI

// Wykluczanie składników — dwie podstrony wpychane w stos arkusza „Filtry”
// (6.10.2026: push zamiast arkuszy na arkuszu), obie piszą od razu do filtrów
// Przepisów:
//
// - `RecipeExcludePage` — kafelek „Wyklucz składniki” w Filtrach: pole
//   szukania (wyniki od drugiej litery, pogrupowane po działach, „Cofnij”
//   nad klawiaturą), karta „Wykluczone” i działy sklepu z ich ikonami.
// - `RecipeExcludeDepartmentPage` — stuknięty dział („Warzywa”): składniki
//   jako chmura pigułek od najczęstszych w przepisach.
//
// Obie mają systemowy pasek z tytułem, „wstecz” i „Wyczyść”.
//
// Makieta (`FFSearch`, `FFCategory` w `filtry-final.jsx`) miała listę
// wierszy z przyciskiem „Wyklucz” przy każdym składniku. W dziale „Warzywa”
// to 49 wierszy po 56 pt i 49 terakotowych przycisków jeden pod drugim —
// Rafał (23.09.2026): „lista jest do zmiany, daj lepszy widok”. Pigułka
// niesie stan sama (terakota = wykluczony), dział mieści się na półtora
// ekranu, a działy mają te same ikony i barwy co alejki Zakupów.
//
// Dział ma znowu „wstecz”, jak w makiecie — jest podstroną, nie arkuszem
// nałożonym na arkusz.

// MARK: - Dział

struct RecipeExcludeDepartmentPage: View {
    let department: IngredientDepartment
    let index: RecipeFilterIndex
    @Binding var filters: RecipeFilterOptions
    let fit: Bool
    /// „Gotowe” — zamyka cały arkusz Filtrów (zmiany już działają).
    let onDone: () -> Void

    @Environment(\.colorScheme) private var scheme

    @State private var query = ""
    @State private var expandedGroups: Set<String> = []
    @FocusState private var isSearchFocused: Bool

    private var excludedHere: [IngredientExclusion] {
        department.excluded(in: filters.excludedIngredients)
    }

    /// Wszystkie klucze wykluczeń tego działu — składniki, grupy i rodzaje
    /// w grupach. „Wyczyść” zdejmuje je razem, także rodzaj wykluczony
    /// z osobna obok wykluczonej całej grupy.
    private var foldedQuery: String {
        IngredientSearch.fold(query).trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        SCSearchField(
                            prompt: department.searchPrompt,
                            text: $query,
                            focus: $isSearchFocused,
                            isActive: isSearchFocused
                        )
                        .padding(.top, 6)

                        if foldedQuery.isEmpty {
                            sectionLabel("Najczęściej w przepisach")
                            cloud
                        } else {
                            searchCloud
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .containerRelativeFrame(.horizontal)
                    .animation(.smooth(duration: 0.25), value: filters.excludedIngredients)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                // Pod systemowym paskiem — miękka krawędź, bez kreski.
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scSheetFooter { footer }
            }
        }
        .sensoryFeedback(.selection, trigger: filters.excludedIngredients)
        .navigationTitle(department.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        // „Wyczyść” zdejmuje naraz wszystko, co wykluczono w TYM dziale
        // (Rafał, 23.09.2026) — wyszarzone, gdy nie ma czego czyścić.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Wyczyść") { clearDepartment() }
                    .disabled(excludedHere.isEmpty)
                    .accessibilityLabel("Wyczyść wykluczenia w tym dziale")
            }
        }
    }

    private func clearDepartment() {
        let keys = department.exclusions
        withAnimation(.smooth(duration: 0.25)) {
            filters.excludedIngredients.subtract(keys)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        EditorialSheetSectionLabel(title: title)
            .padding(.top, 22)
            .padding(.bottom, 4)
    }

    // MARK: Chmura działu

    /// Wszystkie składniki działu w kolejności częstości. Kolejność się nie
    /// zmienia po stuknięciu — wykluczony składnik zostaje w miejscu, tylko
    /// zmienia kolor, więc pomyłkę cofa się tym samym ruchem.
    private var cloud: some View {
        RecipeExclusionFlow(spacing: 8) {
            ForEach(department.entries) { entry in
                switch entry {
                case .item(let item):
                    RecipeExclusionPill(
                        title: item.title,
                        state: filters.exclusionState(of: item.exclusion)
                    ) {
                        filters.toggle(item: item, in: nil)
                    }
                case .group(let group):
                    groupPill(group)
                    if expandedGroups.contains(group.id) {
                        kindsPanel(group)
                    }
                }
            }
        }
    }

    /// Grupa rozwija rodzaje, a nie wyklucza — „Papryka” to i czerwona,
    /// i słodka mielona, więc decyzja „całą” ma być świadoma („Wszystkie”
    /// w panelu).
    private func groupPill(_ group: IngredientGroup) -> some View {
        let isExpanded = expandedGroups.contains(group.id)

        return RecipeExclusionPill(
            title: group.title,
            state: filters.exclusionState(of: group.exclusion),
            disclosure: isExpanded ? .expanded : .collapsed,
            excludedKinds: filters.excludedKinds(of: group)
        ) {
            isSearchFocused = false
            withAnimation(.smooth(duration: 0.28)) { toggleExpanded(group) }
        }
    }

    /// Rodzaje grupy pod jej pigułką, na całą szerokość chmury.
    private func kindsPanel(_ group: IngredientGroup) -> some View {
        AllergenChipFlow(spacing: 7) {
            RecipeExclusionPill(
                title: "Wszystkie",
                state: filters.exclusionState(of: group.exclusion),
                compact: true
            ) {
                filters.toggle(group: group)
            }

            ForEach(group.members) { member in
                RecipeExclusionPill(
                    title: member.title,
                    state: filters.exclusionState(of: member.exclusion, parent: group),
                    compact: true
                ) {
                    filters.toggle(item: member, in: group)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.scChipBg(scheme))
        )
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        .recipeExclusionFullWidth()
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
    private var searchCloud: some View {
        let results = IngredientSearch.results(for: query, in: department.entries)

        sectionLabel("Wyniki")
        if results.isEmpty {
            Text("W tym dziale nie ma takiego składnika.")
                .font(.sc(size: 13.5))
                .foregroundStyle(Color.scMuted(scheme))
                .padding(.horizontal, 6)
        } else {
            RecipeExclusionFlow(spacing: 8) {
                ForEach(results) { result in
                    RecipeExclusionResultPill(result: result, filters: filters) {
                        switch result.kind {
                        case .item(let item, let parent):
                            filters.toggle(item: item, in: parent)
                        case .group(let group):
                            filters.toggle(group: group)
                        }
                    }
                }
            }
        }
    }

    // MARK: Stopka

    private var footer: some View {
        let count = excludedHere.count
        let hidden = index.hiddenCount(by: filters.excludedIngredients, fit: fit)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: count == 0 ? "Nic nie wykluczasz" : PolishPlural.excluded(count))
                    .font(.sc(size: 15, weight: .bold))
                    .tracking(-0.3)
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))
                    .contentTransition(.numericText(value: Double(count)))

                Text(verbatim: hidden == 0
                     ? "Wszystkie przepisy zostają"
                     : "łącznie ukrywa \(PolishPlural.recipes(hidden))")
                    .font(.sc(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(Color.scMuted(scheme))
                    .contentTransition(.numericText(value: Double(hidden)))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.25), value: hidden)
            .accessibilityElement(children: .combine)

            RecipeFilterFooterButton(title: "Gotowe", trailingIcon: nil, action: onDone)
        }
        .padding(.leading, 4)
    }
}

// MARK: - Wykluczanie

/// Podstrona „Wyklucz składniki” — wpychana kafelkiem z arkusza „Filtry”.
///
/// Od góry: pole szukania, karta „Wykluczone” (chipy, stuknięcie przywraca)
/// i działy sklepu. Od drugiej litery w polu karta i działy ustępują wynikom —
/// pigułkom pogrupowanym po działach; szukanie jest tutaj, w miejscu, a nie
/// na kolejnej stronie. Wykluczenie z wyników potwierdza „Cofnij” nad
/// klawiaturą (albo dołem ekranu); nowy chip czeka w karcie podświetlony
/// jeszcze przez chwilę po wyjściu z szukania. Dział wpycha
/// `RecipeExcludeDepartmentPage`.
struct RecipeExcludePage: View {
    let index: RecipeFilterIndex
    @Binding var filters: RecipeFilterOptions
    let fit: Bool
    /// Alergeny i dieta z profilu — w karcie „Wykluczone” z kłódką.
    let profileChips: [RecipeFilterChipLine.Chip]
    /// „Gotowe” na stronie działu — zamyka cały arkusz Filtrów.
    let onDone: () -> Void

    @Environment(\.colorScheme) private var scheme

    @State private var query = ""
    @FocusState private var isFocused: Bool
    @State private var openDepartment: IngredientDepartment?
    /// Kolejność chipów w karcie: stare po kolei, nowe na końcu — `Set` nie
    /// ma własnej, a chip dochodzący do karty nie może wskoczyć w środek.
    @State private var chipOrder: [IngredientExclusion] = []
    @State private var freshChip: IngredientExclusion?
    @State private var undo: Undo?
    @State private var showsAllChips = false
    @State private var undoTask: Task<Void, Never>?

    private struct Undo: Equatable {
        let exclusion: IngredientExclusion
        let previous: Set<IngredientExclusion>
    }

    /// Ile chipów widać, zanim karta zwinie resztę w „+N więcej”.
    private static let collapsedChipLimit = 5

    private var foldedQuery: String {
        IngredientSearch.fold(query).trimmingCharacters(in: .whitespaces)
    }

    private var isSearching: Bool { foldedQuery.count >= 2 }

    /// Karta „Wykluczone” stoi tylko wtedy, gdy jest co w niej pokazać —
    /// pusta mówiła tylko to, co mówi już pole szukania.
    private var showsStrip: Bool {
        !filters.excludedIngredients.isEmpty || !profileChips.isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        SCSearchField(
                            prompt: "Szukaj składnika, np. papryka",
                            text: $query,
                            focus: $isFocused,
                            isActive: isFocused
                        )
                        .padding(.top, 6)

                        if isSearching {
                            results
                                .transition(.opacity)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                if showsStrip {
                                    strip
                                        .padding(.top, 14)
                                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                                }
                                departments
                            }
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .containerRelativeFrame(.horizontal)
                    .animation(.smooth(duration: 0.25), value: filters.excludedIngredients)
                    .animation(.smooth(duration: 0.2), value: isSearching)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                // Pod systemowym paskiem — miękka krawędź, bez kreski.
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
        }
        // Nad klawiaturą — bezpieczny obszar kończy się na niej.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            toast
        }
        .sensoryFeedback(.selection, trigger: filters.excludedIngredients)
        .task {
            chipOrder = filters.excludedIngredients.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        }
        // Także przy wejściu w dział (push) — „Cofnij” i podświetlenie mówią
        // o ostatnim ruchu na TEJ stronie i nie mogą czekać na powrót.
        .onDisappear {
            undoTask?.cancel()
            undo = nil
            freshChip = nil
        }
        .navigationTitle("Wyklucz składniki")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        // „Wyczyść” zdejmuje wszystkie wykluczenia naraz (profil z kłódką
        // zostaje, bo nie jest wykluczeniem z tej strony).
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Wyczyść") { clearAll() }
                    .disabled(filters.excludedIngredients.isEmpty)
                    .accessibilityLabel("Wyczyść wykluczenia")
            }
        }
        .navigationDestination(item: $openDepartment) { department in
            RecipeExcludeDepartmentPage(
                department: department,
                index: index,
                filters: $filters,
                fit: fit,
                onDone: onDone
            )
        }
    }

    // MARK: Działy

    private var departments: some View {
        let list = index.departments

        return VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Działy")
                .padding(.top, 22)
                .padding(.bottom, 4)

            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { offset, department in
                    departmentRow(department, showsRule: offset > 0)
                }

                if list.isEmpty {
                    Text("Przepisy nie mają jeszcze listy składników.")
                        .font(.sc(size: 13))
                        .foregroundStyle(Color.scMuted(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.scTileStroke(scheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    /// Dział: ikona i barwa alejki z Zakupów, nazwa, pod nią liczba składników
    /// albo — gdy coś tu wykluczono — ich nazwy w terakocie.
    private func departmentRow(_ department: IngredientDepartment, showsRule: Bool) -> some View {
        let excluded = department.excluded(in: filters.excludedIngredients)
        let subtitle = excluded.isEmpty
            ? PolishPlural.ingredients(department.ingredientCount)
            : excluded.map(\.chipTitle).joined(separator: ", ")

        return Button {
            isFocused = false
            openDepartment = department
        } label: {
            HStack(spacing: 12) {
                RecipeExclusionDepartmentIcon(department: department.name)

                VStack(alignment: .leading, spacing: 2) {
                    Text(department.name)
                        .font(.sc(size: 15.5, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.sc(size: 12.5, weight: excluded.isEmpty ? .regular : .medium))
                        .foregroundStyle(excluded.isEmpty ? Color.scMuted(scheme) : SCPalette.terracotta)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !excluded.isEmpty {
                    RecipeFilterCountBadge(count: excluded.count)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }

                Image(systemName: "chevron.right")
                    .font(.sc(size: 12, weight: .bold))
                    .foregroundStyle(Color.scFaint(scheme))
            }
            .padding(.vertical, 11)
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .overlay(alignment: .top) {
            if showsRule {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    .padding(.leading, 12 + 34 + 12)
            }
        }
        .animation(.smooth(duration: 0.22), value: excluded)
        .accessibilityLabel(department.name)
        .accessibilityValue(excluded.isEmpty
            ? PolishPlural.ingredients(department.ingredientCount)
            : "wykluczone: " + excluded.map(\.chipTitle).joined(separator: ", "))
    }

    // MARK: Karta „Wykluczone”

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
                    .font(.sc(size: 14, weight: .semibold))
                    .tracking(-0.25)
                    .foregroundStyle(Color.scLabel(scheme))

                RecipeFilterCountBadge(count: total)

                Spacer(minLength: 8)

                if hidden > 0 {
                    (Text("ukrywa ")
                        + Text(verbatim: "\(hidden)").fontWeight(.semibold).foregroundStyle(Color.scLabel(scheme))
                        + Text(verbatim: " \(PolishPlural.recipesNoun(hidden))"))
                        .font(.sc(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }

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

    private struct ResultSection: Identifiable {
        let department: String
        var results: [IngredientSearchResult]

        var id: String { department }
    }

    /// Trafienia pogrupowane po działach: dział z najlepszym trafieniem
    /// pierwszy, w dziale kolejność trafień. „Papryka” w Warzywach i w
    /// Przyprawach to dla kogoś, kto nie je świeżej papryki, dwie różne
    /// rzeczy — nagłówek działu mówi, która jest która.
    private static func sections(of results: [IngredientSearchResult]) -> [ResultSection] {
        var sections: [ResultSection] = []
        for result in results {
            let department: String
            switch result.kind {
            case .item(let item, _):
                department = item.department
            case .group(let group):
                department = group.department
            }
            if let position = sections.firstIndex(where: { $0.department == department }) {
                sections[position].results.append(result)
            } else {
                sections.append(ResultSection(department: department, results: [result]))
            }
        }
        return sections
    }

    @ViewBuilder
    private var results: some View {
        let sections = Self.sections(of: IngredientSearch.results(for: query, in: index.allEntries))

        if sections.isEmpty {
            Text("Żaden przepis nie ma takiego składnika.")
                .font(.sc(size: 13.5))
                .foregroundStyle(Color.scMuted(scheme))
                .padding(.horizontal, 6)
                .padding(.top, 22)
        } else {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    RecipeExclusionDepartmentLabel(department: section.department)

                    RecipeExclusionFlow(spacing: 8) {
                        ForEach(section.results) { result in
                            RecipeExclusionResultPill(result: result, filters: filters) {
                                switch result.kind {
                                case .item(let item, let parent):
                                    toggle(item.exclusion) { filters.toggle(item: item, in: parent) }
                                case .group(let group):
                                    toggle(group.exclusion) { filters.toggle(group: group) }
                                }
                            }
                        }
                    }
                }
                .padding(.top, 20)
            }
        }
    }

    // MARK: Wykluczanie i „Cofnij”

    /// Przełącza i — jeśli coś właśnie wykluczono — zapala chip w karcie
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

    /// Wszystko naraz — razem z „Cofnij” i podświetleniem, które mówiłyby
    /// o wykluczeniu, którego już nie ma.
    private func clearAll() {
        undoTask?.cancel()
        withAnimation(.smooth(duration: 0.25)) {
            filters.excludedIngredients = []
            freshChip = nil
            undo = nil
            showsAllChips = false
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
                        .font(.sc(size: 12, weight: .heavy))
                        .foregroundStyle(SCPalette.terracotta)

                    (Text("Wykluczono: ") + Text(undo.exclusion.chipTitle).fontWeight(.bold))
                        .font(.sc(size: 13.5))
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(1)

                    Button(action: performUndo) {
                        Text("Cofnij")
                            .font(.sc(size: 13.5, weight: .semibold))
                            .foregroundStyle(SCPalette.terracotta)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            // Stoi NA szklanym toaście — zwykły tint, nie
                            // drugie szkło na pierwszym.
                            .background(Capsule(style: .continuous).fill(SCPalette.terracotta.opacity(0.14)))
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(PlanPressStyle(scale: 0.94))
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .frame(height: 44)
                // Pływa nad chmurą pigułek — czyste szkło warstwy nawigacji,
                // jak dolne menu (`scChromeGlass`), bez matowej warstwy.
                .scChromeGlass(in: .capsule)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(undo.exclusion.id)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Trafienie szukania

/// Trafienie szukania jako pigułka: składnik albo cała grupa
/// („Papryka · wszystkie”). Co zrobić po stuknięciu, decyduje strona —
/// „Wyklucz składniki” dokłada do tego „Cofnij”.
struct RecipeExclusionResultPill: View {
    let result: IngredientSearchResult
    let filters: RecipeFilterOptions
    let onToggle: () -> Void

    private var highlight: (offset: Int, length: Int)? {
        result.match.map { (offset: $0.offset, length: $0.length) }
    }

    var body: some View {
        switch result.kind {
        case .item(let item, let parent):
            RecipeExclusionPill(
                title: item.title,
                state: filters.exclusionState(of: item.exclusion, parent: parent),
                highlight: highlight,
                action: onToggle
            )
        case .group(let group):
            RecipeExclusionPill(
                title: group.exclusion.chipTitle,
                state: filters.exclusionState(of: group.exclusion),
                highlight: highlight,
                action: onToggle
            )
        }
    }
}
