import SwiftUI

// 38pt okrągła pigułka z obwódką i delikatnym wypełnieniem — akcja w wierszu
// nagłówka (`EditorialPageHeader`). Gdy `highlighted` jest ustawione, tło i
// obwódka biorą kolor akcentu.
struct EditorialIconButton: View {
    let icon: String
    var accent: Color = WMPalette.terracotta
    var highlighted: Bool = false
    /// Średnica pigułki. 38 pt to domyślny rozmiar w wierszu tytułu; różdżka
    /// na Przepisach używa 43 pt, żeby zgadzać się wysokością z pigułką
    /// filtra stojącą w rzędzie niżej.
    var size: CGFloat = 38
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        highlighted
                        ? accent.opacity(0.20)
                        : Color.wmTileBg(scheme)
                    )

                Circle()
                    .stroke(
                        highlighted
                        ? accent.opacity(0.40)
                        : Color.wmTileStroke(scheme),
                        lineWidth: 1
                    )

                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(highlighted ? accent : Color.wmLabel(scheme))
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(icon))
    }
}
