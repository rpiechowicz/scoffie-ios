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
struct PlanDayGoalBar: View {
    let nutrition: PlanDayNutrition
    let targets: DailyNutritionTargets
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    /// Promień rogu szkła i obszaru dotyku — jedna liczba, żeby te dwa
    /// kształty nie mogły się rozjechać.
    private static let cornerRadius: CGFloat = 22

    /// Ile kalorii zostaje do celu; ujemne znaczy „ponad cel".
    private var remaining: Int { targets.kcal - nutrition.kcal }

    private var fillFraction: CGFloat {
        CGFloat(nutrition.kcal) / CGFloat(max(targets.kcal, 1))
    }

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
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: String(abs(remaining)))
                        .font(.system(size: 17, weight: .heavy))
                        .tracking(-0.4)
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(scheme))
                        .contentTransition(.numericText())

                    Text(caption)
                        .font(.system(size: 12.5, weight: .medium))
                        .tracking(-0.1)
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)

                    Spacer(minLength: 10)

                    macroTriple
                }

                // Pasek NIE idzie przez całą szerokość pigułki, tylko dzieli
                // wiersz z licznikiem „zjedzone / cel". Dwa powody: pasek na
                // całość ciągnął oko na sam dół i wyglądał jak kreska pod
                // treścią, a nie jak jej część; a sama proporcja („965 zostało"
                // to ile właściwie z ilu?) nie miała gdzie paść. Podziału nie
                // wymuszam ułamkiem — licznik bierze tyle, ile potrzebuje na
                // swoje cyfry, pasek resztę, i przy typowych wartościach
                // wychodzi z tego mniej więcej dwie trzecie na pasek.
                HStack(alignment: .center, spacing: 10) {
                    MacroSegmentBar(
                        protein: nutrition.protein,
                        fat: nutrition.fat,
                        carbs: nutrition.carbs,
                        fillFraction: fillFraction
                    )
                    .frame(maxWidth: .infinity)

                    progressCount
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            // `interactive()` daje szkłu reakcję na dotyk — tę samą, którą ma
            // dolne menu. `PlanPressStyle` dokłada ściśnięcie treści, więc
            // pigułka odpowiada dokładnie jak wiersz osi nad nią.
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Self.cornerRadius))
            // Bez tego stuknięcie łapie się WYŁĄCZNIE na rysowanej treści:
            // na cyfrach, na literach i na czterech punktach paska. Padding,
            // przerwa pod `Spacer` między podpisem a makrami i całe tło szkła
            // były martwe — pigułka otwierała arkusz tylko wtedy, gdy palec
            // trafił w tekst, a przy trafieniu obok nie działo się nic.
            // `glassEffect` sam obszaru dotyku nie ustawia, bo rysuje tło,
            // a nie kształt przycisku.
            .contentShape(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            )
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .animation(.spring(response: 0.36, dampingFraction: 0.9), value: fingerprint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Otwiera cel dnia")
        .accessibilityAddTraits(.isButton)
    }

    /// „1135 / 2100 kcal" na prawym końcu paska.
    ///
    /// Wielka liczba u góry mówi, ile ZOSTAŁO — a to jest odpowiedź bez
    /// pytania, dopóki nie widać, z ilu. Po przekroczeniu celu zjedzone idzie
    /// w kolor kalorii, żeby przejście przez cel było widać także tutaj,
    /// a nie tylko w podpisie nad paskiem.
    private var progressCount: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: String(nutrition.kcal))
                .font(.system(size: 11.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(remaining < 0 ? SCMacroPalette.calories : Color.scLabel(scheme))
                .contentTransition(.numericText())

            Text(verbatim: "/ \(targets.kcal) kcal")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.scMuted(scheme))
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// „B 71 · T 56 · W 95" — te same trzy litery, co w liczniku pod osią
    /// i w podsumowaniu Kalendarza, w tych samych trzech kolorach.
    private var macroTriple: some View {
        HStack(spacing: 10) {
            macroChip("B", value: nutrition.protein, color: SCMacroPalette.protein)
            macroChip("T", value: nutrition.fat, color: SCMacroPalette.fat)
            macroChip("W", value: nutrition.carbs, color: SCMacroPalette.carbs)
        }
        .fixedSize()
    }

    private func macroChip(_ letter: String, value: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(letter)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(color)

            Text(verbatim: String(value))
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.scLabel(scheme))
                .contentTransition(.numericText())
        }
    }

    private var accessibilityLabel: String {
        let head = remaining >= 0
            ? "Zostało \(remaining) kilokalorii z \(targets.kcal)"
            : "\(abs(remaining)) kilokalorii ponad cel \(targets.kcal)"
        return "\(head). Białko \(nutrition.protein) gramów, tłuszcze \(nutrition.fat) gramów, węglowodany \(nutrition.carbs) gramów."
    }
}
