import Foundation

/// Dzień planu policzony raz: co stoi w slotach, ile z tego wychodzi na jedną
/// osobę i ile zostaje do celu.
///
/// Jedno źródło dla pigułki nad dolnym menu (`PlanDayGoalBar`) i dla arkusza
/// „Cel dnia" (`PlanDayGoalSheet`). Oba pokazują TE SAME liczby, więc nie mogą
/// ich liczyć osobno — pigułka mówiąca „965 kcal zostało" i arkusz otwarty
/// z tej samej pigułki z inną liczbą w środku to najgorszy możliwy wynik.
///
/// Liczby są udziałem JEDNEJ osoby, nie sumą tego, co stoi na stole — tak samo
/// jak w wierszach osi dnia (`PlanDayTimeline`). Dzienny cel jest
/// osobisty, więc porównywać się z nim może wyłącznie osobisty talerz.
struct PlanDayNutrition {
    /// Jeden wiersz listy „W posiłkach": danie albo pusta pora.
    struct Entry: Identifiable {
        let slot: MealSlot
        /// `nil` = pora bez posiłku.
        let meal: PlanMeal?
        /// Makra na jedną osobę; `.zero` dla pustej pory.
        let nutrition: Nutrition
        /// Czy posiłek jest odhaczony jako zjedzony. Zawsze `false` tam, gdzie
        /// odhaczanie nie ma sensu (Plan tygodnia planuje, a nie liczy zjedzone).
        let isEaten: Bool
        let id: String

        var isPlanned: Bool { meal != nil }
    }

    let entries: [Entry]
    /// Suma dnia na jedną osobę.
    let total: Nutrition
    /// Ile pór ma już posiłek i ile ich w ogóle jest — „3 z 3 posiłków".
    /// W Kalendarzu licznik po lewej mówi o porach ZJEDZONYCH.
    let filledSlots: Int
    let slotCount: Int
    /// Czy `total` liczy wyłącznie odhaczone posiłki (Kalendarz), czy
    /// wszystko, co stoi w planie (Plan tygodnia).
    ///
    /// Widok czyta stąd, jak opisać dzień: przy `true` niezjedzone dania
    /// nadal są na liście — bo dzień je ma — ale nie wchodzą do sumy i muszą
    /// to po sobie pokazać. Lista bez nich odpowiadałaby na pytanie „co
    /// zjadłem" pustką, zamiast powiedzieć „to jeszcze przed tobą".
    let countsOnlyEaten: Bool

    var kcal: Int { Int(total.kcal.rounded()) }
    var protein: Int { Int(total.protein.rounded()) }
    var fat: Int { Int(total.fat.rounded()) }
    var carbs: Int { Int(total.carbs.rounded()) }

    /// Nic w całym dniu — pigułka i arkusz mówią wtedy o celu, a nie o postępie.
    var isEmpty: Bool { filledSlots == 0 }

    /// Suma leci w `Double`, bo obcinanie każdego posiłku z osobna kumulowało
    /// błąd przez cały dzień.
    ///
    /// - Parameters:
    ///   - slots: pory do pokazania, w kolejności dnia — ta sama lista, którą
    ///     rysuje oś (`visibleSlots(on:)`), żeby „3 z 3" znaczyło to samo
    ///     w nagłówku dnia i w arkuszu.
    ///   - meals: warianty posiłku w porze, już zawężone do JEDNEJ osoby
    ///     (`visibleTo(memberId:)`) — suma dnia jest udziałem jednego talerza.
    ///   - knownHouseholdMemberCount: `nil`, dopóki `SessionStore` nie dowiezie
    ///     składu gospodarstwa — wtedy udziałem jednej osoby jest pełna porcja
    ///     przepisu, czyli ta sama liczba, którą reguła auto pokaże po
    ///     wczytaniu listy. Ekran nie miga.
    ///   - isEaten: `nil` w Planie tygodnia — liczy się wszystko, co stoi
    ///     w dniu. Kalendarz podaje tu regułę odhaczenia i wtedy do sumy
    ///     wchodzą WYŁĄCZNIE posiłki zjedzone, a reszta zostaje na liście
    ///     wygaszona. Zaplanowany obiad nie jest dowodem, że ktoś go zjadł,
    ///     ale nie jest też powodem, żeby zniknął z dnia.
    static func make(
        slots: [MealSlot],
        meals: (MealSlot) -> [PlanMeal],
        knownHouseholdMemberCount: Int?,
        isEaten: ((PlanMeal) -> Bool)? = nil
    ) -> PlanDayNutrition {
        // Dopasowanie wzorca zamiast `isEaten != nil`: domknięcie nie jest
        // `Equatable` i porównywanie go z `nil` czyta się jak pomyłka, nawet
        // gdy kompilator je przepuszcza.
        var countsOnlyEaten = false
        if case .some = isEaten { countsOnlyEaten = true }

        var entries: [Entry] = []
        var sum = Nutrition.zero
        var filled = 0

        for slot in slots {
            let dishes = meals(slot)

            guard !dishes.isEmpty else {
                entries.append(
                    Entry(
                        slot: slot,
                        meal: nil,
                        nutrition: .zero,
                        isEaten: false,
                        id: "empty.\(slot.rawValue)"
                    )
                )
                continue
            }

            // Pora liczy się jako „wypełniona", gdy niesie to, o co pyta
            // licznik: w Planie — cokolwiek, w Kalendarzu — coś zjedzonego.
            if !countsOnlyEaten || dishes.contains(where: { isEaten?($0) == true }) {
                filled += 1
            }

            for dish in dishes {
                let nutrition = dish.nutritionPerPerson(
                    knownHouseholdMemberCount: knownHouseholdMemberCount
                )
                let eaten = isEaten?(dish) ?? false

                if !countsOnlyEaten || eaten {
                    sum.kcal += nutrition.kcal
                    sum.protein += nutrition.protein
                    sum.fat += nutrition.fat
                    sum.carbs += nutrition.carbs
                    sum.fiber += nutrition.fiber
                    sum.salt += nutrition.salt
                }

                entries.append(
                    Entry(
                        slot: slot,
                        meal: dish,
                        nutrition: nutrition,
                        isEaten: eaten,
                        id: "\(slot.rawValue).\(dish.id)"
                    )
                )
            }
        }

        return PlanDayNutrition(
            entries: entries,
            total: sum,
            filledSlots: filled,
            slotCount: slots.count,
            countsOnlyEaten: countsOnlyEaten
        )
    }
}
