import AudioToolbox
import SwiftUI

/// Koniec timera w aplikacji (ST4, D35): pełny ekran bez doku — tarcza
/// z czasem po terminie liczonym w górę, tytuł i treść alertu ze scenariusza,
/// inne trwające timery, „Jeszcze chwilę?” +1 / +2 / +5 min i „Gotowe —
/// dalej”. „Wycisz” zostawia timer po czasie (kapsuła pulsuje mocno), dopóki
/// nie padnie „Gotowe”.
///
/// Tarcza, aureole, dzwonek i „Gotowe — dalej” są w kolorze TEGO timera
/// (runda 3: „każdy inny timer inny kolor”) — ten sam kolor co jego kapsuła.
struct CookAlarmView: View {
    let session: CookSession
    let item: CookDockTimer
    let now: Date
    let onExtend: (Int) -> Void
    let onSilence: () -> Void
    let onDone: () -> Void

    @State private var hasAppeared = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color { item.accent.color }

    private var over: TimeInterval {
        if case let .overdue(over, _, _) = item.status { return over }
        return 0
    }

    private var others: [CookDockTimer] {
        session.timerLineup(now: now).filter { other in
            guard other.id != item.id else { return false }
            if case .running = other.status { return true }
            return false
        }
    }

    var body: some View {
        ZStack {
            // Tło wchodzi szybko (dok TimelineView nie niesie animacji, więc
            // przenikanie idzie ze stanu), tarcza i reszta — kaskadą za nim.
            ZStack {
                Color.scPageBase(scheme).ignoresSafeArea()
                CookBackdropPhoto(url: session.imageURL, opacity: SCCook.Opacity.alarmPhoto)
                SCCook.Palette.alarmVeil(scheme).ignoresSafeArea()
            }
            .opacity(hasAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.25), value: hasAppeared)

            VStack(spacing: 0) {
                topBar
                    .cookChrome(hasAppeared)
                dial
                    .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.86)
                    .opacity(hasAppeared ? 1 : 0)
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.72), value: hasAppeared)
                    .padding(.top, 34)
                texts
                    .padding(.top, 26)
                    .cookReveal(hasAppeared, order: 1)
                if !others.isEmpty {
                    VStack(spacing: 8) {
                        // Same pigułki — że lecą dalej, widać po tykającym
                        // czasie (runda 2: „bez sensu ten tekst”).
                        ForEach(others) { other in
                            CookTimerPill(item: other)
                        }
                    }
                    .padding(.top, 16)
                    .cookReveal(hasAppeared, order: 2)
                }
                Spacer(minLength: 16)
                panel
                    .cookReveal(hasAppeared, order: 3)
            }
            .padding(.horizontal, SCCook.Spacing.page)
            .padding(.top, 11)
            .padding(.bottom, 8)
        }
        .sensoryFeedback(.warning, trigger: Int(over) / 4)
        .task(id: item.id) { await ring() }
        .task {
            // Dźwięk i haptyka ruszają od razu, obraz — po klatce oddechu
            // (w klatce wstawienia animacja wejścia nie grała).
            guard !hasAppeared else { return }
            await CookEntrance.breathe()
            hasAppeared = true
        }
        .accessibilityAction(named: "Gotowe — dalej", onDone)
    }

    /// Dźwięk alarmu co 2 s, dopóki nie padnie „Wycisz” albo „Gotowe” —
    /// widok znika z ekranu, a zadanie razem z nim.
    private func ring() async {
        while !Task.isCancelled {
            if case let .overdue(_, _, silenced) = item.status, silenced { return }
            AudioServicesPlayAlertSound(SystemSoundID(1005))
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            CookStepRing(count: session.stepCount, current: session.stepIndex)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onSilence) {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.slash")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Wycisz")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(Color.scLabel(scheme))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Capsule().fill(Color.scCanvas(scheme).opacity(0.78)))
                .overlay(Capsule().strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// Tarcza jak stoper (runda 4: „teksty wychodzą poza zegar — doszlifuj
    /// go”): po obwodzie podziałka sekund, po niej krąży kropka wskazówki ze
    /// smugą — raz na minutę po czasie, bez powrotu na start (`CookAlarmBezel`).
    /// W krążku zostają tylko trzy krótkie wiersze, każdy w szerokości, która
    /// mieści się w kole: nazwa timera z dzwonkiem, licznik i „po czasie”.
    /// Dłuższe maleją, zamiast wychodzić poza tarczę; na czas nastawienia
    /// („było 10–12 min”) jest miejsce w panelu „Jeszcze chwilę?”.
    private var dial: some View {
        let minutes = Int(over) / 60
        let counter = CookClock.overdueText(over)
        return ZStack {
            CookAlarmHalos(accent: item.accent)
            CookAlarmBezel(color: color, over: over)
                .frame(width: SCCook.Size.alarmRing, height: SCCook.Size.alarmRing)
            Circle()
                .fill(Color.scPageBase(scheme))
                .overlay(Circle().strokeBorder(color, lineWidth: SCCook.Stroke.alarmDisc))
                .frame(width: SCCook.Size.alarmDisc, height: SCCook.Size.alarmDisc)
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    CookBell(isRinging: !reduceMotion)
                    Text(item.timer.label.uppercased(with: Locale(identifier: "pl_PL")))
                        .cookText(SCCook.Typography.stage)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(color)
                .frame(maxWidth: SCCook.Size.alarmTextWidth)
                Text(counter)
                    .cookText(SCCook.Typography.alarmCounter)
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: SCCook.Size.alarmCounterWidth)
                    .cookTicking(counter, countsDown: false)
                    .padding(.top, 2)
                Text("po czasie")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
                    .frame(maxWidth: SCCook.Size.alarmTextWidth)
            }
        }
        .frame(width: SCCook.Size.alarmDial, height: SCCook.Size.alarmDial)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.timer.label): czas minął \(minutes > 0 ? "\(minutes) min temu" : "przed chwilą")")
    }

    private var texts: some View {
        VStack(spacing: 10) {
            Text(item.timer.alert.title)
                .cookText(SCCook.Typography.alarmTitle)
                .foregroundStyle(Color.scLabel(scheme))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(item.timer.alert.body)
                .font(.system(size: 17))
                .lineSpacing(4)
                .foregroundStyle(SCCook.Palette.alarmBody(scheme))
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: SCCook.Radius.alarmPanel, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            // Na ile był nastawiony — tu, przy „+min”, bo od tego zależy,
            // ile dołożyć (w tarczy się nie mieścił).
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Jeszcze chwilę?")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.scMuted(scheme))
                Spacer(minLength: 8)
                Text("było \(CookClock.duration(item.timer))")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(SCCook.Palette.caption(scheme))
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            HStack(spacing: 8) {
                ForEach([1, 2, 5], id: \.self) { minutes in
                    Button { onExtend(minutes * 60) } label: {
                        Text("+\(minutes) min")
                            .font(.system(size: 16, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.scLabel(scheme))
                            .frame(maxWidth: .infinity)
                            .frame(height: SCCook.Height.alarmExtend)
                            .background(Capsule().fill(Color.scChipBg(scheme)))
                            .overlay(Capsule().strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Button(action: onDone) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                    Text("Gotowe — dalej")
                        .cookText(SCCook.Typography.buttonQuiet)
                }
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(height: SCCook.Height.alarmDone)
                .scSoftCapsule(color)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(shape.fill(SCCook.Palette.dockSurface(scheme)))
        .overlay(shape.strokeBorder(SCCook.Palette.dockStroke(scheme), lineWidth: 1))
    }
}

/// Dwie aureole za tarczą, na zmianę (skala 0,86 → 1,22, krycie 0,55 → 0),
/// w kolorze timera.
private struct CookAlarmHalos: View {
    let accent: CookTimerAccent

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Circle()
                .fill(accent.tint(scheme))
                .frame(width: SCCook.Size.alarmHalo, height: SCCook.Size.alarmHalo)
        } else {
            TimelineView(.animation) { context in
                let period = SCCook.Duration.alarmHalo
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    halo(phase: (t / period).truncatingRemainder(dividingBy: 1), color: accent.color.opacity(SCCook.Opacity.alarmHalo))
                    halo(phase: (t / period + 0.5).truncatingRemainder(dividingBy: 1), color: accent.tint(scheme))
                }
            }
        }
    }

    private func halo(phase: Double, color: Color) -> some View {
        let eased = 1 - pow(1 - phase, 3)
        return Circle()
            .fill(color)
            .frame(width: SCCook.Size.alarmHalo, height: SCCook.Size.alarmHalo)
            .scaleEffect(0.86 + (1.22 - 0.86) * eased)
            .opacity(0.55 * (1 - eased))
    }
}

/// Pierścień tarczy końca timera: podziałka sekund (60 kresek, co piąta
/// dłuższa) i kropka wskazówki ze smugą, która okrąża go raz na minutę po
/// czasie. Kąt rośnie bez końca (6° na sekundę) i dojeżdża liniowo przez
/// sekundę, więc na pełnej minucie wskazówka biegnie dalej — dawny łuk
/// „sekund bieżącej minuty” wracał co minutę do zera.
private struct CookAlarmBezel: View {
    let color: Color
    let over: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let angle = over / 60 * 360
        let hand = SCCook.Size.alarmHand
        let ring = SCCook.Size.alarmRing
        // Smuga jako ułamek obwodu pierścienia.
        let trail = Double(SCCook.Size.alarmTrail / (.pi * ring))
        ZStack {
            CookAlarmTicks(every: 1, skippingEvery: 5, length: SCCook.Size.alarmTick)
                .stroke(color.opacity(SCCook.Opacity.alarmTick), style: StrokeStyle(lineWidth: SCCook.Stroke.alarmTick, lineCap: .round))
            CookAlarmTicks(every: 5, skippingEvery: 0, length: SCCook.Size.alarmTickMajor)
                .stroke(color.opacity(SCCook.Opacity.alarmTickMajor), style: StrokeStyle(lineWidth: SCCook.Stroke.alarmTick, lineCap: .round))
            ZStack {
                Circle()
                    .trim(from: 1 - trail, to: 1)
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0), color],
                            center: .center,
                            startAngle: .degrees(360 * (1 - trail)),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: SCCook.Stroke.alarmTrail, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Circle()
                    .fill(color)
                    .frame(width: hand, height: hand)
                    .shadow(color: color.opacity(0.5), radius: 4)
                    .offset(y: -ring / 2)
            }
            .rotationEffect(.degrees(angle))
            .animation(reduceMotion ? nil : .linear(duration: 1), value: angle)
        }
        .accessibilityHidden(true)
    }
}

