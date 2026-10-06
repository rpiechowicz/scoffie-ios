import SwiftUI

/// Pigułka „ile jeszcze zostało" tuż nad dolnym menu — wejście do arkusza
/// „Cel dnia" (`PlanDayGoalSheet`).
///
/// Źródło: canvas claude.ai → „Weekly Meals - Plan v2.html”, pasek pod osią
/// dnia. W aplikacji nie stoi jednak na końcu przewijanej treści, tylko wisi
/// nad menu jako `safeAreaInset`: liczba, po którą sięga się w trakcie
/// układania dnia, nie może wymagać przewinięcia na sam dół.
///
/// **Szkło, nie karta.** Dolne menu na iOS 26 jest z Liquid Glass i pigułka
/// stoi tuż nad nim, więc musi być z tego samego materiału — kafel z tokenów
/// `scTileBg` wyglądałby obok niego jak wklejka z innego ekranu. Stąd
/// `glassEffect` zamiast płaskiego tła, którego używa reszta
/// aplikacji tam, gdzie karta leży W treści, a nie NAD nią.
///
/// **Treść przewija się pod spodem, ale kończy nad pigułką.** To jest cała
/// robota `safeAreaInset` po stronie `WeeklyPlanView`: pasek nie zjada
/// ostatniego wiersza osi, a mimo to jedzenie przelatuje pod szkłem i jest
/// przez nie widać. Zwykły `overlay` dawał pierwsze i tracił drugie —
/// „Dodaj posiłek" siedziało pod pigułką i nie dało się w nie stuknąć.
///
/// **Cztery kolumny w jednym wierszu.** Kalorie i trzy makra stoją obok siebie,
/// każde z podpisem „kcal 1135/2100" i torem pod spodem na pełną szerokość swojej
/// kolumny. Cztery tory tej samej długości, wszystkie zaczynające się w tym
/// samym miejscu — czyta się je jako jedną siatkę, a nie cztery osobne kreski.
///
/// Dwa poprzednie układy tego nie dawały. Trzy makra w jednym wierszu obok
/// swoich podpisów zostawiały na tor ~32 pt, a podpisy różnej długości
/// przesuwały każdy tor w inne miejsce; wcześniejszy wariant z podpisem nad
/// torem miał tory sensownej długości, ale kosztem trzeciego poziomu tekstu
/// i pigułki wysokiej jak klocek. Kolumna dwulinijkowa w JEDNYM wierszu daje
/// oba naraz: pigułka jest niższa niż przy dwóch wierszach jednolinijkowych,
/// a tor jest dwa razy dłuższy.
///
/// Cztery kolumny mają ten sam stopień pisma. Kalorie wyróżnia pierwsze
/// miejsce i kolor akcentu marki, a nie większe cyfry — większe rozjeżdżałyby
/// wysokość podpisu i zsuwały jeden tor niżej od pozostałych, czyli psuły
/// dokładnie tę siatkę, dla której ten układ powstał. Kolumna kalorii jest za
/// to SZERSZA: bierze tyle, ile potrzebuje jej podpis („kcal 2298/2300" to
/// słowo i dziewięć cyfr wobec litery i sześciu w makrach), a trzy makra
/// dzielą resztę po równo.
/// Przy czterech równych kolumnach kalorie musiały się kurczyć albo ucinać,
/// a makra stały z zapasem, którego nie miały na co wydać.
/// Pasek dzielony między trzy makra, który stał tu na początku, zniknął
/// z aplikacji razem z blokiem makra w Kalendarzu: odpowiadał na „z czego
/// składa się to, co zjadłem", a pigułka pyta „ile mi zostało".
///
/// **Ile zostało do celu nie stoi już nigdzie na ekranie.** Jest do policzenia
/// z „1135/2100", a tor obok mówi to samo bez czytania. VoiceOver dostaje tę
/// liczbę nadal, bo dla niego tor nie istnieje.
///
/// Szerokość pigułki ustawia `WeeklyPlanView` — to ona zna wymiar zakładki.
/// Cztery kolumny potrzebują jej więcej niż dwa wiersze po trzy, bo najdłuższy
/// podpis („kcal 1135/2100") musi się zmieścić obok trzech makr.
///
/// **Na „Dziś” ten sam jeden wiersz** (Rafał 6.10.2026 wieczór: „kompaktowe,
/// czytelne i mieści się w 1 wierszu”). Zdanie „Zjedzone X z Y kcal · w planie
/// Z” nad makrami z tego samego dnia odpadło — pigułka miała przez nie dwa
/// układy, a przejście między nimi „nie siedziało”. Dziś liczy ZJEDZONE,
/// a plan dnia stoi bladą warstwą pod każdym torem (`planned`), więc poranne
/// „kcal 0/2100” nie wygląda jak plan, który zginął.
///
/// **Przejście Plan ↔ Dziś**: ten sam układ, więc przechodzą LICZBY. Pigułka
/// zakładki, na którą się weszło, staje na pierwszej klatce z liczbami
/// pigułki poprzedniej (`PlanDayGoalFace` z `SCTabBarChrome.goalBarFaces`),
/// a potem cyfry rolują się do własnych (`numericText`, jak każda liczba
/// w aplikacji), a tory dojeżdżają.
struct PlanDayGoalBar: View {
    let nutrition: PlanDayNutrition
    let targets: DailyNutritionTargets
    /// Do ilu dojdzie dzień, jeśli zjeść wszystko, co w nim stoi.
    ///
    /// Pigułka pokazuje ZJEDZONE, więc dzień, którego nikt jeszcze nie
    /// odhaczył, ma w niej same zera — i wygląda identycznie jak dzień,
    /// w którym nie ma czego jeść. Blada warstwa pod każdym torem rozdziela
    /// te dwa stany, nie dokładając ani jednej liczby: pokazuje, dokąd tor
    /// dojdzie, tym samym kolorem, tylko ściszonym.
    ///
    /// `nil` w Planie tygodnia — tam pigułka liczy SAM plan, więc zapowiadać
    /// go drugi raz nie ma czym. Podane na zakładce „Dziś”.
    var planned: PlanDayNutrition?
    /// Zakładka, na której stoi pigułka (`.plan` / `.calendar`) — do przejścia
    /// z pigułki drugiej z nich.
    let tab: DashboardTab
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scTabIsActive) private var isActiveTab
    @Environment(\.scTabBarChrome) private var tabBarChrome
    @Environment(\.sessionStore) private var sessionStore

    /// Twarz pigułki z poprzedniej zakładki na czas przejścia — `nil` = własna.
    @State private var handoff: PlanDayGoalFace?
    /// Trwa przejście — kolumny dostają ruch przejścia zamiast zwykłej
    /// sprężyny zmiany liczb.
    @State private var isHandingOff = false

    /// Promień rogu szkła i obszaru dotyku — jedna liczba, żeby te dwa
    /// kształty nie mogły się rozjechać.
    private static let cornerRadius: CGFloat = 20

    /// Jedna sprężyna dla cyfr i torów pod nimi. `MacroProgressTrack` ma
    /// własną domyślną (0,4 s) i przy 0,36 s na cyfrach kreska lądowała
    /// chwilę po liczbie — dwie sprężyny w jednej kolumnie widać jako dwie.
    static let animation: Animation = .spring(response: 0.36, dampingFraction: 0.9)

    /// Ruch przejścia Plan ↔ Pulpit — cyfry i tor KAŻDEJ kolumny jednym
    /// ruchem (te same 0,55 s), kolumny ruszają po kolei co 0,05 s: kcal, B,
    /// T, W. Wcześniej cyfry jechały krzywą rolowania tekstu (0,42 s), a tory
    /// własną sprężyną (0,36 s) — liczba i pasek pod nią lądowały osobno.
    private static let handoffMotion: Animation = .smooth(duration: 0.55)
    private static let handoffStagger: Double = 0.05

    /// Własne liczby pigułki.
    private var ownFace: PlanDayGoalFace {
        PlanDayGoalFace(nutrition: nutrition, targets: targets, planned: planned)
    }

    /// To, co pigułka rysuje: w trakcie przejścia twarz z poprzedniej
    /// zakładki, potem własna.
    private var face: PlanDayGoalFace { handoff ?? ownFace }

    /// Pigułka po drugiej stronie przejścia.
    private var handoffPartner: DashboardTab? {
        switch tab {
        case .plan: .calendar
        case .calendar: .plan
        default: nil
        }
    }

    /// Szerokość pigułki na zakładce o szerokości `pageWidth` — JEDNA reguła
    /// dla Planu i Pulpitu, żeby pigułka przy zmianie zakładki stała w tym
    /// samym miejscu i tej samej szerokości.
    ///
    /// Pigułka jest węższa od dolnego menu i to jest jedyna rzecz, która mówi,
    /// co jest nawigacją, a co podglądem: dwa paski tej samej szerokości jeden
    /// nad drugim czytały się jak dwa poziomy tego samego menu. Ile dokładnie —
    /// decydują podpisy: kolumna kalorii ma szerokość wzorca „kcal 8888/8888”
    /// (~95 pt), a trzy makra dzielą resztę po równo i każde musi zmieścić
    /// „B 112/110” (~60 pt). Stąd 0,82, a nie okrągłe dwie trzecie; podłoga
    /// 310 pt trzyma to samo na wąskich telefonach, sufit zostawia pigułkę
    /// w marginesach strony.
    static func width(in pageWidth: CGFloat) -> CGFloat {
        guard pageWidth > 0 else { return 0 }
        let limit = pageWidth - SCPageMetrics.horizontal * 2
        return min(max(pageWidth * 0.82, 310), limit)
    }

    var body: some View {
        bar
    }

    private var bar: some View {
        Button(action: action) {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                // `interactive()` daje szkłu reakcję na dotyk — tę samą, którą ma
                // dolne menu. `PlanPressStyle` dokłada ściśnięcie treści, więc
                // pigułka odpowiada dokładnie jak wiersz osi nad nią.
                // Czyste szkło, jak dolne menu (`scChromeGlass`). Tekst osi
                // przewijany pod pigułką przebijał przez nie ostro — dawniej gasiła
                // go kryjąca warstwa tła w szkle (matowa plama), teraz natywny
                // efekt krawędzi przewijania pod pigułką (`safeAreaBar`
                // w `WeeklyPlanView`).
                .scChromeGlass(in: .rect(cornerRadius: Self.cornerRadius), interactive: true)
                // Bez tego stuknięcie łapie się WYŁĄCZNIE na rysowanej treści:
                // na cyfrach, na literach i na kilku punktach pasków. Padding,
                // przerwy między kolumnami i całe tło szkła były martwe — pigułka
                // otwierała arkusz tylko wtedy, gdy palec trafił w tekst.
                // `glassEffect` sam obszaru dotyku nie ustawia, bo rysuje tło,
                // a nie kształt przycisku.
                .contentShape(
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                )
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .animation(Self.animation, value: ownFace.fingerprint)
        // `.combine`, nie `.contain`: każdy miernik ma własne zdanie z celem
        // („Białko: 100 ze 150 gramów, cel przekroczony") i scalenie skleja te
        // cztery zdania w jeden element, który NADAL jest przyciskiem.
        // `.contain` robił z pigułki kontener z czterema mierników w środku
        // i podpowiedzią „Otwiera cel dnia" na czymś, w co nie dało się
        // stuknąć — VoiceOver czytał liczby i nie miał czego aktywować.
        .accessibilityElement(children: .combine)
        .accessibilityHint("Otwiera cel dnia")
        // Własna twarz dla pigułki drugiej zakładki — przy każdej zmianie liczb.
        .onChange(of: ownFace.fingerprint, initial: true) { _, _ in
            tabBarChrome.goalBarFaces[tab] = ownFace
        }
        // Wejście na zakładkę z pigułki drugiej strony (Plan ↔ Dziś).
        // `initial`, bo `TabView` buduje zakładkę przy pierwszym wyborze
        // i wtedy flaga już jest `true`.
        .onChange(of: isActiveTab, initial: true) { _, active in
            guard active else { return }
            startHandoff()
        }
    }

    /// Pierwsza klatka = pigułka z poprzedniej zakładki, potem jednym ruchem
    /// własna.
    private func startHandoff() {
        guard !reduceMotion,
              let partner = handoffPartner,
              sessionStore.previousDashboardTab == partner,
              let from = tabBarChrome.goalBarFaces[partner],
              from.fingerprint != ownFace.fingerprint
        else { return }

        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            handoff = from
            isHandingOff = true
        }

        Task { @MainActor in
            // Klatka z twarzą poprzedniej zakładki musi wejść na ekran, zanim
            // ruszy przejście — inaczej SwiftUI zlepia oba zapisy w jeden.
            try? await Task.sleep(for: .milliseconds(32))
            withAnimation(Self.handoffMotion) { handoff = nil }
            // Po ostatniej kolumnie wraca zwykła sprężyna zmiany liczb.
            try? await Task.sleep(for: .milliseconds(800))
            isHandingOff = false
        }
    }

    /// Ruch kolumny `index` (0 = kalorie): w przejściu wspólny ruch
    /// z opóźnieniem kolumny, poza nim zwykła sprężyna zmiany liczb.
    private func motion(_ index: Int) -> Animation {
        guard isHandingOff else { return Self.animation }
        return Self.handoffMotion.delay(Double(index) * Self.handoffStagger)
    }

    /// Treść pigułki: cztery kolumny w jednym wierszu — kalorie i trzy makra.
    /// Na „Dziś” każda z bladą warstwą planu dnia pod torem.
    private var content: some View {
        let face = self.face
        return HStack(alignment: .top, spacing: 8) {
            // Szerokość kolumny kalorii z WZORCA „kcal 8888/8888”, nie z bieżących
            // liczb: przy „kcal 850/2100” kolumna była węższa niż przy
            // „kcal 1450/2100”, więc rolowanie liczb przy zmianie zakładki
            // i dnia przesuwało makra, a pigułka Planu i Pulpitu wyglądały na
            // różne (Rafał 6.10.2026: „trochę się rozszerza”). Wzorzec jest
            // niewidoczny, prawdziwy miernik leży na nim i wypełnia jego ramkę.
            MacroMeter(
                letter: "kcal",
                title: "",
                value: 8888,
                target: 8888,
                color: .clear,
                animation: nil
            )
            .hidden()
            .accessibilityHidden(true)
            .overlay(alignment: .leading) {
                MacroMeter(
                    letter: "kcal",
                    title: face.planned == nil ? "Kalorie" : "Zjedzone kalorie",
                    value: face.nutrition.kcal,
                    target: face.targets.kcal,
                    plannedValue: face.planned?.kcal,
                    color: SCMacroPalette.calories,
                    unit: "kilokalorii",
                    accessibilityDetail: kcalDetail(face),
                    animation: motion(0)
                )
            }
            .fixedSize(horizontal: true, vertical: false)

            macroMeters(face)
        }
    }

    /// Dopowiedzenie dla VoiceOver: ile zostaje do celu, a na „Dziś” także
    /// ile stoi w planie.
    private func kcalDetail(_ face: PlanDayGoalFace) -> String {
        guard let planned = face.planned else { return remainingDetail(face) }
        return remainingDetail(face)
            + (planned.kcal > 0 ? ", w planie \(planned.kcal) kilokalorii" : ", nic w planie")
    }

    /// „zostało 965 kilokalorii" albo „230 kilokalorii ponad cel" — to, co
    /// widać z paska, a czego nie słychać z dwóch liczb. Ile zostaje do celu,
    /// na ekranie nie stoi — idzie wyłącznie do opisu dla VoiceOver.
    private func remainingDetail(_ face: PlanDayGoalFace) -> String {
        let remaining = face.targets.kcal - face.nutrition.kcal
        return remaining >= 0
            ? "zostało \(remaining) kilokalorii"
            : "\(abs(remaining)) kilokalorii ponad cel"
    }

    /// Trzy kolumny makr — dopełnienie kolumny kalorii do czterech.
    ///
    /// Osobna funkcja, a nie trzy wywołania wprost w `body`: rozbija to
    /// jeden wielki `HStack` na dwa czytelne kawałki, a `Group` zachowuje
    /// płaską strukturę wiersza, więc kolumny nadal dzielą szerokość
    /// po równo — nie trzy czwarte na makra i jedna na kalorie.
    ///
    /// Bez policzonych celów makr (brak sylwetki w profilu) `MacroMeter`
    /// zostawia samą wartość i rezerwuje puste miejsce po torze — pusty pasek
    /// obiecywałby cel, którego nikt nie wyznaczył, a zwinięcie go rozjechałoby
    /// wysokość kolumn.
    private func macroMeters(_ face: PlanDayGoalFace) -> some View {
        Group {
            MacroMeter(
                letter: "B",
                title: "Białko",
                value: face.nutrition.protein,
                target: face.targets.macros?.proteinG,
                plannedValue: face.planned?.protein,
                color: SCMacroPalette.protein,
                animation: motion(1)
            )
            MacroMeter(
                letter: "T",
                title: "Tłuszcze",
                value: face.nutrition.fat,
                target: face.targets.macros?.fatG,
                plannedValue: face.planned?.fat,
                color: SCMacroPalette.fat,
                animation: motion(2)
            )
            MacroMeter(
                letter: "W",
                title: "Węgle",
                value: face.nutrition.carbs,
                target: face.targets.macros?.carbsG,
                plannedValue: face.planned?.carbs,
                color: SCMacroPalette.carbs,
                animation: motion(3)
            )
        }
    }
}

