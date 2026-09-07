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
/// `glassEffect` zamiast `dashboardLiquidCard()`, którego używa reszta
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
/// `MacroSegmentBar`, który stał tu na początku, zostaje w Kalendarzu: tam
/// pytanie brzmi „z czego składa się to, co zjadłem", a nie „ile mi zostało".
///
/// **Ile zostało do celu nie stoi już nigdzie na ekranie.** Jest do policzenia
/// z „1135/2100", a tor obok mówi to samo bez czytania. VoiceOver dostaje tę
/// liczbę nadal, bo dla niego tor nie istnieje.
///
/// Szerokość pigułki ustawia `WeeklyPlanView` — to ona zna wymiar zakładki.
/// Cztery kolumny potrzebują jej więcej niż dwa wiersze po trzy, bo najdłuższy
/// podpis („kcal 1135/2100") musi się zmieścić obok trzech makr.
struct PlanDayGoalBar: View {
    let nutrition: PlanDayNutrition
    let targets: DailyNutritionTargets
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

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
    }

    /// Jedna sprężyna dla cyfr i torów pod nimi. `MacroProgressTrack` ma
    /// własną domyślną (0,4 s) i przy 0,36 s na cyfrach kreska lądowała
    /// chwilę po liczbie — dwie sprężyny w jednej kolumnie widać jako dwie.
    static let animation: Animation = .spring(response: 0.36, dampingFraction: 0.9)

    var body: some View {
        Button(action: action) {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            // `interactive()` daje szkłu reakcję na dotyk — tę samą, którą ma
            // dolne menu. `PlanPressStyle` dokłada ściśnięcie treści, więc
            // pigułka odpowiada dokładnie jak wiersz osi nad nią.
            // Samo `.regular` przepuszczało tekst osi przewijany pod pigułką
            // na tyle wyraźnie, że przy górnej krawędzi wyglądał jak artefakt
            // renderowania. Sam `tint` tego nie gasił — barwi szkło, ale nie
            // zasłania. Stąd warstwa tła strony POD szkłem: to ona przygasza
            // przelatującą treść do rozmytej plamy, a odblaski i reakcja na
            // dotyk zostają na szkle nad nią.
            .glassEffect(
                .regular.tint(Color.scPageBase(scheme).opacity(0.35)).interactive(),
                in: .rect(cornerRadius: Self.cornerRadius)
            )
            .background(
                Color.scPageBase(scheme).opacity(0.72),
                in: .rect(cornerRadius: Self.cornerRadius)
            )
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
                color: SCMacroPalette.protein,
                animation: Self.animation
            )
            MacroMeter(
                letter: "T",
                title: "Tłuszcze",
                value: nutrition.fat,
                target: targets.macros?.fatG,
                color: SCMacroPalette.fat,
                animation: Self.animation
            )
            MacroMeter(
                letter: "W",
                title: "Węgle",
                value: nutrition.carbs,
                target: targets.macros?.carbsG,
                color: SCMacroPalette.carbs,
                animation: Self.animation
            )
        }
    }
}
