import SwiftUI

// Wspólne klocki wyglądu trybu Gotuj. Liczby biorą się z `SCCook`
// (wygenerowane z scoffie-design `tokens/cook.json`), opis ekranów —
// scoffie-design `docs/GOTUJ.md`.

extension CookTimerAccent {
    /// Kolor timera: pierścień, etykieta, obwódka i przycisk pauzy.
    var color: Color {
        switch self {
        case .terracotta: SCPalette.terracotta
        case .sage: SCPalette.sage
        }
    }
}

extension View {
    /// Styl tekstu z tokenu: krój, światło liter i odstęp linii z makiety.
    func cookText(_ style: SCCookTextStyle) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
    }

    /// Tekst przechodzi w nowy tekst W MIEJSCU — słowo w słowo, liczba
    /// w liczbę (`SCMotion.textRoll`, jak danie w arkuszu wyboru posiłku
    /// i Kalendarz). `value` = to, co się zmienia.
    func cookRoll<V: Equatable>(_ value: V, countsDown: Bool = false) -> some View {
        modifier(CookTextMotion(value: value, countsDown: countsDown, ticking: false))
    }

    /// Liczba w miejscu (numer kroku, liczba składników): cyfry rolują
    /// w górę przy wzroście i w dół przy spadku (`numericText(value:)`).
    func cookRoll(_ value: Int) -> some View {
        modifier(CookTextMotion(value: value, countsDown: false, ticking: false, numericValue: Double(value)))
    }

    /// Zegar, który tyka co sekundę: cyfry rolują krótkim `easeOut` 0,3 s
    /// (`SCRollingNumber` — każdy zegar w aplikacji rusza się tak samo).
    func cookTicking<V: Equatable>(_ value: V, countsDown: Bool = true) -> some View {
        modifier(CookTextMotion(value: value, countsDown: countsDown, ticking: true))
    }

    /// Wejście ekranu trybu: sekcja wjeżdża z dołu i rozjaśnia się kaskadą
    /// (`scReveal`, wzór szczegółów posiłku).
    func cookReveal(_ isVisible: Bool, order: Int) -> some View {
        scReveal(isVisible, order: order)
    }

    /// Krążki na zdjęciu (pierścień kroków, krzyżyk) pojawiają się razem
    /// z treścią — jak serce i krzyżyk w szczegółach posiłku.
    func cookChrome(_ isVisible: Bool) -> some View {
        modifier(CookChrome(isVisible: isVisible))
    }
}

private struct CookTextMotion<V: Equatable>: ViewModifier {
    let value: V
    let countsDown: Bool
    let ticking: Bool
    /// Gdy jest — kierunek rolowania idzie za zmianą tej liczby.
    var numericValue: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(transition)
            .animation(animation, value: value)
    }

    private var transition: ContentTransition {
        if reduceMotion { return .opacity }
        if let numericValue { return .numericText(value: numericValue) }
        return .numericText(countsDown: countsDown)
    }

    private var animation: Animation {
        if reduceMotion { return .easeInOut(duration: 0.2) }
        return ticking ? .easeOut(duration: 0.3) : SCMotion.textRoll
    }
}

private struct CookChrome: ViewModifier {
    let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.85)
            .animation(.easeOut(duration: 0.35).delay(0.05), value: isVisible)
    }
}

/// Klatka oddechu przed kaskadą wejścia: ustawione w `onAppear` padało
/// w klatce wstawienia widoku i nic nie grało (szczegóły posiłku).
enum CookEntrance {
    static func breathe() async {
        try? await Task.sleep(for: .milliseconds(80))
    }
}

/// Ikona i kolor składnika: działy sklepu jak w Zakupach — ten sam produkt
/// ma w aplikacji jeden kolor (docs/GOTUJ.md, ustalenie 3).
enum CookIngredientLook {
    static func icon(_ department: String?) -> String {
        ProductConstants.departmentIcon(for: department ?? "")
    }

    static func color(_ department: String?) -> Color {
        ProductConstants.departmentColor(for: department ?? "")
    }
}

