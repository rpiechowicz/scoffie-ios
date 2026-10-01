import SwiftUI

/// Ekran kroku (Y3K1–3): u góry pierścień kroków i krzyżyk, scena (etap ·
/// tytuł · opis · adnotacja) pod zdjęciem dania, na dole dok. Tekst przewija
/// się pod dokiem, a jego koniec staje nad nim (`spacing.cookDockReserve`).
///
/// Ruch (§8.2, `motion.cookStep`): przy wejściu sekcje wjeżdżają kaskadą,
/// przy zmianie kroku nagłówek (etap i tytuł) ROLUJE się w miejscu jak danie
/// w arkuszu wyboru posiłku, a opis wjeżdża z boku, z którego przyszedł krok,
/// o chwilę później — nagłówek szybciej niż „jak”. Układ zostaje jeden: nowy
/// opis i stary leżą w tym samym `ZStack`, więc nic pod nimi nie skacze.
struct CookStepView: View {
    let session: CookSession
    let step: CookStep
    /// Skąd przyszedł krok — nowy wjeżdża z tej strony.
    let direction: Edge
    /// Zdjęcie osiada raz, przy wejściu w tryb (`CookModeView`).
    let isPhotoRevealed: Bool
    @Binding var card: CookDock.Card?
    let onClose: () -> Void
    let onBack: () -> Void
    let onNext: () -> Void
    let onTimer: (CookTimerAction) -> Void

    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var hasAppeared = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Color.scPageBase(scheme).ignoresSafeArea()

