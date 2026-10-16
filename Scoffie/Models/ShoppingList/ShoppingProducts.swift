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

/// Jednostki, w których ilość jedzie na serwer. Serwer trzyma ją w jednostce
/// listy (`szt` / `g` / `ml`) — kilogramy i litry są tylko wygodą zapisu.
enum ShoppingAmountUnit: String, CaseIterable, Codable, Identifiable {
    case piece = "szt"
    case gram = "g"
    case kilogram = "kg"
    case milliliter = "ml"
    case liter = "l"

    var id: String { rawValue }

    /// Jednostka listy, do której serwer sprowadza tę jednostkę.
    var listUnit: String { kind.listUnit }

    var kind: ShoppingAmountKind {
        switch self {
        case .piece: return .pieces
        case .gram, .kilogram: return .weight
        case .milliliter, .liter: return .volume
        }
    }
}

/// JAK się to kupuje: na sztuki, na wagę albo na objętość (16.10.2026).
///
/// Wcześniej arkusz dawał każdemu produktowi pięć jednostek naraz („szt g kg
/// ml l”) z krokiem 250 ml — Rafał: „nie ma sensu kupować 222 ml piwa, tylko
/// sztuki”. Teraz produkt dostaje rodzaje, które mają sens w sklepie (dział
/// i masa sztuki), a gramy z kilogramami (i mililitry z litrami) to JEDEN
/// rodzaj, który sam przechodzi w większą jednostkę. Krok idzie po drabinie
/// ilości, jakie się kupuje (50 g … 1 kg … 1,5 kg), a nie po stałym kroku.
enum ShoppingAmountKind: String, CaseIterable, Identifiable {
    case pieces
    case weight
    case volume

    var id: String { rawValue }

    /// Etykieta przełącznika.
    var chipTitle: String {
        switch self {
        case .pieces: return "szt"
        case .weight: return "g · kg"
        case .volume: return "ml · l"
        }
    }

    var listUnit: String {
        switch self {
        case .pieces: return "szt"
        case .weight: return "g"
        case .volume: return "ml"
        }
    }

    /// Pierwsza ilość po wybraniu rodzaju (w jednostce listy).
    var defaultListValue: Double {
        switch self {
        case .pieces: return 1
        case .weight: return 500
        case .volume: return 1000
        }
    }

    /// Ilości, po których chodzi stepper (w jednostce listy). Sufit = ten
    /// sam co na serwerze (`SHOPPING_PRODUCT_INPUT_LIMITS`: 99 szt, 20 kg, 20 l).
    var ladder: [Double] { Self.ladders[self] ?? [] }

    private static let ladders: [ShoppingAmountKind: [Double]] = [
        .pieces: rungs([(1, 99, 1)]),
        // 50 g … 250 g co 50, do 1 kg co 100, do 5 kg co pół, dalej co kilogram.
        .weight: rungs([(50, 250, 50), (300, 900, 100), (1000, 4500, 500), (5000, 20_000, 1000)]),
        // Butelki i kartony: 0,33 l i 0,75 l też są szczeblami.
        .volume: [100, 200, 250, 330, 500, 750] + rungs([(1000, 2500, 500), (3000, 20_000, 1000)])
    ]

    /// Szczeble z odcinków (od, do włącznie, krok).
    private static func rungs(_ spans: [(from: Double, through: Double, by: Double)]) -> [Double] {
        var values: [Double] = []
        for span in spans {
            values.append(contentsOf: stride(from: span.from, through: span.through, by: span.by))
        }
        return values
    }

    /// Rodzaje do wyboru — pierwszy jest domyślny.
    ///
    /// Produkt, który JUŻ stoi na liście, dostaje tylko rodzaj swojego
    /// wiersza — inaczej dopisanie zrobiłoby drugi wiersz „Mleko (szt)” obok
    /// „Mleko (ml)”. Produkt z masą sztuki — same sztuki, jak w planie.
    /// Reszta idzie za działem sklepu: napoje, alkohol, chemia, pieczywo,
    /// słodycze, przekąski, konserwy, mrożonki, przyprawy i oleje kupuje się
    /// na sztuki (butelka, puszka, paczka); mięso i ryby na wagę; warzywa,
    /// owoce, nabiał i produkty sypkie — na sztuki albo na wagę. Objętość
    /// zostaje tylko dla wiersza z planu w mililitrach.
    static func allowed(listUnit: String?, pieceOnly: Bool, department: String) -> [ShoppingAmountKind] {
        switch listUnit {
        case "szt": return [.pieces]
        case "g": return [.weight]
        case "ml": return [.volume]
        default: break
        }
        if pieceOnly { return [.pieces] }
        switch department {
        case ProductConstants.Department.meat,
             ProductConstants.Department.fish:
            return [.weight, .pieces]
        case ProductConstants.Department.vegetables,
             ProductConstants.Department.fruits,
             ProductConstants.Department.dairy,
             ProductConstants.Department.grains,
             ProductConstants.Department.other:
            return [.pieces, .weight]
        default:
            return [.pieces]
        }
    }
}