/// Puls rozchodzący się NA ZEWNĄTRZ kształtu — sama kontrolka się nie
/// skaluje (makieta: `box-shadow` rośnie od 0 do `spread`, krycie spada do 0,
/// ease-out, w pętli). Przy Reduce Motion pulsu nie ma.
struct CookPulse<S: InsettableShape>: ViewModifier {
    let shape: S
    let color: Color
    let spread: CGFloat
    let startOpacity: Double
    let period: Double
    var isActive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.background {
            if isActive, !reduceMotion {
                TimelineView(.animation) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: period) / period
                    let eased = 1 - pow(1 - phase, 3)
                    let width = max(0.01, spread * eased)
                    shape
                        .inset(by: -width)
                        .strokeBorder(color.opacity(startOpacity * (1 - eased)), lineWidth: width)
                }
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// Łagodny puls „do włączenia” (timer czeka na start).
    func cookInvitePulse<S: InsettableShape>(_ shape: S, isActive: Bool = true) -> some View {
        modifier(CookPulse(
            shape: shape,
            color: SCPalette.terracotta,
            spread: SCCook.Spacing.inviteSpread,
            startOpacity: SCCook.Opacity.pendingPulse,
            period: SCCook.Duration.invitePulse,
            isActive: isActive
        ))
    }

    /// Mocny puls „po czasie”.
    func cookOverduePulse<S: InsettableShape>(_ shape: S, isActive: Bool = true) -> some View {
        modifier(CookPulse(
            shape: shape,
            color: SCPalette.terracotta,
            spread: SCCook.Spacing.overdueSpread,
            startOpacity: SCCook.Opacity.overduePulse,
            period: SCCook.Duration.overduePulse,
            isActive: isActive
        ))
    }
}

/// Zdjęcie dania w nagłówku każdego ekranu trybu — ta sama wysokość
/// i to samo wygaszenie, więc przejścia między ekranami nie skaczą (§13).
///
/// Szerokość bierze się z ekranu, NIGDY ze zdjęcia: zdjęcie leży w tle
/// pustej ramki i jest przycięte do niej. Wcześniej `scaledToFill` w samej
/// ramce wysokości zgłaszał szerokość kadru (1344 × 768 przy 330 pt wysokości
/// to ~580 pt), `ZStack` z treścią robił się szerszy niż ekran, a tekst
/// przypięty do lewej uciekał za krawędź — „ekran bez marginesów”.
///
/// Ruch jak okładka szczegółów posiłku: przy wejściu w tryb zdjęcie osiada
/// z 1,12 (`isRevealed`), przy przewijaniu zostaje w tyle o 30 % drogi,
/// a przy przeciągnięciu w dół rozciąga się od dolnej krawędzi.
struct CookHeaderPhoto: View {
    let url: URL?
    var opacity: Double = SCCook.Opacity.headerPhoto
    var isRevealed = true

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let base = Color.scPageBase(scheme)
        // Zamknięcia `visualEffect` biegną poza głównym aktorem — biorą kopie.
        let height = SCCook.Size.headerPhoto
        let parallax: CGFloat = reduceMotion ? 0 : 0.3
        Color.clear
            .frame(height: height)
            .background {
                photo
                    .visualEffect { content, proxy in
                        let minY = proxy.frame(in: .scrollView).minY
                        return content.offset(y: minY > 0 ? 0 : -minY * parallax)
                    }
            }
            .overlay(alignment: .top) {
                LinearGradient(colors: [base.opacity(0), base], startPoint: .top, endPoint: .bottom)
                    .frame(height: SCCook.Size.headerFade)
                    .padding(.top, SCCook.Spacing.headerFadeStart)
                    .allowsHitTesting(false)
            }
            .clipped()
            .visualEffect { content, proxy in
                let minY = proxy.frame(in: .scrollView).minY
                let stretch = minY > 0 ? (height + minY) / height : 1
                return content.scaleEffect(stretch, anchor: .bottom)
            }
            .accessibilityHidden(true)
    }

    private var photo: some View {
        CachedAsyncImage(url: url, variant: .large) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity.animation(.easeOut(duration: 0.35)))
            } else {
                Color.scTileBg(scheme)
            }
        }
        .scaleEffect(isRevealed || reduceMotion ? 1 : 1.12)
        .animation(.easeOut(duration: 1.1), value: isRevealed)
        // Obie granice = ramka bierze rozmiar od rodzica, a nie od kadru.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .opacity(opacity)
    }
}

/// Zdjęcie dania na cały ekran pod welonem (koniec timera) — ta sama zasada:
/// rozmiar z ekranu, kadr przycięty.
struct CookBackdropPhoto: View {
    let url: URL?
    let opacity: Double

