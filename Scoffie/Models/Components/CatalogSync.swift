import Foundation

// Synchronizacja publicznego katalogu z serwerem (`catalog:snapshot` /
// `catalog:changes`, backend `CatalogSyncService`). Czysta logika — tylko
// Foundation, bez SwiftUI i sieci — sprawdza ją `Scripts/catalog-sync-check.sh`.
//
// Zasady, na których stoi poprawność:
// - przebieg (wszystkie strony snapshotu albo delty) pracuje na KOPII stanu
//   i oddaje nowy stan dopiero po ostatniej stronie. Przerwanie w połowie
//   (sieć, zabita aplikacja, anulowanie) nie zmienia niczego: zostaje stary
//   katalog ze starą rewizją, a następny przebieg zaczyna od niej;
// - rewizja to NIEPRZEZROCZYSTY token serwera — klient go nie parsuje, tylko
//   odsyła. Pierwsza strona go ustala, kolejne strony tego przebiegu muszą
//   nieść ten sam, inaczej przebieg jest odrzucany;
// - upsert nadpisuje po `id`, tombstone usuwa (także id, którego klient nie
//   zna). Ta sama delta zastosowana dwa razy daje ten sam stan, więc
//   powtórzona dostawa nic nie psuje.

/// Lokalny stan publicznego katalogu.
struct CatalogSyncState<Item> {
    /// Kolejność przepisów (snapshot: kolejność serwera; nowe na końcu).
    private(set) var ids: [String] = []
    private(set) var items: [String: Item] = [:]
    /// Rewizja W CAŁOŚCI zastosowanego stanu; `nil` = następny sync to snapshot
    /// (katalog, jeśli jest, zostaje na ekranie do czasu jego zakończenia).
    private(set) var revision: String?

    init() {}

    init(ids: [String], items: [String: Item], revision: String?) {
        var seen = Set<String>()
        self.ids = ids.filter { items[$0] != nil && seen.insert($0).inserted }
        self.items = items.filter { seen.contains($0.key) }
        self.revision = revision
    }

    var isEmpty: Bool { ids.isEmpty }
    var orderedItems: [Item] { ids.compactMap { items[$0] } }

    /// Pełny snapshot zastępuje stan i ustawia rewizję.
    mutating func applySnapshot(_ buffer: CatalogSyncBuffer<Item>, revision: String) {
        ids = buffer.upsertOrder
        items = buffer.upserts
        self.revision = revision
    }

    /// Delta nakłada się na stan; rewizja dopiero po całości.
    mutating func applyDelta(_ buffer: CatalogSyncBuffer<Item>, revision: String) {
        for id in buffer.tombstones {
            items[id] = nil
        }
        if !buffer.tombstones.isEmpty {
            ids.removeAll { buffer.tombstones.contains($0) }
        }
        for id in buffer.upsertOrder {
            guard let item = buffer.upserts[id] else { continue }
            if items[id] == nil { ids.append(id) }
            items[id] = item
        }
        self.revision = revision
    }

    /// Pełniejsza wersja przepisu, który stan już zna (np. szczegóły). Rewizji
    /// nie rusza — to ten sam przepis, najwyżej świeższy niż rewizja, a delta
    /// i tak go potem nadpisze.
    mutating func replaceKnownItem(id: String, with item: Item) {
        guard items[id] != nil else { return }
        items[id] = item
    }

    /// RESET_REQUIRED: rewizja do wyrzucenia, katalog zostaje do czasu snapshotu.
    mutating func forgetRevision() {
        revision = nil
    }
}

/// Strony jednego przebiegu, zanim trafią do stanu.
struct CatalogSyncBuffer<Item> {
    private(set) var upserts: [String: Item] = [:]
    private(set) var upsertOrder: [String] = []
    private(set) var tombstones: Set<String> = []

    init() {}

    var changedCount: Int { upsertOrder.count + tombstones.count }

    mutating func addUpserts(_ entries: [(id: String, item: Item)]) {
        for entry in entries {
            tombstones.remove(entry.id)
            if upserts[entry.id] == nil { upsertOrder.append(entry.id) }
            upserts[entry.id] = entry.item
        }
    }

    mutating func addTombstones(_ ids: [String]) {
        for id in ids {
            if upserts.removeValue(forKey: id) != nil {
                upsertOrder.removeAll { $0 == id }
            }
            tombstones.insert(id)
        }
    }
}

