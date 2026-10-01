import SwiftUI

/// Dok na dole ekranu kroku (D34): wyspa ‹ Składniki N › zawsze w tym samym
/// miejscu, nad nią każdy timer osobną kapsułą. Wyspa ma wymiary i miejsce
/// dolnego menu aplikacji (60 pt, 20 pt od boków, na dolnej krawędzi
/// bezpiecznego obszaru — runda 2 testów, 1.10.2026).
///
/// Dok ma STAŁĄ wysokość: plakietka, kapsuły i wyspa mają swoje miejsca,
/// także puste (runda 4: „jak się pojawia / chowa timer, wyspa się rusza,
/// przeskakuje”). Wcześniej rząd kapsuł wchodził do `VStack` nad wyspą, dok
/// rósł, a wyspa jechała po krzywej innej niż kapsuły i podskakiwała.
///
/// Najwyżej dwie kapsuły (`CookSession.dockCapsules`), w kolejności kroków,
/// każdy timer w swoim kolorze. Kapsuły mają stałą tożsamość (po id timera)
/// i jeden układ na oba rozmiary, więc druga wjeżdża z boku, a pierwsza
/// zwęża się i przestawia w miejscu. Timery, które się nie zmieściły, mówi
/// plakietka nad kapsułami (`CookOverflowTab`).
///
/// Timery i Składniki otwierają się jako arkusze systemu (`CookSheet`).
struct CookDock: View {
    let session: CookSession
    let now: Date
    let onBack: () -> Void
    let onNext: () -> Void
    let onTimer: (CookTimerAction) -> Void
    let onOpen: (CookSheet) -> Void

    /// Koszyk woła (runda 10: „widać, aż user nie otworzy”; „subtelny, jak
    /// dzwonek w zegarze”): krok przynosi składniki, a arkusza Składniki na
    /// tym kroku jeszcze nikt nie otworzył. Koszyk jest wtedy w terakocie
    /// i kołysze się jak dzwonek na tarczy końca timera, z dłuższą przerwą,
    /// do stuknięcia w Składniki. Krok bez składników koszyka nie rusza.
    @State private var basketPending = false
    /// Kroki, na których arkusz Składniki już był otwarty — powrót do nich
    /// nie woła drugi raz.
    @State private var basketSeenSteps: Set<Int> = []
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Liczba składników bieżącego kroku (plakietka na wyspie).
    private var stepIngredientCount: Int {
        session.currentStep.map { session.package.lines(for: $0, portions: session.portions).count } ?? 0
    }

