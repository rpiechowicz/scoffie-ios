import Foundation
import SwiftUI

// Granica store → repozytorium dla porcji per osoba: PRAWDZIWY
// `MealCalendarStore.upsertWeekSlot` i atrapa `WeeklyPlanRepository`, która
// zapisuje każde wywołanie. Sprawdzamy, co naprawdę wychodzi do repozytorium
// — nie osobną kopię warunku. Uruchomienie: `sh Scripts/plan-store-check.sh`.

var failures = 0

func check(_ condition: Bool, _ name: String) {
    if condition {
        print("OK   \(name)")
    } else {
        failures += 1
        print("BŁĄD \(name)")
    }
}

// MARK: - Zaślepki spoza zestawu plików

/// `BackendRecipeDTO` bierze bazowy adres z `AppEnvironment` (ScoffieApp.swift, `@main`).
enum AppEnvironment {
    static let apiBaseURL = URL(string: "https://api.scoffie.invalid")!
}

/// Podgląd w `PolishPlural.swift` sięga po kolory z `SCDesignSystem.swift`
/// (UIKit, tylko iOS) — w sprawdzianie na macOS wystarczą stałe kolory.
extension Color {
    static func scCanvas(_ scheme: ColorScheme) -> Color { .clear }
    static func scLabel(_ scheme: ColorScheme) -> Color { .primary }
}

// MARK: - Bezpiecznik: pliki store'u tylko w katalogu tymczasowym

// `MealCalendarStore` zapisuje `meal_plans_<ns>.json` w Documents i przy starcie
// kasuje `saved_plan.json`. Skrypt ustawia `CFFIXED_USER_HOME` na katalog
// tymczasowy; bez tego sprawdzian NIE rusza — nie dotykamy prawdziwego Documents.
let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
guard let fixedHome = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"],
      !fixedHome.isEmpty,
      documents.resolvingSymlinksInPath().path
          .hasPrefix(URL(fileURLWithPath: fixedHome).resolvingSymlinksInPath().path) else {
    print("PRZERWANE: uruchom przez Scripts/plan-store-check.sh (Documents musi być w katalogu tymczasowym, jest: \(documents.path))")
    exit(2)
}
try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)

// MARK: - Atrapa repozytorium

final class SpyWeeklyPlanRepository: WeeklyPlanRepository {
    struct Upsert: Equatable {
        let weekStart: String
        let mealSlot: MealSlot
        let recipeId: UUID
        let participantIds: [String]
        let plannedServings: Int?
        let replaceRecipeId: UUID?
    }

    private(set) var upserts: [Upsert] = []
    private(set) var otherCalls: [String] = []

    var totalCalls: Int { upserts.count + otherCalls.count }

    func fetchWeekPlan(weekStart: String) async throws -> [WeekPlanSlot] {
        otherCalls.append("fetchWeekPlan")
        return []
    }

    func upsertWeekSlot(weekStart: String, date: Date, mealSlot: MealSlot, recipeId: UUID, participantIds: [String], plannedServings: Int?, replaceRecipeId: UUID?) async throws -> WeekPlanSlot? {
        upserts.append(Upsert(
            weekStart: weekStart,
            mealSlot: mealSlot,
            recipeId: recipeId,
            participantIds: participantIds,
            plannedServings: plannedServings,
            replaceRecipeId: replaceRecipeId
        ))
        // `nil` = odpowiedź, której klient nie umie odczytać — store zostawia
        // wpis optymistyczny, więc widać dokładnie to, co sam z siebie zrobił.
        return nil
    }

    func removeWeekSlot(weekStart: String, date: Date, mealSlot: MealSlot, recipeId: UUID?) async throws {
        otherCalls.append("removeWeekSlot")
    }

    func clearWeekPlan(weekStart: String) async throws {
        otherCalls.append("clearWeekPlan")
    }

