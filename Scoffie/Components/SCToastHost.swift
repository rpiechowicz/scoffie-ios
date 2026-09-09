import SwiftUI

// MARK: - Geometria wyspy

/// Liczby opisujące Dynamic Island i miejsce, w którym kapsuła ma z niej
/// wyrosnąć.
///
/// Wszystko idzie z bezpiecznego obszaru u góry, a nie z listy modeli
/// telefonów: taka lista starzeje się co wrzesień, a wcięcie jest tym samym
/// pomiarem, który system i tak podaje każdemu widokowi.
enum SCToastMetrics {
    /// Ramka wyspy — identyczna na wszystkich telefonach, które ją mają.
    static let islandSize = CGSize(width: 126, height: 37.33)

    /// Poniżej tej wysokości wcięcia telefon wyspy nie ma.
    ///
    /// Wartości z życia: wyspa 59 albo 62 pt, wcięcie 47/48/50, przycisk
    /// Początek 20, orientacja pozioma 0. Próg 51 rozdziela te grupy — od
    /// strony wyspy z zapasem (50 → 59), od strony wcięcia o włos, bo
    /// iPhone 13 mini zgłasza 50 pt. Przy okazji łapie orientację poziomą,
    /// w której wyspa leży z boku i nie da się z niej nic wyprowadzić.
    private static let islandInsetFloor: CGFloat = 51

    /// O ile wyspa stoi WYŻEJ niż górna krawędź bezpiecznego obszaru.
    ///
    /// Jedna liczba na wszystkie telefony, i to nie przypadek: przy wcięciu
    /// 59 pt wyspa zaczyna się 11 pt od góry ekranu, przy 62 pt — 14 pt.
    /// W obu przypadkach 48 pt nad bezpiecznym obszarem, więc tabela modeli
    /// jest niepotrzebna.
    private static let islandTopFromInset: CGFloat = 48

    /// Prześwit pod pasem systemu na telefonach BEZ wyspy — tam granicą jest
    /// wcięcie albo sam pasek stanu.
    private static let belowSystemBand: CGFloat = 8

    struct Layout {
        /// Przesunięcie kapsuły ZWINIĘTEJ względem górnej krawędzi
        /// bezpiecznego obszaru. Z wyspą ujemne, bo w nią wchodzi — kapsuła
        /// startuje dokładnie na niej i dlatego czyta się jak jej część.
        /// Bez wyspy nie ma z czego wyrastać, więc jest równe temu, co
        /// rozwinięte: kapsuła rośnie w miejscu.
        var collapsedTopOffset: CGFloat

        /// Przesunięcie kapsuły ROZWINIĘTEJ.
        ///
        /// I to jest sedno: górny pas ekranu NIE NALEŻY DO APLIKACJI. Wyspę,
        /// zegarek i baterię system rysuje NAD wszystkim, co rysuje aplikacja,
        /// więc treść kapsuły, która tam wjechała, po prostu znikała pod nimi.
        /// Rozwinięta kapsuła schodzi więc pod ten pas w całości; z wyspy
        /// tylko WYJEŻDŻA, a nie zostaje pod nią.
        var expandedTopOffset: CGFloat

        /// Szerokość kapsuły po rozwinięciu.
        var expandedWidth: CGFloat

        /// Czy kapsuła naprawdę wyjeżdża z wyspy, czy tylko zjeżdża z góry.
        var hasIsland: Bool
    }

    static func layout(in proxy: GeometryProxy) -> Layout {
        let hasIsland = proxy.safeAreaInsets.top >= islandInsetFloor
        let width = min(proxy.size.width - 28, 384)
        return Layout(
            // Zwinięta: dokładnie ramka wyspy. Bez wyspy nie ma czego udawać,
            // więc kapsuła po prostu rośnie w miejscu tuż pod paskiem stanu.
            collapsedTopOffset: hasIsland ? -islandTopFromInset : belowSystemBand,
            // Rozwinięta: przy samej krawędzi bezpiecznego obszaru, czyli
            // ~11 pt pod dolną krawędzią wyspy. Tyle wystarczy, żeby ani
            // wyspa, ani zegarek nie miały czego przykryć.
            expandedTopOffset: hasIsland ? 0 : belowSystemBand,
            expandedWidth: max(width, islandSize.width),
            hasIsland: hasIsland
        )
    }
}

// MARK: - Ruch

/// Wszystkie krzywe w jednym miejscu. Jedna sprężyna na jedno przejście,
/// bez `.delay`: opóźnienia nie da się odwrócić w połowie drogi, a sprężyna
/// przejęta w locie zachowuje położenie i prędkość — to cała obsługa
/// przerwań.
///
/// `smooth` to sprężyna krytycznie tłumiona (bounce 0), wybór Apple „gdy nie
/// wiesz". Dwa poprzednie odrzucenia NIE były sprawą odbicia ramki
/// (0,77 % przy tłumieniu 0,84 to ~2 pt, niewidoczne): za pierwszym razem
/// cukierkowy był glif z własną sprężyną 0,62 i kolorowa poświata, za drugim
/// „bugowała się" mechanika — trzy zegary na jednym kształcie, wyścig pomiaru
/// wysokości, wstawianie do drzewa odseparowane od otwarcia czekaniem na
/// klatkę. Pokrętło na potem: `spring(duration:bounce:)` z ±0,1.
private enum SCToastMotion {
    /// Wyjście z wyspy.
    ///
    /// Odrobina odbicia (0,08), nie zero. Sprężyna krytycznie tłumiona
    /// dochodzi do celu bez życia — nic w świecie fizycznym nie zatrzymuje się
    /// dokładnie tak — i to właśnie czytało się jako „nienaturalne". Osiem
    /// setnych daje przeregulowanie rzędu 0,06 %, czyli ułamek punktu: nie
    /// widać odskoku, widać lądowanie.
    static let open = Animation.spring(duration: 0.62, bounce: 0.08)
    /// Powrót do wyspy — krótszy: przychodzi z namysłem, odchodzi zdecydowanie.
    /// Tu odbicia NIE MA: przeregulowanie przy wyspie wystawiłoby czerń ponad
    /// jej krawędź.
    static let close = Animation.smooth(duration: 0.54)
    /// Podmiana treści na otwartej kapsule (zmienia się tylko wysokość).
    static let resize = Animation.spring(duration: 0.50, bounce: 0.06)
    /// Powrót po przeciągnięciu, które nie zamknęło.
    static let settle = Animation.smooth(duration: 0.34)
    /// Reduce Motion: wyłącznie krycie.
    static let fadeIn = Animation.easeOut(duration: 0.24)
    static let fadeOut = Animation.easeIn(duration: 0.18)
}

