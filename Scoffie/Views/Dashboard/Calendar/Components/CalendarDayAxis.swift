import SwiftUI

// Kalendarz v2 — pozioma oś dnia.
//
// Źródło: canvas claude.ai → „Weekly Meals - Kalendarz v2 D6.html”,
// `components/cal-v2-d.jsx` (`CalDAxis`). Doba jako jedna kreska: węzeł to
// okrągłe zdjęcie dania stojące na swojej godzinie, kalorie nad nim, godzina
// pod nim, a terakotowy znacznik „teraz” tylko na dzisiaj.
//
// Cztery rzeczy różnią tę oś od makiety:
//
//  1. **Oś jest przypięta**, tak jak pasek dni — nie jedzie z listą posiłków.
//     Odpowiada na „gdzie w dobie jestem”, a to pytanie nie znika po
//     przewinięciu listy o dwa kafle w dół.
//  2. **„Teraz” to kropka na kresce, nie pionowa linia.** Linia z makiety
//     przecinała pasmo kalorii i przy posiłku stojącym blisko bieżącej
//     godziny wyglądała na usterkę rysowania — dwie kreski i dwie liczby
//     w jednym miejscu. Kropka siedzi dokładnie NA kresce, godzina stoi
//     wyśrodkowana nad nią, i to wszystko.
//  3. **Posiłek bez godziny nie ma czego szukać na osi.** Makieta stawiała go
//     kreskowanego w rynnie po prawej — ale rynna to osobna zasada do
//     nauczenia się, a przekąska „kiedykolwiek” i tak stoi na liście niżej.
//     Filtr robi wywołujący: `Node` nie ma opcjonalnej godziny.
//  4. **Węzły nigdy się nie stykają.** Śniadanie o 8:00 i drugie śniadanie
//     o 8:30 dzieli na podziałce 06–23 jakieś 12 pt — zlewały się w plamę,
//     a podpisy godzin nachodziły na siebie. `Self.spread` rozsuwa je do
//     `Metrics.minSpacing`, zachowując kolejność dnia i trzymając skrajne
//     węzły w granicach osi.
struct CalendarDayAxis: View {
    /// Jeden posiłek na osi.
    ///
    /// `minutes` nie jest opcjonalne celowo — posiłek bez pory nie ma tu
    /// miejsca, a opcjonalna godzina wpuszczałaby go z powrotem. `status`
    /// przychodzi z ekranu, ten sam, którym rysuje się checkbox w wierszu:
    /// oś i lista nie mogą się różnić w tym, co jest „następne”.
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

    /// Węzły dnia; kolejność nie ma znaczenia, oś sortuje po godzinie.
    let nodes: [Node]
    /// Bieżąca godzina w minutach od północy — `nil` dla dnia, który nie jest
    /// dzisiaj. Ekran podaje ją z jednego zegara, wspólnego z listą posiłków.
    let nowMinutes: Int?
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
        /// Pasmo nad zdjęciem. Mieści dwa piętra: godzinę „teraz” pod samą
        /// górą i kalorie tuż nad zdjęciem, więc nigdy nie piszą po sobie.
        static let band: CGFloat = 32
        static let nowLabel: CGFloat = 13
        static let kcalLabel: CGFloat = 13
        static let timeGap: CGFloat = 5
        static let timeLabel: CGFloat = 14
        /// Kropka „teraz" na kresce.
        static let nowDot: CGFloat = 9
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

    private struct Placed: Identifiable {
        let node: Node
        let x: CGFloat
        var id: String { node.id }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let placed = layout(width: width)
            let nowX = nowMinutes.map { x(forMinutes: $0, width: width) }

            ZStack(alignment: .topLeading) {
                track(width: width, elapsedTo: elapsedWidth(nowX: nowX, width: width))

                ForEach(placed) { item in
                    nodeView(item)
                        .offset(x: item.x - Metrics.column / 2, y: 0)
                }

                // Znacznik „teraz" na samej górze stosu: kropka na kresce ma
                // być widoczna także wtedy, gdy wypada tuż obok zdjęcia.
                if let nowX, let nowMinutes {
                    nowMarker(minutes: nowMinutes)
                        .offset(x: nowX - Metrics.column / 2, y: 0)
                }
            }
            .frame(width: width, height: Metrics.height, alignment: .topLeading)
        }
        .frame(height: Metrics.height)
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
            .map { "\($0.id):\($0.minutes):\($0.status.isEaten ? 1 : 0)" }
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

