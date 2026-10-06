import SwiftUI

// Wspólne klocki wyglądu trybu Gotuj. Liczby biorą się z `SCCook`
// (wygenerowane z scoffie-design `tokens/cook.json`), opis ekranów —
// scoffie-design `docs/GOTUJ.md`.

extension CookTimerAccent {
    /// Kolor timera: pierścień, etykieta, obwódka, przycisk i alarm —
    /// akcent aplikacji i kolory pór posiłków (każdy z jasnym wariantem
    /// pod krem, `SCPalette.dynamicColor`).
    var color: Color {
        switch self {
        case .terracotta: SCPalette.terracotta
        case .sage: SCPalette.sage
        case .indigo: SCPalette.indigo
        case .rose: SCPalette.rose
        case .teal: SCPalette.teal
        case .lavender: SCPalette.lavender
        case .butter: SCPalette.butter
        }
    }

    /// Tło pod kolor timera (aureola alarmu) — ten sam przepis co
    /// `scAccentTint` dla akcentu aplikacji.
    func tint(_ scheme: ColorScheme) -> Color {
        color.opacity(scheme == .dark ? 0.16 : 0.12)
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

    /// Akapit (opis kroku z radami) przechodzi w nowy W MIEJSCU jako całość:
    /// stary gaśnie z lekkim rozmyciem i ucieka o kilka punktów, nowy
    /// wchodzi z drugiej strony — ten sam ruch co cyfry `numericText`, ale
    /// bez przelewania liter między liniami (runda 10: „ostatnie litery
    /// w zdaniu i kropka przeskakują na nowy wiersz”). Na widoku z `.id`
    /// w kontenerze; krzywą podaje `cookParagraphSwapAnimation`.
    func cookParagraphSwap(countsDown: Bool) -> some View {
        modifier(CookParagraphSwapTransition(countsDown: countsDown))
    }

    /// Krzywa zamiany akapitu — `SCMotion.textRoll`, jak tytuł obok.
    func cookParagraphSwapAnimation<V: Equatable>(_ value: V) -> some View {
        modifier(CookParagraphSwapAnimation(value: value))
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

private struct CookParagraphSwapTransition: ViewModifier {
    let countsDown: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(CookParagraphSwap(
            rise: reduceMotion ? 0 : (countsDown ? -6 : 6),
            blur: reduceMotion ? 0 : 3
        ))
    }
}

private struct CookParagraphSwapAnimation<V: Equatable>: ViewModifier {
    let value: V

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? .easeInOut(duration: 0.2) : SCMotion.textRoll, value: value)
    }
}

/// Nowy akapit wchodzi od dołu (`rise` > 0) i z rozmycia, stary gaśnie
/// w górę — wstecz odwrotnie, jak cyfry przy odliczaniu.
private struct CookParagraphSwap: Transition {
    let rise: CGFloat
    let blur: CGFloat

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity ? 0 : blur)
            .offset(y: offset(phase))
    }

    private func offset(_ phase: TransitionPhase) -> CGFloat {
        switch phase {
        case .willAppear: rise
        case .didDisappear: -rise
        default: 0
        }
    }
}

/// Kołysanie dzwonka z tarczy końca timera (`scoffie-bell`): 0° → 14° →
/// −12° → 8° → 0° w pierwszych 40 % okresu `duration.cookAlarmBell`, potem
/// spoczynek; oś u góry ikony. Jedno źródło dla dzwonka i wołającego koszyka
/// na wyspie (runda 10: „podoba mi się, jak ikona się trzęsie w tym zegarze”).
enum CookBellSwing {
    static let anchor = UnitPoint(x: 0.5, y: 0.1)

    /// Kąt w chwili `elapsed` sekund od początku kołysania; po ruchu (0,64 s)
    /// zero, aż do końca okresu.
    static func angle(elapsed: Double) -> Double {
        angle(at: elapsed / SCCook.Duration.alarmBell)
    }

