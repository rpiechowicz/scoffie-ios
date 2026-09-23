import SwiftUI

/// Znak Scoffie, który żyje razem z aplikacją — ta sama geometria co
/// `SCMarkShape`, ale z nastrojem: oddycha, co kilka oddechów robi coś
/// swojego (rozgląda się, obraca, mruga), pochyla się ku polu, gdy ktoś pisze,
/// kręci się w rytmie łuku, gdy tura biegnie, i podskakuje, gdy przyjdzie
/// odpowiedź.
///
/// Każdy rytm jest CZYSTĄ FUNKCJĄ czasu od początku nastroju (`epoch`),
/// liczoną w `TimelineView` — nie `repeatForever` na `@State`, które zastyga,
/// gdy rodzic przebuduje widok (ten sam powód co w `SCThinkingGlyph`).
/// Zmiana nastroju nie przeskakuje: poza z chwili zmiany zostaje zamrożona
/// (`Handoff`) i przez 0,6 s przenika w nowy rytm. Po obrocie „myślenia”
/// znak dokręca się DO PRZODU do pozycji spoczynku, zamiast cofać się
/// o pół obrotu.
///
/// Myślenie kręci się z okresem łuku z „Oddechu łuku” (2,4 s) i oddycha jego
/// oddechem (1,8 s) — znak w nagłówku i łuk w wierszu tury idą jednym tempem.
/// Wiersz tury (`AssistantThoughtLine`) NIE dostaje żywego znaku: tam
/// mówi łuk, a dwa kręcące się elementy obok siebie byłyby szumem.
///
/// Zegar staje na niewybranej zakładce (`scTabIsActive`) i przy „Ogranicz
/// ruch” — wtedy znak stoi w pozie spoczynku, bez podskoków.
struct SCLivingMark: View {
    enum Mood: Equatable {
        /// Stoi; reaguje tylko na `cheer` i `nudge` (znak przy odpowiedzi).
        case still
        /// Spokój: oddech co 4,2 s, a co 8 s jedno zachowanie — rozejrzenie
        /// się, mrugnięcie, chwila ciszy, obrót.
        case idle
        /// Ktoś pisze: pochylony ku polu, szybszy i płytszy oddech.
        case attentive
        /// Tura biegnie: obrót 2,4 s i oddech 1,8 s, jak łuk.
        case thinking
        /// Pula wykorzystana: drzemie — przechylony, bardzo wolny oddech,
        /// bez zachowań i bez poświaty.
        case sleeping
    }

    var mood: Mood = .idle
    let color: Color
    var size: CGFloat = 24
    /// Każde podbicie = radosny podskok (przyszła odpowiedź).
    var cheer: Int = 0
    /// Każde podbicie = krótkie skinienie (ktoś zaczął pisać).
    var nudge: Int = 0
    /// Miękka poświata pod znakiem; w wierszu tekstu (≤ 18 pt) to szum.
    var glows: Bool = true

    @Environment(\.scTabIsActive) private var isActiveTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Początek bieżącego nastroju — od niego liczą się wszystkie rytmy.
    @State private var epoch = Date()
    /// Poza zamrożona w chwili zmiany nastroju.
    @State private var handoff: Handoff?

    private struct Handoff {
        let pose: Pose
        let at: Date
        /// Poprzedni nastrój kręcił się — dokręcamy do przodu.
        let forward: Bool
    }

    /// Jedna klatka znaku. Wartości domyślne to spoczynek.
    fileprivate struct Pose: Equatable {
        var scale: Double = 1
        /// Skala w pionie względem `scale` — mrugnięcie.
        var squash: Double = 1
        /// Stopnie, zgodnie z ruchem wskazówek.
        var angle: Double = 0
        /// Przesunięcie w pionie jako ułamek rozmiaru (ujemne = w górę).
        var lift: Double = 0
        /// Siła poświaty 0…1.
        var glow: Double = 0
    }

    /// Ile trwa przejście między nastrojami.
    private static let handoffDuration: TimeInterval = 0.6

