import Foundation

// Sprawdzian kontraktu: JSON policzony przez SERWER wchodzi w struktury iOS.
// Cichy rozjazd nazwy pola nie wywala niczego — karta po prostu staje się
// `.unknown` i znika z ekranu. Ten skrypt zamienia to w twardy błąd.

let planWeekJSON = #"{"kind": "PLAN_WEEK", "v": 1, "proposalId": "55555555-5555-4555-8555-555555555555", "weekStart": "2026-08-31", "title": "Obiad i kolacja na tydzień", "subtitle": "Nic się nie powtarza, a wtorek jest szybki.", "days": [{"dayOfWeek": "MON", "dayLabel": "Poniedziałek", "date": "2026-08-31", "slots": [{"mealType": "LUNCH", "mealLabel": "Obiad", "recipeId": "r-1", "title": "Kurczak z ryżem", "kcalPerServing": 620, "prepTimeMinutes": 30, "participantIds": [], "change": "NEW"}, {"mealType": "DINNER", "mealLabel": "Kolacja", "recipeId": "r-2", "title": "Sałatka z tuńczykiem", "kcalPerServing": 380, "prepTimeMinutes": 12, "participantIds": ["u1"], "change": "KEPT"}], "kcalTotal": 1000}, {"dayOfWeek": "TUE", "dayLabel": "Wtorek", "date": "2026-09-01", "slots": [{"mealType": "DINNER", "mealLabel": "Kolacja", "recipeId": "r-3", "title": "Placki ziemniaczane", "kcalPerServing": 540, "prepTimeMinutes": 40, "participantIds": [], "change": "NEW"}], "kcalTotal": 540}], "removed": [{"dayLabel": "Środa", "mealLabel": "Kolacja", "title": "Zupa pomidorowa"}], "summary": {"meals": 3, "created": 2, "updated": 0, "removed": 1, "averageKcalPerDay": 770, "targetKcalPerDay": 2100}, "actions": [{"type": "APPLY", "proposalId": "55555555-5555-4555-8555-555555555555", "label": "Dodaj do planu", "style": "PRIMARY"}], "state": {"status": "PENDING", "canApply": true, "canUndo": false, "until": "2026-09-03T10:00:00.000Z"}}"#
let appliedJSON = #"{"kind": "APPLIED", "v": 1, "proposalId": "55555555-5555-4555-8555-555555555555", "weekStart": "2026-08-31", "title": "Zapisano plan na tydzień od 31 sierpnia", "summary": {"created": 2, "updated": 0, "removed": 1}, "notes": ["Cofnięcie przywróci usunięte posiłki, ale nie odhaczenia „zjedzone”."], "actions": [{"type": "UNDO", "proposalId": "55555555-5555-4555-8555-555555555555", "label": "Cofnij", "style": "SECONDARY"}, {"type": "OPEN_PLAN", "proposalId": null, "label": "Otwórz Plan tygodnia", "style": "PRIMARY"}], "state": {"status": "APPLIED", "canApply": false, "canUndo": true, "until": "2026-08-31T11:00:00.000Z"}}"#
let unknownJSON = #"{"kind":"MACRO_GAP","v":1,"cokolwiek":true}"#
let brokenJSON = #"{"kind":"PLAN_WEEK","v":1}"#

func check(_ label: String, _ condition: Bool) {
    print(condition ? "  ok    \(label)" : "  BŁĄD  \(label)")
    if !condition { exit(1) }
}

let decoder = JSONDecoder()

let plan = try decoder.decode(AgentCardDTO.self, from: Data(planWeekJSON.utf8))
guard case .planWeek(let week) = plan else {
    print("  BŁĄD  karta propozycji nie zdekodowała się"); exit(1)
}
check("tytuł liczy serwer", week.title == "Obiad i kolacja na tydzień")
check("dni w kolejności tygodnia", week.days.map(\.dayLabel) == ["Poniedziałek", "Wtorek"])
check("etykiety posiłków przychodzą gotowe", week.days[0].slots.map(\.mealLabel) == ["Obiad", "Kolacja"])
check("kalorie dnia policzone", week.days[0].kcalTotal == 1000)
check("zmiana odróżniona od tego, co zostaje", week.days[0].slots[0].isNew && !week.days[0].slots[1].isNew)
check("co zniknie z planu", week.removed.first?.title == "Zupa pomidorowa")
check("cel z preferencji domownika", week.summary.targetKcalPerDay == 2100)
check("średnia dzienna", week.summary.averageKcalPerDay > 0)
check("przycisk zatwierdzenia", week.actions.contains { $0.type == .apply })
check("stan pozwala kliknąć", week.state.canApply && !week.state.canUndo)
check("akcja niesie id propozycji", week.actions.first { $0.type == .apply }?.proposalId == week.proposalId)

let done = try decoder.decode(AgentCardDTO.self, from: Data(appliedJSON.utf8))
guard case .applied(let applied) = done else {
    print("  BŁĄD  karta potwierdzenia nie zdekodowała się"); exit(1)
}
check("„Cofnij” jest w wiadomości, nie w toaście", applied.actions.contains { $0.type == .undo })
check("skrót do planu tygodnia", applied.actions.contains { $0.type == .openPlan })
check("ostrzeżenie o odhaczonych posiłkach", applied.notes.contains { $0.contains("zjedzone") })
check("stan pozwala cofnąć", applied.state.canUndo && !applied.state.canApply)

let unknown = try decoder.decode(AgentCardDTO.self, from: Data(unknownJSON.utf8))
check("nieznany rodzaj karty NIE wywraca rozmowy", unknown == .unknown)
let broken = try decoder.decode(AgentCardDTO.self, from: Data(brokenJSON.utf8))
check("kaleka karta NIE wywraca rozmowy", broken == .unknown)

let after = AgentCardStateDTO(status: "APPLIED", canApply: false, canUndo: true, until: nil)
let patched = plan.withState(after)
check("po zapisie karta propozycji gaśnie", patched.state?.canApply == false)
check("podmiana stanu nie gubi treści", {
    if case .planWeek(let card) = patched { return card.days.count == 2 }
    return false
}())

print("\nKontrakt kart: wszystko się zgadza.")
