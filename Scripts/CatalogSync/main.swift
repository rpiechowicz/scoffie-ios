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
let inconsistent = #"{"version":\#(CatalogCacheEnvelope<String>.currentVersion),"revision":"e.1","ids":["a","b"],"items":{"a":"A"},"savedAt":0}"#.data(using: .utf8)!
if case .corrupted = CatalogCacheEnvelope<String>.load(from: inconsistent) {
    check(true, "plik: id bez przepisu → uszkodzony")
} else {
    check(false, "plik: id bez przepisu → uszkodzony")
}
let badRevision = #"{"version":\#(CatalogCacheEnvelope<String>.currentVersion),"revision":" ","ids":["a"],"items":{"a":"A"},"savedAt":0}"#.data(using: .utf8)!
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

// MARK: - 13. Cykl życia sesji: wylogowanie i zmiana konta (review patch 2)
//
// Deterministycznie, bez sleepów: odpowiedź kończy się dopiero wtedy, gdy
// sprawdzian wywoła `resume`, a kolejkę zapisu da się wstrzymać i opróżnić
// (`flush`). Sprawdzany jest stan w pamięci ORAZ faktyczna zawartość plików.

/// Odpowiedź, której koniec kontroluje sprawdzian. Metody rdzenia biegną
/// poza głównym aktorem, więc stan pod zamkiem.
final class Controlled<T> {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var onStart: CheckedContinuation<Void, Never>?
    private var didStart = false

    func wait() async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            didStart = true
            let waiting = onStart
            onStart = nil
            lock.unlock()
            waiting?.resume()
        }
    }

    /// Czeka, aż zapytanie naprawdę wystartuje (continuation zapisana).
    func started() async {
        await withCheckedContinuation { (waiting: CheckedContinuation<Void, Never>) in
            lock.lock()
            if didStart {
                lock.unlock()
                waiting.resume()
                return
            }
            onStart = waiting
            lock.unlock()
        }
    }

    func resume(_ value: T) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

typealias StringCore = CatalogSyncCore<String>

func makeFiles() -> CatalogCacheFiles {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-sync-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return CatalogCacheFiles(directory: dir)
}

func householdOnDisk(_ files: CatalogCacheFiles) -> HouseholdRecipeCacheEnvelope<String>? {
    guard let data = try? Data(contentsOf: files.householdURL) else { return nil }
    return try? JSONDecoder().decode(HouseholdRecipeCacheEnvelope<String>.self, from: data)
}

func catalogRevisionOnDisk(_ files: CatalogCacheFiles) -> String?? {
    guard let data = try? Data(contentsOf: files.catalogURL),
          let envelope = try? JSONDecoder().decode(CatalogCacheEnvelope<String>.self, from: data) else { return nil }
    return .some(envelope.revision)
}

func isCancelled(_ result: Result<Void, Error>) -> Bool {
    if case .failure(let error) = result { return error is CancellationError }
    return false
}

/// Silnik, którego strona delty czeka na `Controlled`.
func controlledDeltaEngine(_ pending: Controlled<CatalogChangesPage<String>>) -> CatalogSyncEngine<String> {
    CatalogSyncEngine(
        pageLimit: 500,
        fetchSnapshotPage: { _, _, _ in throw Boom() },
        fetchChangesPage: { _, _, _, _ in try await pending.wait() }
    )
}

let deltaPageA = CatalogChangesPage<String>(
    resetRequired: false, revision: "e.9",
    upserts: [(id: "r00000", item: "Przepis z żądania A")], tombstones: [], nextCursor: nil
)

// 13a. Żądanie A → wylogowanie → odpowiedź A.
do {
    let files = makeFiles()
    let gate = CatalogCacheGate(queue: DispatchQueue(label: "check-13a"))
    let coreA = StringCore(ownerKey: "u1_h1", files: files, gate: gate)
    _ = try await coreA.syncCatalog(using: FakeServer(count: 3, revision: "e.1").engine())
    try await coreA.refreshHousehold { StringCore.Household(items: ["Zupa A"], favoriteIds: ["r00001"]) }
    gate.flush()
    check(householdOnDisk(files)?.recipes == ["Zupa A"], "13a: przed wylogowaniem stan domu A na dysku")

    let pendingA = Controlled<StringCore.Household>()
    let requestA = Task { try await coreA.refreshHousehold { try await pendingA.wait() } }
    await pendingA.started()
    coreA.invalidate()
    StringCore.clearPrivateFiles(files, gate: gate)
    pendingA.resume(StringCore.Household(items: ["Tajny przepis A"], favoriteIds: ["r00002"]))
    let resultA = await requestA.result
    gate.flush()
    check(isCancelled(resultA), "13a: spóźniona odpowiedź A kończy się anulowaniem")
    check(coreA.household.items == ["Zupa A"], "13a: stan w pamięci A nie przyjął spóźnionej odpowiedzi")
    check(householdOnDisk(files) == nil, "13a: prywatny plik domu nie wrócił po wylogowaniu")
    check(catalogRevisionOnDisk(files) == .some("e.1"), "13a: publiczny katalog zostaje (polityka)")
}

