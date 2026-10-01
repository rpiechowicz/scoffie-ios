import SwiftUI

/// Dok na dole ekranu kroku (D34): wyspa ‹ Składniki N › zawsze w tym samym
/// miejscu, nad nią każdy timer osobną kapsułą. Stuknięcie w kapsułę z pary
/// otwiera kartę Timery w miejscu kapsuł, „Składniki” rozwijają wyspę
/// w kartę — obie za zasłoną (`cook.scrim`), nie jako arkusz systemu.
struct CookDock: View {
    enum Card: Equatable {
        case timers
        case ingredients
    }

    let session: CookSession
    let now: Date
    @Binding var card: Card?
    let onBack: () -> Void
    let onNext: () -> Void
    let onTimer: (CookTimerAction) -> Void

    @Environment(\.colorScheme) private var scheme

    private var timers: [CookDockTimer] { session.dockTimers(now: now) }

    var body: some View {
        VStack(spacing: SCCook.Spacing.dockGap) {
            switch card {
            case .timers:
                CookTimersCard(session: session, now: now, onTimer: onTimer)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                island
            case .ingredients:
                capsules
                CookIngredientsCard(session: session) {
                    islandRow(highlighted: true)
                }
                .transition(.opacity)
            case nil:
                capsules
                island
            }
        }
        .padding(.horizontal, SCCook.Spacing.dockSide)
        .padding(.bottom, SCCook.Spacing.dockBottom)
        .animation(SCCook.Motion.dock, value: card)
        .animation(SCCook.Motion.dock, value: timers.map(\.id))
        // Ostatni timer zrobiony — pusta karta Timery nie zostaje.
        .onChange(of: timers.isEmpty) { _, isEmpty in
            if isEmpty, card == .timers { card = nil }
        }
    }

    // MARK: - Kapsuły

