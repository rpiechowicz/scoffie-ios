import Foundation

/// Porcje per osoba w pozycji planu (backend `PlanItemPortion`).
///
/// Trzymane w JEDNOSTKACH jak w bazie: 1 jednostka = 1/20 porcji przepisu.
/// Od 27.09.2026 serwer przyjmuje tylko wielokrotności 0,5 porcji (10
/// jednostek), od 0,5 do 6 na osobę i najwyżej 12 na pozycję — „0,8 porcji”
/// nikt nie nakłada. Liczby całkowite zamiast `Double`, żeby krok i widełki
/// liczyły się bez arytmetyki zmiennoprzecinkowej.
/// Czysta logika (tylko Foundation) — sprawdza ją `Scripts/plan-portions-check.sh`.
///
/// ZAPIS (kontrakt backendu: `docs/workstreams/plan-portions-safe-editing/
/// ios-contract.md` i §16 raportu `per-user-portions-write-safety`):
/// - porcja jednej osoby → wyłącznie `weeklyPlans:setPortion` z tokenem TEJ
///   osoby (`PlanMeal.portionRevisions`);
/// - pierwsze ustawienie porcji osób (pozycja bez alokacji, nowe danie
///   z „Dodaj do planu”) → `portionPolicy: REPLACE` + pełna mapa audytorium,
///   z tokenem pozycji, gdy telefon ją zna;
/// - zapis pozycji z alokacją (kto je, zamiana dania, dołączenie) →
///   `portionPolicy: PRESERVE` + token pozycji (przy zamianie para tokenów
///   źródła i celu); serwer sam przelicza porcje na nowe audytorium;
/// - pozycja bez alokacji → zapis jak dotąd, bez tokenów. Gdy serwer ma
///   alokację, której telefon jeszcze nie zna, odmawia (409) zamiast ją
///   kasować — store odświeża wtedy tydzień.
enum PlanPortions {
    static let unitsPerServing = 20
    /// Osoba bez wpisu w alokacji je jedną porcję — reguła serwera
    /// (`daily-balance.util`, dołączenie do domu).
    static let missingEntryUnits = 20

    /// Krok steppera: pół porcji.
    static let stepUnits = 10
    /// Widełki porcji jednej osoby: 0,5–6.
    static let unitsRange = 10...120
    /// Suma porcji pozycji: najwyżej 12 (limit `plannedServings`).
    static let maxTotalUnits = 240

    /// Pozycja z alokacją bez tokenów (stary backend albo cache sprzed
    /// wersji) — zapis zostaje zablokowany do najbliższego odświeżenia.
    static let editBlockedMessage =
        "Nie udało się zapisać porcji. Odśwież plan i spróbuj jeszcze raz."

    /// Podpis pod porcjami bez tokenów — do odczytu, zmiana po odświeżeniu.
    static let readOnlyMessage = "Odśwież plan, żeby zmienić porcje."

    /// Porcja z serwera (`servings`) → jednostki.
    static func units(fromServings servings: Double) -> Int {
        Int((servings * Double(unitsPerServing)).rounded())
    }

    static func servings(fromUnits units: Int) -> Double {
        Double(units) / Double(unitsPerServing)
    }

    /// „1”, „1,5”, „0,5” — bez zbędnych zer. Wartość spoza kroku 0,5 (dane
    /// sprzed zaokrąglenia) dostaje dwa miejsca po przecinku, żeby nie kłamać.
    static func label(units: Int) -> String {
        let whole = units / unitsPerServing
        let rest = units % unitsPerServing
        if rest == 0 { return "\(whole)" }
        if rest == stepUnits { return "\(whole),5" }
        let hundredths = rest * 5
        return "\(whole)," + (hundredths < 10 ? "0\(hundredths)" : "\(hundredths)")
    }

    /// „1 porcja”, „2 porcje”, „1,5 porcji” — ułamek łączy się z dopełniaczem.
    static func spokenServings(units: Int, plural: (Int) -> String) -> String {
        units % unitsPerServing == 0 ? plural(units / unitsPerServing) : "\(label(units: units)) porcji"
    }

    static func totalUnits(_ allocation: [String: Int]) -> Int {
        allocation.values.reduce(0, +)
    }

    /// `plannedServings` pozycji z alokacją — `ceil(Σ)`, jak liczy serwer.
    static func plannedServings(forTotalUnits total: Int) -> Int {
        max(1, (total + unitsPerServing - 1) / unitsPerServing)
    }

    // MARK: - Stepper

