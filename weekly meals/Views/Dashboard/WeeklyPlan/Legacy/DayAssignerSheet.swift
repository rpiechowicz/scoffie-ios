import SwiftUI

/// Pełnoekranowy asystent przypisywania posiłków z puli tygodnia do konkretnych dni.
/// UX: cały tydzień widoczny jako siatka 7×3 + pula na dole. Klik w kartę puli → "podnosi" przepis,
/// klik w pasujący slot dnia → przypisuje. Klik w zajętą komórkę bez wybranej karty puli → zdejmuje.
struct DayAssignerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.weeklyMealStore) private var mealStore
    @Environment(\.colorScheme) private var colorScheme

    let weekDates: [Date]
    let weekStartISO: String

    @State private var activePoolSlot: MealSlot = .breakfast
    @State private var selectedPoolRecipeId: UUID?

    // MARK: - Derived

    private func isEditable(_ date: Date) -> Bool {
        Calendar.current.startOfDay(for: date) >= Calendar.current.startOfDay(for: Date())
    }

    private var totalAssigned: Int {
        weekDates.reduce(0) { acc, date in
            acc + MealSlot.allCases.reduce(0) {
                $0 + (mealStore.recipe(for: date, slot: $1) != nil ? 1 : 0)
            }
        }
    }

    private var totalPotential: Int { weekDates.count * MealSlot.allCases.count }

    private struct PoolItem: Identifiable {
        let recipe: Recipe
        let remaining: Int
        var id: UUID { recipe.id }
    }

    private func poolItems(for slot: MealSlot) -> [PoolItem] {
        let available = mealStore.savedPlan.availableRecipes(for: slot)
        var order: [UUID] = []
        var counts: [UUID: Int] = [:]
        var recipes: [UUID: Recipe] = [:]
        for r in available {
            if recipes[r.id] == nil {
                order.append(r.id)
                recipes[r.id] = r
            }
            counts[r.id, default: 0] += 1
        }
        return order.compactMap { id in
            guard let recipe = recipes[id], let count = counts[id], count > 0 else { return nil }
            return PoolItem(recipe: recipe, remaining: count)
        }
    }

    private var selectedPoolRecipe: Recipe? {
        guard let id = selectedPoolRecipeId else { return nil }
        return poolItems(for: activePoolSlot).first(where: { $0.recipe.id == id })?.recipe
    }

    private var selectedPoolRemaining: Int {
        guard let id = selectedPoolRecipeId else { return 0 }
        return poolItems(for: activePoolSlot).first(where: { $0.recipe.id == id })?.remaining ?? 0
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                DashboardSheetBackground(theme: .indigo)
                    .ignoresSafeArea()

                VStack(spacing: 10) {
                    topBar
                        .frame(height: 56)

                    slotPicker

                    daysPager

                    poolSection
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedPoolRecipeId)
                .animation(.easeInOut(duration: 0.2), value: activePoolSlot)
            }
            .navigationTitle("Przypisz posiłki")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Gotowe") { dismiss() }
                }
            }
            .onAppear {
                prefetchPoolImages()
            }
        }
    }

    // MARK: - Top bar

    @ViewBuilder
    private var topBar: some View {
        if let recipe = selectedPoolRecipe {
            hintBar(recipe: recipe, remaining: selectedPoolRemaining)
        } else {
            progressBar
        }
    }

    private var progressBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            Text("\(totalAssigned) z \(totalPotential) przypisanych")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            GeometryReader { geo in
                let progress = totalPotential > 0 ? CGFloat(totalAssigned) / CGFloat(totalPotential) : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DashboardPalette.surface(colorScheme, level: .tertiary))
                    Capsule()
                        .fill(Color.green.opacity(0.8))
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(width: 80, height: 5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .dashboardLiquidCard(cornerRadius: 14, strokeOpacity: 0.14)
    }

    private func hintBar(recipe: Recipe, remaining: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.2), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text("Kliknij dzień dla \(activePoolSlot.title.lowercased())")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(recipe.name) • \(remaining) do przypisania")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button {
                selectedPoolRecipeId = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.2), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(activePoolSlot.accentColor.opacity(0.88))
        )
        .shadow(color: activePoolSlot.accentColor.opacity(0.35), radius: 8, x: 0, y: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Slot picker

    private var slotPicker: some View {
        Picker("Slot", selection: $activePoolSlot) {
            ForEach(MealSlot.allCases) { slot in
                Text(slot.title).tag(slot)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: activePoolSlot) { _, _ in
            selectedPoolRecipeId = nil
        }
    }

    // MARK: - Days list

    private var daysPager: some View {
        ZStack {
            daysList(for: activePoolSlot)
                .id(activePoolSlot)
                .transition(.opacity)
        }
        .frame(maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.22), value: activePoolSlot)
    }

    private func daysList(for slot: MealSlot) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 7) {
                ForEach(weekDates, id: \.self) { date in
                    dayRow(date: date, slot: slot)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 1)
        }
    }

    private func dayRow(date: Date, slot: MealSlot) -> some View {
        let assigned = mealStore.recipe(for: date, slot: slot)
        let editable = isEditable(date)
        let isToday = Calendar.current.isDateInToday(date)
        let hasPool = selectedPoolRecipeId != nil
        let isValidTarget = hasPool && editable && assigned == nil
        let middleTappable = editable && hasPool

        return HStack(spacing: 12) {
            dayBadge(date: date, isToday: isToday)

            rowMiddle(
                slot: slot,
                assigned: assigned,
                editable: editable
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard middleTappable else { return }
                cellTap(date: date, slot: slot, assigned: assigned)
            }

            trailingControl(
                slot: slot,
                assigned: assigned,
                editable: editable,
                hasPool: hasPool,
                isValidTarget: isValidTarget,
                date: date
            )
            .frame(width: 28, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            rowBackground(
                isValidTarget: isValidTarget,
                isToday: isToday
            )
        )
        .opacity(editable || assigned != nil ? 1 : 0.62)
        .animation(.easeInOut(duration: 0.18), value: isValidTarget)
    }

    private func dayBadge(date: Date, isToday: Bool) -> some View {
        VStack(spacing: 1) {
            Text(dayName(date))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isToday ? Color.blue : .secondary)
            Text(dayNumber(date))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(isToday ? Color.blue : .primary)
                .monospacedDigit()
        }
        .frame(width: 44)
    }

    @ViewBuilder
    private func rowMiddle(
        slot: MealSlot,
        assigned: Recipe?,
        editable: Bool
    ) -> some View {
        if let assigned {
            HStack(spacing: 11) {
                rowThumb(recipe: assigned, slot: slot)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(assigned.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            slot.accentColor.opacity(editable ? 0.45 : 0.2),
                            style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                        )
                    Image(systemName: editable ? slot.icon : "lock.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(slot.accentColor.opacity(editable ? 0.7 : 0.4))
                }
                .frame(width: 56, height: 56)

                Text(editable ? "Wolne" : "Zablokowane")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func trailingControl(
        slot: MealSlot,
        assigned: Recipe?,
        editable: Bool,
        hasPool: Bool,
        isValidTarget: Bool,
        date: Date
    ) -> some View {
        if let assigned {
            if !editable {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.55))
            } else if hasPool {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(slot.accentColor.opacity(0.75))
            } else {
                Button {
                    performRemove(recipe: assigned, date: date, slot: slot)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.65))
                        .padding(.leading, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } else if isValidTarget {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(slot.accentColor)
        }
    }

    private func rowThumb(recipe: Recipe, slot: MealSlot) -> some View {
        Group {
            if let url = recipe.imageURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        ZStack {
                            Rectangle().fill(slot.accentColor.opacity(0.22))
                            Image(systemName: slot.icon)
                                .foregroundStyle(slot.accentColor)
                        }
                    @unknown default:
                        Rectangle().fill(slot.accentColor.opacity(0.22))
                    }
                }
            } else {
                ZStack {
                    Rectangle().fill(slot.accentColor.opacity(0.22))
                    Image(systemName: slot.icon)
                        .foregroundStyle(slot.accentColor)
                }
            }
        }
    }

    private func rowBackground(
        isValidTarget: Bool,
        isToday: Bool
    ) -> some View {
        let corner: CGFloat = 14
        let borderColor: Color = {
            if isValidTarget { return activePoolSlot.accentColor.opacity(0.9) }
            if isToday { return Color.blue.opacity(0.45) }
            return DashboardPalette.neutralBorder(colorScheme, opacity: 0.14)
        }()
        let lineWidth: CGFloat = isValidTarget ? 1.8 : 1

        return RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(DashboardPalette.surface(colorScheme, level: .secondary))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: lineWidth)
            )
    }

    // MARK: - Pool

    private var poolSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: activePoolSlot.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(activePoolSlot.accentColor)
                Text("Pula — \(activePoolSlot.title.lowercased())")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(poolItems(for: activePoolSlot).reduce(0) { $0 + $1.remaining }) poz.")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.8))
            }

            let items = poolItems(for: activePoolSlot)

            if items.isEmpty {
                emptyPoolState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            poolCard(item: item)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
                .frame(height: 138)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .dashboardLiquidCard(cornerRadius: 18, strokeOpacity: 0.16)
    }

    private var emptyPoolState: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.green.opacity(0.85))

            VStack(alignment: .leading, spacing: 2) {
                Text("Pula \(activePoolSlot.title.lowercased()) wyczerpana")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Wszystkie pozycje z planu są już rozdzielone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 138)
    }

    private func poolCard(item: PoolItem) -> some View {
        let recipe = item.recipe
        let isSelected = selectedPoolRecipeId == recipe.id
        let accent = activePoolSlot.accentColor

        return Button {
            togglePool(recipeId: recipe.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    poolThumbnail(recipe: recipe)
                        .frame(width: 106, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text("×\(item.remaining)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .padding(6)
                }

                Text(recipe.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 106, alignment: .leading)
                    .frame(height: 28, alignment: .top)
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isSelected
                            ? accent.opacity(colorScheme == .dark ? 0.22 : 0.16)
                            : DashboardPalette.surface(colorScheme, level: .secondary)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected
                            ? accent.opacity(0.85)
                            : DashboardPalette.neutralBorder(colorScheme, opacity: 0.12),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1)
        }
        .buttonStyle(.plain)
    }

    private func poolThumbnail(recipe: Recipe) -> some View {
        Group {
            if let url = recipe.imageURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        Rectangle().fill(activePoolSlot.accentColor.opacity(0.2))
                    @unknown default:
                        Rectangle().fill(activePoolSlot.accentColor.opacity(0.2))
                    }
                }
            } else {
                ZStack {
                    Rectangle().fill(activePoolSlot.accentColor.opacity(0.22))
                    Image(systemName: activePoolSlot.icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(activePoolSlot.accentColor)
                }
            }
        }
    }

    // MARK: - Interactions

    private func togglePool(recipeId: UUID) {
        if selectedPoolRecipeId == recipeId {
            selectedPoolRecipeId = nil
        } else {
            selectedPoolRecipeId = recipeId
        }
    }

    private func cellTap(date: Date, slot: MealSlot, assigned: Recipe?) {
        let editable = isEditable(date)

        if let recipe = selectedPoolRecipe {
            guard slot == activePoolSlot, editable else {
                if assigned == nil && editable && activePoolSlot != slot {
                    activePoolSlot = slot
                }
                return
            }
            if assigned?.id == recipe.id { return }
            performAssign(recipe: recipe, replacing: assigned, date: date, slot: slot)
            return
        }

        if let assigned, editable {
            performRemove(recipe: assigned, date: date, slot: slot)
            return
        }

        if assigned == nil && editable && activePoolSlot != slot {
            activePoolSlot = slot
        }
    }

    private func performAssign(recipe: Recipe, replacing previous: Recipe?, date: Date, slot: MealSlot) {
        if let previous {
            mealStore.markAsAvailable(previous, slot: slot)
        }
        mealStore.markAsSelected(recipe, slot: slot)

        let previousRecipe = previous
        Task { @MainActor in
            let ok = await mealStore.upsertWeekSlot(
                recipe: recipe,
                for: date,
                slot: slot,
                weekStart: weekStartISO
            )
            if !ok {
                mealStore.markAsAvailable(recipe, slot: slot)
                if let previousRecipe { mealStore.markAsSelected(previousRecipe, slot: slot) }
            }
        }

        let remainingAfter = mealStore.savedPlan.availableCount(for: recipe.id, slot: slot)
        if remainingAfter == 0 {
            selectedPoolRecipeId = nil
        }
    }

    private func performRemove(recipe: Recipe, date: Date, slot: MealSlot) {
        mealStore.markAsAvailable(recipe, slot: slot)
        Task { @MainActor in
            let ok = await mealStore.removeWeekSlot(
                for: date,
                slot: slot,
                weekStart: weekStartISO
            )
            if !ok { mealStore.markAsSelected(recipe, slot: slot) }
        }
    }

    // MARK: - Prefetch

    private func prefetchPoolImages() {
        let urls = MealSlot.allCases
            .flatMap { poolItems(for: $0).map(\.recipe) }
            .compactMap(\.imageURL)
        ImagePrefetcher.prefetch(urls)
    }

    // MARK: - Formatting

    private static let dayNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "EEE"
        return f
    }()

    private func dayName(_ date: Date) -> String {
        Self.dayNameFormatter
            .string(from: date)
            .replacingOccurrences(of: ".", with: "")
            .uppercased()
    }

    private func dayNumber(_ date: Date) -> String {
        String(Calendar.current.component(.day, from: date))
    }
}

#Preview {
    DayAssignerSheet(
        weekDates: (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Date()) },
        weekStartISO: "2026-04-20"
    )
}
