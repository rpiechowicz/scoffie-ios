import Foundation

// Porcje per osoba (backend Etap 2.2) — scenariusze bez SwiftUI i bez
// targetu testów, tak jak `Scripts/CardContract`. Numery = lista testów
// iOS z polecenia (13–17). Uruchomienie: `sh Scripts/plan-portions-check.sh`.

var failures = 0

func check(_ condition: Bool, _ name: String) {
    if condition {
        print("OK   \(name)")
    } else {
        failures += 1
        print("BŁĄD \(name)")
    }
}

func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

let asia = "00000000-0000-4000-8000-00000000000a"
let rafal = "00000000-0000-4000-8000-00000000000b"

/// Przepis na 4 porcje: 2000 kcal całości = 500 kcal na porcję.
let dinner = Recipe(
    name: "Wspólna kolacja",
    description: "",
    category: .dinner,
    servings: 4,
    nutrition: Nutrition(kcal: 2000, protein: 120, fat: 80, carbs: 200, fiber: 20, salt: 4)
)

let decoder = JSONDecoder()
let encoder = JSONEncoder()

// MARK: 13. Stary plan (cache i serwer sprzed porcji) — bez zmian

do {
    let legacy = PlanMeal(recipe: dinner, plannedServings: 3)
    let data = try encoder.encode(legacy)
    // Cache sprzed Etapu 2.2 nie ma klucza `portions` — usuwamy go z JSON-a.
    var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    object.removeValue(forKey: "portions")
    let oldCache = try JSONSerialization.data(withJSONObject: object)
    let decoded = try decoder.decode(PlanMeal.self, from: oldCache)
    check(decoded.portions.isEmpty, "13. plan bez klucza `portions` dekoduje się jako równy podział")
    check(
        near(decoded.nutritionPerPerson(householdMemberCount: 2, memberId: asia).kcal, 750),
        "13. pozycja bez alokacji: 3 porcje / 2 osoby = 750 kcal dla każdego (jak dotąd)"
    )
    check(
        near(decoded.nutritionPerPerson(householdMemberCount: 2).kcal, 750),
        "13. wywołanie bez osoby liczy jak przed zmianą"
    )
    check(decoded.isCustomServings(householdMemberCount: 2), "13. plakietka „3 porcje” dalej działa bez alokacji")
} catch {
    check(false, "13. dekodowanie starego planu: \(error)")
}

// MARK: 14. Nowy plan — moje kcal z mojej porcji

let shared = PlanMeal(
    recipe: dinner,
    plannedServings: 3,
    portions: [asia: 0.8, rafal: 1.3]
)
check(near(shared.nutritionPerPerson(householdMemberCount: 2, memberId: asia).kcal, 400), "14. Asia: 0,8 porcji = 400 kcal")
check(
    near(shared.nutritionPerPerson(knownHouseholdMemberCount: nil, memberId: asia).kcal, 400),
    "14. porcja osoby liczy się także przed wczytaniem składu domu (bez migania)"
)
check(!shared.isCustomServings(householdMemberCount: 2), "14. brak mylącej plakietki „3 porcje” przy 0,8 + 1,3")

// MARK: 15. Kcal innego domownika z JEGO porcji; dołączony bez wpisu = 1 porcja

check(near(shared.nutritionPerPerson(householdMemberCount: 2, memberId: rafal).kcal, 650), "15. Rafał: 1,3 porcji = 650 kcal")
check(near(shared.nutritionPerPerson(householdMemberCount: 3, memberId: "nowy").kcal, 500), "15. osoba bez wpisu je 1 porcję")
check(near(shared.servingsPerPerson(householdMemberCount: 2), 1.05), "15. bez wskazania osoby: średnia porcja")

// MARK: 16. Pasek dnia sumuje INDYWIDUALNĄ porcję; wspólne zostaje wspólne

let breakfast = PlanMeal(recipe: dinner, plannedServings: 2) // bez alokacji: 1 porcja na osobę
let meals: [MealSlot: [PlanMeal]] = [.breakfast: [breakfast], .dinner: [shared]]
let asiaDay = PlanDayNutrition.make(
    slots: [.breakfast, .dinner],
    meals: { (meals[$0] ?? []).visibleTo(memberId: asia) },
    knownHouseholdMemberCount: 2,
    memberId: asia
)
let rafalDay = PlanDayNutrition.make(
    slots: [.breakfast, .dinner],
    meals: { (meals[$0] ?? []).visibleTo(memberId: rafal) },
    knownHouseholdMemberCount: 2,
    memberId: rafal
)
check(near(asiaDay.total.kcal, 900), "16. dzień Asi: 500 + 400 = 900 kcal")
check(near(rafalDay.total.kcal, 1150), "16. dzień Rafała: 500 + 650 = 1150 kcal")
check(shared.isShared && [shared].visibleTo(memberId: asia).count == 1, "16. danie z porcjami zostaje wspólne (jedna pozycja)")

// MARK: 17. Cache po migracji: porcje przeżywają zapis i odczyt

do {
    let data = try encoder.encode(shared)
    let decoded = try decoder.decode(PlanMeal.self, from: data)
    check(decoded == shared, "17. PlanMeal z porcjami: encode → decode bez strat (równość)")
    check(decoded.portions == [asia: 0.8, rafal: 1.3], "17. porcje po odczycie z cache'u")
    var changed = shared
    changed.portions[asia] = 0.85
    check(changed != shared, "17. inna alokacja = inna pozycja (odświeżenie widoku)")
} catch {
    check(false, "17. round-trip cache'u: \(error)")
}

if failures > 0 {
    print("\n\(failures) scenariuszy nie przeszło")
    exit(1)
}
print("\nWszystkie scenariusze przeszły")