// 13b. Żądanie A → przełączenie na B → odpowiedź B → spóźniona odpowiedź A.
do {
    let files = makeFiles()
    let gate = CatalogCacheGate(queue: DispatchQueue(label: "check-13b"))
    let serverA = FakeServer(count: 3, revision: "e.1")
    let coreA = StringCore(ownerKey: "u1_h1", files: files, gate: gate)
    _ = try await coreA.syncCatalog(using: serverA.engine())
    try await coreA.refreshHousehold { StringCore.Household(items: ["Zupa A"], favoriteIds: []) }
    gate.flush()

    let pendingDeltaA = Controlled<CatalogChangesPage<String>>()
    let pendingHouseholdA = Controlled<StringCore.Household>()
    let syncA = Task { _ = try await coreA.syncCatalog(using: controlledDeltaEngine(pendingDeltaA)) }
    await pendingDeltaA.started()
    let householdA = Task { try await coreA.refreshHousehold { try await pendingHouseholdA.wait() } }
    await pendingHouseholdA.started()

    // Przełączenie konta: stara sesja unieważniona, nowa przejmuje zapis.
    coreA.invalidate()
    StringCore.clearPrivateFiles(files, gate: gate)
    let coreB = StringCore(ownerKey: "u2_h2", files: files, gate: gate)
    gate.flush()
    coreB.loadFromDisk()
    check(coreB.catalog.revision == "e.1" && coreB.household.items.isEmpty, "13b: B widzi publiczny katalog, nie widzi domu A")
    serverA.changed = ["r00002"]
    serverA.revision = "e.5"
    _ = try await coreB.syncCatalog(using: serverA.engine())
    try await coreB.refreshHousehold { StringCore.Household(items: ["Zupa B"], favoriteIds: ["r00000"]) }

    // Spóźnione odpowiedzi A.
    pendingDeltaA.resume(deltaPageA)
    pendingHouseholdA.resume(StringCore.Household(items: ["Tajny przepis A"], favoriteIds: []))
    let syncResult = await syncA.result
    let householdResult = await householdA.result
    gate.flush()
    check(isCancelled(syncResult) && isCancelled(householdResult), "13b: spóźnione odpowiedzi A anulowane")
    check(coreA.catalog.revision == "e.1" && coreA.household.items == ["Zupa A"], "13b: stan A nie przyjął spóźnionych odpowiedzi")
    check(coreB.catalog.revision == "e.5" && coreB.household.items == ["Zupa B"], "13b: stan B nietknięty przez A")
    let onDisk = householdOnDisk(files)
    check(onDisk?.ownerKey == "u2_h2" && onDisk?.recipes == ["Zupa B"], "13b: plik domu = B (A go nie nadpisał)")
    check(catalogRevisionOnDisk(files) == .some("e.5"), "13b: plik katalogu = rewizja B, nie spóźniona A (e.9)")
}

// 13c. Zapis czekający w kolejce w chwili unieważnienia.
do {
    let files = makeFiles()
    let queue = DispatchQueue(label: "check-13c")
    let gate = CatalogCacheGate(queue: queue)
    let coreA = StringCore(ownerKey: "u1_h1", files: files, gate: gate)
    queue.suspend()
    try await coreA.refreshHousehold { StringCore.Household(items: ["Zapis w kolejce"], favoriteIds: []) }
    coreA.invalidate()
    queue.resume()
    gate.flush()
    check(householdOnDisk(files) == nil, "13c: zapis, który czekał w kolejce, nie odbył się po unieważnieniu")

    // To samo przy przejęciu przez nową sesję (bez jawnego unieważnienia A).
    let coreOld = StringCore(ownerKey: "u1_h1", files: files, gate: gate)
    queue.suspend()
    try await coreOld.refreshHousehold { StringCore.Household(items: ["Stara sesja"], favoriteIds: []) }
    let coreNew = StringCore(ownerKey: "u2_h2", files: files, gate: gate)
    try await coreNew.refreshHousehold { StringCore.Household(items: ["Nowa sesja"], favoriteIds: []) }
    queue.resume()
    gate.flush()
    check(householdOnDisk(files)?.recipes == ["Nowa sesja"], "13c: nowa sesja odbiera prawo zapisu starej, także w kolejce")
}

