import SwiftUI

/// Pasek makro: tor, opcjonalne widmo planu i trzy segmenty w kolorach
/// białka, tłuszczu i węglowodanów.
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

    @Environment(\.colorScheme) private var scheme

    private var proteinKcal: Int { protein * 4 }
    private var fatKcal: Int { fat * 9 }
    private var carbsKcal: Int { carbs * 4 }
    private var totalMacroKcal: Int { max(1, proteinKcal + fatKcal + carbsKcal) }

    private var proteinShare: CGFloat { CGFloat(proteinKcal) / CGFloat(totalMacroKcal) }
    private var fatShare: CGFloat { CGFloat(fatKcal) / CGFloat(totalMacroKcal) }
    private var carbsShare: CGFloat { CGFloat(carbsKcal) / CGFloat(totalMacroKcal) }

    private var clampedFill: CGFloat { min(max(fillFraction, 0), 1) }

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
                    HStack(spacing: 0) {
                        Rectangle().fill(SCPalette.indigo).frame(width: filled * proteinShare)
                        Rectangle().fill(SCPalette.terracottaDeep).frame(width: filled * fatShare)
                        Rectangle().fill(SCPalette.sage).frame(width: filled * carbsShare)
                    }
                    .frame(width: filled, height: height, alignment: .leading)
                    .clipShape(Capsule())
                }
            }
            .frame(height: height)
        }
        .frame(height: height)
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: shape)
        .accessibilityHidden(true)
    }
}
