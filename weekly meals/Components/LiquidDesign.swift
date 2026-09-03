import SwiftUI

s
enum DashboardSurfaceLevel {
    case primary
    case secondary
    case tertiary
    case emphasized
}

enum DashboardPalette {
    static func backgroundTop(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.08, green: 0.09, blue: 0.11)
            : Color(red: 0.93, green: 0.95, blue: 0.98)
    }

    static func backgroundBottom(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.05, green: 0.06, blue: 0.07)
            : Color(red: 0.89, green: 0.92, blue: 0.97)
    }

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

    static func cardShadow(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? .clear
            : Color(red: 0.36, green: 0.46, blue: 0.61).opacity(0.12)
    }
}

private struct DashboardSheetGlow {
    let color: Color
    let darkOpacity: Double
    let lightOpacity: Double
    let size: CGFloat
    let blur: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum DashboardSheetTheme {
    case sunrise
    case ocean
    case plum
    case spring
    case indigo
    case plan
    case twilight

    fileprivate var glows: [DashboardSheetGlow] {
        switch self {
        case .sunrise:
            return [
                DashboardSheetGlow(color: .orange, darkOpacity: 0.28, lightOpacity: 0.18, size: 280, blur: 98, x: -150, y: -210),
                DashboardSheetGlow(color: .yellow, darkOpacity: 0.18, lightOpacity: 0.12, size: 220, blur: 86, x: 120, y: -150),
                DashboardSheetGlow(color: .red, darkOpacity: 0.14, lightOpacity: 0.1, size: 320, blur: 112, x: 155, y: 255)
            ]
        case .ocean:
            return [
                DashboardSheetGlow(color: .cyan, darkOpacity: 0.24, lightOpacity: 0.15, size: 260, blur: 94, x: -135, y: -220),
                DashboardSheetGlow(color: .blue, darkOpacity: 0.2, lightOpacity: 0.13, size: 230, blur: 84, x: 130, y: -175),
                DashboardSheetGlow(color: .teal, darkOpacity: 0.16, lightOpacity: 0.1, size: 300, blur: 108, x: 165, y: 245)
            ]
        case .plum:
            return [
                DashboardSheetGlow(color: .purple, darkOpacity: 0.24, lightOpacity: 0.15, size: 270, blur: 96, x: -145, y: -205),
                DashboardSheetGlow(color: .indigo, darkOpacity: 0.2, lightOpacity: 0.12, size: 230, blur: 84, x: 120, y: -165),
                DashboardSheetGlow(color: .pink, darkOpacity: 0.14, lightOpacity: 0.09, size: 310, blur: 110, x: 150, y: 250)
            ]
        case .spring:
            return [
                DashboardSheetGlow(color: .green, darkOpacity: 0.22, lightOpacity: 0.14, size: 270, blur: 96, x: -150, y: -215),
                DashboardSheetGlow(color: .cyan, darkOpacity: 0.16, lightOpacity: 0.1, size: 220, blur: 82, x: 125, y: -185),
                DashboardSheetGlow(color: .mint, darkOpacity: 0.14, lightOpacity: 0.09, size: 320, blur: 112, x: 160, y: 255)
            ]
        case .indigo:
            return [
                DashboardSheetGlow(color: .teal, darkOpacity: 0.18, lightOpacity: 0.11, size: 245, blur: 90, x: -150, y: -220),
                DashboardSheetGlow(color: .blue, darkOpacity: 0.2, lightOpacity: 0.12, size: 270, blur: 94, x: 135, y: -225),
                DashboardSheetGlow(color: .indigo, darkOpacity: 0.16, lightOpacity: 0.1, size: 310, blur: 110, x: 150, y: 255)
            ]
        case .plan:
            return [
                DashboardSheetGlow(color: .blue, darkOpacity: 0.24, lightOpacity: 0.14, size: 265, blur: 94, x: -125, y: -205),
                DashboardSheetGlow(color: .purple, darkOpacity: 0.18, lightOpacity: 0.11, size: 290, blur: 102, x: 145, y: 225),
                DashboardSheetGlow(color: .cyan, darkOpacity: 0.14, lightOpacity: 0.09, size: 220, blur: 86, x: 115, y: -245)
            ]
        case .twilight:
            return [
                DashboardSheetGlow(color: .pink, darkOpacity: 0.18, lightOpacity: 0.12, size: 250, blur: 92, x: -145, y: -210),
                DashboardSheetGlow(color: .purple, darkOpacity: 0.2, lightOpacity: 0.12, size: 235, blur: 84, x: 120, y: -170),
                DashboardSheetGlow(color: .blue, darkOpacity: 0.16, lightOpacity: 0.1, size: 310, blur: 108, x: 165, y: 248)
            ]
        }
    }
}

s
private struct DashboardLiquidCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let strokeOpacity: Double

