import Foundation
import SwiftUI

// Kalendarz v4 — doba jako łuk.
//
// Źródło: canvas claude.ai → „Weekly Meals - Kalendarz v4.html”,
// `components/cal-v4.jsx` (`C4Arc`). Doba 06–23 rozpięta na 270° otwartych
// u dołu: dania stoją okrągłymi zdjęciami na swoich godzinach, przebyta
// część doby jest wypełniona, a kropka „teraz” pokazuje, gdzie jesteśmy.
// W dziurze po środku stoi jedno zdanie o tym, co teraz (`CalendarArcCenter`).
//
// Łuk zastąpił poziomą oś (`CalendarDayAxis`) z v2 z jednego powodu: kreska
// przez całą szerokość ekranu zużywała 350 pt na informację, która mieści
// się w kole 230 pt — a to, co zostawało pod nią, i tak było puste. Koło
// oddaje ten sam czas i jeszcze zarabia miejsce na zdanie w środku.
//
// Sześć rzeczy różni ten łuk od makiety:
//
//  1. **Kropka „teraz” nie ma przy sobie godziny.** W makiecie miała —
//     i wtedy trzeba było odsuwać ją od zatłoczonych miejsc, żeby nie
//     wchodziła na zdjęcia. Godzina stoi na pasku stanu telefonu dwa
//     centymetry wyżej, więc pisanie jej drugi raz nic nie wnosi, a psuje
//     rysunek. Zostaje sama kropka.
//  2. **Kropka zmienia barwę, gdy pora coś zrobić.** Terakota znaczy „jesteś
//     tutaj”. Kiedy otwiera się okno gotowania następnego posiłku albo
//     wypada jego pora, kropka przejmuje KOLOR TEJ PORY i zaczyna oddychać —
//     ta sama barwa stoi wtedy w obwódce węzła, w środku łuku i w kółku
//     wiersza na liście. Reguła siedzi w `CalendarDayFocus.nowTint`.
//  3. **Węzły nigdy się nie stykają.** Śniadanie o 8:00 i drugie śniadanie
//     o 8:30 dzieli na podziałce 06–23 jakieś 8° — zlewałyby się w plamę.
//     `Self.spread` rozsuwa je do `minNodeSpacing`, zachowując kolejność dnia
//     i trzymając skrajne w granicach łuku. To ta sama procedura, co na
//     poziomej osi v2, tylko liczona w stopniach zamiast w punktach.
//  4. **Podpis godziny chowa się pod węzłem, nie tylko pod kropką.** Makieta
//     ukrywała „12”, gdy nachodziła na nie kropka „teraz” — ale obiad o 12:00
//     zderzał się z tą samą etykietą dokładnie tak samo.
//  5. **Podziałka idzie co sześć godzin od początku doby**, a nie na sztywno
//     06/12/18/23. Dom, który je śniadanie o 5:00, rozciąga zakres łuku —
//     i wtedy zapisane na sztywno godziny wskazywałyby nie swoje miejsca.
//  6. **Zdjęcie ma wokół siebie prześwit tła.** Zjedzone danie przygasa,
//     a wtedy tor doby prześwitywał przez nie na wylot jak rysa. Krążek tła
//     pod zdjęciem wycina tor tam, gdzie i tak nie miał czego pokazywać.
struct CalendarDayArc: View {
    /// Jeden posiłek na łuku.
    ///
    /// `minutes` nie jest opcjonalne celowo — posiłek bez pory nie ma tu
    /// swojego miejsca w dobie i zostaje na liście pod łukiem (przekąska
    /// „kiedykolwiek”). `status` przychodzi z ekranu, ten sam, którym rysuje
    /// się kółko w wierszu: łuk i lista nie mogą się różnić w tym, który
    /// posiłek jest „następny”.
    struct Node: Identifiable {
        let id: String
        let slot: MealSlot
        /// Minuty od północy — z rozkładu gospodarstwa (`MealSlotSchedule`).
        let minutes: Int
        /// Kalorie na jedną osobę, policzone tak samo jak pigułka celu.
        let kcal: Int
        let status: CalendarMealStatus
        let title: String
        let imageURL: URL?
    }

