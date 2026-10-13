import Foundation
import Observation

// Produkty do dopisania na Zakupach (13.10.2026, artefakt „Własne produkty
// w Zakupach”): katalog Scoffie (~530 składników z działami) i własne nazwy
// domu. Czysta logika — szukanie, jednostki, wybór — bez SwiftUI i sieci.
//
// Katalog przychodzi z `weeklyPlans:shoppingProducts` raz (z rewizją) i leży
// w pamięci telefonu, więc szukanie działa od razu, także w sklepie bez
// zasięgu. Dopisuje się dopiero przyciskiem „Dodaj N produktów” — wtedy sieć
// jest potrzebna. Typy danych (`ShoppingProduct`, `ShoppingAmountText`, …)
// leżą w `ShoppingListData.swift`.

// MARK: - Jednostki

/// Jednostki ilości w arkuszu. Serwer trzyma ilość w jednostce listy
/// (`szt` / `g` / `ml`) — kilogramy i litry są tylko wygodą wpisywania.
enum ShoppingAmountUnit: String, CaseIterable, Codable, Identifiable {
    case piece = "szt"
    case gram = "g"
    case kilogram = "kg"
    case milliliter = "ml"
    case liter = "l"

    var id: String { rawValue }

    /// Krok stepera — tyle, ile zwykle dokłada się w sklepie.
    var step: Double {
        switch self {
        case .piece: return 1
        case .gram: return 100
        case .kilogram: return 0.5
        case .milliliter: return 250
        case .liter: return 0.5
        }
    }

    /// Pierwsza wartość po wybraniu jednostki.
    var defaultAmount: Double {
        switch self {
        case .piece: return 1
        case .gram: return 100
        case .kilogram: return 1
        case .milliliter: return 500
        case .liter: return 1
        }
    }

    /// Sufit, ten sam co na serwerze (`SHOPPING_PRODUCT_INPUT_LIMITS`).
    var maxAmount: Double {
        switch self {
        case .piece: return 99
        case .gram, .milliliter: return 20_000
        case .kilogram, .liter: return 20
        }
    }

    /// Jednostka listy, do której serwer sprowadza tę jednostkę.
    var listUnit: String {
        switch self {
        case .piece: return "szt"
        case .gram, .kilogram: return "g"
        case .milliliter, .liter: return "ml"
        }
    }

    /// Jednostki do wyboru. Produkt, który JUŻ stoi na liście, dostaje
    /// tylko jednostki swojego wiersza — inaczej dopisanie zrobiłoby drugi
    /// wiersz „Mleko (szt)” obok „Mleko (ml)”. Produkt z masą sztuki — same
    /// sztuki, jak w planie.
    static func allowed(listUnit: String?, pieceOnly: Bool) -> [ShoppingAmountUnit] {
        if pieceOnly { return [.piece] }
        switch listUnit {
        case "g": return [.gram, .kilogram]
        case "ml": return [.milliliter, .liter]
        case "szt": return [.piece]
        default: return allCases
        }
    }

    /// Jednostka na start: litr dla płynów z listy, inaczej pierwsza z wolnych.
    static func preferred(in allowed: [ShoppingAmountUnit]) -> ShoppingAmountUnit {
        if allowed == [.milliliter, .liter] { return .liter }
        return allowed.first ?? .piece
    }
}

/// Ilość wybrana w arkuszu.
struct ShoppingAmount: Hashable, Codable {
    var value: Double
    var unit: ShoppingAmountUnit

    /// Ilość w jednostce listy (dla podglądu sumy).
    var listValue: Double {
        switch unit {
        case .kilogram, .liter: return value * 1000
        default: return value
        }
    }

    var text: String { ShoppingAmountText.format(value, unit: unit.rawValue) }

    /// Z jednostki listy na wygodną: 1500 g → 1,5 kg, 1000 ml → 1 l.
    static func fromList(amount: Double?, unit: String?) -> ShoppingAmount? {
        guard let amount, amount > 0, let unit else { return nil }
        switch unit {
        case "g":
            return amount >= 1000 && (amount / 500).rounded() == amount / 500
                ? ShoppingAmount(value: amount / 1000, unit: .kilogram)
                : ShoppingAmount(value: amount, unit: .gram)
        case "ml":
            return amount >= 1000 && (amount / 500).rounded() == amount / 500
                ? ShoppingAmount(value: amount / 1000, unit: .liter)
                : ShoppingAmount(value: amount, unit: .milliliter)
        case "szt":
            return ShoppingAmount(value: amount, unit: .piece)
        default:
            return nil
        }
    }

    /// O krok w górę albo w dół. W dół poniżej jednego kroku = bez ilości.
    func stepped(by direction: Int) -> ShoppingAmount? {
        let next = ((value + Double(direction) * unit.step) * 100).rounded() / 100
        if next < unit.step - 0.000_1 { return nil }
        return ShoppingAmount(value: min(next, unit.maxAmount), unit: unit)
    }
}

