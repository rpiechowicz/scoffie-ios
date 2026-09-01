import SwiftUI

/// „Poznaj aplikację" — przewodnik pokazywany raz, między zalogowaniem
/// a kreatorem profilu.
///
/// Kolejność jest celowa: najpierw pokazujemy, po co ta aplikacja jest,
/// a dopiero potem pytamy o wzrost, wagę i alergeny. Odwrotnie — czyli
/// tak, jak było — pierwszy ekran po zalogowaniu prosił o dane od osoby,
/// która nie widziała jeszcze ani jednego ekranu produktu.
///
/// Fazy: 0 = powitanie, 1…5 = funkcje, 6 = zaproszenie do kreatora.
/// Przejścia jak w `WelcomeView` — treść wjeżdża z krawędzi zgodnej
/// z kierunkiem ruchu, poprzednia wyjeżdża w przeciwną.
struct FeatureTourView: View {
    /// Wywoływane, gdy przewodnik ma zejść z drogi — po ostatnim kroku
    /// albo po „Pomiń".
    let onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var phase: Int = 0
    @State private var direction: Int = 1

    private let steps = TourStep.all

    private var lastPhase: Int { steps.count + 1 }

    var body: some View {
        ZStack {
            TourBackground(scheme: colorScheme)

            ZStack {
                content(for: phase)
                    .id(phase)
                    .transition(asymmetricSlide())
            }
            .animation(.easeInOut(duration: 0.34), value: phase)
        }
    }

    @ViewBuilder
    private func content(for phase: Int) -> some View {
        if phase <= 0 {
            TourIntroView(onStart: advance, onSkip: onFinish)
        } else if phase >= lastPhase {
            TourDoneView(onContinue: onFinish, onBack: goBack)
        } else {
            TourStepView(
                step: steps[phase - 1],
                index: phase - 1,
                total: steps.count,
                onBack: goBack,
                onNext: advance
            )
        }
    }

    private func advance() {
        guard phase < lastPhase else { return }
        direction = 1
        phase += 1
    }

    private func goBack() {
        guard phase > 0 else { return }
        direction = -1
        phase -= 1
    }

    private func asymmetricSlide() -> AnyTransition {
        let slideIn: AnyTransition = direction >= 0
            ? .move(edge: .trailing).combined(with: .opacity)
            : .move(edge: .leading).combined(with: .opacity)
        let slideOut: AnyTransition = direction >= 0
            ? .move(edge: .leading).combined(with: .opacity)
            : .move(edge: .trailing).combined(with: .opacity)
        return .asymmetric(insertion: slideIn, removal: slideOut)
    }
}

#Preview("Dark") {
    FeatureTourView(onFinish: {})
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    FeatureTourView(onFinish: {})
        .preferredColorScheme(.light)
}

/// Klucz „przewodnik obejrzany".
///
/// Trzymany w `UserDefaults`, a nie na serwerze, bo dotyczy urządzenia, nie
/// konta — i celowo kasowany w `SessionStore.clearPersistedSession()`.
/// Bez tego kasowania wylogowanie i ponowne zalogowanie (także na cudze
/// konto) omijałoby przewodnik, bo flaga przeżywa w `UserDefaults` sesję,
/// po której została ustawiona.
enum TourCompletion {
    static let storageKey = "onboarding.tourCompleted"
}