    /// Porcja osoby po jednym kroku (`direction` = +1 / −1) albo `nil`, gdy
    /// krok wyszedłby poza widełki osoby lub poza sumę pozycji. Wartość spoza
    /// siatki 0,5 najpierw dociąga się do najbliższej połówki w stronę kroku.
    static func stepped(units: Int, direction: Int, totalUnits: Int) -> Int? {
        let next: Int
        if units % stepUnits == 0 {
            next = units + direction * stepUnits
        } else {
            let floor = units - units % stepUnits
            next = direction > 0 ? floor + stepUnits : floor
        }
        guard unitsRange.contains(next) else { return nil }
        guard totalUnits - units + next <= maxTotalUnits else { return nil }
        return next
    }

    /// Czy porcję wolno wysłać (`setPortion` odrzuca resztę jako
    /// `PLAN_PORTIONS_INVALID`).
    static func isValid(units: Int) -> Bool {
        unitsRange.contains(units) && units % stepUnits == 0
    }

    // MARK: - Decyzja zapisu pozycji

    /// Tokeny zapisu pozycji (`upsertWeekSlot`) — `PRESERVE` i `REPLACE`.
    struct RevisionTokens: Equatable {
        /// `items[].revision` pozycji zapisywanej — przy zamianie ŹRÓDŁA.
        let expectedRevision: Int
        /// Zamiana dania: token celu idzie ZAWSZE, `nil` = „celu w slocie nie
        /// ma” (na drucie `null`). Bez zamiany pola nie wysyłamy.
        let isSwap: Bool
        let expectedTargetRevision: Int?
    }

    /// Co zapis pozycji mówi serwerowi o porcjach osób.
    enum PortionWrite: Equatable {
        /// `PRESERVE` — zachowaj porcje; tokeny wymagane.
        case preserve(RevisionTokens)
        /// `REPLACE` — pełna mapa porcji audytorium (jednostki 1/20);
        /// tokeny, gdy pozycja (albo źródło zamiany) jest znana telefonowi.
        case replace(units: [String: Int], tokens: RevisionTokens?)
    }

    /// Jak wysłać zapis pozycji.
    enum UpsertDecision: Equatable {
        /// Jak dotąd, bez tokenów — pozycje, których dotyka, nie mają alokacji.
        case send
        /// Z polityką porcji (`PRESERVE` / `REPLACE`).
        case write(PortionWrite)
        /// Alokacja bez znanych tokenów — nie wysyłamy nic, odświeżamy.
        case blocked
    }

    /// Dane slotu potrzebne do decyzji.
    struct SlotMeal: Equatable {
        let recipeId: UUID
        let hasPortions: Bool
        /// `PlanItem.revision`; `nil` = backend bez wersji albo stary cache.
        let revision: Int?
    }

    /// `weeklyPlans:upsertWeekSlot` przepisuje pozycję tego samego przepisu
    /// w slocie (cel) i usuwa pozycję `replaceRecipeId` (źródło zamiany).
    /// Gdy którakolwiek ma alokację, zapis idzie z `PRESERVE` i tokenami —
    /// serwer zachowuje porcje zostających, nowym daje 1, a przy zamianie
    /// nowe danie przejmuje porcje starego. Równe `recipeId` to nie zamiana.
    static func upsertDecision(slot: [SlotMeal], recipeId: UUID, replacingRecipeId: UUID?) -> UpsertDecision {
        let replacing = replacingRecipeId == recipeId ? nil : replacingRecipeId
        let target = slot.first { $0.recipeId == recipeId }
        let source = replacing.flatMap { id in slot.first { $0.recipeId == id } }
        guard [target, source].contains(where: { $0?.hasPortions == true }) else { return .send }

        if replacing != nil {
            // Źródło musi być znane: jego token jest `expectedRevision`.
            guard let sourceRevision = source?.revision else { return .blocked }
            if let target {
                guard let targetRevision = target.revision else { return .blocked }
                return .write(.preserve(RevisionTokens(expectedRevision: sourceRevision, isSwap: true, expectedTargetRevision: targetRevision)))
            }
            return .write(.preserve(RevisionTokens(expectedRevision: sourceRevision, isSwap: true, expectedTargetRevision: nil)))
        }
        guard let targetRevision = target?.revision else { return .blocked }
        return .write(.preserve(RevisionTokens(expectedRevision: targetRevision, isSwap: false, expectedTargetRevision: nil)))
    }

