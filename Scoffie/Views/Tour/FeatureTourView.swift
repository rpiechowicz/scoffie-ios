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
/// z kierunkiem ruchu, poprzednia wyjeżdża w przeciwną. Stopka (pasek kroków
/// i przyciski) stoi pod treścią, poza animowanym obszarem, i jest JEDNĄ
/// instancją na wszystkie fazy: wcześniej jechała razem z treścią, a potem
/// — już osobno — miała trzy odmiany o różnej wysokości, więc przycisk
/// główny podskakiwał przy wejściu w kroki i przy wyjściu z nich.
///
/// Od 23.09.2026 to wspólna stopka przepływów (`SCStepFooter`: płyta
/// `SCSheetFooter` z cieniem krawędzi, pasek `SCStepProgress`, krążek
/// „Wstecz”) na tle `SCPageBackground` — ta sama, co w kreatorze
/// i we wprowadzeniu asystenta, więc przejście przewodnik → kreator nie
/// zmienia ani tła, ani miejsca przycisku.
struct FeatureTourView: View {
    /// Wywoływane, gdy przewodnik ma zejść z drogi — po ostatnim kroku
    /// albo po „Pomiń".
    let onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var phase: Int = 0
    @State private var direction: Int = 1

    private let steps = TourStep.all

    private var lastPhase: Int { steps.count + 1 }

    private var isDone: Bool { phase >= lastPhase }

    private var footerSlot: SCStepFooter.Slot {
        if phase <= 0 {
            return .link("Pomiń i przejdź do konfiguracji")
        }
        if isDone {
            return .empty
        }
        return .progress(step: phase, total: steps.count)
    }

    private var primaryTitle: String {
        if phase <= 0 { return "Poznaj aplikację" }
        if isDone { return "Opowiedz nam o sobie" }
        return phase == steps.count ? "Poznajmy się" : "Dalej"
    }

    var body: some View {
        ZStack {
            SCPageBackground(scheme: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    content(for: phase)
                        .id(phase)
                        .transition(asymmetricSlide())
                }
                .frame(maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.34), value: phase)

                // Ostatnie dziecko `VStack`: cień stopki leży na treści,
                // a strony mają pod spodem zapas `TourLayout.bottom`.
                SCStepFooter(
                    slot: footerSlot,
                    onSlotTap: { onFinish() },
                    showsBack: phase > 0,
                    onBack: { goBack() },
                    backPlacement: .besidePrimary,
                    primaryTitle: primaryTitle,
                    onPrimary: {
                        if isDone {
                            onFinish()
                        } else {
                            advance()
                        }
                    }
                )
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: phase)
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

    private func advance() {
        guard phase < lastPhase else { return }
        move(to: phase + 1)
    }

    private func goBack() {
        guard phase > 0 else { return }
        move(to: phase - 1)
    }

    /// Kierunek trafia do drzewa widoków PRZED zmianą fazy, w osobnym
    /// obiegu pętli zdarzeń. Przejście wyjścia SwiftUI bierze z ostatniego
    /// renderu widoku, który znika — gdyby oba pola zmieniły się w jednej
    /// transakcji, strona schodząca wyjeżdżałaby jeszcze w POPRZEDNIM
    /// kierunku i przy pierwszym „Wstecz" po serii „Dalej" obie strony
    /// zjeżdżały się na tej samej krawędzi.
    private func move(to target: Int) {
        direction = target > phase ? 1 : -1
        DispatchQueue.main.async {
            phase = target
        }
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
