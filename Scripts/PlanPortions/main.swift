import Foundation

// Porcje per osoba (`Scoffie/Models/Plans/PlanPortions.swift`) — jednostki,
// etykiety i decyzja zapisu, bez SwiftUI i bez targetu testów, tak jak
// `Scripts/CardContract`. Uruchomienie: `sh Scripts/plan-portions-check.sh`.
//
// Zapis pozycji z alokacją jest ZABLOKOWANY (API GAP: serwer zastępuje całą
// alokację bez kontroli wersji). Sprawdzamy, że każda ścieżka, która by ją
// przepisała, kończy się `.blocked` — a `MealCalendarStore` wychodzi wtedy
// przed zapisem optymistycznym i przed repozytorium — oraz że pozycje bez
// alokacji (legacy) zapisują się jak dotąd.

var failures = 0

func check(_ condition: Bool, _ name: String) {
    if condition {
        print("OK   \(name)")
    } else {
        failures += 1
        print("BŁĄD \(name)")
    }
}

// MARK: Jednostki i etykiety (odczyt)

check(PlanPortions.units(fromServings: 0.8) == 16, "0,8 porcji = 16 jednostek")
check(PlanPortions.units(fromServings: 1.3) == 26, "1,3 porcji = 26 jednostek")
check(PlanPortions.units(fromServings: 1.25) == 25, "1,25 porcji = 25 jednostek")
check(PlanPortions.label(units: 25) == "1,25", "etykieta 1,25")
check(PlanPortions.label(units: 16) == "0,80", "etykieta 0,80 (dwa miejsca, bez „units=16”)")
check(PlanPortions.label(units: 2) == "0,10", "etykieta minimum 0,10")
check(PlanPortions.label(units: 120) == "6,00", "etykieta maksimum 6,00")
check(PlanPortions.totalUnits(["a": 16, "b": 25]) == 41, "suma 0,80 + 1,25 = 2,05")
var roundTrip = true
for units in 2...120 where PlanPortions.units(fromServings: PlanPortions.servings(fromUnits: units)) != units {
    roundTrip = false
}
check(roundTrip, "0,10…6,00: porcje ↔ jednostki bez strat")

// MARK: Decyzja zapisu

let soup = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
let pasta = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
let salad = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
let allocatedSoup = PlanPortions.SlotMeal(recipeId: soup, hasPortions: true)
let legacySoup = PlanPortions.SlotMeal(recipeId: soup, hasPortions: false)
let legacyPasta = PlanPortions.SlotMeal(recipeId: pasta, hasPortions: false)
let allocatedPasta = PlanPortions.SlotMeal(recipeId: pasta, hasPortions: true)

// Zablokowane: każdy zapis, który przepisałby alokację.
// Zmiana „kto je”, stepper porcji łącznych i ponowny zapis to ten sam
// zapis TEJ pozycji — decyzja nie zależy od rodzaju zmiany.
check(PlanPortions.upsertDecision(slot: [allocatedSoup], recipeId: soup, replacingRecipeId: nil) == .blocked,
      "z alokacją: zapis tej samej pozycji (kto je / stepper / ponowny zapis) → zablokowane")
check(PlanPortions.upsertDecision(slot: [allocatedSoup, legacyPasta], recipeId: soup, replacingRecipeId: nil) == .blocked,
      "z alokacją: dołączenie do istniejącej pozycji (AddToPlan / wybór w slocie) → zablokowane")
check(PlanPortions.upsertDecision(slot: [allocatedSoup], recipeId: salad, replacingRecipeId: soup) == .blocked,
      "z alokacją: zamiana dania z porcjami na inne → zablokowane")
check(PlanPortions.upsertDecision(slot: [legacySoup, allocatedPasta], recipeId: pasta, replacingRecipeId: soup) == .blocked,
      "zamiana na danie, które w slocie ma już alokację → zablokowane")
check(PlanPortions.upsertDecision(slot: [allocatedSoup], recipeId: soup, replacingRecipeId: soup) == .blocked,
      "z alokacją: „Zmień przepis” na to samo danie → zablokowane")

// Niezablokowane: operacje, które alokacji nie przepisują.
check(PlanPortions.upsertDecision(slot: [allocatedSoup], recipeId: pasta, replacingRecipeId: nil) == .send,
      "nowe danie obok dania z porcjami (inna pozycja) → wysyłane")
check(PlanPortions.upsertDecision(slot: [], recipeId: soup, replacingRecipeId: nil) == .send,
      "nowa pozycja w pustym slocie → wysyłane")

// Legacy: pozycje bez alokacji jak dotąd.
check(PlanPortions.upsertDecision(slot: [legacySoup], recipeId: soup, replacingRecipeId: nil) == .send,
      "legacy: zmiana „kto je” / stepper → wysyłane (bez pola portions)")
check(PlanPortions.upsertDecision(slot: [legacySoup, legacyPasta], recipeId: salad, replacingRecipeId: soup) == .send,
      "legacy: zamiana dania → wysyłane")
check(PlanPortions.upsertDecision(slot: [legacySoup, allocatedPasta], recipeId: soup, replacingRecipeId: nil) == .send,
      "legacy pozycja obok dania z porcjami → wysyłane")

check(!PlanPortions.editBlockedMessage.isEmpty && PlanPortions.editBlockedMessage.count < 140,
      "komunikat ograniczenia: krótki")

print(failures == 0 ? "\nWSZYSTKO OK" : "\nBŁĘDÓW: \(failures)")
exit(failures == 0 ? 0 : 1)