// 13d. Ponowne logowanie na to samo konto.
do {
    let files = makeFiles()
    let gate = CatalogCacheGate(queue: DispatchQueue(label: "check-13d"))
    let first = StringCore(ownerKey: "u1_h1", files: files, gate: gate)
    _ = try await first.syncCatalog(using: FakeServer(count: 3, revision: "e.1").engine())
    try await first.refreshHousehold { StringCore.Household(items: ["Zupa 1"], favoriteIds: []) }
    gate.flush()
    let pendingFirst = Controlled<StringCore.Household>()
    let late = Task { try await first.refreshHousehold { try await pendingFirst.wait() } }
    await pendingFirst.started()

    first.invalidate()
    StringCore.clearPrivateFiles(files, gate: gate)
    let second = StringCore(ownerKey: "u1_h1", files: files, gate: gate)
    gate.flush()
    second.loadFromDisk()
    check(second.catalog.revision == "e.1" && second.household.items.isEmpty,
          "13d: po ponownym logowaniu publiczny katalog jest, stan domu z pliku — nie (skasowany)")
    try await second.refreshHousehold { StringCore.Household(items: ["Zupa 2"], favoriteIds: []) }
    pendingFirst.resume(StringCore.Household(items: ["Spóźniona 1"], favoriteIds: []))
    let lateResult = await late.result
    gate.flush()
    check(isCancelled(lateResult), "13d: spóźniona odpowiedź pierwszej sesji anulowana")
    check(householdOnDisk(files)?.recipes == ["Zupa 2"], "13d: plik domu = druga sesja tego samego konta")
    check(second.household.items == ["Zupa 2"], "13d: stan drugiej sesji nietknięty")
}

// MARK: - 14. Taksonomia (katalog 1000, 28.09.2026)
//
// Pola kuchni, rodzaju dania i okazji przechodzą z JSON-a serwera do
// przepisu i przeżywają zapis do pliku cache (`Recipe` ma własne
// `CodingKeys` — zapomniany klucz gubiłby je po cichu przy każdym zapisie).

do {
    var json = recipeDict(recipeUUID(900), "Karp smażony")
    json["cuisine"] = "POLISH"
    json["dishType"] = "MAIN"
    json["seasons"] = ["WINTER"]
    json["occasions"] = ["CHRISTMAS_EVE"]
    json["equipment"] = [String]()
    json["features"] = ["OCCASIONAL"]
    let dto = try JSONDecoder().decode(BackendRecipeDTO.self, from: try JSONSerialization.data(withJSONObject: json))
    let recipe = dto.toAppRecipe()
    check(recipe?.taxonomy?.cuisine == "POLISH" && recipe?.taxonomy?.dishType == "MAIN"
          && recipe?.taxonomy?.occasions == ["CHRISTMAS_EVE"] && recipe?.taxonomy?.features == ["OCCASIONAL"],
          "14: taksonomia z JSON-a serwera trafia do przepisu")
    let cached = try JSONDecoder().decode(Recipe.self, from: try JSONEncoder().encode(recipe!))
    check(cached.taxonomy == recipe?.taxonomy, "14: taksonomia przeżywa zapis do pliku cache")

    let old = try JSONDecoder().decode(BackendRecipeDTO.self, from: try JSONSerialization.data(withJSONObject: recipeDict(recipeUUID(901), "Stary backend")))
    check(old.toAppRecipe()?.taxonomy == nil, "14: stary backend bez kuchni → taksonomia nil (heurystyka filtrów)")

    var odd = recipeDict(recipeUUID(902), "Obce pole")
    odd["cuisine"] = "ITALIAN"
    odd["seasons"] = "SUMMER"
    let oddDTO = try JSONDecoder().decode(BackendRecipeDTO.self, from: try JSONSerialization.data(withJSONObject: odd))
    check(oddDTO.toAppRecipe()?.taxonomy?.seasons == [], "14: obcy kształt jednego pola gubi tylko to pole, nie przepis")
}

// MARK: - 15. Udostępnianie (kontrakt 29.09.2026)
//
// `slug` katalogu i `shareUrl` przepisu domu przechodzą z JSON-a do przepisu
// i przeżywają plik cache; stary plik bez tych kluczy dalej się czyta.

