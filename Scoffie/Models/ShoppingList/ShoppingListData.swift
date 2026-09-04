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

    var totalCount: Int { items.count }
    var boughtCount: Int { items.filter(\.isChecked).count }

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
}
