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
/// jak w nagłówku dnia na osi (`PlanDayTimeline.kcalToday`). Dzienny cel jest
/// osobisty, więc porównywać się z nim może wyłącznie osobisty talerz.
struct PlanDayNutrition {
    /// Jeden wiersz listy „W posiłkach": danie albo pusta pora.
    struct Entry: Identifiable {
        let slot: MealSlot
        /// `nil` = pora bez posiłku.
        let meal: PlanMeal?
        /// Makra na jedną osobę; `.zero` dla pustej pory.
        let nutrition: Nutrition
        let id: String

        var isPlanned: Bool { meal != nil }
    }

    let entries: [Entry]
    /// Suma dnia na jedną osobę.
    let total: Nutrition
    /// Ile pór ma już posiłek i ile ich w ogóle jest — „3 z 3 posiłków".
    let filledSlots: Int
    let slotCount: Int

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
    ///   - meals: warianty posiłku w porze, już zawężone do bieżącej soczewki.
    ///   - knownHouseholdMemberCount: `nil`, dopóki `SessionStore` nie dowiezie
    ///     składu gospodarstwa — wtedy udziałem jednej osoby jest pełna porcja
    ///     przepisu, czyli ta sama liczba, którą reguła auto pokaże po
    ///     wczytaniu listy. Ekran nie miga.
    static func make(
        slots: [MealSlot],
        meals: (MealSlot) -> [PlanMeal],
        knownHouseholdMemberCount: Int?
    ) -> PlanDayNutrition {
        var entries: [Entry] = []
        var sum = Nutrition.zero
        var filled = 0

        for slot in slots {
            let dishes = meals(slot)

            guard !dishes.isEmpty else {
                entries.append(
                    Entry(slot: slot, meal: nil, nutrition: .zero, id: "empty.\(slot.rawValue)")
                )
                continue
            }

            filled += 1

            for dish in dishes {
                let nutrition = dish.nutritionPerPerson(
                    knownHouseholdMemberCount: knownHouseholdMemberCount
                )
                sum.kcal += nutrition.kcal
                sum.protein += nutrition.protein
                sum.fat += nutrition.fat
                sum.carbs += nutrition.carbs
                sum.fiber += nutrition.fiber
                sum.salt += nutrition.salt

                entries.append(
                    Entry(
                        slot: slot,
                        meal: dish,
                        nutrition: nutrition,
                        id: "\(slot.rawValue).\(dish.id)"
                    )
                )
            }
        }

        return PlanDayNutrition(
            entries: entries,
            total: sum,
            filledSlots: filled,
            slotCount: slots.count
        )
    }
}
