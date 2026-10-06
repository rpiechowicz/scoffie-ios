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
/// **Na „Dziś” pigułka MÓWI, co liczy** (6.10.2026, Plan i Kalendarz
/// z wyostrzonymi rolami). Plan sumuje to, co zaplanowane, a „Dziś” — to, co
/// odhaczone; ta sama pigułka z „kcal 0/2100” rano wyglądała jak plan, który
/// gdzieś zginął. Z `planned` (tylko „Dziś”) nad makrami stoi więc zdanie
/// „Zjedzone 1200 z 2100 kcal · w planie 1800” z torem kalorii pod spodem,
/// a kolumna kalorii schodzi z rzędu — te same liczby nie stoją dwa razy.
///
/// Pigułki Planu i „Dziś” NIE przechodzą jedna w drugą przy zmianie zakładki
/// (dawne `handoff` przez `SCTabBarChrome.goalSnapshot`, 4.10.2026): to dwie
/// różne liczby, a rosnące tory mówiły, że to jedna, która się zmieniła.
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
    /// go drugi raz nie ma czym. Podane (zakładka „Dziś”) przełącza też układ
    /// na zdanie „Zjedzone … · w planie …” — patrz komentarz typu.
    var planned: PlanDayNutrition?
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    // Zdanie „Zjedzone … · w planie …” w stopniach `MacroMeter` (wartość 13,
    // reszta 11), skalowanych z Dynamic Type tak samo jak tamte podpisy.
    @ScaledMetric(relativeTo: .footnote) private var summaryValueSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption2) private var summaryTextSize: CGFloat = 11

    /// Promień rogu szkła i obszaru dotyku — jedna liczba, żeby te dwa
    /// kształty nie mogły się rozjechać.
    private static let cornerRadius: CGFloat = 20

    /// Ile kalorii zostaje do celu; ujemne znaczy „ponad cel". Na ekranie tej
    /// liczby nie ma — idzie wyłącznie do opisu dla VoiceOver.
    private var remaining: Int { targets.kcal - nutrition.kcal }

    /// Wszystko, co ma przejść płynnie przy zmianie dnia, przy dołożeniu
    /// posiłku i po przestawieniu celu w Ustawieniach — jedna wartość, jedna
    /// sprężyna. Cele są w odcisku celowo: bez nich powrót z suwaka kalorii
    /// podmieniał mianownik i przeskakiwał cztery tory bez ruchu.
    private var fingerprint: String {
        let macros = targets.macros
        return "\(nutrition.kcal).\(nutrition.protein).\(nutrition.fat).\(nutrition.carbs)"
            + "|\(targets.kcal).\(macros?.proteinG ?? 0).\(macros?.fatG ?? 0).\(macros?.carbsG ?? 0)"
            + "|\(planned?.kcal ?? -1).\(planned?.protein ?? -1)"
            + ".\(planned?.fat ?? -1).\(planned?.carbs ?? -1)"
    }

    /// Jedna sprężyna dla cyfr i torów pod nimi. `MacroProgressTrack` ma
    /// własną domyślną (0,4 s) i przy 0,36 s na cyfrach kreska lądowała
    /// chwilę po liczbie — dwie sprężyny w jednej kolumnie widać jako dwie.
    static let animation: Animation = .spring(response: 0.36, dampingFraction: 0.9)

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
        .animation(Self.animation, value: fingerprint)
        // `.combine`, nie `.contain`: każdy miernik ma własne zdanie z celem
        // („Białko: 100 ze 150 gramów, cel przekroczony") i scalenie skleja te
        // cztery zdania w jeden element, który NADAL jest przyciskiem.
        // `.contain` robił z pigułki kontener z czterema mierników w środku
        // i podpowiedzią „Otwiera cel dnia" na czymś, w co nie dało się
        // stuknąć — VoiceOver czytał liczby i nie miał czego aktywować.
        .accessibilityElement(children: .combine)
        .accessibilityHint("Otwiera cel dnia")
    }

    /// Treść pigułki: w Planie cztery kolumny w jednym wierszu, na „Dziś”
    /// zdanie o zjedzonych i planie nad trzema makrami.
    @ViewBuilder
    private var content: some View {
        if let planned {
            VStack(alignment: .leading, spacing: 6) {
                eatenSummary(planned: planned)
                HStack(alignment: .top, spacing: 8) {
                    macroMeters
                }
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                MacroMeter(
                    letter: "kcal",
                    title: "Kalorie",
                    value: nutrition.kcal,
                    target: targets.kcal,
                    color: SCMacroPalette.calories,
                    unit: "kilokalorii",
                    accessibilityDetail: remainingDetail,
                    animation: Self.animation
                )
                // Szerokość z podpisu, nie z podziału na cztery — patrz
                // komentarz typu. Tor pod spodem i tak wypełnia całą kolumnę.
                .fixedSize(horizontal: true, vertical: false)

                macroMeters
            }
        }
    }

    /// „Zjedzone 1200 z 2100 kcal” · „w planie 1800” i tor kalorii na całą
    /// szerokość pigułki — zjedzone pełnym kolorem, plan dnia blado pod nim
    /// (`MacroProgressTrack.plannedProgress`, ta sama warstwa co dotąd).
    private func eatenSummary(planned: PlanDayNutrition) -> some View {
        let target = targets.kcal
        let progress = target > 0 ? Double(nutrition.kcal) / Double(target) : 0
        let plannedProgress: Double? = target > 0 && planned.kcal > nutrition.kcal
            ? Double(planned.kcal) / Double(target)
            : nil

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                eatenText
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)

                Spacer(minLength: 4)

                plannedText(planned.kcal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .contentTransition(.numericText())

            MacroProgressTrack(
                progress: progress,
                color: SCMacroPalette.calories,
                plannedProgress: plannedProgress,
                height: 4,
                animation: Self.animation
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Zjedzone: \(nutrition.kcal) z \(target) kilokalorii, \(remainingDetail), "
                + (planned.kcal > 0 ? "w planie \(planned.kcal) kilokalorii" : "nic w planie")
        )
    }

    /// „Zjedzone 1200 z 2100 kcal” — jeden `Text`, żeby całość skalowała się
    /// razem i nigdy nie ucinała liczby (ta sama zasada co `MacroMeter.label`).
    private var eatenText: Text {
        let lead = Text("Zjedzone")
            .font(.system(size: summaryTextSize, weight: .bold))
            .foregroundStyle(SCMacroPalette.calories)
        let value = Text(verbatim: String(nutrition.kcal))
            .font(.system(size: summaryValueSize, weight: .bold).monospacedDigit())
            .foregroundStyle(nutrition.kcal > targets.kcal ? SCMacroPalette.calories : Color.scLabel(scheme))
        let goal = Text(verbatim: "z \(targets.kcal) kcal")
            .font(.system(size: summaryTextSize, weight: .semibold).monospacedDigit())
            .foregroundStyle(Color.scMuted(scheme))
        return Text("\(lead) \(value) \(goal)")
    }

    /// „w planie 1800” — ile stoi w planie TEGO dnia dla mnie. Dzień bez
    /// planu mówi to słowami, a nie zerem.
    private func plannedText(_ kcal: Int) -> Text {
        guard kcal > 0 else {
            return Text("nic w planie")
                .font(.system(size: summaryTextSize, weight: .semibold))
                .foregroundStyle(Color.scMuted(scheme))
        }
        let lead = Text("w planie")
            .font(.system(size: summaryTextSize, weight: .semibold))
            .foregroundStyle(Color.scMuted(scheme))
        let value = Text(verbatim: String(kcal))
            .font(.system(size: summaryTextSize, weight: .bold).monospacedDigit())
            .foregroundStyle(Color.scLabel(scheme))
        return Text("\(lead) \(value)")
    }

    /// „zostało 965 kilokalorii" albo „230 kilokalorii ponad cel" — to, co
    /// widać z paska, a czego nie słychać z dwóch liczb.
    private var remainingDetail: String {
        remaining >= 0
            ? "zostało \(remaining) kilokalorii"
            : "\(abs(remaining)) kilokalorii ponad cel"
    }

    /// Trzy kolumny makr — dopełnienie kolumny kalorii do czterech.
    ///
    /// Osobna właściwość, a nie trzy wywołania wprost w `body`: rozbija to
    /// jeden wielki `HStack` na dwa czytelne kawałki, a `Group` zachowuje
    /// płaską strukturę wiersza, więc kolumny nadal dzielą szerokość
    /// po równo — nie trzy czwarte na makra i jedna na kalorie.
    ///
    /// Bez policzonych celów makr (brak sylwetki w profilu) `MacroMeter`
    /// zostawia samą wartość i rezerwuje puste miejsce po torze — pusty pasek
    /// obiecywałby cel, którego nikt nie wyznaczył, a zwinięcie go rozjechałoby
    /// wysokość kolumn.
    private var macroMeters: some View {
        Group {
            MacroMeter(
                letter: "B",
                title: "Białko",
                value: nutrition.protein,
                target: targets.macros?.proteinG,
                plannedValue: planned?.protein,
                color: SCMacroPalette.protein,
                animation: Self.animation
            )
            MacroMeter(
                letter: "T",
                title: "Tłuszcze",
                value: nutrition.fat,
                target: targets.macros?.fatG,
                plannedValue: planned?.fat,
                color: SCMacroPalette.fat,
                animation: Self.animation
            )
            MacroMeter(
                letter: "W",
                title: "Węgle",
                value: nutrition.carbs,
                target: targets.macros?.carbsG,
                plannedValue: planned?.carbs,
                color: SCMacroPalette.carbs,
                animation: Self.animation
            )
        }
    }
}
