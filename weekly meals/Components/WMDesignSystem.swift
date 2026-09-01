import SwiftUI

// Weekly Meals v2 "Cozy Kitchen" design tokens.
// Source of truth: v2-design/Weekly Meals - Onboarding.html (WM_TOKENS).
// Dark-first; light mirrors. Colors converted from OKLCH → sRGB.

enum WMPalette {
    // Warm terracotta family — primary brand accent. Reads as food + warmth
    // without going saturated red.
    //
    // Each accent ships dark-first values from the design tokens. In light
    // mode the lighter accents (`butter`, `sage`) get darker variants so
    // they remain readable against the cream canvas — without the swap,
    // butter on `#FAF6F0` washes out completely.
    static let terracotta = dynamicColor(
        dark:  (219, 132, 82),   // oklch(0.72 0.14 48)
        light: (182, 100, 60)    // oklch(0.60 0.15 40) — same as terracottaDeep, darkens for cream bg
    )
    static let terracottaDeep = Color(red: 182 / 255, green: 100 / 255, blue: 60 / 255)  // oklch(0.60 0.15 40)
    static let sage = dynamicColor(
        dark:  (135, 194, 165),  // oklch(0.74 0.10 155)
        light: (76, 135, 102)    // oklch(0.55 0.10 155) — darkened for legibility on cream
    )
    static let indigo = dynamicColor(
        dark:  (101, 115, 202),  // oklch(0.62 0.14 265)
        light: (75, 88, 175)     // slightly darker for cream-bg contrast
    )
    static let butter = dynamicColor(
        dark:  (232, 207, 133),  // oklch(0.88 0.10 88)
        light: (160, 120, 40)    // oklch(0.55 0.12 80) — mustard, readable on cream
    )

    // Warm canvas. Dark is near-black with a warm brown cast.
    static let canvasDark = Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255)     // #1A1411
    static let canvasLight = Color(red: 250 / 255, green: 246 / 255, blue: 240 / 255) // #FAF6F0

    static let labelDark = Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255)   // #FBF3E8
    static let labelLight = Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255)     // #1A1411

    /// Builds a `Color` whose underlying `UIColor` switches at the trait
    /// level — drop-in replacement for SwiftUI dynamic colors. Inputs are
    /// `(R, G, B)` 0–255 tuples for dark/light variants.
    private static func dynamicColor(
        dark: (Int, Int, Int),
        light: (Int, Int, Int)
    ) -> Color {
        let darkUIColor = UIColor(
            red: CGFloat(dark.0) / 255,
            green: CGFloat(dark.1) / 255,
            blue: CGFloat(dark.2) / 255,
            alpha: 1
        )
        let lightUIColor = UIColor(
            red: CGFloat(light.0) / 255,
            green: CGFloat(light.1) / 255,
            blue: CGFloat(light.2) / 255,
            alpha: 1
        )
        return Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? darkUIColor : lightUIColor
        })
    }
}

