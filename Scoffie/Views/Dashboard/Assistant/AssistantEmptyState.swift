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
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.scAccentTint(scheme))
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(SCPalette.terracotta)
                )

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
