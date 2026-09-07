import Foundation
import Observation

@Observable
class DatesViewModel {
    var selectedDate: Date = Date()
    var currentWeekOffset: Int = 0 // 0 = bieżący tydzień, -1 = poprzedni, +1 = następny

    var isCurrentWeek: Bool {
        currentWeekOffset == 0
    }
    
    /// Generuje tablicę dat dla wybranego tygodnia (Poniedziałek - Niedziela).
    /// Liczone przez `PlanWeek`, nie `Calendar.current` — region z niedzielą
    /// jako pierwszym dniem tygodnia pokazywał w niedzielę następny tydzień.
    var dates: [Date] {
        let calendar = PlanWeek.calendar
        guard let targetDate = calendar.date(byAdding: .weekOfYear, value: currentWeekOffset, to: Date()) else {
            return []
        }
        return PlanWeek.dates(from: PlanWeek.monday(of: targetDate))
    }

    /// `weekStart` w formacie backendowym `yyyy-MM-dd` (poniedziałek wybranego tygodnia)
    var weekStartISO: String {
        PlanWeek.dateKey(dates.first ?? PlanWeek.monday(of: Date()))
    }
    
    /// Sprawdza czy podana data to dzisiaj
    func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
    
    /// Sprawdza czy podana data jest wybrana
    func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }
    
    /// Formatuje datę na nazwę dnia (np. "PN", "WT")
    func dayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: "pl_PL")
        return formatter.string(from: date).uppercased()
    }
    
    /// Formatuje datę na numer dnia (np. "3", "14")
    func dayNumber(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    
    func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        formatter.locale = Locale(identifier: "pl_PL")
        return formatter.string(from: date).capitalized
    }
        
    /// Kotwica dnia dla tygodnia: ekrany trzymają własny wybrany dzień i
    /// zapisują go tutaj, żeby po zmianie tygodnia obie zakładki miały od
    /// czego zacząć.
    func selectDate(_ date: Date) {
        selectedDate = date
    }

    /// Zwraca `date`, jeśli mieści się w pokazywanym tygodniu — inaczej
    /// kotwicę tygodnia. Ekran wchodzący na zakładkę po zmianie tygodnia w
    /// innej nie może zostać z dniem spoza paska.
    func dayWithinVisibleWeek(_ date: Date) -> Date {
        let calendar = Calendar.current
        if dates.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
            return date
        }
        return selectedDate
    }
    
    /// Przechodzi do poprzedniego tygodnia
    func goToPreviousWeek() {
        currentWeekOffset -= 1
        shiftSelectedDate(byWeeks: -1)
    }
    
    /// Przechodzi do następnego tygodnia
    func goToNextWeek() {
        currentWeekOffset += 1
        shiftSelectedDate(byWeeks: 1)
    }
    
    /// Sprawdza czy data jest dzisiaj lub w przyszłości (można edytować)
    func isEditable(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.startOfDay(for: date) >= calendar.startOfDay(for: Date())
    }

    /// Dzień o jeden do przodu albo do tyłu — także przez granicę tygodnia.
    ///
    /// Zwraca nową datę, bo ekrany trzymają własny wybrany dzień; przekroczenie
    /// niedzieli przestawia przy okazji sam pasek na sąsiedni tydzień, więc gest
    /// „dalej" nie zatrzymuje się na końcu planszy. Kolejność ma znaczenie:
    /// `currentWeekOffset` idzie PRZED `selectedDate`, bo `dates` liczy się
    /// z offsetu i sprawdzenie „czy dzień jest jeszcze w tym tygodniu" musi
    /// patrzeć na planszę sprzed przesunięcia.
    @discardableResult
    func stepDay(from date: Date, by days: Int) -> Date {
        let calendar = PlanWeek.calendar
        guard days != 0,
              let next = calendar.date(byAdding: .day, value: days, to: date)
        else { return date }

        if !dates.contains(where: { calendar.isDate($0, inSameDayAs: next) }) {
            currentWeekOffset += days > 0 ? 1 : -1
        }
        selectedDate = next
        return next
    }

    /// Wraca do bieżącego tygodnia
    func goToCurrentWeek() {
        currentWeekOffset = 0
        selectedDate = Date()
    }

    private func shiftSelectedDate(byWeeks weeks: Int) {
        if let shifted = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: selectedDate) {
            selectedDate = shifted
        }
    }
}
