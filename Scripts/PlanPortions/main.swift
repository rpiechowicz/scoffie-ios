import Foundation

// Porcje per osoba (`Scoffie/Models/Plans/PlanPortions.swift`) — jednostki,
// etykiety, stepper co 0,5 i decyzja zapisu, bez SwiftUI i bez targetu
// testów, tak jak `Scripts/CardContract`. Uruchomienie:
// `sh Scripts/plan-portions-check.sh`.
//
// Kontrakt backendu (`ios-contract.md` + §16 raportu write-safety): porcja
// osoby = wielokrotność 0,5 w widełkach 0,5–6, suma pozycji ≤ 12; zapis
// pozycji z alokacją idzie z `PRESERVE` i tokenami, bez tokenów — wcale.

var failures = 0

func check(_ condition: Bool, _ name: String) {
    if condition {
        print("OK   \(name)")
    } else {
        failures += 1
        print("BŁĄD \(name)")
    }
}

// MARK: Jednostki i etykiety

check(PlanPortions.units(fromServings: 1.5) == 30, "1,5 porcji = 30 jednostek")
check(PlanPortions.units(fromServings: 0.5) == 10, "0,5 porcji = 10 jednostek")
check(PlanPortions.label(units: 10) == "0,5", "etykieta 0,5")
check(PlanPortions.label(units: 20) == "1", "etykieta 1 (bez „,00”)")
check(PlanPortions.label(units: 30) == "1,5", "etykieta 1,5")
check(PlanPortions.label(units: 120) == "6", "etykieta maksimum 6")
check(PlanPortions.label(units: 25) == "1,25", "wartość spoza kroku (stare dane) — dwa miejsca, bez zaokrąglania")
check(PlanPortions.label(units: 16) == "0,80", "wartość spoza kroku 0,80")
check(PlanPortions.totalUnits(["a": 10, "b": 30]) == 40, "suma 0,5 + 1,5 = 2")
check(PlanPortions.plannedServings(forTotalUnits: 50) == 3, "plannedServings = ceil(2,5) = 3")
check(PlanPortions.plannedServings(forTotalUnits: 40) == 2, "plannedServings = ceil(2) = 2")
var roundTrip = true
for units in stride(from: 10, through: 120, by: 10)
where PlanPortions.units(fromServings: PlanPortions.servings(fromUnits: units)) != units {
    roundTrip = false
}
check(roundTrip, "0,5…6: porcje ↔ jednostki bez strat")

// MARK: Stepper

check(PlanPortions.stepped(units: 20, direction: 1, totalUnits: 40) == 30, "1 → 1,5")
check(PlanPortions.stepped(units: 20, direction: -1, totalUnits: 40) == 10, "1 → 0,5")
check(PlanPortions.stepped(units: 10, direction: -1, totalUnits: 30) == nil, "0,5 to minimum — minus wygaszony")
check(PlanPortions.stepped(units: 120, direction: 1, totalUnits: 140) == nil, "6 to maksimum osoby — plus wygaszony")
check(PlanPortions.stepped(units: 60, direction: 1, totalUnits: 240) == nil, "suma 12 — plus wygaszony")
check(PlanPortions.stepped(units: 60, direction: 1, totalUnits: 230) == 70, "do sumy 12 włącznie plus działa (11,5 → 12)")
check(PlanPortions.stepped(units: 60, direction: 1, totalUnits: 235) == nil, "krok przekroczyłby sumę 12 — plus wygaszony")
check(PlanPortions.stepped(units: 60, direction: -1, totalUnits: 240) == 50, "przy sumie 12 minus działa")
check(PlanPortions.stepped(units: 120, direction: -1, totalUnits: 260) == 110, "suma ponad 12 (6 + 6 + 1) — minus działa")
check(PlanPortions.stepped(units: 20, direction: 1, totalUnits: 260) == nil, "suma ponad 12 — plus wygaszony")
check(PlanPortions.stepped(units: 25, direction: 1, totalUnits: 45) == 30, "1,25 (stare dane) + → 1,5 (na siatkę)")
check(PlanPortions.stepped(units: 25, direction: -1, totalUnits: 45) == 20, "1,25 (stare dane) − → 1 (na siatkę)")
check(PlanPortions.stepped(units: 16, direction: -1, totalUnits: 36) == 10, "0,80 − → 0,5")
check(PlanPortions.isValid(units: 30) && !PlanPortions.isValid(units: 25) && !PlanPortions.isValid(units: 0)
      && !PlanPortions.isValid(units: 130), "walidacja: tylko 0,5…6 co 0,5")

// MARK: Decyzja zapisu pozycji

