import SwiftUI

struct ProductsView: View {
    @Environment(\.shoppingListStore) private var shoppingListStore
    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.colorScheme) private var scheme

    @State private var archivePendingDeletion: ArchivedShoppingList?
    @State private var showDeleteAllHistoryAlert = false
    @State private var previewArchiveId: String?
    @State private var showHistorySheet = false

    private static let weekRangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    // MARK: - Derived state

    private var shoppingItems: [ShoppingItem] {
        shoppingListStore.items
    }

    private var previewedArchive: ArchivedShoppingList? {
        guard let previewArchiveId else { return nil }
        return shoppingListStore.archivedLists.first { $0.archiveId == previewArchiveId }
    }

    private var previewedArchiveItems: [ShoppingItem] {
        guard let previewArchiveId else { return [] }
        return shoppingListStore.archiveDisplayItems(archiveId: previewArchiveId)
    }

    private var previewArchiveSheetBinding: Binding<ArchivedShoppingList?> {
        Binding(
            get: { previewedArchive },
            set: { updatedValue in
                previewArchiveId = updatedValue?.archiveId
            }
        )
    }

    private var archivedCurrentWeek: ArchivedShoppingList? {
        shoppingListStore.currentClosedArchive(for: datesViewModel.weekStartISO)
    }

    private var hasOpenRevision: Bool {
        shoppingListStore.hasOpenRevision(for: datesViewModel.weekStartISO)
    }

    private var isCurrentWeekArchived: Bool {
        archivedCurrentWeek != nil && !hasOpenRevision
    }

    /// Active list — pending items only when there's an open revision after
    /// a closed list. The previously-bought items are intentionally hidden:
    /// the active list shows only what the user can still buy this week.
    private var activeItems: [ShoppingItem] {
        hasOpenRevision
        ? shoppingListStore.pendingItems(for: datesViewModel.weekStartISO)
        : shoppingItems
    }

    private var groupedByDepartment: [(department: String, items: [ShoppingItem])] {
        groupItemsByDepartment(activeItems)
    }

    private var groupedPreviewItemsByDepartment: [(department: String, items: [ShoppingItem])] {
        groupItemsByDepartment(previewedArchiveItems)
    }

    private func groupItemsByDepartment(_ items: [ShoppingItem]) -> [(department: String, items: [ShoppingItem])] {
        let departmentOrder: [String: Int] = [
            ProductConstants.Department.vegetables: 1,
            ProductConstants.Department.fruits: 2,
            ProductConstants.Department.meat: 3,
            ProductConstants.Department.fish: 4,
            ProductConstants.Department.dairy: 5,
            ProductConstants.Department.bakery: 6,
            ProductConstants.Department.grains: 7,
            ProductConstants.Department.canned: 8,
            ProductConstants.Department.spices: 9,
            ProductConstants.Department.oils: 10,
            ProductConstants.Department.alcohols: 11,
            ProductConstants.Department.beverages: 12,
            ProductConstants.Department.snacks: 13,
            ProductConstants.Department.frozen: 14,
            ProductConstants.Department.bakerySweets: 15,
            ProductConstants.Department.household: 16,
            ProductConstants.Department.other: 99
        ]
        let normalizedOther = ProductConstants.Department.other
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return Dictionary(grouping: items, by: \.department)
            .sorted {
                let leftKey = $0.key.trimmingCharacters(in: .whitespacesAndNewlines)
                let rightKey = $1.key.trimmingCharacters(in: .whitespacesAndNewlines)

                let leftIsOther = leftKey.lowercased() == normalizedOther
                let rightIsOther = rightKey.lowercased() == normalizedOther
                if leftIsOther != rightIsOther {
                    return !leftIsOther
                }

                let leftRank = departmentOrder[leftKey] ?? 999
                let rightRank = departmentOrder[rightKey] ?? 999
                if leftRank != rightRank { return leftRank < rightRank }
                return leftKey < rightKey
            }
            .map { (department: $0.key, items: $0.value) }
    }

    private var boughtCount: Int {
        activeItems.filter(\.isChecked).count
    }

    private var remainingCount: Int {
        max(0, activeItems.count - boughtCount)
    }

    private var weekRangeText: String {
        guard let first = datesViewModel.dates.first,
              let last = datesViewModel.dates.last else {
            return "Bieżący tydzień"
        }
        return "\(Self.weekRangeFormatter.string(from: first)) - \(Self.weekRangeFormatter.string(from: last))"
    }

    private var canCloseCurrentList: Bool {
        if shoppingItems.isEmpty {
            return false
        }
        if hasOpenRevision {
            return shoppingItems.allSatisfy(\.isChecked)
        }
        return !activeItems.isEmpty && boughtCount == activeItems.count
    }

    // MARK: - Hero CTA — dual-purpose (Kupione ↔ Zamknij)
    //
    // The single button in the hero card is the only place where the user
    // can either bulk-mark items as bought or archive the list. We swap
    // the title/icon/action based on state so the button always has a
    // relevant next step (and there's no extra "Zamknij" button taking
    // up screen real estate).

    /// `true` once every item is bought and the list is ready to archive.
    private var allItemsBought: Bool {
        canCloseCurrentList && remainingCount == 0
    }

    private var heroActionTitle: String {
        if shoppingListStore.isArchivePendingAfterBatch {
            return "Zamykam…"
        }
        if shoppingListStore.isBatchUpdating {
            return "Zaznaczanie…"
        }
        return allItemsBought ? "Zamknij" : "Kupione"
    }

    private var heroActionIcon: String {
        if shoppingListStore.isArchivePendingAfterBatch {
            return "hourglass"
        }
        return allItemsBought ? "archivebox.fill" : "checkmark"
    }

    private var heroActionDisabled: Bool {
        if shoppingListStore.isBatchUpdating || shoppingListStore.isArchivePendingAfterBatch {
            return true
        }
        if allItemsBought {
            return false
        }
        // Standard "Kupione" CTA — disabled only when nothing to mark.
        return remainingCount == 0
    }

    private var heroActionLoading: Bool {
        shoppingListStore.isBatchUpdating || shoppingListStore.isArchivePendingAfterBatch
    }

    private var heroAction: () -> Void {
        if allItemsBought {
            return { shoppingListStore.archiveCurrentList(weekLabel: weekRangeText) }
        }
        return { shoppingListStore.markAllChecked() }
    }

    private var pageBottomPadding: CGFloat { WMPageMetrics.bottom }
    private var pageHorizontalPadding: CGFloat { WMPageMetrics.horizontal }
    private var pageTopPadding: CGFloat { WMPageMetrics.top }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                WMPageBackground(scheme: scheme)
                    .ignoresSafeArea()

                Group {
                    if shoppingListStore.isLoading && shoppingItems.isEmpty {
                        loadingState
                    } else if isCurrentWeekArchived {
                        archivedState
                    } else if shoppingItems.isEmpty && !hasOpenRevision {
                        emptyState
                    } else {
                        shoppingListContent
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            .background(NavBarHitTestPassthrough())
            .alert("Usunąć listę z historii?", isPresented: archiveDeleteAlertBinding) {
                Button("Anuluj", role: .cancel) {
                    archivePendingDeletion = nil
                }
                Button("Usuń", role: .destructive) {
                    if let archivePendingDeletion {
                        if previewArchiveId == archivePendingDeletion.archiveId {
                            previewArchiveId = nil
                        }
                        shoppingListStore.deleteArchivedList(archiveId: archivePendingDeletion.id)
                    }
                    archivePendingDeletion = nil
                }
            } message: {
                Text("Ta operacja usunie zapisany wpis historyczny dla wybranego tygodnia.")
            }
            .alert("Usunąć całą historię list?", isPresented: $showDeleteAllHistoryAlert) {
                Button("Anuluj", role: .cancel) { }
                Button("Usuń wszystko", role: .destructive) {
                    previewArchiveId = nil
                    shoppingListStore.deleteAllArchivedLists()
                }
            } message: {
                Text("Ta operacja usunie wszystkie zapisane listy produktów z historii.")
            }
            .task(id: datesViewModel.weekStartISO) {
                previewArchiveId = nil
                await shoppingListStore.load(weekStart: datesViewModel.weekStartISO)
            }
            .sheet(item: previewArchiveSheetBinding) { archive in
                archivePreview(archive)
                    .presentationDetents([.large])
                    .dashboardLiquidSheet()
            }
            .sheet(isPresented: $showHistorySheet) {
                historySheet
                    .presentationDetents([.medium, .large])
                    .dashboardLiquidSheet()
            }
        }
    }

    // MARK: - Header (shared across states)

    private var editorialHeader: some View {
        // Ten sam `EditorialPageHeader` co na Przepisach — sam tytuł, bez
        // eyebrow „№ X · ZAKUPY TYGODNIA" i bez drugiej linii. Numer tygodnia
        // nie niósł tu żadnej akcji, a robił z nagłówka osobny wzorzec.
        EditorialPageHeader("Produkty")
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, pageTopPadding)
            .padding(.bottom, 8)
    }

    // MARK: - Active shopping list

    private var shoppingListContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                editorialHeader

                if let errorMessage = shoppingListStore.errorMessage, !errorMessage.isEmpty {
                    Text(verbatim: errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, pageHorizontalPadding)
                        .padding(.bottom, 8)
                }

                // The hero CTA is dual-purpose:
                //   • items left to buy → "Kupione" (mark all as bought)
                //   • all bought + can close → "Zamknij" (archive the list)
                // Same visual slot, no extra button taking screen space.
                EditorialShoppingHero(
                    bought: boughtCount,
                    total: activeItems.count,
                    subtitleOverride: hasOpenRevision ? "NOWA LISTA ZAKUPÓW" : nil,
                    primaryActionTitle: heroActionTitle,
                    primaryActionSystemImage: heroActionIcon,
                    isPrimaryActionDisabled: heroActionDisabled,
                    isPrimaryActionLoading: heroActionLoading,
                    onPrimaryAction: heroAction
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

                if groupedByDepartment.isEmpty {
                    if hasOpenRevision {
                        noPendingProductsCard
                            .padding(.horizontal, pageHorizontalPadding)
                            .padding(.top, 18)
                    } else {
                        compactEmptyCard
                            .padding(.horizontal, pageHorizontalPadding)
                            .padding(.top, 18)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(Array(groupedByDepartment.enumerated()), id: \.element.department) { idx, group in
                            EditorialAisleSection(
                                index: idx + 1,
                                title: group.department,
                                icon: ProductConstants.departmentIcon(for: group.department),
                                accent: ProductConstants.departmentColor(for: group.department),
                                bought: group.items.filter(\.isChecked).count,
                                total: group.items.count,
                                items: group.items.map(asAisleItem),
                                disableTaps: shoppingListStore.isBatchUpdating,
                                onToggle: { aisleItem in
                                    handleToggle(productKey: aisleItem.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }
            }
            .padding(.bottom, pageBottomPadding)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(.container, edges: .top)
    }

    private func asAisleItem(_ item: ShoppingItem) -> EditorialAisleSection.Item {
        EditorialAisleSection.Item(
            id: item.productKey,
            name: item.name,
            amount: "\(item.formattedAmount) \(item.unit)".trimmingCharacters(in: .whitespaces),
            bought: item.isChecked
        )
    }

    private func handleToggle(productKey: String) {
        guard let item = activeItems.first(where: { $0.productKey == productKey }) else { return }
        Task { @MainActor in
            await shoppingListStore.toggleChecked(item)
        }
    }

    // MARK: - Loading state

    private var loadingState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                editorialHeader

                VStack(alignment: .leading, spacing: 18) {
                    Text("Przygotowuję listę zakupów")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.wmLabel(scheme))
                    Text("Pobieram aktualny stan dla tego tygodnia. Przy kolejnych wejściach aplikacja pokaże zapisany stan od razu.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.wmTileBg(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)

                VStack(spacing: 12) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.wmTileBg(scheme))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
                            )
                            .frame(height: 64)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .redacted(reason: .placeholder)
            }
            .padding(.bottom, pageBottomPadding)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                editorialHeader

                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(WMPalette.terracotta.opacity(scheme == .dark ? 0.18 : 0.10))
                        Image(systemName: "basket.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(WMPalette.terracotta)
                    }
                    .frame(width: 78, height: 78)

                    VStack(spacing: 8) {
                        Text("Lista zakupów jest jeszcze pusta")
                            .font(.system(size: 18, weight: .heavy))
                            .tracking(-0.4)
                            .foregroundStyle(Color.wmLabel(scheme))
                            .multilineTextAlignment(.center)

                        Text("Dodaj posiłki do planu tygodniowego, a produkty pojawią się tutaj automatycznie.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.wmMuted(scheme))
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 8) {
                        emptyHintChip(icon: "calendar.badge.plus", title: "Dodaj plan")
                        emptyHintChip(icon: "cart", title: "Lista pojawi się sama")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.wmTileBg(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .padding(.bottom, pageBottomPadding)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(.container, edges: .top)
    }

    private func emptyHintChip(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.2)
                .lineLimit(1)
        }
        .foregroundStyle(Color.wmMuted(scheme))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.wmChipBg(scheme)))
    }

    // MARK: - Archived state
    //
    // No status card, no duplicated dates, no second eyebrow. The editorial
    // header already says "№ 18 · ZAKUPY TYGODNIA" and the title block stays
    // ("Produkty / na ten tydzień") for tab consistency. Closed-week status
    // and date are folded into a single centered rule (same pattern as the
    // Kalendarz's "W MENU" divider). Each archive row drops the redundant
    // date — they all belong to the viewed week — and shows just the folio,
    // revision label, and count.
    private var archivedState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                editorialHeader

                weekClosedRule
                    .padding(.horizontal, pageHorizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 18)

                if !currentWeekArchives.isEmpty {
                    archiveRowsContainer(currentWeekArchives)
                        .padding(.horizontal, 16)

                    deleteAllHistoryButton
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                }
            }
            .padding(.bottom, pageBottomPadding)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Archives that belong to the currently-viewed week — sorted by
    /// revision ascending so the displayed folios run 01 → 02 → 03 in
    /// the same direction as `Lista 1 → Lista 2 → Lista 3`. Without the
    /// ascending sort the folio counter went 01 / 02 / 03 while the
    /// revision label went Lista 3 / Lista 2 / Lista 1, which read as
    /// a numbering bug.
    private var currentWeekArchives: [ArchivedShoppingList] {
        let weekStart = datesViewModel.weekStartISO
        return shoppingListStore.archivedLists
            .filter { $0.weekStart == weekStart }
            .sorted { $0.revision < $1.revision }
    }

    /// Cross-week history feed — newest week first, then oldest revision
    /// first within each week (so revision folios still read ascending).
    private var sortedAllArchives: [ArchivedShoppingList] {
        shoppingListStore.archivedLists.sorted { lhs, rhs in
            if lhs.weekStart != rhs.weekStart {
                return lhs.weekStart > rhs.weekStart
            }
            return lhs.revision < rhs.revision
        }
    }

    /// Calendar-style centered rule: hairline — "27 KWI – 3 MAJ · ZAMKNIĘTE" —
    /// hairline. Carries both the week range and the closed-state status in
    /// one editorial element, eliminating the previous status card and date
    /// duplication.
    private var weekClosedRule: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.wmRule(scheme))
                .frame(height: 1)
                .frame(maxWidth: .infinity)

            Text("\(weekRangeText.uppercased()) · ZAMKNIĘTE")
                .font(.system(size: 9, weight: .bold))
                .tracking(2)
                .foregroundStyle(WMPalette.indigo)
                .lineLimit(1)
                .fixedSize()

            Rectangle()
                .fill(Color.wmRule(scheme))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helpers (empty / no-pending cards)

    private var compactEmptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "basket")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.wmMuted(scheme))

            Text("Brak aktywnej listy")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color.wmLabel(scheme))

            Text("Zapisz plan tygodniowy, aby wygenerować produkty.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.wmMuted(scheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
    }

    private var noPendingProductsCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(WMPalette.sage)

            Text("Brak nowych produktów do kupienia")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color.wmLabel(scheme))

            Text("Zmiany w planie nie dodały nowych zakupów na ten tydzień.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.wmMuted(scheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
    }

    // MARK: - Archive history (sheet + inline rows)
    //
    // Inline-on-archived state and the modal sheet share the same row
    // container (`archiveRowsContainer`) and destructive footer
    // (`deleteAllHistoryButton`). Folio numbers in each row mirror
    // `archive.revision` directly so they always line up with "Lista N".

    /// Rounded container with hairline separators between archive rows —
    /// mirrors `EditorialAisleSection`'s product-row card.
    private func archiveRowsContainer(_ archives: [ArchivedShoppingList]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(archives.enumerated()), id: \.element.id) { idx, archive in
                archiveRow(archive)

                if idx < archives.count - 1 {
                    Rectangle()
                        .fill(Color.wmRule(scheme))
                        .frame(height: 1)
                        .padding(.leading, 60)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Subtle, full-width red pill — same look as on the history sheet so
    /// the destructive affordance reads consistently across surfaces.
    private var deleteAllHistoryButton: some View {
        Button {
            showDeleteAllHistoryAlert = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                Text("Usuń całą historię")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(-0.1)
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.red.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Usuń całą historię")
    }

    private var historySheet: some View {
        ZStack {
            WMPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("HISTORIA LIST")
                                .font(.system(size: 10.5, weight: .bold))
                                .tracking(1.4)
                                .foregroundStyle(WMPalette.terracotta)
                            Text("Zamknięte listy")
                                .font(.system(size: 22, weight: .heavy))
                                .foregroundStyle(Color.wmLabel(scheme))
                        }
                        Spacer()
                        Button {
                            showHistorySheet = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.wmMuted(scheme))
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.wmChipBg(scheme)))
                        }
                        .buttonStyle(.plain)
                    }

                    if shoppingListStore.archivedLists.isEmpty {
                        Text("Brak zapisanych list.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.wmMuted(scheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        // Same hairline-row container as the inline section
                        // for visual continuity between the screen and sheet.
                        archiveRowsContainer(sortedAllArchives)

                        deleteAllHistoryButton
                            .padding(.top, 8)
                    }
                }
                .padding(20)
                .padding(.top, 12)
            }
        }
    }

    /// One archive row — single line, no date repetition (the date already
    /// lives in the week-closed rule above). Folio italic uses the actual
    /// revision number so it always matches the "Lista N" label, "Lista N"
    /// heavy label, count footnote. Tap on the folio+label opens the preview;
    /// trash icon at the right edge deletes this single entry.
    ///
    /// `weekLabel` is shown in muted footnote ONLY when the row's week
    /// differs from the viewed week — relevant for the cross-week history
    /// sheet.
    private func archiveRow(_ archive: ArchivedShoppingList) -> some View {
        let counts = shoppingListStore.archiveDisplayCounts(archiveId: archive.archiveId)
        // Folio mirrors the revision number directly so 01/02/03 always
        // line up with "Lista 1 / Lista 2 / Lista 3".
        let folio = archive.revision < 10
            ? String(format: "0%d", archive.revision)
            : "\(archive.revision)"
        let isCurrentWeek = archive.weekStart == datesViewModel.weekStartISO

        return HStack(alignment: .center, spacing: 14) {
            Button {
                previewArchiveId = archive.archiveId
                showHistorySheet = false
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    Text(folio)
                        .font(.system(size: 24, weight: .heavy))
                        .italic()
                        .tracking(-0.8)
                        .foregroundStyle(WMPalette.indigo.opacity(scheme == .dark ? 0.65 : 0.55))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()

                    VStack(alignment: .leading, spacing: 1) {
                        // Primary: "Lista 1 · 27/27 kupione"
                        HStack(spacing: 0) {
                            Text("Lista \(archive.revision)")
                                .font(.system(size: 15, weight: .heavy))
                                .tracking(-0.3)
                                .foregroundStyle(Color.wmLabel(scheme))

                            Text(verbatim: " · ")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.wmMuted(scheme))

                            Text("\(counts.bought)/\(counts.total) kupione")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.wmMuted(scheme))
                                .monospacedDigit()
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                        // Secondary (sheet only) — show date when it
                        // differs from the viewed week.
                        if !isCurrentWeek {
                            Text(archive.weekLabel)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.wmMuted(scheme).opacity(0.8))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pokaż listę \(archive.revision), \(archive.weekLabel)")

            HStack(spacing: 6) {
                archiveIconButton(
                    icon: "eye",
                    tint: Color.wmMuted(scheme),
                    fill: Color.wmChipBg(scheme),
                    label: "Pokaż listę \(archive.revision)"
                ) {
                    previewArchiveId = archive.archiveId
                    showHistorySheet = false
                }

                archiveIconButton(
                    icon: "trash",
                    tint: .red.opacity(0.85),
                    fill: Color.red.opacity(0.10),
                    label: "Usuń z historii"
                ) {
                    archivePendingDeletion = archive
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func archiveIconButton(
        icon: String,
        tint: Color,
        fill: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Archive preview sheet

    private func archivePreview(_ archive: ArchivedShoppingList) -> some View {
        ZStack {
            WMPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LISTA \(archive.revision)".uppercased())
                                .font(.system(size: 10.5, weight: .bold))
                                .tracking(1.4)
                                .foregroundStyle(WMPalette.terracotta)
                            Text(archive.weekLabel)
                                .font(.system(size: 22, weight: .heavy))
                                .foregroundStyle(Color.wmLabel(scheme))
                        }
                        Spacer()
                        Button {
                            previewArchiveId = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.wmMuted(scheme))
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.wmChipBg(scheme)))
                        }
                        .buttonStyle(.plain)
                    }

                    if groupedPreviewItemsByDepartment.isEmpty {
                        compactEmptyCard
                    } else {
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(Array(groupedPreviewItemsByDepartment.enumerated()), id: \.element.department) { idx, group in
                                EditorialAisleSection(
                                    index: idx + 1,
                                    title: group.department,
                                    icon: ProductConstants.departmentIcon(for: group.department),
                                    accent: ProductConstants.departmentColor(for: group.department),
                                    bought: group.items.filter(\.isChecked).count,
                                    total: group.items.count,
                                    items: group.items.map(asAisleItem),
                                    disableTaps: true,
                                    onToggle: nil
                                )
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.top, 12)
            }
        }
    }

    private var archiveDeleteAlertBinding: Binding<Bool> {
        Binding(
            get: { archivePendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    archivePendingDeletion = nil
                }
            }
        )
    }
}

// MARK: - Nav bar hit-test pass-through (shared with CalendarView)
//
// SwiftUI's `NavigationStack` keeps the toolbar layer "live" so the auto-blur
// material can fade in on scroll, but that layer also captures touches across
// its full ~44pt height — even when the toolbar is visually empty. That blocks
// the editorial header's icon buttons (search / history) once the layout
// extends under it via `.ignoresSafeArea(.container, edges: .top)`.
//
// We don't have any real toolbar items here (just the invisible 1×1 placeholder
// that keeps the bar from collapsing). Disabling user interaction on the
// underlying `UINavigationBar` lets touches fall through to the SwiftUI
// content below while leaving the auto-blur rendering intact.
private struct NavBarHitTestPassthrough: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        BarUnlocker()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class BarUnlocker: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.findNavigationBar()?.isUserInteractionEnabled = false
            }
        }

        private func findNavigationBar() -> UINavigationBar? {
            var responder: UIResponder? = self
            while let r = responder {
                if let vc = r as? UIViewController,
                   let bar = vc.navigationController?.navigationBar {
                    return bar
                }
                responder = r.next
            }
            return nil
        }
    }
}

#Preview {
    ProductsView()
}