    /// Węzły dnia; kolejność nie ma znaczenia, łuk sortuje po godzinie.
    let nodes: [Node]
    /// Bieżąca godzina w minutach od północy — `nil` dla dnia, który nie jest
    /// dzisiaj. Ekran podaje ją z jednego zegara, wspólnego z listą posiłków.
    let nowMinutes: Int?
    /// Dzień miniony ma całą trasę przebytą, przyszły — żadnej.
    let isPast: Bool
    /// Co powiedzieć w dziurze po środku i jaką barwę ma mieć kropka „teraz”.
    let focus: CalendarDayFocus
    /// Średnica planszy. Projektowe 232 pt na pełnym ekranie; krótsze telefony
    /// dostają mniej, żeby łuk nie zjadł całej listy pod sobą.
    var size: CGFloat = CalendarDayArc.defaultSize
    let onTap: (Node) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Łuk stoi poza `DayPager`, ale furtka nic nie kosztuje i chroni przed
    /// przeniesieniem komponentu na stronę dnia w przyszłości.
    @Environment(\.dayPagerGate) private var pagerGate

    /// Czy tor zdążył się już „dojechać” do teraz.
    ///
    /// Pierwsze wejście na ekran rysuje wypełnienie od początku doby do
    /// kropki — ten jeden ruch tłumaczy, co ten łuk w ogóle znaczy, lepiej
    /// niż jakikolwiek podpis. Potem `didDraw` zostaje na zawsze prawdą, więc
    /// powrót z innej zakładki nie odgrywa animacji od nowa.
    @State private var didDraw = false

    // MARK: - Wymiary

    /// Projektowa średnica planszy — z makiety.
    static let defaultSize: CGFloat = 232
    /// Najmniejsza, przy której środek jeszcze mieści zdanie.
    static let minSize: CGFloat = 180

    /// Doba rysowana domyślnie. Posiłek spoza tych godzin rozciąga zakres,
    /// zamiast wypaść poza łuk.
    static let dayStart = 6 * 60
    static let dayEnd = 23 * 60

    /// Łuk zaczyna się w lewym dolnym rogu i idzie 270° zgodnie z ruchem
    /// wskazówek zegara, kończąc w prawym dolnym. Kąty liczone jak w SwiftUI:
    /// 0° w prawo, rosnące w dół.
    private static let startAngle: Double = 135
    private static let sweep: Double = 270

    /// Prześwit między dwoma zdjęciami stojącymi obok siebie na torze.
    /// Osiem, nie sześć — patrz `minNodeSpacing`.
    private static let nodeGap: CGFloat = 8
    /// Jak blisko musi stanąć węzeł albo kropka, żeby zgasić podpis godziny.
    private static let tickHideDegrees: Double = 16

    private var c: CGFloat { size / 2 }
    /// Promień, na którym stoją podpisy godzin — tuż przy krawędzi planszy.
    private var hourRadius: CGFloat { c - 9 }
    /// Promień toru. Liczony OD KRAWĘDZI do środka, a nie odwrotnie: podpis
    /// godziny musi się zmieścić na planszy także wtedy, gdy łuk zjeżdża do
    /// 180 pt, a to on jest najdalej od środka.
    private var radius: CGFloat { hourRadius - nodeSize * 0.52 }
    private var nodeSize: CGFloat { (size * 34 / CalendarDayArc.defaultSize).rounded() }
    private var trackWidth: CGFloat { max(5, size * 8 / CalendarDayArc.defaultSize) }
    private var dotSize: CGFloat { max(9, (size * 11 / CalendarDayArc.defaultSize).rounded()) }
    /// Pismo w środku zjeżdża razem z planszą, ale nie poniżej 0,82 —
    /// mniejsze przestaje być czytelne, a i tak ma własny `minimumScaleFactor`.
    private var textScale: CGFloat { min(1, max(0.82, size / CalendarDayArc.defaultSize)) }

    /// Sinus kąta startowego — o tyle poniżej środka wypadają oba końce łuku.
    private static let endsSin: CGFloat = 0.7071

    /// Pusty pas nad rysunkiem, oddawany układowi. Łuk jest okrągły, a jego
    /// pudełko kwadratowe — bez tego nad zdjęciem najwyższego węzła zostawał
    /// pas powietrza, którego nikt nie zamawiał.
    private var topTrim: CGFloat { max(0, c - radius - nodeSize / 2 - 2) }

