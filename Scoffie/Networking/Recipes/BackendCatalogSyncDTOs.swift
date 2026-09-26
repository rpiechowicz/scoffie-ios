import Foundation

/// Odpowiedź `catalog:snapshot` (backend workstream Etap 4A).
///
/// `revision` to NIEPRZEZROCZYSTY token — klient go nie parsuje, tylko odsyła:
/// na kolejnych stronach tego samego przebiegu (`revision`) i w następnej
/// synchronizacji (`sinceRevision`). `RESET_REQUIRED` = zacznij snapshot od zera.
struct BackendCatalogSnapshotPageDTO: Decodable {
    let mode: CatalogSyncMode
    let revision: String
    let items: [BackendRecipeDTO]?
    let nextCursor: String?
    let snapshotRequired: Bool?
    let reason: String?
}

/// Odpowiedź `catalog:changes`: upserty i tombstone'y od rewizji klienta.
struct BackendCatalogChangesPageDTO: Decodable {
    let mode: CatalogSyncMode
    let revision: String
    let fromRevision: String?
    let upserts: [BackendRecipeDTO]?
    let tombstones: [String]?
    let nextCursor: String?
    let snapshotRequired: Bool?
    let reason: String?
}

/// Odpowiedź `recipes:householdState`: przepisy gospodarstwa (nie wchodzą do
/// publicznego logu katalogu) i ulubione domu.
struct BackendHouseholdRecipeStateDTO: Decodable {
    let householdId: String
    let recipes: [BackendRecipeDTO]
    let favoriteRecipeIds: [String]
}
