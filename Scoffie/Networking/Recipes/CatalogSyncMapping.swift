import Foundation

/// Odpowiedź `catalog:snapshot` / `catalog:changes`, której nie wolno
/// zastosować. Każdy z tych błędów odrzuca CAŁY przebieg — katalog i rewizja
/// zostają takie, jakie były (`CatalogSyncEngine` składa stan na kopii).
enum CatalogSyncResponseError: Error, Equatable {
    /// Tryb spoza tego zdarzenia (np. DELTA z `catalog:snapshot`).
    case unexpectedMode(String)
    /// Brak pola, które strona tego trybu musi mieć — nie „pusta strona”.
    case missingField(String)
    case emptyRevision
    /// Serwer odpowiedział deltą od innej rewizji niż ta, o którą pytaliśmy.
    case fromRevisionMismatch(requested: String, received: String)
    /// Przepis, którego klient nie umie odczytać (nieznana pora, id spoza
    /// UUID). Nie pomijamy go i nie zamieniamy w tombstone: przesunięta
    /// rewizja zgubiłaby go na zawsze, choć serwer go nie usunął.
    case unmappableRecipe(id: String)
}

/// Strona z serwera → strona dla `CatalogSyncEngine`. Jedyne miejsce, w którym
/// DTO zamienia się w elementy katalogu; bez heurystyk — element, którego nie
/// da się zmapować, odrzuca stronę, a tombstone'y są wyłącznie jawnymi
/// tombstone'ami serwera.
enum CatalogSyncMapping {
    /// Klucz przepisu w stanie katalogu: id z serwera małymi literami — tak
    /// samo dla upsertów, tombstone'ów i starej ścieżki `recipes:findAll`.
    static func key(_ id: String) -> String { id.lowercased() }

    static func snapshotPage<Item>(
        _ dto: BackendCatalogSnapshotPageDTO,
        map: (BackendRecipeDTO) -> Item?
    ) throws -> CatalogSnapshotPage<Item> {
        switch dto.mode {
        case .resetRequired:
            return CatalogSnapshotPage(resetRequired: true, revision: dto.revision, items: [], nextCursor: nil)
        case .delta:
            throw CatalogSyncResponseError.unexpectedMode(dto.mode.rawValue)
        case .snapshot:
            break
        }
        try requireRevision(dto.revision)
        guard let items = dto.items else { throw CatalogSyncResponseError.missingField("items") }
        guard dto.hasNextCursor else { throw CatalogSyncResponseError.missingField("nextCursor") }
        return CatalogSnapshotPage(
            resetRequired: false,
            revision: dto.revision,
            items: try mapAll(items, map: map),
            nextCursor: dto.nextCursor
        )
    }

    static func changesPage<Item>(
        _ dto: BackendCatalogChangesPageDTO,
        sinceRevision: String,
        map: (BackendRecipeDTO) -> Item?
    ) throws -> CatalogChangesPage<Item> {
        switch dto.mode {
        case .resetRequired:
            return CatalogChangesPage(resetRequired: true, revision: dto.revision, upserts: [], tombstones: [], nextCursor: nil)
        case .snapshot:
            throw CatalogSyncResponseError.unexpectedMode(dto.mode.rawValue)
        case .delta:
            break
        }
        try requireRevision(dto.revision)
        guard let fromRevision = dto.fromRevision else { throw CatalogSyncResponseError.missingField("fromRevision") }
        // Token jest nieprzezroczysty i pochodzi z serwera, więc serwer oddaje
        // go w tej samej postaci — inna wartość to delta od czegoś innego.
        guard fromRevision == sinceRevision else {
            throw CatalogSyncResponseError.fromRevisionMismatch(requested: sinceRevision, received: fromRevision)
        }
        guard let upserts = dto.upserts else { throw CatalogSyncResponseError.missingField("upserts") }
        guard let tombstones = dto.tombstones else { throw CatalogSyncResponseError.missingField("tombstones") }
        guard dto.hasNextCursor else { throw CatalogSyncResponseError.missingField("nextCursor") }
        return CatalogChangesPage(
            resetRequired: false,
            revision: dto.revision,
            upserts: try mapAll(upserts, map: map),
            tombstones: tombstones.map(key),
            nextCursor: dto.nextCursor
        )
    }

    private static func requireRevision(_ revision: String) throws {
        guard !revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CatalogSyncResponseError.emptyRevision
        }
    }

    private static func mapAll<Item>(
        _ dtos: [BackendRecipeDTO],
        map: (BackendRecipeDTO) -> Item?
    ) throws -> [(id: String, item: Item)] {
        var result: [(id: String, item: Item)] = []
        result.reserveCapacity(dtos.count)
        for dto in dtos {
            guard let item = map(dto) else { throw CatalogSyncResponseError.unmappableRecipe(id: dto.id) }
            result.append((id: key(dto.id), item: item))
        }
        return result
    }
}
