import SwiftUI

/// Smart startup loader pokazywany po logowaniu / restore sesji, dopóki
/// `SessionStore` nie przygotuje krytycznych danych (przepisy, miniaturki,
/// domownicy). Cozy Kitchen v2: "Steaming Bowl" logo z oddychaniem,
/// pod nim 7 kafelków-dni wypełniających się sekwencyjnie, headline
/// + 3 pulsujące kropki.
///
/// `SessionStore.startupMinimumDisplaySeconds = 2.24 s` — moment, w którym
/// niedziela (ostatni kafelek) osiąga `fillProgress = 1`
/// (`6 × 0.28 stagger + 0.20 × 2.8 cycle`). Crossfade do dashboardu
/// startuje dokładnie wtedy — żaden kafelek się nie urywa przed
/// zapełnieniem, ekspozycja kończy na "pełnym tygodniu".
///
/// Wszystkie animacje (breathe, sequential fill, dots, steam) są
/// driver'owane jednym `TimelineView(.animation)` na podstawie czasu
/// od `startDate` — eliminuje to artefakty crossfade'ów i sytuacje,
/// w których kafelki na końcu cyklu wyświetlałyby się "już wypełnione"
/// po pierwszym pojawieniu się ekranu (modulo z ujemnych raw'ów).
struct StartupLoaderView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var startDate: Date = .init()

    private static let dayInitials = ["P", "W", "Ś", "C", "P", "S", "N"]
    private static let logoSize: CGFloat = 84

    var body: some View {
        ZStack {
            background

            // Parent (`weekly_mealsApp`) i tak owija nas crossfade'em
            // (`asymmetric(opacity + scale 1.015)` przy `.task(id:)`),
            // więc nie dokładamy własnego appear-anim — komponowałby się
            // z parent'owym, dawał double-fade i delikatne migotanie.
            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSince(startDate)
                content(elapsed: max(0, elapsed))
            }
        }
    }

    // MARK: - Foreground content

    @ViewBuilder
    private func content(elapsed: Double) -> some View {
        // wm-pot-breathe: 0/100 % scale=1, 50 % scale=1.015, ease-in-out 2.4 s.
        // sin-shape (1-cos) daje krzywą bardzo zbliżoną do CSS ease-in-out
        // bez state'a + repeatForever animation'a.
        let breatheT = (1 - cos(2 * .pi * elapsed / 2.4)) / 2
        let breatheScale = 1.0 + 0.015 * breatheT

        VStack(spacing: 0) {
            ZStack {
                WMSteamingBowlLogo(size: Self.logoSize)
                steamWispsOverlay(elapsed: elapsed)
            }
            .frame(width: Self.logoSize, height: Self.logoSize)
            .scaleEffect(breatheScale)
            .shadow(color: shadowColor, radius: 14, x: 0, y: 10)
            .padding(.bottom, 28)

            weekTilesRow(elapsed: elapsed)
                .padding(.bottom, 36)

            VStack(spacing: 0) {
                Text("Przygotowujemy Twój tydzień")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.wmLabel(colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)

                Text("Układamy plan na każdy dzień…")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.wmMuted(colorScheme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 18)

                pulsingDots(elapsed: elapsed)
            }
            .frame(maxWidth: 320)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Background

    /// Ciepłe kremowe (light) / głęboko brązowe (dark) tło z dwiema
    /// radialnymi winietami w rogach — odwzorowanie `LoaderWeek` z designu
    /// (`Scoffie - Loader i Logo.html`).
    private var background: some View {
        Color.wmCanvas(colorScheme)
            .overlay(vignettes)
            .ignoresSafeArea()
    }

    private var vignettes: some View {
        GeometryReader { proxy in
            let span = max(proxy.size.width, proxy.size.height)
            ZStack {
                RadialGradient(
                    colors: [vignetteWarm, .clear],
                    center: UnitPoint(x: 0.3, y: 0.2),
                    startRadius: 0,
                    endRadius: span * 0.55
                )
                RadialGradient(
                    colors: [vignetteCool, .clear],
                    center: UnitPoint(x: 0.7, y: 0.8),
                    startRadius: 0,
                    endRadius: span * 0.6
                )
            }
        }
        .allowsHitTesting(false)
    }

    /// `oklch(0.32 0.06 40 / 0.55)` (dark) / `oklch(0.92 0.06 70 / 0.7)` (light).
    /// Konwersje przybliżone do sRGB; subtelność > literalność OKLCH,
    /// wartości dobrane pod kompozycję z `Color.wmCanvas`.
    private var vignetteWarm: Color {
        colorScheme == .dark
            ? Color(red: 78 / 255, green: 56 / 255, blue: 42 / 255).opacity(0.55)
            : Color(red: 248 / 255, green: 234 / 255, blue: 200 / 255).opacity(0.7)
    }

    private var vignetteCool: Color {
        colorScheme == .dark
            ? Color(red: 70 / 255, green: 50 / 255, blue: 38 / 255).opacity(0.45)
            : Color(red: 235 / 255, green: 210 / 255, blue: 175 / 255).opacity(0.5)
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.45)
            : Color(red: 80 / 255, green: 40 / 255, blue: 20 / 255).opacity(0.18)
    }

    // MARK: - Logo + steam

    /// 3 cząstki pary kontynuujące ruch żółtej pary "WM" z logo v3.
    /// `position(x:y:)` w przestrzeni 84-coord (logo size). Startują tuż nad
    /// wierzchołkami narysowanej pary (y≈11–17 w 84-coord) i unoszą się
    /// ponad kafelek logo (ZStack nie clipuje, więc ujemne y są widoczne).
    private func steamWispsOverlay(elapsed: Double) -> some View {
        ZStack {
            ForEach(SteamWisp.all) { wisp in
                let phase = wisp.phase(at: elapsed)
                Circle()
                    .fill(steamWispGradient)
                    .frame(width: 8, height: 8)
                    .blur(radius: 2)
                    .scaleEffect(1.0 + 0.4 * phase.t)
                    .position(
                        x: wisp.x,
                        y: wisp.startY - 22 * phase.t
                    )
                    .opacity(phase.opacity * wisp.baseOpacity)
            }
        }
        .frame(width: Self.logoSize, height: Self.logoSize)
        .allowsHitTesting(false)
    }

    private var steamWispGradient: RadialGradient {
        RadialGradient(
            colors: colorScheme == .dark
                ? [Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.55), .clear]
                : [Color(red: 80 / 255, green: 40 / 255, blue: 20 / 255).opacity(0.4), .clear],
            center: UnitPoint(x: 0.35, y: 0.35),
            startRadius: 0,
            endRadius: 5
        )
    }

    // MARK: - 7 day tiles

    private func weekTilesRow(elapsed: Double) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                let progress = LoaderTilePhase.fillProgress(
                    elapsed: elapsed,
                    index: index,
                    cycle: 2.8,
                    stagger: 0.28
                )
                DayLoaderTile(
                    letter: Self.dayInitials[index],
                    fillColor: tileColors[index],
                    fillProgress: progress
                )
            }
        }
        .frame(height: 42)
    }

    private var tileColors: [Color] {
        [
            WMPalette.terracotta,
            WMPalette.butter,
            WMPalette.sage,
            WMPalette.terracotta,
            WMPalette.butter,
            WMPalette.sage,
            WMPalette.terracottaDeep
        ]
    }

    // MARK: - Pulsing dots

    private func pulsingDots(elapsed: Double) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(WMPalette.terracotta)
                    .frame(width: 6, height: 6)
                    .opacity(LoaderDotPhase.opacity(
                        elapsed: elapsed,
                        index: index,
                        cycle: 1.4,
                        stagger: 0.18
                    ))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Day loader tile