    /// Zegar stoi: „Ogranicz ruch”, inna zakładka albo znak nieruchomy.
    private var isPaused: Bool { reduceMotion || !isActiveTab || mood == .still }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isPaused)) { context in
            let now: Pose = (reduceMotion || mood == .still) ? Pose() : pose(for: mood, at: context.date)
            SCMarkShape()
                .fill(color)
                .frame(width: size, height: size)
                .scaleEffect(x: CGFloat(now.scale), y: CGFloat(now.scale * now.squash))
                .rotationEffect(.degrees(now.angle))
                .offset(y: CGFloat(now.lift) * size)
                .background {
                    if glows, now.glow > 0.01 {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [color.opacity(0.24 * now.glow), color.opacity(0)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: size * 0.95
                                )
                            )
                            .frame(width: size * 1.9, height: size * 1.9)
                            .allowsHitTesting(false)
                    }
                }
        }
        // Podskok i skinienie to jednorazowe keyframe'y NAD rytmem — każdy
        // tor startuje od `MoveKeyframe`, więc drugie podbicie gra od zera,
        // a nie od końca poprzedniego (wzór z `BurstHeart`). Rozmiar jedzie
        // w samej wartości (`unit`), bo domknięcie treści niczego nie łapie.
        .keyframeAnimator(initialValue: MarkReaction(unit: size), trigger: reduceMotion ? 0 : cheer) { mark, frame in
            mark
                .scaleEffect(frame.scale)
                .rotationEffect(.degrees(frame.angle))
                .offset(y: frame.lift * frame.unit)
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                MoveKeyframe(1)
                SpringKeyframe(1.24, duration: 0.18, spring: Spring(response: 0.2, dampingRatio: 0.7))
                SpringKeyframe(0.93, duration: 0.16, spring: Spring(response: 0.18, dampingRatio: 0.8))
                SpringKeyframe(1, duration: 0.45, spring: Spring(response: 0.42, dampingRatio: 0.55))
            }
            KeyframeTrack(\.lift) {
                MoveKeyframe(0)
                CubicKeyframe(-0.3, duration: 0.2)
                CubicKeyframe(0.04, duration: 0.2)
                CubicKeyframe(0, duration: 0.25)
            }
            KeyframeTrack(\.angle) {
                MoveKeyframe(0)
                CubicKeyframe(-12, duration: 0.16)
                CubicKeyframe(9, duration: 0.2)
                CubicKeyframe(0, duration: 0.28)
            }
        }
        .keyframeAnimator(initialValue: MarkReaction(unit: size), trigger: reduceMotion ? 0 : nudge) { mark, frame in
            mark
                .scaleEffect(frame.scale)
                .rotationEffect(.degrees(frame.angle))
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                MoveKeyframe(1)
                CubicKeyframe(1.1, duration: 0.14)
                SpringKeyframe(1, duration: 0.4, spring: Spring(response: 0.35, dampingRatio: 0.6))
            }
            KeyframeTrack(\.angle) {
                MoveKeyframe(0)
                CubicKeyframe(10, duration: 0.14)
                CubicKeyframe(-4, duration: 0.16)
                CubicKeyframe(0, duration: 0.22)
            }
        }
        .frame(width: size, height: size)
        .onChange(of: mood) { old, _ in
            // Poza STAREGO nastroju w tej chwili — z niej rusza nowy.
            let now = Date()
            let from = pose(for: old, at: now)
            handoff = Handoff(pose: from, at: now, forward: old == .thinking)
            epoch = now
        }
        .accessibilityHidden(true)
    }

    // MARK: - Poza w czasie

    /// Poza nastroju `mood` w chwili `date`, z przejściem od zamrożonej pozy.
    private func pose(for mood: Mood, at date: Date) -> Pose {
        let target = Self.pose(mood, t: max(0, date.timeIntervalSince(epoch)))
        guard let handoff else { return target }
        let progress = date.timeIntervalSince(handoff.at) / Self.handoffDuration
        guard progress < 1 else { return target }
        let p = max(0, progress)
        let weight = p * p * (3 - 2 * p)
        return Self.mix(handoff.pose, target, weight, forward: handoff.forward)
    }

    private static func pose(_ mood: Mood, t: TimeInterval) -> Pose {
        switch mood {
        case .still: return Pose()
        case .idle: return idle(t)
        case .attentive: return attentive(t)
        case .thinking: return thinking(t)
        case .sleeping: return sleeping(t)
        }
    }

    /// Oddech 0…1 zaczynający się od zera — wejście w nastrój startuje
    /// ze spoczynku.
    private static func breath(_ t: TimeInterval, period: Double) -> Double {
        (1 - cos(2 * .pi * t / period)) / 2
    }

    private static func easeInOut(_ p: Double) -> Double {
        p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
    }

    /// Spokój. Zachowania co 8 s (od 4,5 s cyklu), po kolei: rozejrzenie,
    /// mrugnięcie, cisza, obrót — przewidywalnie rzadko, żeby znak żył,
    /// a nie wiercił się.
    private static func idle(_ t: TimeInterval) -> Pose {
        let b = breath(t, period: 4.2)
        var pose = Pose(scale: 1 + 0.045 * b, glow: 0.15 + 0.45 * b)
        let cycle = 8.0
        let index = Int(t / cycle)
        let u = t - Double(index) * cycle - 4.5
        switch index % 4 {
        case 0:
            // Rozejrzenie: kęs zerka w prawo, potem w lewo, i wraca.
            let duration = 2.4
            if u >= 0, u < duration {
                let p = u / duration
                pose.angle = 14 * sin(2 * .pi * p) * sin(.pi * p)
                pose.lift = -0.03 * sin(.pi * p)
            }
        case 1:
            // Mrugnięcie — dwa szybkie przymknięcia w pionie.
            let duration = 0.55
            if u >= 0, u < duration {
                let s = sin(2 * .pi * u / duration)
                pose.squash = 1 - 0.3 * s * s
            }
        case 3:
            // Pełny obrót z lekkim przysiadem w połowie; 360° = spoczynek.
            let duration = 1.5
            if u >= 0, u < duration {
                let p = u / duration
                pose.angle = 360 * easeInOut(p)
                pose.scale *= 1 - 0.08 * sin(.pi * p)
            }
        default:
            break
        }
        return pose
    }

    /// Ktoś pisze: znak pochyla się ku polu i kołysze w rytmie szybszego oddechu.
    private static func attentive(_ t: TimeInterval) -> Pose {
        let b = breath(t, period: 2.6)
        return Pose(
            scale: 1.06 + 0.025 * b,
            angle: 12 + 4 * sin(2 * .pi * t / 2.6),
            lift: -0.02,
            glow: 0.45 + 0.3 * b
        )
    }

    /// Tura biegnie: obrót i oddech w tempie łuku.
    private static func thinking(_ t: TimeInterval) -> Pose {
        let b = breath(t, period: 1.8)
        return Pose(
            scale: 0.95 + 0.08 * b,
            angle: 360 * (t / 2.4).truncatingRemainder(dividingBy: 1),
            glow: 0.3 + 0.5 * b
        )
    }

    /// Drzemka: przechylony, prawie nieruchomy.
    private static func sleeping(_ t: TimeInterval) -> Pose {
        let b = breath(t, period: 6.5)
        return Pose(scale: 0.97 + 0.03 * b, angle: -10, lift: 0.015 * b)
    }

    /// Przenikanie póz. Kąt po krótszej drodze, a po obrocie — do przodu
    /// (do 30° wstecz, żeby prawie-spoczynek nie robił całego obrotu).
    private static func mix(_ a: Pose, _ b: Pose, _ w: Double, forward: Bool) -> Pose {
        var delta = (b.angle - a.angle).truncatingRemainder(dividingBy: 360)
        if forward {
            if delta < 0 { delta += 360 }
            if delta > 330 { delta -= 360 }
        } else if delta > 180 {
            delta -= 360
        } else if delta < -180 {
            delta += 360
        }
        return Pose(
            scale: a.scale + (b.scale - a.scale) * w,
            squash: a.squash + (b.squash - a.squash) * w,
            angle: a.angle + delta * w,
            lift: a.lift + (b.lift - a.lift) * w,
            glow: a.glow + (b.glow - a.glow) * w
        )
    }
}

