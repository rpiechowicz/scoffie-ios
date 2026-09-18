import Combine
import UIKit
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
    /// Stan własnego paska (zwinięty / klawiatura). Żyje tu, bo menu jest
    /// jedynym miejscem, które przeżywa przełączanie zakładek.
    @State private var chrome = SCTabBarChrome()

    var body: some View {
        @Bindable var session = sessionStore

        // Systemowy pasek jest schowany na każdej zakładce, a w jego miejscu
        // stoi `SCFloatingTabBar` w `overlay` nad całym `TabView`. `TabView`
        // zostaje: trzyma wybór, leniwe budowanie zakładek i przełączanie
        // z zewnątrz (asystent → Plan). Zmieniamy wyłącznie to, co widać.
        return TabView(selection: $session.dashboardTab) {
            Tab(MenuConstans.Recipes.name, systemImage: MenuConstans.Recipes.icon, value: DashboardTab.recipes) {
                page { RecipesView() }
            }

            Tab(MenuConstans.Plan.name, systemImage: MenuConstans.Plan.icon, value: DashboardTab.plan) {
                page { WeeklyPlanView() }
            }

            Tab(MenuConstans.Calendar.name, systemImage: MenuConstans.Calendar.icon, value: DashboardTab.calendar) {
                page { CalendarView() }
            }

            // Asystent zajął miejsce „Produktów": to do niego wraca się
            // wiele razy w tygodniu, a lista zakupów powstaje przy Planie
            // i tam też ma swoje wejście.
            Tab(MenuConstans.Assistant.name, systemImage: MenuConstans.Assistant.icon, value: DashboardTab.assistant) {
                page {
                    if let agentStore = sessionStore.agentStore {
                        AssistantView(store: agentStore)
                    } else {
                        AssistantUnavailableView()
                    }
                }
            }

            Tab(MenuConstans.Settings.name, systemImage: MenuConstans.Settings.icon, value: DashboardTab.settings) {
                page { SettingsView() }
            }
        }
        .tint(SCPalette.terracotta)
        .overlay(alignment: .bottom) {
            SCFloatingTabBar(items: items, selection: $session.dashboardTab, isCompact: chrome.isCompact)
                // Klawiatura ma pasek ZASŁONIĆ, jak systemowy — bez tego
                // `overlay` uciekałby nad klawiaturę i stawał między nią
                // a polem asystenta.
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .environment(\.scTabBarChrome, chrome)
        // Nowa zakładka zaczyna z pełnym paskiem: stan zwinięcia należy
        // do przewijania, które użytkownik właśnie opuścił.
        .onChange(of: session.dashboardTab) { _, _ in
            chrome.isCompact = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            chrome.isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            chrome.isKeyboardVisible = false
        }
    }

    private var items: [SCTabBarItem] {
        [
            SCTabBarItem(tab: .recipes, title: MenuConstans.Recipes.name, icon: MenuConstans.Recipes.icon),
            SCTabBarItem(tab: .plan, title: MenuConstans.Plan.name, icon: MenuConstans.Plan.icon),
            SCTabBarItem(tab: .calendar, title: MenuConstans.Calendar.name, icon: MenuConstans.Calendar.icon),
            // Odpowiedź potrafi dojść, gdy użytkownik ogląda plan — bez tej
            // plakietki musiałby sam wracać i sprawdzać, czy już jest.
            SCTabBarItem(
                tab: .assistant,
                title: MenuConstans.Assistant.name,
                icon: MenuConstans.Assistant.icon,
                badge: sessionStore.agentStore?.unseenAnswers ?? 0
            ),
            SCTabBarItem(tab: .settings, title: MenuConstans.Settings.name, icon: MenuConstans.Settings.icon),
        ]
    }

    /// Treść zakładki bez paska systemowego, z rezerwą miejsca pod własny.
    ///
    /// Rezerwa wchodzi bezpiecznym obszarem, nie paddingiem: `ScrollView`
    /// przewija wtedy treść POD szkłem paska (widać ją przez nie), a kończy
    /// nad nim — dokładnie jak z paskiem systemowym. Wysokość jest stała
    /// (od pełnego paska), więc zwijanie nie rusza układu. Przy klawiaturze
    /// rezerwa schodzi do zera, bo pasek i tak jest pod nią.
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .toolbarVisibility(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: chrome.isKeyboardVisible ? 0 : SCFloatingTabBar.reservedHeight)
                    .animation(.easeOut(duration: 0.25), value: chrome.isKeyboardVisible)
            }
    }
}

#Preview {
    NavigationMenu()
}
