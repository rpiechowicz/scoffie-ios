import SwiftUI

// Kalendarz v4 — dwa dopiski pod listą posiłków.
//
// Źródło: canvas claude.ai → „Weekly Meals - Kalendarz v4.html”,
// `components/cal-v4.jsx` (bloki `empty` i `past` w `C4Day`). Oba mówią to,
// czego lista sama z siebie nie powie, i oba pojawiają się wyłącznie wtedy,
// gdy jest o czym mówić.

// MARK: - Pusty dzień

/// Dzień bez ani jednego posiłku: jedno zdanie o tym, gdzie się go układa,
/// i dwa wyjścia.
///
/// Wcześniej pusty dzień był stosem trzech identycznych wierszy „Nic nie
/// zaplanowano · Zaplanujesz w zakładce Plan” — po jednym na każdą włączoną
/// porę. Trzy razy to samo zdanie nie jest trzy razy mocniejsze, tylko trzy
/// razy głośniejsze. Jeden dopisek mówi dokładnie tyle samo i zostawia
/// miejsce na dwa przyciski, które faktycznie coś robią.
///
/// Kalendarz NIE planuje — to jest reguła całej zakładki, nie oszczędność
/// w tym widoku. Dlatego oba wyjścia prowadzą stąd gdzie indziej: do
/// asystenta, który ułoży dzień, albo do Planu tygodnia, gdzie posiłki
/// dodaje się ręką.
struct CalendarEmptyDayNote: View {
    /// Czy dzień w ogóle da się jeszcze zaplanować. Przeszłości nie —
    /// i wtedy zostaje samo wyjaśnienie, bez przycisków prowadzących
    /// donikąd.
    let canPlan: Bool
    let onAskAssistant: () -> Void
    let onOpenPlan: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                // Ikona z dolnego menu, nie własna: dopisek mówi „idź do
                // Planu”, a użytkownik ma tam trafić wzrokiem po tym samym
                // znaku, który widzi w pasku pod spodem.
                Image(systemName: MenuConstans.Plan.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.scMuted(scheme))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.scChipBg(scheme)))
                    .overlay(Circle().strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Dzień układasz w Planie tygodnia")
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(scheme))
                        // Bez limitu linii: „Dzień układasz w Planie
                        // tygodnia” mieści się w jednej linii na iPhonie
                        // 15 Pro i w dwóch na SE — i w obu przypadkach ma
                        // się złamać, a nie skurczyć.
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Kalendarz pokazuje, co i kiedy jeść, i odhacza zjedzone. Posiłki dodaje się i zamienia w Planie.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.scFaint(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if canPlan {
                HStack(spacing: 10) {
                    EditorialPrimaryActionButton(
                        title: "Ułóż dzień",
                        icon: MenuConstans.Assistant.icon,
                        action: onAskAssistant
                    )

                    EditorialPrimaryActionButton(
                        title: "Otwórz Plan",
                        icon: MenuConstans.Plan.icon,
                        accent: Color.scLabel(scheme),
                        action: onOpenPlan
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Nadrobienie minionego dnia

/// „Odhacz cały dzień” — jedno stuknięcie dla dnia, w którym nikt nie
/// odhaczał na bieżąco.
///
/// Stoi wyłącznie pod dniem MINIONYM i wyłącznie wtedy, gdy zostało co
/// odhaczać. W dzisiejszym dniu byłby to guzik „zjadłem wszystko, także
/// kolację o 20:00”, czyli zapis nieprawdy — a w przyszłym nie ma nawet
/// czego zapisywać.
///
/// Obok stoi liczba, którą ten ruch dopisze do dnia, bo „odhacz wszystko”
/// bez niej jest skokiem w ciemno: 1135 kcal to zupełnie inna decyzja niż
/// 2900.
struct CalendarCatchUpRow: View {
    /// Ile kalorii dołoży odhaczenie reszty dnia.
    let missingKcal: Int
    /// Ile posiłków zostało — do podpisu dla VoiceOver.
    let missingMeals: Int
    let isBusy: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: action) {
                HStack(spacing: 7) {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(SCPalette.terracotta)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                    }

                    Text("Odhacz cały dzień")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(-0.1)
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(SCPalette.terracotta)
                .padding(.horizontal, 16)
                .frame(height: 42)
                .scSoftCapsule()
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .opacity(isBusy ? 0.7 : 1)
            .accessibilityLabel("Odhacz cały dzień")
            .accessibilityValue(
                "\(PolishPlural.meals(missingMeals)) do odhaczenia, \(missingKcal) kcal"
            )

            Text("\(missingKcal) kcal wg planu")
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(Color.scFaint(scheme))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                // Liczba stoi już w podpisie przycisku obok — VoiceOver
                // czytałby ją dwa razy pod rząd.
                .accessibilityHidden(true)

            Spacer(minLength: 0)
        }
        .padding(.top, 14)
        .animation(.smooth(duration: 0.2), value: isBusy)
    }
}

#Preview("Dopiski dnia") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()

        VStack(alignment: .leading, spacing: 32) {
            CalendarEmptyDayNote(canPlan: true, onAskAssistant: {}, onOpenPlan: {})
            CalendarEmptyDayNote(canPlan: false, onAskAssistant: {}, onOpenPlan: {})
            CalendarCatchUpRow(missingKcal: 1135, missingMeals: 3, isBusy: false, action: {})
            CalendarCatchUpRow(missingKcal: 1135, missingMeals: 3, isBusy: true, action: {})
        }
        .padding(.horizontal, SCPageMetrics.horizontal)
    }
    .preferredColorScheme(.dark)
}