    func body(content: Content) -> some View {
        content
            .myBackground(cornerRadius: cornerRadius)
            .myBorderOverlay(
                cornerRadius: cornerRadius,
                color: DashboardPalette.neutralBorder(colorScheme, opacity: strokeOpacity),
                lineWidth: 1
            )
    }
}

extension View {
    func dashboardLiquidCard(
        cornerRadius: CGFloat = 22,
        strokeOpacity: Double = 0.24
    ) -> some View {
        modifier(
            DashboardLiquidCardModifier(
                cornerRadius: cornerRadius,
                strokeOpacity: strokeOpacity
            )
        )
    }

    @ViewBuilder
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

enum DashboardActionTone {
    case neutral
    case accent(Color)
    case destructive
}

struct DashboardActionLabel: View {
    let title: String?
    let systemImage: String
    var tone: DashboardActionTone = .neutral
    var fullWidth: Bool = false
    var isDisabled: Bool = false
    var foregroundColor: Color? = nil
    var controlSize: CGFloat = 34
    var iconFont: Font? = nil
    @Environment(\.colorScheme) private var colorScheme

    private var resolvedForegroundColor: Color {
        if let foregroundColor {
            return foregroundColor
        }

        switch tone {
        case .destructive:
            return .red
        case .neutral, .accent:
            return .primary
        }
    }

    private var backgroundColor: Color {
        if isDisabled {
            return DashboardPalette.surface(colorScheme, level: .tertiary)
        }

        switch tone {
        case .neutral:
            return DashboardPalette.surface(colorScheme, level: .secondary)
        case .accent(let color):
            return DashboardPalette.tintFill(color, scheme: colorScheme, dark: 0.12, light: 0.18)
        case .destructive:
            return DashboardPalette.tintFill(.red, scheme: colorScheme, dark: 0.08, light: 0.12)
        }
    }

    private var borderColor: Color {
        if isDisabled {
            return DashboardPalette.neutralBorder(colorScheme, opacity: 0.08)
        }

        switch tone {
        case .neutral:
            return DashboardPalette.neutralBorder(colorScheme, opacity: 0.12)
        case .accent(let color):
            return color.opacity(colorScheme == .dark ? 0.2 : 0.3)
        case .destructive:
            return Color.red.opacity(colorScheme == .dark ? 0.18 : 0.28)
        }
    }

    var body: some View {
        HStack(spacing: title == nil ? 0 : 6) {
            Image(systemName: systemImage)
                .font(iconFont ?? .caption.weight(.semibold))

            if let title {
                Text(title)
                    .lineLimit(1)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isDisabled ? .secondary : resolvedForegroundColor)
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .frame(width: title == nil ? controlSize : nil, height: controlSize)
        .padding(.horizontal, title == nil ? 0 : 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .opacity(isDisabled ? 0.72 : 1)
    }
}

struct DashboardActionButton: View {
    let title: String?
    let systemImage: String
    var tone: DashboardActionTone = .neutral
    var fullWidth: Bool = false
    var isDisabled: Bool = false
    var foregroundColor: Color? = nil
    var controlSize: CGFloat = 34
    var iconFont: Font? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            DashboardActionLabel(
                title: title,
                systemImage: systemImage,
                tone: tone,
                fullWidth: fullWidth,
                isDisabled: isDisabled,
                foregroundColor: foregroundColor,
                controlSize: controlSize,
                iconFont: iconFont
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
