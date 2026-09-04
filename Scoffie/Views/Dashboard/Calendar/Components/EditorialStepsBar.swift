import SwiftUI

// Editorial steps bar — rysowany w Kalendarzu bezpośrednio pod blokiem makro,
// tym samym językiem: eyebrow, licznik z rolującymi cyframi, kapsułowy pasek
// wysokości 4 i stopka 9pt. Skala licznika to 20pt (jak MacroStat), nie 44pt —
// kroki są danymi drugiego planu względem kalorii.
//
// `steps == nil` znaczy „brak danych" (odmowa odczytu w Zdrowiu, brak próbek,
// Garmin bez syncu) — pasek stoi pusty, a stopka mówi to wprost. Zera z
// HealthKit nigdy tu nie przychodzą: serwis pomija dni bez próbek.
struct EditorialStepsBar: View {
    let steps: Int?
    let goal: Int
    /// Źródło wybrane w integracji — stopka pokazuje notkę tylko dla Garmina,
    /// Apple Zdrowie jest domyślnym, „cichym" źródłem.
    let source: StepsSource?
    @Environment(\.colorScheme) private var scheme

    private var fillPct: CGFloat {
        guard let steps else { return 0 }
        return min(1, CGFloat(steps) / CGFloat(max(goal, 1)))
    }

    private var goalPct: Int {
        guard let steps else { return 0 }
        return Int((CGFloat(steps) / CGFloat(max(goal, 1)) * 100).rounded())
    }

    private var hasData: Bool { (steps ?? 0) > 0 }

    var body: some View {
        let label = Color.scLabel(scheme)
        let muted = Color.scMuted(scheme)
        let faint = Color.scFaint(scheme)

        VStack(alignment: .leading, spacing: 6) {
            Text("KROKI")
                .font(.system(size: 9, weight: .bold))
                .tracking(2)
                .foregroundStyle(muted)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                CountingNumber(target: steps ?? 0)
                    .font(.system(size: 20, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(hasData ? label : faint)
                    .lineLimit(1)
                    .fixedSize()

                Text(verbatim: "/ \(goal)")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(muted)
                    .lineLimit(1)
                    .fixedSize()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.scBarTrack(scheme))

                    if hasData {
                        Capsule()
                            .fill(SCPalette.sage)
                            .frame(width: geo.size.width * fillPct, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(height: 4)
            .padding(.top, 2)

            HStack {
                progressFootnote
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(muted)

                Spacer()

                if source == .garmin {
                    Text("ŹRÓDŁO: GARMIN")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var progressFootnote: some View {
        if hasData {
            // Procent bez capa (np. 134%) — przekroczony cel to informacja,
            // nie błąd; przycina się tylko sam pasek.
            HStack(spacing: 0) {
                CountingNumber(target: goalPct)
                Text("% CELU KROKÓW")
            }
        } else {
            Text("BRAK DANYCH O KROKACH")
        }
    }
}
