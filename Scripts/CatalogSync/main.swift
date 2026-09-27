import Foundation

// Synchronizacja katalogu (`Scoffie/Models/Components/CatalogSync.swift`) —
// logika klienta bez SwiftUI i bez targetu testów, tak jak `Scripts/CardContract`.
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

struct Boom: Error {}

/// `BackendRecipeDTO` bierze bazowy adres z `AppEnvironment` (ScoffieApp.swift,
/// z `@main`) — w sprawdzianie wystarczy stały adres.
enum AppEnvironment {
    static let apiBaseURL = URL(string: "https://api.scoffie.invalid")!
}

/// Serwer na niby: katalog `id → tytuł`, strony po `limit` w kolejności id,
/// zapisane wywołania (żeby sprawdzić, co klient odsyła).
final class FakeServer {
    var items: [String: String]
    var revision: String
    var snapshotCalls: [(revision: String?, cursor: String?)] = []
    var changesCalls: [(since: String, until: String?, cursor: String?)] = []
    /// Numer wywołania (od 1), które ma rzucić / oddać RESET_REQUIRED.
    var failOnCall: Int?
    var resetOnCall: Set<Int> = []
    var changed: [String] = []
    var tombstoned: [String] = []
    var forcedRevisionOnCall: [Int: String] = [:]
    var stuckCursor = false

    init(count: Int, revision: String) {
        var items: [String: String] = [:]
        for i in 0..<count { items[String(format: "r%05d", i)] = "Danie \(i)" }
        self.items = items
        self.revision = revision
    }

    private var calls: Int { snapshotCalls.count + changesCalls.count }

    func snapshotPage(_ revision: String?, _ cursor: String?, _ limit: Int) throws -> CatalogSnapshotPage<String> {
        snapshotCalls.append((revision, cursor))
        if calls == failOnCall { throw Boom() }
        if resetOnCall.contains(calls) {
            return CatalogSnapshotPage(resetRequired: true, revision: self.revision, items: [], nextCursor: nil)
        }
        let ids = items.keys.sorted().filter { cursor == nil || $0 > cursor! }
        let page = Array(ids.prefix(limit))
        let next = ids.count > limit ? page.last : nil
        return CatalogSnapshotPage(
            resetRequired: false,
            revision: forcedRevisionOnCall[calls] ?? revision ?? self.revision,
            items: page.map { (id: $0, item: items[$0]!) },
            nextCursor: stuckCursor ? cursor ?? page.last : next
        )
    }

    func changesPage(_ since: String, _ until: String?, _ cursor: String?, _ limit: Int) throws -> CatalogChangesPage<String> {
        changesCalls.append((since, until, cursor))
        if calls == failOnCall { throw Boom() }
        if resetOnCall.contains(calls) {
            return CatalogChangesPage(resetRequired: true, revision: revision, upserts: [], tombstones: [], nextCursor: nil)
        }
        let all = (changed + tombstoned).sorted().filter { cursor == nil || $0 > cursor! }
        let page = Array(all.prefix(limit))
        let next = all.count > limit ? page.last : nil
        return CatalogChangesPage(
            resetRequired: false,
            revision: forcedRevisionOnCall[calls] ?? until ?? revision,
            upserts: page.filter { changed.contains($0) }.map { (id: $0, item: items[$0] ?? "?") },
            tombstones: page.filter { tombstoned.contains($0) },
            nextCursor: next
        )
    }

    func engine(limit: Int = 500) -> CatalogSyncEngine<String> {
        CatalogSyncEngine(
            pageLimit: limit,
            fetchSnapshotPage: { try self.snapshotPage($0, $1, $2) },
            fetchChangesPage: { try self.changesPage($0, $1, $2, $3) }
        )
    }
}

func expectError<E: Error & Equatable>(_ expected: E, _ name: String, _ body: () async throws -> Void) async {
    do {
        try await body()
        check(false, name + " (brak błędu)")
    } catch let error as E {
        check(error == expected, name)
    } catch {
        check(false, name + " (inny błąd: \(error))")
    }
}

// 1. Snapshot 5100 przepisów w 11 stronach — bez sufitu 4000.
let server = FakeServer(count: 5100, revision: "e.100")
var state = try await server.engine().pullSnapshot()
check(state.orderedItems.count == 5100, "snapshot 5100 przepisów w całości (bez limitu 4000)")
check(state.revision == "e.100", "rewizja snapshotu = znacznik z pierwszej strony")
check(server.snapshotCalls.count == 11, "11 stron po 500")
check(server.snapshotCalls[0].revision == nil, "pierwsza strona snapshotu bez rewizji (klucz pominięty, nie null)")
check(server.snapshotCalls.dropFirst().allSatisfy { $0.revision == "e.100" }, "kolejne strony odsyłają rewizję z pierwszej")

