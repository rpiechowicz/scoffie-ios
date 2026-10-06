import SwiftUI

/// Nagłówek zakładki „Dziś” (6.10.2026 — Plan i Kalendarz z wyostrzonymi
/// rolami: Plan to „co jemy w domu”, ta zakładka to „mój dzień”).
///
/// Duży tytuł w miejscu i stroju `EditorialPageHeader` innych zakładek —
/// „Dziś”, a przy oglądaniu sąsiedniego dnia „Wczoraj” albo „Jutro” — pod nim
/// data słowami („wtorek, 6 października”), obok strzałki o jeden dzień i,
/// poza dziś, powrót do dziś (krążek w terakocie jak `SCWeekTodayButton`,
/// tylko w rozmiarze akcji nagłówka).
///
/// Zakres to wyłącznie wczoraj · dziś · jutro: przeglądanie dalszych dni to
/// rola Planu, więc strzałka na krawędzi gaśnie, a pasek tygodnia
/// (`EditorialWeekBar`) z tej zakładki zszedł — wraz z nim osobny tydzień
/// Kalendarza z 4.10.2026.
///
/// Tytuł i data ROLUJĄ się przy zmianie dnia (`numericText`,
/// `SCMotion.textRoll`): strona pod spodem przekłada się w nowy dzień
/// w miejscu (`DayPagerMotion.morph`), więc nagłówek też nie przeskakuje.
struct CalendarTodayHeader: View {
    /// Oglądany dzień.
    let date: Date
    /// Dziś — od niego liczą się „Wczoraj” i „Jutro”.
    let today: Date
    let canGoBack: Bool
    let canGoForward: Bool
    /// Dzień w tył (−1) albo w przód (+1).
    let onStep: (Int) -> Void
    let onToday: () -> Void

    @Environment(\.colorScheme) private var scheme

    /// Akcje nagłówka w rozmiarze akcji nagłówka Planu (34 pt, cel dotyku 44).
    private static let actionSize: CGFloat = 34

    /// Odległość oglądanego dnia od dziś, w dniach kalendarza.
    private var dayOffset: Int {
        let calendar = PlanWeek.calendar
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: today),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
    }

    private var title: String {
        switch dayOffset {
        case 0: return "Dziś"
        case -1: return "Wczoraj"
        case 1: return "Jutro"
        // Poza zakresem tej zakładki nie bywa — gdyby jednak, nazwa dnia
        // jest prawdą, a „Dziś” nie.
        default: return Self.weekdayFormatter.string(from: date).capitalized
        }
    }

    /// „wtorek, 6 października” — miesiąc w dopełniaczu (`d MMMM`).
    private var dateLine: String {
        Self.dateFormatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            EditorialPageHeader(title: title) {
                actions
            }
            // Tytuł przechodzi w nowy literami („Dziś” → „Jutro”), tą samą
            // krzywą co każdy tekst w aplikacji.
            .contentTransition(.numericText())
            .animation(SCMotion.textRoll, value: title)

            Text(dateLine)
                .scFont(15, weight: .semibold, relativeTo: .subheadline)
                .foregroundStyle(Color.scMuted(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentTransition(.numericText())
                .animation(SCMotion.textRoll, value: dateLine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Powrót do dziś (tylko poza dziś) i strzałki o jeden dzień. Szkło
    /// krążków w jednej grupie — powrót wyrasta obok strzałek, zamiast
    /// wskakiwać.
    private var actions: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                if dayOffset != 0 {
                    EditorialIconButton(
                        icon: "arrow.uturn.backward",
                        highlighted: true,
                        size: Self.actionSize,
                        accessibilityTitle: "Wróć do dziś",
                        tapTarget: 44,
                        action: onToday
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }

                stepButton(
                    icon: "chevron.left",
                    label: dayOffset == 1 ? "Dziś" : "Wczoraj",
                    isEnabled: canGoBack
                ) {
                    onStep(-1)
                }

                stepButton(
                    icon: "chevron.right",
                    label: dayOffset == -1 ? "Dziś" : "Jutro",
                    isEnabled: canGoForward
                ) {
                    onStep(1)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: dayOffset == 0)
    }

    /// Strzałka o jeden dzień. Na krawędzi zakresu gaśnie — dalej jest już
    /// Plan, nie ta zakładka.
    private func stepButton(
        icon: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        EditorialIconButton(
            icon: icon,
            size: Self.actionSize,
            accessibilityTitle: label,
            tapTarget: 44,
            action: action
        )
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .animation(.smooth(duration: 0.2), value: isEnabled)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.calendar = PlanWeek.calendar
        formatter.timeZone = PlanWeek.calendar.timeZone
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.calendar = PlanWeek.calendar
        formatter.timeZone = PlanWeek.calendar.timeZone
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}

#Preview("Nagłówek „Dziś”") {
    let today = Date()
    let tomorrow = PlanWeek.calendar.date(byAdding: .day, value: 1, to: today) ?? today

    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()

        VStack(alignment: .leading, spacing: 32) {
            CalendarTodayHeader(
                date: today, today: today,
                canGoBack: true, canGoForward: true,
                onStep: { _ in }, onToday: {}
            )
            CalendarTodayHeader(
                date: tomorrow, today: today,
                canGoBack: true, canGoForward: false,
                onStep: { _ in }, onToday: {}
            )
        }
        .padding(.horizontal, SCPageMetrics.horizontal)
    }
    .preferredColorScheme(.dark)
}