/// Gładki próg 0→1 z zerowym nachyleniem na obu końcach.
private func smoothstep(_ x: CGFloat) -> CGFloat {
    let t = min(max(x, 0), 1)
    return t * t * (3 - 2 * t)
}

// MARK: - Choreografia z jednej liczby

/// Kropla, nie kałuża.
///
/// Cała droga z wyspy do pigułki jest funkcją JEDNEJ liczby `progress`
/// (0 = ramka wyspy, 1 = pigułka). Sprężyna animuje tę liczbę, a wszystko
/// inne — wysokość, odklejenie górnej krawędzi, szerokość, cień, obwódka,
/// krycie treści — liczy się z niej co klatkę. Kanały nie mogą się rozjechać,
/// bo nie ma dwóch krzywych, które mogłyby; a każde przerwanie (zamknięcie
/// w połowie otwierania, nowy toast w połowie zwijania) to zawrócenie jednej
/// sprężyny.
///
/// Kolejność w `progress` nie jest ozdobą — wynika z tego, czego NIE wolno.
/// Pas u góry ekranu (wyspa, zegarek, bateria) należy do systemu i jest
/// rysowany nad aplikacją; szeroka kapsuła w tym pasie chowałaby zegarek.
/// Dlatego:
/// 1. najpierw rośnie WYSOKOŚĆ, z górną krawędzią wciąż na wyspie — wyspa
///    wypuszcza w dół wąską kroplę;
/// 2. potem kropla ODKLEJA się i zjeżdża pod pas;
/// 3. i dopiero wtedy ROZLEWA się na szerokość.
/// Przy zwijaniu to samo wspak: zwęża się, wraca pod wyspę, wsiąka.
private struct SCToastChoreography {
    let progress: CGFloat

    // Cała GEOMETRIA kończy się przy 0,82, nie przy 0,70 — i to jest
    // odpowiedź na „za szybko przeskakuje".
    //
    // Samo wydłużenie sprężyny tego nie załatwiło: przy pasmach kończących się
    // na 0,70 wydłużenie z 0,48 s do 0,62 s przesunęło koniec ruchu ze 186 ms
    // na 226 ms, czyli o 40 ms, a całe pozostałe 140 ms wpadło w przenikanie
    // tekstu i narastanie cienia — czyli w rzeczy, o których nikt nie mówił,
    // że są za szybkie. Dopiero przesunięcie pasm w górę oddaje ten czas
    // RUCHOWI: teraz kropla wychodzi z wyspy, zjeżdża i rozlewa się przez
    // 284 ms zamiast 186.
    /// Udział wysokości — prowadzi.
    var height: CGFloat { smoothstep(progress / 0.82) }
    /// Odklejenie górnej krawędzi od wyspy.
    var detach: CGFloat { smoothstep((progress - 0.15) / 0.67) }
    /// Szerokość — dopiero gdy górna krawędź wychodzi z pasa systemu.
    ///
    /// Rząd ikon systemu (zegarek do x≈75, bateria od x≈300) kończy się na
    /// y≈34, a górna krawędź kapsuły schodzi poniżej tego przy p≈0,48 —
    /// i ma tam ledwie 165 pt szerokości, czyli od x=114 do x=279. Do p=0,36
    /// szerokość stoi na 126 pt, czyli DOKŁADNIE w obrysie wyspy: kapsuła nie
    /// kładzie ani jednego piksela bliżej zegarka, niż leży sama wyspa.
    var width: CGFloat { smoothstep((progress - 0.36) / 0.46) }
    /// Krycie treści — dopiero gdy okno przycięcia odsłoni kółko z glifem
    /// (p≈0,72, wraz z łukiem końca kapsuły). Treść, która pojawiłaby się
    /// wcześniej, nie przenikałaby, tylko wysuwała spod krawędzi cięcia.
    var reveal: CGFloat { smoothstep((progress - 0.82) / 0.18) }
    /// Cień i obwódka — wyspa ich nie ma, więc zaczynają się dopiero, gdy
    /// górna krawędź naprawdę wyjdzie spod niej (p≈0,62 → y≈48,7 wobec dolnej
    /// krawędzi wyspy na 48,33).
    ///
    /// I muszą być prawie gotowe RAZEM ze stygnięciem, nie po nim: kapsuła
    /// w jasnym motywie ma wobec kremowego płótna 1,05 : 1, więc przez chwilę,
    /// w której jest już biała, a cienia jeszcze nie ma, tekst wygląda jak
    /// wypisany wprost na tle, bez żadnego pojemnika.
    var settle: CGFloat { smoothstep((progress - 0.62) / 0.26) }
    /// Stygnięcie: przejście z czerni wyspy na własną powierzchnię kapsuły.
    ///
    /// Ma znaczenie tylko w jasnym motywie i tylko na telefonach z wyspą
    /// (patrz `needsCooling` w morfie). Kończy się przy 0,82, czyli DOKŁADNIE
    /// tam, gdzie zaczyna się `reveal` — pismo i glif nigdy nie zmieniają
    /// więc barwy na oczach. Pasmo jest szerokie z rozmysłem: przy węższym
    /// przejście trwało 92 ms, czyli pięć klatek, i czytało się jak mrugnięcie,
    /// a nie jak stygnięcie.
    var warmth: CGFloat { smoothstep((progress - 0.34) / 0.48) }
}

