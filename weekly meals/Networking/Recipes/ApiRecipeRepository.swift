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

    func observeRealtimeReconnect(_ onReconnect: @escaping () -> Void) {
        client.observeRealtimeReconnect(onReconnect)
    }
}