// 2. Delta: zmiana, nowy, tombstone (także nieznanego id).
server.items["r00017"] = "Danie 17 — nowy tytuł"
server.items["r99999"] = "Nowe danie"
server.items["r00003"] = nil
server.changed = ["r00017", "r99999"]
server.tombstoned = ["r00003", "nieznany"]
server.revision = "e.104"
guard case .applied(let afterDelta, let changedCount) = try await server.engine().pullDelta(onto: state) else {
    fatalError("delta miała się zastosować")
}
check(state.revision == "e.100" && state.orderedItems.count == 5100, "delta nie rusza stanu wejściowego (praca na kopii)")
check(afterDelta.revision == "e.104", "rewizja po delcie")
check(afterDelta.items["r00017"] == "Danie 17 — nowy tytuł", "upsert nadpisuje")
check(afterDelta.items["r99999"] == "Nowe danie" && afterDelta.ids.last == "r99999", "nowy przepis na końcu")
check(afterDelta.items["r00003"] == nil && !afterDelta.ids.contains("r00003"), "tombstone usuwa")
check(afterDelta.orderedItems.count == 5100, "tombstone nieznanego id niczego nie psuje")
check(changedCount == 4, "liczba zmian w przebiegu")

// 3. Ta sama delta drugi raz (powtórzona dostawa) = ten sam stan.
var duplicate = CatalogSyncBuffer<String>()
duplicate.addUpserts([(id: "r00017", item: "Danie 17 — nowy tytuł"), (id: "r99999", item: "Nowe danie")])
duplicate.addUpserts([(id: "r99999", item: "Nowe danie")])
duplicate.addTombstones(["r00003", "nieznany"])
var twice = afterDelta
twice.applyDelta(duplicate, revision: "e.104")
twice.applyDelta(duplicate, revision: "e.104")
check(twice.ids == afterDelta.ids && twice.items == afterDelta.items, "powtórzona dostawa (i duplikat na dwóch stronach) = ten sam stan")

// 4. Delta stronami: untilRevision z pierwszej strony, kursor dalej.
let paged = FakeServer(count: 50, revision: "e.1")
var small = try await paged.engine(limit: 10).pullSnapshot()
paged.changed = (0..<25).map { String(format: "r%05d", $0) }
paged.revision = "e.9"
guard case .applied(let pagedDelta, _) = try await paged.engine(limit: 10).pullDelta(onto: small) else {
    fatalError("delta stronami")
}
check(paged.changesCalls.count == 3, "delta 25 zmian w 3 stronach po 10")
check(paged.changesCalls[0].until == nil, "pierwsza strona delty bez untilRevision")
check(paged.changesCalls.dropFirst().allSatisfy { $0.until == "e.9" }, "kolejne strony z untilRevision = rewizja z pierwszej")
check(pagedDelta.revision == "e.9", "rewizja po delcie stronami")

// 5. Zmiana w trakcie przebiegu (serwer przesunął głowę) — przebieg trzyma się
//    znacznika z pierwszej strony, a zmiana przyjdzie następną deltą.
paged.changesCalls = []
paged.snapshotCalls = []
paged.revision = "e.12"
paged.changed = ["r00001"]
let pinnedCheck = try await paged.engine(limit: 10).pullDelta(onto: pagedDelta)
if case .applied(let s, _) = pinnedCheck { small = s }
check(small.revision == "e.12", "następna delta od zapisanej rewizji")

// 6. Przerwanie w połowie (sieć, zabita aplikacja): stan bez zmian, błąd do wołającego.
let broken = FakeServer(count: 30, revision: "e.1")
let base = try await broken.engine(limit: 10).pullSnapshot()
broken.changed = (0..<30).map { String(format: "r%05d", $0) }
broken.revision = "e.2"
broken.failOnCall = broken.snapshotCalls.count + 2
var interrupted = false
do {
    _ = try await broken.engine(limit: 10).pullDelta(onto: base)
} catch {
    interrupted = true
}
check(interrupted && base.revision == "e.1", "przerwana delta: błąd, stan i rewizja bez zmian")
broken.failOnCall = broken.snapshotCalls.count + broken.changesCalls.count + 2
var snapshotInterrupted = false
do {
    _ = try await broken.engine(limit: 10).pullSnapshot()
} catch {
    snapshotInterrupted = true
}
check(snapshotInterrupted, "przerwany snapshot: błąd, nic do podmiany")