/// Kształt kapsuły — pigułka z SUFITEM promienia.
///
/// Zwykły `Capsule` liczy promień jako połowę wysokości i przy normalnych
/// rozmiarach (54–88 pt) to jest dokładnie to, czego chcemy. Przy rozmiarach
/// dostępności toast rośnie do ~200 pt, promień razem z nim, i łuk zaczyna
/// zjadać rogi tekstu: nie ucina go wielokropkiem, tylko fizycznie obcina
/// litery. Sufit 44 pt zatrzymuje promień, zanim to nastąpi (prawy górny róg
/// pisma wymaga promienia poniżej ~49 pt), a poniżej 88 pt wysokości kształt
/// jest CO DO PIKSELA tą samą pigułką, co wcześniej.
private struct SCToastCapsuleShape: InsettableShape {
    static let maxCornerRadius: CGFloat = 44

    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(box.height / 2, Self.maxCornerRadius)
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: box)
    }

    func inset(by amount: CGFloat) -> Self {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// Rozmiar kapsuły jako funkcja udziałów i NATURALNEGO rozmiaru treści.
///
/// Treść jest jedynym dzieckiem. Układ pyta ją o rozmiar idealny (stała
/// szerokość docelowa, wysokość z tekstu) w tym samym przebiegu, w którym
/// rysuje kapsułę — więc nie ma ukrytej kopii do mierzenia, stanu
/// `contentHeight` ani wyścigu, w którym wysokość przychodziła klatkę za
/// późno i sprężyna zawracała w locie. Przy okazji znika błąd, przez który
/// dwuwierszowa wiadomość obcinała się do jednej linii: pomiar w tle kapsuły
/// dostawał propozycję wysokości równą… samej kapsule.
private struct SCIslandMorphLayout: Layout {
    var widthT: CGFloat
    var heightT: CGFloat
    var island: CGSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let natural = subviews.first?.sizeThatFits(.unspecified) ?? island
        return CGSize(
            width: island.width + (max(island.width, natural.width) - island.width) * widthT,
            height: island.height + (max(island.height, natural.height) - island.height) * heightT
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Treść stoi w miejscu — na osi kapsuły, przy górnej krawędzi, w swoim
        // naturalnym rozmiarze. Kapsuła ją ODSŁANIA, nie przesuwa. Wcześniej
        // treść była wyśrodkowana w rosnącej ramce i jechała ~130 pt w lewo
        // i ~60 pt w dół, wjeżdżając w pole widzenia — czytało się to jako
        // „wsuwanie na miejsce", nie jako pojawienie.
        for subview in subviews {
            subview.place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top, proposal: .unspecified)
        }
    }
}

/// Cała kapsuła — kształt, cień, obwódka, krycie i pozycja — policzona
/// z jednej interpolowanej liczby. SwiftUI woła `body` z pośrednimi
/// wartościami `progress` w każdej klatce; to ten sam mechanizm, na którym
/// stoi `AnimatedNumber`.
private struct SCIslandMorph: ViewModifier, Animatable {
    var progress: CGFloat
    let layout: SCToastMetrics.Layout
    let accent: Color
    /// Barwa, w którą kapsuła stygnie po wyjściu z wyspy. W ciemnym motywie
    /// to dalej czerń, więc przejście jest tam żadne.
    let surface: Color
    /// Czy w ogóle stygnąć.
    ///
    /// Czerń na starcie ma sens WYŁĄCZNIE wtedy, gdy jest z czego wychodzić.
    /// Na telefonie bez wyspy (SE, 13 mini, każdy w orientacji poziomej)
    /// nie ma czego udawać, a kapsuła i tak wjeżdża kryciem — czarna pigułka
    /// pojawiająca się na kremie i bielejąca przez ćwierć sekundy byłaby tam
    /// najbardziej rzucającą się w oczy rzeczą, jaką ten toast robi.
    ///
    /// Przy okazji oszczędza dwa mostkowania `UIColor` na klatkę w ciemnym
    /// motywie, gdzie mieszanie i tak zawsze daje czerń.
    let needsCooling: Bool
    /// Docelowe krycie włosa obwódki. W jasnym motywie wyżej, bo tam obwódka
    /// jest JEDYNĄ rzeczą odcinającą górną krawędź kapsuły: cień jest
    /// przesunięty o 8 pt w dół i nad kapsułą nie robi nic.
    let hairline: Double
    /// Ramka kapsuły w układzie okna, mierzona TU — WEWNĄTRZ przesunięcia,
    /// więc razem z nim. Modyfikator zapięty za `offset` widziałby
    /// nieprzesunięte gniazdo układu (tak samo, jak `.background` po
    /// `.offset` nie jedzie za treścią): przy starcie ruchu 48 pt POD kroplą,
    /// a na telefonach bez wyspy zawsze 8 pt nad kapsułą.
    let onFrame: (CGRect) -> Void

