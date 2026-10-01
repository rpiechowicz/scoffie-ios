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

    /// Niemapowalny przepis albo niekompletna strona odrzuca cały przebieg
    /// (`CatalogSyncMapping`) — katalog i rewizja zostają, jakie były.
    func fetchCatalogSnapshotPage(revision: String?, cursor: String?, limit: Int) async throws -> CatalogSnapshotPage<Recipe> {
        let dto = try await client.fetchCatalogSnapshot(revision: revision, cursor: cursor, limit: limit)
        return try CatalogSyncMapping.snapshotPage(dto, map: Self.catalogRecipe)
    }

    func fetchCatalogChangesPage(sinceRevision: String, untilRevision: String?, cursor: String?, limit: Int) async throws -> CatalogChangesPage<Recipe> {
        let dto = try await client.fetchCatalogChanges(
            sinceRevision: sinceRevision,
            untilRevision: untilRevision,
            cursor: cursor,
            limit: limit
        )
        return try CatalogSyncMapping.changesPage(dto, sinceRevision: sinceRevision, map: Self.catalogRecipe)
    }

    func fetchHouseholdRecipeState() async throws -> HouseholdRecipeState {
        let dto = try await client.fetchHouseholdRecipeState()
        return HouseholdRecipeState(
            recipes: dto.recipes.compactMap { $0.toAppRecipe() },
            favoriteRecipeIds: Set(dto.favoriteRecipeIds.compactMap { UUID(uuidString: $0) })
        )
    }

    /// Klucz przepisu w stanie katalogu — patrz `CatalogSyncMapping.key`.
    static func catalogKey(_ id: String) -> String { CatalogSyncMapping.key(id) }

    /// DTO → przepis publicznego katalogu (bez serca); `nil` = niemapowalny.
    static func catalogRecipe(_ dto: BackendRecipeDTO) -> Recipe? {
        dto.toAppRecipe().map(catalogCopy)
    }

    /// Publiczny katalog nie niesie ulubionych (to stan DOMU) — kopia bez serca,
    /// żeby plik katalogu, który przeżywa wylogowanie, nie trzymał cudzych ulubionych.
    static func catalogCopy(_ recipe: Recipe) -> Recipe {
        var copy = recipe
        copy.favourite = false
        return copy
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

    // MARK: - Udostępnianie

    func createShareLink(recipeId: UUID) async throws -> RecipeShareLink {
        let dto = try await client.createShareLink(recipeId: Self.wireId(recipeId))
        guard let url = URL(string: dto.url) else {
            throw RecipeDataError.serverError(message: "Nieprawidłowy adres z recipes:shareLink.")
        }
        return RecipeShareLink(url: url, isHouseholdLink: dto.kind == "HOUSEHOLD")
    }

    func revokeShareLink(recipeId: UUID) async throws -> Bool {
        try await client.revokeShareLink(recipeId: Self.wireId(recipeId)).revoked
    }

    func markRecipeShared(recipeId: UUID) async throws {
        try await client.markRecipeShared(recipeId: Self.wireId(recipeId))
    }

    func openRecipeLink(_ target: RecipeLinkTarget) async throws -> OpenedRecipeLink {
        let dto: BackendOpenSharedRecipeDTO
        switch target {
        case .catalog(let slug):
            dto = try await client.openSharedRecipe(slug: slug, token: nil)
        case .shared(let token):
            dto = try await client.openSharedRecipe(slug: nil, token: token)
        }
        guard let recipe = dto.recipe.toAppRecipe() else {
            throw RecipeDataError.serverError(message: "Nie udało się zmapować recipes:openShared.")
        }
        let origin: OpenedRecipeLink.Origin
        switch dto.origin {
        case "CATALOG": origin = .catalog
        case "HOUSEHOLD": origin = .household
        // Nieznane pochodzenie traktujemy jak obce: tylko odczyt to jedyny
        // tryb, w którym telefon nie wyśle zapisu, którego serwer nie przyjmie.
        default: origin = .shared
        }
        return OpenedRecipeLink(
            origin: origin,
            recipe: recipe,
            savedRecipeId: dto.savedRecipeId.flatMap { UUID(uuidString: $0) },
            shareToken: dto.shareToken ?? target.shareToken
        )
    }

    func saveSharedRecipe(token: String) async throws -> Recipe {
        let dto = try await client.saveSharedRecipe(token: token)
        guard let recipe = dto.recipe.toAppRecipe() else {
            throw RecipeDataError.serverError(message: "Nie udało się zmapować recipes:saveShared.")
        }
        return recipe
    }

    func fetchCookScenario(_ recipeId: UUID) async throws -> CookScenarioEnvelope? {
        try await client.fetchCookScenario(recipeId: Self.wireId(recipeId)).scenario
    }

    /// UUID małymi literami — tak, jak trzyma je baza i jak wracają w odpowiedziach.
    private static func wireId(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }
}
