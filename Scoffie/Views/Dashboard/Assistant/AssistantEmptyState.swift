import SwiftUI

// Pusta rozmowa z asystentem — jeden wyśrodkowany kafel i dwa zdania.
//
// Projekt „Asystent Zgoda" (3.09.2026) zdjął stąd kartę „Co wiem o Was"
// i cztery skróty: szybkie starty siedzą teraz tuż nad polem, a fakty
// o gospodarstwie asystent i tak zna. Kod tamtych dwóch bloków stał tu
// jeszcze pół roku „na wypadek powrotu" — razem z modelem `AssistantKnowledge`
// i liczeniem faktów po stronie `AssistantView`, czyli ze stu pięćdziesięcioma
// wierszami, które nic nie rysowały. Wersja, do której warto wracać, jest
// w historii repozytorium, a nie w pliku.
struct AssistantEmptyState: View {
    /// Zdania składa `AssistantWelcome` z godziny, imienia i planu —
    /// ten widok tylko je rysuje.
    let welcome: AssistantWelcome

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 16) {
            // Znak marki, nie systemowe „sparkles": to ten sam glif, który
            // oddycha we wskaźniku tury i stoi nad każdą odpowiedzią —
            // powitanie ma być pierwszym spotkaniem z NIM, a nie z ikoną
            // z katalogu. Miękki krążek z cienką obwódką zamiast kwadratu:
            // wszystko na tym ekranie jest kapsułą albo kołem.
            ZStack {
                Circle()
                    .fill(Color.scAccentTint(scheme))
                Circle()
                    .strokeBorder(SCPalette.terracotta.opacity(scheme == .dark ? 0.28 : 0.18), lineWidth: 1)
                SCMarkShape()
                    .fill(SCPalette.terracotta)
                    .frame(width: 30, height: 30)
            }
            .frame(width: 72, height: 72)

            VStack(spacing: 4) {
                Text(welcome.title)
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.45)
                    .foregroundStyle(Color.scLabel(scheme))

                Text(welcome.subtitle)
                    .font(.system(size: 14))
                    .tracking(-0.15)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.scMuted(scheme))
                    .frame(maxWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
