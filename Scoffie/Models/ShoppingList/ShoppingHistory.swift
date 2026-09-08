import Foundation

// Historia list zakupów — zamknięte listy poukładane w miesiące i tygodnie.
//
// Źródło układu: canvas claude.ai → „Weekly Meals - Zakupy v2.html”,
// sekcja „Zakupy v2 · Historia · Final” (`components/shop-v2-history-flow.jsx`).
//
// Serwer oddaje płaską listę archiwów (`ArchivedShoppingList`). Trzy poziomy —
// miesiąc → tydzień → lista — powstają tutaj, bo to jest wyłącznie sposób
// pokazania tych samych danych, a nie osobny stan do trzymania.

/// Jedna zamknięta lista, gotowa do pokazania w wierszu historii.
struct ShoppingHistoryEntry: Identifiable, Hashable {
    let archiveId: String
    let revision: Int
    let weekStart: String
    let closedAt: Date
    let bought: Int
    let total: Int

    var id: String { archiveId }

    /// „Lista 1”, „Lista 2” — numer rewizji w obrębie tygodnia.
    var name: String { "Lista \(revision)" }

    var isComplete: Bool { total > 0 && bought == total }

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(bought) / Double(total))
    }
}

/// Tydzień z jedną albo kilkoma zamkniętymi listami.
struct ShoppingHistoryWeek: Identifiable, Hashable {
    let weekStart: String
    let start: Date
    let end: Date
    /// Tydzień oglądany w tej chwili na Planie — dostaje terakotową kropkę
    /// na szynie i dopisek „ten tydzień”.
    let isCurrent: Bool
    /// Najnowsza rewizja na górze — historię czyta się od tego, co ostatnie.
    let entries: [ShoppingHistoryEntry]

    var id: String { weekStart }

    /// „7–13 wrz”, a przez przełom miesiąca „31 sie – 6 wrz”.
    var rangeLabel: String { ShoppingHistoryFormat.weekRange(start: start, end: end) }

    /// „7–13”, „31–6” — pod kropką na szynie tygodni.
    var shortLabel: String { ShoppingHistoryFormat.weekShort(start: start, end: end) }
}

/// Miesiąc historii.
struct ShoppingHistoryMonth: Identifiable, Hashable {
    let key: String
    let name: String
    let year: Int
    let isCurrent: Bool
    let weeks: [ShoppingHistoryWeek]

    var id: String { key }

    var entries: [ShoppingHistoryEntry] { weeks.flatMap(\.entries) }
    var listCount: Int { entries.count }
    var productCount: Int { entries.reduce(0) { $0 + $1.total } }
    var lastClosedAt: Date? { entries.map(\.closedAt).max() }
}

enum ShoppingHistory {
    /// Składa historię z archiwów.
    ///
    /// Miesiąc bierze się z DATY ZAMKNIĘCIA listy, nie z poniedziałku jej
    /// tygodnia. Tydzień potrafi leżeć w dwóch miesiącach naraz („31 sie –
    /// 6 wrz”) i wtedy podział po tygodniu jest zawsze do podważenia, a data
    /// zamknięcia jest jedną datą i to właśnie ona stoi w opisie wiersza
    /// („ostatnia sob. 6 wrz”).
    ///
    /// `counts` liczy pozycje jak `ShoppingListStore.archiveDisplayCounts`:
    /// druga rewizja tygodnia pokazuje tylko to, co dołożyła, więc suma
    /// produktów w miesiącu nie liczy tego samego jogurtu trzy razy.
    static func months(
        archives: [ArchivedShoppingList],
        counts: (String) -> (bought: Int, total: Int),
        currentWeekStart: String,
        now: Date = Date()
    ) -> [ShoppingHistoryMonth] {
        let calendar = PlanWeek.calendar

        let entries = archives.map { archive -> ShoppingHistoryEntry in
            let c = counts(archive.archiveId)
            return ShoppingHistoryEntry(
                archiveId: archive.archiveId,
                revision: archive.revision,
                weekStart: archive.weekStart,
                closedAt: archive.archivedAt,
                bought: c.bought,
                total: c.total
            )
        }

        let currentMonthKey = monthKey(for: now, calendar: calendar)

        return Dictionary(grouping: entries) { monthKey(for: $0.closedAt, calendar: calendar) }
            .map { key, monthEntries -> ShoppingHistoryMonth in
                let anchor = monthEntries.map(\.closedAt).max() ?? now

                let weeks = Dictionary(grouping: monthEntries, by: \.weekStart)
                    .map { weekStart, weekEntries -> ShoppingHistoryWeek in
                        let monday = PlanWeek.date(fromKey: weekStart) ?? weekEntries[0].closedAt
                        let dates = PlanWeek.dates(from: monday)
                        return ShoppingHistoryWeek(
                            weekStart: weekStart,
                            start: dates.first ?? monday,
                            end: dates.last ?? monday,
                            isCurrent: weekStart == currentWeekStart,
                            entries: weekEntries.sorted { $0.revision > $1.revision }
                        )
                    }
                    .sorted { $0.start > $1.start }

                return ShoppingHistoryMonth(
                    key: key,
                    name: ShoppingHistoryFormat.monthName(anchor),
                    year: calendar.component(.year, from: anchor),
                    isCurrent: key == currentMonthKey,
                    weeks: weeks
                )
            }
            .sorted { $0.key > $1.key }
    }

