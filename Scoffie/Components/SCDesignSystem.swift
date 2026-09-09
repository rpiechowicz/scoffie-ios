import SwiftUI

// Scoffie v2 "Cozy Kitchen" design tokens.
// Źródło: v2-design/Scoffie - Onboarding.html (tokeny kolorów).
// Dark-first; light mirrors. Colors converted from OKLCH → sRGB.
//
// UWAGA na adnotacje OKLCH przy poszczególnych barwach: te opisane jako
// „zmierzone" odpowiadają wiezionym liczbom co do trzeciego miejsca, reszta
// to tokeny z makiety, dostrojone potem ręcznie — i potrafią się od wiezionej
// wartości różnić zauważalnie (terakota o ΔE ≈ 6,5). Nie przeliczaj barwy
// z komentarza, jeśli nie pisze przy nim „zmierzone".

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
        dark:  (135, 194, 165),  // zmierzone oklch(0.765 0.074 163)
        light: (76, 135, 102)    // oklch(0.55 0.10 155) — darkened for legibility on cream
    )
    static let indigo = dynamicColor(
        dark:  (101, 115, 202),  // zmierzone oklch(0.585 0.134 274)
        light: (75, 88, 175)     // slightly darker for cream-bg contrast
    )
    static let butter = dynamicColor(
        dark:  (232, 207, 133),  // zmierzone oklch(0.859 0.097 92)
        light: (160, 120, 40)    // oklch(0.55 0.12 80) — mustard, readable on cream
    )

    // Trzy akcenty dołożone dla pór „pomiędzy" (II śniadanie, podwieczorek,
    // przekąska). Wcześniej dziedziczyły barwę po sąsiednim posiłku głównym
    // i przez to obiad wychodził w kalendarzu tym samym kolorem, co
    // podwieczorek — a to są dwa różne wiersze w tym samym dniu.
    //
    // Dobrane po odstępie na kole barw, nie „na oko": każda para ma co
    // najmniej ~35° różnicy, a pary stojące najbliżej (róż–terakota,
    // lawenda–indygo) rozjeżdżają się dodatkowo jasnością i nasyceniem.
    // Dzień czyta się przez to jako przejście od ciepłego rana do chłodnego
    // wieczoru: masło → róż → szałwia → morska → indygo, a bezczasowa
    // przekąska stoi z boku w lawendzie.

    /// II śniadanie. Przygaszony róż — cieplejszy niż wszystko po lewej
    /// stronie palety, ale wyraźnie różowy, nie pomarańczowy jak terakota.
    static let rose = dynamicColor(
        dark:  (224, 154, 164),  // oklch(0.76 0.08 5)
        light: (176, 78, 104)    // oklch(0.52 0.13 0) — ciemniejszy na kremie
    )

    /// Podwieczorek. Morska — jedyny wolny kawałek koła między szałwią
    /// a indygo, i jedyny kolor w palecie, którego nie da się pomylić
    /// z zielenią obiadu.
    static let teal = dynamicColor(
        dark:  (111, 185, 204),  // oklch(0.73 0.07 215)
        light: (40, 120, 145)    // oklch(0.51 0.08 220) — ciemniejsza na kremie
    )

    /// Przekąska. Lawenda wprost z makiety kalendarza (`#B79BE0`) — pora
    /// bez godziny dostaje kolor, który też nie pasuje do rytmu dnia.
    static let lavender = dynamicColor(
        dark:  (183, 155, 224),  // #B79BE0 z canvasu
        light: (126, 79, 160)    // ciemniejsza i bardziej fioletowa niż indygo
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

    /// Akcenty kapsuły toastu — jedyna powierzchnia w aplikacji, która nie
    /// stoi na płótnie.
    ///
    /// Drugi komplet liczb dla barw, które paleta już ma, i to jest celowe.
    /// Warianty w ciemnym motywie są strojone pod `canvasDark` (#1A1411),
    /// a kapsuła wychodzi z CZERNI — a czerń jest wobec `canvasDark` inną
    /// planetą (płótno ma wobec niej ledwie 1,15 : 1). Ta sama czwórka
    /// rozjeżdżała się tam prawie trzykrotnie: szałwia 10,3 : 1, masło
    /// 13,7 : 1, a indygo tylko 4,86 : 1. Glif 12 pt w indygo czytał się jak
    /// przybrudzony piksel, a masło przekrzykiwało biały tytuł obok.
    ///
    /// Warianty jasne są z kolei strojone pod CIEPŁĄ BIEL kapsuły
    /// (`#FFFCF6`), nie pod krem płótna, i mają nieść glif WYCIĘTY w tej
    /// bieli — stąd wszystkie są ciemniejsze od swoich odpowiedników
    /// z palety i wszystkie trzymają wobec niej co najmniej 4,9 : 1.
    ///
    /// RUSZASZ `SCPalette.sage`, `.indigo` ALBO `.butter`? Zajrzyj i tutaj —
    /// te wartości nie wynikają z tamtych automatycznie.
    enum Toast {
        /// Powierzchnia kapsuły w jasnym motywie — ciepła biel karty, nie krem
        /// płótna, żeby toast czytał się jako coś unoszącego się NAD ekranem.
        /// W ciemnym motywie kapsuła zostaje czarna: tam czerń jest zgodna
        /// z wyspą i nic nie zyskałaby na zmianie.
        static let surfaceLight = Color(red: 255 / 255, green: 252 / 255, blue: 246 / 255) // #FFFCF6

        /// Pismo i glif wycięty w kapsule — po prostu druga strona powierzchni.
        static let inkLight = Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255)        // #1A1411

        /// Sukces. Jedyna, która już była w paśmie — reszta jest strojona
        /// do niej. Szałwia znaczy w tej aplikacji „zrobione" (`scChecked`).
        static let sage = SCPalette.dynamicColor(
            dark:  (135, 194, 165),  // 10,29 : 1 na czerni
            light: (61, 122, 88)     //  4,97 : 1 na ciepłej bieli kapsuły
        )

        /// Informacja. Ruszona jest przede wszystkim jasność
        /// (oklch 0,585 → 0,719), nasycenie schodzi śladowo (0,134 → 0,121),
        /// barwa stoi w miejscu (274°) — więc nadal jest to rozpoznawalnie
        /// indygo, które znaczy „informacyjnie" (`scIndigoTint`) i „białko".
        static let indigo = SCPalette.dynamicColor(
            dark:  (141, 158, 240),  // 8,28 : 1 na czerni
            light: (75, 88, 175)     // 6,19 : 1 na ciepłej bieli — tu wariant
                                     // z palety trafia idealnie
        )

        /// Uwaga. Ściszone, ale ŚWIADOMIE nie do końca — masło zostaje
        /// wyraźnie jaśniejsze od reszty, bo to ono siedzi na trwałym pasku
        /// braku sieci, czyli na jedynym toaście, w który ktokolwiek naprawdę
        /// się wpatruje.
        ///
        /// Parą do pilnowania przy deuteranopii NIE jest szałwia–masło (te
        /// rozjeżdżają się swobodnie, ΔE ≈ 38), tylko szałwia–ember: ΔE ≈ 25,
        /// czyli najbliższa para w komplecie — i akurat ta, w której pomyłka
        /// kosztuje najwięcej, bo to „zrobione" kontra „nie udało się".
        /// Rozdziela je dopiero glif, dlatego ma zostać ciężki.
        static let butter = SCPalette.dynamicColor(
            dark:  (220, 194, 118),  // 12,02 : 1 na czerni
            light: (142, 102, 24)    //  5,05 : 1 — musztarda ciemniejsza niż
                                     // `SCPalette.butter` na kremie (3,96 : 1
                                     // nie uniosłoby wyciętego glifu).
                                     // Najsłabsze ogniwo kompletu, stąd zapas
        )

        /// Błąd. NOWA barwa, nie ma jej w palecie na płótnie — i tak ma
        /// zostać.
        ///
        /// Wcześniej błąd brał róż, ale róż ma już trzy etaty (II śniadanie,
        /// owoce i alkohole na liście zakupów, pierścień ekranu startowego)
        /// i jest przy nasyceniu 0,085 NAJMNIEJ natarczywą barwą, jaką ta
        /// aplikacja ma — w robocie, która natarczywa być musi. Wychodziło
        /// z tego, że awaria czytała się łagodniej niż akcja główna.
        /// Systemowa czerwień była odrzucona słusznie (jest brutalna i obca
        /// tej palecie); odpowiedzią jest ciepły alarm zestrojony z resztą,
        /// a nie sięgnięcie po najbliższy róż.
        ///
        /// Zostaje w `Toast` i tylko tam: na płótnie biłaby się z terakotą,
        /// z którą dzieli jasność, a dzieli je raptem 31° barwy.
        ///
        /// W ciemnym motywie nasycenie podniesione ponad to, co dawał sam
        /// alarm: przy tej samej jasności i barwie odsuwa embera od szałwii
        /// w oczach osoby z deuteranopią (ΔE 21,7 → 25,2). Rozjaśnianie
        /// działa tu ODWROTNIE — jaśniejszy ember zbliża się do szałwii,
        /// nie oddala.
        static let ember = SCPalette.dynamicColor(
            dark:  (254, 97, 113),   // 7,16 : 1 na czerni
            light: (191, 45, 62)     // 5,60 : 1 na ciepłej bieli — wyraźnie
                                     // czerwony, nie pomarańczowy jak terakota
        )
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
    /// (kafel posiłku 0.14/0.09, `HealthIntegrationSheet` 0.10/0.07,
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

    /// Znak odhaczenia — „zjedzone".
    ///
    /// Neutralny, nie zielony, i to jest decyzja, a nie oszczędność. Sześć pór
    /// dnia zajmuje sześć barw, a szałwia była jedną z nich — kolorem obiadu.
    /// Odhaczony obiad miał przez to dwa szałwiowe kółka w jednym wierszu
    /// i nie dawało się powiedzieć, które mówi „obiad", a które „zjedzone".
    ///
    /// Przesunięcie obiadu nic by nie dało: żeby status miał własną barwę,
    /// musiałaby stać co najmniej ~90° od każdej z sześciu pór, a tyle
    /// wolnego miejsca na kole już nie ma. Status wychodzi więc z koła
    /// w ogóle: to ATRAMENT, nie plama. Kółko z ledwie zaznaczonym
    /// wypełnieniem, obwódką w połowie mocy i wyraźnym ptaszkiem w środku —
    /// ta sama warstwa, co pismo wiersza. Pełny krążek w tym kolorze świecił
    /// w ciemnym motywie jak lampka i przekrzykiwał zarówno zdjęcie, jak
    /// i tytuł dania, choć zjedzony posiłek ma PRZYGASAĆ, a nie wołać.
    ///
    /// Szałwia zostaje przy podsumowaniach dnia (kropki „2 z 4", kropka
    /// „z planem" na pasku dni) — tam nie sąsiaduje z kolorem pory, więc nie
    /// ma czego mylić, i nadal znaczy „zrobione".
    static func scChecked(_ scheme: ColorScheme) -> Color {
        scLabel(scheme)
    }

    static func scChipBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? SCPalette.labelDark.opacity(0.08)
            : SCPalette.labelLight.opacity(0.05)
    }
}