    /// Animuje się WYŁĄCZNIE `progress`.
    ///
    /// Przesunięcie palcem świadomie tu nie wchodzi, choć kusiło: wspólny
    /// `AnimatablePair` dałby jeden atrybut na całą pionową geometrię, ale
    /// gest zapisuje przesunięcie BEZ animacji, a zapis bez animacji do
    /// połowy pary zdejmuje animację z całej pary. Kapsuła chwycona w trakcie
    /// wyrastania przeskakiwałaby wtedy od razu do pełnej pigułki. Dlatego
    /// przeciąganie zostaje osobnym `offset` na zewnątrz — zwykłym
    /// modyfikatorem, który animuje się sam, gdy trzeba.
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        let c = SCToastChoreography(progress: min(max(progress, 0), 1))
        let y = layout.collapsedTopOffset + (layout.expandedTopOffset - layout.collapsedTopOffset) * c.detach
        // Z wyspą: w spoczynku krycie DOKŁADNIE 0. Czerń pod czernią wystarcza
        // na ekranie, ale nie w przełączniku aplikacji ani na nagraniu ekranu —
        // tam wycięcie wyspy nie zakrywa już naszej kapsuły. Bez wyspy nie ma
        // z czego wyrastać, więc pierwsza trzecia ruchu to zwykłe pojawienie.
        let alpha: Double = layout.hasIsland
            ? (c.progress > 0.001 ? 1 : 0)
            : Double(min(1, c.progress / 0.35))

        SCIslandMorphLayout(widthT: c.width, heightT: c.height, island: SCToastMetrics.islandSize) {
            content.opacity(Double(c.reveal))
        }
        .clipShape(SCToastCapsuleShape())
        // Cień rzuca sam kształt, nie grupa z tekstem — taniej i bez
        // `compositingGroup`. Zgaszony, póki kapsuła siedzi na wyspie: wyspa
        // nie rzuca cienia, a ciemna poświata wokół niej w pierwszych klatkach
        // była tym samym rodzajem błędu, co odrzucona kolorowa.
        .background {
            SCToastCapsuleShape()
                .fill(needsCooling ? Color.black.mix(with: surface, by: c.warmth) : surface)
                .shadow(color: .black.opacity(Double(0.34 * c.settle)), radius: 16, x: 0, y: 8)
        }
        // Włos obwódki, nie obrys.
        //
        // W ciemnym motywie 0,28, a nie dawne 0,16: przy 0,16 wychodziło
        // 1,18–1,26 : 1, czyli dokładnie tyle, co ciemne płótno pod spodem
        // (1,15 : 1) — kapsuła nie miała krawędzi w ogóle, tylko cień.
        //
        // W jasnym MOCNIEJ, bo tam ten włos pracuje najciężej: ciepła biel
        // kapsuły ma wobec kremowego płótna 1,05 : 1, cień jest przesunięty
        // w dół i nad górną krawędzią nie robi nic, a nad kartą (te też są
        // #FFFCF6) obwódka zostaje jedyną granicą, jaka istnieje.
        .overlay {
            SCToastCapsuleShape()
                .strokeBorder(accent.opacity(hairline * Double(c.settle)), lineWidth: 1)
        }
        // Kształt dotyku i pomiar ramki TU, przed `offset` — w układzie
        // współrzędnych samej kapsuły, więc jadą razem z nią. Gesty zapięte
        // na zewnątrz trafiają w rysowaną kapsułę i tak (dotyk schodzi przez
        // przesunięcie do treści), ale kształt i ramka zadeklarowane na
        // zewnątrz stałyby w nieprzesuniętym gnieździe układu.
        .contentShape(SCToastCapsuleShape())
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: onFrame)
        .opacity(alpha)
        .offset(y: y)
    }
}

// MARK: - Widok

/// Ostatnia zmierzona ramka kapsuły — w klasie, nie w `@State CGRect`, bo
/// zapis co klatkę animacji do zwykłego `@State` przebudowywałby ciało
/// całego widoku co klatkę. Tożsamość obiektu wystarcza: nikt nie musi być
/// odświeżany, gdy ramka się zmienia, tylko okno ma ją dostać.
private final class SCFrameBox {
    var rect: CGRect = .zero
}

/// Kapsuła toastu i cała jej animacja.
///
/// Mieszka w OSOBNYM oknie (`scToastLayer`), nie w drzewie widoków aplikacji.
/// Powód jest prozaiczny: pół tej aplikacji to arkusze — Zakupy, asystent,
/// każdy ekran Ustawień — a arkusz rysuje się nad całą zawartością okna
/// razem z jej nakładkami. Toast wpięty w korzeń byłby niewidoczny dokładnie
/// wtedy, gdy najczęściej ma coś do powiedzenia.
struct SCToastHost: View {
    let center: SCToastCenter

    /// Ramka kapsuły w układzie okna — okno bierze z niej jedyny obszar,
    /// w którym łapie dotyk. Wszystko poza nią ma trafiać do aplikacji pod
    /// spodem, bo okno toastu przykrywa cały ekran.
    var onFrameChange: (CGRect) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Motyw dociera tu przez `overrideUserInterfaceStyle` nałożone na OKNO
    /// toastu — samo `preferredColorScheme` aplikacji nie sięga innego okna,
    /// więc bez tego wymuszony jasny motyw przy ciemnym systemie dawałby
    /// czarną kapsułę na kremowym ekranie.
    @Environment(\.colorScheme) private var scheme

    /// Barwa, w którą kapsuła stygnie po wyjściu z wyspy, i pismo na niej.
    private var surface: Color { scheme == .dark ? .black : SCPalette.Toast.surfaceLight }
    private var ink: Color { scheme == .dark ? .white : SCPalette.Toast.inkLight }
    /// W ciemnym motywie kapsuła jest czarna od początku do końca, więc nie ma
    /// z czego stygnąć.
    private var needsCooling: Bool { scheme != .dark }
    private var hairlineOpacity: Double { scheme == .dark ? 0.28 : 0.40 }