/// Tryb odpowiedzi serwera na `catalog:snapshot` / `catalog:changes`.
enum CatalogSyncMode: String, Codable {
    case snapshot = "SNAPSHOT"
    case delta = "DELTA"
    case resetRequired = "RESET_REQUIRED"
}

/// Strona `catalog:snapshot` po zmapowaniu przepisów.
struct CatalogSnapshotPage<Item> {
    let resetRequired: Bool
    let revision: String
    let items: [(id: String, item: Item)]
    let nextCursor: String?
}

/// Strona `catalog:changes`. Wiersz, którego klient nie umie zmapować, idzie
/// jako tombstone — lepiej zdjąć przepis, niż pokazać jego starą wersję.
struct CatalogChangesPage<Item> {
    let resetRequired: Bool
    let revision: String
    let upserts: [(id: String, item: Item)]
    let tombstones: [String]
    let nextCursor: String?
}

enum CatalogSyncError: Error, Equatable {
    /// Strony jednego przebiegu niosą różne rewizje — przebieg odrzucony.
    case inconsistentPages
    /// Serwer oddał ten sam kursor drugi raz — przerwane, żeby nie kręcić się w kółko.
    case cursorDidNotAdvance
    /// Snapshot dwa razy z rzędu zakończył się RESET_REQUIRED.
    case snapshotKeepsResetting
    case tooManyPages
}

enum CatalogDeltaOutcome<Item> {
    /// Nowy stan (kopia z nałożoną deltą) i liczba zmienionych przepisów.
    case applied(CatalogSyncState<Item>, changed: Int)
    /// Serwer nie zna rewizji klienta — potrzebny snapshot.
    case resetRequired
}

/// Pobiera strony i składa z nich nowy stan. Niczego nie zapisuje — nowy stan
/// oddaje wołającemu, który podmienia go razem z plikiem cache.
struct CatalogSyncEngine<Item> {
    let pageLimit: Int
    let fetchSnapshotPage: (_ revision: String?, _ cursor: String?, _ limit: Int) async throws -> CatalogSnapshotPage<Item>
    let fetchChangesPage: (_ sinceRevision: String, _ untilRevision: String?, _ cursor: String?, _ limit: Int) async throws -> CatalogChangesPage<Item>
    /// Bezpiecznik pętli — przy stronach po 500 to 5 mln przepisów.
    var maxPages: Int = 10_000

    /// Delta od rewizji `state`: wszystkie strony do bufora, `untilRevision`
    /// z pierwszej strony, nowy stan dopiero po ostatniej.
    func pullDelta(onto state: CatalogSyncState<Item>) async throws -> CatalogDeltaOutcome<Item> {
        guard let since = state.revision else { return .resetRequired }
        var buffer = CatalogSyncBuffer<Item>()
        var until: String?
        var cursor: String?
        var pages = 0
        repeat {
            try Task.checkCancellation()
            pages += 1
            if pages > maxPages { throw CatalogSyncError.tooManyPages }
            let page = try await fetchChangesPage(since, until, cursor, pageLimit)
            if page.resetRequired { return .resetRequired }
            if let until, page.revision != until { throw CatalogSyncError.inconsistentPages }
            until = until ?? page.revision
            buffer.addTombstones(page.tombstones)
            buffer.addUpserts(page.upserts)
            if let next = page.nextCursor, next == cursor { throw CatalogSyncError.cursorDidNotAdvance }
            cursor = page.nextCursor
        } while cursor != nil
        try Task.checkCancellation()
        var next = state
        next.applyDelta(buffer, revision: until ?? since)
        return .applied(next, changed: buffer.changedCount)
    }

    /// Snapshot od zera: znacznik z pierwszej strony odsyłany na kolejnych.
    /// RESET_REQUIRED w trakcie (np. nowa epoka katalogu) = jedna próba od nowa.
    func pullSnapshot() async throws -> CatalogSyncState<Item> {
        for _ in 0..<2 {
            var buffer = CatalogSyncBuffer<Item>()
            var revision: String?
            var cursor: String?
            var pages = 0
            var restart = false
            repeat {
                try Task.checkCancellation()
                pages += 1
                if pages > maxPages { throw CatalogSyncError.tooManyPages }
                let page = try await fetchSnapshotPage(revision, cursor, pageLimit)
                if page.resetRequired {
                    restart = true
                    break
                }
                if let revision, page.revision != revision { throw CatalogSyncError.inconsistentPages }
                revision = revision ?? page.revision
                buffer.addUpserts(page.items)
                if let next = page.nextCursor, next == cursor { throw CatalogSyncError.cursorDidNotAdvance }
                cursor = page.nextCursor
            } while cursor != nil
            if !restart, let revision {
                try Task.checkCancellation()
                var fresh = CatalogSyncState<Item>()
                fresh.applySnapshot(buffer, revision: revision)
                return fresh
            }
        }
        throw CatalogSyncError.snapshotKeepsResetting
    }
}

