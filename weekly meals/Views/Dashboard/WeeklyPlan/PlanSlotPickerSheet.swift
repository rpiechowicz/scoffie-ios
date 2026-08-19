import SwiftUI

/// Picks a recipe *and its audience* for a single `(day, slot)` pair and writes
/// it straight to the week plan — the `+ Dodaj` / „Zmień przepis" target of
/// Plan v2.
///
/// The audience chips sit above the grid and default to „Wspólne", so adding a
/// normal household meal stays a single tap. Naming people instead is what
/// turns the slot into a „Każdy je inaczej" split.
///
/// This is the only way meals enter the plan. Kalendarz opens it too, so both
/// tabs assign the same way.
struct PlanSlotPickerSheet: View {
    let date: Date
    let slot: MealSlot
    let weekStartISO: String
    let members: [HouseholdMemberSnapshot]
    /// Meal being edited — preloads the audience chips and highlights its
    /// recipe. `nil` adds a new variant to the slot.
    let editing: PlanMeal?

    init(
        date: Date,
        slot: MealSlot,
        weekStartISO: String,
        members: [HouseholdMemberSnapshot],
        editing: PlanMeal?,
        defaultParticipantIds: [String] = []
    ) {
        self.date = date
        self.slot = slot
        self.weekStartISO = weekStartISO
        self.members = members
        self.editing = editing
        // Seeded here rather than in `.task`: that ran after `await`ing the
        // recipe catalog, so a chip tapped in the meantime was silently reset
        // and the meal saved as „Wspólne".
        _selectedParticipants = State(
            initialValue: Set(editing?.participantIds ?? defaultParticipantIds)
        )
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.weeklyMealStore) private var mealStore
    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var onlyFavourites = false
    @State private var isSaving = false
    /// Empty means „Wspólne" — the whole household eats it.
    @State private var selectedParticipants: Set<String> = []

    // MARK: - Derived

    private var slotCategory: RecipesCategory {
        switch slot {
        case .breakfast: .breakfast
        case .lunch:     .lunch
        case .dinner:    .dinner
        }
    }

