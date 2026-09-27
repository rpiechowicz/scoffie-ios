import Foundation

/// Odpowiedź `catalog:snapshot` (backend `CatalogSyncService`).
///
/// `revision` to NIEPRZEZROCZYSTY token — klient go nie parsuje, tylko odsyła:
/// na kolejnych stronach tego samego przebiegu (`revision`) i w następnej
/// synchronizacji (`sinceRevision`). `RESET_REQUIRED` = zacznij snapshot od zera.
///
/// Pola strony są opcjonalne tylko dlatego, że RESET_REQUIRED ich nie niesie —
/// o tym, czy strona jest kompletna, rozstrzyga `CatalogSyncMapping`, a nie
/// domyślne `[]`. `hasNextCursor` odróżnia `"nextCursor": null` (ostatnia strona)
/// od braku klucza (odpowiedź niekompletna).
struct BackendCatalogSnapshotPageDTO: Decodable {
    let mode: CatalogSyncMode
    let revision: String
    let items: [BackendRecipeDTO]?
    let nextCursor: String?
    let hasNextCursor: Bool
    let snapshotRequired: Bool?
    let reason: String?

    private enum CodingKeys: String, CodingKey {
        case mode, revision, items, nextCursor, snapshotRequired, reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(CatalogSyncMode.self, forKey: .mode)
        revision = try container.decode(String.self, forKey: .revision)
        items = try container.decodeIfPresent([BackendRecipeDTO].self, forKey: .items)
        hasNextCursor = container.contains(.nextCursor)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
        snapshotRequired = try container.decodeIfPresent(Bool.self, forKey: .snapshotRequired)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }
}

/// Odpowiedź `catalog:changes`: upserty i tombstone'y od rewizji klienta.
/// Kompletność strony — patrz `BackendCatalogSnapshotPageDTO`.
struct BackendCatalogChangesPageDTO: Decodable {
    let mode: CatalogSyncMode
    let revision: String
    let fromRevision: String?
    let upserts: [BackendRecipeDTO]?
    let tombstones: [String]?
    let nextCursor: String?
    let hasNextCursor: Bool
    let snapshotRequired: Bool?
    let reason: String?

    private enum CodingKeys: String, CodingKey {
        case mode, revision, fromRevision, upserts, tombstones, nextCursor, snapshotRequired, reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(CatalogSyncMode.self, forKey: .mode)
        revision = try container.decode(String.self, forKey: .revision)
        fromRevision = try container.decodeIfPresent(String.self, forKey: .fromRevision)
        upserts = try container.decodeIfPresent([BackendRecipeDTO].self, forKey: .upserts)
        tombstones = try container.decodeIfPresent([String].self, forKey: .tombstones)
        hasNextCursor = container.contains(.nextCursor)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
        snapshotRequired = try container.decodeIfPresent(Bool.self, forKey: .snapshotRequired)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }
}

/// Odpowiedź `recipes:householdState`: przepisy gospodarstwa (nie wchodzą do
/// publicznego logu katalogu) i ulubione domu.
struct BackendHouseholdRecipeStateDTO: Decodable {
    let householdId: String
    let recipes: [BackendRecipeDTO]
    let favoriteRecipeIds: [String]
}
