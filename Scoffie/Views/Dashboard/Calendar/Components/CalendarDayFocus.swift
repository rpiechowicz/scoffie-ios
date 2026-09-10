import SwiftUI

// Kalendarz v4 — środek łuku doby.
//
// Źródło: canvas claude.ai → „Weekly Meals - Kalendarz v4.html”,
// `components/cal-v4.jsx` (blok `center` w `C4Day`). Łuk niesie „gdzie
// w dobie jestem”, lista niesie „co jem”, a to jest trzecie pytanie: **co
// teraz**. Jedno zdanie na stan dnia, w dziurze po środku łuku, gdzie i tak
// nic nie stoi.
//
// Stan liczy ekran (`CalendarView.dayFocus`), a nie ten plik: „następny
// posiłek” zależy od całego dnia i od zegara, więc widok, który go rysuje,
// nie ma z czego go wywnioskować. Tutaj zostaje wyłącznie to, JAK się
// o tym mówi — i jednym tchem także to, jaką barwę ma wtedy kropka „teraz”
// na torze (`nowTint`), bo to jest ta sama informacja pokazana dwa razy.
enum CalendarDayFocus: Equatable {
    /// Dzień bez ani jednego zaplanowanego posiłku.
    case empty
    /// Dzień z przyszłości — jest tylko plan, nie ma czego odhaczać.
    case plan(meals: Int, kcal: Int, firstTime: String?)
    /// Wszystko odhaczone. `delta` = zjedzone minus cel dnia.
    case closed(kcal: Int, delta: Int)
    /// Jest co dalej: posiłek przed nami albo właśnie trwający.
    case next(NextMeal)
    /// Nic nie odhaczone i nic już nie nadchodzi.
    case untouched(planKcal: Int, meals: Int, isPast: Bool)
    /// Część dnia odhaczona, ale nic już nie nadchodzi.
    case partial(kcal: Int, eaten: Int, total: Int, planKcal: Int)

    /// Najbliższy nieodhaczony posiłek z godziną, razem z tym, czego lista
    /// pod łukiem nie niesie: ile trwa gotowanie i od której trzeba stanąć
    /// przy garnkach.
    struct NextMeal: Equatable {
        let slot: MealSlot
        /// Pora posiłku („14:00”) — jedyna godzina, którą pokazuje łuk.
        let time: String
        let kcal: Int
        /// Minuty do pory posiłku. Ujemne = pora już minęła.
        let minutesAway: Int
        /// Ile minut zajmuje przygotowanie. Zero = nie ma czego gotować
        /// (jogurt z lodówki), więc nie ma też o czym uprzedzać.
        let prepMinutes: Int
        /// Godzina, o której trzeba stanąć przy garnkach („13:00”) — pora
        /// posiłku minus czas przygotowania. `nil`, gdy `prepMinutes` to zero.
        let cookFrom: String?

        /// Najdalszy horyzont, na jaki uprzedzamy o gotowaniu.
        ///
        /// Pieczeń na cztery godziny zamieniłaby kropkę „teraz” w kolorową
        /// przez pół popołudnia — a wtedy kolor przestaje cokolwiek znaczyć.
        /// Dwie godziny to tyle, ile realnie zajmuje najdłuższe danie
        /// w katalogu, i tyle, ile człowiek jest w stanie planować „zaraz”.
        static let cookWindow = 120

        /// Najkrótsze przygotowanie, o którym w ogóle warto uprzedzać.
        ///
        /// „Pora gotować” pięć minut przed jogurtem z granolą to nie
        /// przypomnienie, tylko szum — i jeszcze stan, który mignie przez
        /// dwa tyknięcia zegara i zniknie. Ekran, który zmienia zdanie co
        /// minutę, przestaje się czytać.
        static let minPrepHint = 10

        /// Czy o tym daniu jest sens uprzedzać z wyprzedzeniem.
        var showsCookHint: Bool { prepMinutes >= Self.minPrepHint }

        /// Pora gotować: okno przygotowania już się otworzyło, a posiłek
        /// jeszcze przed nami.
        var isCooking: Bool {
            guard showsCookHint, minutesAway > 0 else { return false }
            return minutesAway <= min(prepMinutes, Self.cookWindow)
        }

        /// Pora jeść — godzina posiłku wypadła, z tą samą tolerancją, z jaką
        /// wiersz mówi „teraz”. Obiad o 14:00 zjedzony o 14:10 nie jest
        /// spóźniony, tylko zjedzony.
        var isDue: Bool {
            minutesAway <= 0 && minutesAway >= -CalendarRelativeTime.graceMinutes
        }

