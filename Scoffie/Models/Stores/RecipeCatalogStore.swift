import Foundation
import Observation
import SwiftUI

// Wydzielono z MealCalendarStore.swift — wcześniej oba Observable były w jednym pliku 1476 linii.

/// Katalog przepisów na telefonie.
///
/// Od synchronizacji przyrostowej (backend workstream Etap 4A) katalog ma dwie
/// części: PUBLICZNY katalog (`catalog:snapshot` / `catalog:changes`, z trwałą
/// rewizją) i stan DOMU (`recipes:householdState`: przepisy gospodarstwa
/// i ulubione). Pierwsze uruchomienie pobiera snapshot do końca — bez
/// sufitu stron, więc katalog 10 000 przepisów dojeżdża w całości — a każde
/// kolejne (foreground, powrót połączenia) tylko zmiany od zapisanej rewizji.
/// Rewizja zapisuje się WYŁĄCZNIE po zastosowaniu całego przebiegu
/// (`CatalogSyncState`), więc przerwany sync powtarza się od tej samej rewizji.
@Observable
final class RecipeCatalogStore {
    private struct RecipeCatalogCachePayload: Codable {
        /// Publiczny katalog w kolejności z serwera.
        let catalogIds: [String]
        let catalog: [String: Recipe]
        /// Rewizja W CAŁOŚCI zastosowanego katalogu; `nil` = następny sync to snapshot.
        let revision: String?
        let householdRecipes: [Recipe]
        let favoriteRecipeIds: [UUID]
        let savedAt: Date
    }

    private let repository: RecipeRepository
    private(set) var recipes: [Recipe] = []
    private(set) var didLoad: Bool = false
    var isLoading: Bool = false
    var isLoadingMore: Bool = false
    var hasMore: Bool = false
    var errorMessage: String?
    /// Strona snapshotu/delty — duża, bo przepis to ~1,7 kB, a stron ma być mało.
    private let syncPageSize: Int = 500
    /// Tylko dla awaryjnej ścieżki starego backendu (`recipes:findAll`).
    private let legacyPageSize: Int = 100
    private let maxFetchAttempts: Int = 3
    private var catalogState = CatalogSyncState<Recipe>()
    private var householdRecipes: [Recipe] = []
    private var favoriteIds: Set<UUID> = []
    private var pendingRealtimeReloadTask: Task<Void, Never>?
    private var pendingHouseholdRefreshTask: Task<Void, Never>?
    private var pendingFavoriteTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingFavoriteOriginalState: [UUID: Bool] = [:]
    private var cacheURL: URL { Self.cacheFileURL }

    /// Kasuje plik cache — wołane przy wylogowaniu (`SessionStore`), bo plik
    /// nie zna konta.
    /// Przez tę samą kolejkę co zapis — inaczej zapis czekający w kolejce
    /// odtworzyłby plik już po wylogowaniu.
    static func clearCache() {
        let url = cacheFileURL
        cacheWriteQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static var cacheFileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            // v13: katalog z rewizją synchronizacji + osobno przepisy domu
            // i ulubione (backend Etap 4A). Stary plik (pełna lista bez
            // rewizji) nie ma z czego zrobić delty — nowy przebieg zaczyna
            // od snapshotu.
            // v12: doszły tagi z serwera (allergens/dietTags).
            // v11: plaster A — porcje 1..8 i prostowanie nazw składników.
            // v10: prostowanie id przepisów w katalogu.
            // v9: sekcja „Przekąski i desery".
            // v8: pola sourceProvider/sourceRecipeId (badge Thermomixa).
            .appendingPathComponent("recipes_catalog_cache_v13.json")
    }

