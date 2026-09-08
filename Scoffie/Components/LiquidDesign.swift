import SwiftUI

enum DashboardSurfaceLevel {
    case primary
    case secondary
    case tertiary
    case emphasized
}

enum DashboardPalette {
    static func surface(_ scheme: ColorScheme, level: DashboardSurfaceLevel = .primary) -> Color {
        if scheme == .dark {
            switch level {
            case .primary:
                return Color.white.opacity(0.08)
            case .secondary:
                return Color.white.opacity(0.1)
            case .tertiary:
                return Color.white.opacity(0.06)
            case .emphasized:
                return Color.white.opacity(0.14)
            }
        }

        switch level {
        case .primary:
            return Color(red: 0.98, green: 0.985, blue: 0.995)
        case .secondary:
            return Color(red: 0.965, green: 0.973, blue: 0.989)
        case .tertiary:
            return Color(red: 0.946, green: 0.956, blue: 0.98)
        case .emphasized:
            return Color(red: 0.925, green: 0.938, blue: 0.97)
        }
    }

    static func neutralBorder(_ scheme: ColorScheme, opacity: Double? = nil) -> Color {
        if scheme == .dark {
            return Color.white.opacity(opacity ?? 0.16)
        }

        let resolvedOpacity = min(max(opacity ?? 0.14, 0.08), 0.3)
        return Color(red: 0.58, green: 0.66, blue: 0.78).opacity(resolvedOpacity * 1.75)
    }

    static func tintFill(
        _ tint: Color,
        scheme: ColorScheme,
        dark: Double = 0.16,
        light: Double = 0.14
    ) -> Color {
        tint.opacity(scheme == .dark ? dark : light)
    }
}

extension View {
    func dashboardLiquidSheet(cornerRadius: CGFloat = 30) -> some View {
        if #available(iOS 16.4, *) {
            self
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(cornerRadius)
                .presentationBackground(.clear)
        } else {
            self
                .presentationDragIndicator(.visible)
        }
    }
}
