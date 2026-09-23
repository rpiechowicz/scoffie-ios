import SwiftUI

/// Cień krawędzi — treść pod przypiętym paskiem łagodnie gaśnie w kolor tła.
/// JEDEN w całej aplikacji: górny pasek szczegółów posiłku (serce i krzyżyk
/// nad przewiniętą treścią) i dolna stopka każdego arkusza (`SCSheetFooter`).
///
/// Wzór to górny pasek szczegółów posiłku — Rafał (23.09.2026): „bardzo mi
/// się podoba shadow górny, zrób taki sam od dołu”. Krzywa: przez połowę
/// wysokości prawie kryjący (85 %), potem szybko gaśnie. Dolny to lustro
/// górnego, ale stoi NAD płytą stopki, a nie pod przyciskiem: przycisk ma
/// pod sobą pełne tło, a cień zaczyna się dokładnie na górnej krawędzi
/// płyty — nie wchodzi na przycisk.
///
/// Wcześniej dół miał własne 36 pt przejścia od 0 do 70 %, słabsze i krótsze
/// niż góra — ten sam arkusz kończył się u góry i u dołu na dwa sposoby.
struct SCEdgeShade: View {
    /// Górny: przyciski stoją NA cieniu, więc sięga pod nie i dalej.
    static let topHeight: CGFloat = 84
    /// Dolny: sam ogon nad płytą stopki.
    static let bottomHeight: CGFloat = 56

    let edge: VerticalEdge
    /// Kolor tła pod paskiem — cień gaśnie DO niego. `nil` = `scPageBase`.
    var base: Color? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let base = base ?? Color.scPageBase(scheme)
        let stops: [Gradient.Stop] = edge == .top
            ? [
                .init(color: base, location: 0),
                .init(color: base.opacity(0.85), location: 0.55),
                .init(color: base.opacity(0), location: 1)
            ]
            : [
                .init(color: base.opacity(0), location: 0),
                .init(color: base.opacity(0.85), location: 0.45),
                .init(color: base, location: 1)
            ]

        LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