    /// Treść w kapsule. ZOSTAJE po zamknięciu — kapsuła zwija się z tym, co
    /// pokazywała, więc nic nie przeskakuje w trakcie zwijania — i jest
    /// podmieniana w miejscu, gdy przychodzi następny toast.
    @State private var displayed: SCToast?
    /// JEDYNA liczba ruchu: 0 = ramka wyspy, 1 = rozwinięta pigułka.
    @State private var progress: CGFloat = 0
    /// Logiczna widoczność — dotyk, VoiceOver, ramka dla okna. Zmienia się
    /// od razu, nie po animacji.
    @State private var isPresented = false
    /// Bramka krycia. Rządzi WYŁĄCZNIE przy Reduce Motion (geometria wtedy
    /// nie animuje się wcale, kapsuła tylko przenika), ale pisana jest
    /// w każdej gałęzi, żeby zawsze mówiła to samo, co `isPresented`:
    /// przełączenie Reduce Motion w trakcie toastu nie może odsłonić
    /// widmowej kapsuły ani schować żywej.
    @State private var veil = false
    @State private var dragOffset: CGFloat = 0
    @State private var frameBox = SCFrameBox()

    var body: some View {
        // Świadomie BEZ `ignoresSafeArea`: pod nim `GeometryReader` potrafi
        // zgłosić zerowe wcięcia, a to z nich bierze się cała pozycja kapsuły.
        // Wszystko liczy się od krawędzi bezpiecznego obszaru, a w pas wyspy
        // wchodzi ujemnym przesunięciem — rysowanie poza tę krawędź i tak nie
        // jest przycinane.
        GeometryReader { proxy in
            let layout = SCToastMetrics.layout(in: proxy)
            capsule(layout: layout)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // Synchronicznie, nie `.task`: `withAnimation` rusza w TEJ SAMEJ
        // transakcji, w której zmienia się stan. Nie ma klatki zwłoki do
        // wyczekania ani `Task.sleep` do anulowania — a to właśnie przerwane
        // odliczanie gubiło pasek braku sieci, gdy ktoś stuknął w kapsułę
        // podczas podmiany: zadanie zaczynało od nowa, widziało „ten sam
        // toast" i wychodziło, zostawiając kapsułę zwiniętą na zawsze.
        .onChange(of: center.current?.id, initial: true) { _, _ in sync() }
        // Ramka dla okna na OBU zboczach. Sam pomiar geometrii nie wystarczy:
        // odpala się tylko, gdy ramka się ZMIENI, a przy Reduce Motion między
        // dwoma toastami o tej samej wysokości nie zmienia się nic — okno
        // zostawałoby z zerem i widoczny pasek nie dałby się stuknąć.
        .onChange(of: isPresented) { _, presented in
            onFrameChange(presented ? frameBox.rect : .zero)
        }
        // Dotyk i ogłoszenie idą za ZDARZENIEM, nie za treścią: nowy toast
        // chwilowy albo nowy pasek stanu. Pasek wracający po „Zapisano" nie
        // stuka i nie mówi drugi raz.
        .sensoryFeedback(trigger: center.feedbackCount) { _, _ in
            center.current?.style.feedback
        }
        // `initial: true`, bo warstwa toastów wstaje razem z aplikacją: gdyby
        // pasek braku sieci zapalił się, zanim okno zdąży się założyć,
        // VoiceOver nie usłyszałby o nim nigdy.
        .onChange(of: center.feedbackCount, initial: true) { _, _ in
            if let toast = center.current {
                announce(toast)
            }
        }
    }

    // MARK: Kapsuła (zawsze zamontowana)

    /// Kapsuła NIGDY nie jest wstawiana ani usuwana z drzewa. W spoczynku
    /// siedzi zwinięta dokładnie na wyspie, z kryciem 0.
    ///
    /// Dzięki temu nie ma osobnej transakcji wstawienia, którą trzeba by
    /// odseparować od otwarcia czekaniem „na jedną klatkę". Tamto czekanie
    /// działało ze szczęścia: gdy główny wątek był zajęty — a bywa, dokładnie
    /// na błędzie, który toast ma zgłosić — oba zapisy lądowały w jednej
    /// klatce i kapsuła pojawiała się od razu rozwinięta, bez wyrastania
    /// z wyspy. Raz tak, raz nie: to jest to „bugowanie się".
    private func capsule(layout: SCToastMetrics.Layout) -> some View {
        // ZStack, NIE Group. `Group` jest przezroczysty: każdy modyfikator za
        // nim idzie na każde dziecko z osobna, a przed pierwszym toastem
        // dzieci nie ma — czyli nie ma też morfu w drzewie i pierwsze otwarcie
        // wskoczyłoby od razu rozwinięte. Pusty ZStack to prawdziwy widok
        // o rozmiarze zero: układ spada na ramkę wyspy, krycie zostaje 0,
        // a `progress` ma od czego startować.
        ZStack(alignment: .top) {
            if let displayed {
                content(displayed)
                    .frame(width: layout.expandedWidth, alignment: .leading)
                    // Bez własnego przenikania — kryciem treści steruje
                    // `reveal` w morfie.
                    .transition(.identity)
            }
        }
        .modifier(SCIslandMorph(
            progress: progress,
            layout: layout,
            accent: displayed?.style.accent ?? .clear,
            surface: surface,
            // Stygnięcie tylko tam, gdzie jest z czego stygnąć — na telefonie
            // bez wyspy czarna pigułka na kremie nie ma żadnego uzasadnienia.
            needsCooling: needsCooling && layout.hasIsland,
            hairline: hairlineOpacity,
            onFrame: { rect in
                frameBox.rect = rect
                if isPresented {
                    onFrameChange(rect)
                }
            }
        ))
        .opacity(reduceMotion ? (veil ? 1 : 0) : 1)
        // Przeciąganie osobno i NA ZEWNĄTRZ morfu — patrz `animatableData`.
        // Pomiar ramki siedzi głębiej, więc oba przesunięcia są dla niego
        // przodkami i wchodzą do przeliczenia na układ okna.
        .offset(y: dragOffset)
        .onTapGesture { center.dismiss() }
        .gesture(dismissDrag)
        // PO gestach, nie przed nimi: `allowsHitTesting` wyłącza dotyk dla
        // widoku, który modyfikuje, a gest zapięty później owija już
        // wyłączony widok od zewnątrz i dalej by słuchał.
        .allowsHitTesting(isPresented)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayed?.style.accessibilityPrefix ?? "") \(displayed?.title ?? "")")
        .accessibilityValue(displayed?.message ?? "")
        .accessibilityAddTraits(.isStaticText)
        .accessibilityHidden(!isPresented)
    }

