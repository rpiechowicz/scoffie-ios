import SwiftUI

/// Krok 0 przepływu startowego — „Poznaj asystenta". Hero, nie lista:
/// duża ikona AI, tytuł na dwie linie, cztery haczyki i pigułka zaufania.
/// Zaproszenie, nie instrukcja — RODO, dostawca modelu i limity pojawiają
/// się dopiero w kroku „Zgoda", gdzie użytkownik faktycznie decyduje.
struct AssistantWelcomeView: View {
    /// „Zaczynamy" — przejście do kroku „Zgoda".
    let onStart: () -> Void
    var onShowCapabilities: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    private let ticks = [
        "Plan tygodnia albo jednego dnia",
        "Podmiany i domykanie makro",
        "Cały dom albo tylko Ty",
        "Zakupy i własne przepisy",
    ]

    var body: some View {
        VStack(spacing: 0) {
            // `basedOnSize`: przy zwykłej czcionce kontener stoi (nie pływa
            // pod palcem), a przy dużej Dynamic Type treść daje się dosunąć.
            ScrollView {
                VStack(spacing: 0) {
                    // Poświata sięga ~50 pt poza ikonę, a ScrollView tnie po
                    // swojej krawędzi — bez tego zapasu górna część cienia
                    // ginęła pod nagłówkiem.
                    AssistantAIMark(size: 112)
                        .padding(.top, 54)

                    AssistantSectionLabel(text: "Asystent AI", color: SCPalette.terracotta)
                        .padding(.top, 26)

                    Text("Poznaj\nasystenta")
                        .font(.system(size: 36, weight: .bold))
                        .tracking(-1)
                        .lineSpacing(0)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.scLabel(scheme))
                        .padding(.top, 6)

                    Text("Układa plan tygodnia, podmienia dania i pilnuje alergenów całego domu. Każdą propozycję pokazuje jako kartę, którą zatwierdzasz Ty.")
                        .font(.system(size: 14.5))
                        .tracking(-0.2)
                        .lineSpacing(3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.scMuted(scheme))
                        .frame(maxWidth: 300)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)

                    // Wyrównane do lewej, ale blok jako całość centrowany.
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(ticks, id: \.self) { AssistantTickRow(text: $0) }
                    }
                    .padding(.top, 20)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, SCPageMetrics.horizontal)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)

            AssistantStickyFooter {
                SCSoftButton(title: "Zaczynamy", trailingIcon: "arrow.right", action: onStart)
                if let onShowCapabilities {
                    AssistantTextButton(title: "Zobacz wszystko, co potrafi", action: onShowCapabilities)
                }
            }
        }
    }
}
