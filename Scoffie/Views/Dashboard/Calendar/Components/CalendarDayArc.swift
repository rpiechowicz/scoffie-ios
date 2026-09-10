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
//  1. **Kropka „teraz” nie ma przy sobie godziny, a pod daniem chowa się
//     w całości.** W makiecie miała godzinę — i wtedy trzeba było odsuwać ją
//     od zatłoczonych miejsc, żeby nie wchodziła na zdjęcia. Godzina stoi na
//     pasku stanu telefonu dwa centymetry wyżej, więc pisanie jej drugi raz
//     nic nie wnosi, a psuje rysunek. Sama kropka też nie przepycha się ze
//     zdjęciem: kiedy pora posiłku nadchodzi, wsuwa się pod nie i wraca,
//     kiedy pora minie — bo wystający zza dania półksiężyc wygląda jak
//     usterka, a nie jak znacznik.
//  2. **Kropka zmienia barwę, gdy pora coś zrobić.** Terakota znaczy „jesteś
//     tutaj”. Kiedy otwiera się okno gotowania następnego posiłku albo
//     wypada jego pora, kropka przejmuje KOLOR TEJ PORY — ta sama barwa stoi
//     wtedy w pierścieniu wybijającym spod dania, w środku łuku i w kółku
//     wiersza na liście. Reguła siedzi w `CalendarDayFocus.nowTint`.
//  3. **Skrajne posiłki dnia są wyrównane, reszta zostaje na swoich
//     godzinach.** Największa różnica wobec makiety i jedyna, która zmienia
//     znaczenie rysunku — cała reguła i jej uzasadnienie siedzą w `anchors`.
//     Skrót: zegar dnia nie jest symetryczny, więc czysta linijka czasu
//     robiła z łuku kształt przekrzywiony, choć policzony co do stopnia.
//  4. **Podpis godziny chowa się pod węzłem, nie tylko pod kropką.** Makieta
//     ukrywała podpis, gdy nachodziła na niego kropka „teraz” — ale zdjęcie
//     dania zderza się z nim dokładnie tak samo.
//  5. **Podpisane są tylko dwa końce doby**, a nie 06/12/18/23 z makiety.
//     Powód jest ten sam, co w punkcie 3: skala nie jest jednostajna, więc
//     podpis w środku obiecywałby równomierność, której nie ma.
//  6. **Zdjęcie ma pod sobą krążek tła.** Makieta przeciągała kreskę pod
//     daniami, a że zjedzone danie przygasa, kreska prześwitywała przez nie
//     jak rysa. Krążek wycina ją tam, gdzie i tak nie miała czego pokazywać.
//     Tor zostaje przy tym JEDNĄ kreską od początku doby do jej końca —
//     przerywanie go pod daniami próbowaliśmy dwa razy i za każdym razem
//     wychodziło gorzej niż nieprzerywanie (patrz `trackLayer`).
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
            trackLayer()

            ForEach(hourTicks, id: \.self) { hour in
                hourLabel(hour, hidden: isTickHidden(hour, placed: placed))
            }

            // Kropka „teraz" POD zdjęciami, nie nad nimi — i wsuwająca się
            // pod nie w całości, kiedy pora posiłku nadchodzi. Wtedy to danie
            // ma być widać w całości, a że „teraz" jest właśnie na nim, mówi
            // pierścień wybijający spod zdjęcia.
            nowDot(placed)

            ForEach(placed) { item in
                nodeButton(item)
            }

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

    /// Tor doby: pusty pod spodem, przebyty na wierzchu. JEDNA kreska od
    /// początku doby do jej końca — zdjęcia leżą na niej, a nie w niej.
    ///
    /// Były dwa podejścia do przerywania jej pod daniami i oba okazały się
    /// gorsze od nieprzerywania. Odcinki z zaokrąglonymi końcówkami robiły
    /// przy grubości 10 pt osiem widocznych półkoli dokoła łuku. Maska tnąca
    /// okręgiem nie miała tej wady, ale przerwy rozstawione według godzin
    /// posiłków zmieniały się z dnia na dzień — i tor przestawał czytać się
    /// jako jedna doba, a zaczynał jako kilka kresek między daniami.
    ///
    /// Kreska prześwitująca przez przygaszone zdjęcie zjedzonego dania
    /// załatwia się prościej: krążkiem tła pod zdjęciem (patrz `thumbnail`).
    private func trackLayer() -> some View {
        let drawn = didDraw ? elapsed : 0
        let motion: Animation? = reduceMotion ? nil : .easeOut(duration: 0.85)

        return ZStack {
            arcStroke(to: 1, color: Color.scLabel(scheme).opacity(0.10))

            arcStroke(
                to: drawn,
                color: Color.scLabel(scheme).opacity(scheme == .dark ? 0.26 : 0.28)
            )
            // Zerowe wypełnienie i tak nic nie rysuje, ale zaokrąglona
            // końcówka potrafi przy nim zostawić kropkę na starcie łuku.
            .opacity(drawn > 0.001 ? 1 : 0)
            .animation(motion, value: drawn)
        }
    }

    /// Łuk od początku doby do `progress` (ułamek jego długości).
    ///
    /// `Circle().trim(from: 0, …)` ZACZYNA SIĘ NA GODZINIE TRZECIEJ, nie na
    /// dwunastej — `CGPath(ellipseIn:)` startuje w punkcie `(maxX, midY)`
    /// i idzie zgodnie z ruchem wskazówek zegara. Dlatego obrót to dokładnie
    /// `startAngle`, a nie `startAngle + 90`: kąty w tym pliku liczą się
    /// w tej samej konwencji, co punkty na łuku (0° w prawo, rosnące w dół),
    /// więc tor i węzły muszą wychodzić z tej samej liczby. Dołożone 90°
    /// przekręcało sam tor o ćwierć obrotu i otwarcie łuku wypadało z lewej
    /// zamiast u dołu — zdjęcia stały wtedy w powietrzu, obok kreski.
    private func arcStroke(to progress: Double, color: Color) -> some View {
        Circle()
            .trim(from: 0, to: (Self.sweep / 360) * progress)
            .stroke(color, style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
            .rotationEffect(.degrees(Self.startAngle))
            .frame(width: radius * 2, height: radius * 2)
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
        return placed.contains { abs(degrees(at: $0.position) - tick) < Self.tickHideDegrees }
    }

    // MARK: - Węzły

    private struct Placed: Identifiable {
        let node: Node
        /// Miejsce na łuku w ułamku jego długości (0 = początek doby,
        /// 1 = koniec). Stopnie liczy z tego `degrees(at:)` — jedno źródło,
        /// bo po tej samej skali jedzie też tor pod zdjęciami.
        let position: Double
        var id: String { node.id }
    }

    private func degrees(at position: Double) -> Double {
        Self.startAngle + Self.sweep * position
    }

    private func nodeButton(_ item: Placed) -> some View {
        Button {
            pagerGate.ifNotSwiping { onTap(item.node) }
        } label: {
            thumbnail(item.node)
                .scTapTarget(44, drawn: nodeSize)
        }
        .buttonStyle(ArcNodePressStyle())
        .position(point(degrees(at: item.position), radius: radius))
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
                .strokeBorder(ringColor(node), lineWidth: ringWidth(node))
        )
        // Dwie warstwy pod zdjęciem, w tej kolejności.
        //
        // Krążek tła szerszy od zdjęcia wycina pod nim tor doby: zjedzone
        // danie przygasa, a wtedy kreska przechodząca pod spodem
        // prześwitywała przez nie jak rysa na ekranie.
        //
        // Na nim — a więc NAD krążkiem, ale wciąż pod zdjęciem — danie,
        // na które właśnie przyszła pora, wybija pierścieniem jak echosonda.
        // Gdyby leżał głębiej, pierwsza ćwiartka jego drogi chowałaby się za
        // krążkiem i pierścień pojawiałby się w locie zamiast wychodzić spod
        // zdjęcia. Kropka „teraz" jest wtedy schowana (patrz `nowDot`), więc
        // to ten ruch niesie „to jest ten posiłek, teraz" — i niesie go
        // barwą, którą kropka przejmuje w tej samej chwili.
        //
        // Ruch, a nie kolejna nieruchoma obwódka: zdjęcie ma już jedną
        // (`ringColor`) i druga wokół niej robiła z dania tarczę strzelniczą.
        .background {
            ZStack {
                Circle()
                    .fill(Color.scPageBase(scheme))
                    .padding(-2.5)

                if isActive(node) {
                    if reduceMotion {
                        // Bez ruchu zostaje sam pierścień — w miejscu,
                        // w którym echosonda spędza połowę cyklu.
                        Circle()
                            .strokeBorder(node.slot.cozyAccent.opacity(0.45), lineWidth: 2.5)
                            .frame(width: nodeSize, height: nodeSize)
                            .scaleEffect(1.22)
                    } else {
                        ArcActivePing(tint: node.slot.cozyAccent, diameter: nodeSize)
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if node.status.isEaten { eatenBadge }
        }
        .animation(.smooth(duration: 0.24), value: node.status)
        // Kołnierz zapala się z zegara, nie ze zmiany statusu — bez własnego
        // odcisku pojawiałby się skokiem w minucie, w której otwiera się okno
        // gotowania.
        .animation(.smooth(duration: 0.35), value: isActive(node))
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

    /// Danie, na które właśnie przyszła pora — gotuje się albo czeka na
    /// stole. To ono dostaje pełną obwódkę i kołnierz, i to jego barwę
    /// przejmuje w tej samej chwili kropka „teraz" (`CalendarDayFocus`).
    private func isActive(_ node: Node) -> Bool {
        focus.isUrgent && node.status == .next
    }

    private func ringColor(_ node: Node) -> Color {
        switch node.status {
        case .eaten: return Color.scChecked(scheme).opacity(0.28)
        case .next:  return node.slot.cozyAccent
        default:     return Color.scTileStroke(scheme)
        }
    }

    private func ringWidth(_ node: Node) -> CGFloat {
        if isActive(node) { return 2.5 }
        return node.status == .next ? 2 : 1
    }

    /// Pierścień wybijający spod zdjęcia i gasnący — sygnał „pora na to
    /// danie".
    ///
    /// `autoreverses: false`, więc pierścień nie wraca do środka, tylko
    /// zaczyna od nowa: powrót widać jako ruch wsteczny, a echosonda ma bić
    /// zawsze w tę samą stronę. Skok na początek cyklu wypada przy zerowym
    /// kryciu, czyli poza wzrokiem.
    ///
    /// Ramka jest STAŁA, oddycha `scaleEffect` — rosnąca ramka kazałaby
    /// układowi przeliczać się co klatkę animacji bez końca.
    private struct ArcActivePing: View {
        let tint: Color
        let diameter: CGFloat

        @State private var expanded = false

        var body: some View {
            Circle()
                .strokeBorder(tint, lineWidth: 2.5)
                .frame(width: diameter, height: diameter)
                .scaleEffect(expanded ? 1.34 : 1)
                .opacity(expanded ? 0 : 0.65)
                .animation(
                    .easeOut(duration: 1.9).repeatForever(autoreverses: false),
                    value: expanded
                )
                .onAppear { expanded = true }
                .allowsHitTesting(false)
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
    private func nowDot(_ placed: [Placed]) -> some View {
        let motion: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.6)
        let tucked = isNowUnderNode(placed)

        if let nowMinutes {
            CalendarNowDot(
                tint: focus.nowTint,
                ring: Color.scPageBase(scheme),
                diameter: dotSize
            )
            // Kropka nie wystaje zza dania półksiężycem — wsuwa się pod nie
            // w całości i wraca, kiedy pora minie.
            //
            // Zjazd skalą, nie samym kryciem: kropka ma SCHOWAĆ SIĘ pod
            // zdjęciem, a nie zniknąć w powietrzu tuż obok niego. Że „teraz"
            // jest właśnie na tym daniu, mówi wtedy pierścień wybijający spod
            // zdjęcia — a barwę ma tę samą, którą kropka miała przed chwilą.
            .scaleEffect(tucked ? 0.35 : 1)
            .opacity(tucked ? 0 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: tucked)
            .position(point(angle(forMinutes: nowMinutes), radius: radius))
            // Kropka pełznie po torze co minutę — bez tego przeskakiwałaby
            // skokiem o pół punktu, co przy oglądaniu ekranu na żywo widać
            // jako drgnięcie.
            .animation(motion, value: nowMinutes)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Czy kropka „teraz" wchodzi właśnie pod któreś zdjęcie.
    ///
    /// Liczone geometrią, a nie stanem posiłku, bo to problem czysto
    /// rysunkowy: przy krótkim gotowaniu (jogurt, 5 min) kropka wjeżdża pod
    /// danie na długo przed tym, zanim cokolwiek zaczyna się dziać, a przy
    /// pieczeni zaczyna się dziać, gdy kropka jest jeszcze daleko. Wystarczy,
    /// że brzeg kropki dotknie brzegu zdjęcia.
    private func isNowUnderNode(_ placed: [Placed]) -> Bool {
        guard let nowMinutes else { return false }
        let now = angle(forMinutes: nowMinutes)
        let reach = Double(nodeSize / 2 + dotSize / 2) / Double(radius) * 180 / Double.pi
        return placed.contains { abs(degrees(at: $0.position) - now) < reach }
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

    /// Skala łuku — i to jest miejsce, w którym łuk przestaje być zwykłą
    /// linijką czasu.
    ///
    /// **Równane są tylko SKRAJNE posiłki.** Pierwsze danie dnia siada na
    /// `endMargin`, ostatnie na `1 − endMargin`, czyli w miejscach lustrzanych
    /// wobec szczytu łuku — i to załatwia całą krzywiznę, którą widać było
    /// gołym okiem: zegar dnia nie jest symetryczny (śniadanie o 08:00 dzielą
    /// od początku doby dwie godziny, kolację o 20:00 od jej końca trzy), więc
    /// na czystej linijce czasu śniadanie siedziało niżej niż kolacja.
    ///
    /// **Wszystko pomiędzy zostaje na swojej godzinie**, rozpięte liniowo
    /// między pierwszym a ostatnim posiłkiem. To był warunek konieczny:
    /// przy rozkładzie „każdy po równo" przestawienie obiadu z 14:00 na 12:00
    /// nie ruszało na łuku niczego, więc łuk przestawał cokolwiek mówić
    /// o dniu. Teraz obiad przesuwa się dokładnie tak, jak go przesuniesz —
    /// tylko dwa końce są przybite.
    ///
    /// Kropka „teraz" jedzie po tej samej skali, więc dalej mówi prawdę:
    /// o 09:41 stoi między śniadaniem a obiadem dokładnie tam, gdzie wypada
    /// proporcją. Zmienia się tylko to, że godzina drogi przed pierwszym
    /// posiłkiem bywa na łuku krótsza niż godzina drogi między posiłkami.
    private var anchors: [Anchor] {
        let bounds = domain
        let mealMinutes = nodes.map(\.minutes).sorted()

        guard let first = mealMinutes.first, let last = mealMinutes.last else {
            return [Anchor(minutes: bounds.lower, position: 0),
                    Anchor(minutes: bounds.upper, position: 1)]
        }
        // Jeden posiłek (albo wszystkie o tej samej porze) nie ma czego
        // równać z niczym — staje w szczycie łuku.
        guard last > first else {
            return [Anchor(minutes: bounds.lower, position: 0),
                    Anchor(minutes: first, position: 0.5),
                    Anchor(minutes: bounds.upper, position: 1)]
        }
        return [
            Anchor(minutes: bounds.lower, position: 0),
            Anchor(minutes: first, position: Self.endMargin),
            Anchor(minutes: last, position: 1 - Self.endMargin),
            Anchor(minutes: bounds.upper, position: 1)
        ]
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
    /// Po niej rozsuwa węzły `spread` — śniadanie o 08:00 i drugie śniadanie
    /// o 08:30 dzieli na tej skali kilka stopni i bez tego zlałyby się
    /// w jedną plamę.
    ///
    /// Liczone po ŁUKU, nie po cięciwie — a łuk jest zawsze dłuższy niż
    /// cięciwa, więc wychodzi z tego próg odrobinę ciaśniejszy, niż
    /// wyglądałoby to na oko. Stąd `nodeGap` z zapasem: przy planszy
    /// z makiety różnica między jednym a drugim rachunkiem to pół punktu.
    private var minNodeSpacing: Double {
        Double(nodeSize + Self.nodeGap) / Double(radius) * 180 / Double.pi
    }

    /// Węzły siadają tam, gdzie skala (`anchors`) stawia ich godzinę —
    /// a potem rozsuwają się, jeśli któreś dwa stanęły na sobie.
    ///
    /// Rozsuwanie wróciło razem ze skalą po czasie: śniadanie o 08:00
    /// i drugie śniadanie o 08:30 dzieli na tym łuku kilka stopni i bez tego
    /// zlewałyby się w plamę.
    private func layout() -> [Placed] {
        let sorted = nodes.sorted { $0.minutes < $1.minutes }
        guard !sorted.isEmpty else { return [] }

        let positions = Self.spread(
            ideal: sorted.map { progress(forMinutes: $0.minutes) },
            minSpacing: minNodeSpacing / Self.sweep,
            lower: Self.endMargin,
            upper: 1 - Self.endMargin
        )
        return sorted.indices.map { Placed(node: sorted[$0], position: positions[$0]) }
    }

    /// Rozsuwa węzły tak, żeby żadne dwa nie stały bliżej niż `minSpacing`,
    /// nie ruszając ich kolejności i nie wypuszczając poza `lower…upper`.
    ///
    /// Przejście w przód dopycha każdy węzeł za poprzednika; jeśli ostatni
    /// wyjdzie za koniec, przejście w tył ściąga cały ogon z powrotem. Gdy
    /// węzłów jest tyle, że nie mieszczą się nawet ciasno upakowane, proporcje
    /// przestają cokolwiek znaczyć i rozkładamy je równo — lepiej stracić
    /// informację o godzinie niż zlepić zdjęcia w jedną plamę.
    ///
    /// `static` i bez `self`, żeby dało się to przeczytać (i policzyć
    /// w głowie) w oderwaniu od widoku. Ta sama procedura jechała na poziomej
    /// osi v2, tylko w punktach zamiast w ułamkach łuku.
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

    /// Odcisk zawartości łuku — po nim animuje się podmiana dnia i odhaczenie
    /// posiłku. Sama data w nim nie siedzi: przy dwóch dniach o identycznym
    /// zestawie posiłków nie ma czego animować.
    private func fingerprint(_ placed: [Placed]) -> String {
        placed
            .map { "\($0.node.id):\(Int(($0.position * 1000).rounded())):\($0.node.status)" }
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
/// Kropka sama nie pulsuje. Miała własną oddychającą poświatę, dopóki leżała
/// NAD zdjęciami — odkąd chowa się pod nie, w chwili, w której pulsowanie
/// miałoby sens, i tak nie było jej widać. Ruch przeniósł się tam, gdzie go
/// widać: na pierścień wybijający spod dania (`ArcActivePing`). Kropce
/// zostaje sama barwa, ta sama, którą bierze wtedy tamten pierścień.
private struct CalendarNowDot: View {
    let tint: Color
    let ring: Color
    let diameter: CGFloat

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: diameter, height: diameter)
            .overlay(
                Circle().strokeBorder(ring, lineWidth: 2.5)
                    .padding(-2.5)
            )
            // Barwa przechodzi płynnie: kropka nie „przeskakuje” z terakoty
            // w kolor pory, tylko dojrzewa do niego przez ćwierć sekundy.
            .animation(.smooth(duration: 0.45), value: tint)
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