    var body: some View {
        CachedAsyncImage(url: url, variant: .large) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .opacity(opacity)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Pierścień kroków: N odcinków zgodnie z zegarem od 12:00 — zrobione
/// w szałwii, bieżący w terakocie, przed nami `cook.ringTodo`. Ten sam znak
/// w nagłówku trybu i na talerzu po wstrzymaniu (Live Activity w E5).
///
/// Odcinki mają okrągłe końce i realną przerwę (runda 2 testów: „bardziej
/// zaokrąglone, dopracuj designersko”). Zmiana kroku PRZELEWA barwę:
/// szałwia przechodzi po starym odcinku, a terakota nalewa się w nowy (wstecz
/// — odwrotnie). Jedna liczba (`position`) interpolowana przez SwiftUI,
/// z której trzy warstwy liczą swoje łuki w każdej klatce (wzór `RingLap`
/// z Planu), więc żaden odcinek nie przeskakuje kolorem w jednej klatce.
struct CookStepArcs: View {
    let count: Int
    /// Indeks od zera.
    let current: Int
    var lineWidth: CGFloat = SCCook.Stroke.stepRing
    /// Widoczna przerwa między odcinkami — od końca do końca zaokrąglenia.
    var gap: CGFloat = SCCook.Spacing.stepRingGap

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        let position = Double(current)
        ZStack {
            CookStepArcLayer(part: .todo, count: count, position: position, lineWidth: lineWidth, gap: gap)
                .stroke(SCCook.Palette.ringTodo(scheme), style: style)
            CookStepArcLayer(part: .done, count: count, position: position, lineWidth: lineWidth, gap: gap)
                .stroke(SCPalette.sage, style: style)
            CookStepArcLayer(part: .current, count: count, position: position, lineWidth: lineWidth, gap: gap)
                .stroke(SCPalette.terracotta, style: style)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.6), value: current)
    }
}

/// Łuki jednej barwy pierścienia kroków we wszystkich odcinkach.
/// `position` (bieżący krok) jest `animatableData` — podział każdego odcinka
/// na „zrobione / bieżący / przed nami” liczy się z niej w każdej klatce.
private struct CookStepArcLayer: Shape {
    enum Part {
        case done
        case current
        case todo
    }

    let part: Part
    let count: Int
    var position: Double
    let lineWidth: CGFloat
    let gap: CGFloat

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let total = max(1, count)
        let radius = (min(rect.width, rect.height) - lineWidth) / 2
        guard radius > 0 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let circumference = 2 * .pi * radius
        let pitch = circumference / CGFloat(total)
        // Okrągłe końce dokładają pół kreski z każdej strony — łuk między
        // odcinkami = widoczna przerwa + kreska.
        let arcGap = gap + lineWidth
        var path = Path()

        /// Łuk od `start` do `end` w punktach wzdłuż obwodu, od 12:00
        /// zgodnie z zegarem. Każdy zaczyna się `move`, inaczej `addArc`
        /// dociągnąłby kreskę od końca poprzedniego.
        func arc(from start: CGFloat, to end: CGFloat) {
            guard end - start > 0.01 else { return }
            let a0 = Double(start / radius) - .pi / 2
            let a1 = Double(end / radius) - .pi / 2
            path.move(to: CGPoint(x: center.x + radius * CGFloat(cos(a0)), y: center.y + radius * CGFloat(sin(a0))))
            path.addArc(center: center, radius: radius, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
        }

        if pitch - arcGap >= 1 {
            let length = pitch - arcGap
            for index in 0..<total {
                let origin = CGFloat(index) * pitch + arcGap / 2
                let (from, to) = share(of: Double(index), size: 1)
                arc(from: origin + length * from, to: origin + length * to)
            }
        } else {
            // Bardzo długi przepis: odcinek byłby krótszy od przerwy —
            // ciągły łuk postępu w tych samych trzech barwach.
            let (from, to) = share(of: 0, size: Double(total))
            arc(from: circumference * from, to: circumference * to)
        }
        return path
    }

    /// Część (0…1) przedziału [`origin`, `origin + size`) w krokach, która
    /// należy do tej barwy: zrobione = przed `position`, bieżący = od
    /// `position` do `position + 1`, przed nami = reszta.
    private func share(of origin: Double, size: Double) -> (CGFloat, CGFloat) {
        let done = CGFloat(min(1, max(0, (position - origin) / size)))
        let currentEnd = CGFloat(min(1, max(0, (position + 1 - origin) / size)))
        switch part {
        case .done: return (0, done)
        case .current: return (done, currentEnd)
        case .todo: return (currentEnd, 1)
        }
    }
}

