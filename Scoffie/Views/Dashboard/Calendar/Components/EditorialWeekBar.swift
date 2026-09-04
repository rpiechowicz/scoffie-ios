import SwiftUI

// Editorial week strip used on the Cozy Kitchen Kalendarz v2.
// Past days = strikethrough numbers, today = bold + accent underline,
// planned = sage dot. Tap to select.
//
// Animations:
// - Terracotta selected-day underline slides between cells via matched geometry.
// - Sage planned dots fade/scale in & out when a day's planned status changes.
struct EditorialWeekBar: View {
    let datesViewModel: DatesViewModel
    // Wybrany dzień jest stanem ekranu, który pokazuje pasek — nie
    // `DatesViewModel`. Plan i Kalendarz dzielą tydzień, ale każdy trzyma
    // własny dzień, więc przestawienie dnia w jednej zakładce nie przestawia
    // go w drugiej.
    @Binding var selectedDate: Date
    let plannedDates: Set<String>   // "yyyy-MM-dd" keys for days that already have ≥1 meal
    @Environment(\.colorScheme) private var scheme
    @Namespace private var indicatorNS

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "EE"
        return f
    }()

    var body: some View {
        HStack(spacing: 0) {
            ForEach(datesViewModel.dates, id: \.self) { date in
                DayCell(
                    date: date,
                    isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                    isToday: datesViewModel.isToday(date),
                    isPast: !datesViewModel.isEditable(date) && !datesViewModel.isToday(date),
                    isPlanned: plannedDates.contains(PlanWeek.dateKey(date)),
                    indicatorNS: indicatorNS
                )
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        selectedDate = date
                    }
                }
            }
        }
    }

    private struct DayCell: View {
        let date: Date
        let isSelected: Bool
        let isToday: Bool
        let isPast: Bool
        let isPlanned: Bool
        let indicatorNS: Namespace.ID

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            let label = Color.scLabel(scheme)
            let muted = Color.scMuted(scheme)
            let strike = Color.scStrike(scheme)
            let accent = SCPalette.terracotta

            VStack(spacing: 4) {
                Text(EditorialWeekBar.shortDayFormatter.string(from: date).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(isSelected ? label : muted)
                    // Jak niżej przy numerze dnia — bez tego kolor skrótu
                    // przeskakiwał zamiast płynnie przejść razem ze sprężyną.
                    .contentTransition(.interpolate)

                Text(dayNumber)
                    .font(.system(size: 18, weight: isSelected ? .heavy : .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(isPast ? muted : label)
                    .strikethrough(isPast, color: strike)
                    // Grubość fontu nie jest animowalna „za darmo": w sprężynie
                    // zaznaczenia tekst czekał do końca animacji i dopiero wtedy
                    // przeskakiwał semibold → heavy. `.interpolate` prowadzi wagę
                    // płynnie razem z suwającym się podkreśleniem.
                    .contentTransition(.interpolate)

                ZStack {
                    // Reserve the slot height so layout doesn't shift while
                    // the indicators animate in/out.
                    Color.clear.frame(height: 2)

                    // Sage planned dot — fades/scales in/out when the planned
                    // state of a day changes.
                    if isPlanned && !isSelected {
                        Capsule()
                            .fill(SCPalette.sage)
                            .frame(width: 10, height: 2)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Terracotta selected-day underline — slides between cells
                    // because all DayCells share the same indicator namespace.
                    if isSelected {
                        Capsule()
                            .fill(accent)
                            .frame(width: 18, height: 2)
                            .matchedGeometryEffect(id: "weekbar.indicator", in: indicatorNS)
                    }
                }
                .frame(height: 4)
                .padding(.top, 4)
            }
            .padding(.bottom, 8)
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        private var dayNumber: String {
            let f = DateFormatter()
            f.dateFormat = "d"
            return f.string(from: date)
        }

        private var accessibilityLabel: String {
            let weekday = DateFormatter.localizedString(from: date, dateStyle: .full, timeStyle: .none)
            if isToday { return "\(weekday), dziś" }
            if isPast { return "\(weekday), przeszłość" }
            if isPlanned { return "\(weekday), zaplanowany" }
            return weekday
        }
    }
}
