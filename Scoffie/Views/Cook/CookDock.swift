import SwiftUI

/// Dok na dole ekranu kroku (D34): wyspa ‹ Składniki N › zawsze w tym samym
/// miejscu, nad nią każdy timer osobną kapsułą. Wyspa ma wymiary i miejsce
/// dolnego menu aplikacji (60 pt, 20 pt od boków, na dolnej krawędzi
/// bezpiecznego obszaru — runda 2 testów, 1.10.2026).
///
/// Najwyżej dwie kapsuły — dwa najdawniej włączone timery, a wolne miejsce
/// bierze timer do włączenia (`CookSession.dockCapsules`, runda 3); stoją
/// w kolejności kroków i każdy ma swój kolor (`CookTimerAccent`). Kapsuły
/// mają stałą tożsamość (po id timera): druga wjeżdża z boku, pierwsza
/// zwęża się w miejscu, a cały rząd wychodzi spod wyspy.
///
/// Timery i Składniki otwierają się jako arkusze systemu (`CookSheet`;
/// runda 3: „trochę się buguje animacja”, „Składniki do połowy ekranu,
/// przewijanie rozwija na cały”) — dok się wtedy nie przestawia.
struct CookDock: View {
    let session: CookSession
    let now: Date
    let onBack: () -> Void
    let onNext: () -> Void
    let onTimer: (CookTimerAction) -> Void
    let onOpen: (CookSheet) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let capsules = session.dockCapsules(now: now)
        let total = session.dockTimers(now: now).count
        VStack(spacing: SCCook.Spacing.dockGap) {
            if !capsules.isEmpty {
                capsuleRow(capsules, total: total)
                    .transition(riseFromIsland)
            }
            island
        }
        .padding(.horizontal, SCCook.Spacing.dockSide)
        .padding(.bottom, SCCook.Spacing.dockBottom)
        .animation(SCCook.Motion.dock, value: capsules.map(\.id))
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

    private func capsuleRow(_ items: [CookDockTimer], total: Int) -> some View {
        let layout: CookTimerCapsule.Layout = items.count > 1 ? .pair : .single
        return HStack(spacing: SCCook.Spacing.capsuleGap) {
            ForEach(items) { item in
                CookTimerCapsule(item: item, layout: layout, onTimer: onTimer, onOpen: { onOpen(.timers) })
                    .transition(capsuleTransition)
            }
        }
        // Trzeci i dalsze (poza planem scenariusza, D38) — plakietka „+N”
        // na drugiej kapsule, wszystkie są w arkuszu Timery.
        .overlay(alignment: .topTrailing) {
            if total > items.count {
                Button { onOpen(.timers) } label: {
                    Text("+\(total - items.count)")
                        .font(.system(size: 12, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(Color.scPageBase(scheme))
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.scLabel(scheme)))
                        // Sama wysokość dotyku: szersza niż 22 pt plakietka
                        // nie wchodzi wtedy pod róg kapsuły obok.
                        .scTapHeight(44, drawn: 22)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -8)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityLabel("Jeszcze \(total - items.count) w arkuszu Timery")
            }
        }
    }

    private var capsuleTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .scale(scale: 0.85).combined(with: .opacity)
        )
    }

    // MARK: - Wyspa

    private var island: some View {
        let count = session.currentStep.map { session.package.lines(for: $0, portions: session.portions).count } ?? 0
        // Jeden krążek „Dalej”: w ostatnim kroku strzałka PRZECHODZI w ptaszek
        // na szałwii (glif się podmienia, kolory przenikają).
        let isLast = session.isLastStep
        return HStack(spacing: SCCook.Spacing.islandGap) {
            islandCircle(
                systemName: "chevron.left",
                fill: Color.scTileStroke(scheme),
                stroke: Color.scTileBg(scheme),
                tint: Color.scLabel(scheme),
                label: "Poprzedni krok",
                action: onBack
            )
            .disabled(session.isFirstStep)
            .opacity(session.isFirstStep ? 0.4 : 1)

            Button {
                onOpen(.ingredients)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "basket")
                        .font(.system(size: 18, weight: .medium))
                    Text("Składniki")
                        .font(.system(size: 16, weight: .bold))
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 12, weight: .heavy))
                            .monospacedDigit()
                            .cookRoll(count)
                            .padding(.horizontal, 6)
                            .frame(minWidth: SCCook.Size.islandBadge, minHeight: SCCook.Size.islandBadge)
                            .background(Capsule().fill(SCCook.Palette.badge(scheme)))
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
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
                fill: isLast ? SCPalette.sage.opacity(SCCook.Opacity.finishFill) : SCCook.Palette.ringTodo(scheme),
                stroke: isLast ? SCPalette.sage.opacity(SCCook.Opacity.finishStroke) : SCCook.Palette.badge(scheme),
                tint: isLast ? SCPalette.sage : Color.scLabel(scheme),
                label: isLast ? "Zakończ gotowanie" : "Następny krok",
                action: onNext
            )
        }
        .padding(SCCook.Spacing.islandPadding)
        .frame(height: SCCook.Height.island)
        .background(Capsule().fill(SCCook.Palette.dockSurface(scheme)))
        .overlay(Capsule().strokeBorder(SCCook.Palette.dockStroke(scheme), lineWidth: 1))
        .shadow(color: SCCook.Palette.dockShadow(scheme), radius: 18, y: 14)
        .sensoryFeedback(.selection, trigger: session.stepIndex)
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