/// Ilość wybrana w arkuszu.
struct ShoppingAmount: Hashable, Codable {
    var value: Double
    var unit: ShoppingAmountUnit

    var kind: ShoppingAmountKind { unit.kind }

    /// Ilość w jednostce listy (dla podglądu sumy i dla stepera).
    var listValue: Double {
        switch unit {
        case .kilogram, .liter: return (value * 1000 * 100).rounded() / 100
        default: return value
        }
    }

    var text: String { ShoppingAmountText.format(value, unit: unit.rawValue) }

    /// Pierwsza ilość danego rodzaju.
    static func initial(_ kind: ShoppingAmountKind) -> ShoppingAmount {
        make(listValue: kind.defaultListValue, kind: kind)
    }

    /// Z jednostki listy na wygodną: 1500 g → 1,5 kg, 1000 ml → 1 l.
    static func fromList(amount: Double?, unit: String?) -> ShoppingAmount? {
        guard let amount, amount > 0 else { return nil }
        switch unit {
        case "g": return make(listValue: amount, kind: .weight)
        case "ml": return make(listValue: amount, kind: .volume)
        case "szt": return make(listValue: amount, kind: .pieces)
        default: return nil
        }
    }

    /// Ilość w jednostce listy → do pokazania: od tysiąca kilogramy i litry.
    static func make(listValue: Double, kind: ShoppingAmountKind) -> ShoppingAmount {
        switch kind {
        case .pieces:
            return ShoppingAmount(value: listValue, unit: .piece)
        case .weight:
            return listValue >= 1000
                ? ShoppingAmount(value: listValue / 1000, unit: .kilogram)
                : ShoppingAmount(value: listValue, unit: .gram)
        case .volume:
            return listValue >= 1000
                ? ShoppingAmount(value: listValue / 1000, unit: .liter)
                : ShoppingAmount(value: listValue, unit: .milliliter)
        }
    }

    /// Następna ilość z drabiny w górę albo w dół. W dół poniżej pierwszego
    /// szczebla = bez ilości. Ilość spoza drabiny (zapisana wcześniej, np.
    /// 1,3 kg) przeskakuje na najbliższy szczebel w daną stronę.
    func stepped(by direction: Int) -> ShoppingAmount? {
        let ladder = kind.ladder
        let current = listValue
        let next: Double?
        if direction > 0 {
            next = ladder.first { $0 > current + 0.000_1 } ?? ladder.last
        } else {
            next = ladder.last { $0 < current - 0.000_1 }
        }
        guard let next else { return nil }
        return Self.make(listValue: next, kind: kind)
    }

    /// Czy da się jeszcze dołożyć (sufit drabiny).
    var canStepUp: Bool {
        guard let top = kind.ladder.last else { return false }
        return listValue < top - 0.000_1
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
    /// Wysłany wybór, którego sukcesu nie potwierdzono: zapis trwa albo się
    /// nie udał. Dopóki jest, wybór stoi w miejscu, a ponowienie wysyła
    /// DOKŁADNIE to samo pod tym samym id; porzuca go tylko „Wyczyść” albo
    /// wyjście z dodawania. Po KAŻDYM błędzie, bez wyjątków dla kodów:
    /// odmowa może przyjść z automatycznego ponowienia `emitWithAck` po
    /// zapisie, który przeszedł (429, a przy zmianie katalogu w trakcie
    /// nawet walidacja). Zmiana wyboru po takim błędzie dopisywała mleko
    /// drugi raz pod nowym id, a sukces kasował produkty wybrane w trakcie.
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
    /// za produktem, ale tylko w rodzaju, który wolno (wiersz na liście).
    func toggle(_ product: ShoppingProduct, suggested: ShoppingAmount? = nil, allowed: [ShoppingAmountKind]) {
        guard !isLocked else { return }
        if let index = drafts.firstIndex(where: { $0.id == product.nameKey }) {
            drafts.remove(at: index)
            if editingKey == product.nameKey { editingKey = nil }
            return
        }
        let amount = suggested.flatMap { allowed.contains($0.kind) ? $0 : nil }
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
