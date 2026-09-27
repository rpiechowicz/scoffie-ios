import Foundation
import Observation
import SwiftUI

// Wydzielono z MealCalendarStore.swift — wcześniej oba Observable były w jednym pliku 1476 linii.

/// Katalog przepisów na telefonie.
///
/// Dwie części:
/// - PUBLICZNY katalog — `catalog:snapshot` / `catalog:changes` z trwałą
///   rewizją (`CatalogSyncEngine`). Pierwsze uruchomienie (albo brak ważnego
///   pliku) pobiera snapshot do końca, każde kolejne — foreground, powrót
///   połączenia — tylko zmiany od zapisanej rewizji;
/// - stan DOMU — `recipes:householdState`: przepisy gospodarstwa i ulubione.
///
/// Atomowość: przebieg składa nowy stan na kopii, a stan w pamięci i plik
/// (katalog + rewizja w JEDNYM pliku, zapis `.atomic`) podmieniają się razem,
/// dopiero po ostatniej stronie. Przerwany sync zostawia poprzedni katalog
/// z poprzednią rewizją — nigdy pół snapshotu z rewizją końca.
///
/// Czego sync nie kasuje: działający katalog zostaje na ekranie przy braku
/// sieci, przy RESET_REQUIRED (do końca nowego snapshotu) i przy błędzie
/// serwera. Plik jest odrzucany tylko wtedy, gdy nie da się go odczytać albo
/// ma inny format (`CatalogCacheEnvelope.Load`).
@Observable
final class RecipeCatalogStore {
    private let repository: RecipeRepository
    /// Konto i dom, do których należy stan domu w cache (`userId_householdId`).
    private let ownerKey: String?
    private(set) var recipes: [Recipe] = []
    private(set) var didLoad: Bool = false
    var isLoading: Bool = false
    var isLoadingMore: Bool = false
    /// Katalog trzyma się w całości — dociągania stron ze scrolla już nie ma.
    var hasMore: Bool = false
    var errorMessage: String?
    /// Strona snapshotu/delty: maksimum serwera (`CATALOG_SYNC_MAX_LIMIT`),
    /// bo przepis to ~1,7 kB, a stron ma być mało.
    private let syncPageSize: Int = 500
    /// Tylko dla awaryjnej ścieżki starego backendu (`recipes:findAll`, max 100).
    private let legacyPageSize: Int = 100
    private var catalogState = CatalogSyncState<Recipe>()
    /// Katalog przyszedł starą drogą (plik v12 albo `recipes:findAll`) —
    /// miesza przepisy domu z publicznymi, więc NIE trafia do pliku
    /// publicznego katalogu (ten przeżywa wylogowanie).
    private var catalogIsLegacy = false
    private var householdRecipes: [Recipe] = []
    private var favoriteIds: Set<UUID> = []
    private var pendingRealtimeReloadTask: Task<Void, Never>?
    private var pendingHouseholdRefreshTask: Task<Void, Never>?
    private var pendingFavoriteTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingFavoriteOriginalState: [UUID: Bool] = [:]

    /// Wylogowanie (`SessionStore`): znika stan DOMU (przepisy gospodarstwa,
    /// ulubione) i stare pliki sprzed synchronizacji, które go mieszały
    /// z katalogiem. Publiczny katalog zostaje — jest ten sam dla każdego
    /// konta, a następne logowanie zrobi z niego deltę zamiast snapshotu.
    /// Przez tę samą kolejkę co zapis — inaczej zapis czekający w kolejce
    /// odtworzyłby plik już po wylogowaniu.
    static func clearCache() {
        let householdURL = householdCacheURL
        cacheWriteQueue.async {
            try? FileManager.default.removeItem(at: householdURL)
            removeLegacyCacheFiles()
        }
    }

    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Publiczny katalog z rewizją. Wersja formatu jest W pliku
    /// (`CatalogCacheEnvelope.currentVersion`), nie w nazwie.
    private static var catalogCacheURL: URL {
        documentsURL.appendingPathComponent("recipe_catalog.json")
    }