/// Wszystko, co pigułka kcal pokazuje — liczby i układ (z `planned` = układ
/// „Dziś”). Pigułka zakładki, na którą się weszło, startuje z twarzy pigułki
/// poprzedniej (`SCTabBarChrome.goalBarFaces`).
struct PlanDayGoalFace {
    let nutrition: PlanDayNutrition
    let targets: DailyNutritionTargets
    let planned: PlanDayNutrition?

    /// Wszystko, co ma przejść płynnie przy zmianie dnia, przy dołożeniu
    /// posiłku i po przestawieniu celu w Ustawieniach — jedna wartość, jedna
    /// sprężyna. Cele są w odcisku celowo: bez nich powrót z suwaka kalorii
    /// podmieniał mianownik i przeskakiwał cztery tory bez ruchu. Układ też
    /// (`planned` albo -1), więc twarze Planu i Dziś nigdy nie są równe.
    var fingerprint: String {
        let macros = targets.macros
        return "\(nutrition.kcal).\(nutrition.protein).\(nutrition.fat).\(nutrition.carbs)"
            + "|\(targets.kcal).\(macros?.proteinG ?? 0).\(macros?.fatG ?? 0).\(macros?.carbsG ?? 0)"
            + "|\(planned?.kcal ?? -1).\(planned?.protein ?? -1)"
            + ".\(planned?.fat ?? -1).\(planned?.carbs ?? -1)"
    }
}
