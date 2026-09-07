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
/// każde z podpisem „K 1135/2100" i torem pod spodem na pełną szerokość swojej
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
/// Wszystkie cztery kolumny są równe i tego samego rozmiaru. Kalorie wyróżnia
/// pierwsze miejsce i kolor akcentu marki, a nie większy stopień pisma —
/// większy rozjeżdżałby wysokość podpisu i zsuwał jeden tor niżej od
/// pozostałych, czyli psuł dokładnie tę siatkę, dla której ten układ powstał.
/// `MacroSegmentBar`, który stał tu na początku, zostaje w Kalendarzu: tam
/// pytanie brzmi „z czego składa się to, co zjadłem", a nie „ile mi zostało".
///
/// **Ile zostało do celu nie stoi już nigdzie na ekranie.** Jest do policzenia
/// z „1135/2100", a tor obok mówi to samo bez czytania. VoiceOver dostaje tę
/// liczbę nadal, bo dla niego tor nie istnieje.
///
/// Szerokość pigułki ustawia `WeeklyPlanView` — to ona zna wymiar zakładki.
/// Cztery kolumny potrzebują jej więcej niż dwa wiersze po trzy, bo najdłuższy
/// podpis („K 1135/2100") musi się zmieścić w jednej czwartej.
struct PlanDayGoalBar: View {
    let nutrition: PlanDayNutrition
    let targets: DailyNutritionTargets
    let action: () -> Void

    /// Promień rogu szkła i obszaru dotyku — jedna liczba, żeby te dwa
    /// kształty nie mogły się rozjechać.
    private static let cornerRadius: CGFloat = 20

    /// Ile kalorii zostaje do celu; ujemne znaczy „ponad cel". Na ekranie tej
    /// liczby nie ma — idzie wyłącznie do opisu dla VoiceOver.
    private var remaining: Int { targets.kcal - nutrition.kcal }

    /// Wszystko, co ma przejść płynnie przy zmianie dnia i przy dołożeniu
    /// posiłku — jedna wartość, jedna sprężyna.
    private var fingerprint: String {
        "\(nutrition.kcal).\(nutrition.protein).\(nutrition.fat).\(nutrition.carbs)"
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                MacroMeter(
                    letter: "K",
                    title: "Kalorie",
                    value: nutrition.kcal,
                    target: targets.kcal,
                    color: SCMacroPalette.calories,
                    unit: "kilokalorii",
                    accessibilityDetail: remainingDetail
                )

                macroMeters
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            // `interactive()` daje szkłu reakcję na dotyk — tę samą, którą ma
            // dolne menu. `PlanPressStyle` dokłada ściśnięcie treści, więc
            // pigułka odpowiada dokładnie jak wiersz osi nad nią.
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Self.cornerRadius))
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
        .animation(.spring(response: 0.36, dampingFraction: 0.9), value: fingerprint)
        // `.contain`, nie `.ignore`: każdy miernik ma własne zdanie z celem
        // („Białko: 100 ze 150 gramów, cel przekroczony") i scalenie wszystkiego
        // w jedno zjadałoby dokładnie tę część, dla której VoiceOver przychodzi
        // na ten pasek.
        .accessibilityElement(children: .contain)
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
                color: SCMacroPalette.protein
            )
            MacroMeter(
                letter: "T",
                title: "Tłuszcze",
                value: nutrition.fat,
                target: targets.macros?.fatG,
                color: SCMacroPalette.fat
            )
            MacroMeter(
                letter: "W",
                title: "Węglowodany",
                value: nutrition.carbs,
                target: targets.macros?.carbsG,
                color: SCMacroPalette.carbs
            )
        }
    }
}