extension Color {
    static func wmCanvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? WMPalette.canvasDark : WMPalette.canvasLight
    }

    static func wmLabel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? WMPalette.labelDark : WMPalette.labelLight
    }

    static func wmMuted(_ scheme: ColorScheme) -> Color {
        // Light mode opacity bumped from 0.56 → 0.66 to match the design's
        // `rgba(26,15,10,0.68)` muted token — captions and meta rows on the
        // cream canvas were reading too washed-out at 0.56.
        scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.58)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.66)
    }

    static func wmTileBg(_ scheme: ColorScheme) -> Color {
        // Cards on cream need slightly more body than the dark-first 0.04 to
        // visibly separate from the canvas — bumped to 0.06.
        scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.04)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.06)
    }

    static func wmTileStroke(_ scheme: ColorScheme) -> Color {
        // Hairline strokes on light mode go from 0.06 → 0.12 so card edges
        // and circular xmark wells remain visible against the cream canvas.
        scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.06)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.12)
    }

    /// Elevated card surface. In light mode it goes *lighter* than the cream
    /// canvas — a darker-tinted card there reads as a stain, not as elevation —
    /// and leans on a shadow for separation. Dark mode keeps the dark-first
    /// translucent fill, identical to `wmTileBg`.
    static func wmCardSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.04)
            : Color(red: 255 / 255, green: 252 / 255, blue: 246 / 255)  // #FFFCF6 warm white
    }

    /// Recessed surface *inside* a card — meal rows, date tiles. Sits one step
    /// below `wmCardSurface`, which is how a well reads on a white card.
    static func wmInsetSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.025)
            : Color(red: 246 / 255, green: 239 / 255, blue: 228 / 255)  // #F6EFE4 cream well
    }

    /// Hairline for elevated cards — softer than `wmTileStroke`, because the
    /// shadow is already doing the separating.
    static func wmCardStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.06)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.07)
    }

    static func wmFeatureRowBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.08)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.04)
    }

    static func wmAccentTint(_ scheme: ColorScheme) -> Color {
        WMPalette.terracotta.opacity(scheme == .dark ? 0.16 : 0.12)
    }

    /// Tło pod akcent zielony — „zapisane / gotowe”.
    ///
    /// Te trzy tinty istniały dotąd wyłącznie jako liczby wpisywane w miejscu
    /// użycia i zdążyły się rozjechać na cztery różne wartości
    /// (`EditorialMealCard` 0.14/0.09, `HealthIntegrationSheet` 0.10/0.07,
    /// `PlanDaySplitsSection` 0.22/0.16, `PlanSlotPickerSheet` 0.16/0.10).
    /// Asystent potrzebuje ich w kartach na tyle często, że dalsze mnożenie
    /// wariantów zrobiłoby z tego loterię — stąd jedna prawda tutaj.
    static func wmSageTint(_ scheme: ColorScheme) -> Color {
        WMPalette.sage.opacity(scheme == .dark ? 0.13 : 0.10)
    }

    /// Tło pod akcent niebieski — analiza, liczby, „informacyjnie”.
    static func wmIndigoTint(_ scheme: ColorScheme) -> Color {
        WMPalette.indigo.opacity(scheme == .dark ? 0.14 : 0.10)
    }

    /// Tło pod akcent żółty — pytanie asystenta i etykieta „nowe”.
    static func wmButterTint(_ scheme: ColorScheme) -> Color {
        WMPalette.butter.opacity(scheme == .dark ? 0.14 : 0.12)
    }

    /// Najgłębsze tło strony — o pół tonu ciemniejsze niż `wmCanvas`, bo pod
    /// poświatę nagłówka potrzeba czerni, od której akcent ma się odbić.
    /// Wcześniej ta wartość żyła wyłącznie w `WMPageBackground`; asystent
    /// dokłada nad nią własne warstwy (composer, arkusze), więc musi umieć
    /// nazwać ten sam kolor.
    static func wmPageBase(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 12 / 255, green: 8 / 255, blue: 6 / 255)        // #0C0806
            : Color(red: 251 / 255, green: 245 / 255, blue: 234 / 255)   // #FBF5EA
    }

    static func wmRule(_ scheme: ColorScheme) -> Color {
        // Divider rules on cream need extra contrast — bumped 0.12 → 0.18 so
        // section dividers and ingredient hairlines are clearly visible.
        scheme == .dark
            ? WMPalette.labelDark.opacity(0.12)
            : WMPalette.labelLight.opacity(0.18)
    }

    static func wmFaint(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? WMPalette.labelDark.opacity(0.32)
            : WMPalette.labelLight.opacity(0.32)
    }

    static func wmStrike(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? WMPalette.labelDark.opacity(0.30)
            : WMPalette.labelLight.opacity(0.30)
    }

    static func wmBarTrack(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? WMPalette.labelDark.opacity(0.07)
            : WMPalette.labelLight.opacity(0.07)
    }

    static func wmChipBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? WMPalette.labelDark.opacity(0.08)
            : WMPalette.labelLight.opacity(0.05)
    }
}

// Page background — warm canvas with a soft terracotta glow at the top.
// Used as the root of editorial screens (Kalendarz v2).
struct WMPageBackground: View {
    let scheme: ColorScheme

    var body: some View {
        let base = Color.wmPageBase(scheme)
        let glow = WMPalette.terracotta.opacity(scheme == .dark ? 0.12 : 0.10)

        return ZStack {
            base
            RadialGradient(
                colors: [glow, .clear],
                center: .top,
                startRadius: 0,
                endRadius: 360
            )
        }
    }
}