    /// Zapis z JAWNYMI porcjami osób (`REPLACE`) — pierwsze ustawienie porcji
    /// na pozycji bez alokacji albo nowe danie z porcjami. Tokeny idą, gdy
    /// telefon zna pozycję: nieaktualna kończy się konfliktem zamiast
    /// nadpisania. `knownRevision` to token z migawki ekranu, na którym
    /// użytkownik edytował (ma pierwszeństwo przed stanem store'u).
    static func replaceDecision(
        slot: [SlotMeal],
        recipeId: UUID,
        replacingRecipeId: UUID?,
        units: [String: Int],
        knownRevision: Int? = nil
    ) -> UpsertDecision {
        let replacing = replacingRecipeId == recipeId ? nil : replacingRecipeId
        let target = slot.first { $0.recipeId == recipeId }
        if let replacing {
            guard let source = slot.first(where: { $0.recipeId == replacing }) else {
                // Źródła telefon nie zna — zamiana bez tokenów (legacy),
                // chyba że cel ma alokację, której bez tokenu nie wolno zastąpić.
                return target?.hasPortions == true ? .blocked : .write(.replace(units: units, tokens: nil))
            }
            guard let sourceRevision = source.revision else {
                return source.hasPortions || target?.hasPortions == true
                    ? .blocked
                    : .write(.replace(units: units, tokens: nil))
            }
            if let target {
                guard let targetRevision = target.revision else { return .blocked }
                return .write(.replace(units: units, tokens: RevisionTokens(
                    expectedRevision: sourceRevision, isSwap: true, expectedTargetRevision: targetRevision
                )))
            }
            return .write(.replace(units: units, tokens: RevisionTokens(
                expectedRevision: sourceRevision, isSwap: true, expectedTargetRevision: nil
            )))
        }
        if let target {
            // Ekran bez tokenu nie widział alokacji, którą store ma już
            // z serwera (inny telefon) — REPLACE ze świeżym tokenem nadpisałby
            // ją bez konfliktu.
            if knownRevision == nil, target.hasPortions { return .blocked }
            guard let revision = knownRevision ?? target.revision else {
                return .write(.replace(units: units, tokens: nil))
            }
            return .write(.replace(units: units, tokens: RevisionTokens(
                expectedRevision: revision, isSwap: false, expectedTargetRevision: nil
            )))
        }
        return .write(.replace(units: units, tokens: nil))
    }

    /// Porcje osób bez alokacji — podział `totalUnits` (np. `plannedServings`
    /// × 20) po pół porcji, tak żeby suma się zgadzała: reszta idzie po 0,5
    /// na pierwsze osoby (5 porcji na 3 → 2 / 1,5 / 1,5). Najmniej 0,5, najwięcej
    /// 6 na osobę. Punkt startowy stepperów; na serwer idzie dopiero po zmianie.
    static func seededUnits(eaters: [String], totalUnits: Int) -> [String: Int] {
        let people = Array(Set(eaters)).sorted()
        guard !people.isEmpty else { return [:] }
        let steps = max(0, totalUnits) / stepUnits
        let base = steps / people.count
        let extra = steps % people.count
        var result: [String: Int] = [:]
        for (index, person) in people.enumerated() {
            let units = (base + (index < extra ? 1 : 0)) * stepUnits
            result[person] = min(unitsRange.upperBound, max(unitsRange.lowerBound, units))
        }
        return result
    }

    /// Czy łączne porcje da się rozpisać na osoby (najwyżej 6 na osobę).
    /// Nie — zostaje stepper porcji łącznych (np. 8 porcji w domu
    /// jednoosobowym: gotowanie na zapas).
    static func fitsPerPerson(totalUnits: Int, eaterCount: Int) -> Bool {
        eaterCount > 0 && totalUnits <= eaterCount * unitsRange.upperBound
    }

    /// Optymistyczna alokacja po zapisie `PRESERVE` ze zmianą „kto je” —
    /// ta sama reguła co serwer: zostający zachowują porcję, nowi dostają 1,
    /// usunięci znikają. Przy „Wspólne” (pusta lista) telefon nie zna
    /// wszystkich id domowników, więc zostawia alokację — prawdę przynosi ack.
    static func preservedAllocation(_ current: [String: Int], participantIds: [String]) -> [String: Int] {
        guard !participantIds.isEmpty else { return current }
        return Dictionary(
            participantIds.map { ($0, current[$0] ?? missingEntryUnits) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Błędy zapisu

    /// Kody, po których lokalny stan pozycji jest nieaktualny: cofamy wpis
    /// optymistyczny i odświeżamy tydzień — nigdy ciche ponowienie ze starym
    /// tokenem (kontrakt §6).
    static let staleStateCodes: Set<String> = [
        "PLAN_REVISION_CONFLICT",
        "PLAN_REVISION_REQUIRED",
        "PLAN_PORTIONS_CONFLICT",
        "PLAN_ITEM_NOT_FOUND"
    ]
}
