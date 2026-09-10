import Foundation
import SwiftUI

// Kalendarz v4 — doba jako łuk.
//
// Źródło: canvas claude.ai → „Weekly Meals - Kalendarz v4.html”,
// `components/cal-v4.jsx` (`C4Arc`). Doba 06–23 rozpięta na 270° otwartych
// u dołu: dania stoją okrągłymi zdjęciami wzdłuż toru, przebyta część doby
// jest wypełniona, a kropka „teraz” pokazuje, gdzie jesteśmy. W dziurze po
// środku stoi jedno zdanie o tym, co teraz (`CalendarArcCenter`).
//
// Łuk zastąpił poziomą oś (`CalendarDayAxis`) z v2 z jednego powodu: kreska
// przez całą szerokość ekranu zużywała 350 pt na informację, która mieści
// się w kole — a to, co zostawało pod nią, i tak było puste. Koło oddaje ten
// sam dzień i jeszcze zarabia miejsce na zdanie w środku.
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
//  3. **Posiłki stoją w RÓWNYCH odstępach, nie na swoich godzinach.**
//     Największa różnica wobec makiety i jedyna, która zmienia znaczenie
//     rysunku — cała reguła i jej uzasadnienie siedzą w `anchors`. Skrót:
//     zegar dnia nie jest równomierny, więc linijka czasu robiła z łuku
//     kształt przekrzywiony, choć policzony co do stopnia.
//  4. **Podpis godziny chowa się pod węzłem, nie tylko pod kropką.** Makieta
//     ukrywała podpis, gdy nachodziła na niego kropka „teraz” — ale zdjęcie
//     dania zderza się z nim dokładnie tak samo.
//  5. **Podpisane są tylko dwa końce doby**, a nie 06/12/18/23 z makiety.
//     Powód jest ten sam, co w punkcie 3: skala między posiłkami nie jest
//     równomierna, więc podpis w środku obiecywałby coś, czego nie ma.
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

    /// Plansza z makiety — od niej liczą się WSZYSTKIE proporcje (zdjęcie,
    /// grubość toru, kropka, pismo w środku). Nie mylić z `defaultSize`:
    /// tamto mówi, jak duży łuk rysujemy, to — w jakich proporcjach.
    private static let designSize: CGFloat = 232

    /// Średnica, do której łuk dochodzi tam, gdzie jest na nią miejsce.
    /// Większa od makiety, bo na telefonie zostawało po niej kilkadziesiąt
    /// punktów pustki z obu stron.
    static let defaultSize: CGFloat = 280
    /// Najmniejsza, przy której środek jeszcze mieści zdanie.
    static let minSize: CGFloat = 210

    /// Doba rysowana domyślnie. Posiłek spoza tych godzin rozciąga zakres,
    /// zamiast wypaść poza łuk.
    static let dayStart = 6 * 60
    static let dayEnd = 23 * 60

    /// Łuk zaczyna się w lewym dolnym rogu i idzie 270° zgodnie z ruchem
    /// wskazówek zegara, kończąc w prawym dolnym. Kąty liczone jak w SwiftUI:
    /// 0° w prawo, rosnące w dół.
    private static let startAngle: Double = 135
    private static let sweep: Double = 270

    /// Ile łuku zostaje wolne przed pierwszym posiłkiem i za ostatnim.
    ///
    /// Bez tego marginesu śniadanie siedziałoby dokładnie na końcu toru
    /// i kropka „teraz" o 6:30 nie miałaby gdzie stanąć przed nim — a poranek
    /// przed pierwszym posiłkiem to normalny stan dnia, nie wyjątek.
    private static let endMargin: Double = 0.12

    /// Prześwit między dwoma zdjęciami stojącymi obok siebie na torze.
    private static let nodeGap: CGFloat = 8
    /// Jak blisko musi stanąć węzeł albo kropka, żeby zgasić podpis godziny.
    private static let tickHideDegrees: Double = 16

    /// Proporcje względem `designSize`: zdjęcie 36 pt, tor 8, kropka 11.
    private static let nodeRatio: CGFloat = 36 / designSize
    private static let trackRatio: CGFloat = 8 / designSize
    private static let dotRatio: CGFloat = 11 / designSize

    private var c: CGFloat { size / 2 }
    /// Promień, na którym stoją podpisy godzin — tuż przy krawędzi planszy.
    private var hourRadius: CGFloat { c - 9 }
    /// Promień toru. Liczony OD KRAWĘDZI do środka, a nie odwrotnie: podpis
    /// godziny musi się zmieścić na planszy także wtedy, gdy łuk zjeżdża do
    /// `minSize`, a to on jest najdalej od środka.
    private var radius: CGFloat { hourRadius - nodeSize * 0.52 }
    private var nodeSize: CGFloat { (size * Self.nodeRatio).rounded() }
    private var trackWidth: CGFloat { max(5, size * Self.trackRatio) }
    private var dotSize: CGFloat { max(9, (size * Self.dotRatio).rounded()) }
    /// Pismo w środku NIE rośnie razem z planszą — zostaje przy rozmiarach
    /// z makiety, bo to one były strojone pod czytanie, a nie pod średnicę.
    /// Zjeżdża tylko wtedy, gdy łuk schodzi poniżej makiety, i nie niżej niż
    /// do 0,82: mniejsze przestaje być czytelne, a i tak ma własny
    /// `minimumScaleFactor`.
    private var textScale: CGFloat { min(1, max(0.82, size / Self.designSize)) }

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

    /// Dwa podpisy: godzina, o której doba się na łuku zaczyna, i ta, o której
    /// się kończy. Domyślnie 06 i 23.
    ///
    /// Makieta miała jeszcze 12 i 18 w środku i miały sens, dopóki łuk był
    /// linijką czasu. Odkąd posiłki dostały równe odstępy (patrz `anchors`),
    /// czas między nimi rozciąga się i ściska — podpis „12" wypadałby wtedy
    /// raz bliżej, raz dalej od „06", obiecując równomierność, której już
    /// nie ma. Zostają końce, bo one się nie ruszają i mówią dokładnie to,
    /// co trzeba: tu dzień się zaczyna, tam kończy.
    private var hourTicks: [Int] {
        let bounds = domain
        let lower = bounds.lower / 60
        let upper = bounds.upper / 60
        return upper > lower ? [lower, upper] : [lower]
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
    /// rozciągany o pełną godzinę, gdy dom je poza tymi porami.
    ///
    /// Rozciągany o godzinę, a nie „do pierwszego posiłku": oba końce muszą
    /// zostać ŚCIŚLE przed pierwszym i za ostatnim daniem, bo to na nich
    /// opiera się skala (`anchors`). Śniadanie o 06:00 przy zakresie
    /// zaczynającym się też o 06:00 dawałoby odcinek o zerowej szerokości.
    ///
    /// „Teraz” zakresu NIE rozciąga: o 02:00 kropka siada na początku łuku
    /// i to jest prawda („doba jeszcze się nie zaczęła”).
    private var domain: (lower: Int, upper: Int) {
        let minutes = nodes.map(\.minutes)
        var lower = Self.dayStart
        var upper = Self.dayEnd

        if let first = minutes.min(), first <= lower {
            lower = max(0, (first / 60 - 1) * 60)
        }
        if let last = minutes.max(), last >= upper {
            upper = min(24 * 60 - 1, (last / 60 + 1) * 60)
        }
        return (lower, max(upper, lower + 1))
    }

    /// Kotwica skali: która minuta doby wypada w którym miejscu łuku (0…1).
    private struct Anchor {
        let minutes: Int
        let position: Double
    }

    /// Skala łuku — i to jest miejsce, w którym łuk PRZESTAJE być linijką
    /// czasu.
    ///
    /// Posiłki stoją na nim w RÓWNYCH odstępach, bo zegar dnia i tak nie jest
    /// równomierny: śniadanie o 08:00 dzielą od początku doby dwie godziny,
    /// a kolację o 20:00 od jej końca trzy. Na linijce czasu wychodziło z tego
    /// śniadanie zauważalnie niżej niż kolacja i cały łuk czytał się jak
    /// przekrzywiony, choć był policzony co do stopnia. Rytm dnia niesie
    /// KOLEJNOŚĆ posiłków, nie odległość w minutach — więc to kolejność
    /// dostaje równe odstępy.
    ///
    /// Czas nie znika: rozciąga się i ściska MIĘDZY posiłkami. Kropka „teraz"
    /// dalej mówi prawdę — o 09:41 stoi między śniadaniem a obiadem dokładnie
    /// tam, gdzie wypada proporcją. Zmienia się tylko to, że godzina drogi
    /// przed obiadem może być na łuku dłuższa niż godzina drogi po nim.
    private var anchors: [Anchor] {
        let bounds = domain
        let mealMinutes = nodes.map(\.minutes).sorted()
        guard !mealMinutes.isEmpty else {
            return [Anchor(minutes: bounds.lower, position: 0),
                    Anchor(minutes: bounds.upper, position: 1)]
        }

        var result = [Anchor(minutes: bounds.lower, position: 0)]
        for (index, minutes) in mealMinutes.enumerated() {
            result.append(Anchor(minutes: minutes, position: mealPosition(index, of: mealMinutes.count)))
        }
        result.append(Anchor(minutes: bounds.upper, position: 1))
        return result
    }

    /// Miejsce `index`-tego posiłku dnia na łuku. Jedyny posiłek staje
    /// w szczycie; reszta rozkłada się równo między marginesami.
    private func mealPosition(_ index: Int, of count: Int) -> Double {
        guard count > 1 else { return 0.5 }

        // Dzień gęstszy, niż łuk umie pomieścić z marginesami (kilka
        // wariantów w tej samej porze), oddaje marginesy na rzecz prześwitu
        // między zdjęciami. Poniżej tego i tak nie ma czego ratować.
        var margin = Self.endMargin
        if Self.sweep * (1 - 2 * margin) / Double(count - 1) < minNodeSpacing {
            margin = 0
        }
        return margin + (1 - 2 * margin) * Double(index) / Double(count - 1)
    }

    /// Minuta doby → miejsce na łuku, po odcinkach między kotwicami.
    private func progress(forMinutes minutes: Int) -> Double {
        let points = anchors
        guard let first = points.first, let last = points.last else { return 0 }
        if minutes <= first.minutes { return first.position }
        if minutes >= last.minutes { return last.position }

        for index in 1..<points.count where minutes <= points[index].minutes {
            let start = points[index - 1]
            let end = points[index]
            let width = end.minutes - start.minutes
            // Odcinek o zerowej szerokości zdarza się, gdy posiłek stoi
            // dokładnie na granicy zakresu — wtedy po prostu bierzemy jego
            // miejsce, zamiast dzielić przez zero.
            guard width > 0 else { return end.position }
            let ratio = Double(minutes - start.minutes) / Double(width)
            return start.position + (end.position - start.position) * ratio
        }
        return last.position
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
    /// Odkąd posiłki rozkładają się równo, nic tu nikogo nie rozsuwa —
    /// ta liczba jest już tylko progiem, po którym `mealPosition` oddaje
    /// marginesy przy końcach łuku, żeby dzień z sześcioma wariantami nie
    /// zlepił zdjęć w jedną plamę.
    ///
    /// Liczone po ŁUKU, nie po cięciwie — a łuk jest zawsze dłuższy niż
    /// cięciwa, więc wychodzi z tego próg odrobinę ciaśniejszy, niż
    /// wyglądałoby to na oko. Stąd `nodeGap` z zapasem: przy planszy
    /// z makiety różnica między jednym a drugim rachunkiem to pół punktu.
    private var minNodeSpacing: Double {
        Double(nodeSize + Self.nodeGap) / Double(radius) * 180 / Double.pi
    }

    /// Węzły biorą swoje miejsce WPROST z kolejności dnia, a nie z godziny —
    /// to jest cała różnica między tym łukiem a linijką czasu (patrz
    /// `anchors`). Równe odstępy wychodzą z rachunku, a nie z rozsuwania po
    /// fakcie, więc nie ma tu czego poprawiać kolizjami.
    private func layout() -> [Placed] {
        let sorted = nodes.sorted { $0.minutes < $1.minutes }
        guard !sorted.isEmpty else { return [] }

        return sorted.indices.map { index in
            let position = mealPosition(index, of: sorted.count)
            return Placed(node: sorted[index], degrees: Self.startAngle + Self.sweep * position)
        }
    }

    /// Odcisk zawartości łuku — po nim animuje się podmiana dnia i odhaczenie
    /// posiłku. Sama data w nim nie siedzi: przy dwóch dniach o identycznym
    /// zestawie posiłków nie ma czego animować.
    private func fingerprint(_ placed: [Placed]) -> String {
        placed
            .map { "\($0.node.id):\(Int($0.degrees.rounded())):\($0.node.status)" }
            .joined(separator: "|")
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
