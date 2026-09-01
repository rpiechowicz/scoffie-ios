import Foundation

// Sprawdzian kontraktu: JSON policzony przez SERWER wchodzi w struktury iOS.
// Cichy rozjazd nazwy pola nie wywala niczego — karta po prostu staje się
// `.unknown` i znika z ekranu. Ten skrypt zamienia to w twardy błąd.
//
// Wzorce pochodzą z `scripts/dump-card-fixtures.ts` w backendzie i są
// DOSŁOWNĄ odpowiedzią builderów, nie ręcznie pisanym JSON-em.

let planWeekJSON = #"{"kind": "PLAN_WEEK", "v": 1, "proposalId": "55555555-5555-4555-8555-555555555555", "weekStart": "2026-08-31", "eyebrow": "Propozycja planu", "eyebrowDetail": "31 sierpnia – 6 września", "title": "Obiad i kolacja na tydzień", "subtitle": "Nic się nie powtarza, a wtorek jest szybki.", "days": [{"dayOfWeek": "MON", "dayLabel": "Poniedziałek", "dayShort": "Pon", "date": "2026-08-31", "dateLabel": "31.08", "slots": [{"mealType": "LUNCH", "mealLabel": "Obiad", "recipeId": "r-1", "title": "Kurczak z ryżem", "kcalPerServing": 620, "prepTimeMinutes": 30, "imageUrl": "https://example.invalid/kurczak.png", "participantIds": [], "change": "NEW"}, {"mealType": "DINNER", "mealLabel": "Kolacja", "recipeId": "r-2", "title": "Sałatka z tuńczykiem", "kcalPerServing": 380, "prepTimeMinutes": 12, "imageUrl": null, "participantIds": ["u1"], "change": "KEPT"}], "kcalTotal": 1000}, {"dayOfWeek": "TUE", "dayLabel": "Wtorek", "dayShort": "Wt", "date": "2026-09-01", "dateLabel": "1.09", "slots": [{"mealType": "DINNER", "mealLabel": "Kolacja", "recipeId": "r-3", "title": "Placki ziemniaczane", "kcalPerServing": 540, "prepTimeMinutes": 40, "imageUrl": null, "participantIds": [], "change": "NEW"}], "kcalTotal": 540}], "removed": [{"dayLabel": "Środa", "mealLabel": "Kolacja", "title": "Zupa pomidorowa"}], "summary": {"meals": 3, "created": 2, "updated": 0, "removed": 1, "averageKcalPerDay": 770, "targetKcalPerDay": 2100, "goalNote": "1330 kcal poniżej celu"}, "actions": [{"type": "APPLY", "proposalId": "55555555-5555-4555-8555-555555555555", "label": "Dodaj do planu", "style": "PRIMARY"}], "state": {"status": "PENDING", "canApply": true, "canUndo": false, "until": "2026-09-03T10:00:00.000Z"}}"#
let planDayJSON = #"{"kind": "PLAN_DAY", "v": 1, "proposalId": "66666666-6666-4666-8666-666666666666", "weekStart": "2026-08-31", "date": "2026-09-01", "eyebrow": "Propozycja dnia", "eyebrowDetail": "wtorek, 1 września", "title": "Cały dzień pod cel 2100 kcal", "subtitle": "Lekki wieczór po ciężkim obiedzie.", "slots": [{"mealType": "BREAKFAST", "mealLabel": "Śniadanie", "recipeId": "r-4", "title": "Owsianka z bananem", "kcalPerServing": 447, "prepTimeMinutes": 12, "imageUrl": null, "participantIds": [], "change": "NEW"}, {"mealType": "LUNCH", "mealLabel": "Obiad", "recipeId": "r-1", "title": "Kurczak w sosie curry z ryżem", "kcalPerServing": 620, "prepTimeMinutes": 35, "imageUrl": null, "participantIds": [], "change": "KEPT"}, {"mealType": "DINNER", "mealLabel": "Kolacja", "recipeId": "r-5", "title": "Omlet ze szpinakiem i fetą", "kcalPerServing": 393, "prepTimeMinutes": 12, "imageUrl": null, "participantIds": [], "change": "NEW"}], "removed": [{"dayLabel": "Wtorek", "mealLabel": "Kolacja", "title": "Pizza mrożona"}], "summary": {"meals": 3, "kcalTotal": 1460, "targetKcalPerDay": 2100, "goalNote": "zostaje 640"}, "actions": [{"type": "APPLY", "proposalId": "66666666-6666-4666-8666-666666666666", "label": "Zapisz wtorek", "style": "PRIMARY"}], "state": {"status": "PENDING", "canApply": true, "canUndo": false, "until": "2026-09-03T10:00:00.000Z"}}"#
let clarifyJSON = #"{"kind": "CLARIFY", "v": 1, "question": "Dla ilu osób mam planować ten tydzień?", "hint": "W profilu są cztery osoby, ale wspominałeś o weekendzie we dwoje.", "actions": [{"type": "ASK", "proposalId": null, "label": "Dla czterech", "style": "PRIMARY", "prompt": "Dla czterech"}, {"type": "ASK", "proposalId": null, "label": "Dla dwóch", "style": "SECONDARY", "prompt": "Dla dwóch"}, {"type": "ASK", "proposalId": null, "label": "Inaczej w weekend", "style": "SECONDARY", "prompt": "Inaczej w weekend"}]}"#
let optionsJSON = #"{"kind": "OPTIONS", "v": 1, "eyebrow": "Kolacja · wtorek", "title": "Trzy szybkie kolacje", "options": [{"recipeId": "r-5", "title": "Omlet ze szpinakiem i fetą", "kcalPerServing": 393, "prepTimeMinutes": 12, "imageUrl": "https://example.invalid/omlet.jpg", "tag": "Najszybsze", "prompt": "Wybieram: Omlet ze szpinakiem i fetą"}, {"recipeId": "r-7", "title": "Sałatka z tuńczykiem", "kcalPerServing": 340, "prepTimeMinutes": 15, "imageUrl": null, "tag": null, "prompt": "Wybieram: Sałatka z tuńczykiem"}, {"recipeId": "r-8", "title": "Tost z awokado i jajkiem", "kcalPerServing": 420, "prepTimeMinutes": 10, "imageUrl": null, "tag": "Najwięcej białka", "prompt": "Wybieram: Tost z awokado i jajkiem"}], "actions": [{"type": "ASK", "proposalId": null, "label": "Coś innego", "style": "SECONDARY", "prompt": "Żadne z tych mi nie pasuje. Zaproponuj coś innego."}]}"#
let swapJSON = #"{"kind": "SWAP", "v": 1, "proposalId": "77777777-7777-4777-8777-777777777777", "weekStart": "2026-08-31", "date": "2026-09-01", "eyebrow": "Podmiana · wtorek, kolacja", "title": "Szybciej o 43 min", "from": {"recipeId": "r-1", "title": "Gulasz wołowy z kaszą", "kcalPerServing": 720, "prepTimeMinutes": 55}, "to": {"recipeId": "r-5", "title": "Omlet ze szpinakiem i fetą", "kcalPerServing": 393, "prepTimeMinutes": 12}, "deltas": [{"value": "−43 min", "label": "szybciej", "good": true}, {"value": "−327 kcal", "label": "na porcję", "good": true}], "actions": [{"type": "APPLY", "proposalId": "77777777-7777-4777-8777-777777777777", "label": "Podmień", "style": "PRIMARY"}], "state": {"status": "PENDING", "canApply": true, "canUndo": false, "until": "2026-09-03T10:00:00.000Z"}}"#
let splitJSON = #"{"kind": "HOUSEHOLD_SPLIT", "v": 1, "proposalId": "88888888-8888-4888-8888-888888888888", "weekStart": "2026-08-31", "date": "2026-09-02", "eyebrow": "Jedna baza · trzy porcje", "title": "Gulasz wołowy z kaszą gryczaną", "prepTimeMinutes": 55, "portions": [{"userId": "u-1", "displayName": "Rafał", "goalLabel": "2100 kcal", "note": "Duża porcja + kasza 100 g", "kcal": 740}, {"userId": "u-2", "displayName": "Ania", "goalLabel": "1750 kcal · wegetariańska", "note": "Bez mięsa, więcej kaszy", "kcal": 590}, {"userId": "u-3", "displayName": "Zosia", "goalLabel": "1400 kcal · bez laktozy", "note": "Śmietana osobno", "kcal": 420}], "actions": [{"type": "APPLY", "proposalId": "88888888-8888-4888-8888-888888888888", "label": "Zapisz na środę", "style": "PRIMARY"}], "state": {"status": "PENDING", "canApply": true, "canUndo": false, "until": "2026-09-03T10:00:00.000Z"}}"#
let macroJSON = #"{"kind": "MACRO_GAP", "v": 1, "eyebrow": "Białko · ten tydzień", "title": "Brakuje średnio 44 g dziennie", "macro": "PROTEIN", "unit": "g", "current": 96, "target": 140, "boosters": [{"text": "Twarożek zamiast musli (śr.)", "amount": 24}, {"text": "Jogurt grecki do owsianki (pon., czw.)", "amount": 18}, {"text": "Kurczak zamiast makaronu na kolację (pt.)", "amount": 22}], "actions": [{"type": "ASK", "proposalId": null, "label": "Zastosuj wszystkie trzy", "style": "PRIMARY", "prompt": "Zastosuj te zmiany w planie i pokaż mi je jako propozycję."}]}"#
let shoppingJSON = #"{"kind": "SHOPPING_LIST", "v": 1, "weekStart": "2026-08-31", "eyebrow": "Lista zakupów · 31 sierpnia – 6 września", "title": "4 rzeczy do kupienia", "groups": [{"department": "Warzywa", "items": ["Cukinia 2 szt.", "Dynia 1 kg"]}, {"department": "Ryby", "items": ["Dorsz 600 g"]}, {"department": "Nabiał", "items": ["Feta 2 op."]}], "summary": {"remaining": 4, "checked": 1}, "checkedNote": "1 pozycja już odhaczona", "actions": [{"type": "OPEN_SHOPPING", "proposalId": null, "label": "Otwórz listę zakupów", "style": "PRIMARY"}]}"#
let detectedJSON = #"{"kind": "DETECTED_ITEMS", "v": 1, "eyebrow": "Ze zdjęcia", "title": "Widzę 3 produkty, 1 niepewny", "items": [{"name": "Jajka", "sure": true}, {"name": "Ser żółty", "sure": true}, {"name": "Coś w folii na dolnej półce", "sure": false}], "actions": [{"type": "ASK", "proposalId": null, "label": "Popraw listę", "style": "SECONDARY", "prompt": "Popraw listę: "}]}"#
let appliedJSON = #"{"kind": "APPLIED", "v": 1, "proposalId": "55555555-5555-4555-8555-555555555555", "weekStart": "2026-08-31", "title": "Zapisano w planie", "subtitle": "2 nowe pozycje, 1 usunięta · 31 sierpnia – 6 września", "summary": {"created": 2, "updated": 0, "removed": 1}, "notes": ["Cofnięcie przywróci usunięte posiłki, ale nie odhaczenia „zjedzone”."], "actions": [{"type": "UNDO", "proposalId": "55555555-5555-4555-8555-555555555555", "label": "Cofnij", "style": "SECONDARY"}, {"type": "OPEN_PLAN", "proposalId": null, "label": "Otwórz Plan tygodnia", "style": "PRIMARY"}], "state": {"status": "APPLIED", "canApply": false, "canUndo": true, "until": "2026-08-31T11:00:00.000Z"}}"#
let unknownJSON = #"{"kind":"MACRO_GAP","v":1,"cokolwiek":true}"#
let brokenJSON = #"{"kind":"PLAN_WEEK","v":1}"#

