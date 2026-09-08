import SwiftUI

// Kalendarz v2 — nagłówek dnia nad listą posiłków.
//
// Źródło: canvas claude.ai → „Weekly Meals - Kalendarz v2 D6.html”
// (`P2DayHeader` z podpisem „1 z 4 zjedzone”). Nazwa dnia po lewej, stan dnia
// po prawej — jeden wiersz, ten sam rytm co nagłówek dnia w Planie tygodnia.
//
// Wchodzi w miejsce kreski „W MENU”. Kreska mówiła tylko „niżej są posiłki”,
// co widać i bez niej; ten wiersz w tym samym miejscu mówi, KTÓRY to dzień
// i ile z niego zostało do zjedzenia.
//
// Stan dnia idzie plakietką z kropkami (`SCPipsBadge`), a nie zdaniem:
// „1 z 4” trzeba przeczytać i porównać dwie liczby, a jedną pełną kropkę
// z czterech widać kątem oka — dokładnie tak, jak pulę wiadomości
// w nagłówku asystenta.
struct CalendarDayHeader: View {
    let date: Date
    let isToday: Bool
    /// Posiłki odhaczone przez zalogowanego użytkownika.
    let eaten: Int
    /// Wszystkie posiłki dnia. Zero = nie ma czego liczyć i plakietki nie ma.
    let total: Int

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.longDayFormatter.string(from: date).capitalized)
                .scFont(22, weight: .bold, relativeTo: .title2)
                .tracking(-0.5)
                .foregroundStyle(Color.scLabel(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                // Nazwa dnia ma pierwszeństwo przy dzieleniu wiersza —
                // „Poniedziałek” nie skraca się pod plakietkę.
                .layoutPriority(1)

            if isToday { todayBadge }

            Spacer(minLength: 10)

            if total > 0 {
                SCPipsBadge(
                    filled: eaten,
                    total: total,
                    color: SCPalette.sage,
                    label: "\(eaten) z \(total)",
                    // Mała, bo to komentarz do tytułu dnia, a nie drugi
                    // tytuł: przy 28 pt plakietka ważyła w wierszu tyle,
                    // co „Poniedziałek" obok niej.
                    size: .small
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Zjedzone \(eaten) z \(total) posiłków")
            }
        }
        // Odhaczenie posiłku zapala kropkę tym samym ruchem, którym zmienia
        // się wiersz niżej. Odcisk obejmuje też pulę, więc dołożenie posiłku
        // dorysowuje kropkę zamiast podmienić plakietkę między klatkami.
        .animation(.smooth(duration: 0.22), value: "\(eaten)/\(total)")
    }

    private var todayBadge: some View {
        Text("DZIŚ")
            .scFont(10.5, weight: .bold, relativeTo: .caption2)
            .tracking(0.6)
            .foregroundStyle(SCPalette.terracotta)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.16 : 0.14))
            )
            .fixedSize()
    }

    private static let longDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}

#Preview("Nagłówek dnia") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()

        VStack(alignment: .leading, spacing: 24) {
            CalendarDayHeader(date: Date(), isToday: true, eaten: 1, total: 4)
            CalendarDayHeader(date: Date(), isToday: false, eaten: 3, total: 3)
            CalendarDayHeader(date: Date(), isToday: false, eaten: 0, total: 0)
        }
        .padding(.horizontal, SCPageMetrics.horizontal)
    }
    .preferredColorScheme(.dark)
}
