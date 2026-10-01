// WYGENEROWANE przez scoffie-design (npm run build) z tokens/cook.json — nie edytuj ręcznie.
// Zmiana wartości: tokens/cook.json → npm run build → skopiuj dist/ios/SCCookTokens.swift
// do scoffie-ios/Scoffie/Components/ → npm run check:ios na zielono.
import SwiftUI

/// Tokeny trybu Gotuj — jedno źródło z Androidem (`ScoffieTokens.kt`).
/// Opis ekranów i komponentów: scoffie-design `docs/GOTUJ.md`.
enum SCCook {
    enum Palette {
        /// Opis kroku („jak”) 17 pt — jaśniejszy niż muted, bo to najdłuższy tekst czytany z metra (ST1–ST3).
        static func body(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.86)
                : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.86)
        }

        /// Podpisy w kartach doku: podsumowanie „1 trwa · 1 do włączenia”, „krok 3 · z 20 min”, nagłówki ZA CHWILĘ / JUŻ W DANIU, wiersze „już w daniu”, notka wstrzymanego timera (ST5, KM1–KM2). Ciszej niż muted (0,58). Jasny motyw: o 0,08 mocniej, jak muted (0,58 → 0,66).
        static func caption(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.42)
                : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.5)
        }

        /// Wskazówka pod nagłówkiem ekranu końca timera („Złote ze wszystkich stron — gotowe.”) — ST4.
        static func alarmBody(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.72)
                : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.72)
        }

        /// Kroki przed nami w pierścieniu kroków (nagłówek trybu, talerz po wstrzymaniu, Live Activity) i tło przycisku „Dalej” w wyspie. Zrobione = palette.sage, bieżący = palette.terracotta.
        static func ringTodo(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.16)
                : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.16)
        }

        /// Plakietka liczby składników w wyspie, obwódka „Dalej”, wybrany segment „Ten krok / Cały przepis” (Y3K*, KM1).
        static func badge(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.14)
                : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.14)
        }

        /// Obwódka 1 pt wyspy i kart doku (Timery, Składniki), kreski rzędu statystyk na zakończeniu (Y3*, EF8). Jasny motyw jak semantic.rule.
        static func dockStroke(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.1)
                : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.18)
        }

        /// Nakładka kapsuły wstrzymanego timera na semantic.canvas (Y3S „Jeden wstrzymany”).
        static func pausedFill(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.05)
                : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.05)
        }

        /// Powierzchnia wyspy, kapsuł timerów, kart doku i szuflad powitania. Ciemny motyw: płótno (semantic.canvas, jak w makiecie). Jasny: ciepła biel uniesionej powierzchni (semantic.cardSurface) — płótno #FAF6F0 na tle strony #FBF5EA to ten sam kolor i dok odcinała tylko cienka obwódka (runda 2 testów, 1.10.2026).
        static func dockSurface(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255)
                : Color(red: 255 / 255, green: 252 / 255, blue: 246 / 255)
        }

        /// Warstwa na zdjęciu (krycie 0,35) ekranu końca timera — ST4.
        static func alarmVeil(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 12 / 255, green: 8 / 255, blue: 6 / 255).opacity(0.88)
                : Color(red: 251 / 255, green: 245 / 255, blue: 234 / 255).opacity(0.88)
        }

        /// Zasłona za otwartą kartą doku (Timery, Składniki) — ST5, KM1. Jasny motyw: lżej, jak przyciemnienie arkusza systemu.
        static func scrim(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0 / 255, green: 0 / 255, blue: 0 / 255).opacity(0.7)
                : Color(red: 0 / 255, green: 0 / 255, blue: 0 / 255).opacity(0.4)
        }

        /// Cień kapsuł (0 12 30) i wyspy z kartami (0 14 36) — dok pływa nad treścią kroku. Jasny motyw: cień miękki.
        static func dockShadow(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0 / 255, green: 0 / 255, blue: 0 / 255).opacity(0.55)
                : Color(red: 0 / 255, green: 0 / 255, blue: 0 / 255).opacity(0.16)
        }
    }

    enum Opacity {
        /// Kolor timera na semantic.canvas w kapsule, która trwa (Y3K1). Kolor timera: terakota albo szałwia, patrz docs/GOTUJ.md „Kolor timera”.
        static let timerFill: Double = 0.1

        /// Obwódka 1 pt kapsuły, która trwa, w kolorze timera (Y3K1).
        static let timerStroke: Double = 0.3

        /// Tor pierścieni timerów (kapsuła, arkusz Timery, pigułki) w kolorze timera.
        static let timerTrack: Double = 0.25

        /// Terakota na semantic.canvas w kapsule „do włączenia” (obwódka 1,5 pt pełna terakota) — Y3S.
        static let pendingFill: Double = 0.12

        /// Pusty okrąg w miejscu pierścienia w pojedynczej kapsule „do włączenia” — Y3S.
        static let pendingRing: Double = 0.35

        /// Krycie terakoty na starcie łagodnego pulsu „do włączenia” (pierścień rozchodzi się na zewnątrz kapsuły do 0).
        static let pendingPulse: Double = 0.38

        /// Krycie terakoty na starcie mocnego pulsu „po czasie”.
        static let overduePulse: Double = 0.6

        /// Tło pigułki biegnącego timera w kolorze timera: arkusz wyjścia, „leci dalej” na ekranie końca timera (XW1–XW2, ST4).
        static let timerPill: Double = 0.12

        /// Szałwia pod ptaszkiem „Zakończ gotowanie” w miejscu „Dalej” na ostatnim kroku (Y3S); obwódka cookFinishStroke.
        static let finishFill: Double = 0.2

        /// Obwódka przycisku „Zakończ gotowanie” w szałwii.
        static let finishStroke: Double = 0.5

        /// Wyróżniony kafel „Wstrzymaj” w arkuszu wyjścia: szałwia jako tło (XW0–XW2).
        static let pauseTileFill: Double = 0.08

        /// Obwódka kafla „Wstrzymaj” w szałwii.
        static let pauseTileStroke: Double = 0.35

        /// Aureola 5 pt wokół terakotowego „play” na talerzu Kalendarza (EC41, PS1).
        static let playHalo: Double = 0.18

        /// Pierwsza aureola tarczy końca timera w terakocie; druga stoi na semantic.accentTint (ST4).
        static let alarmHalo: Double = 0.22

        /// Tor zewnętrznego łuku „minut po czasie” w terakocie (ST4).
        static let alarmTrack: Double = 0.14

        /// Krycie zdjęcia dania w nagłówku każdego ekranu trybu (powitanie, krok, zakończenie).
        static let headerPhoto: Double = 0.85

        /// Krycie zdjęcia na całym ekranie końca timera, pod cook.alarmVeil (ST4).
        static let alarmPhoto: Double = 0.35
    }

    enum Duration {
        /// Łagodny puls „do włączenia”: pierścień 0 → spacing.cookInviteSpread, krycie opacity.cookPendingPulse → 0, ease-out, w pętli. Kapsuła się nie skaluje.
        static let invitePulse: Double = 2

        /// Mocny puls „po czasie”: 0 → spacing.cookOverdueSpread, opacity.cookOverduePulse → 0, ease-out, w pętli.
        static let overduePulse: Double = 1.2

        /// Aureole tarczy końca timera: skala 0,86 → 1,22, krycie warstwy 0,55 → 0, ease-out, w pętli; druga z opóźnieniem połowy okresu.
        static let alarmHalo: Double = 1.6

        /// Kołysanie dzwonka na tarczy: 0° → 14° → −12° → 8° → 0° w pierwszych 40 % okresu, potem spoczynek; oś u góry dzwonka.
        static let alarmBell: Double = 1.6
    }

    enum Motion {
        /// Przejście między krokami: nowy krok wjeżdża z boku, nagłówek szybciej niż opis (§8.2 workstreamu). Ta sama krzywa co motion.textRoll — tytuł kroku przenika jak danie w daniu. Do strojenia na urządzeniu.
        static let step: Animation = .spring(response: 0.42, dampingFraction: 1)

        /// Kapsuły timerów wchodzą, schodzą i zmieniają układ (jedna ↔ dwie), karta doku rozwija się z wyspy. Ta sama sprężyna co motion.dayNavigation. Do strojenia na urządzeniu.
        static let dock: Animation = .spring(response: 0.34, dampingFraction: 0.86)
    }

    enum Size {
        /// Wysokość zdjęcia dania w nagłówku każdego ekranu trybu (pełna szerokość) — przejścia między ekranami nie skaczą (§13).
        static let headerPhoto: CGFloat = 330

        /// Wygaszenie zdjęcia do semantic.pageBase: od spacing.cookHeaderFadeStart w dół (kończy się 2 pt pod zdjęciem).
        static let headerFade: CGFloat = 172

        /// Krążek z pierścieniem kroków i numerem bieżącego kroku (typography.cookStepNumber) w nagłówku trybu — tej samej wielkości co krzyżyk (SCSheetCloseButton 36, runda 2: „X oraz stepper mają być takiej samej wielkości”) i na tej samej powierzchni co krzyżyk na zdjęciu. Pierścień: promień size.cookStepRingRadius, kreska stroke.cookStepRing, końce okrągłe, start o 12:00.
        static let stepRing: CGFloat = 36

        /// Promień pierścienia kroków w krążku 36 (do środka kreski).
        static let stepRingRadius: CGFloat = 13.5

        /// Krążki „Wstecz” i „Dalej” (ostatni krok: ptaszek „Zakończ gotowanie”) w wyspie doku — wysokość pigułki dolnego menu aplikacji (60 − 2 × 6).
        static let islandButton: CGFloat = 48

        /// Plakietka liczby składników kroku obok „Składniki” w wyspie (min. szerokość i wysokość).
        static let islandBadge: CGFloat = 22

        /// Pierścień postępu w POJEDYNCZEJ kapsule timera (pełna szerokość doku); promień 12,8.
        static let timerRing: CGFloat = 30

        /// Pierścień w kapsule z PARY (dwa timery obok siebie) — zarazem przycisk start / pauza / wznów / gotowe z glifem w środku (runda 2: „włączyć / wyłączyć timer z pulpitu, nie wchodząc w kartę”); kreska stroke.cookTimerRingSmall, dotyk 44.
        static let timerRingPair: CGFloat = 34

        /// Ten sam pierścień-przycisk w kapsule z TRÓJKI — trzy timery obok siebie, gdy się zmieszczą (runda 2), dotyk 44.
        static let timerRingTrio: CGFloat = 30

        /// Pierścień-przycisk pauzy w wierszu arkusza Timery; promień 20,5 (ST5).
        static let sheetTimerRing: CGFloat = 46

        /// Mały pierścień w pigułce biegnącego timera (arkusz wyjścia, „leci dalej”); promień 9.
        static let pillRing: CGFloat = 22

        /// Krążek ikony produktu w kolorze działu w wierszu arkusza Składniki (ikona 16) — KM1, D36.
        static let ingredientIcon: CGFloat = 32

        /// Tarcza ekranu końca timera: łuk „minut po czasie” na promieniu 108, krążek 94 z obwódką stroke.cookAlarmDisc (ST4).
        static let alarmDial: CGFloat = 244

        /// Aureole za tarczą końca timera (dwie, na zmianę).
        static let alarmHalo: CGFloat = 200

        /// Krążek z glifem pauzy / stopu w kaflach „Wstrzymaj” i „Zakończ” (XW0–XW2).
        static let exitTileIcon: CGFloat = 52

        /// Pełny terakotowy „play” na talerzu Kalendarza (prawy dół), w krążku semantic.pageBase size.cookPlatePlayWell; cel dotyku 44+ (EC41).
        static let platePlay: CGFloat = 38

        /// Krążek tła pod „play” na talerzu — wycina go z obręczy.
        static let platePlayWell: CGFloat = 46

        /// Pieczątka „zjedzone” jako kółko z ptaszkiem (lewy dół talerza, D23) — w krążku semantic.pageBase 38.
        static let plateStamp: CGFloat = 32
    }

    enum Height {
        /// Wyspa ‹ Składniki N › na dole ekranu kroku — zawsze w tym samym miejscu (D34). Wysokość, boki i położenie jak dolne menu aplikacji (SCFloatingTabBar 60 pt, runda 2 testów). Kapsuła, padding spacing.cookIslandPadding.
        static let island: CGFloat = 60

        /// Kapsuła timera nad wyspą; jedna = cała szerokość doku, dwie = obok siebie (D34).
        static let timerCapsule: CGFloat = 56

        /// Przycisk w pojedynczej kapsule: pauza (krążek), „▶ Start”, „▶ Wznów”, „✓ Gotowe”.
        static let timerAction: CGFloat = 40

        /// Minimalna wysokość wiersza trwającego timera w arkuszu Timery.
        static let timerRow: CGFloat = 62

        /// Przyciski pełnej szerokości trybu: „Zaczynamy”, „Zjedzone”, „Gotuj dalej”, „Wyślij” (miękka kapsuła).
        static let button: CGFloat = 56

        /// Szuflady powitania „Składniki · N” i „Rady kucharza · N” (WL1).
        static let drawer: CGFloat = 72

        /// Karta „Gotujesz 2 porcje / tyle, ile w planie” ze stepperem (WL1).
        static let servingsCard: CGFloat = 64

        /// Segment przełącznika „Ten krok / Cały przepis” w karcie Składniki.
        static let segment: CGFloat = 36

        /// Wiersz składnika w karcie Składniki (z podpisem części — 56).
        static let ingredientRow: CGFloat = 50

        /// Przyciski „+1 / +2 / +5 min” na ekranie końca timera (D35).
        static let alarmExtend: CGFloat = 52

        /// „✓ Gotowe — dalej” na ekranie końca timera.
        static let alarmDone: CGFloat = 60

        /// Kafle „Wstrzymaj” / „Zakończ” obok siebie w arkuszu „Wychodzisz z gotowania?”.
        static let exitTile: CGFloat = 132
    }

    enum Stroke {
        /// Kreska pierścienia kroków w nagłówku; widoczna przerwa między odcinkami spacing.cookStepRingGap, końce okrągłe.
        static let stepRing: CGFloat = 3

        /// Kreska pierścienia pojedynczej kapsuły, końce okrągłe. Łuk = pozostały czas i ubywa ZGODNIE ze wskazówkami zegara (koniec stoi o 12:00, początek ucieka w prawo — runda 2 testów).
        static let timerRing: CGFloat = 3.4

        /// Kreska pierścienia-przycisku w kapsułach z pary i trójki.
        static let timerRingSmall: CGFloat = 3

        /// Kreska pierścienia-przycisku w arkuszu Timery.
        static let sheetTimerRing: CGFloat = 4

        /// Pierścień kroków zamiast obręczy pory na talerzu po wstrzymaniu (PS1), promień 90,5.
        static let plateStepRing: CGFloat = 5

        /// Terakotowa obwódka krążka na tarczy końca timera (łuk minut ma 4).
        static let alarmDisc: CGFloat = 10
    }

    enum Spacing {
        /// Margines boczny treści każdego ekranu trybu.
        static let page: CGFloat = 20

        /// Gdzie zaczyna się wygaszenie zdjęcia (od góry ekranu).
        static let headerFadeStart: CGFloat = 160

        /// Etykieta nad tytułem (etap kroku, „GOTUJEMY · OBIAD”) zaczyna się tyle od góry ekranu — na każdym ekranie trybu w tym samym miejscu, wcześniej tylko na zakończeniu (270).
        static let titleTop: CGFloat = 290

        /// Dok pływa tyle od boków ekranu (D34) — jak dolne menu aplikacji (SCFloatingTabBar.sideMargin).
        static let dockSide: CGFloat = 20

        /// Odległość doku od dolnej krawędzi bezpiecznego obszaru — 0, czyli tam, gdzie stoi dolne menu aplikacji (nad paskiem domowym).
        static let dockBottom: CGFloat = 0

        /// Odstęp kapsuł (albo karty Timery) od wyspy.
        static let dockGap: CGFloat = 10

        /// Odstęp dwóch kapsuł obok siebie.
        static let capsuleGap: CGFloat = 8

        /// Wcięcie krążków od krawędzi wyspy (jak pigułka w dolnym menu).
        static let islandPadding: CGFloat = 6

        /// Odstęp krążków od środka „Składniki” w wyspie.
        static let islandGap: CGFloat = 6

        /// Miejsce pod treścią kroku zarezerwowane na dok z kapsułami (wyspa 60 + przerwa 10 + kapsuła 56), liczone od dolnej krawędzi bezpiecznego obszaru — tekst kroku przewija się pod dokiem, ale jego koniec staje nad nim.
        static let dockReserve: CGFloat = 126

        /// Widoczna przerwa między odcinkami pierścienia kroków — od końca do końca zaokrąglenia (łuk między odcinkami = przerwa + kreska).
        static let stepRingGap: CGFloat = 2

        /// Jak daleko rozchodzi się łagodny puls „do włączenia”.
        static let inviteSpread: CGFloat = 9

        /// Jak daleko rozchodzi się mocny puls „po czasie”.
        static let overdueSpread: CGFloat = 12
    }

    enum Radius {
        /// Kafle trybu: karta porcji, szuflady, „NA NASTĘPNY RAZ”, kafle wyjścia, pole uwag (§13: promień kafli 24).
        static let tile: CGFloat = 24

        /// Karty doku: Timery (w miejscu kapsuł) i Składniki (wyspa rozwinięta w kartę) — połowa wysokości wyspy, więc wyspa i karta to ten sam kształt, rozwijany w górę.
        static let dockCard: CGFloat = 30

        /// Kafel „W TYM KROKU” z „▶ Start” w arkuszu Timery.
        static let timerStartTile: CGFloat = 22

        /// Panel „Jeszcze chwilę?” na dole ekranu końca timera.
        static let alarmPanel: CGFloat = 28
    }

    enum Typography {
        /// Tytuł kroku — czytelny z metra (§8.5); ≤ 30 znaków = dwie linie (D37). Trzy linie → cookStepTitleCompact.
        static let stepTitle = SCCookTextStyle(size: 40, weight: .heavy, tracking: -1.4, lineHeight: 41.2)

        /// Tytuł kroku, który przy 40 pt wyszedłby na trzy linie (D37).
        static let stepTitleCompact = SCCookTextStyle(size: 32, weight: .heavy, tracking: -1.12, lineHeight: 33)

        /// Etykieta nad tytułem: etap kroku („SMAŻENIE”, „W MIĘDZYCZASIE”), „GOTUJEMY · OBIAD” — wersaliki w szałwii.
        static let stage = SCCookTextStyle(size: 12, weight: .heavy, tracking: 0.96, lineHeight: nil)

        /// Numer bieżącego kroku w środku pierścienia kroków (krążek 36).
        static let stepNumber = SCCookTextStyle(size: 13, weight: .heavy, tracking: 0, lineHeight: nil)

        /// Opis kroku w cook.body.
        static let stepBody = SCCookTextStyle(size: 17, weight: .regular, tracking: 0, lineHeight: 25.5)

        /// Adnotacja kroku z ikoną (ostrzeżenie w palette.butter, po czym poznać, rada).
        static let note = SCCookTextStyle(size: 15, weight: .regular, tracking: 0, lineHeight: nil)

        /// Nazwa dania na powitaniu (WL1).
        static let welcomeTitle = SCCookTextStyle(size: 38, weight: .heavy, tracking: -1.33, lineHeight: 39.1)

        /// „Smacznego!” na zakończeniu (EF8).
        static let finishTitle = SCCookTextStyle(size: 44, weight: .heavy, tracking: -1.76, lineHeight: 44)

        /// Tytuł karty doku („Timery”, „Składniki”) i arkusza uwag.
        static let sheetTitle = SCCookTextStyle(size: 22, weight: .heavy, tracking: -0.44, lineHeight: nil)

        /// Nagłówki sekcji kart doku (TRWA, W TYM KROKU, TERAZ, ZA CHWILĘ · KROK 11) i „KROK 10 Z 12”.
        static let sectionLabel = SCCookTextStyle(size: 12, weight: .heavy, tracking: 1.2, lineHeight: nil)

        /// Nazwa albo warunek startu w kapsule timera, w kolorze timera, jedna linia.
        static let timerLabel = SCCookTextStyle(size: 11, weight: .bold, tracking: 0, lineHeight: nil)

        /// Czas w pojedynczej kapsule („9:41”, „+0:42”), cyfry tabelaryczne.
        static let timerTime = SCCookTextStyle(size: 20, weight: .heavy, tracking: 0, lineHeight: nil)

        /// Czas w kapsule z pary.
        static let timerTimePair = SCCookTextStyle(size: 17, weight: .heavy, tracking: 0, lineHeight: nil)

        /// Czas w kapsule z trójki.
        static let timerTimeTrio = SCCookTextStyle(size: 15, weight: .heavy, tracking: 0, lineHeight: nil)

        /// Czas w wierszu arkusza Timery, w kolorze timera.
        static let sheetTime = SCCookTextStyle(size: 26, weight: .heavy, tracking: -0.78, lineHeight: nil)

        /// Licznik „po czasie” w tarczy końca timera („+0:18”).
        static let alarmCounter = SCCookTextStyle(size: 54, weight: .heavy, tracking: -2.43, lineHeight: 56.7)

        /// Nagłówek ekranu końca timera (tytuł alertu ze scenariusza: „Sprawdź, czy są złote”).
        static let alarmTitle = SCCookTextStyle(size: 32, weight: .heavy, tracking: -0.96, lineHeight: 35.2)

        /// „Wychodzisz z gotowania?”.
        static let exitTitle = SCCookTextStyle(size: 24, weight: .heavy, tracking: -0.48, lineHeight: nil)

        /// Główne akcje w terakocie: „Zaczynamy”, „Wyślij”, „▶ Start”.
        static let button = SCCookTextStyle(size: 17, weight: .heavy, tracking: 0, lineHeight: nil)

        /// Akcje w szałwii i neutralne: „Zjedzone”, „Gotuj dalej”, „Gotowe — dalej”.
        static let buttonQuiet = SCCookTextStyle(size: 17, weight: .bold, tracking: 0, lineHeight: nil)
    }
}

/// Styl tekstu z tokenu: krój systemowy, grubość, światło liter, wysokość
/// linii z makiety (`nil` = naturalna). Odstęp między liniami w SwiftUI to
/// `lineHeight` minus naturalna linia kroju (~1,19 × rozmiar).
struct SCCookTextStyle {
    let size: CGFloat
    let weight: Font.Weight
    let tracking: CGFloat
    let lineHeight: CGFloat?

    var font: Font { .system(size: size, weight: weight) }

    var lineSpacing: CGFloat {
        guard let lineHeight else { return 0 }
        return max(0, lineHeight - size * 1.19)
    }
}