func check(_ label: String, _ condition: Bool) {
    print(condition ? "  ok    \(label)" : "  BŁĄD  \(label)")
    if !condition { exit(1) }
}

let decoder = JSONDecoder()
func card(_ json: String) -> AgentCardDTO {
    // swiftlint:disable:next force_try
    try! decoder.decode(AgentCardDTO.self, from: Data(json.utf8))
}

print("PLAN_WEEK")
guard case .planWeek(let week) = card(planWeekJSON) else {
    print("  BŁĄD  karta propozycji tygodnia nie zdekodowała się"); exit(1)
}
check("nadtytuł bez daty w środku", week.eyebrow == "Propozycja planu")
check("data w osobnym wierszu", week.eyebrowDetail == "31 sierpnia – 6 września")
check("miniatura dania, gdy przepis ją ma", week.days[0].slots[0].imageUrl != nil)
check("brak zdjęcia to nie błąd", week.days[0].slots[1].imageUrl == nil)
check("tytuł liczy serwer", week.title == "Obiad i kolacja na tydzień")
check("dni w kolejności tygodnia", week.days.map(\.dayLabel) == ["Poniedziałek", "Wtorek"])
check("skrót dnia i krótka data", week.days[0].shortName == "Pon" && week.days[0].dateLabel == "31.08")
check("etykiety posiłków przychodzą gotowe", week.days[0].slots.map(\.mealLabel) == ["Obiad", "Kolacja"])
check("kalorie dnia policzone", week.days[0].kcalTotal == 1000)
check("zmiana odróżniona od tego, co zostaje", week.days[0].slots[0].isNew && !week.days[0].slots[1].isNew)
check("co zniknie z planu", week.removed.first?.title == "Zupa pomidorowa")
check("cel z preferencji domownika", week.summary.targetKcalPerDay == 2100)
check("zdanie o celu, nie sama liczba", week.summary.goalNote?.isEmpty == false)
check("przycisk zatwierdzenia", week.actions.contains { $0.type == .apply })
check("stan pozwala kliknąć", week.state.canApply && !week.state.canUndo)
check("akcja niesie id propozycji", week.actions.first { $0.type == .apply }?.proposalId == week.proposalId)

