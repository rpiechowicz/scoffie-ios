import SwiftUI

/// Krok 0 przepływu startowego — „Poznaj asystenta". Zaproszenie, nie
/// instrukcja — RODO, dostawca modelu i limity pojawiają się dopiero
/// w kroku „Zgoda", gdzie użytkownik faktycznie decyduje.
///
/// Układ powitania przewodnika „Poznaj aplikację” (`TourIntroView`): znak,
/// nagłówek kroku (`SCStepHeader`) i karta funkcji (`SCStepFeatureCard`).
/// Wiersze karty to tytuły czterech kart „Poznaj”, które przyjdą po zgodzie,
/// z ich ikonami i kolorami — powitanie zapowiada dokładnie to, co za chwilę
/// pokaże, zamiast osobnej listy ptaszków o tym samym.
///
/// Sama treść: „Zaczynamy" i „Zobacz wszystko, co potrafi" są w stopce
/// przepływu (`AssistantIntroFooter`), którą składa `AssistantView` poza
/// animowanym obszarem — jak w przewodniku.
struct AssistantWelcomeView: View {
    private var features: [SCStepFeature] {
        AssistantCapabilities.onboarding.map { card in
            SCStepFeature(icon: card.icon, accent: card.accent.color, title: card.title)
        }
    }

    var body: some View {
        // `basedOnSize`: przy zwykłej czcionce kontener stoi (nie pływa
        // pod palcem), a przy dużej Dynamic Type treść daje się dosunąć.
        // Pion liczony pod iPhone'a z ekranem 852 pt: nagłówek zakładki,
        // ta treść (~420), stopka (~120) i tab bar — ostatni wiersz karty
        // ma stać NAD cieniem stopki, nie pod nim.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AssistantAIMark(size: 56)
                    .padding(.bottom, 18)

                SCStepHeader(
                    eyebrow: "Asystent AI",
                    title: "Poznaj asystenta",
                    subtitle: "Układa plan, podmienia dania i pilnuje alergenów całego domu. Zatwierdzasz Ty."
                )
                .padding(.bottom, 22)

                SCStepFeatureCard(features: features)
            }
            .padding(.horizontal, SCPageMetrics.horizontal)
            .padding(.top, 12)
            // Zapas na cień stopki (`SCEdgeShade`), gdy jednak trzeba przewinąć.
            .padding(.bottom, SCEdgeShade.bottomHeight + 4)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }
}