do {
    var json = recipeDict(recipeUUID(950), "Bigos")
    json["slug"] = "bigos-staropolski"
    json["shareUrl"] = "https://scoffie.app/przepis/u/aaaaaaaaaaaaaaaaaaaaaa"
    let dto = try JSONDecoder().decode(BackendRecipeDTO.self, from: try JSONSerialization.data(withJSONObject: json))
    let recipe = dto.toAppRecipe()
    check(recipe?.slug == "bigos-staropolski", "15: slug z JSON-a serwera trafia do przepisu")
    check(recipe?.shareUrl?.absoluteString == "https://scoffie.app/przepis/u/aaaaaaaaaaaaaaaaaaaaaa",
          "15: shareUrl z JSON-a serwera trafia do przepisu")
    let cached = try JSONDecoder().decode(Recipe.self, from: try JSONEncoder().encode(recipe!))
    check(cached.slug == recipe?.slug && cached.shareUrl == recipe?.shareUrl, "15: slug i shareUrl przeżywają zapis do pliku cache")

    var nulls = recipeDict(recipeUUID(951), "Przepis domu")
    nulls["slug"] = NSNull()
    nulls["shareUrl"] = NSNull()
    let nullDTO = try JSONDecoder().decode(BackendRecipeDTO.self, from: try JSONSerialization.data(withJSONObject: nulls))
    check(nullDTO.toAppRecipe()?.slug == nil && nullDTO.toAppRecipe()?.shareUrl == nil, "15: null z serwera → nil")

    // Plik cache sprzed udostępniania: przepis bez kluczy `slug` / `shareUrl`.
    var legacy = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(recipe!)) as! [String: Any]
    legacy.removeValue(forKey: "slug")
    legacy.removeValue(forKey: "shareUrl")
    let legacyRecipe = try JSONDecoder().decode(Recipe.self, from: try JSONSerialization.data(withJSONObject: legacy))
    check(legacyRecipe.slug == nil && legacyRecipe.shareUrl == nil && legacyRecipe.name == "Bigos",
          "15: stary plik cache bez nowych kluczy czyta się bez nich")
}

// MARK: - 16. Gotuj (1.10.2026)
//
// `cookScenarioVersion` decyduje o przycisku „Gotuj” — przechodzi z JSON-a do
// przepisu i przeżywa plik cache; `ingredientId` składnika (tylko szczegół)
// wskazuje składniki kroków scenariusza.

do {
    var json = recipeDict(recipeUUID(980), "Kotlet de volaille")
    json["cookScenarioVersion"] = 3
    var ingredient: [String: Any] = [
        "id": "11111111-1111-4111-8111-111111111111",
        "recipeId": recipeUUID(980),
        "ingredientId": "ABCDEFAB-1111-4111-8111-111111111111",
        "name": "masło",
        "amount": 30,
        "unit": "g",
    ]
    json["ingredients"] = [ingredient]
    let dto = try JSONDecoder().decode(BackendRecipeDTO.self, from: try JSONSerialization.data(withJSONObject: json))
    let recipe = dto.toAppRecipe()
    check(recipe?.cookScenarioVersion == 3, "16: wersja scenariusza z JSON-a serwera trafia do przepisu")
    check(recipe?.ingredients.first?.ingredientId == "abcdefab-1111-4111-8111-111111111111",
          "16: ingredientId ze szczegółu, małymi literami")
    let cached = try JSONDecoder().decode(Recipe.self, from: try JSONEncoder().encode(recipe!))
    check(cached.cookScenarioVersion == 3 && cached.ingredients.first?.ingredientId == recipe?.ingredients.first?.ingredientId,
          "16: wersja i ingredientId przeżywają zapis do pliku cache")

    ingredient.removeValue(forKey: "ingredientId")
    var list = recipeDict(recipeUUID(981), "Z listy")
    list["cookScenarioVersion"] = NSNull()
    list["ingredients"] = [ingredient]
    let listDTO = try JSONDecoder().decode(BackendRecipeDTO.self, from: try JSONSerialization.data(withJSONObject: list))
    check(listDTO.toAppRecipe()?.cookScenarioVersion == nil, "16: null = przepis bez trybu Gotuj")
    check(listDTO.toAppRecipe()?.ingredients.first?.ingredientId == nil, "16: lista bez ingredientId → nil")
    check(CatalogCacheEnvelope<String>.currentVersion >= 4, "16: plik katalogu podbity — stary nie zna wersji scenariusza")
}

print(failures == 0 ? "\nWSZYSTKO OK" : "\nBŁĘDÓW: \(failures)")
exit(failures == 0 ? 0 : 1)