print("PLAN_DAY")
guard case .planDay(let day) = card(planDayJSON) else {
    print("  BŁĄD  karta dnia nie zdekodowała się"); exit(1)
}
check("wyłącznie ten dzień", day.slots.count == 3)
check("posiłki w porządku dnia", day.slots.map(\.mealLabel) == ["Śniadanie", "Obiad", "Kolacja"])
check("suma dnia", day.summary.kcalTotal == 1460)
check("ile jeszcze wchodzi w cel", day.summary.goalNote == "zostaje 640")
check("usunięcia tylko z tego dnia", day.removed.count == 1)
check("przycisk nazywa dzień", day.actions.first { $0.type == .apply }?.label == "Zapisz wtorek")

print("OPTIONS")
guard case .options(let options) = card(optionsJSON) else {
    print("  BŁĄD  karta wyboru nie zdekodowała się"); exit(1)
}
check("kafelki z katalogu", options.options.count == 3)
check("nazwa, kalorie i czas z bazy", options.options[0].kcalPerServing == 393 && options.options[0].prepTimeMinutes == 12)
check("zdjęcie bywa puste i to nie jest błąd", options.options[1].imageUrl == nil)
check("wyróżnik pokazuje się tylko tam, gdzie jest", options.options[0].tag == "Najszybsze" && options.options[1].tag == nil)
check("dotknięcie wysyła wybór jako wiadomość", options.options[0].prompt.hasPrefix("Wybieram: "))
check("zawsze jest wyjście „coś innego”", options.actions.contains { $0.type == .ask })
check("wybór nie ma stanu i nie udaje, że ma", card(optionsJSON).state == nil)

