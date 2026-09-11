import SwiftUI

// Kalendarz — stan posiłku względem „teraz” i rysunek, który ten stan niesie.
//
// Plik został po `CalendarMealRow`: wiersze listy zeszły z ekranu razem
// z układem v11 · Talerz (dzień jest teraz jednym wielkim daniem na środku
// i sekwencją talerzyków pod nim, patrz `CalendarPlate`). Zostało to, co było
// w tamtym pliku NAJWAŻNIEJSZE i jest wspólne dla wszystkich układów: jeden
// słownik stanów, jedno liczenie „za ile” i jedno kółko, które ten stan
// rysuje.
//
// Stan liczy ekran (`CalendarView.statusMap`), a nie widok: „następny”
// zależy od całego dnia i od zegara, więc pojedynczy talerz nie umie tego
// rozstrzygnąć sam. Gdyby dwa miejsca liczyły osobno, prędzej czy później
// pierścień na talerzu i obwódka w sekwencji wskazałyby dwa różne posiłki.

/// Stan posiłku względem „teraz”.
enum CalendarMealStatus {
    /// Odhaczony przez zalogowanego użytkownika.
    case eaten
    /// Pierwszy nieodhaczony posiłek z godziną — tylko dzisiaj.
    case next
    /// Dzisiaj, ale już za „następnym”.
    case later
    /// Slot bez stałej pory (domyślnie przekąska).
    case anytime
    /// Dzień miniony albo przyszły — nic nie nadchodzi i nic nie minęło.
    case planned

    var isEaten: Bool { self == .eaten }
}

/// „za 4 h 19 min” — ile zostało do posiłku.
enum CalendarRelativeTime {
    /// Ile minut po godzinie posiłku wciąż mówimy „teraz".
    ///
    /// Obiad o 14:00 zjedzony o 14:10 nie jest spóźniony, tylko zjedzony —
    /// ale ten sam obiad oglądany o 18:00 już nie jest „teraz" i ekran nie ma
    /// prawa tak twierdzić. Bez tej granicy pierwszy nieodhaczony posiłek dnia
    /// stał w „teraz" aż do północy.
    static let graceMinutes = 20

    static func text(to minutes: Int, from nowMinutes: Int) -> String {
        text(inMinutes: minutes - nowMinutes)
    }

    /// To samo, ale z gotową różnicą. Talerz liczy ją raz i nie ma po co
    /// rozkładać jej z powrotem na dwie godziny.
    static func text(inMinutes delta: Int) -> String {
        if delta <= 0 {
            return delta >= -graceMinutes ? "teraz" : "pora minęła"
        }

        let hours = delta / 60
        let rest = delta % 60
        if hours > 0 && rest > 0 { return "za \(hours) h \(rest) min" }
        if hours > 0 { return "za \(hours) h" }
        return "za \(rest) min"
    }
}

// MARK: - Checkbox

/// Kółko stanu: puste (później / inny dzień) · kreskowane (bez pory) ·
/// w kolorze pory z kropką (następne) · pełne z ptaszkiem (zjedzone).
///
/// Siedzi w rogu wielkiego talerza jako pieczątka odhaczenia. Ten sam rysunek
/// stał wcześniej w wierszu listy i na węźle łuku doby — i to jest cała jego
/// racja bytu: jeden znak na jeden stan, niezależnie od układu ekranu.
struct CalendarMealCheck: View {
    let status: CalendarMealStatus
    let color: Color
    var size: CGFloat = 26

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if status.isEaten {
                // Neutralne, nie w kolorze pory i nie zielone — patrz
                // `Color.scChecked`. Zieleń była zarazem kolorem obiadu.
                //
                // Wypełnienie ledwie zaznaczone, obwódka w połowie mocy,
                // ptaszek pełną mocą: pełny krążek w kolorze pisma świecił
                // w ciemnym motywie jak lampka, a zjedzony posiłek ma
                // przygasać, nie wołać.
                Circle().fill(Color.scChecked(scheme).opacity(0.12))

                Circle()
                    .strokeBorder(Color.scChecked(scheme).opacity(0.4), lineWidth: 1.5)

                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(Color.scChecked(scheme).opacity(0.85))
            } else {
                Circle()
                    .strokeBorder(
                        borderColor,
                        style: StrokeStyle(
                            lineWidth: 1.5,
                            dash: status == .anytime ? [3, 2.5] : []
                        )
                    )

                if status == .next {
                    Circle()
                        .fill(color)
                        .frame(width: size * 0.36, height: size * 0.36)
                }
            }
        }
        .frame(width: size, height: size)
        // Poświata tylko pod „następnym": to jedyny posiłek, w który
        // użytkownik ma teraz stuknąć, więc jako jedyny woła o uwagę.
        .background(
            Circle()
                .fill(color.opacity(status == .next ? 0.16 : 0))
                .padding(-3)
        )
        .animation(.smooth(duration: 0.22), value: status)
    }

    private var borderColor: Color {
        status == .next ? color : Color.scRule(scheme)
    }
}

// MARK: - Paleta pór dnia

extension MealSlot {
    /// Akcent „Cozy Kitchen" — jeden kolor na porę dnia.
    ///
    /// Sześć kolorów, nie trzy. Pory „pomiędzy" dziedziczyły wcześniej barwę
    /// po sąsiednim posiłku głównym — założenie było takie, że mniej ważny
    /// posiłek nie potrzebuje własnego koloru i odróżni go ikona. W dniu,
    /// w którym obiad i podwieczorek stoją dwa talerzyki od siebie w tej samej
    /// zieleni, to założenie po prostu nie działa: kolor przestaje cokolwiek
    /// znaczyć, skoro dwie różne pory noszą ten sam.
    ///
    /// Kolejność jest kolejnością doby — ciepłe rano, chłodny wieczór —
    /// a przekąska stoi z boku, bo jako jedyna nie ma swojej godziny.
    var cozyAccent: Color {
        switch self {
        case .breakfast:       return SCPalette.butter
        case .secondBreakfast: return SCPalette.rose
        case .lunch:           return SCPalette.sage
        case .afternoonSnack:  return SCPalette.teal
        case .dinner:          return SCPalette.indigo
        case .snack:           return SCPalette.lavender
        }
    }

    /// Tło talerza, gdy przepis nie ma zdjęcia.
    var cozyTint: Color { cozyAccent }
}

#Preview("Kółka stanu") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()

        HStack(spacing: 18) {
            CalendarMealCheck(status: .eaten, color: SCPalette.sage, size: 32)
            CalendarMealCheck(status: .next, color: SCPalette.indigo, size: 32)
            CalendarMealCheck(status: .later, color: SCPalette.butter, size: 32)
            CalendarMealCheck(status: .anytime, color: SCPalette.lavender, size: 32)
            CalendarMealCheck(status: .planned, color: SCPalette.rose, size: 32)
        }
        .padding(24)
    }
    .preferredColorScheme(.dark)
}
