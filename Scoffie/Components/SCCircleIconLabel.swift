import SwiftUI

/// Okrągła akcja nagłówka — sam RYSUNEK, bez przycisku. Szklany krążek.
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

    /// Liquid Glass (4.10.2026, runda 2 — przyciski nagłówka jak „wstecz”
    /// i awatar w Telegramie na iOS 26). Szkło ma własny brzeg, więc bez
    /// obwódki; podświetlony = szkło w tincie akcentu i glif w akcencie.
    /// Sąsiednie krążki w jednym rzędzie stawiać w `GlassEffectContainer`.
    var body: some View {
        Image(systemName: icon)
            .font(.sc(size: iconSize, weight: .semibold))
            .foregroundStyle(highlighted ? accent : Color.scLabel(scheme))
            .frame(width: size, height: size)
            .scChromeGlass(
                in: Circle(),
                tint: highlighted ? accent.opacity(scheme == .dark ? 0.28 : 0.22) : nil
            )
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