    /// Przepisy domu i ulubione — z właścicielem w środku.
    private static var householdCacheURL: URL {
        documentsURL.appendingPathComponent("recipe_catalog_household.json")
    }

    /// Pliki sprzed synchronizacji rewizją: `recipes_catalog_cache_v<N>.json`
    /// (v8…v12) — pełna lista z ulubionymi i przepisami domu, ważna 12 h.
    private static let legacyCacheFileName = "recipes_catalog_cache_v12.json"

    private static func removeLegacyCacheFiles() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: documentsURL.path) else { return }
        for name in names where name.hasPrefix("recipes_catalog_cache_v") && name.hasSuffix(".json") {
            try? fm.removeItem(at: documentsURL.appendingPathComponent(name))
        }
    }

    init(
        repository: RecipeRepository = ApiRecipeRepository(
            client: WebSocketRecipeTransportClient(
                socket: UnconfiguredRecipeSocketClient(),
                userId: "mock-user"
            )
        ),
        ownerKey: String? = nil
    ) {
        self.repository = repository
        self.ownerKey = ownerKey
        self.repository.observeFavoritesChanges { [weak self] recipeId, isFavorite in
            guard let self else { return }
            Task { @MainActor in
                self.setFavoriteId(recipeId, isFavorite)
                if let index = self.recipes.firstIndex(where: { $0.id == recipeId }) {
                    self.recipes[index].favourite = isFavorite
                }
                self.saveHouseholdCache()
            }
        }
        // Przepis GOSPODARSTWA zmieniony poza tym telefonem (domownik,
        // asystent AI). `recipes:changed` nie dotyczy publicznego katalogu —
        // ten serwer ogłasza tylko rewizją, więc wystarczy stan domu.
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
            // Anulowany debounce NIE startuje synchronizacji — `try?` połykał
            // anulowanie i zadanie ciągnęło katalog jako anulowane.
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
                self.saveHouseholdCache()
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
                    saveHouseholdCache()
                } catch {
                    errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
                }
            }
            rebuildRecipes()
            didLoad = true
        } catch is CancellationError {
            // Przerwany przebieg: nic nie zostało podmienione.
        } catch {
            // Brak sieci / błąd serwera: poprzedni katalog zostaje na ekranie.
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

    private func makeEngine() -> CatalogSyncEngine<Recipe> {
        let repository = repository
        return CatalogSyncEngine(
            pageLimit: syncPageSize,
            fetchSnapshotPage: { revision, cursor, limit in
                try await Self.retryingRateLimit {
                    try await repository.fetchCatalogSnapshotPage(revision: revision, cursor: cursor, limit: limit)
                }
            },
            fetchChangesPage: { since, until, cursor, limit in
                try await Self.retryingRateLimit {
                    try await repository.fetchCatalogChangesPage(
                        sinceRevision: since,
                        untilRevision: until,
                        cursor: cursor,
                        limit: limit
                    )
                }
            }
        )
    }

    /// Zwraca `true`, gdy katalog przyszedł starą drogą (`recipes:findAll`).
    private func syncCatalog() async throws -> Bool {
        let engine = makeEngine()
        do {
            if !catalogIsLegacy, catalogState.revision != nil {
                let outcome = try await engine.pullDelta(onto: catalogState)
                switch outcome {
                case .applied(let next, _):
                    commitCatalog(next)
                    return false
                case .resetRequired:
                    // Serwer nie zna tej rewizji (nowa epoka, przycięty log).
                    // Starego katalogu nie naprawiamy deltą — rewizja znika też
                    // z pliku, a katalog zostaje na ekranie do końca snapshotu.
                    catalogState.forgetRevision()
                    saveCatalogCache()
                }
            }
            commitCatalog(try await engine.pullSnapshot())
            return false
        } catch {
            // Backend sprzed synchronizacji przyrostowej nie zna
            // `catalog:snapshot` (ack nie przychodzi) albo ma ją wyłączoną
            // (503 po wycofaniu migracji) — pełna lista starą drogą. Każdy
            // inny błąd (sieć, 500, anulowanie) zostawia katalog jak był.
            guard Self.indicatesLegacyBackend(error) else { throw error }
            try await legacyFullReload()
            return true
        }
    }

    /// Nowy stan katalogu i jego plik — razem, po całym przebiegu.
    private func commitCatalog(_ next: CatalogSyncState<Recipe>) {
        catalogState = next
        catalogIsLegacy = false
        saveCatalogCache()
        let queue = Self.cacheWriteQueue
        queue.async { Self.removeLegacyCacheFiles() }
    }

    /// Stary backend: `catalog:snapshot` bez ack (socket sam ponawia 3×) albo
    /// `SERVICE_UNAVAILABLE`. Treść komunikatu braku ack ustawia
    /// `SocketIORecipeSocketClient.requestAck`.
    static func indicatesLegacyBackend(_ error: Error) -> Bool {
        guard let error = error as? RecipeDataError else { return false }
        switch error {
        case let .server(code, _, _, _):
            return code == "SERVICE_UNAVAILABLE"
        case let .serverError(message):
            return message.hasPrefix("Brak ACK")
        default:
            return false
        }
    }

    /// Limit zapytań (120/min na użytkownika, wspólny dla wszystkich zdarzeń)
    /// to jedyny błąd, który warto tu ponowić — resztę ponawia już socket.
    private static func retryingRateLimit<T>(_ operation: () async throws -> T) async throws -> T {
        for attempt in 1...3 {
            do {
                return try await operation()
            } catch RecipeDataError.server(let code, _, _, _) where code == "TOO_MANY_REQUESTS" && attempt < 3 {
                try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
            }
        }
        return try await operation()
    }

    private func refreshHouseholdState() async throws {
        let state = try await Self.retryingRateLimit {
            try await self.repository.fetchHouseholdRecipeState()
        }
        householdRecipes = state.recipes
        favoriteIds = state.favoriteRecipeIds
    }

    /// Awaryjnie, dla backendu bez `catalog:snapshot`: `recipes:findAll` do
    /// ostatniej strony (katalog + przepisy domu + ulubione w jednym). Bez
    /// rewizji, więc następnym razem znowu próba snapshotu.
    private func legacyFullReload() async throws {
        var all: [Recipe] = []
        var page = 1
        while true {
            try Task.checkCancellation()
            let fetched = try await repository.fetchRecipes(page: page, limit: legacyPageSize)
            all.append(contentsOf: fetched.recipes)
            // Koniec poznajemy po liczbie wierszy z serwera — patrz `RecipePage`.
            if fetched.receivedCount < legacyPageSize { break }
            page += 1
        }
        householdRecipes = []
        favoriteIds = Set(all.filter(\.favourite).map(\.id))
        let keyed = all.map { (ApiRecipeRepository.catalogKey($0.id.uuidString), $0) }
        catalogState = CatalogSyncState(
            ids: keyed.map(\.0),
            items: Dictionary(keyed, uniquingKeysWith: { first, _ in first }),
            revision: nil
        )
        catalogIsLegacy = true
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
            // Pełna wersja także w stanie, z którego lista się przebudowuje —
            // inaczej następny sync cofałby ją do wersji z listy.
            let key = ApiRecipeRepository.catalogKey(recipeId.uuidString)
            if let index = householdRecipes.firstIndex(where: { $0.id == recipeId }) {
                householdRecipes[index] = detailed
                saveHouseholdCache()
            } else if catalogState.items[key] != nil {
                catalogState.replaceKnownItem(id: key, with: ApiRecipeRepository.catalogCopy(detailed))
                saveCatalogCache()
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
                self.saveHouseholdCache()
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

    /// Katalog + rewizja w jednym pliku, zapis `.atomic` (plik tymczasowy
    /// i podmiana) — na dysku jest albo stary komplet, albo nowy. Encode poza
    /// main threadem — katalog to tysiące przepisów.
    private func saveCatalogCache() {
        guard !catalogIsLegacy else { return }
        let envelope = CatalogCacheEnvelope(state: catalogState, savedAt: Date())
        let url = Self.catalogCacheURL
        Self.cacheWriteQueue.async {
            // Błąd zapisu cache świadomie pomijany — następny sync to naprawi.
            guard let data = try? JSONEncoder().encode(envelope) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func saveHouseholdCache() {
        guard let ownerKey, !catalogIsLegacy else { return }
        let envelope = HouseholdRecipeCacheEnvelope(
            ownerKey: ownerKey,
            recipes: householdRecipes,
            favoriteRecipeIds: favoriteIds.map { $0.uuidString.lowercased() }.sorted(),
            savedAt: Date()
        )
        let url = Self.householdCacheURL
        Self.cacheWriteQueue.async {
            guard let data = try? JSONEncoder().encode(envelope) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Cache pokazuje katalog od razu; świeżość zapewnia następny sync (delta
    /// od zapisanej rewizji), a nie wiek pliku.
    private func loadCache() -> Bool {
        switch CatalogCacheEnvelope<Recipe>.load(from: try? Data(contentsOf: Self.catalogCacheURL)) {
        case .valid(let state):
            catalogState = state
            catalogIsLegacy = false
        case .missing:
            loadLegacyCatalogIfPresent()
        case .unsupportedVersion, .corrupted:
            // Pliku nie da się użyć — snapshot zbuduje go od nowa. Stary plik
            // v12 (jeśli jest) pokaże katalog do tego czasu.
            let url = Self.catalogCacheURL
            Self.cacheWriteQueue.async { try? FileManager.default.removeItem(at: url) }
            loadLegacyCatalogIfPresent()
        }
        // Stan domu tylko tego samego konta i domu — cudzy (inne konto na
        // tym telefonie, inny dom) nie ma prawa się pokazać.
        if let ownerKey,
           let household = HouseholdRecipeCacheEnvelope<Recipe>.load(
               from: try? Data(contentsOf: Self.householdCacheURL),
               ownerKey: ownerKey
           ) {
            householdRecipes = household.recipes
            favoriteIds = Set(household.favoriteRecipeIds.compactMap { UUID(uuidString: $0) })
        }
        rebuildRecipes()
        hasMore = false
        return !recipes.isEmpty
    }

    /// Plik sprzed synchronizacji rewizją (`recipes_catalog_cache_v12.json`):
    /// pokazujemy go do końca pierwszego snapshotu, zamiast pustego ekranu —
    /// ale tylko w pamięci i tylko świeży (dawne 12 h), bo miesza przepisy
    /// domu z publicznymi. Kasuje go pierwszy udany snapshot albo wylogowanie.
    private struct LegacyCachePayload: Decodable {
        let recipes: [Recipe]
        let savedAt: Date
    }

    private func loadLegacyCatalogIfPresent() {
        let url = Self.documentsURL.appendingPathComponent(Self.legacyCacheFileName)
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(LegacyCachePayload.self, from: data),
              Date().timeIntervalSince(payload.savedAt) <= 60 * 60 * 12,
              !payload.recipes.isEmpty else { return }
        let keyed = payload.recipes.map { (ApiRecipeRepository.catalogKey($0.id.uuidString), $0) }
        catalogState = CatalogSyncState(
            ids: keyed.map(\.0),
            items: Dictionary(keyed, uniquingKeysWith: { first, _ in first }),
            revision: nil
        )
        favoriteIds = Set(payload.recipes.filter(\.favourite).map(\.id))
        catalogIsLegacy = true
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
