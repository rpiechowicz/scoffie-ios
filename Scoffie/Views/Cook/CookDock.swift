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
/// Najwyżej dwie pełne kapsuły (`CookSession.dockCapsules`) — pojedyncza
/// albo para, każdy timer w swoim kolorze — a KAŻDY kolejny timer ma własną
/// plakietkę w rzędzie nad nimi (`CookTimerBadge`: pierścień w kolorze
/// timera i „12:04 · Ziemniaki”, „do włączenia” z warunkiem startu i ▶).
/// Rafał 4.10.2026, dwie rundy: najpierw „przy 3 timerach nie widzę, jak
/// działa trzeci” (dawna plakietka „+N” streszczała je jednym zdaniem), potem
/// „jak wchodzi 3 timer, animacja 2. się buguje, 4 się nie mieści, 3 nie da
/// się włączyć” (zwarte kapsuły po równo przebudowywały wszystkie naraz
/// i zwężały czas) — „dodaj badge z czasem i info, aby się mieściło”.
/// Kapsuły mają stałą tożsamość (po id timera), więc druga wjeżdża z boku,
/// a pierwsza zwęża się w miejscu; trzeci timer nie rusza żadnej z nich.
///
/// Stuknięcie w timer (kapsuła albo plakietka) ma JEDNĄ regułę
/// (`CookDockTimer.dockTapAction`): „do włączenia” włącza, reszta otwiera
/// arkusz Timery — tylko tam są pauza, „+1 min”, „Pomiń” i „Gotowe”.
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

    var body: some View {
        let capsules = session.dockCapsules(now: now)
        let overflow = session.dockOverflow(now: now)
        VStack(spacing: SCCook.Spacing.overflowGap) {
            // Rząd plakietek nad kapsułami — w miejscu dawnej „+N”, więc dok
            // ma dalej STAŁĄ wysokość (`spacing.cookDockReserve`).
            badgeRow(overflow)
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

    /// Plakietki timerów spoza kapsuł — w STAŁEJ kolejności kroków, nie
    /// pilności (Rafał 4.10.2026: „timery 3 i 4 nie mogą się zamieniać
    /// miejscami”; `dockOverflow` układa po czasie do końca, więc przestawiał
    /// je start, pauza i każde odliczanie). Przy kilku rząd przewija się w bok.
    private func badgeRow(_ items: [CookDockTimer]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(items.sorted { $0.stepIndex < $1.stepIndex }) { item in
                    CookTimerBadge(item: item, onTimer: onTimer, onOpen: { onOpen(.timers) })
                        .transition(badgeTransition)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private var badgeTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .scale(scale: 0.85, anchor: .bottom).combined(with: .opacity)
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
                            CookIslandBadge(count: count)
                                .alignmentGuide(.trailing) { $0[HorizontalAlignment.center] - SCCook.Spacing.islandBadgeInset }
                                .alignmentGuide(.top) { $0[VerticalAlignment.center] + SCCook.Spacing.islandBadgeInset }
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

/// Co użytkownik zrobił z timerem — jedna droga z kapsuły, plakietki
/// i arkusza Timery.
enum CookTimerAction {
    case start(String)
    case pause(String)
    case resume(String)
    case finish(String)
    /// „Pomiń” timer, który czeka na włączenie (runda 4: pominięty przy
    /// „Dalej” już sam nie znika).
    case skip(String)
    /// „+1 min” w arkuszu Timery (timer po czasie, wyciszony) — sekundy.
    case extend(String, Int)
}

extension CookDockTimer {
    /// JEDNA reguła stuknięcia w timer w DOKU — kapsuła pojedyncza, para
    /// i plakietka: „do włączenia” = Start, każdy inny stan (trwa, pauza, po
    /// czasie, wyciszony) = arkusz Timery (`nil`). Mokrą ręką przy kuchence
    /// łatwo trafić przypadkiem, więc pauza, wznowienie, „+1 min”, „Pomiń”
    /// i „Gotowe” są wyłącznie w arkuszu (6.10.2026; wcześniej pierścień
    /// kapsuły w parze pauzował, a pojedyncza miała przycisk pauzy obok).
    var dockTapAction: CookTimerAction? {
        if case .pending = status { return .start(id) }
        return nil
    }

    /// Ruch pierścienia-przycisku w wierszu arkusza Timery: włącz / pauza /
    /// wznów / gotowe. `nil` = timer skończony.
    var primaryAction: CookTimerAction? {
        switch status {
        case .pending: .start(id)
        case .running: .pause(id)
        case .paused: .resume(id)
        case .overdue: .finish(id)
        case .finished: nil
        }
    }

    /// Glif tego ruchu w arkuszu Timery.
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
/// - Pojedyncza (cała szerokość): pierścień, etykieta i czas, a przy „do
///   włączenia” pigułka „▶ Start” z makiety.
/// - Z pary: większy pierścień z glifem stanu w środku.
///
/// Oba rozmiary to JEDEN układ: pierścień, teksty i pigułka zostają tymi
/// samymi widokami, więc przy wjeździe drugiego timera kapsuła zwęża się,
/// pierścień rośnie i dostaje glif, a pigułka gaśnie — w jednym ruchu
/// (runda 4: „ten 1 powinien animować się, zmieniając swój design”). Dawniej
/// `switch` na układzie podmieniał całą treść i kapsuła przeskakiwała.
///
/// Cała kapsuła to JEDEN przycisk z jedną regułą doku
/// (`CookDockTimer.dockTapAction`): „do włączenia” — włącza, każdy inny
/// stan — otwiera arkusz Timery. Bez menu przytrzymania i bez osobnych
/// przycisków w środku (6.10.2026, „mokre ręce”): pierścień w parze pauzował
/// timer, a pojedyncza miała obok przycisk pauzy — łatwo o przypadek. Glif
/// w pierścieniu mówi więc STAN (dzwonek po czasie, pauza), a ▶ zostaje tylko
/// tam, gdzie stuknięcie naprawdę włącza.
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
        Button(action: tap) {
            HStack(spacing: isSingle ? 10 : 8) {
                ring
                texts
                if isSingle, isPending {
                    startPill
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
        }
        .buttonStyle(PlanPressStyle(scale: 0.97))
        .accessibilityLabel(CookDockLabels.accessibility(item))
        .accessibilityHint(isPending ? "Włącza timer" : "Otwiera arkusz Timery")
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

    private func tap() {
        if let action = item.dockTapAction {
            onTimer(action)
        } else {
            onOpen()
        }
    }

    // MARK: Pierścień

    /// Pierścień — ten sam widok w obu rozmiarach (w parze większy i z glifem).
    /// Nie jest osobnym przyciskiem: stuknięcie w niego to stuknięcie
    /// w kapsułę.
    private var ring: some View {
        let side = isSingle ? SCCook.Size.timerRing : SCCook.Size.timerRingPair
        return ZStack {
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
        .accessibilityHidden(true)
    }

    /// Glif w pierścieniu = STAN, nie ruch: po czasie — dzwonek, wstrzymany —
    /// pauza (przygaszona), trwa — sam łuk. „Do włączenia” w parze — ▶, bo
    /// stuknięcie w kapsułę włącza; w pojedynczej ▶ stoi w pigułce „Start”.
    private var glyph: String? {
        switch item.status {
        case .overdue: return "bell.fill"
        case .paused: return "pause.fill"
        case .pending: return isSingle ? nil : "play.fill"
        case .running, .finished: return nil
        }
    }

    private var ringFill: Color {
        if isOverdue { return Color.scPageBase(scheme).opacity(0.16) }
        if isPending, !isSingle { return color }
        return .clear
    }

    private var glyphColor: Color {
        if isOverdue || isPending { return Color.scPageBase(scheme) }
        if isPaused { return Color.scMuted(scheme) }
        return color
    }

    // MARK: Teksty

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

    // MARK: Pojedyncza — „▶ Start”

    /// Pigułka „▶ Start” z makiety (pojedyncza, do włączenia). Sam rysunek —
    /// stuka się w całą kapsułę, która robi to samo.
    private var startPill: some View {
        HStack(spacing: 7) {
            Image(systemName: "play.fill")
                .font(.system(size: 12, weight: .heavy))
            Text("Start")
                .font(.system(size: 15, weight: .heavy))
        }
        .foregroundStyle(Color.scPageBase(scheme))
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(height: SCCook.Height.timerAction)
        .background(Capsule().fill(color))
    }
}

// MARK: - Plakietka timera

/// Plakietka timera spoza dwóch kapsuł — w rzędzie nad nimi. Pierścień
/// w kolorze timera (odliczanie ubywa jak w kapsule) i jedno krótkie zdanie:
/// trwa / pauza — „12:04 · Ziemniaki”, po czasie — „+1:20 · Ziemniaki” na
/// pełnym kolorze, do włączenia — ▶ i warunek startu („Gdy woda zawrze”, D37),
/// więc stuknięcie od razu włącza odliczanie. W pozostałych stanach
/// stuknięcie otwiera arkusz Timery — ta sama reguła co kapsuły
/// (`CookDockTimer.dockTapAction`).
struct CookTimerBadge: View {
    let item: CookDockTimer
    let onTimer: (CookTimerAction) -> Void
    let onOpen: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var color: Color { item.accent.color }
    private var isOverdue: Bool { if case .overdue = item.status { true } else { false } }
    private var isPending: Bool { if case .pending = item.status { true } else { false } }
    private var isPaused: Bool { if case .paused = item.status { true } else { false } }

    private var text: String {
        if isPending { return item.timer.startLabel }
        return "\(CookDockLabels.time(item.status)) · \(item.timer.label)"
    }

    var body: some View {
        Button {
            if let action = item.dockTapAction { onTimer(action) } else { onOpen() }
        } label: {
            HStack(spacing: 6) {
                mark
                Text(text)
                    .cookText(SCCook.Typography.timerLabel)
                    .monospacedDigit()
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .contentTransition(.numericText(countsDown: !isOverdue))
            }
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .frame(height: SCCook.Height.overflowTab)
            .background {
                if isOverdue {
                    Capsule().fill(color)
                } else if scheme == .dark {
                    Capsule().fill(SCCook.Palette.dockSurface(scheme))
                }
            }
            .cookDockGlass(scheme)
            .contentShape(Capsule())
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .accessibilityLabel(CookDockLabels.accessibility(item))
        .accessibilityHint(isPending ? "Włącza timer" : "Otwiera arkusz Timery")
    }

    @ViewBuilder
    private var mark: some View {
        let side = SCCook.Size.overflowMark
        ZStack {
            if isPending {
                Circle().fill(color)
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color.scPageBase(scheme))
                    .offset(x: 0.5)
            } else if isOverdue {
                Image(systemName: "bell.fill")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.scPageBase(scheme))
            } else {
                CookTimerRing(
                    fraction: item.status.remainingFraction,
                    color: isPaused ? Color.scMuted(scheme) : color,
                    lineWidth: SCCook.Stroke.overflowMark
                )
            }
        }
        .frame(width: side, height: side)
    }

    private var textColor: Color {
        if isOverdue { return Color.scPageBase(scheme) }
        if isPaused { return Color.scMuted(scheme) }
        return Color.scLabel(scheme)
    }
}

/// Liczba składników kroku nad koszykiem (runda 11: „badge nad ikonę
/// składników”). Widok STOI zawsze (runda 12: „pojawianie / znikanie się
/// buguje”) — wstawiany i zdejmowany w pustym kontenerze zmieniał wraz ze
/// skalą także położenie, a przy pojawieniu odpalał jeszcze podskok zmiany.
/// Teraz pojawienie i zniknięcie = skala 0,2 ↔ 1 i krycie w miejscu
/// (sprężyna), znikając trzyma ostatnią liczbę, a podskok 1,22 i rolowanie
/// cyfr są tylko przy zmianie liczby między krokami ze składnikami.
private struct CookIslandBadge: View {
    let count: Int

    /// Ostatnia liczba > 0 — zostaje na plakietce w trakcie znikania.
    @State private var shown: Int
    @State private var bump = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(count: Int) {
        self.count = count
        _shown = State(initialValue: max(count, 1))
    }

    var body: some View {
        let visible = count > 0
        Text("\(shown)")
            .font(.system(size: 10.5, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(.white)
            .cookRoll(shown)
            .padding(.horizontal, 4)
            .frame(minWidth: SCCook.Size.islandBadge, minHeight: SCCook.Size.islandBadge)
            .background(Capsule().fill(SCPalette.terracotta))
            .keyframeAnimator(initialValue: 1.0, trigger: bump) { badge, scale in
                badge.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(1.22, duration: 0.14, spring: .snappy)
                    SpringKeyframe(1, duration: 0.4, spring: .bouncy)
                }
            }
            .scaleEffect(visible || reduceMotion ? 1 : 0.2)
            .opacity(visible ? 1 : 0)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.34, dampingFraction: 0.62), value: visible)
            .onChange(of: count) { old, new in
                guard new > 0 else { return }
                if old > 0 {
                    if old != new, !reduceMotion { bump += 1 }
                    shown = new
                } else {
                    // Pojawienie: liczba podmienia się bez rolowania — rośnie
                    // już z właściwą.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { shown = new }
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