    func setMealEaten(weekStart: String, date: Date, mealSlot: MealSlot, recipeId: UUID, isEaten: Bool) async throws {
        otherCalls.append("setMealEaten")
    }

    func observeWeekPlanChanges(_ onChange: @escaping (_ event: BackendWeekChangedDTO) -> Void) {}
    func observeRealtimeReconnect(_ onReconnect: @escaping () -> Void) {}
}

// MARK: - Dane

let asia = "00000000-0000-4000-8000-00000000000a"
let rafal = "00000000-0000-4000-8000-00000000000b"
let soup = Recipe(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, name: "Zupa", description: "", category: .dinner, servings: 4)
let pasta = Recipe(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, name: "Makaron", description: "", category: .dinner, servings: 4)
let salad = Recipe(id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!, name: "Sałatka", description: "", category: .dinner, servings: 2)

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12))!
let weekStart = "2026-09-28"

func allocated(_ recipe: Recipe) -> PlanMeal {
    PlanMeal(id: "item-\(recipe.name)", recipe: recipe, participantIds: [], plannedServings: 3, portionUnits: [asia: 16, rafal: 25])
}

func legacy(_ recipe: Recipe) -> PlanMeal {
    PlanMeal(id: "item-\(recipe.name)", recipe: recipe, participantIds: [], plannedServings: 2)
}

/// Świeży store z atrapą i zadanym slotem.
@MainActor
func makeStore(_ meals: [PlanMeal]) -> (MealCalendarStore, SpyWeeklyPlanRepository) {
    let spy = SpyWeeklyPlanRepository()
    let store = MealCalendarStore(weeklyPlanRepository: spy, currentUserId: rafal, cacheNamespace: "check_\(UUID().uuidString)")
    store.setMeals(meals, for: monday, slot: .dinner)
    return (store, spy)
}

@MainActor
func upsert(
    _ store: MealCalendarStore,
    _ recipe: Recipe,
    participants: [String] = [],
    servings: Int? = nil,
    replacing: UUID? = nil
) async -> Bool {
    await store.upsertWeekSlot(
        recipe: recipe,
        participantIds: participants,
        plannedServings: servings,
        householdMemberCount: 2,
        replacingRecipeId: replacing,
        for: monday,
        slot: .dinner,
        weekStart: weekStart
    )
}

// MARK: - 1. Pozycja ze znaną alokacją — zero zapytań, bez zmiany optymistycznej

do {
    let (store, spy) = makeStore([allocated(soup)])
    let before = store.meals(for: monday, slot: .dinner)
    let saved = await upsert(store, soup, participants: [rafal])
    check(!saved, "1a: zmiana „kto je” pozycji z alokacją → false")
    check(spy.totalCalls == 0, "1a: zero zapytań do repozytorium")
    check(store.meals(for: monday, slot: .dinner) == before, "1a: brak zmiany optymistycznej (alokacja i audytorium bez zmian)")
    check(store.errorMessage == PlanPortions.editBlockedMessage, "1a: komunikat ograniczenia")
}
do {
    let (store, spy) = makeStore([allocated(soup)])
    let before = store.meals(for: monday, slot: .dinner)
    let saved = await upsert(store, soup, servings: 4)
    check(!saved && spy.totalCalls == 0 && store.meals(for: monday, slot: .dinner) == before,
          "1b: stepper porcji łącznych na pozycji z alokacją → false, zero zapytań, bez zmian")
}
do {
    let (store, spy) = makeStore([allocated(soup)])
    let saved = await upsert(store, soup)
    check(!saved && spy.totalCalls == 0, "1c: dołączenie / ponowny zapis tej samej pozycji → false, zero zapytań")
}

// MARK: - 2. Zamiana pozycji z alokacją — zero zapytań

do {
    let (store, spy) = makeStore([allocated(soup)])
    let before = store.meals(for: monday, slot: .dinner)
    let saved = await upsert(store, pasta, replacing: soup.id)
    check(!saved && spy.totalCalls == 0, "2: zamiana dania z alokacją na inne → false, zero zapytań")
    check(store.meals(for: monday, slot: .dinner) == before, "2: danie z alokacją zostaje w slocie")
}

