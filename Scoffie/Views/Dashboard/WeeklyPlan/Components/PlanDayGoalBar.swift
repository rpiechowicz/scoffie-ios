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
/// **Trzy osobne mierniki, nie jeden podzielony pasek.** Wcześniej stał tu
/// `MacroSegmentBar` — jeden tor podzielony na trzy kolory w proporcji kalorii
/// z makr. Mówił, z CZEGO SKŁADA SIĘ dzień, ale nie mówił, ile którego makra
/// zostało: dwa razy dłuższy segment białka mógł znaczyć zarówno „zrobione",
/// jak i „dopiero połowa". Teraz każde makro ma własny cel, własny tor
/// i własną szarą resztę, a podpis podaje wprost „B 100/150". Składowy pasek
/// nie znika z aplikacji — zostaje w Kalendarzu, gdzie pytanie brzmi właśnie
/// „z czego składa się to, co zjadłem".
///
/// **Dwa wiersze, nie trzy.** Mierniki są poziome (`MacroMeter`: podpis i tor
/// w jednej linii), bo podpis NAD paskiem robił z każdej kolumny drugi wiersz
/// i pigułka rosła do trzech poziomów tekstu — czytała się wtedy jak klocek
/// nad menu, a nie jak pasek. Cała reszta odchudzania (stopnie pisma, odstępy)
/// dawała po kilka punktów; ten jeden ruch daje kilkanaście.
///
/// Szerokość pigułki ustawia `WeeklyPlanView` — to ona zna wymiar zakładki,
/// a pigułka ma tylko wypełnić to, co dostanie. Poziomy miernik potrzebuje
/// miejsca na podpis I na tor, więc ta szerokość nie może już schodzić tak
/// nisko, jak przy wariancie z podpisem nad paskiem.
struct PlanDayGoalBar: View {
    let nutrition: PlanDayNutrition
    let targets: DailyNutritionTargets
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    /// Promień rogu szkła i obszaru dotyku — jedna liczba, żeby te dwa
    /// kształty nie mogły się rozjechać.
    private static let cornerRadius: CGFloat = 20

    /// Ile kalorii zostaje do celu; ujemne znaczy „ponad cel".
    private var remaining: Int { targets.kcal - nutrition.kcal }

    /// Podpis przy liczbie. Po przekroczeniu celu pokazujemy nadwyżkę, a nie
    /// zero — „0 kcal zostało" i „230 kcal ponad cel" to dwie różne wiadomości,
    /// a użytkownikowi potrzebna jest ta druga.
    private var caption: String {
        remaining >= 0 ? "kcal zostało" : "kcal ponad cel"
    }

    /// Wszystko, co ma przejść płynnie przy zmianie dnia i przy dołożeniu
    /// posiłku — jedna wartość, jedna sprężyna.
    private var fingerprint: String {
        "\(remaining).\(nutrition.kcal).\(nutrition.protein).\(nutrition.fat).\(nutrition.carbs)"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: String(abs(remaining)))
                        .font(.system(size: 15.5, weight: .heavy))
                        .tracking(-0.4)
                        .monospacedDigit()
                        .foregroundStyle(
                            remaining < 0 ? SCMacroPalette.calories : Color.scLabel(scheme)
                        )
                        .contentTransition(.numericText())

                    Text(caption)
                        .font(.system(size: 11.5, weight: .medium))
                        .tracking(-0.1)
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 8)

                    calorieCount
                }

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
            // przerwa pod `Spacer` i całe tło szkła były martwe — pigułka
            // otwierała arkusz tylko wtedy, gdy palec trafił w tekst.
            // `glassEffect` sam obszaru dotyku nie ustawia, bo rysuje tło,
            // a nie kształt przycisku.
            .contentShape(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            )
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .animation(.spring(response: 0.36, dampingFraction: 0.9), value: fingerprint)
        // `.contain`, nie `.ignore`: mierniki makr mają własne opisy z celami
        // („Białko: 100 ze 150 gramów, cel przekroczony") i scalenie wszystkiego
        // w jedno zdanie zjadałoby dokładnie tę część, dla której VoiceOver
        // przychodzi na ten pasek.
        .accessibilityElement(children: .contain)
        .accessibilityHint("Otwiera cel dnia")
    }

    /// „1135 / 2100" na prawym końcu wiersza.
    ///
    /// Wielka liczba obok mówi, ile ZOSTAŁO — a to jest odpowiedź bez pytania,
    /// dopóki nie widać, z ilu. Bez „kcal" na końcu, bo jednostka pada
    /// w podpisie tuż obok i drugi raz tylko zabierałaby miejsce.
    private var calorieCount: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: String(nutrition.kcal))
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(
                    remaining < 0 ? SCMacroPalette.calories : Color.scLabel(scheme)
                )
                .contentTransition(.numericText())

            Text(verbatim: "/ \(targets.kcal)")
                .font(.system(size: 9.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.scMuted(scheme))
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(calorieAccessibilityLabel)
    }

    /// Trzy równe kolumny: podpis „B 100/150" nad własnym torem makra.
    ///
    /// Bez policzonych celów makr (brak sylwetki w profilu) `MacroMeter`
    /// zostawia sam skład dnia i nie rysuje toru — pusty pasek obiecywałby
    /// cel, którego nikt nie wyznaczył.
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
                title: "Węgle",
                value: nutrition.carbs,
                target: targets.macros?.carbsG,
                color: SCMacroPalette.carbs
            )
        }
    }

    private var calorieAccessibilityLabel: String {
        remaining >= 0
            ? "Kalorie: \(nutrition.kcal) z \(targets.kcal), zostało \(remaining)"
            : "Kalorie: \(nutrition.kcal) z \(targets.kcal), \(abs(remaining)) ponad cel"
    }
}