/// Co użytkownik zrobił z timerem — jedna droga z kapsuły, arkusza i alarmu.
enum CookTimerAction {
    case start(String)
    case pause(String)
    case resume(String)
    case finish(String)
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

/// Kapsuła timera nad wyspą — w kolorze SWOJEGO timera (runda 3: „każdy
/// inny timer inny kolor”), we wszystkich stanach.
///
/// - Pojedyncza (cała szerokość): pierścień, etykieta, czas i przycisk
///   w pigułce z makiety (pauza / ▶ Start / ▶ Wznów / ✓ Gotowe).
/// - Z pary: PIERŚCIEŃ JEST PRZYCISKIEM tego samego ruchu, z glifem w środku
///   (runda 2: „włączyć / wyłączyć timer z pulpitu, nie wchodząc w kartę”).
///
/// Stuknięcie w resztę kapsuły otwiera arkusz Timery; w „do włączenia” cała
/// kapsuła włącza timer (makieta).
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

    private var isOverdue: Bool { if case .overdue = item.status { true } else { false } }
    private var isPending: Bool { if case .pending = item.status { true } else { false } }
    private var isPaused: Bool { if case .paused = item.status { true } else { false } }

    private var color: Color { item.accent.color }

    var body: some View {
        HStack(spacing: layout == .single ? 10 : 8) {
            switch layout {
            case .single:
                bodyButton {
                    HStack(spacing: 10) {
                        leadingRing
                        texts
                    }
                }
                singleAction
            case .pair:
                ringButton
                bodyButton { texts }
            }
        }
        .padding(.leading, layout == .single ? 12 : 8)
        .padding(.trailing, layout == .single ? 6 : 12)
        .frame(height: SCCook.Height.timerCapsule)
        .frame(maxWidth: .infinity)
        .background(background)
        .overlay(border)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .shadow(color: SCCook.Palette.dockShadow(scheme), radius: 15, y: 12)
        .cookInvitePulse(Capsule(), color: color, isActive: isPending)
        .cookOverduePulse(Capsule(), color: color, isActive: isOverdue)
        // Koniec odliczania przychodzi z zegara (bez animacji w transakcji) —
        // kolor kapsuły przechodzi sprężyną doku, a nie w klatce.
        .animation(SCCook.Motion.dock, value: item.status.phase)
    }

    private func bodyAction() {
        if isPending {
            onTimer(.start(item.id))
        } else {
            onOpen()
        }
    }

    private func bodyButton<Label: View>(@ViewBuilder _ label: () -> Label) -> some View {
        Button(action: bodyAction) {
            label()
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
        let label = layout == .single || isPending ? CookDockLabels.capsuleLabel(item) : item.timer.label
        let time = CookDockLabels.time(item.status)
        return VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .cookText(SCCook.Typography.timerLabel)
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .cookRoll(label)
            Text(time)
                .cookText(layout == .single ? SCCook.Typography.timerTime : SCCook.Typography.timerTimePair)
                .monospacedDigit()
                .foregroundStyle(timeColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .cookTicking(time, countsDown: !isOverdue)
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

    @ViewBuilder
    private var background: some View {
        let surface = SCCook.Palette.dockSurface(scheme)
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

    // MARK: Pojedyncza

    /// Pierścień pojedynczej kapsuły — sam znak, ruch jest w pigułce obok.
    @ViewBuilder
    private var leadingRing: some View {
        let side = SCCook.Size.timerRing
        if isOverdue {
            Image(systemName: "bell")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.scPageBase(scheme))
                .frame(width: side, height: side)
        } else if isPaused {
            Image(systemName: "pause.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.scMuted(scheme))
                .frame(width: side, height: side)
                .overlay(Circle().strokeBorder(Color.scMuted(scheme), lineWidth: 2))
        } else if isPending {
            Circle()
                .strokeBorder(color.opacity(SCCook.Opacity.pendingRing), lineWidth: SCCook.Stroke.timerRing)
                .frame(width: side, height: side)
        } else {
            CookTimerRing(fraction: item.status.remainingFraction, color: color, lineWidth: SCCook.Stroke.timerRing)
                .frame(width: side, height: side)
        }
    }

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

    // MARK: Para

    /// Pierścień-przycisk: łuk pozostałego czasu z glifem ruchu w środku.
    /// Jeden widok przez wszystkie stany — glif się podmienia, kolory
    /// przenikają, nic w kapsule się nie przestawia.
    private var ringButton: some View {
        let side = SCCook.Size.timerRingPair
        let showsRing = item.status.phase == 1 || isPaused
        return Button {
            if let action = item.primaryAction { onTimer(action) }
        } label: {
            ZStack {
                Circle().fill(ringFill)
                CookTimerRing(
                    fraction: item.status.remainingFraction,
                    color: isPaused ? Color.scMuted(scheme) : color,
                    lineWidth: SCCook.Stroke.timerRingSmall
                )
                .opacity(showsRing ? 1 : 0)
                Image(systemName: item.primaryIcon)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(glyphColor)
                    .offset(x: item.primaryIcon == "play.fill" ? 1 : 0)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: side, height: side)
            .scTapTarget(44, drawn: side)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.primaryLabel)
    }

    private var ringFill: Color {
        if isPending { return color }
        if isOverdue { return Color.scPageBase(scheme).opacity(0.16) }
        return .clear
    }

    private var glyphColor: Color {
        if isPending || isOverdue { return Color.scPageBase(scheme) }
        if isPaused { return Color.scLabel(scheme) }
        return color
    }
}