    /// `"2026-09"` — sortowalny leksykograficznie, więc porządek miesięcy
    /// wychodzi z samego klucza.
    private static func monthKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}

/// Etykiety historii. Wszystkie po polsku, wszystkie w jednym miejscu — te
/// same napisy stoją na trzech ekranach i rozjeżdżały się już przy dwóch
/// kopiach formatera.
enum ShoppingHistoryFormat {
    private static let plLocale = Locale(identifier: "pl_PL")

    // Każdy formater składa się we własnym domknięciu, zamiast wołać wspólną
    // fabrykę. Statyczna właściwość, której inicjalizator sięga do INNEJ
    // statycznej właściwości tego samego typu, jest w tym projekcie proszeniem
    // się o diagnostykę izolacji (`-default-isolation=MainActor`) — a oszczędza
    // cztery wiersze.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = PlanWeek.calendar
        f.locale = Locale(identifier: "pl_PL")
        f.timeZone = PlanWeek.calendar.timeZone
        f.dateFormat = "d"
        return f
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = PlanWeek.calendar
        f.locale = Locale(identifier: "pl_PL")
        f.timeZone = PlanWeek.calendar.timeZone
        f.dateFormat = "d MMM"
        return f
    }()

    private static let weekdayDayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = PlanWeek.calendar
        f.locale = Locale(identifier: "pl_PL")
        f.timeZone = PlanWeek.calendar.timeZone
        f.dateFormat = "EEE d MMM"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = PlanWeek.calendar
        f.locale = Locale(identifier: "pl_PL")
        f.timeZone = PlanWeek.calendar.timeZone
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = PlanWeek.calendar
        f.locale = Locale(identifier: "pl_PL")
        f.timeZone = PlanWeek.calendar.timeZone
        f.dateFormat = "LLLL"
        return f
    }()

    /// „7–13 wrz”, przez przełom miesiąca „31 sie – 6 wrz”.
    static func weekRange(start: Date, end: Date) -> String {
        if PlanWeek.calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(dayFormatter.string(from: start))–\(dayMonthFormatter.string(from: end))"
        }
        return "\(dayMonthFormatter.string(from: start)) – \(dayMonthFormatter.string(from: end))"
    }

    /// „7–13”, „31–6” — pod kropką na szynie jest miejsce na cztery znaki.
    static func weekShort(start: Date, end: Date) -> String {
        "\(dayFormatter.string(from: start))–\(dayFormatter.string(from: end))"
    }

    /// „dziś, 09:12”, „wczoraj, 18:40”, „sob. 6 wrz”.
    ///
    /// Godzina tylko przy dziś i wczoraj: przy liście sprzed trzech tygodni
    /// nikogo nie obchodzi, czy zamknęła się o 9:12, czy o 18:40 — obchodzi
    /// go, który to był dzień.
    static func closedAt(_ date: Date) -> String {
        let calendar = PlanWeek.calendar
        if calendar.isDateInToday(date) {
            return "dziś, \(timeFormatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            return "wczoraj, \(timeFormatter.string(from: date))"
        }
        return weekdayDayMonthFormatter.string(from: date)
    }

    /// „Wrzesień” — mianownik z wielkiej litery.
    static func monthName(_ date: Date) -> String {
        let raw = monthFormatter.string(from: date)
        guard let first = raw.first else { return raw }
        return String(first).uppercased(with: plLocale) + raw.dropFirst()
    }
}
