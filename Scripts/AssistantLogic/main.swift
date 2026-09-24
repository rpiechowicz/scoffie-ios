import Foundation

// Test priorytetów powitania asystenta — czysta logika, bez SwiftUI.
//
// Projekt nie ma targetu testów, więc to jest jedyny sprawdzian tego, że
// „wyczerpana pula zawsze wygrywa”, „pusty tydzień bije pusty następny”,
// „pusty obiad po 16:00 nie robi powitania” itd. Uruchomienie:
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
        meals: filled.map { AssistantBriefingDay.Meal(slot: $0, title: "Danie", kcal: 500, imageURL: nil, minutes: 20) }
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

func plates(_ b: AssistantBriefing) -> [AssistantBriefing.Plate] {
    if case .plates(let plates) = b.visual { return plates }
    return []
}

func asks(_ action: AssistantBriefing.Action) -> String? {
    if case .ask(let prompt) = action.kind { return prompt }
    return nil
}

print("PRIORYTETY")

// Czwartek 16:00, wszystko zaplanowane (poza oknem „zaraz obiad/kolacja”).
let thursday = date(17, hour: 16)
var full = context(now: thursday, thisWeek: week(from: monday, planned: 7), nextWeek: week(from: nextMonday, planned: 7))

full.trialExhausted = true
full.isNewUser = true
check("wyczerpana pula wygrywa ze wszystkim", resolve(full).kind == .trialExhausted)
check("pula: nic do wysłania", ([resolve(full).primary] + resolve(full).alternatives).allSatisfy { asks($0) == nil })
check("pula: akcja główna otwiera plany", resolve(full).primary.kind == .openPlans)
full.trialExhausted = false

check("nowe konto przed pustym tygodniem", resolve(full).kind == .newUser)
check("nowe konto: imię w otwarciu", resolve(full).headline == "Cześć, Rafał. Od czego zaczniemy?")
full.isNewUser = false

// Późna pora.
var late = context(now: date(17, hour: 23), thisWeek: week(from: monday, planned: 4), nextWeek: week(from: nextMonday, planned: 7))
check("23:00 i jutro puste: późna pora", resolve(late).kind == .lateNight)
check("późna pora: talerzyki jutra", plates(resolve(late)).count == 3 && plates(resolve(late)).allSatisfy { !$0.filled })
late.thisWeek = week(from: monday, planned: 7)
check("23:00 i jutro gotowe: nadal późna pora, inne otwarcie", resolve(late).kind == .lateNight && resolve(late).headline == "Jutro jest już w planie.")

var empty = context(now: thursday, thisWeek: week(from: monday, planned: 0), nextWeek: week(from: nextMonday, planned: 0))
check("pusty bieżący tydzień bije pusty następny", resolve(empty).kind == .weekEmpty)
check("pusty tydzień: jedna alternatywa + „Mam inny pomysł”", resolve(empty).alternatives.count == 2 && resolve(empty).alternatives.last?.kind == .compose)
let sundayEmpty = context(now: date(20, hour: 11), thisWeek: week(from: monday, planned: 0), nextWeek: week(from: nextMonday, planned: 0))
check("niedziela: pustego bieżącego tygodnia już się nie planuje", resolve(sundayEmpty).kind != .weekEmpty)

// Pon–śr zaplanowane, czwartek pusty.
var todayEmpty = context(now: date(17, hour: 12), thisWeek: week(from: monday, planned: 3), nextWeek: week(from: nextMonday, planned: 7))
check("dziś pusto bije jutro", resolve(todayEmpty).kind == .todayEmpty)
check("dziś pusto: podświetlona najbliższa pora (obiad)", plates(resolve(todayEmpty)).first { $0.isFocus }?.id == "lunch")
check("dziś pusto: pomysły na obiad do wyboru", asks(resolve(todayEmpty).alternatives[0]) == "Pokaż 3 pomysły na obiad na dziś do wyboru")
todayEmpty.now = date(17, hour: 19)
check("o 19:00 dziś pusto nadal wygrywa", resolve(todayEmpty).kind == .todayEmpty)
todayEmpty.now = date(17, hour: 21)
check("o 21:00 pusty dzisiejszy dzień oddaje miejsce jutru", resolve(todayEmpty).kind == .tomorrowEmpty)

