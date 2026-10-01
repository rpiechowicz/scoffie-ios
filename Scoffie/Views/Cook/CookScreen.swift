import SwiftUI

/// Jeden ekran trybu Gotuj na wszystkie etapy (runda 3 testów, 1.10.2026:
/// „to powinno być wszystko jednym stanem, bo np. X wjeżdża na nowo”).
///
/// Zdjęcie dania, krzyżyk i przewijanie są TE SAME od powitania do
/// „Smacznego!”. Zmienia się tylko to, co pod zdjęciem
/// (`CookWelcomeContent`, `CookStepScene`, `CookFinishContent`), stopka
/// (szuflady i „Zaczynamy” / „Zjedzone”) i dok, a pierścień kroków stoi
/// obok krzyżyka tylko w krokach. Wcześniej każdy etap był osobnym ekranem
/// z własnym zdjęciem i krzyżykiem — przy „Zaczynamy” i po ostatnim kroku
/// krzyżyk wjeżdżał od nowa.
///
/// Zmiana etapu: stara treść gaśnie w miejscu, nowa wchodzi własną kaskadą
/// (`cookReveal`), stopka gaśnie i zjeżdża, dok wyjeżdża od dołu — wszystko
/// nad nieruchomym zdjęciem.
struct CookScreen: View {
    let session: CookSession
    let recipe: CookRecipeFacts
    /// Zdjęcie osiada raz, przy wejściu w tryb (`CookModeView`).
    let isPhotoRevealed: Bool
    /// Skąd przyszedł krok — nowy opis wjeżdża z tej strony.
    let direction: Edge
    let onPortions: (Int) -> Void
    let onStart: () -> Void
    let onClose: () -> Void
    let onBack: () -> Void
    let onNext: () -> Void
    let onTimer: (CookTimerAction) -> Void
    let onOpen: (CookSheet) -> Void
    let onEaten: () -> Void
    let onFeedback: (CookFeedback) -> Void

    @State private var scrollPosition = ScrollPosition(edge: .top)
    /// Wejście w tryb (krzyżyk, pierścień, dok) — raz. Zmiana etapu go nie
    /// powtarza: to, co zostaje na ekranie, stoi w miejscu.
    @State private var hasAppeared = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Color.scPageBase(scheme).ignoresSafeArea()

