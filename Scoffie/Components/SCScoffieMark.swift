import SwiftUI

/// Znak Scoffie — dysk z kęsem, rysowany ścieżkami zamiast bundlowania PNG-ów.
///
/// Geometria 1:1 ze źródła `branding/scoffie-logo.svg` (viewBox 1024 ÷ 10.24 →
/// przestrzeń 100×100): dysk R = 25 w środku (50, 50) minus kęs r = 11,7646
/// w (67,6758, 32,3242). Ikona aplikacji w `Assets.xcassets/AppIcon.appiconset`
/// ma tę samą geometrię, więc znak w aplikacji i ikona na ekranie startowym
/// czytają się jako ten sam rysunek.
///
/// Renderowane przez `Canvas` — jedna ścieżka skaluje się bez aliasingu od 22 pt
/// (`OnboardingHeroPattern`) po 140 pt (podgląd).
struct SCScoffieMark: View {
    enum Palette {
        case auto
        case dark
        case light
    }

    var size: CGFloat = 100
    var mono: Bool = false
    var palette: Palette = .auto

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 100

            drawBackground(in: context, scale: scale, canvasSize: canvasSize, isLight: isLight)
            context.fill(Self.markPath(scale: scale), with: .color(markColor(isLight: isLight)))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var isLight: Bool {
        switch palette {
        case .auto: return colorScheme == .light
        case .dark: return false
        case .light: return true
        }
    }

    // MARK: - Colors

    /// Kolory ikony aplikacji, wariant B: znak kremowy na terakotowej płycie.
    /// Terakota to `SCPalette.terracottaDeep`, krem to `SCPalette.canvasLight`.
    private static let terracotta = Color(red: 182 / 255, green: 100 / 255, blue: 60 / 255) // #B6643C
    private static let cream = Color(red: 250 / 255, green: 246 / 255, blue: 240 / 255)     // #FAF6F0
    private static let terracottaLight = Color(red: 219 / 255, green: 132 / 255, blue: 82 / 255) // #DB8452
    private static let canvasDark = Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255)   // #1A1411

    private func markColor(isLight: Bool) -> Color {
        if mono {
            return isLight
                ? Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255)   // #1A1411
                : Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255) // #FBF3E8
        }
        return isLight ? Self.cream : Self.terracottaLight
    }

    private func backgroundColor(isLight: Bool) -> Color {
        if mono {
            // Odpowiednik `bgCard` z designu (CK / CKL).
            return isLight
                ? Color(red: 251 / 255, green: 246 / 255, blue: 236 / 255) // #FBF6EC
                : Color(red: 42 / 255, green: 32 / 255, blue: 26 / 255)    // #2A201A
        }
        return isLight ? Self.terracotta : Self.canvasDark
    }

    // MARK: - Drawing

    private func drawBackground(
        in context: GraphicsContext,
        scale: CGFloat,
        canvasSize: CGSize,
        isLight: Bool
    ) {
        let path = Path(
            roundedRect: CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height),
            cornerRadius: 22 * scale,
            style: .continuous
        )
        context.fill(path, with: .color(backgroundColor(isLight: isLight)))
    }

    /// Dysk minus kęs — `subtracting`, a nie `evenOdd`, bo koło kęsa wystaje
    /// poza dysk i przy regule parzystości jego zewnętrzny fragment zostałby
    /// wypełniony.
    private static func markPath(scale: CGFloat) -> Path {
        let disc = Path(ellipseIn: CGRect(
            x: (50 - 25) * scale,
            y: (50 - 25) * scale,
            width: 50 * scale,
            height: 50 * scale
        ))
        let bite = Path(ellipseIn: CGRect(
            x: (67.67578125 - 11.76464844) * scale,
            y: (32.32421875 - 11.76464844) * scale,
            width: 23.52929688 * scale,
            height: 23.52929688 * scale
        ))
        return disc.subtracting(bite)
    }
}

#Preview("Znak Scoffie — dark") {
    ZStack {
        Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).ignoresSafeArea()
        VStack(spacing: 16) {
            SCScoffieMark(size: 140, palette: .dark)
            HStack(spacing: 12) {
                SCScoffieMark(size: 64, palette: .dark)
                SCScoffieMark(size: 44, palette: .dark)
                SCScoffieMark(size: 28, palette: .dark)
                SCScoffieMark(size: 22, palette: .dark)
            }
        }
    }
}

#Preview("Znak Scoffie — light") {
    ZStack {
        Color(red: 250 / 255, green: 246 / 255, blue: 240 / 255).ignoresSafeArea()
        VStack(spacing: 16) {
            SCScoffieMark(size: 140, palette: .light)
            HStack(spacing: 12) {
                SCScoffieMark(size: 52, mono: true, palette: .light)
                SCScoffieMark(size: 52, mono: true, palette: .dark)
            }
        }
    }
}
