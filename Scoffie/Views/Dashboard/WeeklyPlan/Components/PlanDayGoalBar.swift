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
/// **Cztery mierniki jednego kształtu.** Kalorie zajmują pierwszy wiersz, trzy
/// makra dzielą drugi; każdy z podpisem „x/y" i własnym torem z szarą resztą.
/// Kalorie miały tu wcześniej osobny nagłówek — wielką liczbę „ile zostało",
/// podpis przy niej i licznik „1135 / 2100" na drugim końcu wiersza. Były to
/// trzy sposoby powiedzenia jednej rzeczy, każdy innym krojem, i to one robiły
/// z pigułki nagłówek z tabelką pod spodem zamiast czterech równorzędnych
/// pasków. `MacroSegmentBar`, który stał tu jeszcze wcześniej, nie znika
/// z aplikacji: zostaje w Kalendarzu, gdzie pytanie brzmi „z czego składa się
/// to, co zjadłem", a nie „ile mi zostało".
///
/// Miernik kalorii jest o pół stopnia większy i ma grubszy tor. To jedyna
/// hierarchia w pigułce — cztery identyczne wiersze czytałyby się jak lista,
/// a kalorie są tu pierwszą liczbą, nie czwartą.
///
/// **Ile zostało do celu nie stoi już nigdzie na ekranie.** Jest do policzenia
/// z „1135/2100", a pasek obok mówi to samo bez czytania — trzy warianty tej
/// jednej liczby w jednej pigułce były po prostu za dużo. VoiceOver dostaje ją
/// nadal, bo dla niego pasek nie istnieje.
///
/// Szerokość pigułki ustawia `WeeklyPlanView` — to ona zna wymiar zakładki,
/// a pigułka ma tylko wypełnić to, co dostanie. Poziomy miernik potrzebuje
/// miejsca na podpis I na tor, więc ta szerokość nie może schodzić zbyt nisko.
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
            VStack(alignment: .leading, spacing: 5) {
                MacroMeter(
                    letter: "kcal",
                    title: "Kalorie",
                    value: nutrition.kcal,
                    target: targets.kcal,
                    color: SCMacroPalette.calories,
                    unit: "kilokalorii",
                    accessibilityDetail: remainingDetail,
                    isProminent: true
                )

                macroMeters
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
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

    /// Trzy równe kolumny: podpis „B 100/150" i tor makra w jednej linii.
    ///
    /// Bez policzonych celów makr (brak sylwetki w profilu) `MacroMeter`
    /// zostawia samą wartość i nie rysuje toru — pusty pasek obiecywałby cel,
    /// którego nikt nie wyznaczył.
    private var macroMeters: some View {
        HStack(alignment: .center, spacing: 12) {
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
