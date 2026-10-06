import SwiftUI

struct DashboardView: View {
    /// Pulpit widać — loader startu zszedł (`ScoffieApp.showsStartupLoader`).
    /// Przepis z linku czeka na tę chwilę: arkusz pokazany wcześniej wjechałby
    /// NAD loader, który stoi nad budującym się pod nim pulpitem.
    var isRevealed: Bool = true

    @Environment(\.sessionStore) private var sessionStore
    /// Przepis z linku na ekranie. Arkusz wisi TUTAJ, a nie na którejś
    /// zakładce: link przychodzi z zewnątrz, niezależnie od tego, gdzie
    /// użytkownik stoi, a pulpit to najniższe miejsce, w którym są wszystkie
    /// store w środowisku (plan, zakupy, katalog — „Dodaj do planu” z arkusza
    /// potrzebuje ich jak z listy).
    @State private var recipeLink: RecipeLinkRequest?

    var body: some View {
        ZStack {
            NavigationMenu()
                // Rozmiary z makiet liczą się przy budowaniu widoku
                // (`Font.sc`) — zmiana rozmiaru tekstu w trakcie działania
                // przebudowuje pulpit, żeby weszła od razu.
                .scRefreshesOnDynamicType()
        }
        .sheet(item: $recipeLink) { request in
            RecipeLinkSheet(request: request) {
                recipeLink = nil
            }
            .recipeDetailSheet()
        }
        .task(id: recipeLinkTaskKey) {
            await openPendingRecipeLink()
        }
    }

    /// Zmienia się z nowym linkiem i z odsłonięciem pulpitu — każda z tych
    /// chwil może być tą, w której przepis wreszcie da się otworzyć.
    private var recipeLinkTaskKey: String {
        "\(isRevealed)|\(sessionStore.pendingRecipeLink?.key ?? "")"
    }

    private func openPendingRecipeLink() async {
        guard isRevealed, sessionStore.pendingRecipeLink != nil else { return }
        // Link nad otwartym arkuszem (inny przepis, Ustawienia, lista
        // zakupów): najpierw zjeżdża to, co stoi, potem wjeżdża przepis.
        // Własny arkusz zamykamy stanem — SwiftUI musi wiedzieć, że go nie ma,
        // zanim dostanie następny.
        if recipeLink != nil {
            recipeLink = nil
            try? await Task.sleep(for: .milliseconds(450))
        }
        await sessionStore.sessionCurtain.dismissPresentedScreensAnimated()
        guard let target = sessionStore.takePendingRecipeLink() else { return }
        recipeLink = RecipeLinkRequest(target: target)
    }
}

/// Jedno otwarcie przepisu z linku. Własna tożsamość (a nie sam cel), żeby
/// ten sam link otwarty drugi raz był nowym arkuszem, a nie „tym samym”.
struct RecipeLinkRequest: Identifiable {
    let id = UUID()
    let target: RecipeLinkTarget
}

#Preview {
    DashboardView()
}