    private func content(_ toast: SCToast) -> some View {
        HStack(spacing: 11) {
            // Kółko z glifem podmienia się przez przenikanie CAŁEGO kółka
            // (tożsamość po stylu) — bez interpolacji barwy, bez efektów
            // symboli, bez własnej sprężyny. Wchodzi razem z tekstem.
            // Krążek PEŁNY, z glifem wyciętym w POWIERZCHNI kapsuły.
            //
            // Wcześniej stały tu trzy warstwy przepisane z `scSoftSurface`
            // (wypełnienie 0,18, obwódka 0,45, glif w akcencie) — a te liczby
            // są strojone pod tło PRZYCISKU na ciemnym płótnie, nie pod
            // czerń. Na #000 wypełnienie wychodziło 1,16–1,38 : 1, czyli
            // nic, trzy z czterech obwódek nie dobijały do 3 : 1, i cały
            // sygnał barwy niósł jeden glif szerokości włosa, który na OLED
            // dodatkowo się rozlewał.
            //
            // Pełny krążek robi trzy rzeczy naraz: kontrast glifu równa się
            // kontrastowi akcentu (więc zestrojenie czwórki barw zestraja
            // i glify), znika rozlewanie, a sam glif staje się DZIURĄ —
            // dokładnie tym, czym jest wyspa, którą kapsuła udaje.
            // `.heavy` zostaje: pismo wycięte czyta się cieńsze, niż jest.
            //
            // Glif bierze barwę POWIERZCHNI, nie stałą czerń — w jasnym
            // motywie kapsuła jest ciepłą bielą i dziura ma być tą bielą.
            // Treść pojawia się dopiero po `warmth`, więc barwa nigdy nie
            // zmienia się na oczach.
            ZStack {
                Image(systemName: toast.style.icon)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(surface)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(toast.style.accent))
                    .id(toast.style)
                    .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title)
                    .scFont(14.5, weight: .semibold, relativeTo: .subheadline)
                    .tracking(-0.2)
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    // Podmiana w miejscu: stare zdanie przenika w nowe.
                    .contentTransition(.opacity)

                if let message = toast.message {
                    Text(message)
                        .scFont(12.5, weight: .regular, relativeTo: .caption)
                        .foregroundStyle(ink.opacity(0.62))
                        .lineLimit(2)
                        .contentTransition(.opacity)
                        .transition(.opacity)
                }
            }
            .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 18)
        .padding(.vertical, 11)
        // Podłoga wysokości: sama treść jednowierszowa dałaby kapsułę ledwie
        // wyższą od wyspy i rozwinięcie przestałoby być widoczne.
        .frame(minHeight: 54)
    }

    // MARK: Sterowanie

    /// Jedyny właściciel ruchu. Każde przejście ma dokładnie JEDNĄ animowaną
    /// transakcję, obejmującą treść, `progress` i reset przeciągnięcia — więc
    /// po machnięciu kapsuła wraca DO wyspy z miejsca, w którym zostawił ją
    /// palec, a nie zwija się w powietrzu nad nią i nie skacze potem o 48 pt.
    /// Otwarcie ze spoczynku i Reduce Motion dokładają przed nią jedną
    /// transakcję BEZ ruchu — po to, żeby podmiana treści nie animowała się
    /// tam, gdzie i tak nic nie widać.
    ///
    /// Idempotentne: zawsze celuje w stan wynikający z `center.current`,
    /// niezależnie od tego, w którym punkcie animacji jest kapsuła. Sprężyna
    /// przejmuje bieżące położenie i prędkość i zawraca — to zamyka wszystkie
    /// przypadki przerwania jednym mechanizmem.
    ///
    /// Nowy toast na otwartej kapsule NIE zwija jej do wyspy. Poprzednio tak
    /// było, z uzasadnieniem „zmienia się szerokość i wysokość" — ale
    /// szerokość zależy wyłącznie od ekranu, nigdy od treści. Zmienia się
    /// sama wysokość, a to jest zwykły ruch sprężyny plus przenikanie treści.
    /// Kolejka trzech toastów przestaje wyglądać jak drzwi windy, a pasek
    /// braku sieci nie znika i nie wraca dwa razy wokół każdego „Zapisano".
    private func sync() {
        var still = Transaction()
        still.disablesAnimations = true

        if let incoming = center.current {
            let replacing = isPresented
            isPresented = true

            if reduceMotion {
                // Geometria i treść skaczą bez ruchu, animuje się tylko zasłona.
                // Treść też w tej transakcji: gdyby szła pod `fadeIn`, zmiana
                // naturalnego rozmiaru treści pociągnęłaby za sobą ramkę
                // i kapsuła rosłaby przez 0,2 s — dokładnie to, czego ten tryb
                // ma nie robić.
                withTransaction(still) {
                    displayed = incoming
                    progress = 1
                    dragOffset = 0
                }
                withAnimation(SCToastMotion.fadeIn) { veil = true }
            } else {
                // Otwarcie ze spoczynku: treść podmienia się BEZ animacji, bo
                // przy `progress` bliskim zera i tak jej nie widać. Animowana
                // podmiana krzyżowałaby stare kółko z nowym pod rosnącym
                // kryciem — duch poprzedniego akcentu przez ~0,1 s.
                //
                // Jedyna dziura: toast, który przyjdzie w pierwszych ~40 ms
                // zwijania, gdy `reveal` jeszcze nie zszedł do zera. Wtedy
                // treść podmienia się skokiem zamiast przenikać. Wartości
                // prezentacyjnej `progress` nie da się odczytać ze stanu, więc
                // ten przypadek zostaje świadomie — kosztuje dwie klatki
                // i wymaga zdarzenia z zewnątrz dokładnie w chwili odsunięcia
                // ręką (kolejka idzie ścieżką `replacing`).
                // Dwie rozłączne ścieżki, bo `displayed` wolno zapisać
                // DOKŁADNIE RAZ na przejście: drugi zapis tej samej zmiennej
                // w animowanej transakcji skasowałby transakcję bez ruchu
                // i podmiana treści jednak by przenikała.
                if replacing {
                    // Kapsuła otwarta albo w połowie zwijania? Sprężyna
                    // przejmuje bieżącą pozycję i prędkość; przenikanie treści
                    // jedzie tą samą krzywą.
                    withAnimation(SCToastMotion.resize) {
                        displayed = incoming
                        progress = 1
                        dragOffset = 0
                        veil = true
                    }
                } else {
                    withTransaction(still) { displayed = incoming }
                    withAnimation(SCToastMotion.open) {
                        progress = 1
                        dragOffset = 0
                        veil = true
                    }
                }
            }
        } else {
            guard isPresented else { return }
            isPresented = false

            if reduceMotion {
                // Zasłona gaśnie; geometria wraca do wyspy dopiero PO niej
                // i bez ruchu. Zostawiona przy 1 byłaby niewidoczna tylko
                // dopóty, dopóki Reduce Motion jest włączone — wyłączenie go
                // odsłaniałoby rozwiniętą kapsułę ze starym zdaniem.
                withAnimation(SCToastMotion.fadeOut, completionCriteria: .removed) {
                    veil = false
                } completion: {
                    guard !isPresented else { return }
                    var settle = Transaction()
                    settle.disablesAnimations = true
                    withTransaction(settle) {
                        progress = 0
                        dragOffset = 0
                    }
                }
            } else {
                withAnimation(SCToastMotion.close) {
                    progress = 0
                    dragOffset = 0
                    veil = false
                }
            }
        }
    }

    /// VoiceOver nie widzi kapsuły, dopóki ktoś jej nie dotknie — a toast mówi
    /// o rzeczach, które właśnie się stały. Ogłoszenie dowozi treść bez
    /// szukania jej palcem.
    private func announce(_ toast: SCToast) {
        var text = "\(toast.style.accessibilityPrefix) \(toast.title)"
        if let message = toast.message {
            text += ". \(message)"
        }
        AccessibilityNotification.Announcement(text).post()
    }

    // MARK: Gest

    /// Machnięcie w górę zamyka. W dół kapsuła prawie nie idzie — opór mówi
    /// „tędy nie", zamiast pozwolić przeciągnąć ją na pół ekranu.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let dy = value.translation.height
                // W górę też jest sufit, nie tylko opór w dół. Cała
                // choreografia pilnuje, żeby kapsuła nie weszła w rząd ikon
                // systemu — a nieograniczone przeciągnięcie wsuwało ją tam
                // jednym ruchem palca, na całej szerokości. Ani czarna
                // pigułka w ciemnym motywie, ani biała w jasnym nie ma czego
                // szukać za zegarkiem. 18 pt jest wyraźnie za progiem
                // zamknięcia (14 pt), więc gest działa jak wcześniej.
                dragOffset = dy < 0 ? max(dy, -18) : dy * 0.16
            }
            .onEnded { value in
                let flicked = value.predictedEndTranslation.height < -50
                if value.translation.height < -14 || flicked {
                    // Reszta dzieje się w `sync()`: przesunięcie wraca w TEJ
                    // SAMEJ sprężynie, co zwijanie.
                    center.dismiss()
                } else {
                    withAnimation(SCToastMotion.settle) { dragOffset = 0 }
                }
            }
    }
}

