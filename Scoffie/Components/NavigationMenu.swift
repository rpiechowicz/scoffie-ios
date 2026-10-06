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

private struct SCTabIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Czy ekran stoi na WYBRANEJ zakładce. `TabView` trzyma raz zbudowaną
    /// zakładkę przy życiu także wtedy, gdy jej nie widać, więc „użytkownik
    /// tu wszedł" mówi ta flaga (`onChange(of:initial:)`), a nie `onAppear`.
    /// Poza menu (arkusze, podglądy) `true`.
    var scTabIsActive: Bool {
        get { self[SCTabIsActiveKey.self] }
        set { self[SCTabIsActiveKey.self] = newValue }
    }
}

// MARK: - Stan wspólny zakładek

/// To, co zakładki przekazują sobie ponad `TabView` — i nic więcej.
///
/// Dawniej stan WŁASNEGO paska zakładek (zwinięcie „jak Revolut”, klawiatura,
/// rezerwa miejsca pod treścią). Od przejścia na systemowy `TabView` (6.10.2026,
/// decyzja Rafała: aplikacja „jak od Apple”) pasek, jego zwijanie, miejsce pod
/// treścią i ruch z klawiaturą robi system. Zostało:
/// - `compactTitles` — kapsuła z tytułem pod paskiem stanu (`SCCompactTitle`),
///   którą rysuje `NavigationMenu` nad wszystkimi zakładkami;
/// - `keyboardCurve` — krzywa klawiatury dla wszystkiego, co jedzie z polem
///   nad klawiaturą (powitanie Asystenta).
@Observable
final class SCTabBarChrome {
    /// Tytuł do kapsuły pod paskiem stanu (`SCCompactTitle`) dla zakładek,
    /// których duży tytuł zjechał już pod górną krawędź.
    var compactTitles: [DashboardTab: String] = [:]

    /// Krzywa klawiatury iOS — krzywa 7 z `UIKeyboardAnimationCurveUserInfoKey`
    /// nie ma publicznego odpowiednika; to jej znane przybliżenie Béziera.
    /// JEDNA dla wszystkiego, co jedzie z polem nad klawiaturą (powitanie
    /// Asystenta) — dwie różne krzywe rozjeżdżały pole i blok nad nim
    /// o kilka klatek.
    static func keyboardCurve(duration: Double) -> Animation {
        .timingCurve(0.38, 0.7, 0.125, 1, duration: max(duration, 0.2))
    }
}

private struct SCTabBarChromeKey: EnvironmentKey {
    @MainActor static let defaultValue = SCTabBarChrome()
}

extension EnvironmentValues {
    var scTabBarChrome: SCTabBarChrome {
        get { self[SCTabBarChromeKey.self] }
        set { self[SCTabBarChromeKey.self] = newValue }
    }
}

// MARK: - Menu

/// Pulpit: systemowy `TabView` z iOS 26 (Liquid Glass) i pięć zakładek.
///
/// Do 6.10.2026 stał tu własny kontener (`ZStack`) z własnym paskiem
/// (`SCFloatingTabBar`): wszystkie zakładki budowały się pod loaderem,
/// zmiana zakładki przenikała, pasek zwijał się do samych ikon i miał jeden
/// gest przeciągania pigułki. Rafał zdecydował: aplikacja „jak od Apple” —
/// systemowy pasek, systemowe zwijanie przy przewijaniu (do bieżącej
/// zakładki), cięcie przy zmianie zakładki. W zamian system robi sam:
/// miejsce pod treścią, efekt krawędzi przewijania pod paskiem i to, że
/// klawiatura zasłania pasek, a wstawki zakładek (pole Asystenta, pasek
/// szukania Przepisów, pigułka „Cel dnia”) jadą nad nią.
///
/// `TabView` buduje zakładkę dopiero przy pierwszym wyborze. To, co dawniej
/// zakładki robiły same pod loaderem, a co ma się dziać bez nich (rozmowa
/// asystenta wraca do tury w biegu, pula), robi start sesji
/// (`SessionStore.prepareUnbuiltTabs`).
struct NavigationMenu: View {
    @Environment(\.sessionStore) private var sessionStore
    /// Stan wspólny zakładek. Żyje tu, bo menu jest jedynym miejscem, które
    /// przeżywa przełączanie zakładek.
    @State private var chrome = SCTabBarChrome()