    init(
        repository: RecipeRepository = ApiRecipeRepository(
            client: WebSocketRecipeTransportClient(
                socket: UnconfiguredRecipeSocketClient(),
                userId: "mock-user"
            )
        )
    ) {
        self.repository = repository
        self.repository.observeFavoritesChanges { [weak self] recipeId, isFavorite in
            guard let self else { return }
            Task { @MainActor in
                if isFavorite {
                    self.favoriteIds.insert(recipeId)
                } else {
                    self.favoriteIds.remove(recipeId)
                }
                if let index = self.recipes.firstIndex(where: { $0.id == recipeId }) {
                    self.recipes[index].favourite = isFavorite
                    self.saveCache()
                }
            }
        }
        // Przepis GOSPODARSTWA zmieniony poza tym telefonem (domownik,
        // asystent AI). Publiczny katalog się od tego nie zmienia — wystarczy
        // odświeżyć stan domu, bez synchronizacji katalogu.
        self.repository.observeRecipeChanges { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard self.didLoad else { return }
                self.scheduleHouseholdRefresh()
            }
        }
        // Powrót połączenia: zmiany katalogu od zapisanej rewizji (zwykle
        // pusta delta, jedno zapytanie) — nie pełne pobranie.
        self.repository.observeRealtimeReconnect { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard self.didLoad else { return }
                self.scheduleRealtimeReload()
            }
        }
    }

    /// Synchronizacja po zdarzeniu z serwera, z krótkim opóźnieniem — kilka
    /// zdarzeń pod rząd (powrót połączenia) daje jeden przebieg.
    private func scheduleRealtimeReload() {
        pendingRealtimeReloadTask?.cancel()
        pendingRealtimeReloadTask = Task { @MainActor [weak self] in
            // Anulowany debounce NIE startuje synchronizacji.
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }
            guard let self else { return }
            await self.reload()
        }
    }

    private func scheduleHouseholdRefresh() {
        pendingHouseholdRefreshTask?.cancel()
        pendingHouseholdRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }
            guard let self else { return }
            do {
                try await self.refreshHouseholdState()
                self.rebuildRecipes()
                self.saveCache()
            } catch {
                self.errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
            }
        }
    }

    func loadIfNeeded() async {
        guard !didLoad else { return }
        if loadCache() {
            didLoad = true
            errorMessage = nil
            Task { @MainActor [weak self] in
                await self?.reload()
            }
            return
        }
        await reload()
    }

    /// Synchronizacja katalogu (delta albo snapshot) i odświeżenie stanu domu.
    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        do {
            let usedLegacy = try await syncCatalog()
            // Stan domu osobno: jego błąd (np. chwilowy timeout) nie może
            // schować publicznego katalogu, który właśnie się zsynchronizował.
            // Stara ścieżka `recipes:findAll` niesie już przepisy domu
            // i ulubione — a stary backend i tak nie zna tego zdarzenia.
            if !usedLegacy {
                do {
                    try await refreshHouseholdState()
                } catch {
                    errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
                }
            }
            rebuildRecipes()
            hasMore = false
            didLoad = true
            saveCache()
        } catch {
            errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
        }
        isLoading = false
    }

    /// Katalog trzyma się w całości (synchronizacja do końca protokołu), więc
    /// dociąganie stron ze scrolla nie ma już czego dociągać.
    func loadNextPageIfNeeded(currentItemId: UUID?, threshold: Int = 6) async {
        _ = currentItemId
        _ = threshold
    }

    // MARK: - Synchronizacja

    private enum DeltaOutcome {
        case applied
        case resetRequired
    }

    /// Zwraca `true`, gdy katalog przyszedł starą drogą (`recipes:findAll`).
    private func syncCatalog() async throws -> Bool {
        if let since = catalogState.revision {
            if try await pullDelta(since: since) == .applied { return false }
            catalogState.invalidateRevision()
        }
        do {
            try await pullSnapshot()
            return false
        } catch {
            // Backend sprzed synchronizacji przyrostowej nie zna
            // `catalog:snapshot` (ack nie przychodzi) — pełna lista starą
            // drogą, do końca, bez sufitu stron. Rewizji wtedy nie ma, więc
            // następnym razem znowu snapshot, a po jego porażce znowu ta droga.
            try await legacyFullReload()
            return true
        }
    }

    /// Delta od `since`: wszystkie strony do bufora, `untilRevision` z pierwszej
    /// strony, stan i rewizja dopiero po ostatniej.
    private func pullDelta(since: String) async throws -> DeltaOutcome {
        var buffer = CatalogSyncBuffer<Recipe>()
        var until: String?
        var cursor: String?
        repeat {
            let page = try await withRetry {
                try await self.repository.fetchCatalogChangesPage(
                    sinceRevision: since,
                    untilRevision: until,
                    cursor: cursor,
                    limit: self.syncPageSize
                )
            }
            if page.resetRequired { return .resetRequired }
            until = until ?? page.revision
            buffer.addTombstones(page.tombstones)
            buffer.addUpserts(page.upserts)
            cursor = page.nextCursor
        } while cursor != nil
        catalogState.applyDelta(buffer, revision: until ?? since)
        return .applied
    }

    /// Snapshot: znacznik z pierwszej strony odsyłany na kolejnych. Gdy serwer
    /// każe zacząć od nowa w trakcie (np. odtworzona baza), jedna ponowna próba.
    private func pullSnapshot() async throws {
        for _ in 0..<2 {
            var buffer = CatalogSyncBuffer<Recipe>()
            var revision: String?
            var cursor: String?
            var restart = false
            repeat {
                let page = try await withRetry {
                    try await self.repository.fetchCatalogSnapshotPage(
                        revision: revision,
                        cursor: cursor,
                        limit: self.syncPageSize
                    )
                }
                if page.resetRequired {
                    restart = true
                    break
                }
                revision = revision ?? page.revision
                buffer.addUpserts(page.recipes)
                cursor = page.nextCursor
            } while cursor != nil
            if !restart, let revision {
                catalogState.applySnapshot(buffer, revision: revision)
                return
            }
        }
        throw RecipeDataError.serverError(message: "Nie udało się pobrać katalogu przepisów.")
    }

    private func refreshHouseholdState() async throws {
        let state = try await withRetry {
            try await self.repository.fetchHouseholdRecipeState()
        }
        householdRecipes = state.recipes
        favoriteIds = state.favoriteRecipeIds
    }

    /// Awaryjnie, dla backendu bez `catalog:snapshot`: `recipes:findAll` do
    /// ostatniej strony (katalog + przepisy domu + ulubione w jednym).
    private func legacyFullReload() async throws {
        var all: [Recipe] = []
        var page = 1
        while true {
            let fetched = try await withRetry {
                try await self.repository.fetchRecipes(page: page, limit: self.legacyPageSize)
            }
            all.append(contentsOf: fetched.recipes)
            // Koniec poznajemy po liczbie wierszy z serwera — patrz `RecipePage`.
            if fetched.receivedCount < legacyPageSize { break }
            page += 1
        }
        householdRecipes = []
        favoriteIds = Set(all.filter(\.favourite).map(\.id))
        catalogState = CatalogSyncState(
            ids: all.map { $0.id.uuidString.lowercased() },
            items: Dictionary(
                all.map { ($0.id.uuidString.lowercased(), $0) },
                uniquingKeysWith: { first, _ in first }
            ),
            revision: nil
        )
    }

    /// Przepisy domu na początku, potem katalog; ulubione z bieżącego stanu domu.
    /// Serduszko, którego zapis jeszcze czeka (`pendingFavoriteTasks`), zostaje
    /// takie, jak na ekranie — stan domu pobrany przed zapisem go nie cofa.
    private func rebuildRecipes() {
        let householdIds = Set(householdRecipes.map(\.id))
        let onScreen = Dictionary(
            recipes.map { ($0.id, $0.favourite) },
            uniquingKeysWith: { first, _ in first }
        )
        var merged = householdRecipes
        merged.append(contentsOf: catalogState.orderedItems.filter { !householdIds.contains($0.id) })
        for index in merged.indices {
            let id = merged[index].id
            if pendingFavoriteTasks[id] != nil, let visible = onScreen[id] {
                merged[index].favourite = visible
            } else {
                merged[index].favourite = favoriteIds.contains(id)
            }
        }
        recipes = merged
    }

    private func setFavoriteId(_ recipeId: UUID, _ isFavorite: Bool) {
        if isFavorite {
            favoriteIds.insert(recipeId)
        } else {
            favoriteIds.remove(recipeId)
        }
    }

    @MainActor
    func loadRecipeDetail(recipeId: UUID) async -> Recipe? {
        if let index = recipes.firstIndex(where: { $0.id == recipeId }) {
            let current = recipes[index]
            if !current.ingredients.isEmpty && !current.preparationSteps.isEmpty {
                return current
            }
        }

        do {
            let detailed = try await repository.fetchRecipeById(recipeId)
            if let index = recipes.firstIndex(where: { $0.id == recipeId }) {
                recipes[index] = detailed
            } else {
                recipes.append(detailed)
            }
            return detailed
        } catch {
            errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
            return recipes.first(where: { $0.id == recipeId })
        }
    }

    /// Ustawia ulubione na podaną wartość — nic nie robi, gdy przepis już ją ma.
    ///
    /// Serce zapisuje się z opóźnieniem, po animacji (`RecipeFavouriteButton`).
    /// Przełącznik liczony od kopii przepisu sprzed chwili potrafił wtedy
    /// przestawić stan w złą stronę — np. karuzela zdążyła zapisać, a arkusz
    /// szczegółów miał starszą kopię. Docelowa wartość jest odporna na to, kto
    /// zapisał pierwszy.
    func setFavourite(recipeId: UUID, to value: Bool) async {
        guard let index = recipes.firstIndex(where: { $0.id == recipeId }),
              recipes[index].favourite != value else { return }
        await toggleFavorite(recipeId: recipeId)
    }

    func toggleFavorite(recipeId: UUID) async {
        guard let index = recipes.firstIndex(where: { $0.id == recipeId }) else { return }
        let previous = recipes[index].favourite
        let next = !previous

        recipes[index].favourite = next
        // Od razu także w stanie domu: przebudowa listy (sync, odświeżenie
        // domu) w oknie przed odpowiedzią serwera nie cofa serduszka.
        setFavoriteId(recipeId, next)

        if pendingFavoriteTasks[recipeId] == nil {
            pendingFavoriteOriginalState[recipeId] = previous
        }
        pendingFavoriteTasks[recipeId]?.cancel()

        pendingFavoriteTasks[recipeId] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled else { return }

            let originalState = self.pendingFavoriteOriginalState[recipeId] ?? previous
            self.pendingFavoriteTasks[recipeId] = nil
            self.pendingFavoriteOriginalState[recipeId] = nil

            guard let finalIndex = self.recipes.firstIndex(where: { $0.id == recipeId }) else { return }
            let finalState = self.recipes[finalIndex].favourite

            if finalState == originalState { return }

            do {
                try await self.repository.setFavorite(recipeId: recipeId, isFavorite: finalState)
                self.setFavoriteId(recipeId, finalState)
                self.saveCache()
            } catch {
                self.setFavoriteId(recipeId, originalState)
                if let rollbackIndex = self.recipes.firstIndex(where: { $0.id == recipeId }) {
                    self.recipes[rollbackIndex].favourite = originalState
                }
                self.errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
            }
        }
    }

    // MARK: - Cache

    /// Jedna kolejka seryjna na wszystkie zapisy — ostatni snapshot wygrywa
    /// (ten sam wzór co `ShoppingListStore.persistCache`).
    private static let cacheWriteQueue = DispatchQueue(
        label: "recipe-catalog-cache-write",
        qos: .utility
    )

    /// Encode + zapis pliku poza main threadem — katalog to tysiące przepisów.
    private func saveCache() {
        let ids = catalogState.ids
        let payload = RecipeCatalogCachePayload(
            catalogIds: ids,
            catalog: catalogState.items,
            revision: catalogState.revision,
            householdRecipes: householdRecipes,
            favoriteRecipeIds: Array(favoriteIds),
            savedAt: Date()
        )
        let url = cacheURL
        Self.cacheWriteQueue.async {
            // Błąd zapisu cache świadomie pomijany.
            guard let data = try? JSONEncoder().encode(payload) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Cache pokazuje katalog od razu; świeżość zapewnia następny sync (delta
    /// od zapisanej rewizji), a nie wiek pliku.
    private func loadCache() -> Bool {
        guard let data = try? Data(contentsOf: cacheURL) else { return false }
        guard let payload = try? JSONDecoder().decode(RecipeCatalogCachePayload.self, from: data) else { return false }
        catalogState = CatalogSyncState(
            ids: payload.catalogIds,
            items: payload.catalog,
            revision: payload.revision
        )
        householdRecipes = payload.householdRecipes
        favoriteIds = Set(payload.favoriteRecipeIds)
        rebuildRecipes()
        hasMore = false
        return !recipes.isEmpty
    }

    private func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        var lastError: Error?
        for attempt in 1...maxFetchAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < maxFetchAttempts {
                    let backoffMs = UInt64(200 * attempt)
                    try await Task.sleep(nanoseconds: backoffMs * 1_000_000)
                }
            }
        }
        throw lastError ?? RecipeDataError.serverError(message: "Nie udało się pobrać listy przepisów.")
    }
}

private struct RecipeCatalogStoreKey: EnvironmentKey {
    @MainActor static let defaultValue = RecipeCatalogStore()
}

extension EnvironmentValues {
    var recipeCatalogStore: RecipeCatalogStore {
        get { self[RecipeCatalogStoreKey.self] }
        set { self[RecipeCatalogStoreKey.self] = newValue }
    }
}
