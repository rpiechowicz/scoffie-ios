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
/// Stan, zapis na dysk i cykl życia sesji trzyma `CatalogSyncCore` (czysta
/// logika ze sprawdzianem); ten typ to fasada dla SwiftUI.
///
/// Atomowość: przebieg składa nowy stan na kopii, a stan w pamięci i plik
/// (katalog + rewizja w JEDNYM pliku, zapis `.atomic`) podmieniają się razem,
/// dopiero po ostatniej stronie. Przerwany sync zostawia poprzedni katalog
/// z poprzednią rewizją — nigdy pół snapshotu z rewizją końca.
///
/// Cykl życia: `SessionStore` woła `invalidate()` przy wylogowaniu i przed
/// zastąpieniem store'u nową sesją. Po tym spóźnione odpowiedzi i callbacki
/// tej instancji nie zmieniają już ani jej stanu, ani plików.
@Observable
final class RecipeCatalogStore {
    private let repository: RecipeRepository
    private let core: CatalogSyncCore<Recipe>
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
    private var reloadTask: Task<Void, Never>?
    private var pendingRealtimeReloadTask: Task<Void, Never>?
    private var pendingHouseholdRefreshTask: Task<Void, Never>?
    private var pendingFavoriteTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingFavoriteOriginalState: [UUID: Bool] = [:]

    /// Czy ta instancja została unieważniona (wylogowanie, nowa sesja).
    var isInvalidated: Bool { core.isInvalidated }

    /// Wylogowanie (`SessionStore`): znika stan DOMU (przepisy gospodarstwa,
    /// ulubione) i stare pliki sprzed synchronizacji, które go mieszały
    /// z katalogiem. Publiczny katalog zostaje — jest ten sam dla każdego
    /// konta, a następne logowanie zrobi z niego deltę zamiast snapshotu.
    /// Wołać PO `invalidate()` starej instancji — inaczej jej zapis, który
    /// właśnie czeka w kolejce, mógłby przyjść po skasowaniu.
    static func clearCache() {
        CatalogSyncCore<Recipe>.clearPrivateFiles(.documents, gate: .shared)
    }

    /// Pliki sprzed synchronizacji rewizją: `recipes_catalog_cache_v<N>.json`
    /// (v8…v12) — pełna lista z ulubionymi i przepisami domu, ważna 12 h.
    private static let legacyCacheFileName = "recipes_catalog_cache_v12.json"