// 7. RESET_REQUIRED w delcie = sygnał snapshotu; w snapshocie = jedna próba od nowa.
let reset = FakeServer(count: 20, revision: "e.1")
let resetBase = try await reset.engine(limit: 10).pullSnapshot()
reset.resetOnCall = [reset.snapshotCalls.count + 1]
if case .resetRequired = try await reset.engine(limit: 10).pullDelta(onto: resetBase) {
    check(true, "RESET_REQUIRED w delcie → snapshot")
} else {
    check(false, "RESET_REQUIRED w delcie → snapshot")
}
reset.snapshotCalls = []
reset.changesCalls = []
reset.resetOnCall = [2]
let afterReset = try await reset.engine(limit: 10).pullSnapshot()
check(afterReset.orderedItems.count == 20 && reset.snapshotCalls[2].revision == nil, "RESET_REQUIRED w połowie snapshotu → snapshot od zera, bez rewizji")
reset.snapshotCalls = []
reset.resetOnCall = [1, 2]
await expectError(CatalogSyncError.snapshotKeepsResetting, "snapshot dwa razy RESET → błąd, bez pętli") {
    _ = try await reset.engine(limit: 10).pullSnapshot()
}
var forgotten = resetBase
forgotten.forgetRevision()
check(forgotten.revision == nil && forgotten.orderedItems.count == 20, "forgetRevision: katalog zostaje do końca snapshotu")

// 8. Strony z różnymi rewizjami i kursor w miejscu — przebieg odrzucony.
let odd = FakeServer(count: 30, revision: "e.1")
odd.forcedRevisionOnCall = [2: "e.2"]
await expectError(CatalogSyncError.inconsistentPages, "snapshot: inna rewizja na 2. stronie → odrzucony") {
    _ = try await odd.engine(limit: 10).pullSnapshot()
}
let stuck = FakeServer(count: 30, revision: "e.1")
stuck.stuckCursor = true
await expectError(CatalogSyncError.cursorDidNotAdvance, "kursor w miejscu → przerwane, bez pętli") {
    _ = try await stuck.engine(limit: 10).pullSnapshot()
}

// 9. Anulowanie (np. wylogowanie w trakcie) — CancellationError, stan bez zmian.
let slow = FakeServer(count: 30, revision: "e.1")
let task = Task { () -> Bool in
    do {
        _ = try await CatalogSyncEngine<String>(
            pageLimit: 10,
            fetchSnapshotPage: { r, c, l in
                try await Task.sleep(nanoseconds: 50_000_000)
                return try slow.snapshotPage(r, c, l)
            },
            fetchChangesPage: { s, u, c, l in try slow.changesPage(s, u, c, l) }
        ).pullSnapshot()
        return false
    } catch is CancellationError {
        return true
    } catch {
        return false
    }
}
task.cancel()
check(await task.value, "anulowany przebieg kończy się CancellationError")

