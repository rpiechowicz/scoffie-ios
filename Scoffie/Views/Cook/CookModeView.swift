import SwiftUI

/// Tryb Gotuj — pełny ekran nad pulpitem (D6): powitanie → kroki →
/// „Smacznego!”, a nad krokami ekran końca timera, gdy któryś dzwoni.
///
/// Stan żyje w `CookSessionStore` (zapis przy każdej zmianie), widok tylko
/// go rysuje i przekazuje decyzje. Ekran nie gaśnie przez cały tryb.
/// Krzyżyk w trakcie kroków pyta „Wychodzisz z gotowania?” (D22); na
/// powitaniu, zanim cokolwiek ruszyło, po prostu zamyka.
struct CookModeView: View {
    let store: CookSessionStore
    /// „Zjedzone” — odhaczenie w planie robi pulpit (dostęp do planu).
    let onEaten: (CookSession) -> Void
    let onFeedback: (CookFeedback) -> Void

    @State private var card: CookDock.Card?
    @State private var isExitPresented = false
    @State private var direction: Edge = .trailing
    @Environment(\.colorScheme) private var scheme

    /// `initialCard` / `showsExit` — tylko ekran debug (zrzut otwartej karty
    /// albo arkusza wyjścia).
    init(
        store: CookSessionStore,
        onEaten: @escaping (CookSession) -> Void,
        onFeedback: @escaping (CookFeedback) -> Void = { _ in },
        initialCard: CookDock.Card? = nil,
        showsExit: Bool = false
    ) {
        self.store = store
        self.onEaten = onEaten
        self.onFeedback = onFeedback
        _card = State(initialValue: initialCard)
        _isExitPresented = State(initialValue: showsExit)
    }

    var body: some View {
        ZStack {
            Color.scPageBase(scheme).ignoresSafeArea()
            if let session = store.session {
                screen(session)
            }
        }
        .interactiveDismissDisabled()
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $isExitPresented) {
            if let session = store.session {
                CookExitSheet(
                    session: session,
                    onPause: {
                        isExitPresented = false
                        store.pause()
                    },
                    onEnd: {
                        isExitPresented = false
                        store.end()
                    },
                    onContinue: { isExitPresented = false }
                )
                .presentationDetents([.height(440)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(40)
                .presentationBackground(Color.scCanvas(scheme))
            }
        }
    }

    @ViewBuilder
    private func screen(_ session: CookSession) -> some View {
        let facts = CookRecipeFacts(
            headline: CookRecipeFacts.shortTitle(session.recipeTitle),
            subtitle: CookRecipeFacts.subtitle(session.recipeTitle),
            difficultyText: session.difficultyText,
            kcalPerServing: session.kcalPerServing
        )
        switch session.stage {
        case .welcome:
            CookWelcomeView(
                session: session,
                recipe: facts,
                onPortions: { value in store.update { $0.setPortions(value) } },
                onStart: {
                    withAnimation(SCCook.Motion.step) {
                        store.update { $0.begin(now: Date()) }
                    }
                },
                onClose: { store.end() }
            )
            .transition(.opacity)
        case .steps:
            if let step = session.currentStep {
                CookStepView(
                    session: session,
                    step: step,
                    direction: direction,
                    card: $card,
                    onClose: { isExitPresented = true },
                    onBack: { move(forward: false) },
                    onNext: { move(forward: true) },
                    onTimer: handle
                )
                .overlay {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let ringing = session.ringingTimer(now: context.date) {
                            CookAlarmView(
                                session: session,
                                item: ringing,
                                now: context.date,
                                onExtend: { seconds in
                                    store.update { $0.extendTimer(ringing.id, by: seconds, now: Date()) }
                                },
                                onSilence: { store.update { $0.silenceTimer(ringing.id) } },
                                onDone: {
                                    card = nil
                                    direction = .trailing
                                    withAnimation(SCCook.Motion.step) {
                                        store.update { $0.finishTimerAndAdvance(ringing.id, now: Date()) }
                                    }
                                }
                            )
                            .transition(.opacity)
                        }
                    }
                }
            }
        case .finished:
            TimelineView(.periodic(from: .now, by: 60)) { context in
                CookFinishView(
                    session: session,
                    recipe: facts,
                    now: context.date,
                    onEaten: {
                        onEaten(session)
                        store.end()
                    },
                    onClose: { store.end() },
                    onFeedback: onFeedback
                )
            }
            .transition(.opacity)
        }
    }

    private func move(forward: Bool) {
        card = nil
        direction = forward ? .trailing : .leading
        withAnimation(SCCook.Motion.step) {
            store.update { session in
                if forward {
                    session.next(now: Date())
                } else {
                    session.back()
                }
            }
        }
    }

    private func handle(_ action: CookTimerAction) {
        let now = Date()
        withAnimation(SCCook.Motion.dock) {
            store.update { session in
                switch action {
                case .start(let id): session.startTimer(id, now: now)
                case .pause(let id): session.pauseTimer(id, now: now)
                case .resume(let id): session.resumeTimer(id, now: now)
                case .finish(let id): session.finishTimer(id)
                }
            }
        }
    }
}

extension CookSession {
    /// „średnio trudne” na powitaniu.
    var difficultyText: String {
        switch Difficulty(rawValue: difficultyRaw ?? "") {
        case .medium: "średnio trudne"
        case .hard: "trudne"
        case .easy, nil: "łatwe"
        }
    }
}