// MARK: - Okno

/// Okno, które przepuszcza dotyk wszędzie poza kapsułą.
///
/// `point(inside:)` zwracające `false` sprawia, że UIKit w ogóle nie
/// rozpatruje tego okna i szuka dalej — pod spodem stoi okno aplikacji.
/// Bez tego przezroczysta nakładka na cały ekran zjadałaby każde stuknięcie.
private final class SCToastWindow: UIWindow {
    var interactiveRect: CGRect = .zero

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Pierwsze klatki otwierania: kapsuła ma jeszcze ramkę wyspy
        // (`isPresented` już prawdziwe, ramka zgłoszona), a stoi pod wyspą —
        // przez ten moment nie zabiera stuknięć z okolic wyspy. Zwijanie
        // zgłasza od razu zero, więc tu nie trafia; w spoczynku ramka ma
        // co najmniej 54 pt, więc próg zawsze przepuszcza.
        guard interactiveRect.height > SCToastMetrics.islandSize.height + 4 else { return false }
        return interactiveRect.contains(point)
    }
}

/// Zakłada okno toastów przy pierwszym pojawieniu się w scenie.
///
/// Okno zakłada się RAZ, a `updateUIView` dowozi mu już tylko motyw. Stoi to
/// na założeniu, że
/// `SCToastCenter` w aplikacji jest dokładnie jedno (tworzone w `ScoffieApp`).
/// Gdyby kiedyś `scToastLayer` dostał inną instancję, okno pokazywałoby dalej
/// toasty ze starej — po cichu.
private struct SCToastWindowInstaller: UIViewRepresentable {
    let center: SCToastCenter
    /// Motyw wybrany w Ustawieniach. `nil` znaczy „jak w systemie".
    let colorScheme: ColorScheme?

