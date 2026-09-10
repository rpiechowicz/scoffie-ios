import SwiftUI

// Kalendarz v4 — dopisek pod listą posiłków.
//
// Źródło: canvas claude.ai → „Weekly Meals - Kalendarz v4.html”,
// `components/cal-v4.jsx` (blok `empty` w `C4Day`). Mówi to, czego lista
// sama z siebie nie powie, i pojawia się wyłącznie wtedy, gdy jest o czym
// mówić.
//
// Makieta stawiała tu jeszcze „Odhacz cały dzień” z podsumowaniem kalorii
// pod dniem minionym. Zeszło z ekranu: dzień, w którym nikt nic nie
// odhaczył, ma to napisane w środku łuku, a jedno stuknięcie zapisujące
// pięć posiłków naraz jest deklaracją, nie zapisem.

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

#Preview("Pusty dzień") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()

        VStack(alignment: .leading, spacing: 32) {
            CalendarEmptyDayNote(canPlan: true, onAskAssistant: {}, onOpenPlan: {})
            CalendarEmptyDayNote(canPlan: false, onAskAssistant: {}, onOpenPlan: {})
        }
        .padding(.horizontal, SCPageMetrics.horizontal)
    }
    .preferredColorScheme(.dark)
}