            ScrollView {
                ZStack(alignment: .topLeading) {
                    CookHeaderPhoto(url: session.imageURL, isRevealed: isPhotoRevealed)
                    scene
                }
                // Szerokość treści = szerokość ekranu (wzór szczegółów
                // posiłku): żaden element nie poszerzy obszaru przewijania.
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
            .scrollPosition($scrollPosition)
            // Zdjęcie pod paskiem stanu; dół zostaje w bezpiecznym obszarze,
            // tak jak dok (`cookDockReserve` liczy się od jego krawędzi).
            .ignoresSafeArea(edges: .top)
            .simultaneousGesture(swipe)
            // Nowy krok zaczyna się od tytułu, nie od miejsca, w którym
            // skończyło się czytanie poprzedniego.
            .onChange(of: step.id) {
                withAnimation(SCCook.Motion.step) {
                    scrollPosition.scrollTo(edge: .top)
                }
            }

            topBar
        }
        .overlay {
            if card != nil {
                SCCook.Palette.scrim(scheme)
                    .ignoresSafeArea()
                    .onTapGesture { card = nil }
                    .transition(.opacity)
                    .accessibilityLabel("Zamknij kartę")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .overlay(alignment: .bottom) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                CookDock(
                    session: session,
                    now: context.date,
                    card: $card,
                    onBack: onBack,
                    onNext: onNext,
                    onTimer: onTimer
                )
            }
            .cookReveal(hasAppeared, order: 3)
            // Dok stoi tam, gdzie dolne menu aplikacji — na dolnej krawędzi
            // bezpiecznego obszaru (runda 2: „ciut za wysoko”).
        }
        .animation(SCCook.Motion.dock, value: card)
        .task {
            guard !hasAppeared else { return }
            await CookEntrance.breathe()
            hasAppeared = true
        }
    }

    /// Pierścień kroków i krzyżyk — ta sama wielkość i powierzchnia. Przy
    /// wejściu pojawia się tylko pierścień: krzyżyk stoi w tym samym miejscu
    /// na powitaniu, więc przejście powitanie → krok go nie gasi.
    private var topBar: some View {
        HStack(spacing: 10) {
            CookStepRing(count: session.stepCount, current: session.stepIndex)
                .cookChrome(hasAppeared)
                .frame(maxWidth: .infinity, alignment: .leading)
            SCSheetCloseButton(onImage: true, action: onClose)
        }
        .padding(.horizontal, SCCook.Spacing.page)
        .padding(.top, 11)
    }

    private var scene: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: SCCook.Spacing.titleTop)

            header
                .cookReveal(hasAppeared, order: 0)

            ZStack(alignment: .topLeading) {
                details
                    .id(step.id)
                    .transition(detailsTransition)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cookReveal(hasAppeared, order: 1)

            Color.clear.frame(height: SCCook.Spacing.dockReserve + 24)
        }
        .padding(.horizontal, SCCook.Spacing.page)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Etap i tytuł — ten sam widok przez wszystkie kroki, tekst roluje się
    /// w miejscu (wstecz = w drugą stronę).
    private var header: some View {
        let backwards = direction == .leading
        return VStack(alignment: .leading, spacing: 0) {
            if let stage = step.stageLabel {
                Text(stage)
                    .cookText(SCCook.Typography.stage)
                    .foregroundStyle(SCPalette.sage)
                    .cookRoll(stage, countsDown: backwards)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }

            Text(step.title)
                .cookText(titleStyle)
                .foregroundStyle(Color.scLabel(scheme))
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .cookRoll(step.title, countsDown: backwards)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Opis, adnotacja i dopisek o porcjach — nowy krok = nowy widok, który
    /// wjeżdża z boku.
    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(session.package.body(for: step, portions: session.portions))
                .cookText(SCCook.Typography.stepBody)
                .foregroundStyle(SCCook.Palette.body(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            if let note = step.note {
                CookNoteLine(kind: note.kind, text: note.text)
                    .padding(.top, 12)
            }

            if let scaleNote = session.package.scaleNote(for: step, portions: session.portions) {
                CookNoteLine(kind: .tip, text: scaleNote, systemImage: "person.2")
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Nowy opis wjeżdża z boku z lekkim opóźnieniem za nagłówkiem, stary
    /// gaśnie od razu w miejscu. Przy „Ogranicz ruch” — samo przenikanie.
    private var detailsTransition: AnyTransition {
        if reduceMotion {
            return .opacity.animation(.easeInOut(duration: 0.2))
        }
        let shift: CGFloat = direction == .trailing ? 44 : -44
        return .asymmetric(
            insertion: .offset(x: shift)
                .combined(with: .opacity)
                .animation(SCCook.Motion.step.delay(0.06)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }

    /// Tytuł ≤ 30 znaków mieści się w dwóch liniach 40 pt (zasady .5, D37);
    /// dłuższy (scenariusze sprzed zasad .5) schodzi do 32 pt.
    private var titleStyle: SCCookTextStyle {
        step.title.count > 30 ? SCCook.Typography.stepTitleCompact : SCCook.Typography.stepTitle
    }

    /// Przesunięcie w bok = krok dalej / wstecz (§4.2). Równolegle
    /// z przewijaniem — liczy się tylko wyraźnie poziomy ruch.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 70, abs(dx) > abs(dy) * 1.6, card == nil else { return }
                if dx < 0 {
                    if !session.isLastStep { onNext() }
                } else if !session.isFirstStep {
                    onBack()
                }
            }
    }
}

/// Adnotacja kroku: ostrzeżenie w maśle z trójkątem (makieta), „po czym
/// poznać” i rada — cicha linijka z ikoną.
struct CookNoteLine: View {
    let kind: CookNoteKind
    let text: String
    var systemImage: String? = nil

    @Environment(\.colorScheme) private var scheme

    private var icon: String {
        if let systemImage { return systemImage }
        switch kind {
        case .warning: return "exclamationmark.triangle"
        case .cue: return "eye"
        case .tip, .unknown: return "lightbulb"
        }
    }

    private var tint: Color {
        switch kind {
        case .warning: SCPalette.butter
        case .cue: SCPalette.sage
        case .tip, .unknown: SCPalette.butter
        }
    }

    private var textColor: Color {
        kind == .warning ? SCPalette.butter : SCCook.Palette.body(scheme)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .cookText(SCCook.Typography.note)
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityPrefix + text)
    }

    private var accessibilityPrefix: String {
        switch kind {
        case .warning: "Uwaga: "
        case .cue: "Po czym poznać: "
        case .tip, .unknown: "Rada: "
        }
    }
}