// MARK: - Plik cache

/// Plik cache publicznego katalogu. Format niesie wersję W ŚRODKU pliku —
/// nazwa pliku jest stała, więc zmiana formatu nie zostawia starych plików
/// obok, a stary albo obcy format rozpoznajemy bez zgadywania po nazwie.
///
/// Publiczny katalog jest taki sam dla każdego konta, więc plik przeżywa
/// wylogowanie. Przepisy domu i ulubione leżą osobno
/// (`HouseholdRecipeCacheEnvelope`), przypisane do konta i domu.
struct CatalogCacheEnvelope<Item: Codable>: Codable {
    /// 1: pierwszy format z rewizją (zastępuje `recipes_catalog_cache_v12.json`).
    /// 2: przepisy z taksonomią (kuchnia, rodzaj dania, okazje — 28.09.2026);
    ///    plik z 1 ich nie ma, a delta nie dośle niezmienionych przepisów.
    /// 3: składniki przypraw z `kitchenMeasure` (łyżeczki zamiast gramów —
    ///    30.09.2026); plik z 2 go nie ma.
    /// Zmiana kształtu `Item` albo znaczenia pól = podbij; stary plik zostanie
    /// odrzucony i katalog przyjdzie snapshotem.
    static var currentVersion: Int { 3 }

    let version: Int
    let revision: String?
    let ids: [String]
    let items: [String: Item]
    let savedAt: Date

    init(state: CatalogSyncState<Item>, savedAt: Date) {
        self.version = Self.currentVersion
        self.revision = state.revision
        self.ids = state.ids
        self.items = state.items
        self.savedAt = savedAt
    }

    /// Rozstrzygnięcie odczytu pliku — każdy przypadek poza `.valid` znaczy
    /// „snapshot”; różnią się tylko tym, co zgłosić i czy skasować plik.
    enum Load {
        case missing
        /// Plik z innym numerem formatu (starszy albo nowszy build).
        case unsupportedVersion(Int?)
        /// Nie da się odczytać albo zawartość jest niespójna.
        case corrupted
        case valid(CatalogSyncState<Item>)
    }

    private struct VersionProbe: Decodable {
        let version: Int?
    }

    static func load(from data: Data?) -> Load {
        guard let data, !data.isEmpty else { return .missing }
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data) else { return .corrupted }
        guard probe.version == currentVersion else { return .unsupportedVersion(probe.version) }
        guard let envelope = try? JSONDecoder().decode(Self.self, from: data) else { return .corrupted }
        guard envelope.isConsistent else { return .corrupted }
        if envelope.ids.isEmpty && envelope.revision == nil { return .missing }
        return .valid(CatalogSyncState(ids: envelope.ids, items: envelope.items, revision: envelope.revision))
    }

    /// Te same id na liście i w słowniku, bez powtórzeń, rewizja w granicach
    /// tego, co serwer przyjmie z powrotem (`@MaxLength(64)`).
    var isConsistent: Bool {
        let unique = Set(ids)
        guard unique.count == ids.count, unique == Set(items.keys) else { return false }
        if let revision {
            let trimmed = revision.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed == revision, revision.count <= 64 else { return false }
        }
        return true
    }
}

/// Przepisy gospodarstwa i ulubione domu (`recipes:householdState`) —
/// przypisane do konta i domu (`ownerKey`). Obcy właściciel = plik ignorowany.
struct HouseholdRecipeCacheEnvelope<Item: Codable>: Codable {
    static var currentVersion: Int { 1 }

    let version: Int
    let ownerKey: String
    let recipes: [Item]
    let favoriteRecipeIds: [String]
    let savedAt: Date

    init(ownerKey: String, recipes: [Item], favoriteRecipeIds: [String], savedAt: Date) {
        self.version = Self.currentVersion
        self.ownerKey = ownerKey
        self.recipes = recipes
        self.favoriteRecipeIds = favoriteRecipeIds
        self.savedAt = savedAt
    }

    static func load(from data: Data?, ownerKey: String) -> Self? {
        guard let data, !data.isEmpty,
              let envelope = try? JSONDecoder().decode(Self.self, from: data),
              envelope.version == currentVersion,
              envelope.ownerKey == ownerKey else { return nil }
        return envelope
    }
}
