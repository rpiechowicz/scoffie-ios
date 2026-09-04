import SwiftUI

// MARK: - SwiftUI Environment keys for app stores
//
// Provides safe defaults so SwiftUI previews and tests can run without a real
// backend. Production code injects the real instances at the root of the view
// tree (see `ScoffieApp` / SessionStore wiring).

private struct SessionStoreKey: EnvironmentKey {
    @MainActor static let defaultValue = SessionStore()
}

private struct WeeklyMealStoreKey: EnvironmentKey {
    static let defaultValue = WeeklyMealStore()
}

private struct DatesViewModelKey: EnvironmentKey {
    static let defaultValue = DatesViewModel()
}

private struct ShoppingListStoreKey: EnvironmentKey {
    @MainActor static let defaultValue = ShoppingListStore(
        repository: ApiShoppingListRepository(
            client: WebSocketShoppingListTransportClient(
                socket: UnconfiguredRecipeSocketClient(),
                userId: "mock-user"
            )
        ),
        currentUserId: "mock-user"
    )
}

extension EnvironmentValues {
    var sessionStore: SessionStore {
        get { self[SessionStoreKey.self] }
        set { self[SessionStoreKey.self] = newValue }
    }

    var weeklyMealStore: WeeklyMealStore {
        get { self[WeeklyMealStoreKey.self] }
        set { self[WeeklyMealStoreKey.self] = newValue }
    }

    var datesViewModel: DatesViewModel {
        get { self[DatesViewModelKey.self] }
        set { self[DatesViewModelKey.self] = newValue }
    }

    var shoppingListStore: ShoppingListStore {
        get { self[ShoppingListStoreKey.self] }
        set { self[ShoppingListStoreKey.self] = newValue }
    }
}
