import SwiftUI

/// Arkusz trybu Gotuj — najwyżej jeden naraz. Timery i Składniki to arkusze
/// systemu (runda 3 testów, 1.10.2026: „jak otwieram / zamykam sheet od
/// timerów oraz od składników, to trochę się buguje animacja”) — dawne karty
/// rozwijane z doku przestawiały dok i treść pod palcem.
enum CookSheet: String, Identifiable {
    /// Wszystkie timery — z kapsuły i plakietki „+N”.
    case timers
    /// Składniki kroku — z wyspy; pół ekranu, przewijanie rozwija na cały.
    case ingredients
    /// Szuflady powitania: cały przepis i rady kucharza.
    case recipeIngredients
    case tips
    /// „Wychodzisz z gotowania?” — krzyżyk w krokach.
    case exit

    var id: String { rawValue }
}

/// Tryb Gotuj — pełny ekran nad pulpitem (D6): powitanie → kroki →
/// „Smacznego!” na JEDNYM ekranie (`CookScreen`), a nad krokami ekran końca
/// timera, gdy któryś dzwoni.
///
/// Stan żyje w `CookSessionStore` (zapis przy każdej zmianie), widok tylko
/// go rysuje i przekazuje decyzje. Ekran nie gaśnie przez cały tryb.
/// Krzyżyk w trakcie kroków pyta „Wychodzisz z gotowania?” (D22); na
/// powitaniu, zanim cokolwiek ruszyło, i na końcu po prostu zamyka.
struct CookModeView: View {
    let store: CookSessionStore
    /// „Zjedzone” — odhaczenie w planie robi pulpit (dostęp do planu).
    let onEaten: (CookSession) -> Void
    let onFeedback: (CookFeedback) -> Void

    @State private var sheet: CookSheet?
    /// Składniki otwierają się zawsze na pół ekranu.
    @State private var ingredientsDetent: PresentationDetent = .medium
    @State private var direction: Edge = .trailing
    /// Zdjęcie dania osiada RAZ, przy wejściu w tryb — przejście powitanie →
    /// kroki → koniec go nie powtarza (to samo zdjęcie w tym samym miejscu).
    @State private var isPhotoRevealed = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `initialSheet` — tylko ekran debug (zrzut otwartego arkusza).
    init(
        store: CookSessionStore,
        onEaten: @escaping (CookSession) -> Void,
        onFeedback: @escaping (CookFeedback) -> Void = { _ in },
        initialSheet: CookSheet? = nil
    ) {
        self.store = store
        self.onEaten = onEaten
        self.onFeedback = onFeedback
        _sheet = State(initialValue: initialSheet)
    }