// 10. Plik cache: wersja w środku, uszkodzenie, niespójność, pusty plik.
let good = CatalogCacheEnvelope(state: afterDelta, savedAt: Date())
let goodData = try JSONEncoder().encode(good)
if case .valid(let loaded) = CatalogCacheEnvelope<String>.load(from: goodData) {
    check(loaded.ids == afterDelta.ids && loaded.revision == "e.104", "plik: zapis → odczyt = ten sam stan i rewizja")
} else {
    check(false, "plik: zapis → odczyt = ten sam stan i rewizja")
}
var oldFormat = try JSONSerialization.jsonObject(with: goodData) as! [String: Any]
oldFormat["version"] = 0
if case .unsupportedVersion(let v) = CatalogCacheEnvelope<String>.load(from: try JSONSerialization.data(withJSONObject: oldFormat)) {
    check(v == 0, "plik: inny numer formatu → snapshot")
} else {
    check(false, "plik: inny numer formatu → snapshot")
}
let v12 = #"{"recipes":[],"savedAt":0}"#.data(using: .utf8)!
if case .unsupportedVersion(nil) = CatalogCacheEnvelope<String>.load(from: v12) {
    check(true, "plik: stary format bez wersji (v12) → rozpoznany, nie zgadywany po nazwie")
} else {
    check(false, "plik: stary format bez wersji (v12) → rozpoznany, nie zgadywany po nazwie")
}
if case .corrupted = CatalogCacheEnvelope<String>.load(from: Data("{\"version\":1,\"ids\":[".utf8)) {
    check(true, "plik: ucięty JSON → uszkodzony")
} else {
    check(false, "plik: ucięty JSON → uszkodzony")
}
let inconsistent = #"{"version":1,"revision":"e.1","ids":["a","b"],"items":{"a":"A"},"savedAt":0}"#.data(using: .utf8)!
if case .corrupted = CatalogCacheEnvelope<String>.load(from: inconsistent) {
    check(true, "plik: id bez przepisu → uszkodzony")
} else {
    check(false, "plik: id bez przepisu → uszkodzony")
}
let badRevision = #"{"version":1,"revision":" ","ids":["a"],"items":{"a":"A"},"savedAt":0}"#.data(using: .utf8)!
if case .corrupted = CatalogCacheEnvelope<String>.load(from: badRevision) {
    check(true, "plik: pusta rewizja → uszkodzony")
} else {
    check(false, "plik: pusta rewizja → uszkodzony")
}
if case .missing = CatalogCacheEnvelope<String>.load(from: nil) {
    check(true, "plik: brak pliku → snapshot")
} else {
    check(false, "plik: brak pliku → snapshot")
}
let staleNoRevision = CatalogCacheEnvelope(state: forgotten, savedAt: Date())
if case .valid(let s) = CatalogCacheEnvelope<String>.load(from: try JSONEncoder().encode(staleNoRevision)) {
    check(s.revision == nil && s.orderedItems.count == 20, "plik po RESET_REQUIRED: katalog do pokazania, bez rewizji (następnie snapshot)")
} else {
    check(false, "plik po RESET_REQUIRED: katalog do pokazania, bez rewizji (następnie snapshot)")
}

// 11. Stan domu tylko dla tego samego konta i domu.
let household = HouseholdRecipeCacheEnvelope(ownerKey: "u1_h1", recipes: ["Zupa domowa"], favoriteRecipeIds: ["x"], savedAt: Date())
let householdData = try JSONEncoder().encode(household)
check(HouseholdRecipeCacheEnvelope<String>.load(from: householdData, ownerKey: "u1_h1")?.recipes == ["Zupa domowa"], "stan domu: ten sam właściciel → odczyt")
check(HouseholdRecipeCacheEnvelope<String>.load(from: householdData, ownerKey: "u2_h1") == nil, "stan domu: inne konto → ignorowany")
check(HouseholdRecipeCacheEnvelope<String>.load(from: householdData, ownerKey: "u1_h2") == nil, "stan domu: inny dom → ignorowany")

// MARK: - 12. Adapter DTO → domena (review patch 1)
//
// Prawdziwa ścieżka: JSON strony → `BackendCatalog*PageDTO` → `CatalogSyncMapping`
// z `BackendRecipeDTO.toAppRecipe()` → silnik. Niemapowalny przepis, brakujące
// pole, zły tryb albo obca `fromRevision` odrzucają CAŁY przebieg: katalog
// i rewizja bez zmian, żadnych „dopowiedzianych” tombstone'ów.

let epoch = "3f1d2c4b-8a9e-4f00-9b1a-2c3d4e5f6a7b"

func recipeUUID(_ n: Int) -> String {
    String(format: "00000000-0000-4000-8000-%012d", n)
}

func recipeDict(_ id: String, _ title: String, mealType: String = "DINNER") -> [String: Any] {
    [
        "id": id, "title": title, "description": NSNull(), "mealType": mealType,
        "suitableMealTypes": [mealType], "difficulty": "EASY", "prepTimeMinutes": 20,
        "servings": 2, "imageUrl": "https://img.scoffie.app/recipes/x.webp",
        "nutritionKcal": 500, "nutritionProtein": 20, "nutritionFat": 10,
        "nutritionCarbs": 60, "nutritionFiber": 5, "nutritionSalt": 1,
        "isActive": true, "ingredients": [Any](), "sourceProvider": NSNull(),
        "sourceRecipeId": NSNull(), "allergens": [String](), "dietTags": [String]()
    ]
}

