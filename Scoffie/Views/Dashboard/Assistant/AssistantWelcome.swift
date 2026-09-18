import SwiftUI

/// Powitanie na pustej rozmowie — złożone z tego, co aplikacja WIE,
/// zamiast jednego zdania dla wszystkich.
///
/// „Co dziś planujemy?" było prawdziwe zawsze i przez to nic nie mówiło.
/// Telefon zna godzinę, dzień tygodnia, imię i plan: czy dziś jest co jeść,
/// czy jutro, czy tydzień w ogóle istnieje. Z tych czterech rzeczy da się
/// złożyć zdanie, które brzmi jak od kogoś, kto zajrzał do kalendarza,
/// zanim się odezwał — i podpowiedzi, które pasują do tej chwili, a nie
/// trzy te same co zawsze.
///
/// Czysta funkcja stanu: wszystko przychodzi parametrami, więc da się ją
/// przeczytać w całości bez uruchamiania i przewidzieć każde zdanie.
struct AssistantWelcome: Equatable {
    let title: String
    let subtitle: String
    let quickStarts: [String]

    struct Context {
        var now: Date
        var calendar: Calendar = .current
        /// Imię z profilu; `nil` albo puste = powitanie bez imienia.
        var displayName: String?
        var plannedToday: Int
        var plannedTomorrow: Int
        /// Dni z choć jednym posiłkiem w bieżącym tygodniu (pon–niedz).
        var plannedDaysThisWeek: Int
        var plannedDaysNextWeek: Int
        /// Pula na próbę wykorzystana: powitanie nie ma prawa obiecywać
        /// „ułożę w minutę" nad polem, w które nie da się nic wpisać.
        var trialExhausted: Bool = false
    }

    static func compose(_ c: Context) -> AssistantWelcome {
        let hour = c.calendar.component(.hour, from: c.now)
        // 1 = niedziela w `Calendar.current` z gregoriańskim kalendarzem.
        let weekday = c.calendar.component(.weekday, from: c.now)
        let isWeekendEve = weekday == 6 || weekday == 7 || weekday == 1

        let greeting: String
        switch hour {
        case 5..<11: greeting = "Dzień dobry"
        case 11..<17: greeting = "Cześć"
        case 17..<22: greeting = "Dobry wieczór"
        default: greeting = "Późna pora"
        }
        let name = firstName(c.displayName)
        // Wołacz jest dla imion nie do przewidzenia (Kuba → Kubo, Ania →
        // Aniu, ale Rafał → Rafale, Beata → Beato) — mianownik po przecinku
        // czyta się naturalnie i nigdy nie wychodzi z niego potworek.
        let title = name.map { "\(greeting), \($0)" } ?? greeting

        if c.trialExhausted {
            // Zero podpowiedzi: chip, którego nie da się wysłać, jest gorszy
            // niż brak chipa. Zdanie mówi, co ZOSTAJE, zanim powie, co kupić.
            return AssistantWelcome(
                title: title,
                subtitle: "Darmowe wiadomości są wykorzystane. Rozmowy i plan zostają — z planem Scoffie zaczniemy dokładnie tam, gdzie skończyliśmy.",
                quickStarts: []
            )
        }

        // Kolejność = waga sprawy: pusty tydzień bije pusty obiad, a pusty
        // obiad bije jutro. Ostatnia gałąź to „wszystko jest" i wtedy
        // podpowiedzi są o poprawkach, nie o planowaniu od zera.
        if c.plannedDaysThisWeek == 0 {
            return AssistantWelcome(
                title: title,
                subtitle: "Ten tydzień jest jeszcze pusty. Ułożę go w minutę — powiedz tylko, na co masz ochotę.",
                quickStarts: [
                    "Zaplanuj mi obiady i kolacje na ten tydzień",
                    "Ułóż dzisiejszy dzień pod mój cel",
                    "Daj mi trzy szybkie kolacje do wyboru",
                ]
            )
        }
        if c.plannedToday == 0 && hour < 20 {
            return AssistantWelcome(
                title: title,
                subtitle: "Na dziś nic nie ma w planie. Coś szybkiego na obiad, czy od razu cały dzień?",
                quickStarts: [
                    "Co zjeść dziś na obiad?",
                    "Ułóż mi dzisiejszy dzień",
                    "Daj mi trzy szybkie kolacje do wyboru",
                ]
            )
        }
        if c.plannedTomorrow == 0 && hour >= 17 {
            return AssistantWelcome(
                title: title,
                subtitle: "Jutro w planie pusto. Ułożę je teraz, żeby rano było wiadomo, co gotować.",
                quickStarts: [
                    "Ułóż mi jutrzejszy dzień",
                    "Co na jutrzejsze śniadanie?",
                    "Co muszę dokupić na jutro?",
                ]
            )
        }
        if isWeekendEve && c.plannedDaysNextWeek == 0 {
            return AssistantWelcome(
                title: title,
                subtitle: "Przyszły tydzień jeszcze bez planu. Ułożyć go teraz, żeby zakupy zrobić za jednym razem?",
                quickStarts: [
                    "Zaplanuj mi przyszły tydzień",
                    "Co muszę kupić na przyszły tydzień?",
                    "Daj mi trzy pomysły na weekendowy obiad",
                ]
            )
        }
        return AssistantWelcome(
            title: title,
            subtitle: "Plan na dziś jest. Mogę coś podmienić, policzyć zakupy albo sprawdzić, jak wychodzi bilans.",
            quickStarts: [
                "Podmień dzisiejszą kolację na coś szybszego",
                "Co muszę kupić na ten tydzień?",
                "Jak wychodzi mój bilans w tym tygodniu?",
            ]
        )
    }

    /// Pierwsze słowo z profilu — „Rafał Piechowicz" wita się jak „Rafał".
    ///
    /// Login nie jest imieniem: konto z Apple bez podanego imienia ma w profilu
    /// zastępczy identyfikator („rpiechowicz"), a „Dobry wieczór, rpiechowicz"
    /// brzmi jak formularz, nie jak powitanie. Imię zaczyna się wielką literą
    /// i nie ma w sobie cyfr ani „@" — wszystko inne dostaje powitanie bez
    /// imienia, co jest lepsze niż złe imię.
    static func firstName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let first = raw.split(separator: " ").first.map(String.init) ?? ""
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let initial = trimmed.first, initial.isUppercase else { return nil }
        guard !trimmed.contains("@"), !trimmed.contains(where: { $0.isNumber }) else { return nil }
        return trimmed
    }
}
