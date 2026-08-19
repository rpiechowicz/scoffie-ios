import SwiftUI
/// Stałe i pomocnicze funkcje związane z widokiem/przepisami.
enum RecipesConstants {
    /// Polski tytuł dla kategorii przepisu.
    static func displayName(for category: RecipesCategory) -> String {
        switch category {
        case .all:
            return "Wszystkie"
        case .favourite:
            return "Ulubione"
        case .breakfast:
            return "Śniadania"
        case .lunch:
            return "Obiady"
        case .dinner:
            return "Kolacje"
        @unknown default:
            return String(describing: category)
        }
    }

    /// Ikona SF Symbol dla kategorii przepisu.
    static func icon(for category: RecipesCategory) -> String {
        switch category {
        case .all:       return "square.grid.2x2"
        case .favourite: return "heart.fill"
        case .breakfast: return "sunrise.fill"
        case .lunch:     return "fork.knife"
        case .dinner:    return "moon.stars.fill"
        @unknown default: return "questionmark.circle"
        }
    }

    /// Ikona SF Symbol dla poziomu trudności przepisu.
    static func icon(for difficulty: Difficulty) -> String {
        switch difficulty {
        case .easy:   return "leaf.fill"
        case .medium: return "flame.fill"
        case .hard:   return "bolt.fill"
        }
    }

    static func tint(for category: RecipesCategory) -> Color {
        switch category {
        case .all:
            return .blue
        case .favourite:
            return .pink
        case .breakfast:
            return .orange
        case .lunch:
            return .blue
        case .dinner:
            return .purple
        @unknown default:
            return .teal
        }
    }
}