// Zaraz obiad.
var soon = context(now: date(17, hour: 13, minute: 20), thisWeek: week(from: monday, planned: 7), nextWeek: week(from: nextMonday, planned: 7))
check("obiad o 14:00, jest 13:20: zaraz gotowanie", resolve(soon).kind == .cookSoon)
check("zaraz gotowanie: otwarcie z minutami", resolve(soon).headline == "Za 40 minut obiad.")
check("zaraz gotowanie: danie w podglądzie", { if case .meal(let meal) = resolve(soon).visual { return meal.eyebrow == "Obiad · 14:00" && meal.minutes == 20 } else { return false } }())
soon.now = date(17, hour: 12)
check("dwie godziny przed obiadem to jeszcze nie „zaraz”", resolve(soon).kind != .cookSoon)
check("odmiana minut", AssistantBriefingResolver.minutesWord(1) == "minutę" && AssistantBriefingResolver.minutesWord(22) == "minuty" && AssistantBriefingResolver.minutesWord(12) == "minut")

// Brakująca kolacja o 16:00 (kolacja domyślnie 19:30).
var dinner = context(now: thursday, thisWeek: week(from: monday, planned: 7, filled: [.breakfast, .lunch]), nextWeek: week(from: nextMonday, planned: 7))
check("brakująca kolacja", resolve(dinner).kind == .dinnerMissing)
check("brakująca kolacja: pytanie po polsku", resolve(dinner).headline == "Co dziś na kolację?")
check("brakująca kolacja: dania do wyboru", asks(resolve(dinner).primary) == "Pokaż 3 pomysły na kolację na dziś do wyboru")
check("brakująca kolacja: podświetlona kolacja", plates(resolve(dinner)).first { $0.isFocus }?.id == "dinner")
dinner.now = date(17, hour: 21)
check("po godzinie kolacji brak nie robi powitania", resolve(dinner).kind != .dinnerMissing)
dinner.now = thursday
dinner.slotMinutes = [.dinner: 15 * 60]
check("własna godzina kolacji (15:00) już minęła o 16:00", resolve(dinner).kind != .dinnerMissing)

let breakfast = context(now: date(17, hour: 6), thisWeek: week(from: monday, planned: 7, filled: [.lunch, .dinner]), nextWeek: week(from: nextMonday, planned: 7))
check("rano brak śniadania", resolve(breakfast).kind == .breakfastMissing)

// Brak podwieczorku nie jest ważny.
let snackDay = (0..<7).map { offset -> AssistantBriefingDay in
    let d = cal.date(byAdding: .day, value: offset, to: monday)!
    return AssistantBriefingDay(date: d, enabledSlots: [.breakfast, .lunch, .afternoonSnack, .dinner], meals: [.breakfast, .lunch, .dinner].map { AssistantBriefingDay.Meal(slot: $0, title: "Danie", kcal: 500, imageURL: nil) })
}
let snack = context(now: thursday, thisWeek: snackDay, nextWeek: week(from: nextMonday, planned: 7))
check("pusty podwieczorek nie jest brakującym posiłkiem", ![.breakfastMissing, .lunchMissing, .dinnerMissing].contains(resolve(snack).kind))

// Wieczór: jutro puste albo częściowe.
var eve = context(now: date(17, hour: 20), thisWeek: week(from: monday, planned: 4), nextWeek: week(from: nextMonday, planned: 7))
check("wieczór + jutro puste", resolve(eve).kind == .tomorrowEmpty)
var partial = week(from: monday, planned: 4)
partial[4] = day(4, from: monday, filled: [.lunch])
eve.thisWeek = partial
check("wieczór + jutro częściowe", resolve(eve).kind == .tomorrowPartial)
check("jutro częściowe: nazywa to, co jest", resolve(eve).headline == "Jutro masz już obiad. Dobierzemy resztę?")
check("jutro częściowe: podświetlone śniadanie", plates(resolve(eve)).first { $0.isFocus }?.id == "breakfast")
eve.now = date(17, hour: 16)
check("po południu jutro puste nie jest jeszcze sprawą", resolve(eve).kind != .tomorrowEmpty && resolve(eve).kind != .tomorrowPartial)

// Sobota, przyszły tydzień pusty.
let saturday = date(19, hour: 16)
let nextEmpty = context(now: saturday, thisWeek: week(from: monday, planned: 7), nextWeek: week(from: nextMonday, planned: 0))
check("weekend + przyszły tydzień pusty", resolve(nextEmpty).kind == .nextWeekEmpty)
let tuesdayNextEmpty = context(now: date(15, hour: 16), thisWeek: week(from: monday, planned: 7), nextWeek: week(from: nextMonday, planned: 0))
check("we wtorek pusty przyszły tydzień jeszcze nie woła", resolve(tuesdayNextEmpty).kind != .nextWeekEmpty)

