import SwiftUI

/// Menu ⋯ → „Jak działa asystent” — te same trzy strony, co wprowadzenie
/// w zakładce (Powitanie → Planowanie → Ty decydujesz, `AssistantIntroPages`),
/// w arkuszu i bez zgody na końcu. Do wprowadzenia v2 (24.09.2026) były tu
/// cztery karty „Poznaj” z podglądem rozmowy i wiersz „Pomiń” — nieaktualne
/// obietnice i trzeci układ kroków obok przewodnika i kreatora.
///
/// Stopka ta sama, co w zakładce i w onboardingu aplikacji (`SCStepFooter`:
/// pasek kroków nad przyciskiem, „Wstecz” obok „Dalej”), JEDNA instancja na
/// wszystkie strony, żeby pasek się nalewał. Krzyżyk w rogu zamyka arkusz na
/// każdej stronie; ostatnia kończy się „Gotowe”.
struct AssistantHowItWorksView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var page: AssistantIntroPage = .hello
    /// Kierunek ostatniego ruchu: 1 = dalej, −1 = wstecz.
    @State private var direction = 1

    private var pages: [AssistantIntroPage] { AssistantIntroPage.allCases }
    private var isLast: Bool { page == pages.last }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    AssistantIntroPageView(page: page, topPadding: AssistantIntroLayout.sheetTop)
                        .id(page)
                        .transition(.horizontalStep(direction: direction))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.34), value: page)

                SCStepFooter(
                    slot: .progress(step: page.rawValue + 1, total: pages.count),
                    showsBack: page != .hello,
                    onBack: { move(by: -1) },
                    backPlacement: .besidePrimary,
                    primaryTitle: isLast ? "Gotowe" : "Dalej",
                    primaryIcon: isLast ? "checkmark" : "arrow.right",
                    onPrimary: {
                        if isLast {
                            dismiss()
                        } else {
                            move(by: 1)
                        }
                    }
                )
            }

            SCSheetCloseButton { dismiss() }
                .padding(.top, 16)
                .padding(.trailing, 16)
        }
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: page)
    }

    /// Kierunek trafia do drzewa PRZED zmianą strony, w osobnym obiegu pętli
    /// zdarzeń — przejście wyjścia bierze go z ostatniego renderu strony,
    /// która znika (ta sama sztuczka, co w `WelcomeView.move(to:)`).
    private func move(by delta: Int) {
        guard let target = AssistantIntroPage(rawValue: page.rawValue + delta) else { return }
        direction = delta >= 0 ? 1 : -1
        DispatchQueue.main.async {
            page = target
        }
    }
}

#Preview("Jak działa · Dark") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            AssistantHowItWorksView()
        }
        .preferredColorScheme(.dark)
}
