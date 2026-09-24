import SwiftUI

/// Wszystko, co dzieje się między zalogowaniem a wejściem do aplikacji:
/// przewodnik „Poznaj aplikację” i kreator profilu — od 24.09.2026 JEDEN
/// przepływ w `WelcomeView` (jedna stopka, jeden pasek kroków), a nie dwa
/// ekrany przenikane jeden w drugi.
struct WelcomeFlowView: View {
    let initialDisplayName: String
    let isCreatingHousehold: Bool
    let errorMessage: String?
    let initialStep: Int

    @AppStorage(TourCompletion.storageKey) private var tourCompleted: Bool = false

    /// Przewodnik należy się tylko na pełnej ścieżce od zera. Kto już
    /// przeszedł onboarding i wraca tu wyłącznie po nowe gospodarstwo,
    /// aplikację zna — pięć ekranów o tym, gdzie jest zakładka Plan, byłoby
    /// dla niego karą za to, że wyszedł z domu.
    ///
    /// Czytane RAZ, przy wejściu: `WelcomeView` sam ustawia flagę, gdy
    /// przewodnik się kończy, i nie może przez to zostać zbudowany od nowa.
    @State private var showsTourAtStart: Bool?

    var body: some View {
        WelcomeView(
            initialDisplayName: initialDisplayName,
            isCreatingHousehold: isCreatingHousehold,
            errorMessage: errorMessage,
            initialStep: initialStep,
            showsTour: showsTourAtStart ?? (initialStep == 1 && !tourCompleted)
        )
        .onAppear {
            if showsTourAtStart == nil {
                showsTourAtStart = initialStep == 1 && !tourCompleted
            }
        }
    }
}
