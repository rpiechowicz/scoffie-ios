import Foundation

// Porcje per osoba (`Scoffie/Models/Plans/PlanPortions.swift`) — tabela decyzji
// zapisu i jednostki, bez SwiftUI i bez targetu testów, tak jak
// `Scripts/CardContract`. Uruchomienie: `sh Scripts/plan-portions-check.sh`.

var failures = 0

func check(_ condition: Bool, _ name: String) {
    if condition {
        print("OK   \(name)")
    } else {
        failures += 1
        print("BŁĄD \(name)")
    }
}

let asia = "00000000-0000-4000-8000-00000000000a"
let rafal = "00000000-0000-4000-8000-00000000000b"
let ola = "00000000-0000-4000-8000-00000000000c"
let allocated = [asia: 16, rafal: 25] // 0,80 + 1,25

// MARK: Jednostki i etykiety

check(PlanPortions.units(fromServings: 0.8) == 16, "0,8 porcji = 16 jednostek")
check(PlanPortions.units(fromServings: 1.3) == 26, "1,3 porcji = 26 jednostek")
check(PlanPortions.units(fromServings: 1.25) == 25, "1,25 porcji = 25 jednostek")
check(PlanPortions.label(units: 25) == "1,25", "etykieta 1,25")
check(PlanPortions.label(units: 16) == "0,80", "etykieta 0,80 (dwa miejsca, bez „units=16”)")
check(PlanPortions.label(units: 2) == "0,10", "etykieta minimum 0,10")
check(PlanPortions.label(units: 120) == "6,00", "etykieta maksimum 6,00")
check(PlanPortions.derivedPlannedServings(allocated) == 3, "plannedServings = ceil(0,80 + 1,25) = 3")
check(PlanPortions.derivedPlannedServings([asia: 20]) == 1, "plannedServings = ceil(1,00) = 1")
check(PlanPortions.derivedPlannedServings([asia: 120, rafal: 120]) == 12, "plannedServings ≤ 12")

// Każda wartość 0,10…6,00 na drucie: `units/20` to ten sam Double co z napisu
// z dwoma miejscami — więc serwer (`maxDecimalPlaces: 2`) ją przyjmie.
var wireOK = true
for units in PlanPortions.minUnits...PlanPortions.maxUnits {
    let value = PlanPortions.servings(fromUnits: units)
    if Double(String(format: "%.2f", value)) != value { wireOK = false }
    if PlanPortions.units(fromServings: value) != units { wireOK = false }
}
check(wireOK, "0,10…6,00: wartość na drucie = dokładnie k × 0,05 (i wraca do tych samych jednostek)")

// MARK: Tabela decyzji zapisu (MealCalendarStore.upsertWeekSlot)

// Stary plan / pozycja bez alokacji — nic się nie zmienia (równy podział).
check(PlanPortions.forWrite(existing: [:], audience: [asia, rafal], explicit: nil, explicitTotal: false) == nil,
      "pozycja bez alokacji: pole pominięte, jak dotąd")
check(PlanPortions.forWrite(existing: [:], audience: [asia], explicit: nil, explicitTotal: true) == nil,
      "pozycja bez alokacji + stepper łączny: jak dotąd (plannedServings)")

// Ponowny zapis / to samo audytorium — alokacja wraca na serwer bez zmian.
check(PlanPortions.forWrite(existing: allocated, audience: [asia, rafal], explicit: nil, explicitTotal: false) == allocated,
      "ten sam zapis: alokacja odesłana w całości (inaczej serwer ją kasuje)")

// Zmiana „kto je”: dochodzący 1,00, odchodzący znika, reszta zostaje.
check(PlanPortions.forWrite(existing: allocated, audience: [asia, rafal, ola], explicit: nil, explicitTotal: false)
      == [asia: 16, rafal: 25, ola: 20], "dochodzi Ola: jej 1,00, Asia i Rafał bez zmian")
check(PlanPortions.forWrite(existing: allocated, audience: [rafal], explicit: nil, explicitTotal: false)
      == [rafal: 25], "odchodzi Asia: znika jej porcja, Rafał bez zmian")

// Podmiana dania przy tym samym audytorium — porcje osób przechodzą na nowe danie.
check(PlanPortions.forWrite(existing: allocated, audience: [rafal, asia], explicit: nil, explicitTotal: false) == allocated,
      "podmiana dania: porcje osób przechodzą (kolejność audytorium bez znaczenia)")

// Edytor porcji: jedna osoba zmieniona, reszta odesłana — cała alokacja.
let edited = PlanPortions.adjusting(allocated, memberId: rafal, by: 1)
check(edited == [asia: 16, rafal: 26], "edycja jednej osoby: +0,05 tylko Rafałowi")
check(PlanPortions.forWrite(existing: allocated, audience: [asia, rafal], explicit: edited, explicitTotal: false) == edited,
      "edytor: wysyłana PEŁNA alokacja z jedną zmianą")

// Jawny stepper porcji łącznych = świadomy powrót do równego podziału.
check(PlanPortions.forWrite(existing: allocated, audience: [asia, rafal], explicit: nil, explicitTotal: true) == nil,
      "stepper łączny przy alokacji: jawny równy podział (pole pominięte)")

// „Wspólne” bez listy domowników: nie wiadomo, dla kogo — store wstrzymuje zapis.
check(PlanPortions.forWrite(existing: allocated, audience: nil, explicit: nil, explicitTotal: false) == nil,
      "nieznane audytorium: brak alokacji do wysłania (store odmawia zamiast kasować)")

// MARK: Granice serwera

check(PlanPortions.adjusting([asia: 2], memberId: asia, by: -1) == [asia: 2], "minimum 0,10 na osobę")
check(PlanPortions.adjusting([asia: 120], memberId: asia, by: 1) == [asia: 120], "maksimum 6,00 na osobę")
check(PlanPortions.adjusting([asia: 120, rafal: 120], memberId: rafal, by: 1) == [asia: 120, rafal: 120], "Σ ≤ 12 porcji")
check(PlanPortions.adjusting(allocated, memberId: ola, by: 1) == allocated, "osoba spoza alokacji: bez zmian")
check(PlanPortions.isValid(allocated, audience: [rafal, asia]), "poprawna alokacja dla audytorium")
check(!PlanPortions.isValid(allocated, audience: [asia, rafal, ola]), "brak porcji Oli = PLAN_PORTIONS_INVALID")
check(!PlanPortions.isValid([asia: 1, rafal: 25], audience: [asia, rafal]), "0,05 < minimum = PLAN_PORTIONS_INVALID")

print(failures == 0 ? "\nWSZYSTKO OK" : "\nBŁĘDÓW: \(failures)")
exit(failures == 0 ? 0 : 1)