/// Serwer, który oddaje JSON, jak `CatalogSyncService`. `breakPage` psuje
/// wybraną stronę (numer wywołania od 1) zanim trafi do dekodera.
final class DTOServer {
    var recipes: [String: (title: String, mealType: String)] = [:]
    var head = 10
    var changed: [String] = []
    var tombstoned: [String] = []
    var breakPage: [Int: (inout [String: Any]) -> Void] = [:]
    private(set) var calls = 0

    var token: String { "\(epoch).\(head)" }

    private func decode<T: Decodable>(_ page: [String: Any], as: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: try JSONSerialization.data(withJSONObject: page))
    }

    private func dict(_ id: String) -> [String: Any] {
        let recipe = recipes[id]!
        return recipeDict(id, recipe.title, mealType: recipe.mealType)
    }

    func snapshot(_ revision: String?, _ cursor: String?, _ limit: Int) throws -> CatalogSnapshotPage<Recipe> {
        calls += 1
        let ids = recipes.keys.sorted().filter { cursor == nil || $0 > cursor! }
        let page = Array(ids.prefix(limit))
        var json: [String: Any] = [
            "mode": "SNAPSHOT",
            "revision": revision ?? token,
            "items": page.map(dict),
            "nextCursor": ids.count > limit ? page.last! as Any : NSNull()
        ]
        breakPage[calls]?(&json)
        let dto = try decode(json, as: BackendCatalogSnapshotPageDTO.self)
        return try CatalogSyncMapping.snapshotPage(dto, map: { $0.toAppRecipe() })
    }

    func changes(_ since: String, _ until: String?, _ cursor: String?, _ limit: Int) throws -> CatalogChangesPage<Recipe> {
        calls += 1
        let all = (changed + tombstoned).sorted().filter { cursor == nil || $0 > cursor! }
        let page = Array(all.prefix(limit))
        var json: [String: Any] = [
            "mode": "DELTA",
            "fromRevision": since,
            "revision": until ?? token,
            "upserts": page.filter { changed.contains($0) }.map(dict),
            "tombstones": page.filter { tombstoned.contains($0) },
            "nextCursor": all.count > limit ? page.last! as Any : NSNull()
        ]
        breakPage[calls]?(&json)
        let dto = try decode(json, as: BackendCatalogChangesPageDTO.self)
        return try CatalogSyncMapping.changesPage(dto, sinceRevision: since, map: { $0.toAppRecipe() })
    }

    func engine(limit: Int = 2) -> CatalogSyncEngine<Recipe> {
        CatalogSyncEngine(
            pageLimit: limit,
            fetchSnapshotPage: { try self.snapshot($0, $1, $2) },
            fetchChangesPage: { try self.changes($0, $1, $2, $3) }
        )
    }
}

func titles(_ state: CatalogSyncState<Recipe>) -> [String] {
    state.orderedItems.map(\.name)
}

func expectMappingError(_ expected: CatalogSyncResponseError, _ name: String, _ body: () async throws -> Void) async {
    do {
        try await body()
        check(false, name + " (brak błędu)")
    } catch let error as CatalogSyncResponseError {
        check(error == expected, name + (error == expected ? "" : " (inny: \(error))"))
    } catch {
        check(false, name + " (inny błąd: \(error))")
    }
}

let dtoServer = DTOServer()
for n in 1...5 { dtoServer.recipes[recipeUUID(n)] = ("Danie \(n)", "DINNER") }
let dtoBase = try await dtoServer.engine().pullSnapshot()
check(dtoBase.orderedItems.count == 5 && dtoBase.revision == "\(epoch).10", "adapter: snapshot 5 przepisów w 3 stronach, rewizja z serwera")

// Nieznana pora na 2. stronie snapshotu → cały przebieg odrzucony.
dtoServer.recipes[recipeUUID(3)] = ("Danie 3", "BRUNCH")
await expectMappingError(.unmappableRecipe(id: recipeUUID(3)), "snapshot: nieznany mealType na 2. stronie → przebieg odrzucony") {
    _ = try await dtoServer.engine().pullSnapshot()
}
dtoServer.recipes[recipeUUID(3)] = ("Danie 3", "DINNER")

// Id spoza UUID na 2. stronie snapshotu.
dtoServer.recipes["zzzz-not-a-uuid"] = ("Zepsute", "DINNER")
await expectMappingError(.unmappableRecipe(id: "zzzz-not-a-uuid"), "snapshot: id spoza UUID na późniejszej stronie → przebieg odrzucony") {
    _ = try await dtoServer.engine().pullSnapshot()
}
dtoServer.recipes["zzzz-not-a-uuid"] = nil

