import SwiftUI

/// Krok 0 przepływu startowego — „Poznaj asystenta". Hero, nie lista:
/// duża ikona AI, tytuł na dwie linie, cztery haczyki. Zaproszenie, nie
/// instrukcja — RODO, dostawca modelu i limity pojawiają się dopiero
/// w kroku „Zgoda", gdzie użytkownik faktycznie decyduje.
///
/// Sama treść: „Zaczynamy" i „Zobacz wszystko, co potrafi" są w stopce
/// przepływu (`AssistantIntroFooter`), którą składa `AssistantView` poza
/// animowanym obszarem — jak w przewodniku „Poznaj aplikację".
struct AssistantWelcomeView: View {
    @Environment(\.colorScheme) private var scheme

    private let ticks = [
        "Plan tygodnia albo jednego dnia",
        "Podmiany i domykanie makro",
        "Cały dom albo tylko Ty",
        "Zakupy i własne przepisy",
    ]

    var body: some View {
        // `basedOnSize`: przy zwykłej czcionce kontener stoi (nie pływa
        // pod palcem), a przy dużej Dynamic Type treść daje się dosunąć.
        // Pion jest policzony pod iPhone'a z ekranem 852 pt: nagłówek (128)
        // + ta treść (~490) + stopka (118) + tab bar (83) — czwarty haczyk
        // ma stać NAD gradientem stopki, nie pod nim. Każde powiększenie
        // czegoś tutaj trzeba odjąć gdzie indziej.
        ScrollView {
            VStack(spacing: 0) {
                // Poświata sięga ~50 pt poza ikonę, a ScrollView tnie po
                // swojej krawędzi — bez tego zapasu górna część cienia
                // ginęła pod nagłówkiem.
                AssistantAIMark(size: 100)
                    .padding(.top, 36)

                AssistantSectionLabel(text: "Asystent AI", color: SCPalette.terracotta)
                    .padding(.top, 22)

                Text("Poznaj\nasystenta")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.9)
                    .lineSpacing(0)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.scLabel(scheme))
                    .padding(.top, 6)

                Text("Układa plan tygodnia, podmienia dania i pilnuje alergenów całego domu. Każdą propozycję pokazuje jako kartę, którą zatwierdzasz Ty.")
                    .font(.system(size: 15))
                    .tracking(-0.2)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.scMuted(scheme))
                    .frame(maxWidth: 320)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                // Wyrównane do lewej, ale blok jako całość centrowany.
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ticks, id: \.self) { AssistantTickRow(text: $0) }
                }
                .padding(.top, 22)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, SCPageMetrics.horizontal)
            // Zapas na gradient stopki (36 pt), gdy jednak trzeba przewinąć.
            .padding(.bottom, 40)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }
}
