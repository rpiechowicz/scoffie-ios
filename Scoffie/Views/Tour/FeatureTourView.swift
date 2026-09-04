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
/// z kierunkiem ruchu, poprzednia wyjeżdża w przeciwną. Stopka (stepper
/// i przyciski) stoi pod treścią, poza animowanym obszarem: wcześniej
/// jechała razem z treścią i cały ekran „przewijał się" na bok, zamiast
/// zachować się jak kreator, w którym przesuwa się tylko formularz.
struct FeatureTourView: View {
    /// Wywoływane, gdy przewodnik ma zejść z drogi — po ostatnim kroku
    /// albo po „Pomiń".
    let onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var phase: Int = 0
    @State private var direction: Int = 1

    private let steps = TourStep.all

    private var lastPhase: Int { steps.count + 1 }

    /// Stopka ma trzy odmiany, nie siedem: wszystkie kroki z funkcjami
    /// dzielą jedną instancję. Dzięki temu między krokami stopka nie jest
    /// tworzona od nowa — pigułka steppera przesuwa się sprężyście,
    /// a przyciski nie mrugają. Odmiany zmieniają się tylko na wejściu
    /// w kroki i na wyjściu z nich, i wtedy krzyżowo się przenikają.
    private enum FooterKind: Hashable {
        case intro
        case steps
        case done
    }

    private var footerKind: FooterKind {
        if phase <= 0 {
            return .intro
        }
        if phase >= lastPhase {
            return .done
        }
        return .steps
    }

    private var stepIndex: Int {
        min(max(phase - 1, 0), steps.count - 1)
    }

    var body: some View {
        ZStack {
            TourBackground(scheme: colorScheme)

            VStack(spacing: 0) {
                ZStack {
                    content(for: phase)
                        .id(phase)
                        .transition(asymmetricSlide())
                }
                .animation(.easeInOut(duration: 0.34), value: phase)

                ZStack {
                    footer(for: footerKind)
                        .id(footerKind)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.34), value: footerKind)
            }
        }
    }

    @ViewBuilder
    private func content(for phase: Int) -> some View {
        if phase <= 0 {
            TourIntroView()
        } else if phase >= lastPhase {
            TourDoneView()
        } else {
            TourStepView(step: steps[phase - 1])
        }
    }

    @ViewBuilder
    private func footer(for kind: FooterKind) -> some View {
        switch kind {
        case .intro:
            TourIntroFooter(onStart: advance, onSkip: onFinish)
        case .steps:
            TourStepFooter(
                index: stepIndex,
                total: steps.count,
                onBack: goBack,
                onNext: advance
            )
        case .done:
            TourDoneFooter(onContinue: onFinish, onBack: goBack)
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
