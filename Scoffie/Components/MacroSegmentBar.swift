import SwiftUI

/// Pasek makro: tor, opcjonalne widmo planu i trzy segmenty w kolorach
/// białka, tłuszczu i węglowodanów.
///
/// Segmenty są osobnymi kapsułkami z prześwitem, a nie prostokątami sklejonymi
/// w jedną obciętą kapsułę. Tamto zaokrąglało wyłącznie oba końce CAŁEGO
/// paska, więc trzy makra rozdzielała ostra krawędź styku dwóch kolorów —
/// czytelne to było jak szew, a nie jak podział.
///
/// Wyjęty z `EditorialMacroBlock` (Kalendarz), bo Plan tygodnia rysuje ten sam
/// pasek w pigułce nad dolnym menu. Dwie kopie znaczyłyby dwa miejsca, w
/// których trzeba pamiętać, że białko jest indygo, tłuszcz terakotowy,
/// a węgle szałwiowe — a to jest właśnie ta trójka, której użytkownik uczy się
/// raz i rozpoznaje potem wszędzie.
///
/// Proporcje segmentów liczą się z KALORII makroskładników (4/9/4 kcal na
/// gram), nie z gramów. Pasek pokazuje, z czego składa się energia dnia,
/// a gram tłuszczu niesie jej dwa razy tyle, co gram białka.
struct MacroSegmentBar: View {
    let protein: Int
    let fat: Int
    let carbs: Int
    /// Ile z dziennego celu wypełnia to, co już policzone (0…1).
    let fillFraction: CGFloat
    /// Dokąd dojedzie pasek, gdy dojdzie reszta planu. `nil` gasi widmo —
    /// tak jest w Planie, gdzie wszystko na pasku jest już zaplanowane.
    var ghostFraction: CGFloat?
    var height: CGFloat = 4
    /// Prześwit między segmentami. To on robi z paska trzy osobne pigułki
    /// zamiast jednej podzielonej kreskami: bez odstępu zaokrąglone końce
    /// sąsiadów wchodziłyby na siebie i całość czytałaby się jak jeden
    /// pasek w brudnym kolorze przejścia.
    var segmentGap: CGFloat = 2.5

    @Environment(\.colorScheme) private var scheme

    private var proteinKcal: Int { protein * 4 }
    private var fatKcal: Int { fat * 9 }
    private var carbsKcal: Int { carbs * 4 }
    private var totalMacroKcal: Int { max(1, proteinKcal + fatKcal + carbsKcal) }

    private var proteinShare: CGFloat { CGFloat(proteinKcal) / CGFloat(totalMacroKcal) }
    private var fatShare: CGFloat { CGFloat(fatKcal) / CGFloat(totalMacroKcal) }
    private var carbsShare: CGFloat { CGFloat(carbsKcal) / CGFloat(totalMacroKcal) }

    private var clampedFill: CGFloat { min(max(fillFraction, 0), 1) }

    /// Segmenty do narysowania — bez tych o zerowym udziale.
    ///
    /// Zero trzeba odsiać, a nie rysować o szerokości zera: pusta kapsuła
    /// nadal zabierałaby swój prześwit, więc dzień bez tłuszczu miałby
    /// w pasku dziurę tam, gdzie tłuszcz by stał.
    private var segments: [(color: Color, share: CGFloat)] {
        [
            (SCPalette.indigo, proteinShare),
            (SCPalette.terracottaDeep, fatShare),
            (SCPalette.sage, carbsShare)
        ]
        .filter { $0.1 > 0 }
    }

    /// Wszystko, co zmienia kształt paska — jedna wartość, żeby zmiana dnia
    /// przesuwała wypełnienie i proporcje segmentów tą samą sprężyną.
    private var shape: [CGFloat] {
        [clampedFill, proteinShare, fatShare, ghostFraction ?? -1]
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let filled = width * clampedFill

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.scBarTrack(scheme))

                if let ghostFraction, ghostFraction > clampedFill {
                    Capsule()
                        .fill(Color.scMuted(scheme).opacity(0.32))
                        .frame(width: width * min(max(ghostFraction, 0), 1), height: height)
                }

                if clampedFill > 0 {
                    // Prześwity odejmujemy od szerokości DO PODZIAŁU, a nie od
                    // gotowych segmentów: inaczej pasek rósłby o sumę odstępów
                    // i przy pełnym celu wystawał poza tor.
                    let list = segments
                    let usable = max(0, filled - segmentGap * CGFloat(max(list.count - 1, 0)))

                    HStack(spacing: segmentGap) {
                        ForEach(Array(list.enumerated()), id: \.offset) { _, segment in
                            Capsule()
                                .fill(segment.color)
                                .frame(width: usable * segment.share, height: height)
                        }
                    }
                    .frame(width: filled, height: height, alignment: .leading)
                }
            }
            .frame(height: height)
        }
        .frame(height: height)
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: shape)
        .accessibilityHidden(true)
    }
}
