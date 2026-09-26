import Foundation

// Synchronizacja katalogu (backend workstream Etap 4A) — logika klienta bez
// SwiftUI i bez targetu testów, tak jak `Scripts/CardContract`.
// Uruchomienie: `sh Scripts/catalog-sync-check.sh`.

var failures = 0

func check(_ condition: Bool, _ name: String) {
    if condition {
        print("OK   \(name)")
    } else {
        failures += 1
        print("BŁĄD \(name)")
    }
}

func buffer(upserts: [(String, String)] = [], tombstones: [String] = []) -> CatalogSyncBuffer<String> {
    var result = CatalogSyncBuffer<String>()
    result.addTombstones(tombstones)
    result.addUpserts(upserts.map { (id: $0.0, item: $0.1) })
    return result
}

// Snapshot 5100 przepisów w 11 stronach — bez sufitu 4000.
var snapshotBuffer = CatalogSyncBuffer<String>()
for page in 0..<11 {
    let start = page * 500
    let end = min(5100, start + 500)
    snapshotBuffer.addUpserts((start..<end).map { (id: "r\($0)", item: "Danie \($0)") })
}
var state = CatalogSyncState<String>()
check(state.revision == nil, "brak rewizji = pierwszy sync to snapshot")
state.applySnapshot(snapshotBuffer, revision: "e.100")
check(state.orderedItems.count == 5100, "snapshot 5100 przepisów w całości (bez limitu 4000)")
check(state.revision == "e.100", "rewizja snapshotu zapisana po ostatniej stronie")

// Delta: zmiana jednego, nowy, tombstone (także nieznanego id).
let delta = buffer(
    upserts: [("r17", "Danie 17 — nowy tytuł"), ("r9999", "Nowe danie")],
    tombstones: ["r18", "nieznany"]
)
var once = state
once.applyDelta(delta, revision: "e.105")
check(once.items["r17"] == "Danie 17 — nowy tytuł", "upsert nadpisuje istniejący przepis")
check(once.items["r9999"] == "Nowe danie", "upsert dopisuje nowy przepis")
check(once.items["r18"] == nil, "tombstone usuwa przepis")
check(once.orderedItems.count == 5100, "5100 − 1 usunięty + 1 nowy")
check(once.revision == "e.105", "rewizja delty po zastosowaniu całości")

// Idempotencja: ta sama delta drugi raz nic nie zmienia.
var twice = once
twice.applyDelta(delta, revision: "e.105")
check(twice.orderedItems == once.orderedItems, "ta sama delta dwa razy = ten sam stan")

// Przerwany sync: bufor bez zastosowania nie rusza stanu ani rewizji.
var interrupted = once
var partial = CatalogSyncBuffer<String>()
partial.addUpserts([(id: "r1", item: "Zmiana z przerwanego syncu")])
check(interrupted.revision == "e.105" && interrupted.items["r1"] == "Danie 1",
      "przerwany sync nie zapisuje rewizji ani zmian")
_ = partial

// RESET_REQUIRED: rewizja kasowana, następny sync to snapshot.
interrupted.invalidateRevision()
check(interrupted.revision == nil, "RESET_REQUIRED kasuje rewizję")

// W jednym przebiegu: upsert i tombstone tego samego id — wygrywa późniejszy.
var mixed = CatalogSyncBuffer<String>()
mixed.addUpserts([(id: "r5", item: "Wersja A")])
mixed.addTombstones(["r5"])
var afterMixed = once
afterMixed.applyDelta(mixed, revision: "e.106")
check(afterMixed.items["r5"] == nil, "tombstone po upsercie w tym samym przebiegu usuwa")

// Stan odtworzony z cache'u (ids + items + rewizja) daje deltę dalej.
let restored = CatalogSyncState(ids: once.ids, items: once.items, revision: once.revision)
check(restored.orderedItems == once.orderedItems && restored.revision == "e.105",
      "stan z cache'u = stan przed zapisem")

if failures > 0 {
    print("\n\(failures) scenariuszy nie przeszło")
    exit(1)
}
print("\nWszystkie scenariusze przeszły")