// MARK: - Szukanie

/// Szukanie w katalogu i własnych nazwach — bez polskich znaków i wielkości
/// liter (`IngredientSearch.fold`), po nazwie i aliasach. Kolejność: od
/// początku nazwy, od początku wyrazu, w środku; krótsza nazwa wyżej.
/// Gdy nic nie pasuje, próbuje bez ostatniej litery — „jajka” znajdzie
/// „Jajko”.
enum ShoppingProductSearch {
    struct Hit: Identifiable {
        let product: ShoppingProduct
        /// Gdzie w NAZWIE podświetlić trafienie; `nil` = trafił alias.
        let highlight: (offset: Int, length: Int)?
        fileprivate let rank: Int

        var id: String { product.id }
    }

    /// Złożone nazwy (`fold`) liczone raz na katalog, nie przy każdej literze.
    struct Index {
        fileprivate struct Entry {
            let product: ShoppingProduct
            let name: String
            let aliases: [String]
        }

        fileprivate let entries: [Entry]

        init(_ products: [ShoppingProduct]) {
            entries = products.map { product in
                Entry(
                    product: product,
                    name: IngredientSearch.fold(product.name),
                    aliases: product.aliases.map(IngredientSearch.fold)
                )
            }
        }

        var isEmpty: Bool { entries.isEmpty }
    }

    static func results(for query: String, in index: Index, limit: Int = 40) -> [Hit] {
        let folded = IngredientSearch.fold(query)
            .split(separator: " ")
            .joined(separator: " ")
        guard !folded.isEmpty else { return [] }
        var hits = rank(folded, in: index)
        if hits.isEmpty, folded.count >= 4 {
            hits = rank(String(folded.dropLast()), in: index)
        }
        return Array(hits.prefix(limit))
    }

    private static func rank(_ folded: String, in index: Index) -> [Hit] {
        var hits: [Hit] = []
        for entry in index.entries {
            if let match = match(entry.name, folded) {
                hits.append(Hit(product: entry.product, highlight: (match.offset, folded.count), rank: match.rank))
            } else if let best = entry.aliases.compactMap({ match($0, folded) }).min(by: { $0.rank < $1.rank }) {
                // Alias trafia o oczko niżej niż nazwa — „cebulka” ma dać
                // „Cebulę”, ale nie przed produktem, który się tak nazywa.
                hits.append(Hit(product: entry.product, highlight: nil, rank: best.rank + 1))
            }
        }
        return hits.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            if lhs.product.name.count != rhs.product.name.count {
                return lhs.product.name.count < rhs.product.name.count
            }
            return lhs.product.name.localizedCompare(rhs.product.name) == .orderedAscending
        }
    }

    private static func match(_ folded: String, _ query: String) -> (rank: Int, offset: Int)? {
        guard let range = folded.range(of: query) else { return nil }
        let offset = folded.distance(from: folded.startIndex, to: range.lowerBound)
        if offset == 0 { return (0, 0) }
        if folded[folded.index(before: range.lowerBound)] == " " { return (1, offset) }
        return (2, offset)
    }

    /// Dział własnej nazwy: z produktu katalogu, którego WYRAZ pasuje do
    /// wyrazu nazwy (albo jego odmiana — „pieluchy” ~ „pielucha”), a nie
    /// z dowolnego przedrostka: „karma” nie może trafić w „karmazyna”.
    static func guessDepartment(for name: String, in index: Index) -> String? {
        let words = IngredientSearch.fold(name).split(separator: " ").map(String.init).filter { $0.count >= 3 }
        for word in words {
            for entry in index.entries {
                for candidate in entry.name.split(separator: " ") {
                    let other = String(candidate)
                    if other == word { return entry.product.department }
                    if word.count >= 5, other.count >= 5,
                       abs(other.count - word.count) <= 1,
                       other.dropLast(2) == word.dropLast(2) {
                        return entry.product.department
                    }
                }
            }
        }
        return nil
    }
}

// MARK: - Wybór w arkuszu

/// Produkt wybrany w arkuszu „Dodaj produkty”, jeszcze niezapisany.
struct ShoppingProductDraft: Identifiable, Hashable {
    let product: ShoppingProduct
    /// `nil` = bez ilości („kup to”).
    var amount: ShoppingAmount?

    var id: String { product.nameKey }
}

/// Wysłane „Dodaj N produktów”: wybór w chwili wysłania i jego
/// `clientMutationId`.
struct ShoppingAddSubmission {
    let id: UUID
    let drafts: [ShoppingProductDraft]
}

