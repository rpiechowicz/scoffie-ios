import SwiftUI

struct WeeklyPlanPoolView: View {
    @Environment(\.weeklyMealStore) private var mealStore
    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.shoppingListStore) private var shoppingListStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var draft = MealPlanViewModel()
    @State private var activePickerSlot: MealSlot?
    @State private var showDeleteAlert = false
    @State private var pastDayMessage: String?
    @State private var didLoadDraft = false
    @State private var saveTask: Task<Void, Never>?
    @State private var showAssigner = false
    @State private var activeSlot: MealSlot = .breakfast

    private static let weekRangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "d MMM"
        return f
    }()

    private var weekRangeText: String {
        guard let first = datesViewModel.dates.first,
              let last = datesViewModel.dates.last else {
            return "Bieżący tydzień"
        }
        return "\(Self.weekRangeFormatter.string(from: first)) – \(Self.weekRangeFormatter.string(from: last))"
    }

    private var totalCount: Int { draft.totalCount }

    /// Dni tygodnia, do których wciąż można przypisać posiłek (dziś + przyszłość).
    private var editableDaysCount: Int {
        datesViewModel.dates.filter { datesViewModel.isEditable($0) }.count
    }

    /// Ile posiłków danego slotu jest już przypisanych do dni z przeszłości
    /// (zamrożone — liczą się do planu, ale nie można ich przenieść).
    private func lockedAssignments(for slot: MealSlot) -> Int {
        datesViewModel.dates
            .filter { !datesViewModel.isEditable($0) }
            .reduce(0) { acc, date in
                acc + (mealStore.recipe(for: date, slot: slot) != nil ? 1 : 0)
            }
    }

    /// Maksymalna liczba pozycji planu dla danego slotu = zamrożone w przeszłości + edytowalne dni.
    /// Zabezpiecza przed planowaniem większej liczby posiłków niż da się przypisać.
    private func maxPerSlot(_ slot: MealSlot) -> Int {
        lockedAssignments(for: slot) + editableDaysCount
    }

    private var maxTotal: Int {
        MealSlot.allCases.reduce(0) { $0 + maxPerSlot($1) }
    }

    private enum PlanStatus {
        case empty, draft, complete
        var color: Color {
            switch self {
            case .empty: return .gray
            case .draft: return .orange
            case .complete: return .green
            }
        }
    }

    private var status: PlanStatus {
        if totalCount == 0 { return .empty }
        if totalCount >= maxTotal { return .complete }
        return .draft
    }

    private var isDirty: Bool {
        !sameAsSaved(draft, mealStore.savedPlan)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    DashboardSheetBackground(theme: .plan)
                        .ignoresSafeArea()

                    ScrollView {
                        VStack(spacing: 14) {
                            heroHeader

                            slotPills

                            slotContent(cardWidth: cardWidth(for: proxy.size.width))
                                .id(activeSlot)
                                .transition(.opacity)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 6)
                        .padding(.bottom, 28)
                        .animation(.easeInOut(duration: 0.22), value: activeSlot)
                    }
                }
            }
            .navigationTitle("Plan tygodnia")
            .toolbar {
                if totalCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showAssigner = true
                        } label: {
                            Image(systemName: "calendar.badge.plus")
                                .font(.body.weight(.semibold))
                        }
                        .accessibilityLabel("Przypisz do dni")
                    }
                }
                if mealStore.hasSavedPlan {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                showDeleteAlert = true
                            } label: {
                                Label("Usuń plan", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.body.weight(.semibold))
                        }
                    }
                }
            }
            .task(id: datesViewModel.weekStartISO) {
                await mealStore.loadSavedPlanFromBackend(weekStart: datesViewModel.weekStartISO)
                await mealStore.loadWeekPlanFromBackend(
                    weekStart: datesViewModel.weekStartISO,
                    dates: datesViewModel.dates
                )
                if !didLoadDraft {
                    draft.loadFromSaved(mealStore.savedPlan)
                    didLoadDraft = true
                }
                let urls = MealSlot.allCases
                    .flatMap { draft.recipes(for: $0) }
                    .compactMap(\.imageURL)
                ImagePrefetcher.prefetch(urls)
            }
            .onChange(of: planSignature(mealStore.savedPlan)) { _, _ in
                // Gdy nie ma lokalnego edytowania (saveTask == nil), zawsze
                // synchronizuj draft z backendem — łapie zmiany zrobione przez
                // innego użytkownika w gospodarstwie (realtime / foreground refresh).
                if saveTask == nil {
                    draft.loadFromSaved(mealStore.savedPlan)
                }
            }
            .sheet(isPresented: $showAssigner) {
                DayAssignerSheet(
                    weekDates: datesViewModel.dates,
                    weekStartISO: datesViewModel.weekStartISO
                )
                .dashboardLiquidSheet()
            }
            .sheet(item: $activePickerSlot) { slot in
                RecipePickerSheet(
                    slot: slot,
                    draft: draft,
                    slotMax: maxPerSlot(slot),
                    pastDayCountForRecipe: { recipe in
                        pastDayAssignments(for: recipe, slot: slot)
                    },
                    onPastDayBlocked: { message in
                        pastDayMessage = message
                    }
                )
                .dashboardLiquidSheet()
            }
            .onChange(of: activePickerSlot) { oldValue, newValue in
                if oldValue != nil && newValue == nil {
                    scheduleSave()
                }
            }
            .alert("Usuń plan", isPresented: $showDeleteAlert) {
                Button("Usuń", role: .destructive) {
                    Task { await deletePlan() }
                }
                Button("Anuluj", role: .cancel) { }
            } message: {
                Text("Plan tygodnia zostanie usunięty razem z przypisanymi posiłkami w kalendarzu.")
            }
            .alert(
                "Nie można usunąć",
                isPresented: Binding(
                    get: { pastDayMessage != nil },
                    set: { if !$0 { pastDayMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(pastDayMessage ?? "")
            }
        }
    }

    // MARK: - Hero header

    private var heroHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TYDZIEŃ")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)

                Text(weekRangeText)
                    .font(.title3.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(statusCaption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.color)
            }

            Spacer(minLength: 10)

            progressRing
        }
        .padding(16)
        .dashboardLiquidCard(cornerRadius: 22, strokeOpacity: 0.18)
    }

    private var statusCaption: String {
        switch status {
        case .empty: return "Zacznij planować tydzień"
        case .draft: return "W trakcie planowania"
        case .complete: return "Plan kompletny"
        }
    }

    private var progressRing: some View {
        let total = maxTotal
        let progress = total > 0 ? CGFloat(totalCount) / CGFloat(total) : 0
        return ZStack {
            Circle()
                .stroke(status.color.opacity(colorScheme == .dark ? 0.22 : 0.16), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(status.color.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.25), value: progress)
            VStack(spacing: 0) {
                Text("\(totalCount)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("/ \(total)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 64)
    }

    // MARK: - Slot pills (selector + summary)

    private var slotPills: some View {
        HStack(spacing: 8) {
            ForEach(MealSlot.allCases) { slot in
                slotPill(slot)
            }
        }
    }

    private func slotPill(_ slot: MealSlot) -> some View {
        let count = draft.count(for: slot)
        let maxPerSlot = maxPerSlot(slot)
        let isActive = activeSlot == slot
        let isFull = count >= maxPerSlot

        return Button {
            withAnimation(.easeInOut(duration: 0.22)) { activeSlot = slot }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: slot.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(slot.accentColor)
                    Text(slot.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isActive ? .primary : .secondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(count)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("/\(maxPerSlot)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if isFull {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.green.opacity(0.85))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isActive
                            ? DashboardPalette.tintFill(slot.accentColor, scheme: colorScheme, dark: 0.22, light: 0.16)
                            : DashboardPalette.surface(colorScheme, level: .secondary)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isActive
                            ? slot.accentColor.opacity(colorScheme == .dark ? 0.55 : 0.4)
                            : DashboardPalette.neutralBorder(colorScheme, opacity: 0.14),
                        lineWidth: isActive ? 1.6 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Slot content

    private func slotContent(cardWidth: CGFloat) -> some View {
        let slot = activeSlot
        let recipes = draft.uniqueRecipes(for: slot)
        let count = draft.count(for: slot)
        let slotMax = maxPerSlot(slot)

        return VStack(alignment: .leading, spacing: 12) {
            slotHeaderRow(slot: slot, count: count, max: slotMax)

            if recipes.isEmpty {
                emptySlotState(slot: slot)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(recipes) { recipe in
                        planGridCard(recipe: recipe, slot: slot, width: cardWidth)
                    }
                }
            }
        }
    }

    private func cardWidth(for totalWidth: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = 28
        let spacing: CGFloat = 10
        return max(140, floor((totalWidth - horizontalPadding - spacing) / 2))
    }

    private func slotHeaderRow(slot: MealSlot, count: Int, max: Int) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.title)
                    .font(.title3.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)

                Text(count == 0 ? "Brak pozycji" : "\(count) z \(max) wybranych")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            addButton(slot: slot, atLimit: count >= max)
        }
        .padding(.top, 4)
    }

    private func addButton(slot: MealSlot, atLimit: Bool) -> some View {
        Button {
            activePickerSlot = slot
        } label: {
            HStack(spacing: 6) {
                Image(systemName: atLimit ? "square.and.pencil" : "plus")
                    .font(.system(size: 13, weight: .bold))
                Text(atLimit ? "Zmień" : "Dodaj")
                    .font(.footnote.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                LinearGradient(
                    colors: [
                        slot.accentColor.opacity(colorScheme == .dark ? 0.95 : 0.88),
                        slot.secondaryAccentColor.opacity(colorScheme == .dark ? 0.82 : 0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.22), lineWidth: 1)
            )
            .shadow(color: slot.accentColor.opacity(colorScheme == .dark ? 0.3 : 0.2), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(atLimit ? "Zmień wybór: \(slot.title.lowercased())" : "Dodaj \(slot.title.lowercased())")
    }

    // MARK: - Grid card

    private func planGridCard(recipe: Recipe, slot: MealSlot, width: CGFloat) -> some View {
        let count = draft.recipeCount(recipe)
        return Menu {
            Button {
                incrementRecipe(recipe, slot: slot)
            } label: {
                Label("Dodaj porcję", systemImage: "plus")
            }
            Button {
                decrementRecipe(recipe, slot: slot)
            } label: {
                Label("Odejmij porcję", systemImage: "minus")
            }
            Divider()
            Button(role: .destructive) {
                removeRecipe(recipe, slot: slot)
            } label: {
                Label("Usuń z planu", systemImage: "trash")
            }
        } label: {
            ZStack(alignment: .topLeading) {
                RecipeCarouselCard(
                    recipe: recipe,
                    width: width,
                    selectionCount: 0,
                    showsHeart: false
                )

                countBadge(slot: slot, count: count)
                    .padding(10)
            }
        }
        .buttonStyle(.plain)
    }

    private func countBadge(slot: MealSlot, count: Int) -> some View {
        HStack(spacing: 4) {
            Text("×\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            slot.accentColor.opacity(colorScheme == .dark ? 0.95 : 0.88),
                            slot.secondaryAccentColor.opacity(colorScheme == .dark ? 0.82 : 0.74)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 4, x: 0, y: 2)
    }

    // MARK: - Empty state

    private func emptySlotState(slot: MealSlot) -> some View {
        Button {
            activePickerSlot = slot
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(DashboardPalette.tintFill(slot.accentColor, scheme: colorScheme, dark: 0.22, light: 0.16))
                        .frame(width: 68, height: 68)
                    Image(systemName: slot.icon)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(slot.accentColor)
                }

                VStack(spacing: 3) {
                    Text("Brak \(slot.title.lowercased())")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("Stuknij, żeby wybrać pierwszy przepis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(DashboardPalette.surface(colorScheme, level: .secondary))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        slot.accentColor.opacity(colorScheme == .dark ? 0.32 : 0.22),
                        style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func incrementRecipe(_ recipe: Recipe, slot: MealSlot) {
        guard draft.count(for: slot) < maxPerSlot(slot) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            draft.incrementRecipe(recipe)
        }
        scheduleSave()
    }

    private func decrementRecipe(_ recipe: Recipe, slot: MealSlot) {
        let currentCount = draft.recipeCount(recipe)
        let pastUsage = pastDayAssignments(for: recipe, slot: slot)
        if currentCount - 1 < pastUsage {
            pastDayMessage = "Ten przepis jest przypisany do dnia z przeszłości (\(pastUsage) raz(y)). Najpierw usuń go z tych dni w Kalendarzu."
            return
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            draft.decrementRecipe(recipe)
        }
        scheduleSave()
    }

    private func removeRecipe(_ recipe: Recipe, slot: MealSlot) {
        let pastUsage = pastDayAssignments(for: recipe, slot: slot)
        if pastUsage > 0 {
            pastDayMessage = "Ten przepis jest przypisany do dnia z przeszłości (\(pastUsage) raz(y)). Najpierw usuń go z tych dni w Kalendarzu."
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            while draft.isSelected(recipe) {
                draft.decrementRecipe(recipe)
            }
        }
        scheduleSave()
    }

    private func pastDayAssignments(for recipe: Recipe, slot: MealSlot) -> Int {
        let pastDates = datesViewModel.dates.filter { !datesViewModel.isEditable($0) }
        guard !pastDates.isEmpty else { return 0 }
        return pastDates.reduce(into: 0) { acc, date in
            if mealStore.recipe(for: date, slot: slot)?.id == recipe.id {
                acc += 1
            }
        }
    }

    /// Debounced save — złapie serię zmian (np. stepper w pickerze) i wyśle jeden zapis.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await persistCurrentDraft()
            saveTask = nil
        }
    }

    @MainActor
    private func persistCurrentDraft() async {
        guard isDirty else { return }

        let plan = SavedMealPlan(
            breakfastEntries: draft.recipes(for: .breakfast).map { PlanEntry(recipe: $0) },
            lunchEntries: draft.recipes(for: .lunch).map { PlanEntry(recipe: $0) },
            dinnerEntries: draft.recipes(for: .dinner).map { PlanEntry(recipe: $0) }
        )

        await mealStore.saveMealPlanToBackend(plan, weekStart: datesViewModel.weekStartISO)
        await shoppingListStore.load(weekStart: datesViewModel.weekStartISO, force: true)
    }

    @MainActor
    private func deletePlan() async {
        await mealStore.clearWeekFromBackend(
            weekStart: datesViewModel.weekStartISO,
            dates: datesViewModel.dates
        )
        await shoppingListStore.load(weekStart: datesViewModel.weekStartISO, force: true)
        draft.loadFromSaved(mealStore.savedPlan)
    }

    private func sameAsSaved(_ draft: MealPlanViewModel, _ saved: SavedMealPlan) -> Bool {
        func ids(_ recipes: [Recipe]) -> [UUID] { recipes.map(\.id) }
        return ids(draft.recipes(for: .breakfast)) == saved.breakfastEntries.map(\.recipe.id)
            && ids(draft.recipes(for: .lunch)) == saved.lunchEntries.map(\.recipe.id)
            && ids(draft.recipes(for: .dinner)) == saved.dinnerEntries.map(\.recipe.id)
    }

    private func planSignature(_ plan: SavedMealPlan) -> String {
        let b = plan.breakfastEntries.map { $0.recipe.id.uuidString }.joined(separator: ",")
        let l = plan.lunchEntries.map { $0.recipe.id.uuidString }.joined(separator: ",")
        let d = plan.dinnerEntries.map { $0.recipe.id.uuidString }.joined(separator: ",")
        return "\(b)|\(l)|\(d)"
    }
}

// MARK: - Picker sheet

private struct RecipePickerSheet: View {
    let slot: MealSlot
    @Bindable var draft: MealPlanViewModel
    let slotMax: Int
    let pastDayCountForRecipe: (Recipe) -> Int
    let onPastDayBlocked: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var onlyFavourites = false

    private var slotCategory: RecipesCategory {
        switch slot {
        case .breakfast: .breakfast
        case .lunch: .lunch
        case .dinner: .dinner
        }
    }

    private var theme: DashboardSheetTheme {
        switch slot {
        case .breakfast: .sunrise
        case .lunch: .ocean
        case .dinner: .plum
        }
    }

    private var filtered: [Recipe] {
        var list = recipeCatalogStore.recipes.filter { $0.category == slotCategory }
        if onlyFavourites {
            list = list.filter { $0.favourite }
        }
        if !debouncedSearch.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(debouncedSearch) ||
                $0.description.localizedCaseInsensitiveContains(debouncedSearch)
            }
        }
        return list
    }

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
    }

    private func cardWidth(for total: CGFloat) -> CGFloat {
        let count: CGFloat = horizontalSizeClass == .compact ? 2 : 3
        let horizontalPadding: CGFloat = 28
        let spacing: CGFloat = 12 * (count - 1)
        return max(150, floor((total - horizontalPadding - spacing) / count))
    }

    private var slotCount: Int { draft.count(for: slot) }
    private var slotFull: Bool { slotCount >= slotMax }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    DashboardSheetBackground(theme: theme)
                        .ignoresSafeArea()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            headerCard

                            if filtered.isEmpty {
                                emptyState
                            } else {
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(filtered) { recipe in
                                        pickerCard(recipe: recipe, width: cardWidth(for: proxy.size.width))
                                            .task {
                                                await recipeCatalogStore.loadNextPageIfNeeded(currentItemId: recipe.id, threshold: 8)
                                            }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 6)
                        .padding(.bottom, 110)
                    }

                    footerBar
                }
            }
            .navigationTitle(slot.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Gotowe") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Szukaj przepisów")
            .task {
                await recipeCatalogStore.loadIfNeeded()
            }
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    debouncedSearch = newValue
                }
            }
            .onDisappear { searchDebounceTask?.cancel() }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(spacing: 12) {
            Image(systemName: slot.icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(slot.accentColor)
                .frame(width: 40, height: 40)
                .background(
                    DashboardPalette.tintFill(slot.accentColor, scheme: colorScheme, dark: 0.2, light: 0.16),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("\(slotCount) / \(slotMax) w planie")
                    .font(.subheadline.weight(.bold))
                Text("Stuknij kartę, żeby dodać. Kolejne stuknięcie zwiększa porcję.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            favouritesToggle
        }
        .padding(14)
        .dashboardLiquidCard(cornerRadius: 18, strokeOpacity: 0.16)
    }

    private var favouritesToggle: some View {
        Button {
            onlyFavourites.toggle()
        } label: {
            Image(systemName: onlyFavourites ? "heart.fill" : "heart")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(onlyFavourites ? Color.pink : Color.secondary)
                .frame(width: 36, height: 36)
                .background(
                    onlyFavourites
                        ? DashboardPalette.tintFill(.pink, scheme: colorScheme, dark: 0.18, light: 0.14)
                        : DashboardPalette.surface(colorScheme, level: .secondary),
                    in: Circle()
                )
                .overlay(
                    Circle()
                        .stroke(
                            onlyFavourites
                                ? Color.pink.opacity(colorScheme == .dark ? 0.3 : 0.22)
                                : DashboardPalette.neutralBorder(colorScheme, opacity: 0.12),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pokaż tylko ulubione")
    }

    // MARK: - Card

    private func pickerCard(recipe: Recipe, width: CGFloat) -> some View {
        let count = draft.recipeCount(recipe)
        return ZStack(alignment: .topLeading) {
            Button {
                tryIncrement(recipe)
            } label: {
                RecipeCarouselCard(
                    recipe: recipe,
                    width: width,
                    selectionCount: count,
                    showsHeart: count == 0
                )
            }
            .buttonStyle(.plain)

            if count > 0 {
                selectionStepper(recipe: recipe, count: count)
                    .padding(.top, 10)
                    .padding(.leading, 10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.18), value: count)
    }

    private func selectionStepper(recipe: Recipe, count: Int) -> some View {
        let canIncrement = !slotFull
        return HStack(spacing: 0) {
            Button {
                tryDecrement(recipe)
            } label: {
                Image(systemName: count == 1 ? "trash" : "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                Text("×\(count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 4)

            Button {
                tryIncrement(recipe)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canIncrement)
            .opacity(canIncrement ? 1 : 0.45)
        }
        .background(
            Capsule()
                .fill(Color.green.opacity(colorScheme == .dark ? 0.9 : 0.82))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(slotCount) / \(slotMax)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(slotFull ? "Slot domknięty" : "wybrano")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Gotowe")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(height: 44)
                    .background(
                        LinearGradient(
                            colors: [
                                slot.accentColor.opacity(colorScheme == .dark ? 0.95 : 0.88),
                                slot.secondaryAccentColor.opacity(colorScheme == .dark ? 0.82 : 0.74)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.2), lineWidth: 1)
                    )
                    .shadow(color: slot.accentColor.opacity(colorScheme == .dark ? 0.3 : 0.22), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DashboardPalette.neutralBorder(colorScheme, opacity: 0.14), lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Brak wyników")
                .font(.headline.weight(.semibold))
            Text(debouncedSearch.isEmpty ? "Spróbuj zmienić filtr." : "Spróbuj innej frazy.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 16)
        .dashboardLiquidCard(cornerRadius: 20, strokeOpacity: 0.16)
    }

    // MARK: - Actions

    private func tryIncrement(_ recipe: Recipe) {
        guard draft.count(for: slot) < slotMax else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            draft.incrementRecipe(recipe)
        }
    }

    private func tryDecrement(_ recipe: Recipe) {
        let currentCount = draft.recipeCount(recipe)
        let pastUsage = pastDayCountForRecipe(recipe)
        if currentCount - 1 < pastUsage {
            onPastDayBlocked("Ten przepis jest przypisany do dnia z przeszłości (\(pastUsage) raz(y)). Najpierw usuń go z tych dni w Kalendarzu.")
            return
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            draft.decrementRecipe(recipe)
        }
    }
}

#Preview {
    WeeklyPlanPoolView()
}