/// Klatka jednorazowej reakcji (podskok, skinienie). Spoczynek = wartości
/// domyślne; `unit` to rozmiar znaku, żeby skok liczył się w jego skali.
private struct MarkReaction {
    var scale: CGFloat = 1
    var angle: Double = 0
    /// Ułamek rozmiaru (ujemne = w górę).
    var lift: CGFloat = 0
    var unit: CGFloat = 24
}

#Preview("Żywy znak") {
    struct Demo: View {
        @State private var mood: SCLivingMark.Mood = .idle
        @State private var cheer = 0
        @State private var nudge = 0

        var body: some View {
            VStack(spacing: 32) {
                SCLivingMark(mood: mood, color: SCPalette.terracotta, size: 56, cheer: cheer, nudge: nudge)
                    .frame(width: 120, height: 120)
                Picker("Nastrój", selection: $mood) {
                    Text("Spokój").tag(SCLivingMark.Mood.idle)
                    Text("Pisze").tag(SCLivingMark.Mood.attentive)
                    Text("Myśli").tag(SCLivingMark.Mood.thinking)
                    Text("Śpi").tag(SCLivingMark.Mood.sleeping)
                }
                .pickerStyle(.segmented)
                HStack {
                    Button("Odpowiedź") { cheer += 1 }
                    Button("Pisanie") { nudge += 1 }
                }
            }
            .padding(24)
        }
    }
    return Demo()
}
