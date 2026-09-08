import SwiftUI

// Kalendarz v2 — pozioma oś dnia.
//
// Źródło: canvas claude.ai → „Weekly Meals - Kalendarz v2 D6.html”,
// `components/cal-v2-d.jsx` (`CalDAxis`). Doba jako jedna kreska: węzeł to
// okrągłe zdjęcie dania stojące na swojej godzinie, kalorie nad nim, godzina
// pod nim, a terakotowy znacznik „teraz” tylko na dzisiaj.
//
// Trzy rzeczy różnią tę oś od makiety:
//
//  1. **Oś jest przypięta**, tak jak pasek dni — nie jedzie z listą posiłków.
//     Odpowiada na „gdzie w dobie jestem”, a to pytanie nie znika po
//     przewinięciu listy o dwa kafle w dół.
//  2. **Posiłek bez godziny nie ma czego szukać na osi.** Makieta stawiała go
//     kreskowanego w rynnie po prawej — ale rynna to osobna zasada do
//     nauczenia się, a przekąska „kiedykolwiek” i tak stoi na liście niżej.
//     Filtr robi wywołujący: `Node` nie ma opcjonalnej godziny.
//  3. **Węzły nigdy się nie stykają.** Śniadanie o 8:00 i drugie śniadanie
//     o 8:30 dzieli na podziałce 06–23 jakieś 12 pt — zlewały się w plamę,
//     a podpisy godzin nachodziły na siebie. `Self.spread` rozsuwa je do
//     `Metrics.minSpacing`, zachowując kolejność dnia i trzymając skrajne
//     węzły w granicach osi.
struct CalendarDayAxis: View {
    /// Jeden posiłek na osi.
    ///
    /// `minutes` nie jest opcjonalne celowo — posiłek bez pory nie ma tu
    /// miejsca, a opcjonalna godzina wpuszczałaby go z powrotem.
    struct Node: Identifiable {
        let id: String
        let slot: MealSlot
        /// Minuty od północy — z rozkładu gospodarstwa (`MealSlotSchedule`).
        let minutes: Int
        /// Kalorie na jedną osobę, policzone tak samo jak licznik dnia.
        let kcal: Int
        let isEaten: Bool
        let title: String
        let imageURL: URL?
    }

    /// Węzły dnia; kolejność nie ma znaczenia, oś sortuje po godzinie.
    let nodes: [Node]
    /// Czy oglądany dzień to dzisiaj — od tego zależy znacznik „teraz”
    /// i to, który posiłek jest „następny”.
    let isToday: Bool
    /// Dzień miniony ma całą trasę przebytą, przyszły — żadnej.
    let isPast: Bool
    let onTap: (Node) -> Void

    @Environment(\.colorScheme) private var scheme
    /// Oś stoi poza `DayPager`, ale furtka nic nie kosztuje i chroni przed
    /// przeniesieniem komponentu na stronę dnia w przyszłości.
    @Environment(\.dayPagerGate) private var pagerGate

    // MARK: - Wymiary

    private enum Metrics {
        /// Średnica zdjęcia na osi.
        static let node: CGFloat = 30
        /// Pasmo nad zdjęciem. Mieści dwa piętra: znacznik „teraz” pod samą
        /// górą i kalorie tuż nad zdjęciem, więc nigdy nie piszą po sobie.
        static let band: CGFloat = 32
        static let nowLabel: CGFloat = 13
        static let kcalLabel: CGFloat = 13
        static let timeGap: CGFloat = 5
        static let timeLabel: CGFloat = 14
        /// Szerokość kolumny węzła — mierzona podpisem godziny („08:00”),
        /// bo to on, a nie zdjęcie, jest tu najszerszy.
        static let column: CGFloat = 44
        /// Najmniejszy rozstaw środków. O 2 pt większy od kolumny, żeby
        /// sąsiednie podpisy dzielił prześwit, a nie sama styczność.
        static let minSpacing: CGFloat = 46

        static var trackY: CGFloat { band + node / 2 }
        static var height: CGFloat { band + node + timeGap + timeLabel }

