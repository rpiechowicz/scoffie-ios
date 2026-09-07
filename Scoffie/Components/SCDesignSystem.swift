import SwiftUI

// Scoffie v2 "Cozy Kitchen" design tokens.
// Źródło: v2-design/Scoffie - Onboarding.html (tokeny kolorów).
// Dark-first; light mirrors. Colors converted from OKLCH → sRGB.

enum SCPalette {
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

/// Kolory makroskładników i kalorii — jedna czwórka na całą aplikację.
///
/// Żyły dotąd wpisane w miejscu użycia w trzech kopiach (licznik Kalendarza,
/// pasek makr, arkusz „Cel dnia") i przy pierwszej zmianie odcienia trzeba
/// było trafić we wszystkie trzy. Teraz jest jedno miejsce, bo użytkownik
/// uczy się tych kolorów raz i ma je rozpoznawać na każdym ekranie.
///
/// Tłuszcz stoi na maśle, a nie na głębokiej terakocie, bo terakota jest
/// kolorem KALORII — dwa sąsiednie pierścienie w arkuszu wychodziły w tym
/// samym pomarańczu i trzeba było czytać podpisy, żeby wiedzieć, który jest
/// który. Cała czwórka (pomarańcz, indygo, żółty, zieleń) to zarazem paleta
/// z makiety.
enum SCMacroPalette {
    /// Kalorie nie są czwartym makrem, tylko ich sumą — ale mają swój kolor,
    /// bo w arkuszu dostają własny pierścień.
    static let calories = SCPalette.terracotta
    static let protein = SCPalette.indigo
    static let fat = SCPalette.butter
    static let carbs = SCPalette.sage
}

extension Color {
    static func scCanvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? SCPalette.canvasDark : SCPalette.canvasLight
    }

    static func scLabel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? SCPalette.labelDark : SCPalette.labelLight
    }

    static func scMuted(_ scheme: ColorScheme) -> Color {
        // Light mode opacity bumped from 0.56 → 0.66 to match the design's
        // `rgba(26,15,10,0.68)` muted token — captions and meta rows on the
        // cream canvas were reading too washed-out at 0.56.
        scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.58)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.66)
    }

    static func scTileBg(_ scheme: ColorScheme) -> Color {
        // Cards on cream need slightly more body than the dark-first 0.04 to
        // visibly separate from the canvas — bumped to 0.06.
        scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.04)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.06)
    }

    static func scTileStroke(_ scheme: ColorScheme) -> Color {
        // Hairline strokes on light mode go from 0.06 → 0.12 so card edges
        // and circular xmark wells remain visible against the cream canvas.
        scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.06)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.12)
    }

    /// Elevated card surface. In light mode it goes *lighter* than the cream
    /// canvas — a darker-tinted card there reads as a stain, not as elevation —
    /// and leans on a shadow for separation. Dark mode keeps the dark-first
    /// translucent fill, identical to `scTileBg`.
    static func scCardSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.04)
            : Color(red: 255 / 255, green: 252 / 255, blue: 246 / 255)  // #FFFCF6 warm white
    }

    /// Recessed surface *inside* a card — meal rows, date tiles. Sits one step
    /// below `scCardSurface`, which is how a well reads on a white card.
    static func scInsetSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.025)
            : Color(red: 246 / 255, green: 239 / 255, blue: 228 / 255)  // #F6EFE4 cream well
    }

    /// Hairline for elevated cards — softer than `scTileStroke`, because the
    /// shadow is already doing the separating.
    static func scCardStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.06)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.07)
    }

    static func scFeatureRowBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.08)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.04)
    }

    static func scAccentTint(_ scheme: ColorScheme) -> Color {
        SCPalette.terracotta.opacity(scheme == .dark ? 0.16 : 0.12)
    }

    /// Tło pod akcent zielony — „zapisane / gotowe”.
    ///
    /// Te trzy tinty istniały dotąd wyłącznie jako liczby wpisywane w miejscu
    /// użycia i zdążyły się rozjechać na cztery różne wartości
    /// (`EditorialMealCard` 0.14/0.09, `HealthIntegrationSheet` 0.10/0.07,
    /// `PlanDaySplitsSection` 0.22/0.16, `PlanSlotPickerSheet` 0.16/0.10).
    /// Asystent potrzebuje ich w kartach na tyle często, że dalsze mnożenie
    /// wariantów zrobiłoby z tego loterię — stąd jedna prawda tutaj.
    static func scSageTint(_ scheme: ColorScheme) -> Color {
        SCPalette.sage.opacity(scheme == .dark ? 0.13 : 0.10)
    }

    /// Tło pod akcent niebieski — analiza, liczby, „informacyjnie”.
    static func scIndigoTint(_ scheme: ColorScheme) -> Color {
        SCPalette.indigo.opacity(scheme == .dark ? 0.14 : 0.10)
    }

    /// Tło pod akcent żółty — pytanie asystenta i etykieta „nowe”.
    static func scButterTint(_ scheme: ColorScheme) -> Color {
        SCPalette.butter.opacity(scheme == .dark ? 0.14 : 0.12)
    }

    /// Najgłębsze tło strony — o pół tonu ciemniejsze niż `scCanvas`, bo pod
    /// poświatę nagłówka potrzeba czerni, od której akcent ma się odbić.
    /// Wcześniej ta wartość żyła wyłącznie w `SCPageBackground`; asystent
    /// dokłada nad nią własne warstwy (composer, arkusze), więc musi umieć
    /// nazwać ten sam kolor.
    static func scPageBase(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 12 / 255, green: 8 / 255, blue: 6 / 255)        // #0C0806
            : Color(red: 251 / 255, green: 245 / 255, blue: 234 / 255)   // #FBF5EA
    }

    static func scRule(_ scheme: ColorScheme) -> Color {
        // Divider rules on cream need extra contrast — bumped 0.12 → 0.18 so
        // section dividers and ingredient hairlines are clearly visible.
        scheme == .dark
            ? SCPalette.labelDark.opacity(0.12)
            : SCPalette.labelLight.opacity(0.18)
    }

    static func scFaint(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? SCPalette.labelDark.opacity(0.32)
            : SCPalette.labelLight.opacity(0.32)
    }

    static func scStrike(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? SCPalette.labelDark.opacity(0.30)
            : SCPalette.labelLight.opacity(0.30)
    }

    static func scBarTrack(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? SCPalette.labelDark.opacity(0.07)
            : SCPalette.labelLight.opacity(0.07)
    }

    static func scChipBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? SCPalette.labelDark.opacity(0.08)
            : SCPalette.labelLight.opacity(0.05)
    }
}

