import SwiftUI

/// Zakładki dolnego menu.
///
/// Wybór mieszka w `SessionStore`, a nie w `@State` menu, bo przełącza go też
/// kod spoza menu: asystent po zapisaniu planu daje skrót „Otwórz", który ma
/// przenieść użytkownika na Plan tygodnia.
enum DashboardTab: Hashable {
    case recipes
    case plan
    case calendar
    case assistant
    case settings
}

struct NavigationMenu: View {
    @Environment(\.sessionStore) private var sessionStore

    var body: some View {
        @Bindable var session = sessionStore

        return TabView(selection: $session.dashboardTab) {
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
            // Odpowiedź potrafi dojść, gdy użytkownik ogląda plan — bez tej
            // kropki musiałby sam wracać i sprawdzać, czy już jest.
            .badge(sessionStore.agentStore?.unseenAnswers ?? 0)

            Tab(MenuConstans.Settings.name, systemImage: MenuConstans.Settings.icon, value: DashboardTab.settings) {
                SettingsView()
            }
        }
        .tint(SCPalette.terracotta)
    }
}

#Preview {
    NavigationMenu()
}