let soup = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
let pasta = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
let salad = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
let allocatedSoup = PlanPortions.SlotMeal(recipeId: soup, hasPortions: true, revision: 11)
let allocatedSoupNoToken = PlanPortions.SlotMeal(recipeId: soup, hasPortions: true, revision: nil)
let legacySoup = PlanPortions.SlotMeal(recipeId: soup, hasPortions: false, revision: 4)
let legacyPasta = PlanPortions.SlotMeal(recipeId: pasta, hasPortions: false, revision: 5)
let allocatedPasta = PlanPortions.SlotMeal(recipeId: pasta, hasPortions: true, revision: 9)

func preserve(_ revision: Int, swap: Bool = false, target: Int? = nil) -> PlanPortions.UpsertDecision {
    .write(.preserve(PlanPortions.RevisionTokens(expectedRevision: revision, isSwap: swap, expectedTargetRevision: target)))
}

func replace(_ units: [String: Int], _ revision: Int? = nil, swap: Bool = false, target: Int? = nil) -> PlanPortions.UpsertDecision {
    .write(.replace(units: units, tokens: revision.map {
        PlanPortions.RevisionTokens(expectedRevision: $0, isSwap: swap, expectedTargetRevision: target)
    }))
}

// Z alokacją i tokenem: PRESERVE.
check(PlanPortions.upsertDecision(slot: [allocatedSoup], recipeId: soup, replacingRecipeId: nil) == preserve(11),
      "z alokacją: zapis tej samej pozycji (kto je / dołączenie) → PRESERVE, token pozycji")
check(PlanPortions.upsertDecision(slot: [allocatedSoup], recipeId: soup, replacingRecipeId: soup) == preserve(11),
      "z alokacją: „Zmień przepis” na to samo danie → nie zamiana, PRESERVE bez tokenu celu")
check(PlanPortions.upsertDecision(slot: [allocatedSoup], recipeId: salad, replacingRecipeId: soup) == preserve(11, swap: true, target: nil),
      "z alokacją: zamiana na danie spoza slotu → PRESERVE, token źródła + cel null")
check(PlanPortions.upsertDecision(slot: [legacySoup, allocatedPasta], recipeId: pasta, replacingRecipeId: soup) == preserve(4, swap: true, target: 9),
      "zamiana na danie, które w slocie ma alokację → para tokenów źródła i celu")
check(PlanPortions.upsertDecision(slot: [allocatedSoup, legacyPasta], recipeId: pasta, replacingRecipeId: soup) == preserve(11, swap: true, target: 5),
      "zamiana źródła z alokacją na istniejące danie → token celu z odczytu")

// Z alokacją bez tokenu: nic nie wysyłamy.
check(PlanPortions.upsertDecision(slot: [allocatedSoupNoToken], recipeId: soup, replacingRecipeId: nil) == .blocked,
      "alokacja bez tokenu (stary cache / backend) → zablokowane")
check(PlanPortions.upsertDecision(slot: [allocatedSoupNoToken], recipeId: salad, replacingRecipeId: soup) == .blocked,
      "zamiana źródła z alokacją bez tokenu → zablokowane")
check(PlanPortions.upsertDecision(slot: [allocatedPasta], recipeId: pasta, replacingRecipeId: soup) == .blocked,
      "zamiana ze źródłem nieznanym lokalnie, cel z alokacją → zablokowane (brak tokenu źródła)")

// Bez alokacji: jak dotąd.
check(PlanPortions.upsertDecision(slot: [allocatedSoup], recipeId: salad, replacingRecipeId: nil) == .send,
      "nowe danie obok dania z porcjami → bez tokenów")
check(PlanPortions.upsertDecision(slot: [], recipeId: soup, replacingRecipeId: nil) == .send,
      "nowa pozycja w pustym slocie → bez tokenów")
check(PlanPortions.upsertDecision(slot: [legacySoup], recipeId: soup, replacingRecipeId: nil) == .send,
      "legacy: zmiana „kto je” / stepper → bez tokenów")
check(PlanPortions.upsertDecision(slot: [legacySoup, legacyPasta], recipeId: salad, replacingRecipeId: soup) == .send,
      "legacy: zamiana dania → bez tokenów")
check(PlanPortions.upsertDecision(slot: [legacySoup, allocatedPasta], recipeId: soup, replacingRecipeId: nil) == .send,
      "legacy pozycja obok dania z porcjami → bez tokenów")

// MARK: Pierwsze ustawienie porcji osób (REPLACE)

let map = ["a": 30, "b": 10]
check(PlanPortions.replaceDecision(slot: [legacySoup], recipeId: soup, replacingRecipeId: nil, units: map) == replace(map, 4),
      "REPLACE na pozycji bez alokacji → pełna mapa + token pozycji")
check(PlanPortions.replaceDecision(slot: [legacySoup], recipeId: soup, replacingRecipeId: nil, units: map, knownRevision: 3) == replace(map, 3),
      "REPLACE: token z migawki ekranu ma pierwszeństwo przed stanem store'u")
check(PlanPortions.replaceDecision(slot: [], recipeId: soup, replacingRecipeId: nil, units: map) == replace(map),
      "REPLACE na nowej pozycji → bez tokenów")
