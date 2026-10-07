import Foundation

// Stan katalogu JEDNEJ sesji (konto + dom) i jego zapis na dysk, z cyklem życia.
// Czysta logika — tylko Foundation — sprawdza ją `Scripts/catalog-sync-check.sh`.
//
// Problem, który to zamyka: zapytanie wystartowane przed wylogowaniem kończy
// się po nim. Sama szeregowa kolejka zapisów nie wystarcza — stara instancja
// opublikowałaby wynik i dopisała do kolejki zapis PO skasowaniu pliku,
// odtwarzając prywatne dane poprzedniego konta. Dlatego:
// - każda sesja ma token; na dysk pisze wyłącznie AKTYWNY token, sprawdzany
//   pod zamkiem w chwili zapisu (także zapis, który czekał w kolejce);
// - `invalidate()` odbiera token od razu, a stan w pamięci przestaje
//   przyjmować wyniki — każde `await` kończy się sprawdzeniem ważności.

/// Pliki cache katalogu w jednym katalogu.
struct CatalogCacheFiles {
    let directory: URL
    /// Publiczny katalog z rewizją — przeżywa wylogowanie.
    var catalogURL: URL { directory.appendingPathComponent("recipe_catalog.json") }
    /// Przepisy domu i ulubione — prywatne, z właścicielem w środku.
    var householdURL: URL { directory.appendingPathComponent("recipe_catalog_household.json") }

    /// Pliki aplikacji. 7.10.2026 (audyt 2.5): katalog offline poza kopią
    /// zapasową zamiast `Documents` — stare pliki (także `recipes_catalog_cache_v*`)
    /// przenosi `AppCacheDirectory`, więc katalog nie pobiera się od nowa.
    static var appCache: CatalogCacheFiles {
        CatalogCacheFiles(directory: AppCacheDirectory.directory)
    }
}

/// Kto może pisać pliki cache katalogu. Jeden aktywny token naraz — nowa
/// sesja (`activate`) odbiera prawo zapisu poprzedniej.
final class CatalogCacheGate {
    static let shared = CatalogCacheGate(
        queue: DispatchQueue(label: "recipe-catalog-cache-write", qos: .utility)
    )

    private let lock = NSLock()
    private var active: UUID?
    private let queue: DispatchQueue

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func activate(_ token: UUID) {
        lock.lock()
        active = token
        lock.unlock()
    }

    func revoke(_ token: UUID) {
        lock.lock()
        if active == token { active = nil }
        lock.unlock()
    }

    func isActive(_ token: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return active == token
    }

