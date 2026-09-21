import Foundation
import Observation

/// Implementation detail of `ShoppingListStore.openRevisionsByWeek` — tracks
/// pending amount edits against a known archive baseline. Kept at file scope
/// (not nested) so the class declaration stays compact.
private struct OpenShoppingRevision {
    let baseArchiveId: String
    let pendingAmounts: [String: Double]
}

/// Per-household shopping list store. Companion types live alongside this file:
///   - `Models/ShoppingList/ShoppingListData.swift`        — ArchivedShoppingList, ShoppingListState
///   - `Networking/ShoppingList/ShoppingListProtocols.swift` — Repository / Transport
///   - `Networking/ShoppingList/BackendShoppingListDTOs.swift` — Backend DTOs + DTO->domain mapping
///   - `Networking/ShoppingList/WebSocketShoppingListTransportClient.swift`
///   - `Networking/ShoppingList/ApiShoppingListRepository.swift`
@MainActor
@Observable
final class ShoppingListStore {
    private struct ShoppingListCachePayload: Codable {
        let weeks: [String: ShoppingListState]
    }

    private let repository: ShoppingListRepository
    private let currentUserId: String
    private let cacheNamespace: String
    private(set) var items: [ShoppingItem] = []
    private(set) var weekStart: String?
    private(set) var archivedLists: [ArchivedShoppingList] = []
    private(set) var isBatchUpdating: Bool = false
    private var pendingReloadTask: Task<Void, Never>?
    private var lastChangeVersionByWeek: [String: Int64] = [:]
    private var openRevisionsByWeek: [String: OpenShoppingRevision] = [:]
    private var cachedStateByWeek: [String: ShoppingListState] = [:]
    private var invalidatedWeeks: Set<String> = []
    private var pendingArchiveWeekLabel: String?
    private var isReconcilingPendingChecks: Bool = false
    private var pendingResetProductKeys: Set<String> = []
    private var pendingToggleTasks: [String: Task<Void, Never>] = [:]
    private var pendingToggleOriginalState: [String: Bool] = [:]
    /// Klucze produktów, których `setChecked` właśnie leci do serwera.
    /// Wpis w `pendingToggleTasks` znika z chwilą odpalenia requestu, więc
    /// bez tego zbioru `apply()` przez cały round-trip mógł nadpisać
    /// optymistyczny ptaszek stanem z serwera, który o tapnięciu jeszcze
    /// nie wie — checkbox „mrugał".
    private var inFlightToggleKeys: Set<String> = []
    var isLoading: Bool = false
    var errorMessage: String?

