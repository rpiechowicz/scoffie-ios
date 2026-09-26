import Foundation

/// Lokalny stan publicznego katalogu synchronizowanego z serwerem
/// (`catalog:snapshot` / `catalog:changes`, backend workstream Etap 4A).
///
/// Czysta logika bez SwiftUI i sieci — sprawdza ją `Scripts/catalog-sync-check.sh`.
/// Zasady, na których stoi poprawność:
/// - strony snapshotu i delty ZBIERAMY w bufor, a stan i rewizję podmieniamy
///   dopiero po ostatniej stronie. Przerwany sync nie zostawia rewizji, której
///   klient nie zastosował w całości;
/// - upsert nadpisuje po `id` (albo dopisuje nowy), tombstone usuwa — także id,
///   którego klient nie zna. Dzięki temu ta sama delta zastosowana dwa razy
///   daje ten sam stan (idempotencja), a zmiana z czasu snapshotu, która
///   wraca w następnej delcie, nic nie psuje.
struct CatalogSyncState<Item> {
    /// Kolejność przepisów (snapshot: kolejność serwera; nowe dopisywane na końcu).
    private(set) var ids: [String] = []
    private(set) var items: [String: Item] = [:]
    /// Rewizja W CAŁOŚCI zastosowanego stanu; `nil` = trzeba zrobić snapshot.
    private(set) var revision: String?

    init() {}

    init(ids: [String], items: [String: Item], revision: String?) {
        self.ids = ids.filter { items[$0] != nil }
        self.items = items
        self.revision = revision
    }

    var orderedItems: [Item] { ids.compactMap { items[$0] } }

    /// Pełny snapshot (wszystkie strony) zastępuje stan i ustawia rewizję.
    mutating func applySnapshot(_ buffer: CatalogSyncBuffer<Item>, revision: String) {
        ids = buffer.upsertOrder
        items = buffer.upserts
        self.revision = revision
    }

    /// Delta (wszystkie strony) nakłada się na stan; rewizja dopiero po całości.
    mutating func applyDelta(_ buffer: CatalogSyncBuffer<Item>, revision: String) {
        for id in buffer.tombstones where items[id] != nil {
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

    /// Serwer odpowiedział RESET_REQUIRED — następny sync to snapshot.
    mutating func invalidateRevision() {
        revision = nil
    }
}

/// Strony jednego przebiegu synchronizacji, zanim trafią do stanu.
struct CatalogSyncBuffer<Item> {
    private(set) var upserts: [String: Item] = [:]
    private(set) var upsertOrder: [String] = []
    private(set) var tombstones: Set<String> = []

    init() {}

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