/// Kreski podziałki sekund od obwodu do środka: `every` — co ile sekund,
/// `skippingEvery` — bez kresek, które rysuje druga, dłuższa podziałka.
private struct CookAlarmTicks: Shape {
    let every: Int
    let skippingEvery: Int
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        var path = Path()
        for second in stride(from: 0, to: 60, by: every) {
            if skippingEvery > 0, second % skippingEvery == 0 { continue }
            let angle = Double(second) / 60 * 2 * .pi - .pi / 2
            let dx = CGFloat(cos(angle))
            let dy = CGFloat(sin(angle))
            path.move(to: CGPoint(x: center.x + dx * outer, y: center.y + dy * outer))
            path.addLine(to: CGPoint(x: center.x + dx * (outer - length), y: center.y + dy * (outer - length)))
        }
        return path
    }
}

/// Dzwonek, który się kołysze: 0° → 14° → −12° → 8° → 0° w pierwszych 40 %
/// okresu, potem spoczynek; oś u góry dzwonka.
private struct CookBell: View {
    let isRinging: Bool

    var body: some View {
        if isRinging {
            TimelineView(.animation) { context in
                let period = SCCook.Duration.alarmBell
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                bell.rotationEffect(.degrees(Self.angle(at: t)), anchor: UnitPoint(x: 0.5, y: 0.1))
            }
        } else {
            bell
        }
    }

    private var bell: some View {
        Image(systemName: "bell.fill")
            .font(.system(size: 12, weight: .bold))
    }

    /// Klatki z makiety (`scoffie-bell`), liniowo między nimi.
    static func angle(at t: Double) -> Double {
        let frames: [(Double, Double)] = [(0, 0), (0.1, 14), (0.2, -12), (0.3, 8), (0.4, 0), (1, 0)]
        for index in 1..<frames.count where t <= frames[index].0 {
            let (t0, a0) = frames[index - 1]
            let (t1, a1) = frames[index]
            let k = (t - t0) / max(0.0001, t1 - t0)
            return a0 + (a1 - a0) * k
        }
        return 0
    }
}
