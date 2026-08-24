import SwiftUI

/// Cozy Kitchen "Steaming Bowl" — wektorowe logo v3 (Recraft "WM Steam").
/// Terakotowa miska, z której para układa się w litery "WM"
/// (Weekly Meals). Źródło: `branding/weekly-meals-logo-v3.svg`.
///
/// Renderowane przez `Canvas`, żeby precyzyjnie oddać krzywe Béziera ze
/// źródła i jednocześnie skalować się bez aliasingu. Ścieżki przeniesione
/// 1:1 z SVG (viewBox 1024 ÷ 10.24 → przestrzeń 100×100). Cztery
/// subpikselowe ścieżki-łatki z generatora (#F9F19F/#CC8568/#D8B7A1,
/// szwy antyaliasingu w oryginale) są celowo pominięte — na innym tle
/// niż kremowe pokazywałyby się jako jasne drobiny.
struct WMSteamingBowlLogo: View {
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

            if mono {
                let ink: Color = isLight
                    ? Color(red: 26 / 255,  green: 20 / 255,  blue: 17 / 255)
                    : Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255)
                fill(Artwork.bowl, with: ink, in: context, scale: scale)
                fill(Artwork.steamRight, with: ink.opacity(0.62), in: context, scale: scale)
                fill(Artwork.steamLeft, with: ink.opacity(0.62), in: context, scale: scale)
            } else {
                // Kolejność jak w SVG: miska pod parą (dolne końce strug
                // nachodzą na wnętrze miski).
                fill(Artwork.bowl, with: Self.terracotta, in: context, scale: scale)
                fill(Artwork.steamRight, with: Self.steamYellow, in: context, scale: scale)
                fill(Artwork.steamLeft, with: Self.steamYellow, in: context, scale: scale)
            }
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

    /// #BE4834 / #ECD034 — kolory źródłowego SVG; identyczne w light
    /// i dark (terracotta + żółć niosą wystarczający kontrast na obu tłach).
    private static let terracotta = Color(red: 190 / 255, green: 72 / 255, blue: 52 / 255)
    private static let steamYellow = Color(red: 236 / 255, green: 208 / 255, blue: 52 / 255)

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

        if mono {
            context.fill(path, with: .color(monoBackgroundColor(isLight: isLight)))
            return
        }

        if isLight {
            // #F7F7F2 — kremowe tło źródłowego SVG (spójne z app icon).
            context.fill(
                path,
                with: .color(Color(red: 247 / 255, green: 247 / 255, blue: 242 / 255))
            )
            return
        }

        let topColor = Color(red: 58 / 255, green: 42 / 255, blue: 32 / 255)   // #3A2A20
        let bottomColor = Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255) // #1A1411
        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [topColor, bottomColor]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: canvasSize.height)
            )
        )
    }

    private func fill(
        _ segments: [Artwork.Seg],
        with color: Color,
        in context: GraphicsContext,
        scale: CGFloat
    ) {
        var path = Path()
        for segment in segments {
            switch segment {
            case let .move(x, y):
                path.move(to: CGPoint(x: x * scale, y: y * scale))
            case let .line(x, y):
                path.addLine(to: CGPoint(x: x * scale, y: y * scale))
            case let .curve(c1x, c1y, c2x, c2y, x, y):
                path.addCurve(
                    to: CGPoint(x: x * scale, y: y * scale),
                    control1: CGPoint(x: c1x * scale, y: c1y * scale),
                    control2: CGPoint(x: c2x * scale, y: c2y * scale)
                )
            case .close:
                path.closeSubpath()
            }
        }
        context.fill(path, with: .color(color))
    }

    private func monoBackgroundColor(isLight: Bool) -> Color {
        // Odpowiednik `bgCard` z designu (CK / CKL).
        isLight
            ? Color(red: 251 / 255, green: 246 / 255, blue: 236 / 255) // #FBF6EC
            : Color(red: 42 / 255,  green: 32 / 255,  blue: 26 / 255)  // #2A201A
    }
}

// MARK: - Path data (branding/weekly-meals-logo-v3.svg, ÷10.24)

private enum Artwork {
    enum Seg {
        case move(CGFloat, CGFloat)
        case line(CGFloat, CGFloat)
        case curve(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
        case close
    }

