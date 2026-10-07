import Foundation
import SwiftUI

// Granica store → repozytorium dla porcji per osoba: PRAWDZIWY
// `MealCalendarStore` (`upsertWeekSlot`, `setPortions`) i atrapa
// `WeeklyPlanRepository`, która zapisuje każde wywołanie. Sprawdzamy, co
// naprawdę wychodzi do repozytorium — nie osobną kopię warunku.
// Uruchomienie: `sh Scripts/plan-store-check.sh`.

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

// `MealCalendarStore` zapisuje `meal_plans_<ns>.json` w `Application Support/
// ScoffieCache` (od 7.10.2026, `AppCacheDirectory`; przenosi tam też stare
// pliki z Documents) i przy starcie kasuje `saved_plan.json` w Documents.
// Skrypt ustawia `CFFIXED_USER_HOME` na katalog tymczasowy; bez tego sprawdzian
// NIE rusza — nie dotykamy prawdziwego Documents ani Application Support.
let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
guard let fixedHome = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"],
      !fixedHome.isEmpty,
      documents.resolvingSymlinksInPath().path
          .hasPrefix(URL(fileURLWithPath: fixedHome).resolvingSymlinksInPath().path) else {
    print("PRZERWANE: uruchom przez Scripts/plan-store-check.sh (Documents musi być w katalogu tymczasowym, jest: \(documents.path))")
    exit(2)
}
// Application Support liczony BEZ `AppCacheDirectory` (ten od razu tworzy
// katalog) — musi leżeć w tym samym katalogu domowym co sprawdzone Documents.
let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
guard applicationSupport.standardizedFileURL.path
    .hasPrefix(documents.deletingLastPathComponent().standardizedFileURL.path + "/") else {
    print("PRZERWANE: Application Support poza katalogiem tymczasowym (jest: \(applicationSupport.path))")
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
        let portionWrite: PlanPortions.PortionWrite?
    }

    struct SetPortion: Equatable {
        let planItemId: String
        let userId: String
        let units: Int
        let expectedRevision: Int
    }

    private(set) var upserts: [Upsert] = []
    private(set) var portionWrites: [SetPortion] = []
    private(set) var otherCalls: [String] = []
    /// Odpowiedź serwera na `setPortion` — `nil` = nieczytelna.
    var portionAck: ((SetPortion) -> WeekPlanSlot?)?
    /// Odmowa serwera na N-te (od 0) wywołanie `setPortion`.
    var portionFailure: (index: Int, code: String)?

    var totalCalls: Int { upserts.count + portionWrites.count + otherCalls.count }

    func fetchWeekPlan(weekStart: String) async throws -> [WeekPlanSlot] {
        otherCalls.append("fetchWeekPlan")
        return []
    }

    func upsertWeekSlot(weekStart: String, date: Date, mealSlot: MealSlot, recipeId: UUID, participantIds: [String], plannedServings: Int?, replaceRecipeId: UUID?, portionWrite: PlanPortions.PortionWrite?) async throws -> WeekPlanSlot? {
        upserts.append(Upsert(
            weekStart: weekStart,
            mealSlot: mealSlot,
            recipeId: recipeId,
            participantIds: participantIds,
            plannedServings: plannedServings,
            replaceRecipeId: replaceRecipeId,
            portionWrite: portionWrite
        ))
        // `nil` = odpowiedź, której klient nie umie odczytać — store zostawia
        // wpis optymistyczny, więc widać dokładnie to, co sam z siebie zrobił.
        return nil
    }

    func setPortion(weekStart: String, planItemId: String, userId: String, units: Int, expectedRevision: Int) async throws -> WeekPlanSlot? {
        let call = SetPortion(planItemId: planItemId, userId: userId, units: units, expectedRevision: expectedRevision)
        let index = portionWrites.count
        portionWrites.append(call)
        if let portionFailure, portionFailure.index == index {
            throw RecipeDataError.server(code: portionFailure.code, message: "odmowa", status: 409, requestId: nil)
        }
        return portionAck?(call)
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

    func logCookedMeal(weekStart: String, date: Date, mealSlot: MealSlot, recipeId: UUID, servings: Int) async throws {
        otherCalls.append("logCookedMeal")
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

/// Pozycja z alokacją i tokenami (świeży odczyt z backendu z wersjami).
func allocated(_ recipe: Recipe, revision: Int = 11) -> PlanMeal {
    PlanMeal(
        id: "item-\(recipe.name)", recipe: recipe, participantIds: [], plannedServings: 3,
        portionUnits: [asia: 10, rafal: 30],
        revision: revision, portionRevisions: [asia: 9, rafal: revision]
    )
}

/// Ta sama alokacja z cache'u sprzed wersji — bez tokenów.
func allocatedNoTokens(_ recipe: Recipe) -> PlanMeal {
    PlanMeal(id: "item-\(recipe.name)", recipe: recipe, participantIds: [], plannedServings: 2, portionUnits: [asia: 10, rafal: 30])
}

func legacy(_ recipe: Recipe) -> PlanMeal {
    PlanMeal(id: "item-\(recipe.name)", recipe: recipe, participantIds: [], plannedServings: 2, revision: 0)
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

// MARK: - 1. Pozycja z alokacją i tokenem — PRESERVE

do {
    let (store, spy) = makeStore([allocated(soup)])
    let saved = await upsert(store, soup, participants: [rafal])
    check(saved, "1a: zmiana „kto je” pozycji z alokacją → true")
    check(spy.upserts == [SpyWeeklyPlanRepository.Upsert(
        weekStart: weekStart, mealSlot: .dinner, recipeId: soup.id,
        participantIds: [rafal], plannedServings: nil, replaceRecipeId: nil,
        portionWrite: .preserve(PlanPortions.RevisionTokens(expectedRevision: 11, isSwap: false, expectedTargetRevision: nil))
    )] && spy.otherCalls.isEmpty, "1a: jedno zapytanie — PRESERVE z tokenem pozycji, bez plannedServings")
    let meal = store.meals(for: monday, slot: .dinner).first
    check(meal?.portionUnits == [rafal: 30] && meal?.plannedServings == 2,
          "1a: optymistycznie — zostający zachowuje 1,5, Asia znika, ceil(1,5) = 2")
}
do {
    let (store, spy) = makeStore([allocated(soup)])
    let saved = await upsert(store, soup, servings: 4)
    check(saved && spy.upserts.map(\.plannedServings) == [nil] && spy.upserts.first?.portionWrite != nil,
          "1b: liczba porcji łącznych przy PRESERVE nie wychodzi (liczy serwer)")
}
do {
    let (store, spy) = makeStore([allocatedNoTokens(soup)])
    let before = store.meals(for: monday, slot: .dinner)
    let saved = await upsert(store, soup, participants: [rafal])
    check(!saved && spy.totalCalls == 0, "1c: alokacja bez tokenu → false, zero zapytań")
    check(store.meals(for: monday, slot: .dinner) == before, "1c: bez zmiany optymistycznej")
    check(store.errorMessage == PlanPortions.editBlockedMessage, "1c: komunikat")
}

// MARK: - 2. Zamiana dania z alokacją — para tokenów, porcje przechodzą

do {
    let (store, spy) = makeStore([allocated(soup)])
    let saved = await upsert(store, pasta, replacing: soup.id)
    check(saved, "2: zamiana dania z alokacją → true")
    check(spy.upserts.first?.portionWrite == .preserve(PlanPortions.RevisionTokens(expectedRevision: 11, isSwap: true, expectedTargetRevision: nil))
          && spy.upserts.first?.replaceRecipeId == soup.id,
          "2: PRESERVE, token źródła, cel null (nowego dania w slocie nie było)")
    let meals = store.meals(for: monday, slot: .dinner)
    check(meals.map(\.recipe.id) == [pasta.id] && meals.first?.portionUnits == [asia: 10, rafal: 30],
          "2: optymistycznie nowe danie przejmuje porcje starego")
}

// MARK: - 3. Zamiana na istniejącą pozycję z alokacją — token celu z odczytu

do {
    let (store, spy) = makeStore([legacy(soup), allocated(pasta, revision: 9)])
    let saved = await upsert(store, pasta, replacing: soup.id)
    check(saved && spy.upserts.first?.portionWrite == .preserve(PlanPortions.RevisionTokens(expectedRevision: 0, isSwap: true, expectedTargetRevision: 9)),
          "3: token źródła (legacy, 0) + token celu 9")
}

// MARK: - 4. Nowa, niezależna pozycja obok alokowanej — jedno zapytanie

do {
    let (store, spy) = makeStore([allocated(soup)])
    let saved = await upsert(store, salad, participants: [asia])
    check(saved, "4: nowe danie obok dania z alokacją → true")
    check(spy.upserts == [SpyWeeklyPlanRepository.Upsert(
        weekStart: weekStart, mealSlot: .dinner, recipeId: salad.id,
        participantIds: [asia], plannedServings: nil, replaceRecipeId: nil, portionWrite: nil
    )] && spy.otherCalls.isEmpty, "4: dokładnie jedno zapytanie — nowe danie, bez podmiany, bez liczby porcji, bez tokenów")
    let meals = store.meals(for: monday, slot: .dinner)
    check(meals.first { $0.recipe.id == soup.id }?.portionUnits == [asia: 10, rafal: 30],
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
        participantIds: [asia], plannedServings: nil, replaceRecipeId: nil, portionWrite: nil
    ), "5a: zapytanie jak dotąd (bez plannedServings i tokenów — serwer liczy z audytorium)")
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

// MARK: - 5d. Pierwsze ustawienie porcji osób — REPLACE z tokenem migawki

do {
    let (store, spy) = makeStore([legacy(soup)])
    let saved = await store.upsertWeekSlot(
        recipe: soup,
        participantIds: [],
        householdMemberCount: 2,
        portions: [asia: 10, rafal: 30],
        expectedRevision: 0,
        for: monday,
        slot: .dinner,
        weekStart: weekStart
    )
    check(saved && spy.upserts.first?.portionWrite == .replace(
        units: [asia: 10, rafal: 30],
        tokens: PlanPortions.RevisionTokens(expectedRevision: 0, isSwap: false, expectedTargetRevision: nil)
    ), "5d: posiłek bez alokacji → REPLACE, pełna mapa, token pozycji")
    check(spy.upserts.first?.plannedServings == nil, "5d: bez plannedServings (liczy serwer)")
    let meal = store.meals(for: monday, slot: .dinner).first
    check(meal?.portionUnits == [asia: 10, rafal: 30] && meal?.plannedServings == 2,
          "5d: optymistycznie porcje osób i ceil(2) = 2")
}
do {
    let (store, spy) = makeStore([])
    let saved = await store.upsertWeekSlot(
        recipe: salad,
        participantIds: [asia],
        householdMemberCount: 2,
        portions: [asia: 30],
        for: monday,
        slot: .dinner,
        weekStart: weekStart
    )
    check(saved && spy.upserts.first?.portionWrite == .replace(units: [asia: 30], tokens: nil),
          "5e: nowe danie z porcją (Dodaj do planu) → REPLACE bez tokenów")
    check(store.meals(for: monday, slot: .dinner).first?.portionUnits == [asia: 30], "5e: wpis optymistyczny z porcją 1,5")
}

// MARK: - 6. Stepper porcji — setPortion per osoba, z jej tokenem

@MainActor
func setPortions(
    _ store: MealCalendarStore,
    _ units: [String: Int],
    tokens: [String: Int] = [asia: 9, rafal: 11],
    item: String = "item-Zupa"
) async -> Bool {
    await store.setPortions(units, expectedRevisions: tokens, itemId: item, for: monday, slot: .dinner, weekStart: weekStart)
}

do {
    let (store, spy) = makeStore([allocated(soup)])
    spy.portionAck = { call in
        WeekPlanSlot(
            itemId: call.planItemId, dateKey: PlanWeek.dateKey(monday), mealSlot: .dinner, recipe: soup,
            participantIds: [], eatenByUserIds: [], plannedServings: 3,
            portionUnits: [asia: call.units, rafal: 30], revision: 12, portionRevisions: [asia: 12, rafal: 11]
        )
    }
    let saved = await setPortions(store, [asia: 20])
    check(saved, "6a: porcja Asi 0,5 → 1 → true")
    check(spy.portionWrites == [SpyWeeklyPlanRepository.SetPortion(planItemId: "item-Zupa", userId: asia, units: 20, expectedRevision: 9)]
          && spy.upserts.isEmpty, "6a: jedno setPortion z tokenem Asi (9), bez upsertu")
    let meal = store.meals(for: monday, slot: .dinner).first
    check(meal?.portionUnits == [asia: 20, rafal: 30] && meal?.revision == 12 && meal?.portionRevisions[asia] == 12,
          "6a: ack podmienia porcje i tokeny")
}
do {
    let (store, spy) = makeStore([allocated(soup)])
    let saved = await setPortions(store, [rafal: 30])
    check(saved && spy.totalCalls == 0, "6b: porcja bez zmiany → zero zapytań")
}
do {
    let (store, spy) = makeStore([allocated(soup)])
    let saved = await setPortions(store, [asia: 25])
    check(!saved && spy.totalCalls == 0, "6c: porcja spoza kroku 0,5 → false, zero zapytań")
    check(store.errorMessage == UserFacingErrorMapper.message(from: RecipeDataError.server(
        code: "PLAN_PORTIONS_INVALID", message: "", status: 400, requestId: nil
    )), "6c: komunikat o widełkach, nie o odświeżeniu")
}
do {
    let (store, spy) = makeStore([allocatedNoTokens(soup)])
    let saved = await setPortions(store, [asia: 20], tokens: [:])
    check(!saved && spy.totalCalls == 0 && store.errorMessage == PlanPortions.editBlockedMessage,
          "6d: brak tokenu porcji → false, zero zapytań, komunikat")
}
do {
    let (store, spy) = makeStore([allocated(soup)])
    let saved = await setPortions(store, [asia: 20, rafal: 40])
    check(saved && spy.portionWrites.map(\.userId) == [asia, rafal].sorted() && spy.portionWrites.count == 2,
          "6e: dwie osoby → dwa setPortion, każde ze swoim tokenem")
    check(Set(spy.portionWrites.map(\.expectedRevision)) == [9, 11], "6e: tokeny 9 (Asia) i 11 (Rafał)")
}
do {
    // Suma 12 przy trzech osobach: Asia 6 → 5,5 i gość 0,5 → 1. Gość sortuje
    // się po id PRZED Asią, więc kolejność po id dałaby najpierw 12,5
    // (odmowa serwera). Najpierw musi iść zmniejszenie.
    let guest = "0-gosc"
    let full = PlanMeal(
        id: "item-Zupa", recipe: soup, participantIds: [], plannedServings: 12,
        portionUnits: [asia: 120, rafal: 110, guest: 10], revision: 11,
        portionRevisions: [asia: 9, rafal: 11, guest: 7]
    )
    let (store, spy) = makeStore([full])
    let saved = await setPortions(store, [asia: 110, guest: 20], tokens: [asia: 9, rafal: 11, guest: 7])
    check(saved && spy.portionWrites.map(\.userId) == [asia, guest], "6f: najpierw zmniejszenie (Asia), potem zwiększenie (gość)")
}
do {
    // Tydzień przeładowany w tle: store ma już token 10 dla Asi, arkusz
    // edytował na migawce z tokenem 9 — idzie 9 (serwer zgłosi konflikt).
    var fresh = allocated(soup)
    fresh.portionRevisions[asia] = 10
    let (store, spy) = makeStore([fresh])
    _ = await setPortions(store, [asia: 20], tokens: [asia: 9, rafal: 11])
    check(spy.portionWrites.first?.expectedRevision == 9, "6g: token z migawki arkusza, nie z przeładowanego stanu")
}

// MARK: - 7. Konflikt wersji — cofnięcie, bez ponowienia

do {
    let (store, spy) = makeStore([allocated(soup)])
    let before = store.meals(for: monday, slot: .dinner)
    spy.portionFailure = (index: 0, code: "PLAN_REVISION_CONFLICT")
    let saved = await setPortions(store, [asia: 20, rafal: 40])
    check(!saved && spy.portionWrites.count == 1, "7: konflikt pierwszej osoby → false, druga nie idzie, brak ponowienia")
    check(store.meals(for: monday, slot: .dinner) == before, "7: wpis optymistyczny cofnięty")
    check(store.errorMessage == UserFacingErrorMapper.message(from: RecipeDataError.server(
        code: "PLAN_REVISION_CONFLICT", message: "", status: 409, requestId: nil
    )), "7: komunikat konfliktu")
}

print(failures == 0 ? "\nWSZYSTKO OK" : "\nBŁĘDÓW: \(failures)")
exit(failures == 0 ? 0 : 1)