    /// Klatki z makiety, liniowo między nimi; `t` = ułamek okresu dzwonka.
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

/// Składniki jednego działu sklepu (runda 4: „poukładaj składniki względem
/// kategorii”). Działy idą w kolejności obchodzenia sklepu — tej samej co
/// Zakupy i szczegóły przepisu (`ProductConstants.isDepartment`), a w dziale
/// zostaje kolejność z przepisu.
struct CookIngredientAisle: Identifiable {
    let department: String
    let lines: [CookIngredientLine]

    var id: String { department }

    /// „WARZYWA” — nagłówek sekcji.
    var title: String { department.uppercased(with: Locale(identifier: "pl_PL")) }

    static func make(_ lines: [CookIngredientLine]) -> [CookIngredientAisle] {
        let other = ProductConstants.Department.other
        // `Dictionary(grouping:)` trzyma kolejność wejścia wewnątrz działu.
        let grouped = Dictionary(grouping: lines) { line -> String in
            let department = line.department?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return department.isEmpty ? other : department
        }
        return grouped
            .sorted { ProductConstants.isDepartment($0.key, orderedBefore: $1.key) }
            .map { CookIngredientAisle(department: $0.key, lines: $0.value) }
    }

    /// Ta sama kolejność bez nagłówków — składniki jednego działu obok siebie.
    static func sorted(_ lines: [CookIngredientLine]) -> [CookIngredientLine] {
        make(lines).flatMap(\.lines)
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
    /// Łagodny puls „do włączenia” (timer czeka na start) — w kolorze timera.
    func cookInvitePulse<S: InsettableShape>(_ shape: S, color: Color = SCPalette.terracotta, isActive: Bool = true) -> some View {
        modifier(CookPulse(
            shape: shape,
            color: color,
            spread: SCCook.Spacing.inviteSpread,
            startOpacity: SCCook.Opacity.pendingPulse,
            period: SCCook.Duration.invitePulse,
            isActive: isActive
        ))
    }

    /// Mocny puls „po czasie” — w kolorze timera.
    func cookOverduePulse<S: InsettableShape>(_ shape: S, color: Color = SCPalette.terracotta, isActive: Bool = true) -> some View {
        modifier(CookPulse(
            shape: shape,
            color: color,
            spread: SCCook.Spacing.overdueSpread,
            startOpacity: SCCook.Opacity.overduePulse,
            period: SCCook.Duration.overduePulse,
            isActive: isActive
        ))
    }

    /// Tło arkuszy trybu = tło arkuszy aplikacji (`SCPageBackground`:
    /// `scPageBase` z poświatą u góry). Runda 6 testów: „kolor sheetów na
    /// light mode jest inny” — było `scCanvas`, w jasnym motywie bielsze
    /// i bez poświaty.
    func cookSheetBackground(_ scheme: ColorScheme) -> some View {
        presentationBackground { SCPageBackground(scheme: scheme) }
    }

    /// Powierzchnia wyspy doku. Ciemny motyw: kryjąca powierzchnia doku
    /// z obwódką i cieniem (bez zmian). Jasny: Liquid Glass (`cookDockGlass`).
    @ViewBuilder
    func cookIslandSurface(_ scheme: ColorScheme) -> some View {
        if scheme == .dark {
            background(Capsule().fill(SCCook.Palette.dockSurface(scheme)))
                .overlay(Capsule().strokeBorder(SCCook.Palette.dockStroke(scheme), lineWidth: 1))
                .shadow(color: SCCook.Palette.dockShadow(scheme), radius: 18, y: 14)
        } else {
            cookDockGlass(scheme)
        }
    }

    /// Jasny motyw doku = systemowe Liquid Glass na wyspie, kapsułach
    /// i plakietce (runda 7: „kolor wyspy na light mode … strasznie się różni
    /// od reszty, da się to w stylu liquid zrobić?”). Samo szkło, BEZ
    /// kryjącego spodu: runda 6 dała wyspie szkło paska zakładek, ale jego
    /// warstwa `scPageBase` 0,72 zamieniała je w matową kremową plamę. Barwę
    /// (timer, stan) kładzie element nad szkłem; obwódki doku i cienia nie ma —
    /// szkło ma własny brzeg i głębię. W ciemnym motywie nic nie robi.
    @ViewBuilder
    func cookDockGlass(_ scheme: ColorScheme) -> some View {
        if scheme == .dark {
            self
        } else {
            glassEffect(.regular, in: Capsule(style: .continuous))
        }
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
/// Odcinki mają okrągłe końce i realną przerwę (runda 2). Zmiana kroku
/// PRZELEWA barwę: szałwia przechodzi po starym odcinku, terakota nalewa się
/// w nowy. Barwy to pełne, zaokrąglone odcinki odsłaniane KLINEM od środka
/// (`CookStepWedges`, `position` interpolowana przez SwiftUI) — granica
/// barw to prosta krawędź klina. Runda 2 rysowała przelewanie łukami
/// z okrągłymi końcami i przy każdym kroku na końcach odcinków wyskakiwały
/// i znikały kropki („progress przeskakuje”, runda 3).
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
        let segments = CookStepSegments(count: count, lineWidth: lineWidth, gap: gap)
        let position = Double(current)
        let pour: Animation = reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.55)
        // Ruch siedzi na samych klinach w masce — to one się przelewają,
        // a odcinki pod nimi stoją.
        ZStack {
            segments.stroke(SCCook.Palette.ringTodo(scheme), style: style)
            segments.stroke(SCPalette.sage, style: style)
                .mask {
                    CookStepWedges(part: .done, count: count, position: position, lineWidth: lineWidth, gap: gap)
                        .animation(pour, value: current)
                }
            segments.stroke(SCPalette.terracotta, style: style)
                .mask {
                    CookStepWedges(part: .current, count: count, position: position, lineWidth: lineWidth, gap: gap)
                        .animation(pour, value: current)
                }
        }
    }
}

/// Geometria odcinków pierścienia kroków — jedna dla odcinków i klinów.
/// Bez aktora: `path(in:)` kształtu woła ją poza głównym wątkiem.
private nonisolated struct CookStepGeometry {
    let center: CGPoint
    let radius: CGFloat
    let count: Int
    /// Punkty obwodu na jeden krok.
    let pitch: CGFloat
    /// Łuk między odcinkami: widoczna przerwa + kreska (okrągłe końce
    /// dokładają po pół kreski z każdej strony).
    let arcGap: CGFloat
    /// Odcinek dłuższy niż punkt — inaczej ciągły łuk postępu.
    let isSegmented: Bool

    init?(rect: CGRect, count: Int, lineWidth: CGFloat, gap: CGFloat) {
        let radius = (min(rect.width, rect.height) - lineWidth) / 2
        guard radius > 0 else { return nil }
        let total = max(1, count)
        let pitch = 2 * .pi * radius / CGFloat(total)
        let arcGap = gap + lineWidth
        self.center = CGPoint(x: rect.midX, y: rect.midY)
        self.radius = radius
        self.count = total
        self.pitch = pitch
        self.arcGap = arcGap
        self.isSegmented = pitch - arcGap >= 1
    }

    /// Kąt punktu `length` wzdłuż obwodu — od 12:00, zgodnie z zegarem
    /// (`addArc(clockwise: false)` przy rosnących kątach, jak `RingLap`).
    func angle(_ length: CGFloat) -> Double {
        Double(length / radius) - .pi / 2
    }

    func point(_ angle: Double, at distance: CGFloat) -> CGPoint {
        CGPoint(x: center.x + distance * CGFloat(cos(angle)), y: center.y + distance * CGFloat(sin(angle)))
    }

    /// Początek i długość odcinka `index` w punktach obwodu (bez końców).
    func segment(_ index: Int) -> (start: CGFloat, length: CGFloat) {
        (CGFloat(index) * pitch + arcGap / 2, pitch - arcGap)
    }
}

/// Wszystkie odcinki pierścienia (albo cały okrąg przy bardzo długim
/// przepisie) — rysowane kreską z okrągłymi końcami.
private struct CookStepSegments: Shape {
    let count: Int
    let lineWidth: CGFloat
    let gap: CGFloat