    /// SVG fill #BE4834
    static let bowl: [Seg] = [
        .move(33.53, 53.26),
        .line(33.56, 53.35),
        .curve(31.75, 53.77, 28.4, 55.33, 27.42, 56.88),
        .curve(27.14, 57.32, 26.98, 57.82, 27.1, 58.34),
        .curve(27.31, 59.28, 28.19, 59.97, 28.97, 60.44),
        .curve(35.39, 64.27, 50.63, 64.32, 58.17, 63.63),
        .curve(60.9, 63.38, 63.64, 62.99, 66.29, 62.3),
        .curve(68.32, 61.78, 71.69, 60.77, 72.8, 58.9),
        .curve(73.05, 58.49, 73.16, 58.04, 73.02, 57.57),
        .curve(72.62, 56.23, 71.07, 55.31, 69.91, 54.72),
        .curve(68.99, 54.25, 68.01, 53.82, 67.02, 53.5),
        .line(67.04, 53.49),
        .curve(67.15, 53.41, 67.15, 53.41, 67.28, 53.38),
        .curve(69.7, 53.88, 75.14, 55.18, 75.88, 58.18),
        .curve(76.05, 58.87, 75.72, 60.98, 75.58, 61.77),
        .curve(74.54, 67.71, 71.55, 73.14, 67.09, 77.2),
        .curve(64.29, 79.75, 62.05, 80.16, 61.22, 84.39),
        .curve(53.1, 87.33, 46.99, 87.14, 38.87, 84.43),
        .curve(38.65, 83.02, 38.04, 81.71, 37.1, 80.64),
        .curve(36.05, 79.44, 34.4, 78.52, 33.1, 77.35),
        .curve(28.8, 73.46, 25.86, 68.3, 24.68, 62.62),
        .curve(24.49, 61.74, 24.04, 59.05, 24.2, 58.25),
        .curve(24.83, 55.03, 31.08, 53.73, 33.53, 53.26),
        .close,
    ]

    /// SVG fill #ECD034
    static let steamRight: [Seg] = [
        .move(50.24, 61.45),
        .curve(47.91, 60.81, 46.02, 59.4, 44.79, 57.31),
        .curve(42.83, 54.01, 43.72, 50.13, 46.13, 47.33),
        .curve(49.09, 43.9, 52.24, 40.56, 52.08, 35.68),
        .curve(51.88, 29.78, 47.45, 24.72, 48.77, 18.68),
        .curve(49.07, 17.32, 49.82, 15.76, 51.11, 15.09),
        .curve(54.6, 13.33, 57.93, 16.28, 59.74, 19.07),
        .curve(61.66, 21.96, 62.76, 25.18, 63.54, 28.54),
        .curve(63.68, 29.13, 63.89, 29.86, 63.94, 30.46),
        .curve(64.03, 30.29, 64.02, 30.11, 64.06, 29.92),
        .curve(64.08, 27.3, 64.67, 23.16, 66.53, 21.21),
        .curve(68.35, 19.31, 71, 20.57, 72.47, 22.22),
        .curve(78.01, 28.33, 77.51, 41.17, 71.52, 46.77),
        .curve(70.56, 47.66, 69.44, 48.37, 68.22, 48.87),
        .curve(66.5, 49.58, 63.45, 50.34, 61.53, 50.84),
        .curve(57.79, 51.82, 53.18, 52.87, 52.87, 57.62),
        .curve(52.78, 59.05, 53.24, 60.37, 53.77, 61.67),
        .curve(52.01, 60.59, 50.8, 58.91, 50.35, 56.93),
        .curve(48.98, 50.96, 54.15, 47.21, 59.2, 45.68),
        .curve(62.04, 44.81, 64.68, 43.59, 66.69, 41.36),
        .curve(67.64, 40.3, 68.41, 39.08, 68.93, 37.76),
        .curve(69.62, 36.06, 69.95, 34.18, 69.56, 32.36),
        .curve(69.3, 31.15, 68.51, 31.13, 68.1, 32.28),
        .curve(67.78, 33.16, 67.71, 34.08, 67.5, 34.99),
        .curve(67.04, 37.03, 65.88, 39.97, 63.86, 40.91),
        .curve(63.18, 41.23, 62.4, 41.26, 61.7, 41),
        .curve(60.99, 40.75, 60.52, 40.26, 60.22, 39.58),
        .curve(59.57, 38.13, 59.84, 36.63, 59.73, 35.12),
        .curve(59.55, 32.79, 59.29, 30.39, 58.36, 28.23),
        .curve(58.13, 27.7, 57.66, 26.87, 57.13, 26.66),
        .curve(56.06, 26.22, 55.98, 27.47, 55.96, 28.17),
        .curve(55.94, 29.18, 56.33, 29.93, 56.63, 30.87),
        .curve(57.42, 33.54, 57.73, 36.6, 57.04, 39.31),
        .curve(56.38, 41.92, 54.87, 44.05, 52.97, 45.9),
        .curve(52.26, 46.6, 51.5, 47.23, 50.77, 47.92),
        .curve(48.79, 49.8, 47.54, 51.87, 47.42, 54.65),
        .curve(47.35, 56.31, 47.76, 57.96, 48.6, 59.39),
        .curve(49.11, 60.27, 49.54, 60.75, 50.24, 61.45),
        .close,
    ]

