import SwiftUI

/// Smart startup loader pokazywany po logowaniu / restore sesji, dopóki
/// `SessionStore` nie przygotuje krytycznych danych (przepisy, miniaturki,
/// domownicy). Cozy Kitchen v2: "Steaming Bowl" logo z oddychaniem,
/// pod nim 7 kafelków-dni wypełniających się sekwencyjnie „od dołu"
/// z krótkim pop-em i rysowanym ptaszkiem, headline + rotujący status
/// + 3 pulsujące kropki.
///
/// Choreografia (sekundy od pojawienia się ekranu, `LoaderMotion`) — JEDEN
/// takt 1,34 s = jeden obrót znaku (sam znak, kafel stoi), ease-in-out:
/// - 0.00–0.35  wejście: logo scale 0.92→1, kafelki wjeżdżają z dołu
///              ze staggerem 30 ms, tekst dołącza po 0.15 s.
/// - 0.20–1.34  fala: kafelek `i` zaczyna wypełnienie o `0.2 + i × 0.14`,
///              kolor wznosi się od dołu przez 0.20 s, kafelek „podskakuje”,
///              ptaszek dorysowuje się 50 ms później. Niedziela domyka się
///              o 1.34 s razem z pierwszym obrotem znaku
///              = `StartupLoaderView.waveCompletionSeconds`, z którego
///              korzysta `SessionStore.startupMinimumDisplaySeconds`.
/// - od 1.34    wolne ładowanie: kafelki NIE resetują się; na każdy obrót
///              znaku przez tydzień przechodzi refleks światła. Loader schodzi
///              zawsze na końcu obrotu (`remainingToFullTurn`).
/// - zejście    od sygnału gotowości (`restElapsed`) znak dokręca BIEŻĄCY
///              obrót i staje; nowy obrót, oddech, refleks i fala kropek już
///              nie ruszają, więc gaśnięcie planszy (0,4 s) idzie nad
///              stojącym znakiem, a nie nad początkiem kolejnego obrotu.
///
/// Wszystko jest driver'owane jednym `TimelineView(.animation)` na
/// podstawie czasu od `startDate` — bez state'ów i `repeatForever`, więc
/// nie ma artefaktów przy crossfade rodzica ani „już wypełnionych"
/// kafelków w pierwszej klatce. Reduce Motion wyłącza oddech, pop,
/// refleks i wejścia; sama fala wypełnień zostaje (to informacja o postępie).
struct StartupLoaderView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate: Date = .init()
    /// Sekunda (od `startDate`), na której znak staje na dobre — koniec
    /// obrotu trwającego w chwili gotowości (`restingElapsed`). `nil` =
    /// ładowanie trwa i obroty idą dalej.
    private let restElapsed: Double?

    /// Moment, w którym ostatni kafelek (niedziela) jest w pełni domknięty.
    /// Jedyne źródło prawdy dla minimalnego czasu wyświetlania loadera.
    static let waveCompletionSeconds: Double = LoaderMotion.waveEnd

    /// Jeden obrót znaku = jedna fala dni (poniedziałek → niedziela).
    static let turnSeconds: Double = LoaderMotion.waveEnd

    /// Ile brakuje do domknięcia bieżącego obrotu znaku. Loader schodzi
    /// ZAWSZE na pełnym obrocie (`ScoffieApp`): start gotowy w półtora
    /// obrotu = loader stoi do końca drugiego.
    static func remainingToFullTurn(since start: Date, now: Date = .init()) -> Double {
        let elapsed = max(0, now.timeIntervalSince(start))
        return max(0, restingElapsed(since: start, now: now) - elapsed)
    }

    /// Koniec obrotu, na którym znak ma stanąć, licząc od `start`: bieżący
    /// obrót się domyka, kolejny już nie rusza. Gotowość tuż po domknięciu
    /// (< 0,05 s — znak w smoothstepie ledwie drgnął, ~1°) oddaje obrót,
    /// który właśnie się skończył, zamiast kręcić cały następny. Przed
    /// końcem pierwszego obrotu — zawsze jego koniec (fala dni też tam się
    /// domyka).
    static func restingElapsed(since start: Date, now: Date = .init()) -> Double {
        let elapsed = max(0, now.timeIntervalSince(start))
        let completed = floor(elapsed / turnSeconds)
        let into = elapsed - completed * turnSeconds
        if completed >= 1, into < 0.05 { return completed * turnSeconds }
        return (completed + 1) * turnSeconds
    }

    init(startDate: Date = .init(), restElapsed: Double? = nil) {
        _startDate = State(initialValue: startDate)
        self.restElapsed = restElapsed
    }

    private static let dayInitials = ["P", "W", "Ś", "C", "P", "S", "N"]
    private static let logoSize: CGFloat = 84
    private static let statusMessages = [
        "Układamy plan na każdy dzień…",
        "Odświeżamy przepisy i zdjęcia…",
        "Jeszcze chwila, prawie gotowe…",
    ]

    var body: some View {
        ZStack {
            background

            // Parent (`ScoffieApp`) owija nas crossfade'em
            // (`asymmetric(opacity + scale 1.015)` przy `.task(id:)`),
            // więc nie fade'ujemy CAŁEGO ekranu drugi raz — wejścia dotyczą
            // tylko elementów w środku i są przesunięte względem siebie,
            // dzięki czemu nie składają się z parent'owym w double-fade.
            TimelineView(.animation) { context in
                let elapsed = max(0, context.date.timeIntervalSince(startDate))
                content(motion: LoaderMotion(elapsed: elapsed, reduceMotion: reduceMotion, restElapsed: restElapsed))
            }
        }
    }

    // MARK: - Foreground content

    @ViewBuilder
    private func content(motion: LoaderMotion) -> some View {
        VStack(spacing: 0) {
            // Kręci się sam znak, kafel stoi.
            SCScoffieMark(size: Self.logoSize, markRotation: motion.logoRotation)
                .shadow(color: shadowColor, radius: 16, x: 0, y: 10)
                .scaleEffect(motion.logoScale)
                .opacity(motion.logoOpacity)
                .padding(.bottom, 30)

            weekTilesRow(motion: motion)
                .padding(.bottom, 34)

            VStack(spacing: 0) {
                Text("Przygotowujemy Twój tydzień")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.scLabel(colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)

                statusLine(index: motion.statusIndex)
                    .padding(.bottom, 18)

                pulsingDots(motion: motion)
            }
            .frame(maxWidth: 320)
            .padding(.horizontal, 24)
            .opacity(motion.textOpacity)
            .offset(y: motion.textOffset)
        }
    }

    /// Podpis statusu z crossfade'em między etapami. `ZStack` + `.id`, żeby
    /// stary i nowy tekst nakładały się w tym samym miejscu zamiast
    /// przepychać layout; stała wysokość chroni resztę przed skokami.
    private func statusLine(index: Int) -> some View {
        ZStack {
            Text(Self.statusMessages[index])
                .font(.system(size: 14))
                .foregroundStyle(Color.scMuted(colorScheme))
                .multilineTextAlignment(.center)
                .id(index)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 6)),
                        removal: .opacity.combined(with: .offset(y: -6))
                    )
                )
        }
        .frame(height: 20)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: index)
    }

    // MARK: - Background

    /// Ciepłe kremowe (light) / głęboko brązowe (dark) tło z dwiema
    /// radialnymi winietami w rogach — odwzorowanie `LoaderWeek` z designu
    /// (`Scoffie - Loader i Logo.html`).
    private var background: some View {
        Color.scCanvas(colorScheme)
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
    /// wartości dobrane pod kompozycję z `Color.scCanvas`.
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
            : Color(red: 80 / 255, green: 40 / 255, blue: 20 / 255).opacity(0.16)
    }

    // MARK: - 7 day tiles

    private func weekTilesRow(motion: LoaderMotion) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                let entrance = motion.tileEntrance(index)
                DayLoaderTile(
                    letter: Self.dayInitials[index],
                    fillColor: tileColors[index],
                    fill: motion.fill(index),
                    check: motion.check(index),
                    glow: motion.glow(index)
                )
                .scaleEffect(motion.pop(index))
                .opacity(entrance.opacity)
                .offset(y: entrance.offset)
            }
        }
        .frame(height: 42)
    }

    /// Siedem dni, siedem kolorów — cała paleta „Cozy Kitchen" naraz.
    ///
    /// Wcześniej trzy akcenty szły w kółko (terakota, masło, szałwia ×2)
    /// i fala wypełniająca tydzień powtarzała się w połowie drogi. Odkąd
    /// każda pora dnia ma własny kolor, jest ich dokładnie tyle, ile dni:
    /// zaczyna barwa marki, dalej idzie przejście od ciepłego do chłodnego,
    /// tak samo jak doba na osi dnia w Kalendarzu.
    private var tileColors: [Color] {
        [
            SCPalette.terracotta,
            SCPalette.butter,
            SCPalette.rose,
            SCPalette.sage,
            SCPalette.teal,
            SCPalette.indigo,
            SCPalette.lavender
        ]
    }

    // MARK: - Pulsing dots

    private func pulsingDots(motion: LoaderMotion) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                let dot = motion.dot(index)
                Circle()
                    .fill(SCPalette.terracotta)
                    .frame(width: 6, height: 6)
                    .scaleEffect(dot.scale)
                    .opacity(dot.opacity)
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Day loader tile