            ScrollView {
                ZStack(alignment: .topLeading) {
                    CookHeaderPhoto(url: session.imageURL, isRevealed: isPhotoRevealed)
                    content
                }
                // Szerokość treści = szerokość ekranu (wzór szczegółów
                // posiłku): żaden element nie poszerzy obszaru przewijania.
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
            // Krok odbija zawsze — zdjęcie rozciąga się przy przeciągnięciu
            // w dół także na krótkim kroku; powitanie i koniec, gdy się
            // mieszczą, stoją.
            .scrollBounceBehavior(session.stage == .steps ? .always : .basedOnSize)
            .scrollPosition($scrollPosition)
            // Zdjęcie pod paskiem stanu; dół zostaje w bezpiecznym obszarze,
            // tak jak dok (`cookDockReserve` liczy się od jego krawędzi).
            .ignoresSafeArea(edges: .top)
            .simultaneousGesture(swipe)
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            // Nowy krok i nowy etap zaczynają się od góry (tytuł), a nie od
            // miejsca, w którym skończyło się czytanie poprzedniego.
            .onChange(of: session.stepIndex) { scrollToTop() }
            .onChange(of: session.stage) { scrollToTop() }

            topBar
        }
        // Dok stoi tam, gdzie dolne menu aplikacji — na dolnej krawędzi
        // bezpiecznego obszaru (runda 2: „ciut za wysoko”).
        .overlay(alignment: .bottom) { dock }
        .task {
            guard !hasAppeared else { return }
            await CookEntrance.breathe()
            hasAppeared = true
        }
    }

    // MARK: - Pasek

    /// Pierścień kroków i krzyżyk — ta sama wielkość i powierzchnia. Krzyżyk
    /// jest jeden na cały tryb, więc przy zmianie etapu nie mrugnie; pierścień
    /// pojawia się obok niego przy „Zaczynamy” i znika przy „Smacznego!”.
    private var topBar: some View {
        HStack(spacing: 10) {
            if session.stage == .steps {
                // Stuknięcie = arkusz Kroki: wszystkie kroki jeden pod
                // drugim, z drogą do każdego (runda 6).
                Button { onOpen(.steps) } label: {
                    CookStepRing(count: session.stepCount, current: session.stepIndex)
                        // Dotyk 44 pt przy krążku 36 — układ bez zmian.
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .padding(-4)
                }
                .buttonStyle(PlanPressStyle(scale: 0.9))
                .accessibilityHint("Pokazuje wszystkie kroki")
                .cookChrome(hasAppeared)
                .transition(ringTransition)
            }
            Spacer(minLength: 0)
            SCSheetCloseButton(onImage: true, action: onClose)
                .cookChrome(hasAppeared)
        }
        .padding(.horizontal, SCCook.Spacing.page)
        .padding(.top, 11)
    }

    private var ringTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.7)
                .combined(with: .opacity)
                .animation(SCCook.Motion.step.delay(0.1)),
            removal: .opacity.animation(.easeOut(duration: 0.2))
        )
    }

    // MARK: - Treść

    @ViewBuilder
    private var content: some View {
        switch session.stage {
        case .welcome:
            CookWelcomeContent(session: session, recipe: recipe)
                .transition(contentTransition)
                .zIndex(2)
        case .steps:
            // Kontener z przejściem — nie `if let` z przejściem w środku,
            // żeby wyjście z kroków na pewno gasło, a nie cięło.
            ZStack(alignment: .topLeading) {
                if let step = session.currentStep {
                    CookStepScene(session: session, step: step, direction: direction)
                }
            }
            .transition(contentTransition)
            .zIndex(1)
        case .finished:
            TimelineView(.periodic(from: .now, by: 60)) { context in
                CookFinishContent(session: session, recipe: recipe, now: context.date, onFeedback: onFeedback)
            }
            .transition(contentTransition)
            .zIndex(0)
        }
    }

    /// Nowa treść staje od razu (jej sekcje startują niewidoczne i wchodzą
    /// kaskadą), stara gaśnie w miejscu na wierzchu (`zIndex` idzie za
    /// kolejnością etapów).
    private var contentTransition: AnyTransition {
        .asymmetric(
            insertion: .identity,
            removal: .opacity.animation(.easeOut(duration: reduceMotion ? 0.15 : 0.2))
        )
    }

    // MARK: - Stopka i dok

    /// Stopka etapu na płycie stopki aplikacji (`SCSheetFooter`) — w krokach
    /// jej miejsce zajmuje dok, który pływa nad treścią.
    @ViewBuilder
    private var footer: some View {
        switch session.stage {
        case .welcome:
            CookWelcomeFooter(session: session, onPortions: onPortions, onOpen: onOpen, onStart: onStart)
                .transition(footerTransition)
        case .steps:
            EmptyView()
        case .finished:
            CookFinishFooter(onEaten: onEaten)
                .transition(footerTransition)
        }
    }

    /// Płyta stopki rozjaśnia się (przycisk wchodzi kaskadą sam), przy
    /// wyjściu gaśnie i lekko zjeżdża.
    private var footerTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.25)),
            removal: .opacity
                .combined(with: .offset(y: 24))
                .animation(.easeOut(duration: 0.2))
        )
    }

    @ViewBuilder
    private var dock: some View {
        if session.stage == .steps {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                CookDock(
                    session: session,
                    now: context.date,
                    onBack: onBack,
                    onNext: onNext,
                    onTimer: onTimer,
                    onOpen: onOpen
                )
            }
            // Wejście w tryb prosto w kroki (wznowienie) — dok wchodzi
            // z kaskadą; przy „Zaczynamy” — przejściem poniżej.
            .cookReveal(hasAppeared, order: 3)
            .transition(dockTransition)
        }
    }

    /// Dok wyjeżdża od dołu za treścią kroku, przy końcu zjeżdża i gaśnie.
    private var dockTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .offset(y: 60)
                .combined(with: .opacity)
                .animation(SCCook.Motion.step.delay(0.12)),
            removal: .offset(y: 60)
                .combined(with: .opacity)
                .animation(.easeOut(duration: 0.2))
        )
    }

    // MARK: - Ruch

    private func scrollToTop() {
        withAnimation(SCCook.Motion.step) {
            scrollPosition.scrollTo(edge: .top)
        }
    }

    /// Przesunięcie w bok = krok dalej / wstecz (§4.2) — tylko w krokach.
    /// Równolegle z przewijaniem; liczy się tylko wyraźnie poziomy ruch.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard session.stage == .steps else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 70, abs(dx) > abs(dy) * 1.6 else { return }
                if dx < 0 {
                    if !session.isLastStep { onNext() }
                } else if !session.isFirstStep {
                    onBack()
                }
            }
    }
}