    /// To samo pod spodem, i jest go dużo więcej: łuk jest otwarty u dołu,
    /// więc dolna ćwiartka pudełka nie ma czego rysować.
    private var bottomTrim: CGFloat {
        let nodeLow = c + radius * Self.endsSin + nodeSize / 2
        let labelLow = c + hourRadius * Self.endsSin + 8
        return max(0, size - max(nodeLow, labelLow) - 2)
    }

    // MARK: - Body

    var body: some View {
        let placed = layout()

        ZStack {
            track
            elapsedTrack

            ForEach(hourTicks, id: \.self) { hour in
                hourLabel(hour, hidden: isTickHidden(hour, placed: placed))
            }

            ForEach(placed) { item in
                nodeButton(item)
            }

            nowDot

            CalendarArcCenter(focus: focus, scale: textScale)
                .frame(width: (size * 0.62).rounded())
                .position(x: c, y: c)
        }
        .frame(width: size, height: size)
        .padding(.top, -topTrim)
        .padding(.bottom, -bottomTrim)
        // Zmiana dnia przeprowadza węzły tą samą sprężyną, którą jedzie
        // strona dnia i podkreślenie na pasku — jeden ruch na jedną czynność.
        .animation(DayNavigationMotion.spring, value: fingerprint(placed))
        .onAppear { startDrawing() }
        .accessibilityElement(children: .contain)
    }

    /// Wypełnienie toru rusza dopiero po zamontowaniu planszy — inaczej
    /// pierwsza klatka miałaby je już na miejscu i nie byłoby czego animować.
    private func startDrawing() {
        guard !didDraw else { return }
        guard !reduceMotion else {
            didDraw = true
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            didDraw = true
        }
    }

    // MARK: - Tor doby