    /// Plakietka wskakuje sprężyną z małej kropki i znika, kurcząc się
    /// w róg koszyka — jak plakietka na ikonie aplikacji.
    private var badgeTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .scale(scale: 0.2, anchor: .center).combined(with: .opacity)
    }

    private var badgeAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.34, dampingFraction: 0.62)
    }

    var body: some View {
        let capsules = session.dockCapsules(now: now)
        let overflow = session.dockOverflow(now: now)
        VStack(spacing: SCCook.Spacing.overflowGap) {
            ZStack(alignment: .trailing) {
                if !overflow.isEmpty {
                    CookOverflowTab(items: overflow, onOpen: { onOpen(.timers) })
                        .transition(tabTransition)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .frame(height: SCCook.Height.overflowTab)

            VStack(spacing: SCCook.Spacing.dockGap) {
                ZStack(alignment: .bottom) {
                    if !capsules.isEmpty {
                        capsuleRow(capsules)
                            .transition(riseFromIsland)
                    }
                }
                .frame(height: SCCook.Height.timerCapsule)

                island
            }
        }
        .padding(.horizontal, SCCook.Spacing.dockSide)
        .padding(.bottom, SCCook.Spacing.dockBottom)
        .animation(SCCook.Motion.dock, value: capsules.map(\.id))
        .animation(SCCook.Motion.dock, value: overflow.map(\.id))
    }

    /// Rząd kapsuł wychodzi SPOD wyspy: unosi się i rozjaśnia. Wyspa leży nad
    /// nim (jest dalej w `VStack`), więc jego dół chowa się pod nią.
    private var riseFromIsland: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .offset(y: 36).combined(with: .opacity),
            removal: .offset(y: 24).combined(with: .opacity).animation(.easeOut(duration: 0.16))
        )
    }

    private var tabTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity)
    }

    // MARK: - Timery

    private func capsuleRow(_ items: [CookDockTimer]) -> some View {
        let layout: CookTimerCapsule.Layout = items.count > 1 ? .pair : .single
        return HStack(spacing: SCCook.Spacing.capsuleGap) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                CookTimerCapsule(item: item, layout: layout, onTimer: onTimer, onOpen: { onOpen(.timers) })
                    // Kapsuła wjeżdża z tej strony, po której staje —
                    // pominięty timer z wcześniejszego kroku staje z lewej.
                    // Z pary schodzi swoim bokiem; pojedyncza w lewo (gdy
                    // miejsce bierze następna, ta wjeżdża z prawej).
                    .transition(capsuleTransition(
                        in: index == items.count - 1 ? .trailing : .leading,
                        out: items.count > 1 && index == items.count - 1 ? .trailing : .leading
                    ))
            }
        }
    }

    /// Wejście i zejście tą samą stroną (runda 9: „jak pominę timer, to jego
    /// animacja się buguje”): zejście było malejącą kapsułą w miejscu, a druga
    /// z pary w tym samym czasie rozciągała się NA nią — dwie kapsuły (w jasnym
    /// motywie dwa szkła) nachodziły na siebie. Teraz schodząca usuwa się na
    /// swój bok, a sąsiednia zajmuje zwolnione miejsce.
    private func capsuleTransition(in insertionEdge: Edge, out removalEdge: Edge) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge)
                .combined(with: .opacity)
                .animation(.easeIn(duration: 0.22))
        )
    }

    // MARK: - Wyspa

    private var island: some View {
        let count = stepIngredientCount
        // Jeden krążek „Dalej”: w ostatnim kroku strzałka PRZECHODZI w ptaszek
        // na szałwii (glif się podmienia, kolory przenikają).
        let isLast = session.isLastStep
        // Jasny motyw (szkło, runda 7): „Wstecz” prawie przezroczyste,
        // „Dalej” w miękkiej terakocie — jak wybrana zakładka w dolnym menu.
        let light = scheme == .light
        return HStack(spacing: SCCook.Spacing.islandGap) {
            islandCircle(
                systemName: "chevron.left",
                fill: light ? Color.scLabel(scheme).opacity(0.06) : Color.scTileStroke(scheme),
                stroke: light ? .clear : Color.scTileBg(scheme),
                tint: Color.scLabel(scheme),
                label: "Poprzedni krok",
                action: onBack
            )
            .disabled(session.isFirstStep)
            .opacity(session.isFirstStep ? 0.4 : 1)

            Button {
                basketSeenSteps.insert(session.stepIndex)
                basketPending = false
                onOpen(.ingredients)
            } label: {
                HStack(spacing: SCCook.Spacing.islandLabelGap) {
                    CookBasketGlyph(callID: basketPending ? session.stepIndex : nil)
                        // Plakietka NAD koszykiem (runda 11), poza jego
                        // kołysaniem — liczba stoi, koszyk się buja.
                        .overlay(alignment: .topTrailing) {
                            ZStack {
                                if count > 0 {
                                    CookIslandBadge(count: count)
                                        .transition(badgeTransition)
                                }
                            }
                            .alignmentGuide(.trailing) { $0[HorizontalAlignment.center] - SCCook.Spacing.islandBadgeInset }
                            .alignmentGuide(.top) { $0[VerticalAlignment.center] + SCCook.Spacing.islandBadgeInset }
                            .animation(badgeAnimation, value: count > 0)
                        }
                    Text("Składniki")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(Color.scLabel(scheme))
                .frame(maxWidth: .infinity)
                .frame(height: SCCook.Size.islandButton)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(count > 0 ? "Składniki, \(count)" : "Składniki")

            islandCircle(
                systemName: isLast ? "checkmark" : "arrow.right",
                fill: isLast
                    ? SCPalette.sage.opacity(SCCook.Opacity.finishFill)
                    : (light ? SCPalette.terracotta.opacity(0.13) : SCCook.Palette.ringTodo(scheme)),
                stroke: isLast
                    ? SCPalette.sage.opacity(SCCook.Opacity.finishStroke)
                    : (light ? .clear : SCCook.Palette.badge(scheme)),
                tint: isLast ? SCPalette.sage : (light ? SCPalette.terracotta : Color.scLabel(scheme)),
                label: isLast ? "Zakończ gotowanie" : "Następny krok",
                action: onNext
            )
        }
        .padding(SCCook.Spacing.islandPadding)
        .frame(height: SCCook.Height.island)
        .cookIslandSurface(scheme)
        .sensoryFeedback(.selection, trigger: session.stepIndex)
        .onChange(of: session.stepIndex, initial: true) { updateBasketCall() }
    }

    private func updateBasketCall() {
        basketPending = stepIngredientCount > 0 && !basketSeenSteps.contains(session.stepIndex)
    }

    private func islandCircle(
        systemName: String,
        fill: Color,
        stroke: Color,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: SCCook.Size.islandButton, height: SCCook.Size.islandButton)
                .background(Circle().fill(fill))
                .overlay(Circle().strokeBorder(stroke, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Co użytkownik zrobił z timerem — jedna droga z kapsuły, plakietki,
/// arkusza i alarmu.
enum CookTimerAction {
    case start(String)
    case pause(String)
    case resume(String)
    case finish(String)
    /// „Pomiń” timer, który czeka na włączenie (runda 4: pominięty przy
    /// „Dalej” już sam nie znika).
    case skip(String)
}

extension CookDockTimer {
    /// Jedyny ruch, który ma sens w tym stanie: włącz / pauza / wznów /
    /// gotowe. `nil` = timer skończony.
    var primaryAction: CookTimerAction? {
        switch status {
        case .pending: .start(id)
        case .running: .pause(id)
        case .paused: .resume(id)
        case .overdue: .finish(id)
        case .finished: nil
        }
    }

    /// Glif tego ruchu — ten sam w kapsule i w arkuszu Timery.
    var primaryIcon: String {
        switch status {
        case .pending, .paused: "play.fill"
        case .running: "pause.fill"
        case .overdue, .finished: "checkmark"
        }
    }

    var primaryLabel: String {
        switch status {
        case .pending: "Start: \(timer.label)"
        case .running: "Pauza: \(timer.label)"
        case .paused: "Wznów: \(timer.label)"
        case .overdue, .finished: "Gotowe: \(timer.label)"
        }
    }
}

/// Kapsuła timera nad wyspą — w kolorze SWOJEGO timera, we wszystkich stanach.
///
/// - Pojedyncza (cała szerokość): pierścień, etykieta, czas i przycisk
///   w pigułce z makiety (pauza / ▶ Start / ▶ Wznów / ✓ Gotowe).
/// - Z pary: PIERŚCIEŃ JEST PRZYCISKIEM tego samego ruchu, z glifem w środku
///   (runda 2: „włączyć / wyłączyć timer z pulpitu, nie wchodząc w kartę”).
///
/// Oba rozmiary to JEDEN układ: pierścień, teksty i pigułka zostają tymi
/// samymi widokami, więc przy wjeździe drugiego timera kapsuła zwęża się,
/// pierścień rośnie i dostaje glif, a pigułka gaśnie — w jednym ruchu
/// (runda 4: „ten 1 powinien animować się, zmieniając swój design”). Dawniej
/// `switch` na układzie podmieniał całą treść i kapsuła przeskakiwała.
///
/// Stuknięcie w resztę kapsuły otwiera arkusz Timery; w „do włączenia” cała
/// kapsuła włącza timer (makieta). Przytrzymanie: „Włącz” / „Pomiń timer”.
struct CookTimerCapsule: View {
    enum Layout {
        case single
        case pair
    }

    let item: CookDockTimer
    let layout: Layout
    let onTimer: (CookTimerAction) -> Void
    let onOpen: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSingle: Bool { layout == .single }
    private var isOverdue: Bool { if case .overdue = item.status { true } else { false } }
    private var isPending: Bool { if case .pending = item.status { true } else { false } }
    private var isPaused: Bool { if case .paused = item.status { true } else { false } }
    private var isRunning: Bool { if case .running = item.status { true } else { false } }

    private var color: Color { item.accent.color }

    var body: some View {
        HStack(spacing: isSingle ? 10 : 8) {
            ring
            bodyButton
            if isSingle {
                singleAction
                    .transition(actionTransition)
            }
        }
        .padding(.leading, isSingle ? 12 : 8)
        .padding(.trailing, isSingle ? 6 : 12)
        .frame(height: SCCook.Height.timerCapsule)
        .frame(maxWidth: .infinity)
        .background(background)
        .overlay(border)
        .clipShape(Capsule())
        .cookDockGlass(scheme)
        .contentShape(Capsule())
        .contentShape(.contextMenuPreview, Capsule())
        .contextMenu { menu }
        .shadow(color: scheme == .dark ? SCCook.Palette.dockShadow(scheme) : .clear, radius: 15, y: 12)
        .cookInvitePulse(Capsule(), color: color, isActive: isPending)
        .cookOverduePulse(Capsule(), color: color, isActive: isOverdue)
        // Koniec odliczania przychodzi z zegara (bez animacji w transakcji) —
        // kolor kapsuły przechodzi sprężyną doku, a nie w klatce.
        .animation(SCCook.Motion.dock, value: item.status.phase)
    }

    private var actionTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .scale(scale: 0.6, anchor: .trailing).combined(with: .opacity)
    }

    private func bodyAction() {
        if isPending {
            onTimer(.start(item.id))
        } else {
            onOpen()
        }
    }

    // MARK: Pierścień

    /// Pierścień — ten sam widok w obu rozmiarach: w parze rośnie i dostaje
    /// glif ruchu (jest przyciskiem), w pojedynczej jest częścią kapsuły
    /// (stuknięcie jak w resztę), a ruch stoi w pigułce obok.
    private var ring: some View {
        let side = isSingle ? SCCook.Size.timerRing : SCCook.Size.timerRingPair
        return Button {
            if isSingle {
                bodyAction()
            } else if let action = item.primaryAction {
                onTimer(action)
            }
        } label: {
            ZStack {
                Circle().fill(ringFill)
                // Do włączenia w pojedynczej: cicha obręcz — start jest w pigułce.
                Circle()
                    .strokeBorder(color.opacity(SCCook.Opacity.pendingRing), lineWidth: SCCook.Stroke.timerRing)
                    .opacity(isPending && isSingle ? 1 : 0)
                CookTimerRing(
                    fraction: item.status.remainingFraction,
                    color: isPaused ? Color.scMuted(scheme) : color,
                    lineWidth: isSingle ? SCCook.Stroke.timerRing : SCCook.Stroke.timerRingSmall
                )
                .opacity(isRunning || isPaused ? 1 : 0)
                Image(systemName: glyph ?? item.primaryIcon)
                    .font(.system(size: isSingle && isOverdue ? 15 : 11, weight: .heavy))
                    .foregroundStyle(glyphColor)
                    .offset(x: glyph == "play.fill" ? 1 : 0)
                    .contentTransition(.symbolEffect(.replace))
                    .opacity(glyph == nil ? 0 : 1)
            }
            .frame(width: side, height: side)
            .scTapTarget(44, drawn: side)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.primaryLabel)
        // W pojedynczej robi to samo co reszta kapsuły — VoiceOver czytałby
        // kapsułę dwa razy.
        .accessibilityHidden(isSingle)
    }

    /// Glif w pierścieniu: w parze — ruch (▶ / pauza / ✓), w pojedynczej —
    /// sam stan (dzwonek po czasie, pauza), bo ruch stoi w pigułce.
    private var glyph: String? {
        if !isSingle { return item.primaryIcon }
        switch item.status {
        case .overdue: return "bell.fill"
        case .paused: return "pause.fill"
        case .pending, .running, .finished: return nil
        }
    }

    private var ringFill: Color {
        if isOverdue { return Color.scPageBase(scheme).opacity(0.16) }
        if isPending, !isSingle { return color }
        return .clear
    }

    private var glyphColor: Color {
        if isOverdue || isPending { return Color.scPageBase(scheme) }
        if isPaused { return isSingle ? Color.scMuted(scheme) : Color.scLabel(scheme) }
        return color
    }

    // MARK: Teksty

    private var bodyButton: some View {
        Button(action: bodyAction) {
            texts
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CookDockLabels.accessibility(item))
        .accessibilityHint(isPending ? "Włącza timer" : "Otwiera arkusz Timery")
    }

    private var texts: some View {
        // W parze bez dopisków („· pauza”, „· po czasie”) — stan mówi kolor
        // i glif w pierścieniu, a połowa szerokości nie mieści dwóch słów
        // więcej. „Do włączenia” zawsze z warunkiem startu (D37: „Gdy woda
        // zawrze”), bo to on mówi, kiedy stuknąć.
        let label = isSingle || isPending ? CookDockLabels.capsuleLabel(item) : item.timer.label
        let time = CookDockLabels.time(item.status)
        // Czas zawsze w kroju pojedynczej, w parze zmniejszony skalą — zmiana
        // kroju przeskakuje, a skala przechodzi płynnie razem z kapsułą.
        let timeScale = isSingle ? 1 : SCCook.Typography.timerTimePair.size / SCCook.Typography.timerTime.size
        return VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .cookText(SCCook.Typography.timerLabel)
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .cookRoll(label)
            Text(time)
                .cookText(SCCook.Typography.timerTime)
                .monospacedDigit()
                .foregroundStyle(timeColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .cookTicking(time, countsDown: !isOverdue)
                .scaleEffect(timeScale, anchor: .leading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var labelColor: Color {
        if isOverdue { return Color.scPageBase(scheme) }
        if isPaused { return Color.scMuted(scheme) }
        return color
    }

    private var timeColor: Color {
        if isOverdue { return Color.scPageBase(scheme) }
        if isPaused { return Color.scMuted(scheme) }
        return Color.scLabel(scheme)
    }

    // MARK: Tło

    /// Barwa stanu na powierzchni doku — w jasnym motywie na szkle
    /// (`cookDockGlass`), więc bez kryjącego spodu.
    @ViewBuilder
    private var background: some View {
        let surface = scheme == .dark ? SCCook.Palette.dockSurface(scheme) : .clear
        if isOverdue {
            color
        } else if isPaused {
            ZStack { surface; SCCook.Palette.pausedFill(scheme) }
        } else if isPending {
            ZStack { surface; color.opacity(SCCook.Opacity.pendingFill) }
        } else {
            ZStack { surface; color.opacity(SCCook.Opacity.timerFill) }
        }
    }

    @ViewBuilder
    private var border: some View {
        if isOverdue {
            EmptyView()
        } else if isPaused {
            Capsule().strokeBorder(Color.scRule(scheme), lineWidth: 1)
        } else if isPending {
            Capsule().strokeBorder(color, lineWidth: 1.5)
        } else {
            Capsule().strokeBorder(color.opacity(SCCook.Opacity.timerStroke), lineWidth: 1)
        }
    }

    // MARK: Pojedyncza — przycisk z makiety

    /// Przycisk z makiety: pauza w krążku albo pigułka.
    @ViewBuilder
    private var singleAction: some View {
        switch item.status {
        case .running:
            Button { onTimer(.pause(item.id)) } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: SCCook.Height.timerAction, height: SCCook.Height.timerAction)
                    .overlay(Circle().strokeBorder(color, lineWidth: 2))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.primaryLabel)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        case .pending:
            pillButton(title: "Start", icon: "play.fill", fill: color, ink: Color.scPageBase(scheme)) {
                onTimer(.start(item.id))
            }
        case .paused:
            pillButton(title: "Wznów", icon: "play.fill", fill: Color.scChipBg(scheme), ink: Color.scLabel(scheme), stroke: SCCook.Palette.ringTodo(scheme)) {
                onTimer(.resume(item.id))
            }
        case .overdue:
            pillButton(title: "Gotowe", icon: "checkmark", fill: Color.scPageBase(scheme).opacity(0.16), ink: Color.scPageBase(scheme), size: 14) {
                onTimer(.finish(item.id))
            }
        case .finished:
            EmptyView()
        }
    }

    private func pillButton(
        title: String,
        icon: String,
        fill: Color,
        ink: Color,
        stroke: Color? = nil,
        size: CGFloat = 15,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: size - 3, weight: .heavy))
                Text(title)
                    .font(.system(size: size, weight: .heavy))
            }
            .foregroundStyle(ink)
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .frame(height: SCCook.Height.timerAction)
            .background(Capsule().fill(fill))
            .overlay {
                if let stroke {
                    Capsule().strokeBorder(stroke, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.primaryLabel)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    // MARK: Przytrzymanie

    /// Akcja z menu kontekstowego rusza PO jego zamknięciu (runda 9). Zmiana
    /// kapsuły w trakcie zamykania menu — podgląd wraca na miejsce, którego
    /// już nie ma albo które właśnie się zmienia — szarpała animacją.
    private func afterMenu(_ action: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            action()
        }
    }

    @ViewBuilder
    private var menu: some View {
        if isPending {
            Button {
                afterMenu { onTimer(.start(item.id)) }
            } label: {
                Label("Włącz", systemImage: "play.fill")
            }
            Button(role: .destructive) {
                afterMenu { onTimer(.skip(item.id)) }
            } label: {
                Label("Pomiń timer", systemImage: "forward.end")
            }
        } else {
            Button(action: onOpen) {
                Label("Wszystkie timery", systemImage: "timer")
            }
        }
    }
}

// MARK: - Plakietka

/// Plakietka nad kapsułami: timery, które się w nich nie zmieściły (runda 4:
/// zamiast gołego „+1” — „info, że timer idzie, że trzeba włączyć, że jest
/// wstrzymany”). Każdy ukryty timer to znaczek stanu w swoim kolorze
/// (`CookTimerMark`), a obok JEDNO krótkie zdanie (runda 5: „+2 · 2 trwają”
/// powtarzało liczbę):
/// - jeden timer — nazwa i stan: „Ziemniaki · 12:04”, „W piekarniku · włącz”;
/// - kilka w tym samym stanie — liczba ze stanem: „2 timery trwają”;
/// - kilka różnych — liczba i to, co czeka na ruch: „3 timery · 1 do
///   włączenia” (resztę mówią znaczki).
/// Stuknięcie otwiera arkusz Timery.
struct CookOverflowTab: View {
    let items: [CookDockTimer]
    let onOpen: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let captionText = caption
        Button(action: onOpen) {
            HStack(spacing: 7) {
                HStack(spacing: -5) {
                    ForEach(items.prefix(3)) { item in
                        CookTimerMark(item: item)
                    }
                }
                Text(captionText)
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)
                    .cookTicking(captionText)
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .padding(.leading, 4)
            .padding(.trailing, 11)
            .frame(height: SCCook.Height.overflowTab)
            .background(Capsule().fill(scheme == .dark ? SCCook.Palette.dockSurface(scheme) : .clear))
            .overlay(Capsule().strokeBorder(scheme == .dark ? SCCook.Palette.dockStroke(scheme) : .clear, lineWidth: 1))
            .cookDockGlass(scheme)
            .shadow(color: scheme == .dark ? SCCook.Palette.dockShadow(scheme) : .clear, radius: 10, y: 6)
            .contentShape(Capsule())
            .scTapHeight(44, drawn: SCCook.Height.overflowTab)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Otwiera arkusz Timery")
    }

    private var caption: String {
        if items.count == 1, let item = items.first {
            return "\(Self.name(item)) · \(Self.state(item))"
        }
        let count = items.count
        let timers = "\(count) \(PolishPlural.form(count, one: "timer", few: "timery", many: "timerów"))"
        let phases = Set(items.map(\.status.phase))
        if phases.count == 1, let item = items.first {
            return "\(timers) \(Self.groupState(item.status, count: count))"
        }
        // Różne stany — słowem tylko to, co czeka na ruch; resztę mówią znaczki.
        let pending = items.filter { if case .pending = $0.status { true } else { false } }.count
        if pending > 0 { return "\(timers) · \(pending) do włączenia" }
        let overdue = items.filter { if case .overdue = $0.status { true } else { false } }.count
        if overdue > 0 { return "\(timers) · \(overdue) po czasie" }
        return timers
    }

    private var accessibilityText: String {
        let list = items.map { "\($0.timer.label): \(Self.state($0))" }.joined(separator: ", ")
        return "Pozostałe timery: \(list)"
    }

    /// Do włączenia — warunek startu (D37), reszta — nazwa timera.
    private static func name(_ item: CookDockTimer) -> String {
        if case .pending = item.status { return item.timer.startLabel }
        return item.timer.label
    }

    private static func state(_ item: CookDockTimer) -> String {
        switch item.status {
        case .pending: "włącz"
        case .running: CookDockLabels.time(item.status)
        case .paused: "pauza"
        case .overdue: "po czasie"
        case .finished: "gotowe"
        }
    }

    /// Stan kilku timerów naraz, po „2 timery …”.
    private static func groupState(_ status: CookTimerStatus, count: Int) -> String {
        switch status {
        case .pending: "do włączenia"
        case .running: PolishPlural.form(count, one: "trwa", few: "trwają", many: "trwa")
        case .paused: PolishPlural.form(count, one: "wstrzymany", few: "wstrzymane", many: "wstrzymanych")
        case .overdue: "po czasie"
        case .finished: "gotowe"
        }
    }
}

/// Znaczek stanu timera w jego kolorze (plakietka nad kapsułami): trwa —
/// łuk pozostałego czasu, do włączenia — pełne koło z ▶, wstrzymany — szary
/// łuk z pauzą, po czasie — pełne koło z dzwonkiem. Obwódka w kolorze doku
/// oddziela nachodzące na siebie znaczki.
struct CookTimerMark: View {
    let item: CookDockTimer

    @Environment(\.colorScheme) private var scheme

    private var color: Color { item.accent.color }

    var body: some View {
        let side = SCCook.Size.overflowMark
        ZStack {
            Circle().fill(fill)
            CookTimerRing(
                fraction: item.status.remainingFraction,
                color: isPaused ? Color.scMuted(scheme) : color,
                lineWidth: SCCook.Stroke.overflowMark
            )
            .opacity(showsRing ? 1 : 0)
            Image(systemName: glyph ?? "play.fill")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(glyphColor)
                .offset(x: glyph == "play.fill" ? 0.5 : 0)
                .opacity(glyph == nil ? 0 : 1)
        }
        .frame(width: side, height: side)
        .background(Circle().fill(SCCook.Palette.dockSurface(scheme)).padding(-1.5))
        .accessibilityHidden(true)
    }

    private var isPaused: Bool { if case .paused = item.status { true } else { false } }

    private var showsRing: Bool {
        switch item.status {
        case .running, .paused: true
        case .pending, .overdue, .finished: false
        }
    }

    private var fill: Color {
        switch item.status {
        case .pending, .overdue: color
        case .running, .paused, .finished: .clear
        }
    }

    private var glyph: String? {
        switch item.status {
        case .pending: "play.fill"
        case .paused: "pause.fill"
        case .overdue: "bell.fill"
        case .running, .finished: nil
        }
    }

    private var glyphColor: Color {
        isPaused ? Color.scMuted(scheme) : Color.scPageBase(scheme)
    }
}

/// Liczba składników kroku nad koszykiem (runda 11: „badge nad ikonę
/// składników”). Zmiana liczby: cyfry rolują (`cookRoll`), a plakietka
/// lekko podskakuje — każde nowe składniki widać, nawet gdy liczba
/// zostaje dwucyfrowa. Pojawienie i zniknięcie robi przejście rodzica.
private struct CookIslandBadge: View {
    let count: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("\(count)")
            .font(.system(size: 10.5, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(.white)
            .cookRoll(count)
            .padding(.horizontal, 4)
            .frame(minWidth: SCCook.Size.islandBadge, minHeight: SCCook.Size.islandBadge)
            .background(Capsule().fill(SCPalette.terracotta))
            .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? 0 : count) { badge, scale in
                badge.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(1.22, duration: 0.14, spring: .snappy)
                    SpringKeyframe(1, duration: 0.4, spring: .bouncy)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Koszyk na wyspie (runda 10). Woła terakotą i KOŁYSANIEM dzwonka z tarczy
/// końca timera (`CookBellSwing`: te same kąty, ta sama oś u góry, 0,64 s
/// ruchu), co `duration.cookBasketCall` — bez powiększania i pełnej ikony
/// („zbyt intensywny i rzucający się”, druga wersja rundy 10). `callID` =
/// krok, który woła; nowy krok zaczyna kołysanie od początku, po krótkiej
/// chwili (dok i tekst kroku najpierw się przestawiają). Reduce Motion —
/// sam kolor.
private struct CookBasketGlyph: View {
    let callID: Int?

    /// Pierwsze kołysanie czeka, aż krok się przeroluje.
    private static let firstDelay: Double = 0.6

    @State private var callStart = Date()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if callID != nil, !reduceMotion {
                TimelineView(.animation) { context in
                    basket.rotationEffect(.degrees(angle(at: context.date)), anchor: CookBellSwing.anchor)
                }
            } else {
                basket
            }
        }
        .onChange(of: callID, initial: true) { _, id in
            if id != nil { callStart = Date() }
        }
    }

    private var basket: some View {
        Image(systemName: "basket")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(callID != nil ? SCPalette.terracotta : Color.scLabel(scheme))
            .animation(.easeInOut(duration: 0.3), value: callID != nil)
    }

    private func angle(at date: Date) -> Double {
        let elapsed = date.timeIntervalSince(callStart) - Self.firstDelay
        guard elapsed > 0 else { return 0 }
        let period = SCCook.Duration.basketCall
        return CookBellSwing.angle(elapsed: elapsed.truncatingRemainder(dividingBy: period))
    }
}
