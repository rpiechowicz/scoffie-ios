import AudioToolbox
import SwiftUI

/// Koniec timera w aplikacji (ST4, D35): pełny ekran bez doku — tarcza
/// z czasem po terminie liczonym w górę, tytuł i treść alertu ze scenariusza,
/// inne trwające timery, „Jeszcze chwilę?” +1 / +2 / +5 min i „Gotowe —
/// dalej”. „Wycisz” zostawia timer po czasie (kapsuła pulsuje mocno), dopóki
/// nie padnie „Gotowe”.
struct CookAlarmView: View {
    let session: CookSession
    let item: CookDockTimer
    let now: Date
    let onExtend: (Int) -> Void
    let onSilence: () -> Void
    let onDone: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var over: TimeInterval {
        if case let .overdue(over, _, _) = item.status { return over }
        return 0
    }

    private var others: [CookDockTimer] {
        session.dockTimers(now: now).filter { other in
            guard other.id != item.id else { return false }
            if case .running = other.status { return true }
            return false
        }
    }

    var body: some View {
        ZStack {
            Color.scPageBase(scheme).ignoresSafeArea()
            CachedAsyncImage(url: session.imageURL, variant: .large) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Color.clear
                }
            }
            .opacity(SCCook.Opacity.alarmPhoto)
            .ignoresSafeArea()
            SCCook.Palette.alarmVeil(scheme).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                dial
                    .padding(.top, 34)
                texts
                    .padding(.top, 26)
                if !others.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(others) { other in
                            CookTimerPill(item: other, suffix: "· leci dalej")
                        }
                    }
                    .padding(.top, 16)
                }
                Spacer(minLength: 16)
                panel
            }
            .padding(.horizontal, SCCook.Spacing.page)
            .padding(.top, 11)
            .padding(.bottom, 8)
        }
        .sensoryFeedback(.warning, trigger: Int(over) / 4)
        .task(id: item.id) { await ring() }
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

    private var dial: some View {
        let lap = over.truncatingRemainder(dividingBy: 60) / 60
        let minutes = Int(over) / 60
        return ZStack {
            CookAlarmHalos()
            Circle()
                .stroke(SCPalette.terracotta.opacity(SCCook.Opacity.alarmTrack), lineWidth: 4)
                .frame(width: 216, height: 216)
            Circle()
                .trim(from: 0, to: lap)
                .stroke(SCPalette.terracotta, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 216, height: 216)
            Circle()
                .fill(Color.scPageBase(scheme))
                .overlay(Circle().strokeBorder(SCPalette.terracotta, lineWidth: SCCook.Stroke.alarmDisc))
                .frame(width: 198, height: 198)
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    CookBell(isRinging: !reduceMotion)
                    Text(item.timer.label.uppercased(with: Locale(identifier: "pl_PL")))
                        .cookText(SCCook.Typography.stage)
                }
                .foregroundStyle(SCPalette.terracotta)
                Text(CookClock.overdueText(over))
                    .cookText(SCCook.Typography.alarmCounter)
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))
                    .contentTransition(.numericText(countsDown: false))
                    .padding(.top, 2)
                Text(minutes > 0 ? "\(minutes) min po czasie · było \(CookClock.duration(item.timer))" : "po czasie · było \(CookClock.duration(item.timer))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.scMuted(scheme))
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
            Text("Jeszcze chwilę?")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.scMuted(scheme))
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
                .foregroundStyle(SCPalette.terracotta)
                .frame(maxWidth: .infinity)
                .frame(height: SCCook.Height.alarmDone)
                .scSoftCapsule()
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(shape.fill(Color.scCanvas(scheme)))
        .overlay(shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
    }
}

/// Dwie aureole za tarczą, na zmianę (skala 0,86 → 1,22, krycie 0,55 → 0).
private struct CookAlarmHalos: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Circle()
                .fill(Color.scAccentTint(scheme))
                .frame(width: SCCook.Size.alarmHalo, height: SCCook.Size.alarmHalo)
        } else {
            TimelineView(.animation) { context in
                let period = SCCook.Duration.alarmHalo
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    halo(phase: (t / period).truncatingRemainder(dividingBy: 1), color: SCPalette.terracotta.opacity(SCCook.Opacity.alarmHalo))
                    halo(phase: (t / period + 0.5).truncatingRemainder(dividingBy: 1), color: Color.scAccentTint(scheme))
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
