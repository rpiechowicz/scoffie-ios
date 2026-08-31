import SwiftUI

struct NavigationMenu: View {
    private enum DashboardTab: Hashable {
        case recipes
        case plan
        case calendar
        case assistant
        case settings
    }

    @Environment(\.sessionStore) private var sessionStore

    @State private var selectedTab: DashboardTab = .calendar

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(MenuConstans.Recipes.name, systemImage: MenuConstans.Recipes.icon, value: DashboardTab.recipes) {
                RecipesView()
            }

            Tab(MenuConstans.Plan.name, systemImage: MenuConstans.Plan.icon, value: DashboardTab.plan) {
                WeeklyPlanView()
            }

            Tab(MenuConstans.Calendar.name, systemImage: MenuConstans.Calendar.icon, value: DashboardTab.calendar) {
                CalendarView()
            }

            // Asystent zajął miejsce „Produktów": to do niego wraca się
            // wiele razy w tygodniu, a lista zakupów powstaje przy Planie
            // i tam też ma swoje wejście.
            Tab(MenuConstans.Assistant.name, systemImage: MenuConstans.Assistant.icon, value: DashboardTab.assistant) {
                if let agentStore = sessionStore.agentStore {
                    AssistantView(store: agentStore)
                } else {
                    AssistantUnavailableView()
                }
            }

            Tab(MenuConstans.Settings.name, systemImage: MenuConstans.Settings.icon, value: DashboardTab.settings) {
                SettingsView()
            }
        }
        .tint(WMPalette.terracotta)
    }
}

#Preview {
    NavigationMenu()
}
