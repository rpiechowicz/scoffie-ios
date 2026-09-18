import SwiftUI

// Dwa bezstanowe atomy wskaźnika „asystent pracuje": glif, który oddycha,
// i wiersz tekstu z połyskiem. Oba są CZYSTYMI FUNKCJAMI czasu `t`
// podanego przez rodzica — żaden nie ma własnego zegara ani `@State`,
// więc dwa elementy jednego wiersza nigdy nie rozjeżdżają się w fazie.

/// Glif „asystent pracuje": znak Scoffie, który bierze powolny oddech.
///
/// Skala i krycie liczone z CZASU WZGLĘDEM POCZĄTKU TURY podanego przez
/// rodzica — widok przebudowuje się przy każdym kroku postępu, a animacja
/// na `@State` + `repeatForever` zastyga wtedy w miejscu. Czas względny,
/// nie `timeIntervalSinceReferenceDate`: faza nie ma prawa skoczyć, gdy
/// zmieni się cokolwiek innego (to była „eksplozja" poprzedniego orbu —
/// czas absolutny mnożony przez prędkość zależną od stanu).
struct SCThinkingGlyph: View {
    /// Sekundy od początku tury (rodzic liczy je z jednego zegara).
    let t: TimeInterval
    let color: Color
    var size: CGFloat = 14
    /// `true` = pełny, nieruchomy glif (Reduce Motion).
    var still: Bool = false

    var body: some View {
        let s = still ? 1.0 : (1 + sin(t * 2 * .pi / 1.3)) / 2
        SCMarkShape()
            .fill(color)
            // Etap tury zmienia TYLKO barwę i ta barwa PRZENIKA. Modyfikator
            // stoi przed skalą i kryciem, więc oddechu nie dotyka — w odwrotnej
            // kolejności oddech dostałby półsekundowe wygładzanie i zamienił
            // się w rozmazany szum.
            .animation(.smooth(duration: 0.5), value: color)
            .frame(width: size, height: size)
            .scaleEffect(0.86 + 0.14 * s)
            // Przy Reduce Motion 0,85 zamiast pełni: glif ma być odróżnialny
            // od tego samego znaku w `scFaint` po zakończeniu tury.
            .opacity(still ? 0.85 : 0.55 + 0.45 * s)
            .accessibilityHidden(true)
    }
}

/// Jeden wiersz tekstu z połyskiem od lewej do prawej — jedyny „żywy"
/// sygnał wskaźnika, dokładnie tam, gdzie oko czyta. Bez maski i bez
/// `GeometryReader`: `UnitPoint` poza 0…1 jest legalny, a gradient poza
/// zakresem trzyma kolor skrajny, czyli zwykły `scMuted`.
struct SCShimmerText: View {
    let text: String
    /// Sekundy od początku tury.
    let t: TimeInterval
    var still: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let base = Color.scMuted(scheme)
        if still {
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(base)
        } else {
            let phase = t.truncatingRemainder(dividingBy: 2.4) / 2.4
            // −0,6 … 1,6: na obu końcach cyklu pasmo leży CAŁE poza tekstem,
            // więc zawinięcie fazy jest niewidoczne. Ruch liniowy — easing
            // robi z połysku „pulsowanie". Nie domykać do 0…1: wtedy pasmo
            // przyklejałoby się do krawędzi i zawinięcie stałoby się skokiem.
            let p = -0.6 + phase * 2.2
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: base, location: 0),
                            .init(color: Color.scLabel(scheme), location: 0.5),
                            .init(color: base, location: 1),
                        ],
                        startPoint: UnitPoint(x: p - 0.35, y: 0.5),
                        endPoint: UnitPoint(x: p + 0.35, y: 0.5)
                    )
                )
        }
    }
}

#Preview("Glif i połysk") {
    VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 8) {
            SCThinkingGlyph(t: 0, color: SCPalette.terracotta)
            SCShimmerText(text: "Zastanawiam się…", t: 0)
        }
        HStack(spacing: 8) {
            SCThinkingGlyph(t: 0.65, color: SCPalette.indigo)
            SCShimmerText(text: "Układam plan tygodnia", t: 1.2)
        }
        HStack(spacing: 8) {
            SCThinkingGlyph(t: 0.3, color: SCPalette.sage, still: true)
            SCShimmerText(text: "Zapisuję plan tygodnia", t: 0, still: true)
        }
    }
    .padding(24)
}