    /// Zapis w kolejce. Token sprawdzany jest dopiero w chwili zapisu i POD
    /// zamkiem, więc `revoke`/`activate` nie wciśnie się między sprawdzenie
    /// a zapis: albo zapis skończy się przed unieważnieniem (a kasowanie,
    /// które idzie tą samą kolejką, przyjdzie po nim), albo się nie odbędzie.
    func write(token: UUID, to url: URL, encode: @escaping () -> Data?) {
        queue.async { [self] in
            guard isActive(token), let data = encode() else { return }
            lock.lock()
            defer { lock.unlock() }
            guard active == token else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    func remove(_ url: URL) {
        queue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Pliki sprzed synchronizacji rewizją: `recipes_catalog_cache_v<N>.json`.
    func removeLegacyFiles(in directory: URL) {
        queue.async {
            let fm = FileManager.default
            guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
            for name in names where name.hasPrefix("recipes_catalog_cache_v") && name.hasSuffix(".json") {
                try? fm.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    /// Czeka, aż kolejka wykona wszystko, co już w niej jest (sprawdziany).
    func flush() {
        queue.sync {}
    }
}

/// Stan katalogu jednej sesji. `Item` = przepis (w aplikacji `Recipe`).
final class CatalogSyncCore<Item: Codable> {
    struct Household {
        var items: [Item]
        /// Id przepisów małymi literami (`CatalogSyncMapping.key`).
        var favoriteIds: Set<String>
    }

    enum SyncOutcome: Equatable {
        case delta(changed: Int)
        case snapshot
    }

    let ownerKey: String?
    let files: CatalogCacheFiles
    private let gate: CatalogCacheGate
    private let token = UUID()
    private(set) var isInvalidated = false
    private(set) var catalog = CatalogSyncState<Item>()
    /// Katalog ze starej drogi (plik v12 albo `recipes:findAll`) — miesza
    /// przepisy domu z publicznymi, więc nie trafia do pliku publicznego.
    private(set) var catalogIsLegacy = false
    private(set) var household = Household(items: [], favoriteIds: [])

    /// Sesja z właścicielem od razu przejmuje prawo zapisu (poprzednia je
    /// traci). Bez właściciela (domyślny store środowiska) nie pisze nic.
    init(ownerKey: String?, files: CatalogCacheFiles, gate: CatalogCacheGate) {
        self.ownerKey = ownerKey
        self.files = files
        self.gate = gate
        if ownerKey != nil { gate.activate(token) }
    }

    /// Wylogowanie albo zastąpienie sesji: od tej chwili nic, co ta instancja
    /// dostanie, nie trafi ani do jej stanu, ani na dysk.
    func invalidate() {
        isInvalidated = true
        gate.revoke(token)
    }

    func checkValid() throws {
        if isInvalidated { throw CancellationError() }
    }

    /// Wylogowanie: prywatny plik domu i stare pliki; publiczny katalog zostaje.
    static func clearPrivateFiles(_ files: CatalogCacheFiles, gate: CatalogCacheGate) {
        gate.remove(files.householdURL)
        gate.removeLegacyFiles(in: files.directory)
    }

    // MARK: Odczyt z dysku

    /// Katalog z pliku (jeśli poprawny) i stan domu TEGO właściciela.
    /// Plik nieczytelny albo w innym formacie jest usuwany — snapshot zbuduje nowy.
    @discardableResult
    func loadFromDisk() -> CatalogCacheEnvelope<Item>.Load {
        let load = CatalogCacheEnvelope<Item>.load(from: try? Data(contentsOf: files.catalogURL))
        switch load {
        case .valid(let state):
            catalog = state
            catalogIsLegacy = false
        case .unsupportedVersion, .corrupted:
            gate.remove(files.catalogURL)
        case .missing:
            break
        }
        if let ownerKey,
           let envelope = HouseholdRecipeCacheEnvelope<Item>.load(
               from: try? Data(contentsOf: files.householdURL),
               ownerKey: ownerKey
           ) {
            household = Household(items: envelope.recipes, favoriteIds: Set(envelope.favoriteRecipeIds))
        }
        return load
    }

    /// Katalog ze starej drogi — tylko w pamięci, bez rewizji.
    func adoptLegacyCatalog(_ entries: [(id: String, item: Item)], favoriteIds: Set<String>, clearHousehold: Bool) {
        guard !isInvalidated else { return }
        catalog = CatalogSyncState(
            ids: entries.map { $0.id },
            items: Dictionary(entries.map { ($0.id, $0.item) }, uniquingKeysWith: { first, _ in first }),
            revision: nil
        )
        catalogIsLegacy = true
        if clearHousehold { household.items = [] }
        household.favoriteIds = favoriteIds
    }

    // MARK: Synchronizacja

    /// Jeden przebieg (delta albo snapshot). Wynik trafia do stanu i na dysk
    /// tylko wtedy, gdy sesja jest nadal ważna PO powrocie z sieci.
    func syncCatalog(using engine: CatalogSyncEngine<Item>) async throws -> SyncOutcome {
        try checkValid()
        if !catalogIsLegacy, catalog.revision != nil {
            let outcome = try await engine.pullDelta(onto: catalog)
            try checkValid()
            switch outcome {
            case .applied(let next, let changed):
                commit(next)
                return .delta(changed: changed)
            case .resetRequired:
                // Starego katalogu nie naprawiamy; rewizja znika także z pliku,
                // katalog zostaje na ekranie do końca snapshotu.
                catalog.forgetRevision()
                persistCatalog()
            }
        }
        let fresh = try await engine.pullSnapshot()
        try checkValid()
        commit(fresh)
        return .snapshot
    }

    private func commit(_ next: CatalogSyncState<Item>) {
        catalog = next
        catalogIsLegacy = false
        persistCatalog()
        gate.removeLegacyFiles(in: files.directory)
    }

    /// Stan domu z serwera; publikowany tylko przez ważną sesję.
    func refreshHousehold(fetch: () async throws -> Household) async throws {
        try checkValid()
        let fresh = try await fetch()
        try checkValid()
        household = fresh
        persistHousehold()
    }

    // MARK: Zmiany lokalne

    func setFavorite(_ id: String, _ isFavorite: Bool) {
        guard !isInvalidated else { return }
        if isFavorite {
            household.favoriteIds.insert(id)
        } else {
            household.favoriteIds.remove(id)
        }
        persistHousehold()
    }

    /// Pełniejsza wersja przepisu (szczegóły) — do tej części, która go zna.
    func replaceItem(catalogKey: String, with catalogItem: Item, householdItem: Item, isSame: (Item) -> Bool) {
        guard !isInvalidated else { return }
        if let index = household.items.firstIndex(where: isSame) {
            household.items[index] = householdItem
            persistHousehold()
        } else if catalog.items[catalogKey] != nil {
            catalog.replaceKnownItem(id: catalogKey, with: catalogItem)
            persistCatalog()
        }
    }

    // MARK: Zapis

    private func persistCatalog() {
        guard !catalogIsLegacy, !isInvalidated else { return }
        let envelope = CatalogCacheEnvelope(state: catalog, savedAt: Date())
        gate.write(token: token, to: files.catalogURL) { try? JSONEncoder().encode(envelope) }
    }

    private func persistHousehold() {
        guard let ownerKey, !catalogIsLegacy, !isInvalidated else { return }
        let envelope = HouseholdRecipeCacheEnvelope(
            ownerKey: ownerKey,
            recipes: household.items,
            favoriteRecipeIds: household.favoriteIds.sorted(),
            savedAt: Date()
        )
        gate.write(token: token, to: files.householdURL) { try? JSONEncoder().encode(envelope) }
    }
}