private struct DayLoaderTile: View {
    let letter: String
    let fillColor: Color
    /// 0…1 — kolor wznosi się od dołu kafelka.
    let fill: Double
    /// 0…1 — trim rysowanego ptaszka.
    let check: Double
    /// 0…~0.2 — refleks światła po fali (biały overlay).
    let glow: Double

    @Environment(\.colorScheme) private var colorScheme

    private static let cornerRadius: CGFloat = 9
    private static let tileWidth: CGFloat = 32
    private static let tileHeight: CGFloat = 42
    private static let cream = Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255)

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            // Pusta podstawa — ciepły, ledwo widoczny odcień canvasu.
            shape.fill(emptyBackground)

            // Kolor wypełnienia wznosi się od dołu (maska rośnie w górę).
            shape
                .fill(fillColor)
                .mask(alignment: .bottom) {
                    Rectangle()
                        .frame(height: Self.tileHeight * fill)
                }

            // Refleks po zakończonej fali — jedyny ruch na pełnym tygodniu.
            shape.fill(Color.white.opacity(glow))

            // Hairline border — zawsze widoczny (tak jak w designie),
            // dlatego MUSI być na wierzchu nad fillem.
            shape.stroke(borderColor, lineWidth: 1)

            VStack(spacing: 0) {
                // Litera: wyciszona na pustym kafelku, kremowa na
                // wypełnionym — dwie warstwy crossfade'ują się razem
                // z wypełnieniem, bez skoku koloru.
                ZStack {
                    Text(letter)
                        .foregroundStyle(mutedLetterColor)
                        .opacity(1 - fill)
                    Text(letter)
                        .foregroundStyle(Self.cream.opacity(0.95))
                        .opacity(fill)
                }
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.3)
                .padding(.top, 6)

                Spacer(minLength: 0)

                CheckMarkShape()
                    .trim(from: 0, to: check)
                    .stroke(
                        Self.cream,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 14, height: 14)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: Self.tileWidth, height: Self.tileHeight)
        .compositingGroup()
    }

    private var emptyBackground: Color {
        colorScheme == .dark
            ? Self.cream.opacity(0.12)
            : Color(red: 42 / 255, green: 26 / 255, blue: 16 / 255).opacity(0.07)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Self.cream.opacity(0.07)
            : Color(red: 42 / 255, green: 26 / 255, blue: 16 / 255).opacity(0.08)
    }

    /// Litera na pustym kafelku — wyciszona, nie czarna: pusty dzień ma
    /// wyglądać jak „jeszcze nie", a nie jak niedokończony element.
    private var mutedLetterColor: Color {
        colorScheme == .dark
            ? Self.cream.opacity(0.55)
            : Color(red: 42 / 255, green: 26 / 255, blue: 16 / 255).opacity(0.45)
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

// MARK: - Motion model

/// Czysta matematyka choreografii: każda wartość jest funkcją `elapsed`,
/// więc klatka jest deterministyczna i nie zależy od poprzednich.
private struct LoaderMotion {
    let elapsed: Double
    let reduceMotion: Bool
    /// Chwila spoczynku (`StartupLoaderView.restingElapsed`) — po niej nie
    /// zaczyna się żaden nowy cykl. `nil` = ładowanie trwa.
    var restElapsed: Double? = nil

    /// Czas ruchów ciągłych (obrót, oddech): zatrzymany na spoczynku.
    /// Gotowość tuż po domknięciu obrotu cofa go o najwyżej 0,05 s, czyli
    /// o ~1° — niewidoczne, a znak nie zaczyna kolejnego obrotu.
    private var motionElapsed: Double {
        guard let restElapsed else { return elapsed }
        return min(elapsed, restElapsed)
    }

    /// Cykl, który ruszył PO spoczynku, nie gra — ten, który trwał, dogrywa się.
    private func startsAfterRest(_ cycleStart: Double) -> Bool {
        guard let restElapsed else { return false }
        return cycleStart >= restElapsed - 0.001
    }

    // Wszystko liczy się od JEDNEGO taktu — obrotu znaku (`waveEnd`):
    // fala dni, obrót, później refleks na tygodniu, oddech znaku i kropki
    // biegną w tym samym rytmie, a loader schodzi na końcu taktu
    // (`StartupLoaderView.remainingToFullTurn`). Runda 22 (24.09.2026):
    // „szybciej, to musi iść równo wszystko” — takt 2,46 s → 1,34 s.

    // Wejście
    private static let logoInDuration: Double = 0.35
    private static let tilesInStart: Double = 0.0
    private static let tilesInStagger: Double = 0.03
    private static let tilesInDuration: Double = 0.30
    private static let textInStart: Double = 0.15
    private static let textInDuration: Double = 0.35

    // Fala wypełnień
    private static let fillStart: Double = 0.20
    private static let fillStagger: Double = 0.14
    private static let fillDuration: Double = 0.20
    private static let popDuration: Double = 0.30
    private static let checkDelay: Double = 0.05
    private static let checkDuration: Double = 0.20

    /// Niedziela w pełni domknięta (fill + ptaszek + pop): 1,34 s = jeden takt.
    static let waveEnd: Double = fillStart + 6 * fillStagger
        + max(checkDelay + checkDuration, popDuration)

    // Po fali: refleks przechodzi przez tydzień raz na takt, razem z obrotem.
    private static let glowStart: Double = waveEnd
    private static let glowCycle: Double = waveEnd
    private static let glowStagger: Double = 0.12
    private static let glowWidth: Double = 0.50
    private static let statusSwitches: [Double] = [2 * waveEnd, 4 * waveEnd]

    // MARK: Logo

    var logoScale: CGFloat {
        let entrance = reduceMotion ? 1 : 0.92 + 0.08 * Ease.out(elapsed / Self.logoInDuration)
        // Oddech: raz na takt, szczyt w połowie obrotu — krzywa (1 − cos)
        // odpowiada CSS ease-in-out bez state'a.
        let breathe = reduceMotion ? 0 : 0.014 * (1 - cos(2 * .pi * motionElapsed / Self.waveEnd)) / 2
        return CGFloat(entrance + breathe)
    }

    /// Obrót znaku: każdy obrót trwa jedną falę dni i jedzie ease-in-out,
    /// więc między obrotami znak na chwilę staje — i właśnie na takim
    /// postoju loader schodzi (`remainingToFullTurn`).
    var logoRotation: Angle {
        if reduceMotion { return .zero }
        let turns = motionElapsed / Self.waveEnd
        let whole = floor(turns)
        return .degrees(360 * (whole + Ease.inOut(turns - whole)))
    }

    var logoOpacity: Double {
        reduceMotion ? 1 : Ease.out(elapsed / 0.40)
    }

    // MARK: Wejścia

    func tileEntrance(_ index: Int) -> (opacity: Double, offset: CGFloat) {
        if reduceMotion { return (1, 0) }
        let start = Self.tilesInStart + Double(index) * Self.tilesInStagger
        let t = Ease.out((elapsed - start) / Self.tilesInDuration)
        return (t, CGFloat(10 * (1 - t)))
    }

    var textOpacity: Double {
        reduceMotion ? 1 : Ease.out((elapsed - Self.textInStart) / Self.textInDuration)
    }

    var textOffset: CGFloat {
        reduceMotion ? 0 : CGFloat(8 * (1 - Ease.out((elapsed - Self.textInStart) / Self.textInDuration)))
    }

    // MARK: Kafelki

    private func fillBegin(_ index: Int) -> Double {
        Self.fillStart + Double(index) * Self.fillStagger
    }

    /// Wypełnienie wznosi się od dołu z ease-out — start szybki, dojście miękkie.
    func fill(_ index: Int) -> Double {
        Ease.out((elapsed - fillBegin(index)) / Self.fillDuration)
    }

    func check(_ index: Int) -> Double {
        Ease.inOut((elapsed - fillBegin(index) - Self.checkDelay) / Self.checkDuration)
    }

    /// Pop: szybko w górę do 1.07, wolniej z powrotem (sin z „przyspieszonym" u).
    func pop(_ index: Int) -> CGFloat {
        guard !reduceMotion else { return 1 }
        let u = (elapsed - fillBegin(index)) / Self.popDuration
        guard u > 0, u < 1 else { return 1 }
        return CGFloat(1 + 0.07 * sin(.pi * pow(u, 0.7)))
    }

    /// Refleks światła przechodzący przez pełny tydzień — zamiast resetu
    /// kafelków przy dłuższym ładowaniu.
    func glow(_ index: Int) -> Double {
        guard !reduceMotion else { return 0 }
        let raw = elapsed - Self.glowStart - Double(index) * Self.glowStagger
        guard raw >= 0 else { return 0 }
        let into = raw.truncatingRemainder(dividingBy: Self.glowCycle)
        if startsAfterRest(elapsed - into) { return 0 }
        let u = into / Self.glowWidth
        guard u < 1 else { return 0 }
        return 0.22 * sin(.pi * u)
    }

    // MARK: Tekst i kropki

    var statusIndex: Int {
        Self.statusSwitches.filter { elapsed >= $0 }.count
    }

    /// `kropki`: 0–20 % → nisko, 20–50 % → ramp w górę, 50–80 % → ramp w dół.
    /// Opacity i scale jadą razem, więc kropka „wynurza się", a nie tylko mruga.
    func dot(_ index: Int) -> (opacity: Double, scale: CGFloat) {
        let low: Double = 0.28
        let raw = elapsed - Double(index) * 0.18
        var t: Double = 0
        if raw >= 0 {
            let into = raw.truncatingRemainder(dividingBy: Self.waveEnd)
            let phase = startsAfterRest(elapsed - into) ? 0 : into / Self.waveEnd
            if phase >= 0.2, phase < 0.5 {
                t = Ease.inOut((phase - 0.2) / 0.3)
            } else if phase >= 0.5, phase < 0.8 {
                t = 1 - Ease.inOut((phase - 0.5) / 0.3)
            }
        }
        let scale = reduceMotion ? 1 : 0.85 + 0.25 * t
        return (low + (1 - low) * t, CGFloat(scale))
    }
}

private enum Ease {
    /// Cubic ease-out, wejście clampowane do 0…1.
    static func out(_ x: Double) -> Double {
        let t = max(0, min(1, x))
        return 1 - pow(1 - t, 3)
    }

    /// Smoothstep — odpowiednik CSS ease-in-out na keyframach.
    static func inOut(_ x: Double) -> Double {
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
