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
    /// Bez `if #available(iOS 16.4, *)`, bo target aplikacji to iOS 26 —
    /// gałąź zapasowa była nieosiągalna od dawna.
    ///
    /// Nie była też niewinna: dwie gałęzie dawały dwa różne typy konkretne
    /// (trzy modyfikatory kontra jeden), a funkcja obiecywała jedno
    /// `some View`, więc kompilator kończył na „branches have mismatching
    /// types". Jeden typ zamiast dwóch usuwa problem u źródła, zamiast
    /// zaklejać go `@ViewBuilder`, który tylko owinąłby to w `AnyView`.
    func dashboardLiquidSheet(cornerRadius: CGFloat = 30) -> some View {
        presentationDragIndicator(.visible)
            .presentationCornerRadius(cornerRadius)
            .presentationBackground(.clear)
    }
}
