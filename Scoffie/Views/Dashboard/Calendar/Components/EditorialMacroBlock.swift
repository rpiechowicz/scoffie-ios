import SwiftUI

// Editorial macro block. Big rolling KCAL counter on the left, three macro
// stats on the right, three-segment progress bar underneath.
//
// Zjedzone vs zaplanowane: wielki licznik i makra liczą wyłącznie posiłki
// odhaczone jako zjedzone, bo plan sam z siebie nic nie mówi o tym, co
// naprawdę trafiło na talerz. Reszta dnia jedzie na pasku jako widmo —
// widać, gdzie użytkownik wyląduje, jeśli zje wszystko, co zaplanował, ale
// te kalorie nie udają policzonych.
//
// Animations:
// - kcal / protein / fat / carbs roll on appear and on day swap (CountingNumber)
// - segmented progress bar fills from 0 → target % via withAnimation
struct EditorialMacroBlock: View {
    /// Kalorie z posiłków oznaczonych jako zjedzone.
    let kcal: Int
    /// Wszystko zaplanowane na dzień — zjedzone i jeszcze nie. Rysuje widmo.
    let plannedKcal: Int
    /// Makra liczone tak samo jak `kcal` — tylko ze zjedzonych posiłków.
    let protein: Int
    let fat: Int
    let carbs: Int
    var target: Int = 2100
    @Environment(\.colorScheme) private var scheme

    private var pKcal: Int { protein * 4 }
    private var fKcal: Int { fat * 9 }
    private var cKcal: Int { carbs * 4 }
    private var totalMacroKcal: Int { max(1, pKcal + fKcal + cKcal) }
    private var pPct: CGFloat { CGFloat(pKcal) / CGFloat(totalMacroKcal) }
    private var fPct: CGFloat { CGFloat(fKcal) / CGFloat(totalMacroKcal) }
    private var cPct: CGFloat { CGFloat(cKcal) / CGFloat(totalMacroKcal) }
    private var fillPct: CGFloat {
        min(1, CGFloat(kcal) / CGFloat(max(target, 1)))
    }

    /// Dokąd dojedzie pasek, jeśli użytkownik zje resztę planu.
    private var plannedPct: CGFloat {
        min(1, CGFloat(max(plannedKcal, kcal)) / CGFloat(max(target, 1)))
    }

    /// Nic jeszcze nie zjedzone — wielki licznik i makra stoją na zerze i idą
    /// w kolor przygaszony.
    private var isEmpty: Bool { kcal == 0 }

    /// Dzień w ogóle bez posiłków — inaczej niż „zaplanowane, ale niezjedzone".
    private var hasNothingPlanned: Bool { plannedKcal == 0 && kcal == 0 }

    /// Ile kalorii wisi jeszcze w planie.
    private var pendingKcal: Int { max(0, plannedKcal - kcal) }

