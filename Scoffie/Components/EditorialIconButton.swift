import SwiftUI

// Okrągła akcja w wierszu nagłówka (`EditorialPageHeader`) — `SCCircleIconLabel`
// opakowany w przycisk z celem dotyku. Sam rysunek mieszka w komponencie, bo
// biorą go stąd także etykiety menu „…", które przyciskiem nie są.
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

    var body: some View {
        Button(action: action) {
            SCCircleIconLabel(icon: icon, size: size, accent: accent, highlighted: highlighted)
                .scTapTarget(tapTarget ?? size, drawn: size)
        }
        .buttonStyle(PlanPressStyle(scale: 0.9))
        .accessibilityLabel(Text(accessibilityTitle ?? icon))
    }
}