// MARK: - 3. Zamiana na istniejącą pozycję z alokacją — zero zapytań

do {
    let (store, spy) = makeStore([legacy(soup), allocated(pasta)])
    let before = store.meals(for: monday, slot: .dinner)
    let saved = await upsert(store, pasta, replacing: soup.id)
    check(!saved && spy.totalCalls == 0, "3: zamiana na danie, które w slocie ma alokację → false, zero zapytań")
    check(store.meals(for: monday, slot: .dinner) == before, "3: slot bez zmian")
}

// MARK: - 4. Nowa, niezależna pozycja obok alokowanej — jedno zapytanie

do {
    let (store, spy) = makeStore([allocated(soup)])
    let saved = await upsert(store, salad, participants: [asia])
    check(saved, "4: nowe danie obok dania z alokacją → true")
    check(spy.upserts == [SpyWeeklyPlanRepository.Upsert(
        weekStart: weekStart, mealSlot: .dinner, recipeId: salad.id,
        participantIds: [asia], plannedServings: nil, replaceRecipeId: nil
    )] && spy.otherCalls.isEmpty, "4: dokładnie jedno zapytanie — nowe danie, bez podmiany, bez liczby porcji")
    let meals = store.meals(for: monday, slot: .dinner)
    check(meals.first { $0.recipe.id == soup.id }?.portionUnits == [asia: 16, rafal: 25],
          "4: alokacja sąsiedniego dania nietknięta")
    check(meals.first { $0.recipe.id == salad.id }?.plannedServings == 1, "4: wpis optymistyczny nowego dania (1 osoba = 1 porcja)")
}

// MARK: - 5. Legacy bez alokacji — jedno zapytanie, dotychczasowa semantyka

do {
    let (store, spy) = makeStore([legacy(soup)])
    let saved = await upsert(store, soup, participants: [asia])
    check(saved && spy.upserts.count == 1 && spy.otherCalls.isEmpty, "5a: legacy zmiana „kto je” → true, jedno zapytanie")
    check(spy.upserts.first == SpyWeeklyPlanRepository.Upsert(
        weekStart: weekStart, mealSlot: .dinner, recipeId: soup.id,
        participantIds: [asia], plannedServings: nil, replaceRecipeId: nil
    ), "5a: zapytanie jak dotąd (bez plannedServings — serwer liczy z audytorium)")
    let meal = store.meals(for: monday, slot: .dinner).first { $0.recipe.id == soup.id }
    check(meal?.participantIds == [asia] && meal?.plannedServings == 1 && meal?.hasPortions == false,
          "5a: wpis optymistyczny jak dotąd (Asia, 1 porcja, bez alokacji)")
}
do {
    let (store, spy) = makeStore([legacy(soup)])
    let saved = await upsert(store, soup, servings: 3)
    check(saved && spy.upserts.map(\.plannedServings) == [3], "5b: legacy stepper → jedno zapytanie z plannedServings 3")
    check(store.meals(for: monday, slot: .dinner).first?.plannedServings == 3, "5b: wpis optymistyczny 3 porcje")
}
do {
    let (store, spy) = makeStore([legacy(soup)])
    let saved = await upsert(store, pasta, replacing: soup.id)
    check(saved && spy.upserts.map(\.replaceRecipeId) == [soup.id] && spy.upserts.map(\.recipeId) == [pasta.id],
          "5c: legacy zamiana dania → jedno zapytanie z replaceRecipeId")
    check(store.meals(for: monday, slot: .dinner).map(\.recipe.id) == [pasta.id], "5c: w slocie nowe danie zamiast starego")
}

print(failures == 0 ? "\nWSZYSTKO OK" : "\nBŁĘDÓW: \(failures)")
exit(failures == 0 ? 0 : 1)