/// Krążek z pierścieniem kroków i numerem bieżącego kroku (nagłówek trybu) —
/// tej samej wielkości i na tej samej powierzchni co krzyżyk na zdjęciu obok
/// (`SCSheetCloseButton(onImage:)`; runda 2: „X oraz stepper mają być takiej
/// samej wielkości”).
struct CookStepRing: View {
    let count: Int
    /// Indeks od zera.
    let current: Int

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let side = SCCook.Size.stepRing
        let arc = SCCook.Size.stepRingRadius * 2 + SCCook.Stroke.stepRing
        ZStack {
            CookStepArcs(count: count, current: current)
                .frame(width: arc, height: arc)
            Text("\(current + 1)")
                .cookText(SCCook.Typography.stepNumber)
                .monospacedDigit()
                .foregroundStyle(Color.scLabel(scheme))
                .cookRoll(current)
        }
        .frame(width: side, height: side)
        .scSheetIconSurface(onImage: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Krok \(current + 1) z \(count)")
    }
}

/// Pierścień timera: tor w kolorze timera, łuk = POZOSTAŁY czas (topnieje —
/// docs/GOTUJ.md, ustalenie 1), końce okrągłe.
///
/// Ubywa ZGODNIE ze wskazówkami zegara (runda 2 testów): koniec łuku stoi
/// o 12:00, a jego początek ucieka w prawo — tak, jak wskazówka zjada
/// tarczę. Dok przelicza stan raz na sekundę, a łuk dojeżdża do nowej
/// wartości liniowo przez tę sekundę — płynnie, a nie skokami (§8.2).
struct CookTimerRing: View {
    let fraction: Double
    let color: Color
    let lineWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let left = max(0, min(1, fraction))
        ZStack {
            Circle().stroke(color.opacity(SCCook.Opacity.timerTrack), lineWidth: lineWidth)
            Circle()
                .trim(from: 1 - left, to: 1)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 1), value: fraction)
        }
        .padding(lineWidth / 2)
    }
}

/// Pigułka biegnącego timera: pierścień, nazwa, czas w kolorze timera —
/// arkusz wyjścia i inne timery na ekranie końca timera.
struct CookTimerPill: View {
    let item: CookDockTimer

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let color = item.accent.color
        let time = CookDockLabels.time(item.status)
        HStack(spacing: 8) {
            CookTimerRing(fraction: item.status.remainingFraction, color: color, lineWidth: 3)
                .frame(width: SCCook.Size.pillRing, height: SCCook.Size.pillRing)
            Text(item.timer.label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.scLabel(scheme))
                .lineLimit(1)
            Text(time)
                .font(.system(size: 15, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(color)
                .cookTicking(time, countsDown: !item.status.isOverdue)
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(height: 40)
        .background(Capsule().fill(color.opacity(SCCook.Opacity.timerPill)))
        .accessibilityElement(children: .combine)
    }
}

extension CookTimerStatus {
    var isOverdue: Bool {
        if case .overdue = self { true } else { false }
    }

    /// Rodzaj stanu bez liczb — klucz animacji zmiany koloru i przycisku,
    /// który nie tyka co sekundę razem z zegarem.
    var phase: Int {
        switch self {
        case .pending: 0
        case .running: 1
        case .paused: 2
        case .overdue: 3
        case .finished: 4
        }
    }
}

/// Teksty doku i kart wyliczane ze stanu timera.
enum CookDockLabels {
    static func time(_ status: CookTimerStatus) -> String {
        switch status {
        case let .pending(total): CookClock.text(total)
        case let .running(remaining, _, _): CookClock.text(remaining)
        case let .paused(remaining, _): CookClock.text(remaining)
        case let .overdue(over, _, _): CookClock.overdueText(over)
        case .finished: ""
        }
    }

    /// Etykieta w kapsule: przy „do włączenia” warunek startu ze scenariusza
    /// (D37), po czasie i w pauzie — nazwa z dopiskiem.
    static func capsuleLabel(_ item: CookDockTimer) -> String {
        switch item.status {
        case .pending: item.timer.startLabel
        case .overdue: "\(item.timer.label) · po czasie"
        case .paused: "\(item.timer.label) · pauza"
        case .running, .finished: item.timer.label
        }
    }

    static func accessibility(_ item: CookDockTimer) -> String {
        switch item.status {
        case .pending: "Start: \(item.timer.label), \(time(item.status))"
        case .overdue: "\(item.timer.label): czas minął"
        case .paused: "\(item.timer.label), wstrzymany, \(time(item.status))"
        case .running, .finished: "\(item.timer.label), \(time(item.status))"
        }
    }
}