    func path(in rect: CGRect) -> Path {
        guard let geometry = CookStepGeometry(rect: rect, count: count, lineWidth: lineWidth, gap: gap) else { return Path() }
        var path = Path()
        guard geometry.isSegmented else {
            let r = geometry.radius
            path.addEllipse(in: CGRect(x: geometry.center.x - r, y: geometry.center.y - r, width: r * 2, height: r * 2))
            return path
        }
        for index in 0..<geometry.count {
            let (start, length) = geometry.segment(index)
            let a0 = geometry.angle(start)
            let a1 = geometry.angle(start + length)
            // Każdy odcinek od `move` — inaczej `addArc` dociąga kreskę od końca poprzedniego.
            path.move(to: geometry.point(a0, at: geometry.radius))
            path.addArc(center: geometry.center, radius: geometry.radius, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
        }
        return path
    }
}

/// Kliny od środka, które odsłaniają barwę na odcinkach: „zrobione” = przed
/// `position`, „bieżący” = od `position` do `position + 1` (w krokach).
/// Klin obejmuje też zaokrąglone końce, więc w spoczynku barwa kryje cały
/// odcinek, a w ruchu jej brzeg to prosta krawędź klina.
private struct CookStepWedges: Shape {
    enum Part {
        case done
        case current
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
        guard let geometry = CookStepGeometry(rect: rect, count: count, lineWidth: lineWidth, gap: gap) else { return Path() }
        // Klin sięga daleko poza kreskę — maska ma objąć całą jej grubość.
        let reach = geometry.radius * 2 + lineWidth * 2
        // Pół kreski (okrągły koniec) i pół punktu zapasu z każdej strony.
        let cap = lineWidth / 2 + 0.5
        var path = Path()