// Page background — warm canvas with a soft terracotta glow at the top.
// Used as the root of editorial screens (Kalendarz v2).
struct SCPageBackground: View {
    let scheme: ColorScheme

    var body: some View {
        let base = Color.scPageBase(scheme)
        let glow = SCPalette.terracotta.opacity(scheme == .dark ? 0.12 : 0.10)

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

// MARK: - Pismo skalowane z Dynamic Type

/// `.font(.system(size:))`, tylko że rośnie z Dynamic Type — względem stylu,
/// do którego projektowy rozmiar jest najbliższy.
///
/// Samo `size:` stoi w miejscu przy największym tekście w systemie, a
/// `Font.system(_ style:)` nie daje projektowych 15,5 pt ani 12,5 pt.
/// `@ScaledMetric` łączy jedno z drugim: baza z makiety, skala z ustawień
/// telefonu. Ten sam wzór stoi w `MacroMeter`, tylko tam wprost w widoku,
/// bo sklejony `Text` potrzebuje `Font`, a nie modyfikatora.
private struct SCScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    /// Projektowy rozmiar pisma, który skaluje się z Dynamic Type.
    func scFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo style: Font.TextStyle
    ) -> some View {
        modifier(SCScaledFont(size: size, weight: weight, relativeTo: style))
    }

    /// Cel dotyku 44 pt wokół czegoś narysowanego mniej — bez ruszania układu.
    ///
    /// Ramka rośnie do `size`, a ujemny padding oddaje układowi dokładnie
    /// tyle, ile wzięła, więc sąsiedzi stoją tam, gdzie stali. Obszar dotyku
    /// zostaje przy ramce: SwiftUI trafia w widok po jego własnych granicach,
    /// nie po tym, ile miejsca zgłosił rodzicowi. Sąsiednie cele mogą na
    /// siebie zachodzić — wygrywa ten rysowany później, czyli po prawej.
    func scTapTarget(_ size: CGFloat = 44, drawn: CGFloat) -> some View {
        let side = max(size, drawn)
        return frame(width: side, height: side)
            .contentShape(Rectangle())
            .padding(-(side - drawn) / 2)
    }

    /// To samo, ale wyłącznie w pionie — dla wierszy i pigułek na całą
    /// szerokość, którym brakuje tylko wysokości.
    func scTapHeight(_ height: CGFloat = 44, drawn: CGFloat) -> some View {
        let tall = max(height, drawn)
        return frame(height: tall)
            .contentShape(Rectangle())
            .padding(.vertical, -(tall - drawn) / 2)
    }
}
