import SwiftUI

// 38pt okrągła pigułka z obwódką i delikatnym wypełnieniem — akcja w wierszu
// nagłówka (`EditorialPageHeader`). Gdy `highlighted` jest ustawione, tło i
// obwódka biorą kolor akcentu.
struct EditorialIconButton: View {
    let icon: String
    var accent: Color = SCPalette.terracotta
    var highlighted: Bool = false
    /// Średnica pigułki. 38 pt to domyślny rozmiar w wierszu tytułu; różdżka
    /// na Przepisach używa 43 pt, żeby zgadzać się wysokością z pigułką
    /// filtra stojącą w rzędzie niżej.
    var size: CGFloat = 38
    /// Co czyta VoiceOver. Bez tego czytał nazwę symbolu
    /// („square dot and dot pencil”) — dla osoby niewidzącej to szum.
    var accessibilityTitle: String? = nil
    /// Cel dotyku większy niż rysowana pigułka (`scTapTarget`). `nil` zostawia
    /// cel równy pigułce — dla 38 pt i więcej różnica jest kosmetyczna, dla
    /// 34 pt w nagłówku Planu już nie.
    var tapTarget: CGFloat? = nil
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        highlighted
                        ? accent.opacity(0.20)
                        : Color.scTileBg(scheme)
                    )

                Circle()
                    .stroke(
                        highlighted
                        ? accent.opacity(0.40)
                        : Color.scTileStroke(scheme),
                        lineWidth: 1
                    )

                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(highlighted ? accent : Color.scLabel(scheme))
            }
            .frame(width: size, height: size)
            .scTapTarget(tapTarget ?? size, drawn: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityTitle ?? icon))
    }
}