    private var cacheURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("shopping_list_cache_\(cacheNamespace).json")
    }

    /// Usunięcie konta / wylogowanie: lista z dysku nie zostaje (art. 17).
    static func clearCache() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix("shopping_list_cache_") && name.hasSuffix(".json") {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    init(repository: ShoppingListRepository, currentUserId: String = "", cacheNamespace: String = "default") {
        self.repository = repository
        self.currentUserId = currentUserId
        self.cacheNamespace = Self.sanitizedCacheNamespace(cacheNamespace)
        loadPersistedCache()
        self.repository.observeShoppingListChanges { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                guard let currentWeekStart = self.weekStart else { return }
                guard !self.isMutatingState else { return }
                guard event.weekStart == currentWeekStart else {
                    return
                }
                // Serwer rozsyła zmianę do WSZYSTKICH klientów, także do autora.
                // Własne echo nie wnosi nic nowego (stan lokalny jest już
                // optymistycznie zaktualizowany i potwierdzony ACK-iem), a każde
                // powodowało pełny refetch i podmianę tablicy `items` ~0,5 s po
                // tapnięciu — z zewnątrz wyglądało to jak „skacząca" lista.
                if let changedBy = event.changedByUserId,
                   !self.currentUserId.isEmpty,
                   changedBy == self.currentUserId {
                    return
                }
                if let changeVersion = event.changeVersion {
                    let previous = self.lastChangeVersionByWeek[currentWeekStart] ?? 0
                    guard changeVersion > previous else { return }
                    self.lastChangeVersionByWeek[currentWeekStart] = changeVersion
                }
                self.invalidatedWeeks.insert(currentWeekStart)
                self.scheduleReload(weekStart: currentWeekStart)
                let changedByOtherUser = event.changedByUserId != nil && event.changedByUserId != self.currentUserId
                if changedByOtherUser {
                    PlanChangeNotificationService.notifyRemoteShoppingListChange(
                        action: event.action,
                        householdId: event.householdId,
                        changedByDisplayName: event.changedByDisplayName,
                        isChecked: event.isChecked
                    )
                }
            }
        }
        self.repository.observeRealtimeReconnect { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard let currentWeekStart = self.weekStart else { return }
                guard !self.isMutatingState else { return }
                self.invalidatedWeeks.insert(currentWeekStart)
                self.scheduleReload(weekStart: currentWeekStart)
            }
        }
    }

    private var isMutatingState: Bool {
        isBatchUpdating || isReconcilingPendingChecks
    }

    func load(weekStart: String, force: Bool = false) async {
        errorMessage = nil
        self.weekStart = weekStart

        // `!isLoading` także w gałęzi cache: gdy trwa fetch sieciowy, zapis
        // z cache mógłby zaaplikować się PO świeżym stanie z serwera i cofnąć
        // listę do starej zawartości na jedną klatkę — fetch i tak zaraz
        // dostarczy nowsze dane.
        if !force,
           !isLoading,
           let cachedState = cachedStateByWeek[weekStart],
           !invalidatedWeeks.contains(weekStart) {
            await apply(state: cachedState, for: weekStart)
            return
        }

        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            let state = try await repository.fetchShoppingListState(weekStart: weekStart)
            await apply(state: state, for: weekStart)
            invalidatedWeeks.remove(weekStart)
        } catch {
            errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
            if let cachedState = cachedStateByWeek[weekStart] {
                await apply(state: cachedState, for: weekStart)
            }
        }
    }

    func refreshCurrentWeek() {
        guard let weekStart else { return }
        invalidatedWeeks.insert(weekStart)
        scheduleReload(weekStart: weekStart)
    }

    var isArchivePendingAfterBatch: Bool {
        pendingArchiveWeekLabel != nil
    }

    func markAllChecked() {
        guard let weekStart else { return }
        guard !isBatchUpdating else { return }

        let uncheckedItems = items.filter { !$0.isChecked }
        guard !uncheckedItems.isEmpty else { return }

        pendingResetProductKeys.removeAll()
        for task in pendingToggleTasks.values { task.cancel() }
        pendingToggleTasks.removeAll()
        pendingToggleOriginalState.removeAll()
        let originalItems = items
        isBatchUpdating = true
        for index in items.indices {
            items[index].isChecked = true
        }
        cacheCurrentState(for: weekStart)

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncMarkAllChecked(
                weekStart: weekStart,
                uncheckedItems: uncheckedItems,
                originalItems: originalItems
            )
        }
    }

    func toggleChecked(_ item: ShoppingItem) async {
        guard !isBatchUpdating else { return }
        guard let index = items.firstIndex(where: { $0.productKey == item.productKey }),
              let weekStart else { return }

        pendingResetProductKeys.remove(item.productKey)
        let productKey = item.productKey
        let previous = items[index].isChecked
        let next = !previous
        items[index].isChecked = next
        cacheCurrentState(for: weekStart)

        if pendingToggleTasks[productKey] == nil {
            pendingToggleOriginalState[productKey] = previous
        }
        pendingToggleTasks[productKey]?.cancel()

        pendingToggleTasks[productKey] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled else { return }

            let originalState = self.pendingToggleOriginalState[productKey] ?? previous
            self.pendingToggleTasks[productKey] = nil
            self.pendingToggleOriginalState[productKey] = nil

            guard let finalIndex = self.items.firstIndex(where: { $0.productKey == productKey }) else { return }
            let finalState = self.items[finalIndex].isChecked

            if finalState == originalState { return }

            self.inFlightToggleKeys.insert(productKey)
            defer { self.inFlightToggleKeys.remove(productKey) }
            do {
                try await self.repository.setChecked(weekStart: weekStart, productKey: productKey, isChecked: finalState)
            } catch {
                if let rollbackIndex = self.items.firstIndex(where: { $0.productKey == productKey }) {
                    self.items[rollbackIndex].isChecked = originalState
                    self.cacheCurrentState(for: weekStart)
                }
                self.errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
            }
        }
    }

    /// „Brakuje mi” ze szczegółu przepisu — dopisuje składniki do listy
    /// tygodnia `weekStart` i zwraca, ile produktów na nią trafiło.
    ///
    /// Rzuca, zamiast pisać do `errorMessage`: błąd pokazuje ekran przepisu
    /// przy przycisku, który trzeba nacisnąć jeszcze raz, a nie toast listy.
    /// Własne echo zmiany serwer odbija do nas, ale store je ignoruje (patrz
    /// `init`), więc tydzień przeładowujemy tu sami.
    func addRecipeExtras(
        weekStart: String,
        recipeId: String,
        servings: Int,
        ingredientIds: [String]
    ) async throws -> Int {
        let added = try await repository.addRecipeExtras(
            weekStart: weekStart,
            recipeId: recipeId,
            servings: servings,
            ingredientIds: ingredientIds
        )
        invalidatedWeeks.insert(weekStart)
        if self.weekStart == weekStart {
            scheduleReload(weekStart: weekStart)
        }
        return added
    }

    /// Zdejmuje z listy DOPISANĄ część produktu. To, co wniósł plan, zostaje —
    /// wiersz znika tylko wtedy, gdy nic poza dopisanym go nie trzymało.
    func removeExtra(_ item: ShoppingItem) async {
        guard let weekStart, item.hasAddedPart else { return }
        do {
            try await repository.removeExtra(weekStart: weekStart, productKey: item.productKey)
            invalidatedWeeks.insert(weekStart)
            scheduleReload(weekStart: weekStart)
        } catch {
            errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
        }
    }

    func archiveCurrentList(weekLabel: String) {
        guard let weekStart,
              !items.isEmpty,
              items.allSatisfy(\.isChecked)
        else { return }
        if isBatchUpdating {
            pendingArchiveWeekLabel = weekLabel
            return
        }
        Task {
            do {
                try await repository.archiveShoppingList(weekStart: weekStart, weekLabel: weekLabel)
                openRevisionsByWeek.removeValue(forKey: weekStart)
                await load(weekStart: weekStart, force: true)
            } catch {
                errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
            }
        }
    }

    func deleteArchivedList(archiveId: String) {
        guard let currentWeekStart = weekStart else { return }
        Task {
            do {
                let deletedArchiveIds = Set(
                    archivedLists
                        .filter { $0.archiveId == archiveId }
                        .map(\.archiveId)
                )
                try await repository.deleteArchivedList(archiveId: archiveId)
                if !deletedArchiveIds.isEmpty {
                    openRevisionsByWeek = openRevisionsByWeek.filter { !deletedArchiveIds.contains($0.value.baseArchiveId) }
                }
                await load(weekStart: currentWeekStart, force: true)
            } catch {
                errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
            }
        }
    }

    /// Oddaje, czy historia naprawdę zniknęła.
    ///
    /// Wcześniej metoda otwierała własne zadanie i nie mówiła nic — sukcesu
    /// nie dało się odróżnić od awarii, a to operacja nieodwracalna i wspólna
    /// dla całego domu.
    @discardableResult
    func deleteAllArchivedLists() async -> Bool {
        guard let currentWeekStart = weekStart else { return false }
        do {
            try await repository.deleteAllArchivedLists(weekStart: currentWeekStart)
            openRevisionsByWeek.removeAll()
            await load(weekStart: currentWeekStart, force: true)
            return true
        } catch {
            errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
            return false
        }
    }

    func currentClosedArchive(for weekStart: String) -> ArchivedShoppingList? {
        archivedLists.first { $0.weekStart == weekStart && $0.isCurrentClosed }
    }

    func archiveDisplayItems(archiveId: String) -> [ShoppingItem] {
        guard let archive = archivedLists.first(where: { $0.archiveId == archiveId }) else {
            return []
        }

        guard let previousArchive = previousArchive(for: archive) else {
            return archive.items
        }

        return makePendingItems(currentItems: archive.items, archivedItems: previousArchive.items)
    }

    func archiveDisplayCounts(archiveId: String) -> (bought: Int, total: Int) {
        let items = archiveDisplayItems(archiveId: archiveId)
        return (items.filter(\.isChecked).count, items.count)
    }

    func hasOpenRevision(for weekStart: String) -> Bool {
        guard self.weekStart == weekStart,
              let archive = currentClosedArchive(for: weekStart)
        else {
            return false
        }

        return itemSignature(for: items) != itemSignature(for: archive.items)
    }

    func pendingItems(for weekStart: String) -> [ShoppingItem] {
        guard self.weekStart == weekStart,
              let archive = currentClosedArchive(for: weekStart)
        else {
            return items
        }

        return makePendingItems(currentItems: items, archivedItems: archive.items)
    }

    /// Produkty widoczne na aktywnej liście tygodnia — to, co użytkownik
    /// jeszcze może kupić.
    ///
    /// Po zamknięciu listy i zmianie planu zostają wyłącznie pozycje dołożone
    /// przez tę zmianę: dokupione wcześniej rzeczy są już w domu i nie mają
    /// prawa wracać na listę.
    func activeItems(for weekStart: String) -> [ShoppingItem] {
        hasOpenRevision(for: weekStart) ? pendingItems(for: weekStart) : items
    }

    /// Ile produktów zostało do kupienia w tym tygodniu.
    ///
    /// Z tej liczby żyje plakietka przy koszyku w nagłówku Planu tygodnia.
    /// Lista zakupów jest arkuszem, a nie zakładką, więc bez niej stan
    /// zakupów widać dopiero po otwarciu arkusza. Tydzień zamknięty bez
    /// otwartej rewizji nie ma już czego kupować — plakietka gaśnie.
    func remainingCount(for weekStart: String) -> Int {
        guard self.weekStart == weekStart else { return 0 }

        let openRevision = hasOpenRevision(for: weekStart)
        if currentClosedArchive(for: weekStart) != nil, !openRevision {
            return 0
        }

        return activeItems(for: weekStart).filter { !$0.isChecked }.count
    }

    private func scheduleReload(weekStart: String) {
        pendingReloadTask?.cancel()
        pendingReloadTask = Task { @MainActor [weak self] in
            // Anulowany debounce NIE startuje ładowania — `try?` połykał
            // anulowanie, a anulowane zadanie ładowało listę dalej, aż
            // pierwszy rzucający `await` w środku kończył się
            // `CancellationError` pokazanym jako awaria.
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            guard let self else { return }
            await self.load(weekStart: weekStart, force: true)
        }
    }

    private func syncMarkAllChecked(
        weekStart: String,
        uncheckedItems: [ShoppingItem],
        originalItems: [ShoppingItem]
    ) async {
        do {
            for item in uncheckedItems {
                try await repository.setChecked(
                    weekStart: weekStart,
                    productKey: item.productKey,
                    isChecked: true
                )
            }

            let pendingArchiveLabel = pendingArchiveWeekLabel
            pendingArchiveWeekLabel = nil
            isBatchUpdating = false

            if let pendingArchiveLabel {
                try await repository.archiveShoppingList(weekStart: weekStart, weekLabel: pendingArchiveLabel)
                openRevisionsByWeek.removeValue(forKey: weekStart)
            }

            await load(weekStart: weekStart, force: true)
        } catch {
            pendingArchiveWeekLabel = nil
            isBatchUpdating = false
            items = originalItems
            cacheCurrentState(for: weekStart)
            errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
        }
    }

    private func apply(state: ShoppingListState, for weekStart: String) async {
        archivedLists = state.archives
        let pendingKeys = Set(pendingToggleTasks.keys).union(inFlightToggleKeys)
        if pendingKeys.isEmpty {
            items = state.items
        } else {
            // Zachowaj optymistyczne isChecked dla itemów z aktywnym debouncem —
            // serwer jeszcze nie wie o tapnięciu, wiec nie nadpisujemy lokalnego stanu.
            let localCheckedByKey = Dictionary(
                uniqueKeysWithValues: items.map { ($0.productKey, $0.isChecked) }
            )
            items = state.items.map { serverItem in
                guard pendingKeys.contains(serverItem.productKey),
                      let localChecked = localCheckedByKey[serverItem.productKey]
                else { return serverItem }
                var merged = serverItem
                merged.isChecked = localChecked
                return merged
            }
        }
        await syncPendingItemCheckState(for: weekStart, currentItems: state.items)
        cacheCurrentState(for: weekStart)
    }

    private func cacheCurrentState(for weekStart: String) {
        cachedStateByWeek[weekStart] = ShoppingListState(items: items, archives: archivedLists)
        persistCache()
    }

    private func loadPersistedCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let payload = try? JSONDecoder().decode(ShoppingListCachePayload.self, from: data) else {
            return
        }

        cachedStateByWeek = payload.weeks
    }

    /// Jedna kolejka seryjna na wszystkie zapisy — gwarantuje kolejność
    /// (ostatni snapshot wygrywa), czego `Task.detached` by nie dał.
    private static let cacheWriteQueue = DispatchQueue(
        label: "shopping-list-cache-write",
        qos: .utility
    )

    private func persistCache() {
        // Encode + zapis pliku poza main threadem: wołane przy KAŻDYM tapnięciu
        // i każdym loadzie, a przy dłuższej liście serializacja wszystkich
        // tygodni synchronicznie na MainActorze gubiła klatki dokładnie
        // w trakcie ładowania i scrollowania.
        let payload = ShoppingListCachePayload(weeks: cachedStateByWeek)
        let url = cacheURL
        Self.cacheWriteQueue.async {
            guard let data = try? JSONEncoder().encode(payload) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func sanitizedCacheNamespace(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let sanitized = String(scalars)
        return sanitized.isEmpty ? "default" : sanitized
    }

    private func syncPendingItemCheckState(for weekStart: String, currentItems: [ShoppingItem]) async {
        guard let archive = currentClosedArchive(for: weekStart) else {
            openRevisionsByWeek.removeValue(forKey: weekStart)
            return
        }

        guard itemSignature(for: currentItems) != itemSignature(for: archive.items) else {
            openRevisionsByWeek.removeValue(forKey: weekStart)
            return
        }

        let pendingItems = makePendingItems(currentItems: currentItems, archivedItems: archive.items)
        let pendingAmounts = Dictionary(uniqueKeysWithValues: pendingItems.map { ($0.productKey, $0.totalAmount) })
        let previousState = openRevisionsByWeek[weekStart].flatMap { state in
            state.baseArchiveId == archive.id ? state : nil
        }

        let checkedPendingItems = items.filter { item in
            guard let pendingAmount = pendingAmounts[item.productKey], item.isChecked else {
                return false
            }

            guard let previousAmount = previousState?.pendingAmounts[item.productKey] else {
                return true
            }

            return pendingAmount > previousAmount + 0.000_001
        }

        if !checkedPendingItems.isEmpty {
            let keysToReset = Set(checkedPendingItems.map(\.productKey))
            pendingResetProductKeys.formUnion(keysToReset)
            isReconcilingPendingChecks = true

            for index in items.indices where keysToReset.contains(items[index].productKey) {
                items[index].isChecked = false
            }
            cacheCurrentState(for: weekStart)

            do {
                for item in checkedPendingItems {
                    guard pendingResetProductKeys.contains(item.productKey) else {
                        continue
                    }
                    try await repository.setChecked(
                        weekStart: weekStart,
                        productKey: item.productKey,
                        isChecked: false
                    )
                    pendingResetProductKeys.remove(item.productKey)
                }
            } catch {
                errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
                invalidatedWeeks.insert(weekStart)
            }
            pendingResetProductKeys.subtract(keysToReset)
            isReconcilingPendingChecks = false
            if invalidatedWeeks.contains(weekStart) {
                scheduleReload(weekStart: weekStart)
            }
        }

        openRevisionsByWeek[weekStart] = OpenShoppingRevision(
            baseArchiveId: archive.id,
            pendingAmounts: pendingAmounts
        )
    }

    private func makePendingItems(currentItems: [ShoppingItem], archivedItems: [ShoppingItem]) -> [ShoppingItem] {
        let archivedByKey = Dictionary(uniqueKeysWithValues: archivedItems.map { ($0.productKey, $0) })

        return currentItems.compactMap { currentItem in
            guard let archivedItem = archivedByKey[currentItem.productKey] else {
                return currentItem
            }

            let additionalAmount = currentItem.totalAmount - archivedItem.totalAmount
            guard additionalAmount > 0.000_001 else {
                return nil
            }

            var pendingItem = currentItem
            pendingItem.totalAmount = additionalAmount
            return pendingItem
        }
    }

    private func previousArchive(for archive: ArchivedShoppingList) -> ArchivedShoppingList? {
        archivedLists
            .filter { candidate in
                candidate.weekStart == archive.weekStart && candidate.revision < archive.revision
            }
            .max { lhs, rhs in
                lhs.revision < rhs.revision
            }
    }

    private func itemSignature(for items: [ShoppingItem]) -> [String] {
        items
            .map {
                [
                    $0.productKey,
                    String(format: "%.6f", $0.totalAmount),
                    $0.unit,
                    $0.department,
                    $0.name
                ].joined(separator: "|")
            }
            .sorted()
    }
}