// Delta: niemapowalny upsert na 2. stronie — NIE tombstone, stan i rewizja bez zmian.
dtoServer.head = 12
dtoServer.recipes[recipeUUID(4)] = ("Danie 4 — nowe", "BRUNCH")
dtoServer.changed = [recipeUUID(1), recipeUUID(2), recipeUUID(4)]
let beforeDelta = dtoBase
await expectMappingError(.unmappableRecipe(id: recipeUUID(4)), "delta: niemapowalny upsert na 2. stronie → przebieg odrzucony (nie tombstone)") {
    _ = try await dtoServer.engine().pullDelta(onto: dtoBase)
}
check(dtoBase.revision == beforeDelta.revision && titles(dtoBase) == titles(beforeDelta), "po błędzie: katalog i rewizja bez zmian (przepis 4 nadal jest)")

// Ponowienie po poprawce serwera dostarcza wcześniej odrzucony przepis.
dtoServer.recipes[recipeUUID(4)] = ("Danie 4 — nowe", "DINNER")
if case .applied(let retried, _) = try await dtoServer.engine().pullDelta(onto: dtoBase) {
    check(retried.revision == "\(epoch).12" && retried.items[recipeUUID(4)]?.name == "Danie 4 — nowe",
          "ponowienie od tej samej rewizji dostarcza odrzucony wcześniej przepis")
} else {
    check(false, "ponowienie od tej samej rewizji dostarcza odrzucony wcześniej przepis")
}

// Tombstone wyłącznie jawny.
dtoServer.changed = []
dtoServer.tombstoned = [recipeUUID(5)]
if case .applied(let afterTomb, _) = try await dtoServer.engine().pullDelta(onto: dtoBase) {
    check(afterTomb.items[recipeUUID(5)] == nil && afterTomb.orderedItems.count == 4, "jawny tombstone serwera usuwa przepis")
} else {
    check(false, "jawny tombstone serwera usuwa przepis")
}
dtoServer.tombstoned = []
dtoServer.changed = [recipeUUID(1)]

// Brak wymaganych pól — nie „pusta strona”.
for field in ["upserts", "tombstones", "nextCursor", "fromRevision"] {
    dtoServer.breakPage = [dtoServer.calls + 1: { _ = $0.removeValue(forKey: field) }]
    await expectMappingError(.missingField(field), "delta: brak `\(field)` → przebieg odrzucony") {
        _ = try await dtoServer.engine().pullDelta(onto: dtoBase)
    }
}
for field in ["items", "nextCursor"] {
    dtoServer.breakPage = [dtoServer.calls + 2: { _ = $0.removeValue(forKey: field) }]
    await expectMappingError(.missingField(field), "snapshot: brak `\(field)` na 2. stronie → przebieg odrzucony") {
        _ = try await dtoServer.engine().pullSnapshot()
    }
}

// Zły tryb i obca fromRevision.
dtoServer.breakPage = [dtoServer.calls + 1: { $0["mode"] = "DELTA" }]
await expectMappingError(.unexpectedMode("DELTA"), "snapshot: tryb DELTA → przebieg odrzucony") {
    _ = try await dtoServer.engine().pullSnapshot()
}
dtoServer.breakPage = [dtoServer.calls + 1: { $0["mode"] = "SNAPSHOT" }]
await expectMappingError(.unexpectedMode("SNAPSHOT"), "delta: tryb SNAPSHOT → przebieg odrzucony") {
    _ = try await dtoServer.engine().pullDelta(onto: dtoBase)
}
dtoServer.breakPage = [dtoServer.calls + 1: { $0["fromRevision"] = "\(epoch).9" }]
await expectMappingError(
    .fromRevisionMismatch(requested: "\(epoch).10", received: "\(epoch).9"),
    "delta: fromRevision ≠ sinceRevision → przebieg odrzucony"
) {
    _ = try await dtoServer.engine().pullDelta(onto: dtoBase)
}
dtoServer.breakPage = [:]
check(dtoBase.revision == "\(epoch).10" && dtoBase.orderedItems.count == 5, "po wszystkich odrzuconych przebiegach stan wejściowy nietknięty")

print(failures == 0 ? "\nWSZYSTKO OK" : "\nBŁĘDÓW: \(failures)")
exit(failures == 0 ? 0 : 1)
