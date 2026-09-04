import Foundation

/// Tydzień planu to zawsze siatka poniedziałek–niedziela w strefie telefonu,
/// a `weekStart` (`yyyy-MM-dd` poniedziałku) jest kluczem tygodnia w backendzie.
/// Liczenie tego w kilku miejscach z `Calendar.current` rozjeżdżało się z
/// ustawieniami regionu: przy niedzieli jako pierwszym dniu tygodnia Plan
/// pokazywał w niedzielę następny tydzień, a „Dodaj do planu" pisał do
/// bieżącego. Wszystko, co dotyczy klucza tygodnia, liczy się tutaj.
enum PlanWeek {
    /// Gregoriański, poniedziałek pierwszym dniem, niezależnie od locale.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        calendar.timeZone = .current
        return calendar
    }()

    /// Północ poniedziałku tygodnia, w którym leży `date`.
    static func monday(of date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    /// Siedem dni od poniedziałku — arytmetyka kalendarzowa, nie 86 400 s,
    /// żeby zmiana czasu w marcu i październiku nie przesuwała dnia.
    static func dates(from monday: Date) -> [Date] {
        (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: monday)
        }
    }

    /// Klucz dnia/tygodnia w formacie backendu (`yyyy-MM-dd`, strefa telefonu).
    static func dateKey(_ date: Date) -> String {
        keyFormatter.string(from: date)
    }

    /// Odwrotność `dateKey` — północ danego dnia w strefie telefonu.
    static func date(fromKey key: String) -> Date? {
        keyFormatter.date(from: key)
    }

    private static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