print("SWAP")
guard case .swap(let swap) = card(swapJSON) else {
    print("  BŁĄD  karta podmiany nie zdekodowała się"); exit(1)
}
check("obie strony podmiany", swap.from?.title == "Gulasz wołowy z kaszą" && swap.to.title == "Omlet ze szpinakiem i fetą")
check("tytuł nazywa największą różnicę", swap.title == "Szybciej o 43 min")
check("różnice mają znak i kierunek", swap.deltas.map(\.value) == ["−43 min", "−327 kcal"])
check("zysk odróżniony od straty", swap.deltas.allSatisfy(\.good))
check("podmiana czeka na kliknięcie", swap.state.canApply)

print("HOUSEHOLD_SPLIT")
guard case .householdSplit(let split) = card(splitJSON) else {
    print("  BŁĄD  karta podziału nie zdekodowała się"); exit(1)
}
check("nadtytuł liczy talerze", split.eyebrow == "Jedna baza · trzy porcje")
check("przy imieniu stoi JEGO cel", split.portions[2].goalLabel.contains("bez laktozy"))
check("sposób podania od modelu", split.portions[2].note == "Śmietana osobno")
check("inicjał do awatara", split.portions[0].initial == "R")
check("przycisk mówi zdaniem", split.actions.first { $0.type == .apply }?.label == "Zapisz na środę")