    @ViewBuilder
    private var capsules: some View {
        let visible = Array(timers.prefix(2))
        if visible.count == 1, let item = visible.first {
            CookTimerCapsule(item: item, layout: .single, onTimer: onTimer, onOpen: { card = .timers })
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if visible.count == 2 {
            HStack(spacing: SCCook.Spacing.capsuleGap) {
                ForEach(visible) { item in
                    CookTimerCapsule(item: item, layout: .pair, onTimer: onTimer, onOpen: { card = .timers })
                }
            }
            // Trzeci timer poza planem scenariusza (D38) — plakietka „+1”
            // na drugiej kapsule, wszystko widać w karcie Timery.
            .overlay(alignment: .topTrailing) {
                if timers.count > 2 {
                    Text("+\(timers.count - 2)")
                        .font(.system(size: 12, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(Color.scPageBase(scheme))
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(Capsule().fill(SCPalette.terracotta))
                        .offset(x: 4, y: -8)
                        .accessibilityLabel("Jeszcze \(timers.count - 2) w karcie Timery")
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Wyspa

    private var island: some View {
        islandRow(highlighted: false)
            .background(Capsule().fill(Color.scCanvas(scheme)))
            .overlay(Capsule().strokeBorder(SCCook.Palette.dockStroke(scheme), lineWidth: 1))
            .shadow(color: SCCook.Palette.dockShadow(scheme), radius: 18, y: 14)
    }

    private func islandRow(highlighted: Bool) -> some View {
        let count = session.currentStep.map { session.package.lines(for: $0, portions: session.portions).count } ?? 0
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
                card = card == .ingredients ? nil : .ingredients
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "basket")
                        .font(.system(size: 19, weight: .medium))
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
                .background(Capsule().fill(highlighted ? Color.scRule(scheme) : .clear))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(count > 0 ? "Składniki, \(count)" : "Składniki")

            // Jeden krążek: w ostatnim kroku strzałka PRZECHODZI w ptaszek
            // na szałwii (glif się podmienia, kolory przenikają).
            let isLast = session.isLastStep
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
                .font(.system(size: 18, weight: .bold))
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

/// Co użytkownik zrobił z timerem — jedna droga z kapsuły, karty i alarmu.
enum CookTimerAction {
    case start(String)
    case pause(String)
    case resume(String)
    case finish(String)
}

/// Kapsuła timera nad wyspą. Pojedyncza ma JEDEN przycisk akcji (pauza /
/// ▶ Start / ▶ Wznów / ✓ Gotowe), w parze cała kapsuła otwiera kartę Timery.
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

    private var color: Color { isPending ? SCPalette.terracotta : item.accent.color }

    var body: some View {
        Group {
            switch layout {
            case .single:
                content
            case .pair:
                Button(action: pairAction) { content }
                    .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: layout == .pair ? .ignore : .contain)
        .accessibilityLabel(CookDockLabels.accessibility(item))
    }

    private func pairAction() {
        // W parze „do włączenia” to wciąż start — makieta: cała kapsuła = Start.
        if isPending {
            onTimer(.start(item.id))
        } else {
            onOpen()
        }
    }

    private var content: some View {
        HStack(spacing: layout == .single ? 10 : 9) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                let label = CookDockLabels.capsuleLabel(item)
                let time = CookDockLabels.time(item.status)
                // Start / po czasie / pauza zmieniają etykietę — słowa rolują.
                Text(label)
                    .cookText(SCCook.Typography.timerLabel)
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .cookRoll(label)
                Text(time)
                    .cookText(layout == .single ? SCCook.Typography.timerTime : SCCook.Typography.timerTimePair)
                    .monospacedDigit()
                    .foregroundStyle(timeColor)
                    .lineLimit(1)
                    .cookTicking(time, countsDown: !isOverdue)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            if layout == .single {
                action
            }
        }
        .padding(.leading, layout == .single ? 12 : 10)
        .padding(.trailing, layout == .single ? 6 : 12)
        .frame(height: SCCook.Height.timerCapsule)
        .frame(maxWidth: .infinity)
        .background(background)
        .overlay(border)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .shadow(color: SCCook.Palette.dockShadow(scheme), radius: 15, y: 12)
        .cookInvitePulse(Capsule(), isActive: isPending)
        .cookOverduePulse(Capsule(), isActive: isOverdue)
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
        let canvas = Color.scCanvas(scheme)
        if isOverdue {
            SCPalette.terracotta
        } else if isPaused {
            ZStack { canvas; SCCook.Palette.pausedFill(scheme) }
        } else if isPending {
            ZStack { canvas; SCPalette.terracotta.opacity(SCCook.Opacity.pendingFill) }
        } else {
            ZStack { canvas; color.opacity(SCCook.Opacity.timerFill) }
        }
    }

    @ViewBuilder
    private var border: some View {
        if isOverdue {
            EmptyView()
        } else if isPaused {
            Capsule().strokeBorder(Color.scRule(scheme), lineWidth: 1)
        } else if isPending {
            Capsule().strokeBorder(SCPalette.terracotta, lineWidth: 1.5)
        } else {
            Capsule().strokeBorder(color.opacity(SCCook.Opacity.timerStroke), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var leading: some View {
        let side = layout == .single ? SCCook.Size.timerRing : SCCook.Size.timerRingPair
        let stroke = layout == .single ? SCCook.Stroke.timerRing : 3.2
        if isOverdue {
            Image(systemName: "bell")
                .font(.system(size: layout == .single ? 19 : 17, weight: .semibold))
                .foregroundStyle(Color.scPageBase(scheme))
                .frame(width: side, height: side)
        } else if isPaused {
            Image(systemName: "pause.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.scMuted(scheme))
                .frame(width: side, height: side)
                .overlay(Circle().strokeBorder(Color.scMuted(scheme), lineWidth: 2))
        } else if isPending {
            if layout == .single {
                Circle()
                    .strokeBorder(SCPalette.terracotta.opacity(SCCook.Opacity.pendingRing), lineWidth: stroke)
                    .frame(width: side, height: side)
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.scPageBase(scheme))
                    .offset(x: 1)
                    .frame(width: side, height: side)
                    .background(Circle().fill(SCPalette.terracotta))
            }
        } else {
            CookTimerRing(fraction: item.status.remainingFraction, color: color, lineWidth: stroke)
                .frame(width: side, height: side)
        }
    }

    @ViewBuilder
    private var action: some View {
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
            .accessibilityLabel("Pauza: \(item.timer.label)")
        case .pending:
            pillButton(title: "Start", icon: "play.fill", fill: SCPalette.terracotta, ink: Color.scPageBase(scheme)) {
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
    }
}