// Bilans tylko przy realnych danych.
var balance = context(now: date(15, hour: 16), thisWeek: week(from: monday, planned: 7), nextWeek: week(from: nextMonday, planned: 7))
check("bez bilansu: tydzień gotowy", resolve(balance).kind == .weekReady)
balance.balance = AssistantBriefingBalance(macroGenitive: "białka", macroAccusative: "białko", unit: "g", averagePerDay: 116, target: 140, daysCounted: 5, daysBelowTarget: 4)
check("brak 24 g z 140 g to sprawa", resolve(balance).kind == .balanceIssue)
check("bilans: liczby w pasku", resolve(balance).visual == .balance(current: 116, target: 140, unit: "g"))
balance.balance = AssistantBriefingBalance(macroGenitive: "białka", macroAccusative: "białko", unit: "g", averagePerDay: 134, target: 140, daysCounted: 5)
check("brak 6 g to szum, nie powitanie", resolve(balance).kind == .weekReady)
balance.balance = AssistantBriefingBalance(macroGenitive: "białka", macroAccusative: "białko", unit: "g", averagePerDay: 100, target: 140, daysCounted: 2)
check("z dwóch dni nie liczy się średniej tygodnia", resolve(balance).kind == .weekReady)

// Dzień gotowy, ale weekend niezaplanowany.
let dayReady = context(now: thursday, thisWeek: week(from: monday, planned: 5), nextWeek: week(from: nextMonday, planned: 7))
check("dzień gotowy, tydzień nie", resolve(dayReady).kind == .dayReady)
check("dzień gotowy: talerzyki ze zdjęciami dnia", plates(resolve(dayReady)).count == 3 && plates(resolve(dayReady)).allSatisfy(\.filled))

// Wieczór, jutro gotowe.
let eveningReady = context(now: date(17, hour: 20), thisWeek: week(from: monday, planned: 5), nextWeek: week(from: nextMonday, planned: 7))
check("wieczór, jutro gotowe", resolve(eveningReady).kind == .eveningReady)

// Sobota z planem na dziś → inspiracja.
let weekend = context(now: date(19, hour: 11), thisWeek: week(from: monday, planned: 7), nextWeek: week(from: nextMonday, planned: 7))
check("weekend z planem na dziś: inspiracja", resolve(weekend).kind == .weekendInspiration)

print("TEKSTY")
check("imię z pełnej nazwy", AssistantBriefingResolver.firstName("Rafał Piechowicz") == "Rafał")
check("login nie jest imieniem", AssistantBriefingResolver.firstName("rpiechowicz") == nil)
check("e-mail nie jest imieniem", AssistantBriefingResolver.firstName("Rafal@x.pl") == nil)
check("godzina", AssistantBriefingResolver.clock(19 * 60 + 5) == "19:05")
check("wyliczenie pór", AssistantBriefingResolver.joined(["śniadanie", "obiad", "kolację"]) == "śniadanie, obiad i kolację")
let everyone = [empty, todayEmpty, eve, dinner, nextEmpty, balance, dayReady, weekend, soon, late, eveningReady, breakfast]
check("każde powitanie ma najwyżej dwie alternatywy", everyone.allSatisfy { resolve($0).alternatives.count <= 2 })
check("poza pulą ostatnia alternatywa to „Mam inny pomysł”", everyone.allSatisfy { resolve($0).alternatives.last?.kind == .compose })
check("poza pulą przykład w polu nie jest pusty", everyone.allSatisfy { !resolve($0).placeholder.isEmpty })
check("bez liczenia braków w otwarciu", everyone.allSatisfy { !resolve($0).headline.contains(" z ") })

// Zdanie z powitania nie może zmuszać asystenta do dopytania: każde mówi,
// na kiedy. Wyjątki: pytanie o możliwości i kroki konkretnego dania.
let whenWords = ["dziś", "jutr", "tydzień", "tygodni", "dni", "poniedziałek", "sobotę"]
let everyPrompt = everyone.flatMap { c -> [String] in
    let b = resolve(c)
    return ([b.primary] + b.alternatives).compactMap(asks)
}
let vague = everyPrompt.filter { prompt in
    !prompt.hasPrefix("Co potrafisz") && !prompt.hasPrefix("Jak ugotować")
        && !whenWords.contains { prompt.lowercased().contains($0) }
}
check("każde zdanie z powitania mówi, na kiedy" + (vague.isEmpty ? "" : ": \(vague)"), vague.isEmpty)
check("zamiana wskazuje danie z planu", asks(resolve(dayReady).primary)?.hasPrefix("Zamień ") == true && asks(resolve(dayReady).primary)?.contains("(Danie)") == true)
check("zamiana jutra wskazuje obiad", resolve(eveningReady).alternatives.first.flatMap(asks) == "Zamień obiad na jutro (Danie): pokaż 3 inne dania do wyboru")

if failures > 0 {
    print("\n\(failures) błędów")
    exit(1)
}
print("\nwszystko ok")