        /// Część (0…1) przedziału [`origin`, `origin + size`) w krokach,
        /// która należy do tej barwy.
        func share(of origin: Double, size: Double) -> (CGFloat, CGFloat) {
            let done = CGFloat(min(1, max(0, (position - origin) / size)))
            let currentEnd = CGFloat(min(1, max(0, (position + 1 - origin) / size)))
            switch part {
            case .done: return (0, done)
            case .current: return (done, currentEnd)
            }
        }

        func wedge(from a0: Double, to a1: Double) {
            guard a1 - a0 > 0.0001 else { return }
            path.move(to: geometry.center)
            path.addLine(to: geometry.point(a0, at: reach))
            path.addArc(center: geometry.center, radius: reach, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
            path.closeSubpath()
        }

        if geometry.isSegmented {
            for index in 0..<geometry.count {
                let (from, to) = share(of: Double(index), size: 1)
                guard to > from else { continue }
                let (start, length) = geometry.segment(index)
                let span = length + 2 * cap
                wedge(from: geometry.angle(start - cap + span * from), to: geometry.angle(start - cap + span * to))
            }
        } else {
            let (from, to) = share(of: 0, size: Double(geometry.count))
            let full = 2 * .pi * geometry.radius
            wedge(from: geometry.angle(full * from), to: geometry.angle(full * to))
        }
        return path
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
                .font(.sc(size: 14, weight: .semibold))
                .foregroundStyle(Color.scLabel(scheme))
                .lineLimit(1)
            Text(time)
                .font(.sc(size: 15, weight: .heavy))
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
