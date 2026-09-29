import SwiftUI
import UIKit

// Udostępnianie przepisu linkiem (kontrakt 29.09.2026) — JEDNA droga dla
// obu wejść: przycisku w szczegółach (`RecipeShareButton`) i przytrzymania
// karty na listach (`recipeShareContextMenu`). Obie wołają `RecipeShareFlow`
// i rysują te same pozycje menu (`RecipeShareMenuItems`), więc „Wyłącz
// link” nie może być w jednym miejscu, a w drugim nie.

/// Udostępnij / wyłącz link — logika bez widoku.
enum RecipeShareFlow {
    /// `recipes:shareLink` → systemowy arkusz z adresem i podglądem →
    /// po faktycznym wysłaniu `recipes:shared`. Zdjęcie do podglądu idzie
    /// równolegle z linkiem i czeka najwyżej 1,5 s — podgląd bez zdjęcia jest
    /// lepszy niż arkusz, który nie wjeżdża.
    static func share(_ recipe: Recipe, store: RecipeCatalogStore, toasts: SCToastCenter) async {
        let imageURL = recipe.imageURL
        let preview = Task { @MainActor in await Self.previewImage(imageURL) }
        do {
            let url = try await store.shareLink(for: recipe.id)
            let image = await preview.value
            let recipeId = recipe.id
            SCShareSheet.present(url: url, title: recipe.name, image: image) {
                Task { await store.markShared(recipeId) }
            }
        } catch is CancellationError {
            return
        } catch {
            toasts.error("Nie udało się udostępnić przepisu", RecipeLinkErrorCopy.message(for: error))
        }
    }

    /// „Wyłącz link” — kto ma stary adres, zobaczy „przepis niedostępny”.
    static func revoke(_ recipe: Recipe, store: RecipeCatalogStore, toasts: SCToastCenter) async {
        do {
            try await store.revokeShareLink(for: recipe.id)
            toasts.success("Link wyłączony")
        } catch is CancellationError {
            return
        } catch {
            toasts.error("Nie udało się wyłączyć linku", RecipeLinkErrorCopy.message(for: error))
        }
    }

    /// Zdjęcie przepisu z potoku obrazów albo `nil`, gdy nie zdąży.
    ///
    /// Wyścig na kontynuacji, a nie grupa zadań: grupa czeka na KAŻDE swoje
    /// dziecko, a pobieranie obrazu nie przerywa się na anulowanie (dzieli
    /// jedno zadanie z ekranem, który czeka na ten sam plik) — limit czasu
    /// nic by nie dawał.
    private static func previewImage(_ url: URL?) async -> UIImage? {
        guard let url else { return nil }
        let race = RecipePreviewImageRace()
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            race.continuation = continuation
            Task { @MainActor in
                let image = await ImagePrefetcher.image(for: url)
                race.finish(image)
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                race.finish(nil)
            }
        }
    }
}

/// Kto pierwszy, ten oddaje wynik — drugi trafia w pustą kontynuację.
@MainActor
private final class RecipePreviewImageRace {
    var continuation: CheckedContinuation<UIImage?, Never>?

    func finish(_ image: UIImage?) {
        continuation?.resume(returning: image)
        continuation = nil
    }
}

/// Zdania błędów udostępniania i linków do przepisów.
enum RecipeLinkErrorCopy {
    /// W kontekście linku `RECIPE_NOT_FOUND` znaczy „link wyłączony albo
    /// przepis wycofany” — serwer celowo nie mówi, które (ta sama odpowiedź
    /// dla każdego przypadku), a zwykłe „Nie znaleziono przepisu” brzmi jak
    /// błąd aplikacji.
    static let notAvailable = "Ten przepis nie jest już dostępny."

    /// Doprecyzowanie pod tytułem toastu; `nil` przy braku sieci — ta ma
    /// w aplikacji jedno miejsce (pasek u góry, `UserFacingErrorMapper`).
    static func message(for error: Error) -> String? {
        let inline = UserFacingErrorMapper.inlineMessage(from: error)
        if isNotAvailable(error) { return notAvailable }
        return inline
    }