    /// SVG fill #ECD034
    static let steamLeft: [Seg] = [
        .move(43.36, 37.08),
        .curve(44.15, 36.88, 44.54, 36.48, 44.74, 35.67),
        .curve(45.59, 32.3, 43.01, 29.56, 41.47, 26.85),
        .curve(40.03, 24.31, 39.01, 21.38, 39.83, 18.47),
        .curve(40.6, 15.66, 43.78, 12.88, 46.85, 13.7),
        .curve(47.41, 13.85, 47.77, 14.21, 48.03, 14.72),
        .curve(48.04, 15.68, 47.57, 16.34, 47.18, 17.19),
        .curve(45.93, 19.97, 46.39, 23.43, 47.28, 26.26),
        .curve(48.18, 28.76, 49.11, 31.15, 49.67, 33.75),
        .curve(50.39, 37.15, 48.88, 43.08, 45.18, 44.32),
        .curve(44.31, 44.63, 43.36, 44.57, 42.53, 44.16),
        .curve(40.73, 43.26, 39.55, 40.83, 38.94, 39.01),
        .curve(38.83, 39.22, 38.88, 39.37, 38.86, 39.62),
        .curve(38.89, 42.18, 39.7, 44.66, 38.92, 47.21),
        .curve(38.05, 50.04, 35.23, 50.68, 32.65, 49.85),
        .curve(29.8, 48.94, 27.17, 45.94, 25.85, 43.33),
        .curve(23.45, 38.53, 23.05, 32.98, 24.72, 27.89),
        .curve(25.55, 25.4, 26.79, 22.73, 29.24, 21.45),
        .curve(30.86, 20.58, 33.16, 20.96, 33.97, 22.77),
        .curve(34.95, 24.97, 33.86, 26.89, 32.99, 28.84),
        .curve(31.73, 31.66, 30.35, 34.81, 31.78, 37.82),
        .curve(33.01, 40.4, 35.55, 40.75, 35.49, 37.3),
        .curve(35.47, 35.19, 34.08, 31.69, 35.43, 29.83),
        .curve(37.49, 27.01, 40.35, 28.59, 40.84, 31.63),
        .curve(41.13, 33.39, 41.56, 36.51, 43.36, 37.08),
        .close,
    ]
}

#Preview("Steaming Bowl — dark") {
    ZStack {
        Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).ignoresSafeArea()
        VStack(spacing: 16) {
            WMSteamingBowlLogo(size: 140, palette: .dark)
            HStack(spacing: 12) {
                WMSteamingBowlLogo(size: 64, palette: .dark)
                WMSteamingBowlLogo(size: 44, palette: .dark)
                WMSteamingBowlLogo(size: 28, palette: .dark)
            }
        }
    }
}

#Preview("Steaming Bowl — light") {
    ZStack {
        Color(red: 250 / 255, green: 243 / 255, blue: 232 / 255).ignoresSafeArea()
        VStack(spacing: 16) {
            WMSteamingBowlLogo(size: 140, palette: .light)
            HStack(spacing: 12) {
                WMSteamingBowlLogo(size: 52, mono: true, palette: .light)
                WMSteamingBowlLogo(size: 52, mono: true, palette: .dark)
            }
        }
    }
}
