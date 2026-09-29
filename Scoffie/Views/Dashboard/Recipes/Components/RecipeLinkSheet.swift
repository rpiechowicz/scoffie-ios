import SwiftUI

/// Przepis otwarty linkiem (Universal Link albo `scoffie://recipe`).
///
/// Arkusz wjeżdża OD RAZU, z zarysem szczegółów (`RecipeDetailPlaceholder`)
/// — link to odpowiedź na stuknięcie w komunikatorze i ekran ma zareagować
/// w tej samej chwili, a nie po powrocie `recipes:openShared`. Potem ten sam
/// szczegół co z listy, w trybie zależnym od tego, czyj to przepis:
/// - katalog albo przepis TEGO domu → zwykły szczegół (serce, zakupy, plan);
/// - przepis innego domu → tylko odczyt, „Zapisz u siebie” i plan na kopii
///   (`RecipeDetailContext.shared`).
///
/// Błąd zamyka arkusz i zostawia toast — pusty arkusz z komunikatem byłby
/// ekranem, z którego jedyne wyjście to zamknięcie.
struct RecipeLinkSheet: View {
    let request: RecipeLinkRequest
    let onClose: () -> Void

    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.toasts) private var toasts
    @State private var opened: OpenedRecipeLink?

    var body: some View {
        ZStack {
            if let opened {
                detail(opened)
                    .transition(.opacity)
            } else {
                RecipeDetailPlaceholder(onClose: onClose)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: opened == nil)
        .task { await load() }
    }

    @ViewBuilder
    private func detail(_ opened: OpenedRecipeLink) -> some View {
        switch opened.origin {
        case .shared:
            // Cudzy przepis: bez serca (ulubione są stanem domu, a tego
            // przepisu w domu nie ma) i bez dociągania `findById` — serwer
            // i tak odpowie na nie 404.
            RecipeDetailView(
                recipe: opened.recipe,
                onClose: onClose,
                context: .shared(
                    token: opened.shareToken ?? request.target.shareToken ?? "",
                    savedRecipeId: opened.savedRecipeId
                ),
                onAddedToPlan: { _, _ in onClose() }
            )
        case .catalog, .household:
            // Jak z listy: żywy przepis z katalogu (serce nadąża za zapisem),
            // a otwarty z linku — gdyby lista go jeszcze nie miała.
            RecipeDetailView(
                recipe: recipeCatalogStore.recipes.first(where: { $0.id == opened.recipe.id }) ?? opened.recipe,
                onSetFavourite: { value in
                    Task { await recipeCatalogStore.setFavourite(recipeId: opened.recipe.id, to: value) }
                },
                onClose: onClose,
                onAddedToPlan: { _, _ in onClose() }
            )
        }
    }

    private func load() async {
        guard opened == nil else { return }
        do {
            let result = try await recipeCatalogStore.openRecipeLink(request.target)
            opened = result
        } catch {
            // Arkusz zamknięty w trakcie — nie ma komu mówić o błędzie.
            guard !Task.isCancelled, !UserFacingErrorMapper.isCancellation(error) else { return }
            onClose()
            if RecipeLinkErrorCopy.isNotAvailable(error) {
                toasts.error(RecipeLinkErrorCopy.notAvailable)
            } else {
                toasts.error("Nie udało się otworzyć przepisu", RecipeLinkErrorCopy.message(for: error))
            }
        }
    }
}
