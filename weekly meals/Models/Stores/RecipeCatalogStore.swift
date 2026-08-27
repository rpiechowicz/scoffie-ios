import Foundation
import Observation
import SwiftUI

// Wydzielono z WeeklyMealStore.swift — wcześniej oba Observable były w jednym pliku 1476 linii.

@Observable
final class RecipeCatalogStore {
    private struct RecipeCatalogCachePayload: Codable {
        let recipes: [Recipe]
        let savedAt: Date
    }

    private let repository: RecipeRepository
    private(set) var recipes: [Recipe] = []
    private(set) var didLoad: Bool = false
    var isLoading: Bool = false
    var isLoadingMore: Bool = false
    var hasMore: Bool = true
    var errorMessage: String?
    private var currentPage: Int = 0
    private let pageSize: Int = 100
    /// Bezpiecznik pętli pełnego ładowania — 40 stron po 100 to 4000 przepisów,
    /// daleko ponad realny rozmiar katalogu.
    private let maxCatalogPages: Int = 40
    private let cacheMaxAge: TimeInterval = 60 * 60 * 12 // 12 h
    private let maxFetchAttempts: Int = 3
    private var pendingRealtimeReloadTask: Task<Void, Never>?
    private var pendingFavoriteTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingFavoriteOriginalState: [UUID: Bool] = [:]
    /// Odracza pokazanie błędów łączności z `reload()` — patrz komentarz
    /// w `ConnectivityErrorGate`. Błędy akcji użytkownika (ulubione,
    /// paginacja) pokazują się bez zmian, od razu.
    private let connectivityErrorGate = ConnectivityErrorGate()

    private var cacheURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            // v9: doszła sekcja „Przekąski i desery". Zmieniło się i pole
            // (`baseSlot`), i sposób liczenia `category` dla slotów pomiędzy
            // posiłkami, więc cache z v8 trzymałby te dania w starych sekcjach
            // przez pełne 12 h ważności.
            // v8: doszły pola sourceProvider/sourceRecipeId (badge Thermomixa) —
            // stary cache dekodowałby się bez nich i katalog nie miałby badge'ów
            // aż do pełnego przeładowania.
            .appendingPathComponent("recipes_catalog_cache_v9.json")
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
                if let index = self.recipes.firstIndex(where: { $0.id == recipeId }) {
                    self.recipes[index].favourite = isFavorite
                    self.saveCache()
                }
            }
        }
        self.repository.observeRealtimeReconnect { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard self.didLoad else { return }
                self.pendingRealtimeReloadTask?.cancel()
                self.pendingRealtimeReloadTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard let self else { return }
                    await self.reload()
                }
            }
        }
    }

    func loadIfNeeded() async {
        guard !didLoad else { return }
        if loadCacheIfFresh() {
            didLoad = true
            errorMessage = nil
            Task { @MainActor [weak self] in
                await self?.reload()
            }
            return
        }
        await reload()
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        await connectivityErrorGate.reset()
        do {
            // Ekran Przepisów buduje sekcje po kategoriach po stronie klienta,
            // a API sortuje od najnowszych — po rozroście bazy sama pierwsza
            // strona potrafi nie zawierać ani jednego śniadania i sekcja
            // wygląda na pustą. Dlatego katalog ciągnie wszystkie strony od razu.
            var all: [Recipe] = []
            var page = 1
            while true {
                let fetched = try await fetchPageWithRetry(page: page)
                all.append(contentsOf: fetched.recipes)
                // Koniec katalogu poznajemy po tym, ile wierszy przysłał
                // serwer, a nie po tym, ile z nich dało się zmapować — patrz
                // `RecipePage`.
                if fetched.receivedCount < pageSize || page >= maxCatalogPages { break }
                page += 1
            }
            recipes = all
            currentPage = page
            hasMore = false
            didLoad = true
            saveCache()
        } catch {
            // Błąd łączności z odświeżenia pokazuje się dopiero, gdy się
            // utrzyma — reconnect po powrocie z tła gasił go po ~0,3 s
            // i banner tylko migał.
            await connectivityErrorGate.publish(error) { [weak self] message in
                self?.errorMessage = message
            }
        }
        isLoading = false
    }

    func loadNextPageIfNeeded(currentItemId: UUID?, threshold: Int = 6) async {
        guard let currentItemId else { return }
        guard hasMore, !isLoading, !isLoadingMore, didLoad else { return }
        guard let index = recipes.firstIndex(where: { $0.id == currentItemId }) else { return }
        let triggerIndex = max(0, recipes.count - max(1, threshold))
        guard index >= triggerIndex else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = currentPage + 1
            let fetched = try await fetchPageWithRetry(page: nextPage)
            recipes.append(contentsOf: fetched.recipes)
            currentPage = nextPage
            // Ta sama zasada co w `reload()`: o kolejnej stronie decyduje
            // liczba wierszy z serwera, nie liczba tych zmapowanych.
            hasMore = fetched.receivedCount >= pageSize
            saveCache()
        } catch {
            errorMessage = UserFacingErrorMapper.message(from: error)
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
            saveCache()
            return detailed
        } catch {
            errorMessage = UserFacingErrorMapper.message(from: error)
            return recipes.first(where: { $0.id == recipeId })
        }
    }

    func toggleFavorite(recipeId: UUID) async {
        guard let index = recipes.firstIndex(where: { $0.id == recipeId }) else { return }
        let previous = recipes[index].favourite
        let next = !previous

        recipes[index].favourite = next

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
                self.saveCache()
            } catch {
                if let rollbackIndex = self.recipes.firstIndex(where: { $0.id == recipeId }) {
                    self.recipes[rollbackIndex].favourite = originalState
                }
                self.errorMessage = UserFacingErrorMapper.message(from: error)
            }
        }
    }

    private func saveCache() {
        do {
            let payload = RecipeCatalogCachePayload(recipes: recipes, savedAt: Date())
            let data = try JSONEncoder().encode(payload)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // intentionally ignore cache write failures
        }
    }

    private func loadCacheIfFresh() -> Bool {
        guard let data = try? Data(contentsOf: cacheURL) else { return false }
        guard let payload = try? JSONDecoder().decode(RecipeCatalogCachePayload.self, from: data) else { return false }
        guard Date().timeIntervalSince(payload.savedAt) <= cacheMaxAge else { return false }
        recipes = payload.recipes
        currentPage = max(1, Int(ceil(Double(payload.recipes.count) / Double(pageSize))))
        // Cache trzyma pełny katalog (reload ładuje wszystkie strony), a tuż po
        // odczycie i tak startuje pełny reload — dociąganie stron ze scrolla
        // tylko dublowałoby wiersze w tym oknie.
        hasMore = false
        return !payload.recipes.isEmpty
    }

    private func fetchPageWithRetry(page: Int) async throws -> RecipePage {
        var lastError: Error?
        for attempt in 1...maxFetchAttempts {
            do {
                return try await repository.fetchRecipes(page: page, limit: pageSize)
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
