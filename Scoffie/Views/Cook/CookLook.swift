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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: countsDown))
            .animation(animation, value: value)
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
/// w nagłówku trybu, na talerzu po wstrzymaniu i w Live Activity.
struct CookStepArcs: View {
    let count: Int
    let current: Int
    var lineWidth: CGFloat = SCCook.Stroke.stepRing
    var gap: CGFloat = SCCook.Spacing.stepRingGap
    var roundCaps = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = (side - lineWidth) / 2
            let circumference = 2 * .pi * radius
            let total = max(1, count)
            let pitch = circumference / CGFloat(total)
            // Za krótki odcinek przy bardzo długim przepisie = ciągły łuk postępu.
            let segmented = pitch > gap * 2
            ZStack {
                if segmented {
                    ForEach(0..<total, id: \.self) { index in
                        let start = (CGFloat(index) * pitch + gap / 2) / circumference
                        let end = (CGFloat(index + 1) * pitch - gap / 2) / circumference
                        Circle()
                            .trim(from: start, to: end)
                            .stroke(color(for: index), style: StrokeStyle(lineWidth: lineWidth, lineCap: roundCaps ? .round : .butt))
                    }
                } else {
                    Circle().stroke(SCCook.Palette.ringTodo(scheme), lineWidth: lineWidth)
                    Circle()
                        .trim(from: 0, to: CGFloat(current + 1) / CGFloat(total))
                        .stroke(SCPalette.sage, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }
            .rotationEffect(.degrees(-90))
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func color(for index: Int) -> Color {
        if index < current { return SCPalette.sage }
        if index == current { return SCPalette.terracotta }
        return SCCook.Palette.ringTodo(scheme)
    }
}

/// Krążek z pierścieniem kroków i numerem bieżącego kroku (nagłówek trybu).
struct CookStepRing: View {
    let count: Int
    /// Indeks od zera.
    let current: Int

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let side = SCCook.Size.stepRing
        let arc = SCCook.Size.stepRingRadius * 2 + SCCook.Stroke.stepRing
        ZStack {
            Circle().fill(SCCook.Palette.ringDisc(scheme))
            CookStepArcs(count: count, current: current)
                .frame(width: arc, height: arc)
            Text("\(current + 1)")
                .font(.system(size: 14, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Color.scLabel(scheme))
                .cookRoll(current)
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Krok \(current + 1) z \(count)")
    }
}

/// Pierścień timera: tor w kolorze timera, łuk = POZOSTAŁY czas (topnieje —
/// docs/GOTUJ.md, ustalenie 1), końce okrągłe, start o 12:00.
///
/// Dok przelicza stan raz na sekundę, a łuk dojeżdża do nowej wartości
/// liniowo przez tę sekundę — ubywa płynnie, a nie skokami (§8.2).
struct CookTimerRing: View {
    let fraction: Double
    let color: Color
    let lineWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(SCCook.Opacity.timerTrack), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 1), value: fraction)
        }
        .padding(lineWidth / 2)
    }
}

/// Pigułka biegnącego timera: pierścień, nazwa, czas w kolorze timera —
/// arkusz wyjścia i „leci dalej” na ekranie końca timera.
struct CookTimerPill: View {
    let item: CookDockTimer
    var suffix: String? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let color = item.accent.color
        HStack(spacing: 8) {
            CookTimerRing(fraction: item.status.remainingFraction, color: color, lineWidth: 3)
                .frame(width: SCCook.Size.pillRing, height: SCCook.Size.pillRing)
            Text(item.timer.label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.scLabel(scheme))
                .lineLimit(1)
            Text(CookDockLabels.time(item.status))
                .font(.system(size: 15, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(color)
                .cookTicking(CookDockLabels.time(item.status), countsDown: !item.status.isOverdue)
            if let suffix {
                Text(suffix)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.scMuted(scheme))
            }
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