    var body: some View {
        let label = Color.scLabel(scheme)
        let muted = Color.scMuted(scheme)
        let faint = Color.scFaint(scheme)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 28) {
                // Kcal block — fixed 140pt width so the macros grid stays
                // anchored regardless of how many digits the kcal value has
                // ("0" / "610" / "1140" all leave the macros in the exact
                // same horizontal slot). Values that overflow the slot
                // (5+ digits) shrink via `minimumScaleFactor(0.6)`.
                VStack(alignment: .leading, spacing: 0) {
                    Text(hasNothingPlanned ? "KALORIE" : "ZJEDZONE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(muted)
                        .padding(.bottom, -2)

                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        // Always render at full 44pt regardless of digit
                        // count — `monospacedDigit()` (inside CountingNumber)
                        // keeps each digit the same width, and the 140pt
                        // outer slot already fits a 4-digit value with room
                        // to spare. No scaling factor → no visual jitter
                        // between "0", "500", "1500".
                        CountingNumber(target: kcal)
                            .font(.system(size: 44, weight: .heavy))
                            .tracking(-1.6)
                            .foregroundStyle(isEmpty ? faint : label)
                            .lineLimit(1)
                            .fixedSize()

                        Text(verbatim: "/ \(target)")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.3)
                            .foregroundStyle(muted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .frame(width: 140, alignment: .leading)

                // Macros grid — fills the remaining space; with the kcal
                // block at a fixed width, the 3 columns stay equal-width
                // no matter the digit count.
                MacroStatGrid(
                    protein: protein,
                    fat: fat,
                    carbs: carbs,
                    isEmpty: isEmpty
                )
                .frame(maxWidth: .infinity)
                .padding(.bottom, 3)
            }

            // Segmented progress bar
            GeometryReader { geo in
                let w = geo.size.width
                let filled = w * fillPct
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.scBarTrack(scheme))

                    // Widmo planu — dokąd dojedzie dzień, jeśli użytkownik
                    // zje resztę. Neutralny, przygaszony kolor: to jeszcze
                    // nie są policzone kalorie.
                    if plannedPct > fillPct {
                        Capsule()
                            .fill(Color.scMuted(scheme).opacity(0.32))
                            .frame(width: w * plannedPct, height: 4)
                    }

                    if !isEmpty {
                        HStack(spacing: 0) {
                            Rectangle().fill(SCPalette.indigo).frame(width: filled * pPct)
                            Rectangle().fill(SCPalette.terracottaDeep).frame(width: filled * fPct)
                            Rectangle().fill(SCPalette.sage).frame(width: filled * cPct)
                        }
                        .frame(width: filled, height: 4, alignment: .leading)
                        .clipShape(Capsule())
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

                remainingFootnote
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(muted)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var progressFootnote: some View {
        if hasNothingPlanned {
            Text("BRAK ZAPLANOWANYCH POSIŁKÓW")
        } else if isEmpty {
            Text("NIC JESZCZE NIE ODHACZONE")
        } else {
            let pct = Int((CGFloat(kcal) / CGFloat(max(target, 1)) * 100).rounded())
            HStack(spacing: 0) {
                CountingNumber(target: pct)
                Text("% DZIENNEGO CELU")
            }
        }
    }

    @ViewBuilder
    private var remainingFootnote: some View {
        if hasNothingPlanned {
            Text("— KCAL")
        } else if pendingKcal > 0 {
            // Dopóki coś wisi w planie, „do celu" wprowadzałoby w błąd —
            // użytkownik ma już te kalorie na talerzu, tylko ich nie odhaczył.
            HStack(spacing: 0) {
                Text("+")
                CountingNumber(target: pendingKcal)
                Text(" KCAL W PLANIE")
            }
        } else {
            let remaining = max(0, target - kcal)
            HStack(spacing: 0) {
                CountingNumber(target: remaining)
                Text(" KCAL DO CELU")
            }
        }
    }
}

private struct MacroStatGrid: View {
    let protein: Int
    let fat: Int
    let carbs: Int
    let isEmpty: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            MacroStat(label: "BIAŁKO",   value: protein, dot: SCPalette.indigo,         isEmpty: isEmpty)
            MacroStat(label: "TŁUSZCZE", value: fat,     dot: SCPalette.terracottaDeep, isEmpty: isEmpty)
            MacroStat(label: "WĘGLE",    value: carbs,   dot: SCPalette.sage,           isEmpty: isEmpty)
        }
    }
}

private struct MacroStat: View {
    let label: String
    let value: Int
    let dot: Color
    let isEmpty: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let muted = Color.scMuted(scheme)
        let faint = Color.scFaint(scheme)
        let labelColor = Color.scLabel(scheme)

        VStack(alignment: .leading, spacing: 2) {
            Rectangle()
                .fill(Color.scRule(scheme))
                .frame(height: 1)
                .padding(.bottom, 4)

            HStack(spacing: 4) {
                Circle()
                    .fill(isEmpty ? faint : dot)
                    .frame(width: 6, height: 6)

                // 8pt + tracking 0.6 lets the longest label ("TŁUSZCZE") fit
                // in its narrow column at the same size as "BIAŁKO" / "WĘGLE"
                // — no truncation, no per-label scaling, all three uniform.
                Text(label)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                CountingNumber(target: value)
                    .font(.system(size: 20, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(isEmpty ? faint : labelColor)
                    .lineLimit(1)

                Text("g")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isEmpty ? faint : muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
