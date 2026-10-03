import Foundation

/// Pora, pod którą „Zjedzone” wpisuje danie ugotowane spoza planu (D21).
///
/// Serwer nie zna strefy czasowej ani domyślnych godzin aplikacji, więc porę
/// wybiera telefon: z pór, które dom ma włączone, te pasujące do przepisu;
/// spośród nich ta, której godzina jest najbliżej chwili „Zjedzone” (remis —
/// wcześniejsza). Przepis bez pasującej włączonej pory ląduje w najbliższej
/// włączonej — inaczej wpis stałby w wierszu, którego Kalendarz nie pokazuje.
/// Pora bez godziny (przekąska) wygrywa tylko wtedy, gdy nie ma innej.
enum CookPlanEntry {
    static func slot(
        minuteOfDay: Int,
        enabled: [MealSlot],
        recipeSlots: [MealSlot],
        schedule: MealSlotSchedule
    ) -> MealSlot {
        let fitting = enabled.filter(recipeSlots.contains)
        let candidates = !fitting.isEmpty ? fitting : (!enabled.isEmpty ? enabled : recipeSlots)
        let timed = candidates.sortedByDay.compactMap { slot in
            schedule.minutes(for: slot).map { (slot: slot, distance: abs($0 - minuteOfDay)) }
        }
        // `min(by:)` oddaje pierwszy z równych — przy remisie wcześniejsza pora.
        if let nearest = timed.min(by: { $0.distance < $1.distance }) {
            return nearest.slot
        }
        return candidates.sortedByDay.first ?? .dinner
    }
}