private struct DayLoaderTile: View {
    let letter: String
    let fillColor: Color
    let fillProgress: Double

    @Environment(\.colorScheme) private var colorScheme

    private static let cornerRadius: CGFloat = 9
    private static let tileWidth: CGFloat = 32
    private static let tileHeight: CGFloat = 42

    var body: some View {
        ZStack {
            // Pusta podstawa — `creamLow` z palety.
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(emptyBackground)

            // Kolor wypełnienia — opacity ramps 0→1 podczas 14–20 % cyklu.
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(fillColor)
                .opacity(fillProgress)

            // Hairline border — zawsze widoczny (tak jak w designie),
            // dlatego MUSI być na wierzchu nad fillem.
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)

            VStack(spacing: 0) {
                Text(letter)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(letterColor)
                    .opacity(0.85)
                    .tracking(0.3)
                    .padding(.top, 6)

                Spacer(minLength: 0)

                CheckMarkShape()
                    .trim(from: 0, to: fillProgress)
                    .stroke(
                        checkmarkColor,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 14, height: 14)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: Self.tileWidth, height: Self.tileHeight)
    }

    private var emptyBackground: Color {
        colorScheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.18)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.10)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.06)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.06)
    }

    private var letterColor: Color {
        colorScheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255)
            : Color(red: 42 / 255, green: 26 / 255, blue: 16 / 255)
    }

    /// Checkmark zawsze cream — kontrast nad nasyconymi terracotta/butter/sage.
    private var checkmarkColor: Color {
        Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255)
    }
}