check(PlanPortions.replaceDecision(slot: [legacySoup], recipeId: salad, replacingRecipeId: soup, units: map) == replace(map, 4, swap: true, target: nil),
      "REPLACE z zamianą → token źródła + cel null")
check(PlanPortions.replaceDecision(slot: [legacySoup, allocatedPasta], recipeId: pasta, replacingRecipeId: soup, units: map) == replace(map, 4, swap: true, target: 9),
      "REPLACE z zamianą na istniejące danie → para tokenów")
check(PlanPortions.replaceDecision(slot: [allocatedSoupNoToken], recipeId: soup, replacingRecipeId: nil, units: map) == .blocked,
      "REPLACE na alokacji bez tokenu → zablokowane")
check(PlanPortions.replaceDecision(slot: [allocatedSoup], recipeId: soup, replacingRecipeId: nil, units: map) == .blocked,
      "REPLACE z ekranu bez tokenu, a store ma już alokację z serwera → zablokowane (nie nadpisuje cudzej)")
check(PlanPortions.replaceDecision(slot: [allocatedSoup], recipeId: soup, replacingRecipeId: nil, units: map, knownRevision: 11) == replace(map, 11),
      "REPLACE na alokacji z tokenem migawki → zastąpienie z tokenem")
let noTokenLegacy = PlanPortions.SlotMeal(recipeId: soup, hasPortions: false, revision: nil)
check(PlanPortions.replaceDecision(slot: [noTokenLegacy], recipeId: soup, replacingRecipeId: nil, units: map) == replace(map),
      "REPLACE na pozycji bez alokacji i bez tokenu (np. przed ackiem) → bez tokenów")
check(PlanPortions.replaceDecision(slot: [allocatedPasta], recipeId: pasta, replacingRecipeId: soup, units: map) == .blocked,
      "REPLACE z zamianą nieznanego źródła na danie z alokacją → zablokowane")

// MARK: Punkt startowy porcji osób

check(PlanPortions.seededUnits(eaters: ["a", "b"], totalUnits: 40) == ["a": 20, "b": 20], "2 porcje / 2 osoby → po 1")
check(PlanPortions.seededUnits(eaters: ["a", "b"], totalUnits: 60) == ["a": 30, "b": 30], "3 porcje / 2 osoby → po 1,5")
check(PlanPortions.seededUnits(eaters: ["a", "b", "c"], totalUnits: 100) == ["a": 40, "b": 30, "c": 30], "5 / 3 → 2 / 1,5 / 1,5 (suma się zgadza)")
check(PlanPortions.seededUnits(eaters: ["a", "b"], totalUnits: 20) == ["a": 10, "b": 10], "1 porcja / 2 osoby → po 0,5")
check(PlanPortions.seededUnits(eaters: ["a"], totalUnits: 30) == ["a": 30], "1 osoba, 1,5 → 1,5")
check(PlanPortions.totalUnits(PlanPortions.seededUnits(eaters: ["a", "b", "c", "d", "e"], totalUnits: 240)) == 240,
      "12 porcji / 5 osób → suma dokładnie 12")
check(PlanPortions.fitsPerPerson(totalUnits: 120, eaterCount: 1) && !PlanPortions.fitsPerPerson(totalUnits: 160, eaterCount: 1)
      && !PlanPortions.fitsPerPerson(totalUnits: 40, eaterCount: 0),
      "więcej niż 6 na osobę (8 porcji w domu jednoosobowym) → stepper porcji łącznych")
check(PlanPortions.seededUnits(eaters: ["a", "a"], totalUnits: 40) == ["a": 40], "duplikat osoby liczony raz")
check(PlanPortions.seededUnits(eaters: [], totalUnits: 40).isEmpty, "bez jedzących → pusto")

// MARK: Optymistyczne audytorium PRESERVE

check(PlanPortions.preservedAllocation(["a": 30, "b": 10], participantIds: ["a", "c"]) == ["a": 30, "c": 20],
      "PRESERVE: zostający zachowuje porcję, nowy dostaje 1, usunięty znika")
check(PlanPortions.preservedAllocation(["a": 30, "b": 10], participantIds: []) == ["a": 30, "b": 10],
      "PRESERVE na „Wspólne”: alokacja bez zmian do acka")

check(PlanPortions.staleStateCodes == ["PLAN_REVISION_CONFLICT", "PLAN_REVISION_REQUIRED", "PLAN_PORTIONS_CONFLICT", "PLAN_ITEM_NOT_FOUND"],
      "kody nieaktualnego stanu → odświeżenie tygodnia")
check(!PlanPortions.editBlockedMessage.isEmpty && PlanPortions.editBlockedMessage.count < 140
      && !PlanPortions.readOnlyMessage.isEmpty, "komunikaty: krótkie")

print(failures == 0 ? "\nWSZYSTKO OK" : "\nBŁĘDÓW: \(failures)")
exit(failures == 0 ? 0 : 1)