    init(
        repository: RecipeRepository = ApiRecipeRepository(
            client: WebSocketRecipeTransportClient(
                socket: UnconfiguredRecipeSocketClient(),
                userId: "mock-user"
            )
        ),
        ownerKey: String? = nil
    ) {
        // Wyłączone „Dopasowane do Ciebie” trzyma tylko do końca uruchomienia
        // aplikacji — patrz `RecipePersonalization.restoreForThisLaunch`.
        RecipePersonalization.restoreForThisLaunch()
        self.repository = repository
        self.core = CatalogSyncCore(ownerKey: ownerKey, files: .documents, gate: .shared)
        self.repository.observeFavoritesChanges { [weak self] recipeId, isFavorite in
            guard let self else { return }
            Task { @MainActor in
                guard !self.isInvalidated else { return }
                self.core.setFavorite(CatalogSyncMapping.key(recipeId.uuidString), isFavorite)
                if let index = self.recipes.firstIndex(where: { $0.id == recipeId }) {
                    self.recipes[index].favourite = isFavorite
                }
            }
        }
        // Przepis GOSPODARSTWA zmieniony poza tym telefonem (domownik,
        // asystent AI). `recipes:changed` nie dotyczy publicznego katalogu —
        // ten serwer ogłasza tylko rewizją, więc wystarczy stan domu.
        self.repository.observeRecipeChanges { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard self.didLoad, !self.isInvalidated else { return }
                self.scheduleHouseholdRefresh()
            }
        }
        // Powrót połączenia: zmiany katalogu od zapisanej rewizji (zwykle
        // pusta delta, jedno zapytanie) — nie pełne pobranie.
        self.repository.observeRealtimeReconnect { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard self.didLoad, !self.isInvalidated else { return }
                self.scheduleRealtimeReload()
            }
        }
    }

    /// Koniec tej sesji katalogu. Odbiera prawo zapisu plików, anuluje
    /// zadania w toku (sync przerywa się między stronami) i sprawia, że
    /// spóźnione odpowiedzi niczego już nie publikują.
    func invalidate() {
        core.invalidate()
        reloadTask?.cancel()
        pendingRealtimeReloadTask?.cancel()
        pendingHouseholdRefreshTask?.cancel()
        pendingFavoriteTasks.values.forEach { $0.cancel() }
        pendingFavoriteTasks = [:]
        pendingFavoriteOriginalState = [:]
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
            guard let self, !self.isInvalidated else { return }
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
            guard let self, !self.isInvalidated else { return }
            do {
                try await self.refreshHouseholdState()
                self.rebuildRecipes()
            } catch is CancellationError {
                return
            } catch {
                guard !self.isInvalidated else { return }
                self.errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
            }
        }
    }

    func loadIfNeeded() async {
        guard !didLoad, !isInvalidated else { return }
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
    /// Przebieg biegnie we własnym zadaniu, żeby `invalidate()` mogło go przerwać.
    func reload() async {
        guard !isLoading, !isInvalidated else { return }
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        // Typ jawnie: `await self?.performReload()` jako jedyne wyrażenie
        // wyprowadzałoby `Task<Void?, Never>`, niezgodne z `reloadTask`.
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performReload()
        }
        reloadTask = task
        await task.value
        reloadTask = nil
        isLoading = false
    }

    private func performReload() async {
        do {
            let usedLegacy = try await syncCatalog()
            // Stan domu osobno: jego błąd (np. chwilowy timeout) nie może
            // schować publicznego katalogu, który właśnie się zsynchronizował.
            // Stara ścieżka `recipes:findAll` niesie już przepisy domu
            // i ulubione — a stary backend i tak nie zna tego zdarzenia.
            if !usedLegacy {
                do {
                    try await refreshHouseholdState()
                } catch is CancellationError {
                    return
                } catch {
                    guard !isInvalidated else { return }
                    errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
                }
            }
            guard !isInvalidated else { return }
            rebuildRecipes()
            didLoad = true
        } catch is CancellationError {
            // Przerwany albo unieważniony przebieg: nic nie zostało podmienione.
        } catch {
            // Brak sieci / błąd serwera: poprzedni katalog zostaje na ekranie.
            guard !isInvalidated else { return }
            errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
        }
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
        do {
            _ = try await core.syncCatalog(using: makeEngine())
            return false
        } catch {
            // Backend sprzed synchronizacji przyrostowej nie zna
            // `catalog:snapshot` (ack nie przychodzi) albo ma ją wyłączoną
            // (503 po wycofaniu migracji) — pełna lista starą drogą. Każdy
            // inny błąd (sieć, 500, odrzucona strona, anulowanie) zostawia
            // katalog jak był.
            guard Self.indicatesLegacyBackend(error) else { throw error }
            try await legacyFullReload()
            return true
        }
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
        let repository = repository
        try await core.refreshHousehold {
            let state = try await Self.retryingRateLimit {
                try await repository.fetchHouseholdRecipeState()
            }
            return CatalogSyncCore<Recipe>.Household(
                items: state.recipes,
                favoriteIds: Set(state.favoriteRecipeIds.map { CatalogSyncMapping.key($0.uuidString) })
            )
        }
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
            try core.checkValid()
            all.append(contentsOf: fetched.recipes)
            // Koniec poznajemy po liczbie wierszy z serwera — patrz `RecipePage`.
            if fetched.receivedCount < legacyPageSize { break }
            page += 1
        }
        core.adoptLegacyCatalog(
            all.map { (id: CatalogSyncMapping.key($0.id.uuidString), item: $0) },
            favoriteIds: Set(all.filter(\.favourite).map { CatalogSyncMapping.key($0.id.uuidString) }),
            clearHousehold: true
        )
    }

    /// Przepisy domu na początku, potem katalog; ulubione z bieżącego stanu domu.
    /// Serduszko, którego zapis jeszcze czeka (`pendingFavoriteTasks`), zostaje
    /// takie, jak na ekranie — stan domu pobrany przed zapisem go nie cofa.
    private func rebuildRecipes() {
        guard !isInvalidated else { return }
        let household = core.household
        let householdIds = Set(household.items.map(\.id))
        let onScreen = Dictionary(
            recipes.map { ($0.id, $0.favourite) },
            uniquingKeysWith: { first, _ in first }
        )
        var merged = household.items
        merged.append(contentsOf: core.catalog.orderedItems.filter { !householdIds.contains($0.id) })
        for index in merged.indices {
            let id = merged[index].id
            if pendingFavoriteTasks[id] != nil, let visible = onScreen[id] {
                merged[index].favourite = visible
            } else {
                merged[index].favourite = household.favoriteIds.contains(CatalogSyncMapping.key(id.uuidString))
            }
        }
        recipes = merged
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
            guard !isInvalidated else { return nil }
            return adoptDetailed(detailed)
        } catch {
            guard !isInvalidated else { return nil }
            errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
            return recipes.first(where: { $0.id == recipeId })
        }
    }

    /// Pełna wersja przepisu (szczegóły) na liście i w stanie, z którego lista
    /// się przebudowuje — inaczej następny sync cofałby ją do wersji z listy.
    @discardableResult
    private func adoptDetailed(_ detailed: Recipe) -> Recipe {
        var detailed = detailed
        let recipeId = detailed.id
        if let index = recipes.firstIndex(where: { $0.id == recipeId }) {
            // Szczegół (`recipes:findById`, `recipes:openShared`) nie niesie
            // aktywnego linku domu — ten przychodzi tylko ze stanem domu.
            // Bez tego pełna wersja gasiła „Wyłącz link” do następnego
            // odświeżenia.
            if detailed.shareUrl == nil {
                detailed.shareUrl = recipes[index].shareUrl
            }
            recipes[index] = detailed
        } else {
            recipes.append(detailed)
        }
        core.replaceItem(
            catalogKey: CatalogSyncMapping.key(recipeId.uuidString),
            with: ApiRecipeRepository.catalogCopy(detailed),
            householdItem: detailed,
            isSame: { $0.id == recipeId }
        )
        return detailed
    }

    // MARK: - Udostępnianie

    /// Adres przepisu do wysłania. Link przepisu DOMU od razu zostaje na
    /// przepisie (`shareUrl`), więc „Wyłącz link” pojawia się bez czekania
    /// na `recipes:changed`, które dostają pozostali domownicy.
    func shareLink(for recipeId: UUID) async throws -> URL {
        let link = try await repository.createShareLink(recipeId: recipeId)
        if link.isHouseholdLink {
            applyShareUrl(link.url, to: recipeId)
        }
        return link.url
    }

    /// „Wyłącz link” — na zawsze; następne „Udostępnij” wyda nowy adres.
    /// `revoked == false` (link zgasił już ktoś inny) to dla użytkownika ten
    /// sam wynik, więc nie ma osobnej ścieżki.
    func revokeShareLink(for recipeId: UUID) async throws {
        _ = try await repository.revokeShareLink(recipeId: recipeId)
        applyShareUrl(nil, to: recipeId)
    }

    /// Licznik „udostępniono” — po faktycznym wysłaniu. Cichy: jego błąd
    /// niczego nie zmienia po stronie użytkownika.
    func markShared(_ recipeId: UUID) async {
        try? await repository.markRecipeShared(recipeId: recipeId)
    }

    /// Przepis spod linku. Przepis katalogu i przepis tego domu trafiają na
    /// listę w pełnej wersji (jak po `loadRecipeDetail`), żeby szczegół mógł
    /// brać ŻYWY przepis — z sercem, które nadąża za zapisem. Cudzy przepis
    /// (`.shared`) nie należy ani do katalogu, ani do domu — nie wchodzi nigdzie.
    func openRecipeLink(_ target: RecipeLinkTarget) async throws -> OpenedRecipeLink {
        let opened = try await repository.openRecipeLink(target)
        guard !isInvalidated else { throw CancellationError() }
        if opened.origin != .shared {
            adoptDetailed(opened.recipe)
        }
        return opened
    }

    /// „Zapisz u siebie” — kopia cudzego przepisu w tym domu. Stan domu
    /// odświeża się od razu (kopia ma być na liście, zanim ktoś zamknie
    /// arkusz), a nie dopiero po `recipes:changed` (`CREATED`), które tu
    /// i tak przyjdzie.
    func saveSharedRecipe(token: String) async throws -> Recipe {
        let copy = try await repository.saveSharedRecipe(token: token)
        guard !isInvalidated else { throw CancellationError() }
        do {
            try await refreshHouseholdState()
            rebuildRecipes()
        } catch {
            // Kopia jest zapisana — lista dojedzie ze zdarzeniem albo przy
            // następnym odświeżeniu.
        }
        return copy
    }

    private func applyShareUrl(_ url: URL?, to recipeId: UUID) {
        guard !isInvalidated, let index = recipes.firstIndex(where: { $0.id == recipeId }) else { return }
        recipes[index].shareUrl = url
        let updated = recipes[index]
        core.replaceItem(
            catalogKey: CatalogSyncMapping.key(recipeId.uuidString),
            with: ApiRecipeRepository.catalogCopy(updated),
            householdItem: updated,
            isSame: { $0.id == recipeId }
        )
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
        guard !isInvalidated,
              let index = recipes.firstIndex(where: { $0.id == recipeId }) else { return }
        let previous = recipes[index].favourite
        let next = !previous
        let key = CatalogSyncMapping.key(recipeId.uuidString)

        recipes[index].favourite = next
        // Od razu także w stanie domu: przebudowa listy (sync, odświeżenie
        // domu) w oknie przed odpowiedzią serwera nie cofa serduszka.
        core.setFavorite(key, next)

        if pendingFavoriteTasks[recipeId] == nil {
            pendingFavoriteOriginalState[recipeId] = previous
        }
        pendingFavoriteTasks[recipeId]?.cancel()

        pendingFavoriteTasks[recipeId] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled, !self.isInvalidated else { return }

            let originalState = self.pendingFavoriteOriginalState[recipeId] ?? previous
            self.pendingFavoriteTasks[recipeId] = nil
            self.pendingFavoriteOriginalState[recipeId] = nil

            guard let finalIndex = self.recipes.firstIndex(where: { $0.id == recipeId }) else { return }
            let finalState = self.recipes[finalIndex].favourite

            if finalState == originalState { return }

            do {
                try await self.repository.setFavorite(recipeId: recipeId, isFavorite: finalState)
                guard !self.isInvalidated else { return }
                self.core.setFavorite(key, finalState)
            } catch {
                guard !self.isInvalidated else { return }
                self.core.setFavorite(key, originalState)
                if let rollbackIndex = self.recipes.firstIndex(where: { $0.id == recipeId }) {
                    self.recipes[rollbackIndex].favourite = originalState
                }
                self.errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
            }
        }
    }

    // MARK: - Cache

    /// Cache pokazuje katalog od razu; świeżość zapewnia następny sync (delta
    /// od zapisanej rewizji), a nie wiek pliku.
    private func loadCache() -> Bool {
        switch core.loadFromDisk() {
        case .valid:
            break
        case .missing, .unsupportedVersion, .corrupted:
            // Brak używalnego pliku — stary v12 (jeśli jest) pokaże katalog
            // do końca pierwszego snapshotu.
            loadLegacyCatalogIfPresent()
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
        let url = core.files.directory.appendingPathComponent(Self.legacyCacheFileName)
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(LegacyCachePayload.self, from: data),
              Date().timeIntervalSince(payload.savedAt) <= 60 * 60 * 12,
              !payload.recipes.isEmpty else { return }
        core.adoptLegacyCatalog(
            payload.recipes.map { (id: CatalogSyncMapping.key($0.id.uuidString), item: $0) },
            favoriteIds: Set(payload.recipes.filter(\.favourite).map { CatalogSyncMapping.key($0.id.uuidString) }),
            clearHousehold: false
        )
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
