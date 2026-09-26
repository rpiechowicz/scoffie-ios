import Foundation

/// Domain-level repository that hides the DTO layer from stores/views.
/// Translates UUID <-> String and DTOs <-> Recipe.
final class ApiRecipeRepository: RecipeRepository {
    private let client: RecipeTransportClient

    init(client: RecipeTransportClient) {
        self.client = client
    }

    func fetchRecipes(page: Int, limit: Int) async throws -> RecipePage {
        let dtos = try await client.fetchRecipes(page: page, limit: limit)
        return RecipePage(
            recipes: dtos.compactMap { $0.toAppRecipe() },
            receivedCount: dtos.count
        )
    }

    func fetchCatalogSnapshotPage(revision: String?, cursor: String?, limit: Int) async throws -> CatalogSnapshotPage {
        let dto = try await client.fetchCatalogSnapshot(revision: revision, cursor: cursor, limit: limit)
        return CatalogSnapshotPage(
            resetRequired: dto.mode == .resetRequired,
            revision: dto.revision,
            recipes: (dto.items ?? []).compactMap { item in
                item.toAppRecipe().map { (id: item.id, item: $0) }
            },
            nextCursor: dto.nextCursor
        )
    }

    func fetchCatalogChangesPage(sinceRevision: String, untilRevision: String?, cursor: String?, limit: Int) async throws -> CatalogChangesPage {
        let dto = try await client.fetchCatalogChanges(
            sinceRevision: sinceRevision,
            untilRevision: untilRevision,
            cursor: cursor,
            limit: limit
        )
        var upserts: [(id: String, item: Recipe)] = []
        var tombstones = dto.tombstones ?? []
        for item in dto.upserts ?? [] {
            if let recipe = item.toAppRecipe() {
                upserts.append((id: item.id, item: recipe))
            } else {
                tombstones.append(item.id)
            }
        }
        return CatalogChangesPage(
            resetRequired: dto.mode == .resetRequired,
            revision: dto.revision,
            upserts: upserts,
            tombstones: tombstones,
            nextCursor: dto.nextCursor
        )
    }

    func fetchHouseholdRecipeState() async throws -> HouseholdRecipeState {
        let dto = try await client.fetchHouseholdRecipeState()
        return HouseholdRecipeState(
            recipes: dto.recipes.compactMap { $0.toAppRecipe() },
            favoriteRecipeIds: Set(dto.favoriteRecipeIds.compactMap { UUID(uuidString: $0) })
        )
    }

    func fetchRecipeById(_ recipeId: UUID) async throws -> Recipe {
        let id = recipeId.uuidString
        guard !id.isEmpty else { throw RecipeDataError.invalidRecipeId }
        let dto = try await client.fetchRecipeById(recipeId: id)
        guard let mapped = dto.toAppRecipe() else {
            throw RecipeDataError.serverError(message: "Nie udało się zmapować recipes:findById.")
        }
        return mapped
    }

    func setFavorite(recipeId: UUID, isFavorite: Bool) async throws {
        let id = recipeId.uuidString
        guard !id.isEmpty else { throw RecipeDataError.invalidRecipeId }
        try await client.setFavorite(recipeId: id, isFavorite: isFavorite)
    }

    func observeFavoritesChanges(_ onChange: @escaping (_ recipeId: UUID, _ isFavorite: Bool) -> Void) {
        client.observeFavoritesChanges { recipeId, isFavorite in
            guard let uuid = UUID(uuidString: recipeId) else { return }
            onChange(uuid, isFavorite)
        }
    }

    func observeRecipeChanges(_ onChange: @escaping () -> Void) {
        client.observeRecipeChanges(onChange)
    }

    func observeRealtimeReconnect(_ onReconnect: @escaping () -> Void) {
        client.observeRealtimeReconnect(onReconnect)
    }
}