        /// Pora minęła na dobre i nikt nie odhaczył.
        var isLate: Bool { minutesAway < -CalendarRelativeTime.graceMinutes }
    }

    /// Barwa kropki „teraz” na torze doby.
    ///
    /// Terakota znaczy „jesteś tutaj” i tyle — dopóki nic nie wisi
    /// w powietrzu. Kiedy zaczyna się okno gotowania albo wypada pora
    /// posiłku, kropka przejmuje KOLOR TEJ PORY: ta sama barwa stoi wtedy
    /// w obwódce węzła nad nią, w kółku wiersza na liście i w nadpisie
    /// w środku łuku. Cztery miejsca, jeden kolor, jedna rzecz do zrobienia.
    var nowTint: Color {
        guard case .next(let meal) = self else { return SCPalette.terracotta }
        return (meal.isCooking || meal.isDue) ? meal.slot.cozyAccent : SCPalette.terracotta
    }

    /// Czy kropka „teraz” ma oddychać. Tylko wtedy, gdy jest co zrobić —
    /// pulsująca kropka bez powodu to migająca dioda, a nie informacja.
    var isUrgent: Bool {
        guard case .next(let meal) = self else { return false }
        return meal.isCooking || meal.isDue
    }
}

// MARK: - Środek łuku

/// Trzy wiersze w dziurze po środku łuku: nadpis, liczba, dopisek.
///
/// Wszystkie trzy mają twardy sufit szerokości (`maxWidth` podaje łuk,
/// domyślnie ~0,62 jego średnicy) i zjeżdżają skalą, zamiast się łamać.
/// Wiersz przełamany w kole wygląda jak usterka rysowania, a najdłuższe
/// zdania tego ekranu („NIC NIE ODHACZONO”, „za 4 h 19 min”) są znane
/// z góry — nie ma czego zgadywać.
struct CalendarArcCenter: View {
    let focus: CalendarDayFocus
    /// Skala pisma względem projektowych 232 pt planszy. Łuk zjeżdża
    /// wielkością na krótkich ekranach, więc pismo w środku też musi.
    var scale: CGFloat = 1

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 2 * scale) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.system(size: 10 * scale, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(eyebrowColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.opacity)
            }

            Text(headline)
                .font(.system(size: 19 * scale, weight: .bold))
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundStyle(headlineColor)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                // Odliczanie tyka co minutę. Bez tego liczby podmieniałyby
                // się skokiem w samym środku ekranu, na który patrzy się
                // najdłużej.
                .contentTransition(.numericText())

            Text(caption)
                .font(.system(size: 11 * scale, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(captionColor)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .animation(.smooth(duration: 0.28), value: focus)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Treść

    private var eyebrow: String? {
        switch focus {
        case .empty:
            // Bez nadpisu: „PUSTY DZIEŃ” nad „Pusty dzień” to ta sama rzecz
            // powiedziana dwa razy, a w kole 140 pt szerokości nie ma na to
            // miejsca ani powodu.
            return nil
        case .plan:
            return "PLAN"
        case .closed:
            return "DZIEŃ DOMKNIĘTY"
        case .next(let meal):
            // Pora dnia i godzina razem, w każdym stanie tak samo — żeby
            // przejście z odliczania w „Pora gotować" zmieniało JEDNĄ linijkę,
            // a nie przemeblowywało całego środka.
            return "\(meal.slot.title.uppercased()) · \(meal.time)"
        case .untouched(_, _, let isPast):
            return isPast ? "NIC NIE ODHACZONO" : "W PLANIE"
        case .partial:
            return "ZJEDZONE"
        }
    }

    private var headline: String {
        switch focus {
        case .empty:
            return "Pusty dzień"
        case .plan(let meals, _, _):
            return PolishPlural.meals(meals)
        case .closed(let kcal, _):
            return "\(kcal) kcal"
        case .next(let meal):
            // Odkąd okno gotowania jest otwarte, odliczanie przestaje być
            // odpowiedzią: „za 3 min" przy daniu, które robi się kwadrans,
            // mówi, ile zostało do JEDZENIA, a pytanie brzmi już co innego.
            if meal.isCooking { return "Pora gotować" }
            if meal.isDue { return "Pora jeść" }
            if meal.isLate { return "Pora minęła" }
            return CalendarRelativeTime.text(inMinutes: meal.minutesAway)
        case .untouched(let planKcal, _, _):
            return "\(planKcal) kcal"
        case .partial(let kcal, _, _, _):
            return "\(kcal) kcal"
        }
    }

    private var caption: String {
        switch focus {
        case .empty:
            return "Nic nie zaplanowano"
        case .plan(_, let kcal, let firstTime):
            guard let firstTime else { return "\(kcal) kcal" }
            return "\(kcal) kcal · od \(firstTime)"
        case .closed(_, let delta):
            if delta > 0 { return "+\(delta) nad celem" }
            if delta < 0 { return "\(-delta) pod celem" }
            return "Równo z celem"
        case .next(let meal):
            // Ile danie waży, a przy okazji — dopóki gotowanie jest jeszcze
            // przed nami — od której trzeba stanąć przy garnkach. Samo „od",
            // bez czasownika: godzina po kaloriach nie może znaczyć nic
            // innego, a każde dołożone słowo zjada linijkę w kole.
            if meal.isCooking {
                return "\(meal.kcal) kcal · \(meal.prepMinutes) min"
            }
            if meal.isDue || meal.isLate {
                return "\(meal.kcal) kcal"
            }
            if meal.showsCookHint, let cookFrom = meal.cookFrom {
                return "\(meal.kcal) kcal · od \(cookFrom)"
            }
            return "\(meal.kcal) kcal"
        case .untouched(_, let meals, _):
            return "\(PolishPlural.meals(meals)) w planie"
        case .partial(_, let eaten, let total, let planKcal):
            return "\(eaten) z \(total) · plan \(planKcal) kcal"
        }
    }

    // MARK: Barwy

    private var eyebrowColor: Color {
        switch focus {
        case .closed, .partial:
            // Szałwia znaczy tu to samo, co kropki w plakietce dnia nad
            // łukiem: zrobione. Nie sąsiaduje z żadnym kolorem pory, więc
            // nie ma czego mylić — inaczej niż ptaszek w wierszu, który
            // musi być neutralny (patrz `Color.scChecked`).
            return SCPalette.sage
        case .next(let meal):
            return meal.isLate ? Color.scMuted(scheme) : meal.slot.cozyAccent
        case .plan, .untouched, .empty:
            return Color.scMuted(scheme)
        }
    }

    private var headlineColor: Color {
        switch focus {
        case .untouched:
            // Kalorie, których nikt nie zjadł, są przygaszone — to plan,
            // a nie wynik.
            return Color.scMuted(scheme)
        default:
            return Color.scLabel(scheme)
        }
    }

    private var captionColor: Color {
        if case .closed(_, let delta) = focus, delta <= 0 {
            return SCPalette.sage
        }
        return Color.scFaint(scheme)
    }

    /// Jedno zdanie dla VoiceOver — trzy osobne wiersze czytane po kolei
    /// („PLAN”, „3 posiłki”, „1460 kcal od 08:00”) brzmią jak lista, a to
    /// jest jedna informacja.
    private var accessibilityText: String {
        [eyebrow?.lowercased(), headline, caption]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

#Preview("Środek łuku — stany") {
    let meal = CalendarDayFocus.NextMeal(
        slot: .lunch,
        time: "14:00",
        kcal: 604,
        minutesAway: 259,
        prepMinutes: 60,
        cookFrom: "13:00"
    )
    let cooking = CalendarDayFocus.NextMeal(
        slot: .lunch,
        time: "14:00",
        kcal: 604,
        minutesAway: 45,
        prepMinutes: 60,
        cookFrom: "13:00"
    )
    let due = CalendarDayFocus.NextMeal(
        slot: .dinner,
        time: "20:00",
        kcal: 480,
        minutesAway: -5,
        prepMinutes: 35,
        cookFrom: "19:25"
    )
    let late = CalendarDayFocus.NextMeal(
        slot: .breakfast,
        time: "08:00",
        kcal: 393,
        minutesAway: -180,
        prepMinutes: 12,
        cookFrom: "07:48"
    )

    let states: [CalendarDayFocus] = [
        .next(meal),
        .next(cooking),
        .next(due),
        .next(late),
        .closed(kcal: 2903, delta: 603),
        .closed(kcal: 1890, delta: -410),
        .partial(kcal: 1665, eaten: 2, total: 4, planKcal: 2903),
        .untouched(planKcal: 1135, meals: 3, isPast: true),
        .plan(meals: 3, kcal: 1460, firstTime: "08:00"),
        .empty
    ]

    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()

        ScrollView {
            VStack(spacing: 18) {
                ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                    CalendarArcCenter(focus: state)
                        .frame(width: 144, height: 74)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.scRule(.dark), lineWidth: 1)
                        )
                }
            }
            .padding(24)
        }
    }
    .preferredColorScheme(.dark)
}
