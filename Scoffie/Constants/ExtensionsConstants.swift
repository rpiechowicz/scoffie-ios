import SwiftUI

extension View {
    func myBorderOverlay(
        cornerRadius: CGFloat = 14,
        color: Color? = nil,
        lineWidth: CGFloat = 1
    ) -> some View {
        modifier(
            DashboardBorderOverlayModifier(
                cornerRadius: cornerRadius,
                color: color,
                lineWidth: lineWidth
            )
        )
    }

    func myBackground(cornerRadius: CGFloat = 14) -> some View {
        modifier(
            DashboardBackgroundModifier(cornerRadius: cornerRadius)
        )
    }
}

private struct DashboardBorderOverlayModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let color: Color?
    let lineWidth: CGFloat

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    color ?? DashboardPalette.neutralBorder(colorScheme, opacity: nil),
                    lineWidth: lineWidth
                )
        )
    }
}

private struct DashboardBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.background {
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DashboardPalette.surface(colorScheme, level: .primary))
                    .shadow(
                        color: DashboardPalette.cardShadow(for: colorScheme),
                        radius: 18,
                        x: 0,
                        y: 8
                    )
            }
        }
    }
}
