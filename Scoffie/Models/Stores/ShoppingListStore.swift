import Foundation
import Observation

/// Implementation detail of `ShoppingListStore.openRevisionsByWeek` — tracks
/// pending amount edits against a known archive baseline. Kept at file scope
/// (not nested) so the class declaration stays compact.
///
/// Zapisywany w pliku listy razem z tygodniami (jak `revisions` na Androidzie):
/// bez niego po restarcie każda kupiona pozycja otwartej rewizji wyglądała
/// jak „nowa” i store odznaczał ją NA SERWERZE.
private struct OpenShoppingRevision: Codable {
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
        /// Znane stany otwartych rewizji. Opcjonalne: plik zapisany przez
        /// starszą wersję aplikacji nie ma tego pola i dalej się wczytuje.
        let revisions: [String: OpenShoppingRevision]?
    }

    /// Katalog produktów na dysku — wspólny dla wszystkich kont (to nie są
    /// dane osoby, tylko katalog Scoffie), z rewizją serwera.
    private struct ProductCatalogCachePayload: Codable {
        let revision: String
        let products: [ShoppingProduct]
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
    /// Tydzień, który właśnie pobiera `load`.
    private var loadingWeekStart: String?
    /// Tydzień, którego przeładowanie zamówiono, gdy `load` już trwało —
    /// wykona się po nim, zamiast przepaść (patrz `load`).
    private var reloadRequestedDuringLoad: String?
    var isLoading: Bool = false
    var errorMessage: String?

    /// Ostatnio dopisywane w domu (arkusz „Dodaj produkty”) — z ostatniego
    /// stanu listy, ze wszystkich tygodni.
    private(set) var recentProducts: [ShoppingRecentProduct] = []
    /// Katalog produktów do dopisania — z pliku od razu, z serwera w tle.
    private(set) var productCatalog: [ShoppingProduct] = []
    /// Złożone nazwy katalogu do szukania — liczone raz na katalog.
    private(set) var productSearchIndex = ShoppingProductSearch.Index([])
    private var productCatalogRevision: String?
    private var productCatalogFetchedAt: Date?
    private var productCatalogTask: Task<Void, Never>?

    private static var productCatalogURL: URL {
        AppCacheDirectory.url(for: "shopping_products_v1.json")
    }

    /// 7.10.2026 (audyt 2.5): katalog offline poza kopią zapasową, nie
    /// `Documents` — stare pliki przenosi `AppCacheDirectory`.
    private var cacheURL: URL {
        AppCacheDirectory.url(for: "shopping_list_cache_\(cacheNamespace).json")
    }

    /// Usunięcie konta / wylogowanie: lista z dysku nie zostaje (art. 17).
    /// Także ze starego `Documents` (7.10.2026), gdyby migracja go nie przeniosła.
    static func clearCache() {
        AppCacheDirectory.removeFiles { $0.hasPrefix("shopping_list_cache_") && $0.hasSuffix(".json") }
    }

    init(repository: ShoppingListRepository, currentUserId: String = "", cacheNamespace: String = "default") {
        self.repository = repository
        self.currentUserId = currentUserId
        self.cacheNamespace = Self.sanitizedCacheNamespace(cacheNamespace)
        loadPersistedCache()
        self.repository.observeShoppingListChanges { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                // Serwer rozsyła zmianę do WSZYSTKICH klientów, także do autora.
                // Echo odhaczenia, które ten ekran już pokazuje, nie wnosi nic
                // nowego, a pełny refetch ~0,5 s po tapnięciu wyglądał jak
                // „skacząca" lista — tylko ono jest pomijane (patrz niżej).
                if self.isEchoOfLocalChange(event) {
                    return
                }
                // Cache tygodnia, którego akurat nie widać, też jest już
                // nieaktualny — bez tego wejście na niego podawało listę
                // sprzed zmiany (asystent planował przyszły tydzień, a ekran
                // stał na bieżącym).
                self.invalidatedWeeks.insert(event.weekStart)
                guard let currentWeekStart = self.weekStart,
                      event.weekStart == currentWeekStart
                else { return }
                guard !self.isMutatingState else { return }
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

    /// Czy zdarzenie z serwera to odbicie odhaczenia, które ten ekran już ma.
    ///
    /// Dotąd store odrzucał KAŻDE zdarzenie, którego autorem był zalogowany
    /// użytkownik. Ale tym samym użytkownikiem piszą też inne ekrany i
    /// asystent: zapis tygodnia z propozycji (`APPLY_WEEK`), dodanie dania
    /// w kalendarzu, odhaczanie zakupów z rozmowy. Po zaplanowaniu tygodnia
    /// z asystentem lista stała więc pusta, dopóki ktoś nie zamknął i nie
    /// otworzył arkusza (zgłoszenie z 22.09.2026).
    ///
    /// Echem jest wyłącznie `SET_ITEM_CHECKED` na widocznym tygodniu, które
    /// albo właśnie wysyłamy (debounce / request w locie), albo już mamy na
    /// ekranie w tym samym stanie. Odhaczenie asystenta ma na ekranie stan
    /// odwrotny — więc przeładowuje listę. Każda inna akcja przeładowuje ją
    /// zawsze: te, które robi sam store (archiwum, dopisane), i tak kończą
    /// się przeładowaniem, a debounce `scheduleReload` skleja je w jedno.
    private func isEchoOfLocalChange(_ event: BackendShoppingListChangedDTO) -> Bool {
        guard event.action == "SET_ITEM_CHECKED",
              let changedBy = event.changedByUserId,
              !currentUserId.isEmpty,
              changedBy == currentUserId,
              event.weekStart == weekStart,
              let productKey = event.productKey
        else { return false }

        if pendingToggleTasks[productKey] != nil || inFlightToggleKeys.contains(productKey) {
            return true
        }
        guard let isChecked = event.isChecked,
              let local = items.first(where: { $0.productKey == productKey })
        else { return false }
        return local.isChecked == isChecked
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

        guard !isLoading else {
            // Dotąd to żądanie odbijało się tu bez śladu: wymuszone
            // przeładowanie (po zmianie planu, po archiwizacji) przepadało,
            // gdy trwało pobranie, które mogło wyjść z serwera PRZED zmianą —
            // a inny tydzień nie ładował się wcale.
            if force || loadingWeekStart != weekStart {
                reloadRequestedDuringLoad = weekStart
            }
            return
        }

        isLoading = true
        loadingWeekStart = weekStart
        reloadRequestedDuringLoad = nil
        // Ten tydzień pobieramy właśnie teraz. Jeśli coś unieważni go jeszcze
        // raz w trakcie (zdarzenie z serwera, zapis asystenta), po powrocie
        // będzie z powrotem w `invalidatedWeeks` — i pobierzemy go ponownie,
        // zamiast zdjąć flagę pobraniem sprzed zmiany.
        invalidatedWeeks.remove(weekStart)
        var fetched = false
        do {
            let state = try await repository.fetchShoppingListState(weekStart: weekStart)
            fetched = true
            if self.weekStart == weekStart {
                await apply(state: state, for: weekStart)
            } else {
                // Ekran przeszedł w tym czasie na inny tydzień — ten stan
                // idzie tylko do cache, nie na ekran cudzego tygodnia.
                cachedStateByWeek[weekStart] = state
                persistCache()
            }
        } catch {
            // Nadal nieaktualny: następne wejście ma pytać serwer, nie cache.
            // Bez automatycznego ponowienia — bez sieci kręciłoby się w kółko.
            invalidatedWeeks.insert(weekStart)
            errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
            if self.weekStart == weekStart, let cachedState = cachedStateByWeek[weekStart] {
                await apply(state: cachedState, for: weekStart)
            }
        }
        isLoading = false
        loadingWeekStart = nil

        var weekToReload = reloadRequestedDuringLoad
        reloadRequestedDuringLoad = nil
        if weekToReload == nil, fetched, invalidatedWeeks.contains(weekStart) {
            weekToReload = weekStart
        }
        if let weekToReload {
            invalidatedWeeks.insert(weekToReload)
            if self.weekStart == weekToReload {
                scheduleReload(weekStart: weekToReload)
            }
        }
    }

    func refreshCurrentWeek() {
        guard let weekStart else { return }
        invalidatedWeeks.insert(weekStart)
        scheduleReload(weekStart: weekStart)
    }

    /// Plan zmienił się poza tym store'em i nie wiadomo, którego tygodnia to
    /// dotyczy (asystent planuje też przyszły tydzień): widoczny tydzień
    /// przeładowuje się od razu, a każdy z cache — przy pierwszym wejściu.
    func invalidateAllWeeks() {
        invalidatedWeeks.formUnion(cachedStateByWeek.keys)
        refreshCurrentWeek()
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
        isBatchUpdating = true
        for index in items.indices {
            items[index].isChecked = true
        }
        cacheCurrentState(for: weekStart)

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncMarkAllChecked(
                weekStart: weekStart,
                uncheckedItems: uncheckedItems
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

    /// Zdejmuje z listy DOPISANĄ część produktu (z przepisów i ręczną). To,
    /// co wniósł plan, zostaje — wiersz znika tylko wtedy, gdy nic poza
    /// dopisanym go nie trzymało. Oddaje, czy się udało (toast ekranu).
    @discardableResult
    func removeExtra(_ item: ShoppingItem) async -> Bool {
        guard let weekStart, item.hasAddedPart else { return false }
        let removalKey = Self.removalKey(weekStart: weekStart, productKey: item.productKey)
        do {
            try await repository.removeExtra(weekStart: weekStart, productKey: item.productKey)
            optimisticallyRemoved[removalKey] = nil
            invalidatedWeeks.insert(weekStart)
            scheduleReload(weekStart: weekStart)
            return true
        } catch {
            // Zapis padł — zdjęty od razu wiersz wraca: na ekran, gdy to wciąż
            // ten tydzień, i do kopii tygodnia na dysku (odhaczenie w trakcie
            // usuwania zapisało ją już BEZ niego). Tydzień i tak idzie do
            // ponownego odczytu z serwera (Codex, 16.10.2026).
            if let hidden = optimisticallyRemoved.removeValue(forKey: removalKey) {
                restoreHiddenRow(hidden)
            }
            invalidatedWeeks.insert(weekStart)
            if self.weekStart == weekStart {
                scheduleReload(weekStart: weekStart)
            }
            errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
            return false
        }
    }

    /// Wiersz zdjęty z ekranu, zanim serwer potwierdził (`hideRemovedRow`).
    /// Klucz = tydzień + produkt: w trakcie zapisu można przejść na inny
    /// tydzień, a ten sam produkt bywa na obu listach.
    private struct HiddenRow {
        let weekStart: String
        let item: ShoppingItem
        let index: Int
    }

    private var optimisticallyRemoved: [String: HiddenRow] = [:]

    private static func removalKey(weekStart: String, productKey: String) -> String {
        "\(weekStart)|\(productKey)"
    }

    /// Przesunięcie w lewo → „Usuń” na wierszu, który istnieje TYLKO dzięki
    /// dopisaniu: wiersz znika od razu (ekran woła to w `withAnimation`),
    /// a `removeExtra` przywraca go, gdy zapis padnie. Wiersz z częścią
    /// z planu zostaje — schodzi z niego tylko dopisane, po przeładowaniu.
    func hideRemovedRow(_ item: ShoppingItem) {
        guard let weekStart,
              item.isOnlyManual,
              let index = items.firstIndex(where: { $0.productKey == item.productKey })
        else { return }
        optimisticallyRemoved[Self.removalKey(weekStart: weekStart, productKey: item.productKey)] =
            HiddenRow(weekStart: weekStart, item: items[index], index: index)
        items.remove(at: index)
    }

    private func restoreHiddenRow(_ hidden: HiddenRow) {
        let key = hidden.item.productKey
        if self.weekStart == hidden.weekStart {
            if !items.contains(where: { $0.productKey == key }) {
                items.insert(hidden.item, at: min(hidden.index, items.count))
            }
            cacheCurrentState(for: hidden.weekStart)
            return
        }
        // Ekran stoi już na innym tygodniu — naprawiamy tylko kopię tamtego.
        guard let cached = cachedStateByWeek[hidden.weekStart],
              !cached.items.contains(where: { $0.productKey == key })
        else { return }
        var items = cached.items
        items.insert(hidden.item, at: min(hidden.index, items.count))
        cachedStateByWeek[hidden.weekStart] = ShoppingListState(
            items: items,
            archives: cached.archives,
            recentProducts: cached.recentProducts
        )
        persistCache()
    }

    // MARK: - Dopisywanie produktów (arkusz „Dodaj produkty”)

    /// Katalog produktów: najpierw z pliku (od razu, także bez sieci), potem
    /// z serwera z rewizją, którą mamy — zmieniony przychodzi cały, a ten sam
    /// nie przychodzi wcale. Z serwera najwyżej raz na 10 minut.
    func loadProductCatalog() async {
        if productCatalog.isEmpty { restoreProductCatalog() }
        if let running = productCatalogTask {
            await running.value
            return
        }
        if let fetchedAt = productCatalogFetchedAt, Date().timeIntervalSince(fetchedAt) < 600 {
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await self.repository.fetchProductCatalog(revision: self.productCatalogRevision)
                self.productCatalogFetchedAt = Date()
                if let products = result.products {
                    self.setProductCatalog(products, revision: result.revision)
                    self.persistProductCatalog()
                }
            } catch {
                // Cicho: zostaje katalog z pliku, a bez niego arkusz ma
                // jeszcze „Ostatnio dodawane” i własne nazwy.
            }
        }
        productCatalogTask = task
        await task.value
        productCatalogTask = nil
    }

    /// Dopisuje wybrane produkty do OGLĄDANEGO tygodnia i od razu przeładowuje
    /// listę — po powrocie z arkusza mają już na niej stać. Rzuca: błąd
    /// pokazuje arkusz, a wybór zostaje do ponowienia.
    @discardableResult
    func addProducts(_ drafts: [ShoppingProductDraft], mutationId: UUID) async throws -> Int {
        guard !drafts.isEmpty else { return 0 }
        guard let weekStart else {
            // Bez wczytanego tygodnia nie ma do czego dopisać — błąd zostawia
            // wybór na ekranie, zamiast udawać „Dopisano”.
            throw RecipeDataError.serverError(message: "Lista zakupów jeszcze się nie wczytała.")
        }
        let added = try await repository.addProducts(weekStart: weekStart, drafts: drafts, mutationId: mutationId)
        invalidatedWeeks.insert(weekStart)
        await load(weekStart: weekStart, force: true)
        return added
    }

    /// Nowa ilość dopisanej ręcznie części wiersza (`nil` = bez ilości).
    func setManualAmount(_ item: ShoppingItem, amount: ShoppingAmount?) async throws {
        guard let weekStart, item.manual != nil else { return }
        try await repository.setProductAmount(weekStart: weekStart, productKey: item.productKey, amount: amount)
        invalidatedWeeks.insert(weekStart)
        await load(weekStart: weekStart, force: true)
    }

    private func setProductCatalog(_ products: [ShoppingProduct], revision: String) {
        productCatalog = products
        productCatalogRevision = revision
        rebuildProductSearchIndex()
    }

    /// Własne nazwy domu z „ostatnio dodawanych” — w szukaniu tak jak katalog.
    var householdProducts: [ShoppingProduct] {
        var seen = Set(productCatalog.map(\.nameKey))
        return recentProducts.compactMap { recent in
            guard recent.ingredientId == nil else { return nil }
            let product = ShoppingProduct(
                name: recent.name,
                department: recent.department,
                ingredientId: nil,
                pieceOnly: false,
                aliases: []
            )
            return seen.insert(product.nameKey).inserted ? product : nil
        }
    }

    /// Indeks szukania: katalog i własne nazwy domu, złożone raz.
    private func rebuildProductSearchIndex() {
        productSearchIndex = ShoppingProductSearch.Index(productCatalog + householdProducts)
    }

    private func restoreProductCatalog() {
        guard let data = try? Data(contentsOf: Self.productCatalogURL),
              let payload = try? JSONDecoder().decode(ProductCatalogCachePayload.self, from: data),
              !payload.products.isEmpty
        else { return }
        setProductCatalog(payload.products, revision: payload.revision)
    }

    private func persistProductCatalog() {
        guard let revision = productCatalogRevision else { return }
        let payload = ProductCatalogCachePayload(revision: revision, products: productCatalog)
        let url = Self.productCatalogURL
        Self.cacheWriteQueue.async {
            guard let data = try? JSONEncoder().encode(payload) else { return }
            try? data.write(to: url, options: .atomic)
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
            || !rerequestedKeys(currentItems: items, archivedItems: archive.items).isEmpty
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
        uncheckedItems: [ShoppingItem]
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
            // Cofamy SAME ptaszki tej operacji, nie całą tablicę ze zdjęcia
            // sprzed niej: wiersz zdjęty przesunięciem „Usuń” i przywrócony
            // po nieudanym usunięciu w trakcie odhaczania wracał inaczej do
            // starej tablicy BEZ niego — także w kopii na dysku (Codex,
            // 16.10.2026). Inny tydzień na ekranie = tamten tylko do odczytu.
            if self.weekStart == weekStart {
                let reverted = Set(uncheckedItems.map(\.productKey))
                for index in items.indices where reverted.contains(items[index].productKey) {
                    items[index].isChecked = false
                }
                cacheCurrentState(for: weekStart)
            } else {
                invalidatedWeeks.insert(weekStart)
            }
            errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
        }
    }

    private func apply(state: ShoppingListState, for weekStart: String) async {
        archivedLists = state.archives
        if let recent = state.recentProducts, recent != recentProducts {
            recentProducts = recent
            rebuildProductSearchIndex()
        }
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
        cachedStateByWeek[weekStart] = ShoppingListState(
            items: items,
            archives: archivedLists,
            recentProducts: recentProducts
        )
        persistCache()
    }

    private func loadPersistedCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let payload = try? JSONDecoder().decode(ShoppingListCachePayload.self, from: data) else {
            return
        }

        cachedStateByWeek = payload.weeks
        openRevisionsByWeek = payload.revisions ?? [:]
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
        let payload = ShoppingListCachePayload(
            weeks: cachedStateByWeek,
            revisions: openRevisionsByWeek
        )
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

        // Pierwszy odczyt tej rewizji na tym telefonie (po instalacji, na
        // telefonie domownika, po restarcie ze starszego pliku): nie ma z czym
        // porównać, więc ptaszki zostają — to decyzje domowników. Nadwyżkę
        // wobec archiwum odznacza sam serwer przy przebudowie listy
        // (`rebuildShoppingListSnapshot`). Dotąd brak znanego stanu znaczył
        // „wszystko nowe” i store odznaczał na serwerze wszystko, co kupiono
        // w otwartej rewizji — po każdym restarcie aplikacji.
        guard let previousState else {
            openRevisionsByWeek[weekStart] = OpenShoppingRevision(
                baseArchiveId: archive.id,
                pendingAmounts: pendingAmounts
            )
            return
        }

        let checkedPendingItems = items.filter { item in
            guard let pendingAmount = pendingAmounts[item.productKey], item.isChecked else {
                return false
            }

            guard let previousAmount = previousState.pendingAmounts[item.productKey] else {
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
        let rerequested = rerequestedKeys(currentItems: currentItems, archivedItems: archivedItems)

        return currentItems.compactMap { currentItem in
            guard let archivedItem = archivedByKey[currentItem.productKey] else {
                return currentItem
            }

            let additionalAmount = currentItem.totalAmount - archivedItem.totalAmount
            guard additionalAmount > 0.000_001 else {
                // Dopisany PONOWNIE bez ilości („kup jeszcze chleb”) po
                // zamknięciu listy: ilość się nie zmieniła, ale serwer zdjął
                // ptaszek. Wraca na listę — bez pigułki, bo nie wiadomo ile.
                guard rerequested.contains(currentItem.productKey) else { return nil }
                var pendingItem = currentItem
                pendingItem.totalAmount = 0
                pendingItem.unit = ""
                return pendingItem
            }

            var pendingItem = currentItem
            pendingItem.totalAmount = additionalAmount
            return pendingItem
        }
    }

    /// Pozycje dopisane ponownie po zamknięciu listy, bez zmiany ilości:
    /// w zamkniętej liście były kupione, teraz nie są, i mają dopisaną część.
    /// Zamknięta lista ma wszystko kupione, więc odznaczenie robi tu tylko
    /// dopisanie (serwer zdejmuje ptaszek dopisanemu produktowi).
    private func rerequestedKeys(currentItems: [ShoppingItem], archivedItems: [ShoppingItem]) -> Set<String> {
        let archivedByKey = Dictionary(uniqueKeysWithValues: archivedItems.map { ($0.productKey, $0) })
        var keys = Set<String>()
        for item in currentItems where !item.isChecked && item.hasAddedPart {
            guard let archived = archivedByKey[item.productKey],
                  archived.isChecked,
                  abs(item.totalAmount - archived.totalAmount) <= 0.000_001
            else { continue }
            keys.insert(item.productKey)
        }
        return keys
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
