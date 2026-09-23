import SwiftUI

/// Rozmiar wybieranej opcji — od niego zależy siła tintu.
enum SCChoiceSurfaceStyle {
    /// Chip albo pigułka w rzędzie (płeć, liczba treningów, filtry).
    case chip
    /// Karta na całą szerokość (motyw, posiłki w planie, źródło kroków) —
    /// liczby `SCChoiceTile`. Tint chipa na dużej karcie zalewał ją kolorem.
    case tile
}

/// Tło opcji do wybrania: chipa w rzędzie albo całej karty.
/// Wybrana: tint akcentu, obwódka w akcencie i napis w akcencie — jak
/// zaznaczone pigułki filtrów i kafelki `SCChoiceTile`. Niewybrana:
/// neutralne tło z cienką obwódką.
///
/// Zastąpiło pełną terakotę z gradientem i białym napisem (w kreatorze
/// jeszcze z cieniem) i kilka ręcznie rysowanych kopii tego samego tintu
/// w kartach, każdą z innymi liczbami.
struct SCChoiceSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let isOn: Bool
    let accent: Color
    /// Tło niewybranej opcji. `nil` = `scChipBg` (chip stoi na karcie).
    let offFill: Color?
    let style: SCChoiceSurfaceStyle

    @Environment(\.colorScheme) private var scheme

    private var onFill: Color {
        switch style {
        case .chip: return accent.opacity(scheme == .dark ? 0.16 : 0.12)
        case .tile: return accent.opacity(scheme == .dark ? 0.12 : 0.09)
        }
    }

    func body(content: Content) -> some View {
        content
            .background(
                shape.fill(isOn ? onFill : (offFill ?? Color.scChipBg(scheme)))
            )
            .overlay(
                shape.strokeBorder(
                    isOn ? accent.opacity(0.45) : Color.scTileStroke(scheme),
                    lineWidth: isOn ? 1.2 : 1
                )
            )
    }
}

extension View {
    /// Tło wybieranej opcji — patrz `SCChoiceSurface`.
    func scChoiceSurface<S: InsettableShape>(
        _ shape: S,
        isOn: Bool,
        accent: Color = SCPalette.terracotta,
        offFill: Color? = nil,
        style: SCChoiceSurfaceStyle = .chip
    ) -> some View {
        modifier(SCChoiceSurface(shape: shape, isOn: isOn, accent: accent, offFill: offFill, style: style))
    }
}
