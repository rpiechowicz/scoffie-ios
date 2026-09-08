import SwiftUI

/// Okrągła akcja nagłówka — sam RYSUNEK, bez przycisku.
///
/// `Menu` potrzebuje etykiety, a nie przycisku, więc każde menu „…" w aplikacji
/// rysowało ten krążek u siebie: Plan tygodnia, Zakupy, arkusz historii,
/// arkusz zamkniętej listy. Cztery kopie tych samych sześciu modyfikatorów,
/// z których każda mogła się rozjechać przy pierwszej poprawce obwódki.
///
/// `EditorialIconButton` jest tym samym rysunkiem opakowanym w `Button`
/// z celem dotyku — i bierze go stąd, żeby krążek istniał w jednym egzemplarzu.
struct SCCircleIconLabel: View {
    let icon: String
    /// Średnica. 34 pt w nagłówku ekranu (obok innych akcji), 36 pt w nagłówku
    /// arkusza — tam sąsiaduje z krzyżykiem (`SCSheetCloseButton`) i musi mieć
    /// jego rozmiar.
    var size: CGFloat = 34
    var accent: Color = SCPalette.terracotta
    /// Wypełnienie i obwódka w kolorze akcentu — dla jednej akcji w rzędzie,
    /// która coś tworzy.
    var highlighted: Bool = false
    /// Stopień glifu. Stały, nie proporcjonalny do średnicy: „…" i „iskierki"
    /// mają wyglądać tak samo w 34 i w 36 punktach, a proporcja zmieniłaby
    /// ikony w nagłówku Planu, których nikt nie prosił o zmianę.
    var iconSize: CGFloat = 15

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle()
                .fill(highlighted ? accent.opacity(0.20) : Color.scTileBg(scheme))

            Circle()
                .stroke(
                    highlighted ? accent.opacity(0.40) : Color.scTileStroke(scheme),
                    lineWidth: 1
                )

            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(highlighted ? accent : Color.scLabel(scheme))
        }
        .frame(width: size, height: size)
    }
}

#Preview("SCCircleIconLabel") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()
        HStack(spacing: 10) {
            SCCircleIconLabel(icon: "ellipsis")
            SCCircleIconLabel(icon: "sparkles", highlighted: true)
            SCCircleIconLabel(icon: "ellipsis", size: 36)
        }
    }
    .preferredColorScheme(.dark)
}
