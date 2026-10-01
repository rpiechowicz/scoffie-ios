import SwiftUI

/// Dok na dole ekranu kroku (D34): wyspa ‹ Składniki N › zawsze w tym samym
/// miejscu, nad nią każdy timer osobną kapsułą. Wyspa ma wymiary i miejsce
/// dolnego menu aplikacji (60 pt, 20 pt od boków, na dolnej krawędzi
/// bezpiecznego obszaru — runda 2 testów, 1.10.2026).
///
/// Ruch (runda 2: „nie powinno wszystko się wysuwać”):
/// - wyspa jest JEDNYM trwałym kontenerem; „Składniki” rozwijają ją w kartę —
///   lista wysuwa się spod wiersza wyspy jak arkusz, a wiersz zostaje na
///   miejscu (`island`);
/// - kapsuły mają stałą tożsamość (po id timera) i kolejność kroków
///   (`CookSession.dockCapsules`): kolejna wjeżdża z boku, poprzednie zwężają
///   się płynnie, włączenie timera nie zamienia ich miejscami; trzy mieszczą
///   się obok siebie;
/// - kapsuły i karta Timery wychodzą spod wyspy (`riseFromIsland`), w jednym
///   `ZStack` przyklejonym do dołu — wychodząca i wchodząca warstwa nakładają
///   się, zamiast stawać jedna nad drugą.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let capsules = session.dockCapsules(now: now)
        let total = session.dockTimers(now: now).count
        VStack(spacing: 0) {
            timersSlot(capsules: capsules, total: total)
            island
        }
        .padding(.horizontal, SCCook.Spacing.dockSide)
        .padding(.bottom, SCCook.Spacing.dockBottom)
        .animation(SCCook.Motion.dock, value: card)
        .animation(SCCook.Motion.dock, value: capsules.map(\.id))
        // Ostatni timer zrobiony — pusta karta Timery nie zostaje.
        .onChange(of: total == 0) { _, isEmpty in
            if isEmpty, card == .timers { card = nil }
        }
    }

    /// Kapsuły i karta Timery wychodzą SPOD wyspy: unoszą się i rozjaśniają.
    /// Wyspa leży nad nimi (jest dalej w `VStack`), więc dół wchodzącej
    /// warstwy chowa się pod nią — nigdy nie wystaje pod wyspę.
    private var riseFromIsland: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .offset(y: 36).combined(with: .opacity),
            removal: .offset(y: 24).combined(with: .opacity).animation(.easeOut(duration: 0.16))
        )
    }

    // MARK: - Timery

    /// Miejsce nad wyspą: kapsuły albo karta Timery (ST5 — karta w miejscu
    /// kapsuł, wyspa zostaje pod nią).
    private func timersSlot(capsules: [CookDockTimer], total: Int) -> some View {
        ZStack(alignment: .bottom) {
            if card == .timers, total > 0 {
                CookTimersCard(session: session, now: now, onTimer: onTimer)
                    .padding(.bottom, SCCook.Spacing.dockGap)
                    .transition(riseFromIsland)
            } else if !capsules.isEmpty {
                capsuleRow(capsules, total: total)
                    .padding(.bottom, SCCook.Spacing.dockGap)
                    .transition(riseFromIsland)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Kapsuły obok siebie — jedna na całą szerokość, dwie, trzy. Ta sama
    /// kapsuła przez cały czas swojego timera: przy kolejnej zwęża się
    /// w miejscu, a nowa wjeżdża z boku.
    private func capsuleRow(_ items: [CookDockTimer], total: Int) -> some View {
        let layout: CookTimerCapsule.Layout = switch items.count {
        case 1: .single
        case 2: .pair
        default: .trio
        }
        return HStack(spacing: SCCook.Spacing.capsuleGap) {
            ForEach(items) { item in
                CookTimerCapsule(item: item, layout: layout, onTimer: onTimer, onOpen: { card = .timers })
                    .transition(capsuleTransition)
            }
        }
        // Czwarty timer i dalsze (poza planem scenariusza, D38) — plakietka
        // „+N” na ostatniej kapsule, wszystko widać w karcie Timery.
        .overlay(alignment: .topTrailing) {
            if total > items.count {
                Button { card = .timers } label: {
                    Text("+\(total - items.count)")
                        .font(.system(size: 12, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(Color.scPageBase(scheme))
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(Capsule().fill(SCPalette.terracotta))
                        .scTapTarget(44, drawn: 22)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -8)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityLabel("Jeszcze \(total - items.count) w karcie Timery")
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

    /// Wyspa i karta Składniki to ten sam kontener: zaokrąglenie
    /// `radius.cookDockCard` to połowa wysokości wyspy, więc zamknięta jest
    /// kapsułą, a rozwinięcie zmienia tylko wysokość — kształt nie przeskakuje.
    /// Lista wjeżdża od dołu SPOD wiersza wyspy (wiersz ma kryjące tło i leży
    /// nad nią), a kontener rośnie razem z nią — górna krawędź listy idzie
    /// z górną krawędzią karty, jak arkusz.
    private var island: some View {
        let isOpen = card == .ingredients
        let surface = SCCook.Palette.dockSurface(scheme)
        let shape = RoundedRectangle(cornerRadius: SCCook.Radius.dockCard, style: .continuous)
        return VStack(spacing: 0) {
            if isOpen {
                CookIngredientsPanel(session: session)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
            }
            islandRow(highlighted: isOpen)
                .background(surface)
        }
        .background(shape.fill(surface))
        .clipShape(shape)
        .overlay(shape.strokeBorder(SCCook.Palette.dockStroke(scheme), lineWidth: 1))
        .shadow(color: SCCook.Palette.dockShadow(scheme), radius: 18, y: 14)
    }

    private func islandRow(highlighted: Bool) -> some View {
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
                card = card == .ingredients ? nil : .ingredients
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
                .background(Capsule().fill(highlighted ? Color.scRule(scheme) : .clear))
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

/// Co użytkownik zrobił z timerem — jedna droga z kapsuły, karty i alarmu.
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

    /// Glif tego ruchu — ten sam w kapsule i w karcie Timery.
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

/// Kapsuła timera nad wyspą.
///
/// - Pojedyncza (cała szerokość): pierścień, etykieta, czas i przycisk
///   w pigułce z makiety (pauza / ▶ Start / ▶ Wznów / ✓ Gotowe).
/// - Z pary i z trójki: PIERŚCIEŃ JEST PRZYCISKIEM tego samego ruchu, z glifem
///   w środku (runda 2: „włączyć / wyłączyć timer z pulpitu, nie wchodząc
///   w kartę”) — ten sam znak, co w karcie Timery.
///
/// Stuknięcie w resztę kapsuły otwiera kartę Timery; w „do włączenia” cała
/// kapsuła włącza timer (makieta).
struct CookTimerCapsule: View {
    enum Layout {
        case single
        case pair
        case trio
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
        HStack(spacing: spacing) {
            switch layout {
            case .single:
                bodyButton {
                    HStack(spacing: 10) {
                        leadingRing
                        texts
                    }
                }
                singleAction
            case .pair, .trio:
                ringButton
                bodyButton { texts }
            }
        }
        .padding(.leading, leadingPadding)
        .padding(.trailing, trailingPadding)
        .frame(height: SCCook.Height.timerCapsule)
        .frame(maxWidth: .infinity)
        .background(background)
        .overlay(border)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .shadow(color: SCCook.Palette.dockShadow(scheme), radius: 15, y: 12)
        .cookInvitePulse(Capsule(), isActive: isPending)
        .cookOverduePulse(Capsule(), isActive: isOverdue)
        // Koniec odliczania przychodzi z zegara (bez animacji w transakcji) —
        // kolor kapsuły przechodzi w terakotę sprężyną doku, a nie w klatce.
        .animation(SCCook.Motion.dock, value: item.status.phase)
    }

    private var spacing: CGFloat {
        switch layout {
        case .single: 10
        case .pair: 8
        case .trio: 6
        }
    }

    private var leadingPadding: CGFloat {
        switch layout {
        case .single: 12
        case .pair: 8
        case .trio: 6
        }
    }

    private var trailingPadding: CGFloat {
        switch layout {
        case .single: 6
        case .pair: 12
        case .trio: 8
        }
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
        .accessibilityHint(isPending ? "Włącza timer" : "Otwiera kartę Timery")
    }

    private var texts: some View {
        // Poza pojedynczą kapsułą bez dopisków („· pauza”, „· po czasie”) —
        // stan mówi kolor i glif w pierścieniu, a węższa kapsuła nie mieści
        // dwóch słów więcej.
        let label = layout == .single ? CookDockLabels.capsuleLabel(item) : item.timer.label
        let time = CookDockLabels.time(item.status)
        let timeStyle: SCCookTextStyle = switch layout {
        case .single: SCCook.Typography.timerTime
        case .pair: SCCook.Typography.timerTimePair
        case .trio: SCCook.Typography.timerTimeTrio
        }
        return VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .cookText(SCCook.Typography.timerLabel)
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .cookRoll(label)
            Text(time)
                .cookText(timeStyle)
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
            SCPalette.terracotta
        } else if isPaused {
            ZStack { surface; SCCook.Palette.pausedFill(scheme) }
        } else if isPending {
            ZStack { surface; SCPalette.terracotta.opacity(SCCook.Opacity.pendingFill) }
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
            Capsule().strokeBorder(SCPalette.terracotta, lineWidth: 1.5)
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
                .strokeBorder(SCPalette.terracotta.opacity(SCCook.Opacity.pendingRing), lineWidth: SCCook.Stroke.timerRing)
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
        .accessibilityLabel(item.primaryLabel)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    // MARK: Para i trójka

    /// Pierścień-przycisk: łuk pozostałego czasu z glifem ruchu w środku.
    /// Jeden widok przez wszystkie stany — glif się podmienia, kolory
    /// przenikają, nic w kapsule się nie przestawia.
    private var ringButton: some View {
        let side = layout == .trio ? SCCook.Size.timerRingTrio : SCCook.Size.timerRingPair
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
                    .font(.system(size: layout == .trio ? 10 : 11, weight: .heavy))
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
        if isPending { return SCPalette.terracotta }
        if isOverdue { return Color.scPageBase(scheme).opacity(0.16) }
        return .clear
    }

    private var glyphColor: Color {
        if isPending || isOverdue { return Color.scPageBase(scheme) }
        if isPaused { return Color.scLabel(scheme) }
        return color
    }
}