private struct CheckMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        // SVG viewBox 14×14: M3 7 L6 10 L11 4
        let scaleX = rect.width / 14
        let scaleY = rect.height / 14
        var path = Path()
        path.move(to: CGPoint(x: 3 * scaleX, y: 7 * scaleY))
        path.addLine(to: CGPoint(x: 6 * scaleX, y: 10 * scaleY))
        path.addLine(to: CGPoint(x: 11 * scaleX, y: 4 * scaleY))
        return path
    }
}

// MARK: - Steam wisps

private struct SteamWisp: Identifiable {
    let id: Int
    let x: CGFloat
    let startY: CGFloat
    let baseOpacity: Double
    let delay: Double

    /// x/startY = wierzchołki trzech strug żółtej pary logo v3
    /// przeliczone na 84-coord (SVG 1024 × 84/1024).
    static let all: [SteamWisp] = [
        SteamWisp(id: 0, x: 37, startY: 9, baseOpacity: 0.5, delay: 0),
        SteamWisp(id: 1, x: 45, startY: 7, baseOpacity: 0.7, delay: 0.5),
        SteamWisp(id: 2, x: 60, startY: 15, baseOpacity: 0.5, delay: 1.0),
    ]

    /// `wm-steam-rise`: 0 % → opacity 0, 20 % → 0.9, 100 % → 0,
    /// translate 0 → −22 px, scale 1 → 1.4. 2.2 s ease-out infinite.
    /// Pre-delay guard zapobiega "wraparoundowi" przy elapsed < delay
    /// (modulo z ujemnych liczb wprowadzało wisp'y w środku cyklu).
    func phase(at elapsed: Double) -> (t: CGFloat, opacity: Double) {
        if elapsed < delay { return (0, 0) }
        let cycle: Double = 2.2
        let raw = (elapsed - delay).truncatingRemainder(dividingBy: cycle)
        let phase = raw / cycle
        let opacity: Double
        if phase < 0.2 {
            opacity = 0.9 * (phase / 0.2)
        } else {
            opacity = 0.9 * (1 - (phase - 0.2) / 0.8)
        }
        return (CGFloat(phase), max(0, opacity))
    }
}

// MARK: - Phase helpers

private enum LoaderTilePhase {
    /// `wm-day-fill`: 0–14 % → puste, 14–20 % → ramp do pełnego, 20–100 % → pełne.
    /// Pre-stagger guard (`raw < 0`) eliminuje fałszywe pełne kafelki na końcu
    /// rzędu w pierwszym cyklu — bez tego wave'a nie da się odpalić od lewej.
    static func fillProgress(
        elapsed: Double,
        index: Int,
        cycle: Double,
        stagger: Double
    ) -> Double {
        let raw = elapsed - Double(index) * stagger
        if raw < 0 { return 0 }
        let phase = raw.truncatingRemainder(dividingBy: cycle) / cycle
        if phase < 0.14 { return 0 }
        if phase < 0.20 {
            return Smooth.step((phase - 0.14) / 0.06)
        }
        return 1
    }
}

private enum LoaderDotPhase {
    /// `wm-dots`: 0–20 % → 0.25, 20–50 % → ramp do 1, 50–80 % → ramp do 0.25,
    /// 80–100 % → 0.25. Smoothstep odzwierciedla CSS ease-in-out na keyframach.
    static func opacity(
        elapsed: Double,
        index: Int,
        cycle: Double,
        stagger: Double
    ) -> Double {
        let low: Double = 0.25
        let high: Double = 1.0
        let raw = elapsed - Double(index) * stagger
        if raw < 0 { return low }
        let phase = raw.truncatingRemainder(dividingBy: cycle) / cycle
        if phase < 0.2 { return low }
        if phase < 0.5 {
            return low + (high - low) * Smooth.step((phase - 0.2) / 0.3)
        }
        if phase < 0.8 {
            return high - (high - low) * Smooth.step((phase - 0.5) / 0.3)
        }
        return low
    }
}

private enum Smooth {
    static func step(_ x: Double) -> Double {
        let t = max(0, min(1, x))
        return t * t * (3 - 2 * t)
    }
}

#Preview("Loader — dark") {
    StartupLoaderView()
        .preferredColorScheme(.dark)
}

#Preview("Loader — light") {
    StartupLoaderView()
        .preferredColorScheme(.light)
}