    private var filtered: [Recipe] {
        var list = recipeCatalogStore.recipes.filter { $0.category == slotCategory }
        if onlyFavourites {
            list = list.filter(\.favourite)
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
        let horizontalPadding: CGFloat = 44   // 22pt each side
        let spacing: CGFloat = 12 * (count - 1)
        return max(150, floor((total - horizontalPadding - spacing) / count))
    }

    /// Audience to persist. Naming everyone is the same statement as naming
    /// nobody, so it collapses to „Wspólne".
    private var participantsToSave: [String] {
        if selectedParticipants.isEmpty { return [] }
        if selectedParticipants.count == members.count { return [] }
        return members.map(\.id).filter { selectedParticipants.contains($0) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    WMPageBackground(scheme: scheme)
                        .ignoresSafeArea()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            header

                            if members.count > 1 {
                                audienceChips
                            }

                            if let errorMessage = mealStore.errorMessage, !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }

                            if filtered.isEmpty {
                                emptyState
                            } else {
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(filtered) { recipe in
                                        card(recipe: recipe, width: cardWidth(for: proxy.size.width))
                                            .task {
                                                await recipeCatalogStore.loadNextPageIfNeeded(
                                                    currentItemId: recipe.id,
                                                    threshold: 8
                                                )
                                            }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                    .scrollIndicators(.hidden)
                    .disabled(isSaving)
                }
            }
            .navigationTitle(slot.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if editing != nil {
                        Button("Zapisz") { saveAudienceOnly() }
                            .font(.body.weight(.semibold))
                            .disabled(isSaving)
                    } else {
                        favouritesToggle
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Szukaj przepisów")
            .task { await recipeCatalogStore.loadIfNeeded() }
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

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(slot.title.uppercased()) · \(Self.dayFormatter.string(from: date).uppercased())")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundStyle(slot.cozyAccent)

            Text(editing == nil ? "Wybierz przepis" : "Zmień przepis")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Color.wmLabel(scheme))

            Text(
                members.count > 1
                    ? "Wybierz dla kogo, potem stuknij przepis."
                    : "Jedno stuknięcie przypisuje przepis do tego dnia."
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.wmMuted(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// „Wspólne / Marek / Ania …" — deselecting everyone falls back to
    /// „Wspólne", so the slot always has a defined audience.
    private var audienceChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DLA KOGO")
                .font(.system(size: 9, weight: .bold))
                .tracking(2)
                .foregroundStyle(Color.wmMuted(scheme))

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip(
                        title: "Wspólne",
                        tint: WMPalette.terracotta,
                        isOn: selectedParticipants.isEmpty,
                        avatar: AnyView(houseGlyph)
                    ) {
                        selectedParticipants.removeAll()
                    }

                    ForEach(members) { member in
                        let tint = HouseholdMemberStyle.color(for: member.id, in: members)
                        chip(
                            title: HouseholdMemberStyle.shortName(member.displayName),
                            tint: tint,
                            isOn: selectedParticipants.contains(member.id),
                            avatar: AnyView(MemberAvatar(member: member, members: members, size: 20))
                        ) {
                            toggle(member.id)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func chip(
        title: String,
        tint: Color,
        isOn: Bool,
        avatar: AnyView,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                avatar

                Text(title)
                    .font(.system(size: 13, weight: isOn ? .bold : .semibold))
                    .foregroundStyle(isOn ? Color.wmLabel(scheme) : Color.wmMuted(scheme))
                    .lineLimit(1)
            }
            .padding(.leading, 5)
            .padding(.trailing, 12)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isOn ? tint.opacity(scheme == .dark ? 0.22 : 0.16) : Color.wmTileBg(scheme))
            )
            .overlay(
                Capsule().stroke(
                    isOn ? tint.opacity(scheme == .dark ? 0.55 : 0.45) : Color.wmTileStroke(scheme),
                    lineWidth: isOn ? 1.4 : 1
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var houseGlyph: some View {
        Image(systemName: "house.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(
                LinearGradient(
                    colors: [WMPalette.terracotta, WMPalette.terracotta.mix(black: 0.22)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: Circle()
            )
    }

    private var favouritesToggle: some View {
        Button {
            onlyFavourites.toggle()
        } label: {
            Image(systemName: onlyFavourites ? "heart.fill" : "heart")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(onlyFavourites ? WMPalette.terracotta : Color.wmMuted(scheme))
        }
        .accessibilityLabel(onlyFavourites ? "Pokaż wszystkie przepisy" : "Pokaż tylko ulubione")
    }

    private func card(recipe: Recipe, width: CGFloat) -> some View {
        let isCurrent = recipe.id == editing?.recipe.id

        return Button {
            assign(recipe)
        } label: {
            RecipeCarouselCard(
                recipe: recipe,
                width: width,
                selectionCount: isCurrent ? 1 : 0,
                showsHeart: !isCurrent
            )
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel(isCurrent ? "\(recipe.name), obecnie przypisany" : recipe.name)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.wmMuted(scheme))

            Text("Brak wyników")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.wmLabel(scheme))

            Text(debouncedSearch.isEmpty ? "Spróbuj zmienić filtr." : "Spróbuj innej frazy.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.wmMuted(scheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Actions

    private func toggle(_ memberId: String) {
        if selectedParticipants.contains(memberId) {
            selectedParticipants.remove(memberId)
        } else {
            selectedParticipants.insert(memberId)
        }
    }

    private func assign(_ recipe: Recipe) {
        guard !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            let ok = await mealStore.upsertWeekSlot(
                recipe: recipe,
                participantIds: participantsToSave,
                // In edit mode a different pick replaces the meal being edited
                // rather than piling a second variant into the slot.
                replacingRecipeId: editing?.recipe.id,
                for: date,
                slot: slot,
                weekStart: weekStartISO
            )
            isSaving = false
            if ok { dismiss() }
        }
    }

    /// „Zapisz" in edit mode — keeps the recipe, rewrites who it is for.
    private func saveAudienceOnly() {
        guard let editing, !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            let ok = await mealStore.upsertWeekSlot(
                recipe: editing.recipe,
                participantIds: participantsToSave,
                for: date,
                slot: slot,
                weekStart: weekStartISO
            )
            isSaving = false
            if ok { dismiss() }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "EEEE, d MMM"
        return f
    }()
}