        /// Doba rysowana domyślnie — jak w makiecie. Posiłek spoza tych
        /// godzin rozciąga zakres, zamiast wypaść poza oś.
        static let dayStart = 6 * 60
        static let dayEnd = 23 * 60
    }

    /// Stan węzła względem „teraz”. Miniony i przyszły dzień nie mają
    /// „następnego” — tam wszystko, co nieodhaczone, jest po prostu planem.
    private enum Status {
        case eaten, next, planned
    }

    private struct Placed: Identifiable {
        let node: Node
        let x: CGFloat
        let status: Status
        var id: String { node.id }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isToday {
                // Minuta wystarczy: oś ma podziałkę godzinową, więc częstsze
                // odświeżanie i tak nie przesunęłoby znacznika o piksel.
                TimelineView(.everyMinute) { context in
                    axis(nowMinutes: Self.minutes(from: context.date))
                }
            } else {
                axis(nowMinutes: nil)
            }
        }
        .frame(height: Metrics.height)
    }

    private func axis(nowMinutes: Int?) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let placed = layout(width: width)
            let nowX = nowMinutes.map { x(forMinutes: $0, width: width) }

            ZStack(alignment: .topLeading) {
                track(width: width, elapsedTo: elapsedWidth(nowX: nowX, width: width))

                if let nowX, let nowMinutes {
                    nowMarker(minutes: nowMinutes)
                        .offset(x: nowX - Metrics.column / 2, y: 0)
                }

                ForEach(placed) { item in
                    nodeView(item)
                        .offset(x: item.x - Metrics.column / 2, y: 0)
                }
            }
            .frame(width: width, height: Metrics.height, alignment: .topLeading)
        }
        // Zmiana dnia przeprowadza węzły tą samą sprężyną, którą jedzie
        // strona dnia i podkreślenie na pasku — jeden ruch na jedną czynność.
        .animation(DayNavigationMotion.spring, value: fingerprint)
    }

    /// Odcisk zawartości osi — po nim animuje się podmiana dnia i odhaczenie
    /// posiłku. Sama data w nim nie siedzi: przy dwóch dniach o identycznym
    /// zestawie posiłków nie ma czego animować.
    private var fingerprint: String {
        nodes
            .sorted { $0.minutes < $1.minutes }
            .map { "\($0.id):\($0.minutes):\($0.isEaten ? 1 : 0)" }
            .joined(separator: "|")
    }

    // MARK: - Kreska

    private func track(width: CGFloat, elapsedTo elapsed: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.scRule(scheme))
                .frame(width: width, height: 2)

            if elapsed > 0 {
                Capsule()
                    .fill(Color.scFaint(scheme))
                    .frame(width: min(elapsed, width), height: 2)
            }
        }
        .frame(width: width, height: 2, alignment: .leading)
        .offset(y: Metrics.trackY - 1)
    }

    /// Ile trasy dnia jest już za nami: cała (dzień miniony), do znacznika
    /// (dzisiaj) albo nic (dzień przyszły).
    private func elapsedWidth(nowX: CGFloat?, width: CGFloat) -> CGFloat {
        if isPast { return width }
        return nowX ?? 0
    }

    private func nowMarker(minutes: Int) -> some View {
        VStack(spacing: 2) {
            Text(MealSlotSchedule.format(minutes))
                .font(.system(size: 10.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(SCPalette.terracotta)
                .lineLimit(1)
                .frame(height: Metrics.nowLabel)

            Capsule()
                .fill(SCPalette.terracotta)
                .frame(width: 2, height: Metrics.trackY - Metrics.nowLabel - 2)
        }
        .frame(width: Metrics.column, alignment: .center)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Węzeł

    private func nodeView(_ item: Placed) -> some View {
        Button {
            pagerGate.ifNotSwiping { onTap(item.node) }
        } label: {
            VStack(spacing: 0) {
                Text("\(item.node.kcal)")
                    .font(.system(size: 10.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(kcalColor(item.status))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(height: Metrics.kcalLabel)
                    .padding(.bottom, 3)
                    .frame(height: Metrics.band, alignment: .bottom)

                thumbnail(item)

                Text(MealSlotSchedule.format(item.node.minutes))
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(timeColor(item.status))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(height: Metrics.timeGap + Metrics.timeLabel, alignment: .bottom)
            }
            .frame(width: Metrics.column, height: Metrics.height, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .center)))
        .accessibilityLabel(accessibilityLabel(item))
        .accessibilityHint("Otwiera szczegóły posiłku")
    }

    private func thumbnail(_ item: Placed) -> some View {
        Group {
            if let url = item.node.imageURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallback(item.node.slot)
                    }
                }
            } else {
                fallback(item.node.slot)
            }
        }
        .frame(width: Metrics.node, height: Metrics.node)
        .clipShape(Circle())
        // Zjedzone przygasa — zostaje czytelne, ale przestaje konkurować
        // z tym, co dopiero przed użytkownikiem. Ta sama reguła co na kaflu.
        .saturation(item.status == .eaten ? 0.45 : 1)
        .opacity(item.status == .eaten ? 0.8 : 1)
        .overlay(
            Circle()
                .strokeBorder(ringColor(item), lineWidth: item.status == .next ? 2 : 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if item.status == .eaten { eatenBadge }
        }
    }

    private func fallback(_ slot: MealSlot) -> some View {
        ZStack {
            LinearGradient(
                colors: [slot.cozyTint, slot.cozyTint.mix(with: .black, by: 0.40)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: slot.icon)
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(Color.white.opacity(0.65))
        }
    }

    /// Pieczątka zjedzenia — ten sam znak co na kaflu posiłku, tyle że
    /// wielkości guzika od koszuli. Wypełnienie kółka bierze kolor tła
    /// strony, więc pieczątka odcina się od zdjęcia bez dodatkowej obwódki.
    private var eatenBadge: some View {
        Image(systemName: "checkmark.circle.fill")
            .symbolRenderingMode(.palette)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.scPageBase(scheme), SCPalette.sage)
            .offset(x: 2, y: 2)
    }

    // MARK: - Barwy stanu

    private func ringColor(_ item: Placed) -> Color {
        switch item.status {
        case .eaten:   return SCPalette.sage.opacity(0.55)
        case .next:    return item.node.slot.cozyAccent
        case .planned: return Color.scTileStroke(scheme)
        }
    }

    private func kcalColor(_ status: Status) -> Color {
        switch status {
        case .eaten:   return SCPalette.sage
        case .next:    return Color.scLabel(scheme)
        case .planned: return Color.scFaint(scheme)
        }
    }

    private func timeColor(_ status: Status) -> Color {
        switch status {
        case .eaten:   return SCPalette.sage
        case .next:    return Color.scLabel(scheme)
        case .planned: return Color.scFaint(scheme)
        }
    }

    private func accessibilityLabel(_ item: Placed) -> String {
        var parts = [
            item.node.slot.title,
            MealSlotSchedule.format(item.node.minutes),
            item.node.title,
            "\(item.node.kcal) kcal"
        ]
        if item.status == .eaten { parts.append("zjedzone") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Rozkład

    /// Zakres doby, który oś ma pokryć. Domyślnie 06–23 jak w makiecie,
    /// rozciągany, gdy dom je poza tymi godzinami.
    private var domain: (lower: Int, upper: Int) {
        let minutes = nodes.map(\.minutes)
        let lower = min(Metrics.dayStart, minutes.min() ?? Metrics.dayStart)
        let upper = max(Metrics.dayEnd, minutes.max() ?? Metrics.dayEnd)
        // Zakres zerowej długości jest niemożliwy (06 < 23), ale dzielimy
        // przez tę różnicę, więc lepiej to powiedzieć wprost.
        return (lower, max(upper, lower + 1))
    }

    /// Godzina → punkt na osi. Skrajne węzły siadają o pół kolumny od
    /// krawędzi, żeby podpis „23:00” nie wypadł poza margines strony.
    private func x(forMinutes minutes: Int, width: CGFloat) -> CGFloat {
        let half = Metrics.column / 2
        let lower = half
        let upper = max(half, width - half)
        let bounds = domain
        let ratio = Double(minutes - bounds.lower) / Double(bounds.upper - bounds.lower)
        let clamped = min(max(ratio, 0), 1)
        return lower + (upper - lower) * clamped
    }

    private func layout(width: CGFloat) -> [Placed] {
        let sorted = nodes.sorted { $0.minutes < $1.minutes }
        guard !sorted.isEmpty, width > 0 else { return [] }

        let half = Metrics.column / 2
        let ideal = sorted.map { x(forMinutes: $0.minutes, width: width) }
        let xs = Self.spread(
            ideal: ideal,
            minSpacing: Metrics.minSpacing,
            lower: half,
            upper: max(half, width - half)
        )

        // „Następny” istnieje tylko dzisiaj: w minionym dniu nic już nie
        // nadchodzi, a w przyszłym wszystko jest równie odległe.
        var nextTaken = !isToday
        return sorted.indices.map { index in
            let node = sorted[index]
            let status: Status
            if node.isEaten {
                status = .eaten
            } else if !nextTaken {
                nextTaken = true
                status = .next
            } else {
                status = .planned
            }
            return Placed(node: node, x: xs[index], status: status)
        }
    }

    /// Rozsuwa węzły tak, żeby żadne dwa nie stały bliżej niż `minSpacing`,
    /// nie ruszając ich kolejności i nie wypuszczając poza `lower…upper`.
    ///
    /// Przejście w przód dopycha każdy węzeł za poprzednika; jeśli ostatni
    /// wyjdzie za prawą krawędź, przejście w tył ściąga cały ogon z powrotem.
    /// Gdy węzłów jest tyle, że nie mieszczą się nawet ciasno upakowane,
    /// proporcje przestają cokolwiek znaczyć i rozkładamy je równo — lepiej
    /// stracić informację o godzinie niż zlepić podpisy w jedną plamę.
    ///
    /// `static` i bez `self`, żeby dało się to przeczytać (i policzyć
    /// w głowie) w oderwaniu od widoku.
    static func spread(
        ideal: [CGFloat],
        minSpacing: CGFloat,
        lower: CGFloat,
        upper: CGFloat
    ) -> [CGFloat] {
        guard !ideal.isEmpty else { return [] }
        guard ideal.count > 1 else { return [min(max(ideal[0], lower), upper)] }

        let span = upper - lower
        let needed = CGFloat(ideal.count - 1) * minSpacing
        guard needed <= span else {
            let step = span / CGFloat(ideal.count - 1)
            return ideal.indices.map { lower + CGFloat($0) * step }
        }

        var xs = ideal.map { min(max($0, lower), upper) }
        for index in 1..<xs.count {
            xs[index] = max(xs[index], xs[index - 1] + minSpacing)
        }

        if let last = xs.last, last > upper {
            xs[xs.count - 1] = upper
            for index in stride(from: xs.count - 2, through: 0, by: -1) {
                xs[index] = min(xs[index], xs[index + 1] - minSpacing)
            }
        }
        return xs
    }

    private static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

#Preview("Oś dnia — dzisiaj") {
    let nodes = [
        CalendarDayAxis.Node(
            id: "sn", slot: .breakfast, minutes: 8 * 60, kcal: 510,
            isEaten: true, title: "Owsianka kakaowa", imageURL: nil
        ),
        CalendarDayAxis.Node(
            id: "ii", slot: .secondBreakfast, minutes: 8 * 60 + 30, kcal: 190,
            isEaten: false, title: "Jogurt z granolą", imageURL: nil
        ),
        CalendarDayAxis.Node(
            id: "ob", slot: .lunch, minutes: 14 * 60, kcal: 1208,
            isEaten: false, title: "Indyk z ziemniakami", imageURL: nil
        ),
        CalendarDayAxis.Node(
            id: "ko", slot: .dinner, minutes: 20 * 60, kcal: 900,
            isEaten: false, title: "Pierogi z truskawkami", imageURL: nil
        )
    ]

    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()
        CalendarDayAxis(nodes: nodes, isToday: true, isPast: false, onTap: { _ in })
            .padding(.horizontal, SCPageMetrics.horizontal)
    }
    .preferredColorScheme(.dark)
}
