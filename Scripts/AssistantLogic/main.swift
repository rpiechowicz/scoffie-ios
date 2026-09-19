import Foundation

// Test priorytetów briefingu asystenta — czysta logika, bez SwiftUI.
//
// Projekt nie ma targetu testów, więc to jest jedyny sprawdzian tego, że
// „wyczerpana pula zawsze wygrywa”, „pusty tydzień bije pusty następny”,
// „pusty obiad po 16:00 nie robi briefingu” itd. Uruchomienie:
//   sh Scripts/assistant-logic-check.sh

var failures = 0

func check(_ label: String, _ condition: Bool) {
    print(condition ? "  ok    \(label)" : "  BŁĄD  \(label)")
    if !condition { failures += 1 }
}

let cal: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Warsaw") ?? .current
    calendar.locale = Locale(identifier: "pl_PL")
    return calendar
}()

func date(_ day: Int, month: Int = 9, hour: Int = 14, minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

/// Poniedziałek 14.09.2026; czwartek = 17.09.
let monday = date(14, hour: 0)
let nextMonday = date(21, hour: 0)

func day(_ offset: Int, from start: Date, filled: [AssistantBriefingSlot]) -> AssistantBriefingDay {
    let d = cal.date(byAdding: .day, value: offset, to: start)!
    return AssistantBriefingDay(
        date: d,
        enabledSlots: [.breakfast, .lunch, .dinner],
        meals: filled.map { AssistantBriefingDay.Meal(slot: $0, title: "Danie", kcal: 500, imageURL: nil) }
    )
}

func week(from start: Date, planned: Int, filled: [AssistantBriefingSlot] = [.breakfast, .lunch, .dinner]) -> [AssistantBriefingDay] {
    (0..<7).map { day($0, from: start, filled: $0 < planned ? filled : []) }
}

func context(now: Date, thisWeek: [AssistantBriefingDay], nextWeek: [AssistantBriefingDay]) -> AssistantBriefingContext {
    AssistantBriefingContext(now: now, calendar: cal, displayName: "Rafał Piechowicz", thisWeek: thisWeek, nextWeek: nextWeek)
}

func resolve(_ c: AssistantBriefingContext) -> AssistantBriefing {
    AssistantBriefingResolver.resolve(c)
}

extension AssistantBriefingContext {
    func withTrial() -> AssistantBriefingContext { var c = self; c.trialExhausted = true; return c }
}

print("PRIORYTETY")

// Czwartek 14:00, wszystko zaplanowane.
let thursday = date(17, hour: 14)
var full = context(now: thursday, thisWeek: week(from: monday, planned: 7), nextWeek: week(from: nextMonday, planned: 7))

full.trialExhausted = true
full.isNewUser = true
check("wyczerpana pula wygrywa ze wszystkim", resolve(full).kind == .trialExhausted)
check("pula: zero podpowiedzi do wysłania", resolve(full).secondary.allSatisfy { if case .ask = $0.kind { return false } else { return true } })
check("pula: akcja główna otwiera plany", resolve(full).primary.kind == .openPlans)
full.trialExhausted = false

check("nowe konto przed pustym tygodniem", resolve(full).kind == .newUser)
full.isNewUser = false

var empty = context(now: thursday, thisWeek: week(from: monday, planned: 0), nextWeek: week(from: nextMonday, planned: 0))
check("pusty bieżący tydzień bije pusty następny", resolve(empty).kind == .weekEmpty)
check("pusty tydzień: 0 z 7 w podsumowaniu", resolve(empty).summary?.sentence == "0 z 7 dni zaplanowanych")
check("pusty tydzień: siedem kółek", { if case .week(let marks) = resolve(empty).visual { return marks.count == 7 && marks.allSatisfy { $0.state == .empty } } else { return false } }())
check("pusty tydzień: dwie podpowiedzi", resolve(empty).secondary.count == 2)

// Pon–śr zaplanowane, czwartek pusty, 14:00 → dziś pusto.
var todayEmpty = context(now: thursday, thisWeek: week(from: monday, planned: 3), nextWeek: week(from: nextMonday, planned: 7))
check("dziś pusto bije jutro", resolve(todayEmpty).kind == .todayEmpty)
check("dziś pusto: oś trzech posiłków", { if case .day(let label, let marks) = resolve(todayEmpty).visual { return label == "Dziś" && marks.count == 3 && marks.allSatisfy { !$0.filled } } else { return false } }())
check("dziś pusto: 0 z 3 posiłków", resolve(todayEmpty).summary?.sentence == "0 z 3 posiłków")
check("dziś pusto: eyebrow i data", resolve(todayEmpty).eyebrow == "Na dziś" && resolve(todayEmpty).dateLabel == "Czw 17 wrz")

// Wieczór 19:00: dziś pusto, ale po 20 liczy się jutro; o 19 nadal dziś.
todayEmpty.now = date(17, hour: 19)
check("o 19:00 dziś pusto nadal wygrywa", resolve(todayEmpty).kind == .todayEmpty)
todayEmpty.now = date(17, hour: 21)
check("o 21:00 pusty dzisiejszy dzień oddaje miejsce jutru", resolve(todayEmpty).kind == .tomorrowEmpty)

// Wieczór + jutro puste (dziś jest plan).
var eve = context(now: date(17, hour: 19), thisWeek: week(from: monday, planned: 4), nextWeek: week(from: nextMonday, planned: 7))
check("wieczór + jutro puste", resolve(eve).kind == .tomorrowEmpty)
check("jutro: nadtytuł mówi o jutrze", resolve(eve).eyebrow == "Na jutro")
eve.now = date(17, hour: 12)
check("w południe jutro puste nie jest jeszcze sprawą", resolve(eve).kind != .tomorrowEmpty)

// Brakująca kolacja o 14:00 (kolacja domyślnie 19:30).
var dinner = context(now: thursday, thisWeek: week(from: monday, planned: 7, filled: [.breakfast, .lunch]), nextWeek: week(from: nextMonday, planned: 7))
check("brakująca kolacja", resolve(dinner).kind == .missingMeal)
check("brakująca kolacja: nagłówek po polsku", resolve(dinner).headline == "Kolacja jest jeszcze pusta.")
check("brakująca kolacja: biernik w akcji", resolve(dinner).primary.title == "Dobierz kolację")
check("brakująca kolacja: 2 z 3 posiłków", resolve(dinner).summary?.sentence == "2 z 3 posiłków")
dinner.now = date(17, hour: 21)
check("po godzinie kolacji brak nie robi briefingu", resolve(dinner).kind != .missingMeal)
dinner.now = thursday
dinner.slotMinutes = [.dinner: 13 * 60]
check("własna godzina kolacji (13:00) już minęła o 14:00", resolve(dinner).kind != .missingMeal)

// Brak podwieczorku nie jest ważny.
let snackDay = (0..<7).map { offset -> AssistantBriefingDay in
    let d = cal.date(byAdding: .day, value: offset, to: monday)!
    return AssistantBriefingDay(date: d, enabledSlots: [.breakfast, .lunch, .afternoonSnack, .dinner], meals: [.breakfast, .lunch, .dinner].map { AssistantBriefingDay.Meal(slot: $0, title: "Danie", kcal: 500, imageURL: nil) })
}
let snack = context(now: thursday, thisWeek: snackDay, nextWeek: week(from: nextMonday, planned: 7))
check("pusty podwieczorek nie jest brakującym posiłkiem", resolve(snack).kind != .missingMeal)

// Sobota, przyszły tydzień pusty.
let saturday = date(19, hour: 11)
let nextEmpty = context(now: saturday, thisWeek: week(from: monday, planned: 7), nextWeek: week(from: nextMonday, planned: 0))
check("weekend + przyszły tydzień pusty", resolve(nextEmpty).kind == .nextWeekEmpty)
check("skróty dni jak na makiecie", { if case .week(let marks) = resolve(nextEmpty).visual { return marks.map(\.short) == ["Pn", "Wt", "Śr", "Cz", "Pt", "Sb", "Nd"] && marks.first?.dayNumber == "21" } else { return false } }())
check("każda akcja wtórna ma ikonę", resolve(nextEmpty).secondary.allSatisfy { $0.icon != nil })
check("briefing planujący ma dopisek o propozycji", resolve(nextEmpty).helper == "Najpierw pokażę propozycję do zatwierdzenia.")
let tuesdayNextEmpty = context(now: date(15, hour: 11), thisWeek: week(from: monday, planned: 7), nextWeek: week(from: nextMonday, planned: 0))
check("we wtorek pusty przyszły tydzień jeszcze nie woła", resolve(tuesdayNextEmpty).kind != .nextWeekEmpty)

// Bilans tylko przy realnych danych.
var balance = context(now: thursday, thisWeek: week(from: monday, planned: 7), nextWeek: week(from: nextMonday, planned: 7))
check("bez bilansu: tydzień gotowy", resolve(balance).kind == .weekReady)
balance.balance = AssistantBriefingBalance(macroGenitive: "białka", macroAccusative: "białko", unit: "g", averagePerDay: 116, target: 140, daysCounted: 5, daysBelowTarget: 4)
check("brak 24 g z 140 g to sprawa", resolve(balance).kind == .balanceIssue)
check("bilans: dni poniżej celu w podsumowaniu", resolve(balance).summary?.sentence == "Poniżej celu w 4 z 5 dni")
check("bilans: liczby w tekście", resolve(balance).supporting == "Średnio 24 g dziennie poniżej celu.")
balance.balance = AssistantBriefingBalance(macroGenitive: "białka", macroAccusative: "białko", unit: "g", averagePerDay: 134, target: 140, daysCounted: 5)
check("brak 6 g to szum, nie briefing", resolve(balance).kind == .weekReady)
balance.balance = AssistantBriefingBalance(macroGenitive: "białka", macroAccusative: "białko", unit: "g", averagePerDay: 100, target: 140, daysCounted: 2)
check("z dwóch dni nie liczy się średniej tygodnia", resolve(balance).kind == .weekReady)

// Dzień gotowy, ale weekend niezaplanowany.
let dayReady = context(now: thursday, thisWeek: week(from: monday, planned: 5), nextWeek: week(from: nextMonday, planned: 7))
check("dzień gotowy, tydzień nie", resolve(dayReady).kind == .dayReady)
check("dzień gotowy: dania dnia w ilustracji", { if case .meals(let meals) = resolve(dayReady).visual { return meals.count == 3 } else { return false } }())
check("dzień gotowy: tylko podgląd", resolve(dayReady).helper == "Bez zmian w planie — tylko podgląd.")

// Sobota z całym tygodniem: „gotowe” wygrywa z inspiracją.
let fullWeekend = context(now: saturday, thisWeek: week(from: monday, planned: 7), nextWeek: week(from: nextMonday, planned: 7))
check("weekend z pełnym tygodniem: plan gotowy", resolve(fullWeekend).kind == .weekReady)

// Sobota z planem na dziś, niedziela pusta, nic pilnego → inspiracja.
let weekend = context(now: saturday, thisWeek: week(from: monday, planned: 6), nextWeek: week(from: nextMonday, planned: 7))
check("weekend z planem na dziś: inspiracja", resolve(weekend).kind == .weekendInspiration)
check("weekend: zakres soboty i niedzieli", resolve(weekend).dateLabel == "19–20 wrz")
check("weekend: trzy miniatury", { if case .teaser(let urls) = resolve(weekend).visual { return urls.count == 3 } else { return false } }())
check("pula: znak wyciszony", { if case .brand(let muted) = resolve(full.withTrial()).visual { return muted } else { return false } }())

print("TEKSTY")
check("powitanie rano", AssistantBriefingResolver.greeting(hour: 8, name: "Rafał") == "Dzień dobry, Rafał")
check("powitanie wieczorem bez imienia", AssistantBriefingResolver.greeting(hour: 20, name: nil) == "Dobry wieczór")
check("imię z pełnej nazwy", AssistantBriefingResolver.firstName("Rafał Piechowicz") == "Rafał")
check("login nie jest imieniem", AssistantBriefingResolver.firstName("rpiechowicz") == nil)
check("e-mail nie jest imieniem", AssistantBriefingResolver.firstName("Rafal@x.pl") == nil)
check("zakres tygodnia", AssistantBriefingResolver.rangeLabel(week(from: monday, planned: 0), cal) == "14–20 wrz")
check("zakres przez miesiące", AssistantBriefingResolver.rangeLabel(week(from: date(28, hour: 0), planned: 0), cal) == "28 wrz – 4 paź")
check("godzina", AssistantBriefingResolver.clock(19 * 60 + 5) == "19:05")
check("każdy briefing ma najwyżej dwie podpowiedzi", [empty, todayEmpty, eve, dinner, nextEmpty, balance, dayReady, weekend].allSatisfy { resolve($0).secondary.count <= 2 })

if failures > 0 {
    print("\n\(failures) błędów")
    exit(1)
}
print("\nwszystko ok")