    func makeUIView(context: Context) -> UIView {
        Installer(toasts: center, style: Self.style(for: colorScheme))
    }

    /// Tu, a nie tylko przy zakładaniu okna: motyw da się przełączyć
    /// w Ustawieniach w trakcie działania aplikacji.
    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? Installer)?.apply(style: Self.style(for: colorScheme))
    }

    private static func style(for scheme: ColorScheme?) -> UIUserInterfaceStyle {
        switch scheme {
        case .light: .light
        case .dark:  .dark
        default:     .unspecified
        }
    }

    private final class Installer: UIView {
        // NIE `center` — `UIView` ma już własne `center` typu `CGPoint`
        // i nazwa po cichu weszłaby z nim w kolizję.
        private let toasts: SCToastCenter
        private var overlay: SCToastWindow?
        private var style: UIUserInterfaceStyle

        init(toasts: SCToastCenter, style: UIUserInterfaceStyle) {
            self.toasts = toasts
            self.style = style
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        /// Okno toastu jest OSOBNYM oknem, więc `preferredColorScheme`
        /// aplikacji do niego nie dociera — bez tego wymuszony w Ustawieniach
        /// jasny motyw przy ciemnym systemie zostawiałby czarną kapsułę na
        /// kremowym ekranie.
        func apply(style: UIUserInterfaceStyle) {
            self.style = style
            overlay?.overrideUserInterfaceStyle = style
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) nieużywane") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard overlay == nil, let scene = window?.windowScene else { return }

            let overlay = SCToastWindow(windowScene: scene)
            let host = UIHostingController(
                rootView: SCToastHost(center: toasts) { [weak overlay] rect in
                    overlay?.interactiveRect = rect
                }
            )
            host.view.backgroundColor = .clear
            overlay.rootViewController = host
            overlay.backgroundColor = .clear
            // Nad wszystkim, co rysuje aplikacja — łącznie z arkuszami
            // i alertami.
            //
            // `makeKeyAndVisible` świadomie NIE, samo `isHidden = false`.
            // Kluczowe okno zostaje przy aplikacji i to jest tu ważniejsze,
            // niż wygląda: pasek stanu i wskaźnik ekranu głównego biorą styl
            // z korzenia okna kluczowego. Przejęcie klucza przez nakładkę
            // przestawiłoby kolor zegarka na cudzy — a ona nie ma pojęcia,
            // jaki motyw wybrał użytkownik. Przy okazji klawiatura i pole
            // tekstowe zostają tam, gdzie były.
            overlay.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
            overlay.overrideUserInterfaceStyle = style
            overlay.isHidden = false
            self.overlay = overlay
        }
    }
}

extension View {
    /// Zakłada warstwę toastów nad całą aplikacją i wpina kolejkę do
    /// środowiska, żeby dowolny widok mógł sięgnąć po `@Environment(\.toasts)`.
    func scToastLayer(_ center: SCToastCenter, colorScheme: ColorScheme?) -> some View {
        environment(\.toasts, center)
            .background {
                SCToastWindowInstaller(center: center, colorScheme: colorScheme)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
    }
}

// MARK: - Podgląd

/// Podgląd rysuje kapsułę wprost w drzewie widoków (bez osobnego okna) —
/// w kanwie Xcode nie ma sceny, w której dałoby się je założyć.
private struct SCToastPreviewStage: View {
    @Environment(\.colorScheme) private var scheme
    @State private var center = SCToastCenter()

    var body: some View {
        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme).ignoresSafeArea()

            VStack(spacing: 12) {
                Spacer()
                SCSoftButton(title: "Zapisano", trailingIcon: nil, accent: SCPalette.sage) {
                    center.success("Plan zapisany", "Czwartek, 4 posiłki")
                }
                SCSoftButton(title: "Informacja", trailingIcon: nil, accent: SCPalette.indigo) {
                    center.info("Lista zamknięta")
                }
                SCSoftButton(title: "Uwaga", trailingIcon: nil, accent: SCPalette.butter) {
                    center.warning("Cookidoo prosi o ponowne logowanie")
                }
                SCSoftButton(title: "Błąd", trailingIcon: nil, accent: SCPalette.terracottaDeep) {
                    center.error("Nie udało się zapisać", "Spróbuj ponownie za chwilę.")
                }
                // Pasek stanu: zostaje, dopóki go nie zgasisz, i wraca po
                // każdym komunikacie chwilowym. Tak wygląda brak sieci.
                SCSoftButton(title: "Pasek: brak sieci", trailingIcon: nil, accent: SCPalette.butter) {
                    center.setPersistent(
                        SCToast(
                            style: .warning,
                            title: "Brak połączenia z internetem",
                            message: "Widzisz ostatnio pobrane dane."
                        )
                    )
                }
                SCSoftButton(title: "Pasek: zgaś", trailingIcon: nil, accent: SCPalette.sage) {
                    center.setPersistent(nil)
                    center.success("Połączenie wróciło")
                }
                Spacer()
            }
            .padding(24)

            SCToastHost(center: center)
        }
    }
}

#Preview("Toasty — ciemny") {
    SCToastPreviewStage().preferredColorScheme(.dark)
}

#Preview("Toasty — jasny") {
    SCToastPreviewStage().preferredColorScheme(.light)
}