print("MACRO_GAP")
guard case .macroGap(let macro) = card(macroJSON) else {
    print("  BŁĄD  karta makro nie zdekodowała się"); exit(1)
}
check("brak stoi w tytule", macro.title == "Brakuje średnio 44 g dziennie")
check("jednostka z serwera", macro.unit == "g")
check("pasek liczy się z obu liczb", abs(macro.progress - 96.0 / 140.0) < 0.001)
check("trzy zmiany z kwotami", macro.boosters.count == 3 && macro.boosters[0].amount == 24)
check("zastosowanie wysyła wiadomość, nie zapisuje", macro.actions.allSatisfy { $0.type == .ask })
check("analiza nie ma stanu do kliknięcia", card(macroJSON).state == nil)

print("SHOPPING_LIST")
guard case .shoppingList(let shopping) = card(shoppingJSON) else {
    print("  BŁĄD  karta zakupów nie zdekodowała się"); exit(1)
}
check("działy w kolejności sklepu", shopping.groups.map(\.department) == ["Warzywa", "Ryby", "Nabiał"])
check("pozycja z ilością i jednostką", shopping.groups[2].items == ["Feta 2 op."])
check("odhaczone poza listą, ale w rachunku", shopping.summary.checked == 1 && shopping.summary.remaining == 4)
check("odmiana idzie za liczbą", shopping.checkedNote == "1 pozycja już odhaczona")
check("jedyna akcja otwiera listę", shopping.actions.first?.type == .openShopping)

print("DETECTED_ITEMS")
guard case .detectedItems(let detected) = card(detectedJSON) else {
    print("  BŁĄD  karta rozpoznanych nie zdekodowała się"); exit(1)
}
check("pewne przed niepewnymi", detected.items.map(\.sure) == [true, true, false])
check("tytuł mówi, ile jest niepewne", detected.title.contains("niepewny"))
check("da się poprawić listę", detected.actions.first?.type == .ask)
check("rozpoznanie nic nie zapisuje", card(detectedJSON).state == nil)

print("CLARIFY")
guard case .clarify(let clarify) = card(clarifyJSON) else {
    print("  BŁĄD  karta pytania nie zdekodowała się"); exit(1)
}
check("pytanie i powód", !clarify.question.isEmpty && clarify.hint?.isEmpty == false)
check("odpowiedzi to zwykłe wiadomości", clarify.actions.allSatisfy { $0.type == .ask })
check("każda odpowiedź niesie treść do wysłania", clarify.actions.allSatisfy { ($0.prompt ?? "").isEmpty == false })
check("pierwsza odpowiedź wyróżniona", clarify.actions.first?.isPrimary == true)
check("pytanie ZASTĘPUJE tekst wiadomości", card(clarifyJSON).replacesText)
check("propozycja NIE zastępuje tekstu", !card(planWeekJSON).replacesText)

print("APPLIED")
guard case .applied(let applied) = card(appliedJSON) else {
    print("  BŁĄD  karta potwierdzenia nie zdekodowała się"); exit(1)
}
check("podtytuł mówi, co się stało", applied.subtitle?.contains("nowe pozycje") == true)
check("„Cofnij” jest w wiadomości, nie w toaście", applied.actions.contains { $0.type == .undo })
check("skrót do planu tygodnia", applied.actions.contains { $0.type == .openPlan })
check("ostrzeżenie o odhaczonych posiłkach", applied.notes.contains { $0.contains("zjedzone") })
check("stan pozwala cofnąć", applied.state.canUndo && !applied.state.canApply)

print("zgodność wstecz")
check("nieznany rodzaj karty NIE wywraca rozmowy", card(unknownJSON) == .unknown)
check("kaleka karta NIE wywraca rozmowy", card(brokenJSON) == .unknown)

let after = AgentCardStateDTO(status: "APPLIED", canApply: false, canUndo: true, until: nil)
check("po zapisie karta propozycji gaśnie", card(planWeekJSON).withState(after).state?.canApply == false)
check("to samo dla karty dnia", card(planDayJSON).withState(after).state?.canApply == false)
check("to samo dla podmiany", card(swapJSON).withState(after).state?.canApply == false)
check("wybór nie ma stanu do podmiany", card(optionsJSON).withState(after).state == nil)
check("pytanie nie ma stanu i nie udaje, że ma", card(clarifyJSON).withState(after).state == nil)
check("podmiana stanu nie gubi treści", {
    if case .planWeek(let c) = card(planWeekJSON).withState(after) { return c.days.count == 2 }
    return false
}())

print("\nKontrakt kart: wszystko się zgadza.")
