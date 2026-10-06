import SwiftUI

/// „Wróć do dziś” w pasku tygodnia — SAMA ikona cofania w krążku 26 pt, obok
/// strzałek tygodnia (Plan, Kalendarz, „Dodaj do planu”).
///
/// 27.09.2026 (Rafał: „jak zmienię tydzień, to title przy »Wróć do dziś« się
/// pomniejsza — daj sam button z ikoną cofania, aby wszystko się zgadzało”):
/// pigułka ze słowami zabierała podpisowi tygodnia ~90 pt i „TEN TYDZIEŃ ·
/// 22–28 WRZ” zjeżdżał `minimumScaleFactor`. Krążek ma szerokość strzałki, więc
/// podpis zostaje w swoim rozmiarze. Terakotowe szkło odróżnia go od
/// neutralnych strzałek; słowa zostają dla VoiceOver.
struct SCWeekTodayButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward")
                .font(.sc(size: 10, weight: .bold))
                .foregroundStyle(SCPalette.terracotta)
                .frame(width: 26, height: 26)
                // Szkło w tincie terakoty (Liquid Glass runda 2, 4.10.2026)
                // zamiast wariantu „soft” — odróżnia się od neutralnych
                // strzałek tak samo, a stoi w języku reszty kontrolek.
                .scChromeGlass(in: Circle(), tint: SCPalette.terracotta.opacity(0.22))
                .scTapTarget(drawn: 26)
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.7)))
        .accessibilityLabel("Wróć do bieżącego tygodnia")
    }
}