/// Wybór na wszystkich stronach arkusza naraz (dodawanie, dział, własny
/// produkt) — licznik w „Dodaj do listy” mówi o całości, a nie o stronie.
@MainActor
@Observable
final class ShoppingAddSelection {
    private(set) var drafts: [ShoppingProductDraft] = []
    /// Wiersz z rozwiniętym edytorem ilości.
    var editingKey: String?
    /// Wysłany wybór, którego los nie jest znany: zapis trwa albo zerwał
    /// się bez odpowiedzi (serwer mógł go przyjąć). Dopóki jest, wybór stoi
    /// w miejscu, a ponowienie wysyła DOKŁADNIE to samo pod tym samym id —
    /// zmiana wyboru po zgubionym ACK-u dopisywała mleko drugi raz pod nowym
    /// id, a sukces kasował produkty wybrane w trakcie zapisu.
    private(set) var submission: ShoppingAddSubmission?

    var isEmpty: Bool { drafts.isEmpty }
    var count: Int { drafts.count }
    /// Wiersze, ilości i „Własny produkt” nie zmieniają wyboru.
    var isLocked: Bool { submission != nil }

    func draft(for product: ShoppingProduct) -> ShoppingProductDraft? {
        drafts.first { $0.id == product.nameKey }
    }

    func contains(_ product: ShoppingProduct) -> Bool {
        draft(for: product) != nil
    }

    /// Stuknięcie w „+” albo w ptaszek. Ilość z „ostatnio dodawanych” idzie
    /// za produktem, ale tylko w jednostce, którą wolno (wiersz na liście).
    func toggle(_ product: ShoppingProduct, suggested: ShoppingAmount? = nil, allowed: [ShoppingAmountUnit]) {
        guard !isLocked else { return }
        if let index = drafts.firstIndex(where: { $0.id == product.nameKey }) {
            drafts.remove(at: index)
            if editingKey == product.nameKey { editingKey = nil }
            return
        }
        let amount = suggested.flatMap { allowed.contains($0.unit) ? $0 : nil }
        drafts.append(ShoppingProductDraft(product: product, amount: amount))
    }

    /// Dodaje albo podmienia (własny produkt wraca z ekranu „Własny produkt”).
    func put(_ draft: ShoppingProductDraft) {
        guard !isLocked else { return }
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index] = draft
        } else {
            drafts.append(draft)
        }
    }

    func setAmount(_ amount: ShoppingAmount?, for product: ShoppingProduct) {
        guard !isLocked, let index = drafts.firstIndex(where: { $0.id == product.nameKey }) else { return }
        drafts[index].amount = amount
    }

    /// „Wyczyść” i wyjście z dodawania — także porzucenie zerwanej operacji.
    func clear() {
        drafts = []
        editingKey = nil
        submission = nil
    }

    /// Co wysłać: nowa operacja z bieżącego wyboru albo — po zerwanym
    /// zapisie — ta sama, co poprzednio.
    func beginSubmission() -> ShoppingAddSubmission? {
        if let submission { return submission }
        guard !drafts.isEmpty else { return nil }
        let next = ShoppingAddSubmission(id: UUID(), drafts: drafts)
        submission = next
        editingKey = nil
        return next
    }

    /// Zapis przeszedł. Czyści tylko, gdy to wciąż ta operacja (wybór
    /// porzucony w trakcie i zaczęty od nowa zostaje); `false` = nie ta.
    @discardableResult
    func completeSubmission(_ id: UUID) -> Bool {
        guard submission?.id == id else { return false }
        clear()
        return true
    }

    /// Zapis się nie udał. Tylko `VALIDATION_ERROR` dowodzi, że nic nie
    /// zapisano: treść sprawdza się tak samo przy każdej próbie, a operację,
    /// która przeszła, serwer rozpoznaje po id PRZED liczeniem ilości.
    /// Każda inna odmowa (429 z limitu, 401, 403, 5xx), przekroczony czas
    /// i zerwane połączenie mogą przyjść z automatycznego ponowienia po
    /// zapisie, który przeszedł — wybór zostaje zamrożony do ponowienia tym
    /// samym id albo „Wyczyść”.
    func failSubmission(_ id: UUID, error: Error) {
        guard submission?.id == id else { return }
        if case let RecipeDataError.server(code, _, _, _) = error, code == "VALIDATION_ERROR" {
            submission = nil
        }
    }
}

// MARK: - Lista a produkt

extension ShoppingItem {
    /// Nazwa z klucza (`mleko::ml` → `mleko`) — po niej produkt z arkusza
    /// znajduje swój wiersz, także gdy nazwa na ekranie ma dopisek jednostki.
    var productNameKey: String {
        guard let range = productKey.range(of: "::", options: .backwards) else {
            return productKey.lowercased()
        }
        return String(productKey[..<range.lowerBound]).lowercased()
    }

    /// Jednostka wiersza listy; `nil` = wiersz bez ilości.
    var listUnit: String? { unit.isEmpty ? nil : unit }
}

extension Array where Element == ShoppingItem {
    /// Wiersz produktu na liście (pierwszy, gdy produkt stoi w dwóch jednostkach).
    func row(for product: ShoppingProduct) -> ShoppingItem? {
        first { $0.productNameKey == product.nameKey }
    }
}
