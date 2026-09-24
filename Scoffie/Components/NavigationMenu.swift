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

private struct SCTabIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Czy ekran stoi na WYBRANEJ zakładce. Wszystkie zakładki żyją naraz
    /// (patrz `NavigationMenu`), więc `onAppear` nie mówi już „użytkownik
    /// tu wszedł" — mówi to ta flaga. Poza menu (arkusze, podglądy) `true`.
    var scTabIsActive: Bool {
        get { self[SCTabIsActiveKey.self] }
        set { self[SCTabIsActiveKey.self] = newValue }
    }
}

struct NavigationMenu: View {
    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.colorScheme) private var colorScheme
    /// Stan własnego paska (zwinięty / klawiatura). Żyje tu, bo menu jest
    /// jedynym miejscem, które przeżywa przełączanie zakładek.
    @State private var chrome = SCTabBarChrome()
    /// Zakładki już zbudowane. Wybrana buduje się od razu, reszta po kolei
    /// w tle — patrz `warmUpRemainingTabs`.
    @State private var mounted: Set<DashboardTab> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Zakładka, która właśnie wchodzi, i jej krycie. Samo krycie, bez
    /// przesunięcia i bez `keyframeAnimator` na całej stronie: to renderuje
    /// warstwa, a ekran zakładki nie przelicza się w żadnej klatce wejścia.
    @State private var enteringTab: DashboardTab?
    @State private var entranceOpacity: Double = 1
    /// Zakładka, z której się wychodzi — stoi pod wchodzącą, dopóki ta
    /// nie nabierze pełnego krycia (patrz `tabSelection`).
    @State private var leavingTab: DashboardTab?

    private func pageOpacity(_ tab: DashboardTab, isActive: Bool) -> Double {
        if isActive { return tab == enteringTab ? entranceOpacity : 1 }
        return tab == leavingTab ? 1 : 0
    }

    private static let order: [DashboardTab] = [.recipes, .plan, .calendar, .assistant, .settings]

    var body: some View {
        @Bindable var session = sessionStore

        // Własny kontener zamiast `TabView`. `TabView` buduje zakładkę dopiero
        // przy pierwszym wyborze, więc pierwsze wejście na każdą z nich po
        // uruchomieniu kosztowało zgubione klatki (cały ekran + jego dane
        // w jednej klatce), a od iOS 18 dokładał własne przenikanie treści.
        // Tu wszystkie zakładki budują się POD loaderem startowym i potem
        // tylko zmieniają widoczność: przełączenie jest cięciem w jednej
        // klatce, bez budowania czegokolwiek.
        return ZStack {
            ForEach(Self.order, id: \.self) { tab in
                if mounted.contains(tab) || tab == session.dashboardTab {
                    let isActive = tab == session.dashboardTab
                    page(tab)
                        .environment(\.scTabIsActive, isActive)
                        .opacity(pageOpacity(tab, isActive: isActive))
                        .allowsHitTesting(isActive)
                        .accessibilityHidden(!isActive)
                        .zIndex(isActive ? 2 : (tab == leavingTab ? 1 : 0))
                }
            }
        }
        // Tło strony POD zakładkami: wchodząca zakładka wyłania się z tego
        // samego tła, które ma sama, a nie z gołego okna.
        .background(SCPageBackground(scheme: colorScheme).ignoresSafeArea())
        .tint(SCPalette.terracotta)
        .overlay(alignment: .bottom) {
            SCFloatingTabBar(items: items, selection: tabSelection, isCompact: chrome.isCompact)
                // Klawiatura ma pasek ZASŁONIĆ, jak systemowy — bez tego
                // `overlay` uciekałby nad klawiaturę i stawał między nią
                // a polem asystenta.
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .environment(\.scTabBarChrome, chrome)
        // Nowa zakładka zaczyna z pełnym paskiem: stan zwinięcia należy
        // do przewijania, które użytkownik właśnie opuścił.
        .onChange(of: session.dashboardTab, initial: true) { _, tab in
            chrome.isCompact = false
            mounted.insert(tab)
        }
        .task { await warmUpRemainingTabs() }
        // Liczy się RAMKA klawiatury, nie samo „pokazała się": przy klawiaturze
        // sprzętowej (Mac w symulatorze, iPad z etui) system też wysyła
        // `keyboardWillShow`, ale na ekran nie wjeżdża nic albo sam wąski
        // pasek. Rezerwa pod menu schodziła wtedy do zera i pole asystenta
        // lądowało POD paskiem zakładek, którego nic nie zasłaniało.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            chrome.keyboardDuration = Self.animationDuration(of: note)
            chrome.isKeyboardVisible = Self.keyboardCoversTabBar(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
            chrome.keyboardDuration = Self.animationDuration(of: note)
            chrome.isKeyboardVisible = false
        }
    }

    /// Wybór z paska = PRZENIKANIE treści: stara zakładka stoi pod spodem
    /// w pełnym kryciu, a nowa nabiera krycia NAD nią (0,2 s). Tło, pasek
    /// i wszystko, co obie strony mają wspólne, nie drgnie — zmienia się
    /// tylko to, co się różni. Runda 18 wyłaniała nową zakładkę z gołego tła
    /// przy zgaszonej starej i przez pół przejścia cały ekran przygasał
    /// („wygląda, jakby cały widok się zmieniał”). Krycie startowe idzie
    /// w tej samej transakcji co wybór, więc nie ma klatki z nową w pełni.
    /// Asystent ma własne powitanie — wchodzi od razu.
    private var tabSelection: Binding<DashboardTab> {
        Binding(
            get: { sessionStore.dashboardTab },
            set: { tab in
                let previous = sessionStore.dashboardTab
                guard tab != previous else { return }
                let fades = tab != .assistant && !reduceMotion
                enteringTab = fades ? tab : nil
                leavingTab = fades ? previous : nil
                entranceOpacity = fades ? 0 : 1
                sessionStore.dashboardTab = tab
                guard fades else { return }
                DispatchQueue.main.async {
                    guard enteringTab == tab else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        entranceOpacity = 1
                    } completion: {
                        if enteringTab == tab { leavingTab = nil }
                    }
                }
            }
        )
    }

    /// Czas ruchu klawiatury z powiadomienia.
    private static func animationDuration(of note: Notification) -> Double {
        (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
    }

    /// Czy klawiatura po zmianie ramki zasłoni dolne menu.
    private static func keyboardCoversTabBar(_ note: Notification) -> Bool {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return false }
        let screenHeight = UIScreen.main.bounds.height
        let overlap = max(0, screenHeight - frame.minY)
        // Pasek skrótów klawiatury sprzętowej ma ~55–70 pt; prawdziwa
        // klawiatura ponad 250.
        return overlap > 120
    }

    /// Buduje pozostałe zakładki po jednej, z oddechem między nimi: pięć
    /// ekranów w jednej klatce przycięłoby animację loadera, pod którym to
    /// się dzieje. Każda zbudowana zakładka od razu ciągnie swoje dane.
    private func warmUpRemainingTabs() async {
        for tab in Self.order where !mounted.contains(tab) {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            mounted.insert(tab)
        }
    }

    @ViewBuilder
    private func page(_ tab: DashboardTab) -> some View {
        switch tab {
        case .recipes:
            RecipesView()
        case .plan:
            WeeklyPlanView()
        case .calendar:
            CalendarView()
        case .assistant:
            // Asystent zajął miejsce „Produktów": to do niego wraca się
            // wiele razy w tygodniu, a lista zakupów powstaje przy Planie
            // i tam też ma swoje wejście.
            if let agentStore = sessionStore.agentStore {
                AssistantView(store: agentStore)
            } else {
                AssistantUnavailableView()
                    .scReservesTabBarSpace()
            }
        case .settings:
            SettingsView()
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
}

#Preview {
    NavigationMenu()
}
