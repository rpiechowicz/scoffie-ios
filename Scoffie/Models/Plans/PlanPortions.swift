import Foundation

/// Porcje per osoba w pozycji planu (backend `PlanItemPortion`).
///
/// Trzymane w JEDNOSTKACH jak w bazie: 1 jednostka = 1/20 porcji przepisu
/// (0,05). Liczby całkowite zamiast `Double`, bo serwer przechowuje wyłącznie
/// wielokrotności 0,05 — na jednostkach nie ma czego zaokrąglać drugi raz.
/// Czysta logika (tylko Foundation) — sprawdza ją `Scripts/plan-portions-check.sh`.
///
/// ZAPIS. Serwer przy każdym zapisie pozycji zastępuje CAŁĄ alokację,
/// a gdy pola `portions` brak — KASUJE ją; nie ma kontroli wersji.
/// - Zabezpieczenie klienta (tylko dla alokacji ZNANYCH telefonowi): iOS
///   porcji nie wysyła i nie przepisuje pozycji, które lokalnie je mają
///   (`upsertDecision`).
/// - Pozostały race: jeśli alokacja powstała na serwerze, a telefon jeszcze
///   o niej nie wie, zwykły zapis pozycji (bez `portions`) ją skasuje.
///   Klient tego nie zamknie — ani brak pola, ani odświeżenie przed zapisem.
/// - Wymagane po stronie serwera, zanim alokacje zostaną uruchomione:
///   sprawdzenie stanu pozycji i decyzja o zapisie w tej samej transakcji;
///   zapis bez `portions` (także `replaceRecipeId`) nie może niejawnie
///   kasować istniejącej alokacji. Flaga planera nie jest kontrolą zapisu.
/// Szczegóły: `docs/workstreams/catalog-sync-per-user-portions/report.md`.
enum PlanPortions {
    static let unitsPerServing = 20
    /// Osoba bez wpisu w alokacji je jedną porcję — reguła serwera
    /// (`daily-balance.util`, dołączenie do domu).
    static let missingEntryUnits = 20

    /// Komunikat, gdy zmiana dotyka dania z porcjami per osoba.
    static let editBlockedMessage =
        "To danie ma porcje ustawione osobno dla każdej osoby. Tej zmiany nie da się jeszcze zapisać bez ryzyka ich utraty."

    /// Porcja z serwera (`servings`, wielokrotność 0,05) → jednostki.
    static func units(fromServings servings: Double) -> Int {
        Int((servings * Double(unitsPerServing)).rounded())
    }

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

    /// Czy zapis pozycji wolno wysłać.
    enum UpsertDecision: Equatable {
        /// Zapis bez pola `portions` — pozycje, których dotyka, nie mają alokacji.
        case send
        /// Zapis zastąpiłby alokację bez kontroli wersji — nie wysyłamy nic.
        case blocked
    }

    /// Dane slotu potrzebne do decyzji.
    struct SlotMeal: Equatable {
        let recipeId: UUID
        let hasPortions: Bool
    }

    /// `weeklyPlans:upsertWeekSlot` na serwerze przepisuje pozycję tego samego
    /// przepisu w slocie (zmiana „kto je”, stepper, dołączenie, ponowny zapis)
    /// i usuwa pozycję `replaceRecipeId` (zamiana dania) — obie tracą alokację.
    /// Blokujemy więc zapis, gdy którakolwiek z nich ją ma WEDŁUG STANU
    /// LOKALNEGO. Nowe danie obok dania z porcjami (inna pozycja) przechodzi.
    /// `.send` nie znaczy „bezpieczne”: przy nieaktualnym stanie serwer może
    /// mieć alokację, której tu nie widać (patrz nagłówek typu).
    static func upsertDecision(slot: [SlotMeal], recipeId: UUID, replacingRecipeId: UUID?) -> UpsertDecision {
        let touched = slot.filter { $0.recipeId == recipeId || $0.recipeId == replacingRecipeId }
        return touched.contains(where: \.hasPortions) ? .blocked : .send
    }
}