    static func isNotAvailable(_ error: Error) -> Bool {
        UserFacingErrorMapper.code(from: error) == "RECIPE_NOT_FOUND"
    }
}

// MARK: - Pozycje menu

/// „Udostępnij” i — przy przepisie domu z aktywnym linkiem — „Wyłącz link”.
struct RecipeShareMenuItems: View {
    let recipe: Recipe
    let onShare: () -> Void
    let onRevoke: () -> Void

    var body: some View {
        Button("Udostępnij", systemImage: "square.and.arrow.up", action: onShare)
        if recipe.shareUrl != nil {
            Button("Wyłącz link", systemImage: "xmark.circle", role: .destructive, action: onRevoke)
        }
    }
}

// MARK: - Przycisk w szczegółach

/// Krążek „Udostępnij” obok krzyżyka szczegółów — ten sam rysunek co
/// krzyżyk (`SCSheetIconLabel`, wariant na zdjęciu). Przepis domu
/// z aktywnym linkiem dostaje zamiast przycisku menu z „Wyłącz link”.
struct RecipeShareButton: View {
    let recipe: Recipe

    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.toasts) private var toasts
    /// Pobieranie linku (albo wyłączanie) — kręciołek w krążku zamiast glifu.
    @State private var isWorking = false

    var body: some View {
        if recipe.shareUrl != nil {
            Menu {
                RecipeShareMenuItems(recipe: recipe, onShare: share, onRevoke: revoke)
            } label: {
                SCSheetIconLabel(systemName: "square.and.arrow.up", onImage: true, isBusy: isWorking)
            }
            .disabled(isWorking)
            .accessibilityLabel("Udostępnij")
        } else {
            SCSheetIconButton(
                systemName: "square.and.arrow.up",
                accessibilityLabel: "Udostępnij",
                onImage: true,
                isBusy: isWorking,
                action: share
            )
            .disabled(isWorking)
        }
    }

    private func share() {
        guard !isWorking else { return }
        isWorking = true
        let store = recipeCatalogStore
        let toasts = toasts
        let recipe = recipe
        Task { @MainActor in
            await RecipeShareFlow.share(recipe, store: store, toasts: toasts)
            isWorking = false
        }
    }

    private func revoke() {
        guard !isWorking else { return }
        isWorking = true
        let store = recipeCatalogStore
        let toasts = toasts
        let recipe = recipe
        Task { @MainActor in
            await RecipeShareFlow.revoke(recipe, store: store, toasts: toasts)
            isWorking = false
        }
    }
}

// MARK: - Przytrzymanie karty

extension View {
    /// Przytrzymanie karty przepisu na liście → „Udostępnij” (i „Wyłącz
    /// link” przy przepisie domu z aktywnym linkiem). `isEnabled == false`
    /// zdejmuje menu CAŁE — pusty `contextMenu` i tak podnosi kartę pod
    /// palcem (jak w `ShoppingAisleSection`).
    func recipeShareContextMenu(_ recipe: Recipe, isEnabled: Bool = true) -> some View {
        modifier(RecipeShareContextMenu(recipe: recipe, isEnabled: isEnabled))
    }
}

private struct RecipeShareContextMenu: ViewModifier {
    let recipe: Recipe
    let isEnabled: Bool

    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.toasts) private var toasts

    func body(content: Content) -> some View {
        if isEnabled {
            menu(on: content)
        } else {
            content
        }
    }

    private func menu(on content: Content) -> some View {
        content.contextMenu {
            RecipeShareMenuItems(
                recipe: recipe,
                onShare: {
                    let store = recipeCatalogStore
                    let toasts = toasts
                    Task { @MainActor in
                        await RecipeShareFlow.share(recipe, store: store, toasts: toasts)
                    }
                },
                onRevoke: {
                    let store = recipeCatalogStore
                    let toasts = toasts
                    Task { @MainActor in
                        await RecipeShareFlow.revoke(recipe, store: store, toasts: toasts)
                    }
                }
            )
        }
    }
}