    /// Pusty tor całej doby.
    ///
    /// `Circle().trim(from: 0, …)` ZACZYNA SIĘ NA GODZINIE TRZECIEJ, nie na
    /// dwunastej — `CGPath(ellipseIn:)` startuje w punkcie `(maxX, midY)`
    /// i idzie zgodnie z ruchem wskazówek zegara. Dlatego obrót to dokładnie
    /// `startAngle`, a nie `startAngle + 90`: kąty w tym pliku liczą się
    /// w tej samej konwencji, co punkty na łuku (0° w prawo, rosnące w dół),
    /// więc tor i węzły muszą wychodzić z tej samej liczby. Dołożone 90°
    /// przekręcało sam tor o ćwierć obrotu i otwarcie łuku wypadało z lewej
    /// zamiast u dołu — zdjęcia stały wtedy w powietrzu, obok kreski.
    private var track: some View {
        Circle()
            .trim(from: 0, to: Self.sweep / 360)
            .stroke(
                Color.scLabel(scheme).opacity(0.10),
                style: StrokeStyle(lineWidth: trackWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(Self.startAngle))
            .frame(width: radius * 2, height: radius * 2)
    }

    /// Przebyta część doby.
    ///
    /// Widok stoi ZAWSZE, także przy zerowym wypełnieniu — inaczej pierwsze
    /// wejście na ekran wstawiałoby go od razu w docelowej długości i nie
    /// byłoby czego animować. Kryciem, a nie istnieniem, bo zaokrąglona
    /// końcówka potrafi przy zerowej długości zostawić kropkę na starcie łuku.
    private var elapsedTrack: some View {
        let drawn = didDraw ? elapsed : 0
        let motion: Animation? = reduceMotion ? nil : .easeOut(duration: 0.85)

        return Circle()
            .trim(from: 0, to: (Self.sweep / 360) * drawn)
            .stroke(
                Color.scLabel(scheme).opacity(scheme == .dark ? 0.26 : 0.28),
                style: StrokeStyle(lineWidth: trackWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(Self.startAngle))
            .frame(width: radius * 2, height: radius * 2)
            .opacity(drawn > 0.001 ? 1 : 0)
            .animation(motion, value: drawn)
    }

    /// Ile doby jest już za nami: cała (dzień miniony), do kropki (dzisiaj)
    /// albo nic (dzień przyszły).
    private var elapsed: Double {
        if isPast { return 1 }
        guard let nowMinutes else { return 0 }
        return progress(forMinutes: nowMinutes)
    }

    // MARK: - Podziałka godzin

    /// Godziny podpisane na łuku: co sześć od początku doby plus jej koniec.
    ///
    /// Domyślny zakres 06–23 daje dokładnie 06/12/18/23 z makiety. Dom, który
    /// je poza tymi godzinami, rozciąga zakres — i wtedy podziałka jedzie za
    /// nim, zamiast wskazywać nie swoje miejsca. Przedostatni podpis znika,
    /// jeśli stanąłby zbyt blisko końcowego.
    private var hourTicks: [Int] {
        let bounds = domain
        let lower = bounds.lower / 60
        let upper = bounds.upper / 60
        guard upper > lower else { return [lower] }

        var ticks: [Int] = []
        var hour = lower
        while hour < upper {
            ticks.append(hour)
            hour += 6
        }
        if let last = ticks.last, upper - last < 3 {
            ticks.removeLast()
        }
        ticks.append(upper)
        return ticks
    }

    /// Podpis godziny. Gaśnie kryciem, a nie zniknięciem: kropka „teraz”
    /// dojeżdża do „12” po minucie i wtedy etykieta ma zblednąć, a nie
    /// mrugnąć. Zdejmowanie widoku z drzewa dawałoby to drugie, bo insercja
    /// i usunięcie animują się tylko wtedy, gdy zmiana leci w animowanej
    /// transakcji — a zegar tyka poza nią.
    private func hourLabel(_ hour: Int, hidden: Bool) -> some View {
        Text(String(format: "%02d", hour))
            .font(.system(size: max(9, 9.5 * textScale), weight: .bold))
            .monospacedDigit()
            .tracking(0.5)
            .foregroundStyle(Color.scLabel(scheme).opacity(scheme == .dark ? 0.30 : 0.36))
            .fixedSize()
            .opacity(hidden ? 0 : 1)
            .animation(.easeInOut(duration: 0.28), value: hidden)
            .position(point(angle(forMinutes: hour * 60), radius: hourRadius))
            .accessibilityHidden(true)
    }

    /// Podpis godziny gaśnie, gdy stoi na nim zdjęcie albo kropka „teraz”.
    /// Podziałka jest tłem dla treści, a nie odwrotnie.
    private func isTickHidden(_ hour: Int, placed: [Placed]) -> Bool {
        let tick = angle(forMinutes: hour * 60)

        if let nowMinutes,
           abs(angle(forMinutes: nowMinutes) - tick) < Self.tickHideDegrees {
            return true
        }
        return placed.contains { abs($0.degrees - tick) < Self.tickHideDegrees }
    }

    // MARK: - Węzły

    private struct Placed: Identifiable {
        let node: Node
        let degrees: Double
        var id: String { node.id }
    }

    private func nodeButton(_ item: Placed) -> some View {
        Button {
            pagerGate.ifNotSwiping { onTap(item.node) }
        } label: {
            thumbnail(item.node)
                .scTapTarget(44, drawn: nodeSize)
        }
        .buttonStyle(ArcNodePressStyle())
        .position(point(item.degrees, radius: radius))
        .transition(.opacity.combined(with: .scale(scale: 0.86, anchor: .center)))
        .accessibilityLabel(accessibilityLabel(item.node))
        .accessibilityHint("Otwiera szczegóły posiłku")
    }

    private func thumbnail(_ node: Node) -> some View {
        Group {
            if let url = node.imageURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallback(node.slot)
                    }
                }
            } else {
                fallback(node.slot)
            }
        }
        .frame(width: nodeSize, height: nodeSize)
        .clipShape(Circle())
        // Zjedzone przygasa — zostaje czytelne, ale przestaje konkurować
        // z tym, co dopiero przed użytkownikiem. Ta sama reguła co w wierszu.
        .saturation(node.status.isEaten ? 0.45 : 1)
        .opacity(node.status.isEaten ? 0.82 : 1)
        .overlay(
            Circle()
                .strokeBorder(ringColor(node), lineWidth: node.status == .next ? 2 : 1)
        )
        // Krążek tła szerszy od zdjęcia wycina pod nim tor doby. Zjedzone
        // danie przygasa, a wtedy kreska przechodząca pod spodem prześwitywała
        // przez nie jak rysa na ekranie.
        .background(
            Circle()
                .fill(Color.scPageBase(scheme))
                .padding(-2.5)
        )
        .overlay(alignment: .bottomTrailing) {
            if node.status.isEaten { eatenBadge }
        }
        .animation(.smooth(duration: 0.24), value: node.status)
    }

    private func fallback(_ slot: MealSlot) -> some View {
        ZStack {
            LinearGradient(
                colors: [slot.cozyTint, slot.cozyTint.mix(with: .black, by: 0.40)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: slot.icon)
                .font(.system(size: nodeSize * 0.36, weight: .light))
                .foregroundStyle(Color.white.opacity(0.65))
        }
    }

    /// Pieczątka zjedzenia — ten sam znak co w wierszu posiłku, tyle że
    /// wielkości guzika od koszuli.
    ///
    /// Krążek bierze kolor TŁA, ptaszek kolor pisma — odwrotnie, niż odruch
    /// podpowiada. Pieczątka siedzi w rogu zdjęcia, więc musi się z niego
    /// wyciąć, a jasny krążek na jasnym daniu byłby kolejną plamą światła
    /// w miejscu, które ma przygasać.
    private var eatenBadge: some View {
        Image(systemName: "checkmark.circle.fill")
            .symbolRenderingMode(.palette)
            .font(.system(size: max(11, nodeSize * 0.4), weight: .bold))
            .foregroundStyle(Color.scChecked(scheme).opacity(0.9), Color.scPageBase(scheme))
            .offset(x: 2, y: 2)
            .transition(.scale(scale: 0.4).combined(with: .opacity))
    }

    private func ringColor(_ node: Node) -> Color {
        switch node.status {
        case .eaten: return Color.scChecked(scheme).opacity(0.28)
        case .next:  return node.slot.cozyAccent
        default:     return Color.scTileStroke(scheme)
        }
    }

    private func accessibilityLabel(_ node: Node) -> String {
        var parts = [
            node.slot.title,
            MealSlotSchedule.format(node.minutes),
            node.title,
            "\(node.kcal) kcal"
        ]
        if node.status.isEaten { parts.append("zjedzone") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Kropka „teraz”

    @ViewBuilder
    private var nowDot: some View {
        let motion: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.6)

        if let nowMinutes {
            CalendarNowDot(
                tint: focus.nowTint,
                ring: Color.scPageBase(scheme),
                diameter: dotSize,
                isUrgent: focus.isUrgent && !reduceMotion
            )
            .position(point(angle(forMinutes: nowMinutes), radius: radius))
            // Kropka pełznie po torze co minutę — bez tego przeskakiwałaby
            // skokiem o pół punktu, co przy oglądaniu ekranu na żywo widać
            // jako drgnięcie.
            .animation(motion, value: nowMinutes)
            .zIndex(3)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Geometria

    /// Zakres doby, który łuk ma pokryć. Domyślnie 06–23 jak w makiecie,
    /// rozciągany, gdy dom je poza tymi godzinami.
    ///
    /// „Teraz” zakresu NIE rozciąga: o 02:00 kropka siada na początku łuku
    /// i to jest prawda („doba jeszcze się nie zaczęła”), a rozciągnięcie
    /// przestawiłoby całą podziałkę w środku nocy.
    private var domain: (lower: Int, upper: Int) {
        let minutes = nodes.map(\.minutes)
        let lower = min(Self.dayStart, minutes.min() ?? Self.dayStart)
        let upper = max(Self.dayEnd, minutes.max() ?? Self.dayEnd)
        return (lower, max(upper, lower + 1))
    }

    private func progress(forMinutes minutes: Int) -> Double {
        let bounds = domain
        let span = Double(bounds.upper - bounds.lower)
        let ratio = Double(minutes - bounds.lower) / span
        return min(1, max(0, ratio))
    }

    private func angle(forMinutes minutes: Int) -> Double {
        Self.startAngle + Self.sweep * progress(forMinutes: minutes)
    }

    /// Punkt na okręgu o zadanym promieniu, liczony od środka planszy.
    ///
    /// Obrót wektora `(r, 0)` zamiast wprost `cos`/`sin`: `CGAffineTransform`
    /// przychodzi z CoreGraphics razem ze SwiftUI, a funkcje trygonometryczne
    /// z `Darwin` przez Foundation — a ten projekt ma włączone
    /// `MemberImportVisibility` i lepiej nie zakładać, co przez co widać.
    /// Rachunek jest ten sam: x' = r·cos θ, y' = r·sin θ.
    private func point(_ degrees: Double, radius r: CGFloat) -> CGPoint {
        let radians = CGFloat(degrees * Double.pi / 180)
        let spoke = CGPoint(x: r, y: 0)
            .applying(CGAffineTransform(rotationAngle: radians))
        return CGPoint(x: c + spoke.x, y: c + spoke.y)
    }

    /// Najmniejszy kąt między środkami dwóch zdjęć, przy którym zostaje
    /// między nimi `nodeGap` prześwitu.
    ///
    /// Liczone po ŁUKU, nie po cięciwie — a łuk jest zawsze dłuższy niż
    /// cięciwa, więc wychodzi z tego odstęp odrobinę ciaśniejszy, niż
    /// wyglądałoby to na oko. Stąd `nodeGap` z zapasem: przy 232 pt planszy
    /// różnica między jednym a drugim rachunkiem to pół punktu.
    private var minNodeSpacing: Double {
        Double(nodeSize + Self.nodeGap) / Double(radius) * 180 / Double.pi
    }

    private func layout() -> [Placed] {
        let sorted = nodes.sorted { $0.minutes < $1.minutes }
        guard !sorted.isEmpty else { return [] }

        let degrees = Self.spread(
            ideal: sorted.map { angle(forMinutes: $0.minutes) },
            minSpacing: minNodeSpacing,
            lower: Self.startAngle,
            upper: Self.startAngle + Self.sweep
        )
        return sorted.indices.map { Placed(node: sorted[$0], degrees: degrees[$0]) }
    }

    /// Odcisk zawartości łuku — po nim animuje się podmiana dnia i odhaczenie
    /// posiłku. Sama data w nim nie siedzi: przy dwóch dniach o identycznym
    /// zestawie posiłków nie ma czego animować.
    private func fingerprint(_ placed: [Placed]) -> String {
        placed
            .map { "\($0.node.id):\(Int($0.degrees.rounded())):\($0.node.status)" }
            .joined(separator: "|")
    }

    /// Rozsuwa węzły tak, żeby żadne dwa nie stały bliżej niż `minSpacing`,
    /// nie ruszając ich kolejności i nie wypuszczając poza `lower…upper`.
    ///
    /// Przejście w przód dopycha każdy węzeł za poprzednika; jeśli ostatni
    /// wyjdzie za koniec łuku, przejście w tył ściąga cały ogon z powrotem.
    /// Gdy węzłów jest tyle, że nie mieszczą się nawet ciasno upakowane,
    /// proporcje przestają cokolwiek znaczyć i rozkładamy je równo — lepiej
    /// stracić informację o godzinie niż zlepić zdjęcia w jedną plamę.
    ///
    /// `static` i bez `self`, żeby dało się to przeczytać (i policzyć
    /// w głowie) w oderwaniu od widoku. Ta sama procedura jechała na
    /// poziomej osi v2, tylko w punktach zamiast w stopniach.
    static func spread(
        ideal: [Double],
        minSpacing: Double,
        lower: Double,
        upper: Double
    ) -> [Double] {
        guard !ideal.isEmpty else { return [] }
        guard ideal.count > 1 else { return [min(max(ideal[0], lower), upper)] }

        let span = upper - lower
        let needed = Double(ideal.count - 1) * minSpacing
        guard needed <= span else {
            let step = span / Double(ideal.count - 1)
            return ideal.indices.map { lower + Double($0) * step }
        }

        var values = ideal.map { min(max($0, lower), upper) }
        for index in 1..<values.count {
            values[index] = max(values[index], values[index - 1] + minSpacing)
        }

        if let last = values.last, last > upper {
            values[values.count - 1] = upper
            for index in stride(from: values.count - 2, through: 0, by: -1) {
                values[index] = min(values[index], values[index + 1] - minSpacing)
            }
        }
        return values
    }
}

// MARK: - Kropka „teraz”

/// Terakotowa kropka na torze doby — albo w kolorze pory, gdy właśnie ona
/// jest na tapecie.
///
/// Obwódka jest w kolorze tła strony, nie w kolorze kropki: kropka siedzi
/// NA torze i musiałaby się z nim zlać, a wycięcie tła wokół niej odcina ją
/// od wszystkiego, po czym akurat przejeżdża — od toru i od zdjęcia dania,
/// jeśli akurat na nie wejdzie.
///
/// Poświata oddycha wyłącznie wtedy, gdy jest co zrobić (pora gotować, pora
/// jeść). Osobny widok, a nie modyfikator na kropce, bo `repeatForever`
/// musi się urodzić i umrzeć razem z powodem — animacja bez końca doczepiona
/// do widoku, który zostaje na ekranie, potrafi przeżyć swój warunek.
private struct CalendarNowDot: View {
    let tint: Color
    let ring: Color
    let diameter: CGFloat
    let isUrgent: Bool

    var body: some View {
        ZStack {
            if isUrgent {
                PulsingHalo(tint: tint, diameter: diameter)
            }

            Circle()
                .fill(tint)
                .frame(width: diameter, height: diameter)
                .overlay(
                    Circle().strokeBorder(ring, lineWidth: 2.5)
                        .padding(-2.5)
                )
        }
        // Barwa przechodzi płynnie: kropka nie „przeskakuje” z terakoty
        // w kolor pory, tylko dojrzewa do niego przez ćwierć sekundy.
        .animation(.smooth(duration: 0.45), value: tint)
        .animation(.smooth(duration: 0.3), value: isUrgent)
    }

    /// Poświata, która rośnie i gaśnie. Trzyma własny stan, więc każde
    /// wejście w tryb pilny zaczyna oddech od początku.
    ///
    /// Ramka jest STAŁA, a oddycha `scaleEffect` i krycie: rosnąca ramka
    /// zmieniałaby co klatkę rozmiar kontenera pod `position`, czyli kazałaby
    /// układowi przeliczać się przez cały czas trwania animacji bez końca.
    /// Skala i krycie są czystym rysowaniem — układ ich nie widzi.
    private struct PulsingHalo: View {
        let tint: Color
        let diameter: CGFloat

        @State private var expanded = false

        var body: some View {
            Circle()
                .fill(tint)
                .frame(width: diameter * 2.9, height: diameter * 2.9)
                .scaleEffect(expanded ? 1 : 0.6)
                .opacity(expanded ? 0.10 : 0.32)
                .animation(
                    .easeInOut(duration: 1.7).repeatForever(autoreverses: true),
                    value: expanded
                )
                .onAppear { expanded = true }
                .transition(.opacity)
        }
    }
}

// MARK: - Dotknięcie węzła

/// Dotknięcie węzła łuku: samo ściśnięcie, bez zmiany krycia.
///
/// `PlainButtonStyle` (i wspólny `PlanPressStyle`) przygaszają etykietę do
/// ~0,72 — na wierszu z tłem to czytelna reakcja, ale tutaj etykietą jest
/// okrągłe zdjęcie leżące NA torze doby, więc przygaszenie odsłaniało pod
/// nim to, co akurat było głębiej.
private struct ArcNodePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

#Preview("Łuk doby — dzisiaj") {
    let nodes = [
        CalendarDayArc.Node(
            id: "sn", slot: .breakfast, minutes: 8 * 60, kcal: 510,
            status: .eaten, title: "Owsianka kakaowa", imageURL: nil
        ),
        CalendarDayArc.Node(
            id: "ii", slot: .secondBreakfast, minutes: 10 * 60 + 30, kcal: 340,
            status: .next, title: "Jogurt z granolą", imageURL: nil
        ),
        CalendarDayArc.Node(
            id: "ob", slot: .lunch, minutes: 14 * 60, kcal: 604,
            status: .later, title: "Indyk z ziemniakami", imageURL: nil
        ),
        CalendarDayArc.Node(
            id: "ko", slot: .dinner, minutes: 20 * 60, kcal: 480,
            status: .later, title: "Pierogi z truskawkami", imageURL: nil
        )
    ]

    let next = CalendarDayFocus.NextMeal(
        slot: .secondBreakfast,
        time: "10:30",
        kcal: 340,
        minutesAway: 49,
        prepMinutes: 5,
        cookFrom: nil
    )

    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()

        VStack(spacing: 20) {
            CalendarDayArc(
                nodes: nodes,
                nowMinutes: 9 * 60 + 41,
                isPast: false,
                focus: .next(next),
                onTap: { _ in }
            )

            CalendarDayArc(
                nodes: [],
                nowMinutes: 9 * 60 + 41,
                isPast: false,
                focus: .empty,
                size: CalendarDayArc.minSize,
                onTap: { _ in }
            )
        }
        .padding(.horizontal, SCPageMetrics.horizontal)
    }
    .preferredColorScheme(.dark)
}
