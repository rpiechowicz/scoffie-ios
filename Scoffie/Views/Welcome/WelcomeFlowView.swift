import SwiftUI

/// Wszystko, co dzieje się między zalogowaniem a wejściem do aplikacji:
/// najpierw przewodnik „Poznaj aplikację", potem kreator profilu.
///
/// Rozdzielone od `WelcomeView`, bo to dwie różne rozmowy. Przewodnik
/// opowiada, kreator pyta — i tylko kreator ma stan, który trzeba
/// zapisywać na serwerze.
struct WelcomeFlowView: View {
    let initialDisplayName: String
    let isCreatingHousehold: Bool
    let errorMessage: String?
    let initialStep: Int

    @AppStorage(TourCompletion.storageKey) private var tourCompleted: Bool = false

    /// Przewodnik należy się tylko na pełnej ścieżce od zera. Kto już
    /// przeszedł onboarding i wraca tu wyłącznie po nowe gospodarstwo
    /// (`initialStep == 4`), aplikację zna — pięć ekranów o tym, gdzie jest
    /// zakładka Plan, byłoby dla niego karą za to, że wyszedł z domu.
    private var showsTour: Bool {
        initialStep == 1 && !tourCompleted
    }

    var body: some View {
        ZStack {
            if showsTour {
                FeatureTourView(onFinish: finishTour)
                    .transition(.opacity)
            } else {
                WelcomeView(
                    initialDisplayName: initialDisplayName,
                    isCreatingHousehold: isCreatingHousehold,
                    errorMessage: errorMessage,
                    initialStep: initialStep
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showsTour)
    }

    private func finishTour() {
        tourCompleted = true
    }
}