// Mieszanie barw — odpowiednik `color-mix(in oklch, …)` z tokenów makiety.
//
// Mieszka w systemie projektowym, a nie przy ekranie, który akurat pierwszy
// tego potrzebował: `mix(black:)` woła dziś kilkanaście miejsc (awatary
// domowników, kafle ustawień, mierniki makro, kółko odhaczenia na Zakupach),
// więc schowane w pliku jednego komponentu znikało razem z nim.
//
// Nazwy są własne (`mix(black:)` / `mix(white:)`), bo `Color.mix(with:by:in:)`
// z systemowego SwiftUI ma inną listę argumentów — pomyłka w wywołaniu wychodzi
// wtedy jako „extra argument 'black' in call”, a nie jako cicha podmiana.
extension Color {
    /// Interpoluje składowe w zapisie GAMMA sRGB (jak `color-mix in srgb`),
    /// nie w przestrzeni liniowej — więc połowa drogi to połowa składowych,
    /// a nie połowa jasności.
    func mix(with other: Color, by fraction: CGFloat) -> Color {
        let f = max(0, min(1, fraction))

        let a = UIColor(self).cgColor.components ?? [0, 0, 0, 1]
        let b = UIColor(other).cgColor.components ?? [0, 0, 0, 1]

        // Barwa w skali szarości ma dwie składowe (biel + alfa), nie cztery —
        // wtedy jasność siedzi w `[0]` i wszystkie trzy kanały biorą się stamtąd.
        let aR = a.count >= 3 ? a[0] : a[0]
        let aG = a.count >= 3 ? a[1] : a[0]
        let aB = a.count >= 3 ? a[2] : a[0]
        let bR = b.count >= 3 ? b[0] : b[0]
        let bG = b.count >= 3 ? b[1] : b[0]
        let bB = b.count >= 3 ? b[2] : b[0]

        return Color(
            red:   Double(aR + (bR - aR) * f),
            green: Double(aG + (bG - aG) * f),
            blue:  Double(aB + (bB - aB) * f)
        )
    }

    /// Przyciemnienie o `fraction` — cień gradientu pod akcentem.
    func mix(black fraction: CGFloat) -> Color {
        self.mix(with: .black, by: fraction)
    }

    /// Rozjaśnienie o `fraction` — światło u góry gradientu.
    func mix(white fraction: CGFloat) -> Color {
        self.mix(with: .white, by: fraction)
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