    /// Godzina wyśrodkowana nad kropką, kropka wyśrodkowana na kresce.
    ///
    /// Obie części dzielą tę samą kolumnę i to ona trzyma je w jednej osi
    /// pionowej — bez niej podpis stał obok kropki, a nie nad nią.
    private func nowMarker(minutes: Int) -> some View {
        ZStack(alignment: .top) {
            Text(MealSlotSchedule.format(minutes))
                .font(.system(size: 10.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(SCPalette.terracotta)
                .lineLimit(1)
                .frame(width: Metrics.column, height: Metrics.nowLabel)

            Circle()
                .fill(SCPalette.terracotta)
                .frame(width: Metrics.nowDot, height: Metrics.nowDot)
                // Obwódka w kolorze tła robi kropce prześwit na kresce
                // i na zdjęciu, obok którego akurat wypadła.
                .overlay(
                    Circle().strokeBorder(Color.scPageBase(scheme), lineWidth: 2)
                )
                .offset(y: Metrics.trackY - Metrics.nowDot / 2)
        }
        .frame(width: Metrics.column, height: Metrics.height, alignment: .top)
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
                    .foregroundStyle(labelColor(item.node.status))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(height: Metrics.kcalLabel)
                    .padding(.bottom, 3)
                    .frame(height: Metrics.band, alignment: .bottom)

                thumbnail(item.node)

                Text(MealSlotSchedule.format(item.node.minutes))
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(labelColor(item.node.status))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(height: Metrics.timeGap + Metrics.timeLabel, alignment: .bottom)
            }
            .frame(width: Metrics.column, height: Metrics.height, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .center)))
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
        .frame(width: Metrics.node, height: Metrics.node)
        .clipShape(Circle())
        // Zjedzone przygasa — zostaje czytelne, ale przestaje konkurować
        // z tym, co dopiero przed użytkownikiem. Ta sama reguła co w wierszu.
        .saturation(node.status.isEaten ? 0.45 : 1)
        .opacity(node.status.isEaten ? 0.8 : 1)
        .overlay(
            Circle()
                .strokeBorder(ringColor(node), lineWidth: node.status == .next ? 2 : 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if node.status.isEaten { eatenBadge }
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

    /// Pieczątka zjedzenia — ten sam znak co w wierszu posiłku, tyle że
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

    private func ringColor(_ node: Node) -> Color {
        switch node.status {
        case .eaten: return SCPalette.sage.opacity(0.55)
        case .next:  return node.slot.cozyAccent
        default:     return Color.scTileStroke(scheme)
        }
    }

    private func labelColor(_ status: CalendarMealStatus) -> Color {
        switch status {
        case .eaten: return SCPalette.sage
        case .next:  return Color.scLabel(scheme)
        default:     return Color.scFaint(scheme)
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

        return sorted.indices.map { Placed(node: sorted[$0], x: xs[$0]) }
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
}

#Preview("Oś dnia — dzisiaj") {
    let nodes = [
        CalendarDayAxis.Node(
            id: "sn", slot: .breakfast, minutes: 8 * 60, kcal: 510,
            status: .eaten, title: "Owsianka kakaowa", imageURL: nil
        ),
        CalendarDayAxis.Node(
            id: "ii", slot: .secondBreakfast, minutes: 8 * 60 + 30, kcal: 190,
            status: .next, title: "Jogurt z granolą", imageURL: nil
        ),
        CalendarDayAxis.Node(
            id: "ob", slot: .lunch, minutes: 14 * 60, kcal: 1208,
            status: .later, title: "Indyk z ziemniakami", imageURL: nil
        ),
        CalendarDayAxis.Node(
            id: "ko", slot: .dinner, minutes: 20 * 60, kcal: 900,
            status: .later, title: "Pierogi z truskawkami", imageURL: nil
        )
    ]

    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()
        CalendarDayAxis(
            nodes: nodes,
            nowMinutes: 9 * 60 + 41,
            isPast: false,
            onTap: { _ in }
        )
        .padding(.horizontal, SCPageMetrics.horizontal)
    }
    .preferredColorScheme(.dark)
}