    var body: some View {
        @Bindable var session = sessionStore
        let selected = session.dashboardTab
        let compactTitle = chrome.compactTitles[selected]

        return TabView(selection: $session.dashboardTab) {
            Tab(MenuConstans.Recipes.name, systemImage: MenuConstans.Recipes.icon, value: DashboardTab.recipes) {
                page(.recipes, isActive: selected == .recipes)
            }
            Tab(MenuConstans.Plan.name, systemImage: MenuConstans.Plan.icon, value: DashboardTab.plan) {
                page(.plan, isActive: selected == .plan)
            }
            Tab(MenuConstans.Calendar.name, systemImage: MenuConstans.Calendar.icon, value: DashboardTab.calendar) {
                page(.calendar, isActive: selected == .calendar)
            }
            // Odpowiedź potrafi dojść, gdy użytkownik ogląda plan — bez tej
            // plakietki musiałby sam wracać i sprawdzać, czy już jest.
            Tab(MenuConstans.Assistant.name, systemImage: MenuConstans.Assistant.icon, value: DashboardTab.assistant) {
                page(.assistant, isActive: selected == .assistant)
            }
            .badge(sessionStore.agentStore?.unseenAnswers ?? 0)
            Tab(MenuConstans.Settings.name, systemImage: MenuConstans.Settings.icon, value: DashboardTab.settings) {
                page(.settings, isActive: selected == .settings)
            }
        }
        // Przewijanie w dół zwija pasek, w górę rozwija — systemowo.
        .tabBarMinimizeBehavior(.onScrollDown)
        // Wybrana zakładka w terakocie; reszta w kolorze systemu. Ten sam
        // akcent dziedziczą zakładki (był tu i przy własnym kontenerze).
        .tint(SCPalette.terracotta)
        // Pod paskiem stanu treść CHOWA SIĘ — rozmywa i gaśnie — zamiast
        // przejeżdżać ostro pod zegarem i Dynamic Island (Telegram, iOS 26).
        // Jeden pas na wszystkie zakładki, w samym górnym bezpiecznym obszarze.
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                SCStatusBarBlur(extends: compactTitle == nil ? 0 : SCCompactTitle.blurExtension)

                // Duży tytuł zjechał — jego miejsce pod paskiem stanu bierze
                // szklana kapsuła (Telegram). Zmiana zakładki = cięcie, jak
                // treść; animuje się tylko pojawienie i zniknięcie.
                if let compactTitle {
                    SCCompactTitle(title: compactTitle)
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
                }
            }
            .animation(.smooth(duration: 0.3), value: compactTitle == nil)
        }
        .environment(\.scTabBarChrome, chrome)
    }

    private func page(_ tab: DashboardTab, isActive: Bool) -> some View {
        content(of: tab)
            .environment(\.scTabIsActive, isActive)
    }

    @ViewBuilder
    private func content(of tab: DashboardTab) -> some View {
        switch tab {
        case .recipes:
            RecipesView()
        case .plan:
            WeeklyPlanView()
        case .calendar:
            // Zakładka „Dziś” (6.10.2026): sama trzyma wczoraj · dziś · jutro,
            // bez tygodnia — `datesViewModel` z korzenia należy do Planu.
            CalendarView()
        case .assistant:
            // Asystent zajął miejsce „Produktów": to do niego wraca się
            // wiele razy w tygodniu, a lista zakupów powstaje przy Planie
            // i tam też ma swoje wejście.
            if let agentStore = sessionStore.agentStore {
                AssistantView(store: agentStore)
            } else {
                AssistantUnavailableView()
            }
        case .settings:
            SettingsView()
        }
    }
}

#Preview {
    NavigationMenu()
}
