import Foundation

/// Porcje per osoba w pozycji planu (backend `PlanItemPortion`).
///
/// Trzymane w JEDNOSTKACH jak w bazie: 1 jednostka = 1/20 porcji przepisu
/// (0,05). Liczby całkowite zamiast `Double`, bo serwer przyjmuje wyłącznie
/// wielokrotności 0,05 i odrzuca `1.333` — na jednostkach nie ma czego
/// zaokrąglać drugi raz. Czysta logika (tylko Foundation) — sprawdza ją
/// `Scripts/plan-portions-check.sh`.
///
/// Semantyka zapisu (kontrakt `weeklyPlans:upsertWeekSlot`): pominięte
/// `portions` KASUJE alokację i pozycja wraca do równego podziału. Dlatego
/// każda zmiana, która ma alokację zachować, odsyła ją w całości — dla
/// DOKŁADNIE tych osób, które jedzą (przy „Wspólne” — dla całego domu).
enum PlanPortions {
    static let unitsPerServing = 20
    /// `CHECK ("units" BETWEEN 2 AND 120)` — 0,1…6 porcji na osobę.
    static let minUnits = 2
    static let maxUnits = 120
    /// Σ ≤ 12 porcji (`PLANNED_SERVINGS_MAX`).
    static let maxTotalUnits = 240
    /// Osoba dopisana do dania z alokacją dostaje jedną porcję — ta sama
    /// reguła, którą serwer stosuje przy dołączeniu do domu (`plan-roster.util`).
    static let joinerUnits = 20

    /// Porcja z serwera (`servings`, wielokrotność 0,05) → jednostki.
    static func units(fromServings servings: Double) -> Int {
        Int((servings * Double(unitsPerServing)).rounded())
    }

    /// Jednostki → porcje. Iloraz dwóch dokładnych liczb całkowitych IEEE
    /// zaokrągla do najbliższego `Double` od `k × 0,05` — tego samego, który
    /// JS dostaje z napisu „0.85”, więc walidacja `maxDecimalPlaces: 2` na
    /// serwerze przechodzi niezależnie od tego, ile cyfr wypisze JSON.
    static func servings(fromUnits units: Int) -> Double {
        Double(units) / Double(unitsPerServing)
    }

    /// „1,25” — zawsze dwa miejsca po przecinku, bez arytmetyki zmiennoprzecinkowej.
    static func label(units: Int) -> String {
        let whole = units / unitsPerServing
        let hundredths = (units % unitsPerServing) * 5
        return "\(whole)," + (hundredths < 10 ? "0\(hundredths)" : "\(hundredths)")
    }

    static func totalUnits(_ allocation: [String: Int]) -> Int {
        allocation.values.reduce(0, +)
    }

    /// `plannedServings`, które serwer wyprowadzi z alokacji: `ceil(Σ)` w 1…12.
    static func derivedPlannedServings(_ allocation: [String: Int]) -> Int {
        let total = totalUnits(allocation)
        let ceil = (total + unitsPerServing - 1) / unitsPerServing
        return min(12, max(1, ceil))
    }

    /// Alokacja przeniesiona na nowe audytorium: kto zostaje, zachowuje swoją
    /// porcję; kto dochodzi, dostaje jedną; kto odchodzi, znika. `nil`, gdy
    /// nie ma czego przenosić (pozycja bez alokacji) albo audytorium nieznane.
    static func carried(_ existing: [String: Int], to audience: [String]) -> [String: Int]? {
        guard !existing.isEmpty, !audience.isEmpty else { return nil }
        var result: [String: Int] = [:]
        for memberId in audience {
            result[memberId] = existing[memberId] ?? joinerUnits
        }
        return result
    }

    /// Czy serwer przyjmie tę alokację dla tego audytorium (`portionsProblem`):
    /// dokładnie te osoby, każda 0,1…6 porcji, Σ ≤ 12.
    static func isValid(_ allocation: [String: Int], audience: [String]) -> Bool {
        guard !allocation.isEmpty, Set(allocation.keys) == Set(audience), Set(audience).count == audience.count else {
            return false
        }
        guard allocation.values.allSatisfy({ (minUnits...maxUnits).contains($0) }) else { return false }
        return totalUnits(allocation) <= maxTotalUnits
    }

    /// Jedna osoba ±`deltaUnits` w granicach serwera (także Σ ≤ 12).
    static func adjusting(_ allocation: [String: Int], memberId: String, by deltaUnits: Int) -> [String: Int] {
        guard let current = allocation[memberId] else { return allocation }
        let othersTotal = totalUnits(allocation) - current
        let upper = min(maxUnits, maxTotalUnits - othersTotal)
        var next = allocation
        next[memberId] = min(upper, max(minUnits, current + deltaUnits))
        return next
    }

    /// Co wysłać w `portions` przy zapisie pozycji.
    ///
    /// - `explicit`: alokacja ustawiona przez użytkownika (edytor porcji) —
    ///   idzie tak, jak jest.
    /// - `explicitTotal`: użytkownik ustawił liczbę porcji łącznie — to jawny
    ///   powrót do równego podziału, więc `nil` (pole pominięte).
    /// - w każdym innym zapisie (zmiana audytorium, podmiana dania, dołączenie
    ///   do tego samego dania, ponowny zapis) istniejąca alokacja jest
    ///   przenoszona na nowe audytorium — pominięcie pola skasowałoby ją.
    ///
    /// `audience` = `participantIds`, a przy „Wspólne” wszyscy domownicy;
    /// `nil` = nie wiadomo, kto je (lista domowników nie dojechała).
    static func forWrite(
        existing: [String: Int],
        audience: [String]?,
        explicit: [String: Int]?,
        explicitTotal: Bool
    ) -> [String: Int]? {
        if let explicit, !explicit.isEmpty { return explicit }
        if explicitTotal { return nil }
        guard let audience else { return nil }
        return carried(existing, to: audience)
    }
}