    var body: some View {
        ZStack {
            Color.scPageBase(scheme).ignoresSafeArea()
            if let session = store.session {
                screen(session)
                if session.stage == .steps {
                    alarm(session)
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .task {
            guard !isPhotoRevealed else { return }
            await CookEntrance.breathe()
            isPhotoRevealed = true
        }
        .sheet(item: $sheet) { kind in
            sheetContent(kind)
        }
    }

    private func screen(_ session: CookSession) -> some View {
        CookScreen(
            session: session,
            recipe: CookRecipeFacts(
                headline: CookRecipeFacts.shortTitle(session.recipeTitle),
                subtitle: CookRecipeFacts.subtitle(session.recipeTitle),
                difficultyText: session.difficultyText,
                kcalPerServing: session.kcalPerServing
            ),
            isPhotoRevealed: isPhotoRevealed,
            direction: direction,
            // Porcje rolują liczby w karcie, stepperze i skrócie składników.
            onPortions: { value in
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : SCMotion.textRoll) {
                    store.update { $0.setPortions(value) }
                }
            },
            onStart: {
                direction = .trailing
                withAnimation(SCCook.Motion.step) {
                    store.update { $0.begin(now: Date()) }
                }
            },
            onClose: { close(session) },
            onBack: { move(forward: false) },
            onNext: { move(forward: true) },
            onTimer: { action in handle(action) },
            onOpen: { kind in present(kind) },
            onEaten: {
                onEaten(session)
                store.end()
            },
            onFeedback: onFeedback
        )
    }

    /// Ekran końca timera nad krokami. Arkusza nie da się przykryć widokiem
    /// spod niego, więc dzwoniący timer najpierw zamyka otwarty arkusz
    /// (Timery, Składniki, „Wychodzisz…”) — alarm jest ważniejszy.
    private func alarm(_ session: CookSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let ringing = session.ringingTimer(now: context.date)
            ZStack {
                if let ringing {
                    CookAlarmView(
                        session: session,
                        item: ringing,
                        now: context.date,
                        onExtend: { seconds in
                            withAnimation(.easeOut(duration: 0.25)) {
                                store.update { $0.extendTimer(ringing.id, by: seconds, now: Date()) }
                            }
                        },
                        onSilence: {
                            withAnimation(.easeOut(duration: 0.25)) {
                                store.update { $0.silenceTimer(ringing.id) }
                            }
                        },
                        onDone: {
                            sheet = nil
                            direction = .trailing
                            withAnimation(SCCook.Motion.step) {
                                store.update { $0.finishTimerAndAdvance(ringing.id, now: Date()) }
                            }
                        }
                    )
                    // Nowy timer = nowy ekran: drugi alarm zaraz po pierwszym
                    // nie dziedziczy jego tarczy (wskazówka cofałaby się po
                    // obwodzie do krótszego „po czasie”).
                    .id(ringing.id)
                    .transition(.opacity)
                }
            }
            .onChange(of: ringing?.id, initial: true) { _, id in
                if id != nil { sheet = nil }
            }
        }
    }

    // MARK: - Arkusze

    @ViewBuilder
    private func sheetContent(_ kind: CookSheet) -> some View {
        if let session = store.session {
            sheetBody(kind, session: session)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(40)
                .presentationBackground(Color.scCanvas(scheme))
        }
    }

    @ViewBuilder
    private func sheetBody(_ kind: CookSheet, session: CookSession) -> some View {
        switch kind {
        case .timers:
            // Wysokość podaje arkusz sam — z treści (liczba timerów).
            CookTimersSheet(
                session: session,
                onTimer: { action in handle(action) },
                onClose: { sheet = nil }
            )
        case .ingredients:
            CookIngredientsSheet(session: session, onClose: { sheet = nil })
                .presentationDetents([.medium, .large], selection: $ingredientsDetent)
                // Przewijanie listy najpierw rozwija arkusz na cały ekran.
                .presentationContentInteraction(.resizes)
        case .recipeIngredients:
            CookWelcomeDrawerSheet(session: session, drawer: .ingredients)
                .presentationDetents([.medium, .large])
                .presentationContentInteraction(.resizes)
        case .tips:
            CookWelcomeDrawerSheet(session: session, drawer: .tips)
                .presentationDetents([.medium, .large])
                .presentationContentInteraction(.resizes)
        case .exit:
            CookExitSheet(
                session: session,
                onPause: {
                    sheet = nil
                    store.pause()
                },
                onEnd: {
                    sheet = nil
                    store.end()
                },
                onContinue: { sheet = nil }
            )
            // Wysokość podaje arkusz sam — z treści (liczba trwających timerów).
        }
    }

    private func present(_ kind: CookSheet) {
        if kind == .ingredients { ingredientsDetent = .medium }
        sheet = kind
    }

    // MARK: - Decyzje

    private func close(_ session: CookSession) {
        switch session.stage {
        case .welcome, .finished:
            store.end()
        case .steps:
            present(.exit)
        }
    }

    private func move(forward: Bool) {
        sheet = nil
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
                case .skip(let id): session.skipTimer(id, now: now)
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
