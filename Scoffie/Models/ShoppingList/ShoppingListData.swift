import Foundation

/// One archived ("zamknięty") shopping list — produced when the user closes
/// a week's list. Multiple archives can exist per week (revisions).
struct ArchivedShoppingList: Identifiable, Codable, Hashable {
    let archiveId: String
    let weekStart: String
    let weekLabel: String
    let revision: Int
    let archivedAt: Date
    let isCurrentClosed: Bool
    let items: [ShoppingItem]

    var id: String { archiveId }

    private enum CodingKeys: String, CodingKey {
        case archiveId
        case weekStart
        case weekLabel
        case revision
        case archivedAt
        case isCurrentClosed
        case items
    }

    init(
        archiveId: String = UUID().uuidString,
        weekStart: String,
        weekLabel: String,
        revision: Int,
        archivedAt: Date,
        isCurrentClosed: Bool,
        items: [ShoppingItem]
    ) {
        self.archiveId = archiveId
        self.weekStart = weekStart
        self.weekLabel = weekLabel
        self.revision = revision
        self.archivedAt = archivedAt
        self.isCurrentClosed = isCurrentClosed
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        archiveId = try container.decodeIfPresent(String.self, forKey: .archiveId) ?? UUID().uuidString
        weekStart = try container.decode(String.self, forKey: .weekStart)
        weekLabel = try container.decode(String.self, forKey: .weekLabel)
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        archivedAt = try container.decode(Date.self, forKey: .archivedAt)
        isCurrentClosed = try container.decodeIfPresent(Bool.self, forKey: .isCurrentClosed) ?? false
        items = try container.decode([ShoppingItem].self, forKey: .items)
    }
}

/// Snapshot of a week's shopping list (current open list + all archives).
struct ShoppingListState: Codable {
    let items: [ShoppingItem]
    let archives: [ArchivedShoppingList]
    /// Ostatnio dopisywane w domu (arkusz „Dodaj produkty”). Opcjonalne —
    /// stan z cache'u sprzed tego pola dalej się dekoduje.
    var recentProducts: [ShoppingRecentProduct]? = nil
}

// MARK: - Własne produkty (13.10.2026)
//
// Typy danych dopisywania produktów — tutaj, a nie w `ShoppingProducts.swift`,
// bo potrzebują tylko Foundation i używają ich model pozycji i DTO, które
// kompiluje też `Scripts/plan-store-check.sh` (bez szukania i SwiftUI).

/// Produkt, który da się dopisać: z katalogu (`ingredientId`) albo własny.
struct ShoppingProduct: Identifiable, Hashable, Codable {
    let name: String
    let department: String
    /// `nil` = własna nazwa domu, spoza katalogu.
    let ingredientId: String?
    /// Ma masę sztuki — na liście zawsze w sztukach (jak w planie).
    let pieceOnly: Bool
    let aliases: [String]

    var id: String { nameKey }
    var isCustom: Bool { ingredientId == nil }

    /// Ta sama postać, co część nazwy w `productKey` listy (`mleko::ml` →
    /// `mleko`) — po niej produkt znajduje swój wiersz na liście.
    var nameKey: String { Self.nameKey(name) }

    static func nameKey(_ name: String) -> String {
        name
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    /// Nazwa z wielkiej litery, białe znaki zwinięte — jak serwer
    /// (`cleanProductName` + `toTitleCase`).
    static func displayName(_ raw: String) -> String {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let first = collapsed.first else { return collapsed }
        return first.uppercased() + collapsed.dropFirst()
    }
}

/// Ostatnio dopisywane w domu (ze stanu listy) — z ostatnią ilością.
struct ShoppingRecentProduct: Codable, Hashable {
    let name: String
    let department: String
    let ingredientId: String?
    /// Ilość w jednostce listy (`szt` / `g` / `ml`); `nil` = bez ilości.
    let amount: Double?
    let unit: String?
}

/// Część wiersza dopisana ręcznie (`manual` ze stanu listy).
struct ShoppingManualPart: Codable, Hashable {
    /// W jednostce listy; `nil` = „kup to” bez ilości.
    let amount: Double?
    let unit: String?
    let addedById: String?
    /// Ostatnie dopisanie albo zmiana ilości — ms od epoki, jak `archivedAt`.
    /// `nil` w pliku listy sprzed tej wersji.
    var addedAt: Double? = nil

    var addedDate: Date? {
        addedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
    }
}

/// „1,5 kg”, „2 szt”, „1300 ml → 1,3 l” — liczba po polsku z jednostką.
enum ShoppingAmountText {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    static func format(_ value: Double, unit: String) -> String {
        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(number) \(unit)"
    }

    /// Ilość w jednostce listy, z kilogramami i litrami od tysiąca.
    static func list(_ amount: Double, unit: String) -> String {
        switch unit {
        case "g" where amount >= 1000: return format(amount / 1000, unit: "kg")
        case "ml" where amount >= 1000: return format(amount / 1000, unit: "l")
        default: return format(amount, unit: unit)
        }
    }
}
