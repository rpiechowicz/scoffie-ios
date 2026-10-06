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
///   nad klawiaturą (powitanie Asystenta);
/// - `goalBarFaces` / `goalBarHandoff` — co pokazują pigułki kcal Planu
///   i Pulpitu; pigułka zakładki, na którą się wchodzi, rysuje PIERWSZĄ
///   klatkę z twarzą poprzedniej i od niej dojeżdża do swojej.
@Observable
final class SCTabBarChrome {
    /// Tytuł do kapsuły pod paskiem stanu (`SCCompactTitle`) dla zakładek,
    /// których duży tytuł zjechał już pod górną krawędź.
    var compactTitles: [DashboardTab: String] = [:]

    /// Ostatnia twarz pigułki kcal (`PlanDayGoalBar`) na danej zakładce —
    /// liczby i układ. Czytana tylko w akcjach, nigdy w `body` — zapis nie
    /// przebudowuje menu.
    var goalBarFaces: [DashboardTab: PlanDayGoalFace] = [:]

    /// Twarz, od której pigułka zakładki DOCELOWEJ rysuje się w chwili
    /// przełączenia (Plan ↔ Pulpit). Ustawiana ZANIM zmieni się zakładka
    /// (`NavigationMenu.prepareGoalBarHandoff`), więc pierwsza klatka nowej
    /// zakładki to dokładnie pigułka poprzedniej — jeden komponent, który
    /// tylko zmienia stan. Pigułka sama ją zdejmuje, ruchem.
    var goalBarHandoff: [DashboardTab: PlanDayGoalFace] = [:]

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
/// systemowy pasek (od 6.10.2026 bez zwijania przy przewijaniu, do bieżącej
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
    /// Licznik wejść na każdą zakładkę — ikona podskakuje przy KAŻDYM wyborze
    /// (`symbolEffect` z `value:` gra przy zmianie wartości), a nie przy
    /// odejściu z zakładki.
    @State private var bounces: [DashboardTab: Int] = [:]

    var body: some View {
        @Bindable var session = sessionStore
        let selected = session.dashboardTab
        let compactTitle = chrome.compactTitles[selected]

        // Wybór przez wiązanie z przygotowaniem przejścia pigułki kcal —
        // twarz musi stać w stanie, ZANIM zakładka się przełączy.
        let selection = Binding<DashboardTab>(
            get: { session.dashboardTab },
            set: { tab in
                prepareGoalBarHandoff(from: session.dashboardTab, to: tab)
                session.dashboardTab = tab
            }
        )

        return TabView(selection: selection) {
            Tab(value: DashboardTab.recipes) {
                page(.recipes, isActive: selected == .recipes)
            } label: {
                tabLabel(.recipes, MenuConstans.Recipes.name, systemImage: MenuConstans.Recipes.icon)
            }
            Tab(value: DashboardTab.plan) {
                page(.plan, isActive: selected == .plan)
            } label: {
                tabLabel(.plan, MenuConstans.Plan.name, systemImage: MenuConstans.Plan.icon)
            }
            // Znak Scoffie zamiast symbolu systemu — własny obrazek nie ma
            // efektów symboli, więc ta jedna ikona nie podskakuje.
            Tab(value: DashboardTab.calendar) {
                page(.calendar, isActive: selected == .calendar)
            } label: {
                Label(MenuConstans.Calendar.name, image: MenuConstans.Calendar.image)
            }
            // Odpowiedź potrafi dojść, gdy użytkownik ogląda plan — bez tej
            // plakietki musiałby sam wracać i sprawdzać, czy już jest.
            Tab(value: DashboardTab.assistant) {
                page(.assistant, isActive: selected == .assistant)
            } label: {
                tabLabel(.assistant, MenuConstans.Assistant.name, systemImage: MenuConstans.Assistant.icon)
            }
            .badge(sessionStore.agentStore?.unseenAnswers ?? 0)
            Tab(value: DashboardTab.settings) {
                page(.settings, isActive: selected == .settings)
            } label: {
                tabLabel(.settings, MenuConstans.Settings.name, systemImage: MenuConstans.Settings.icon)
            }
        }
        .onChange(of: selected) { old, tab in
            bounces[tab, default: 0] += 1
            // Przełączenie z kodu („Zaplanuj” na Pulpicie → Plan) omija
            // wiązanie — tu przejście dochodzi chwilę później.
            prepareGoalBarHandoff(from: old, to: tab)
        }
        // Pasek NIE zwija się przy przewijaniu (Rafał 6.10.2026). Zwinięty
        // rozjeżdżał się ze wstawkami nad nim (pasek szukania Przepisów,
        // pigułka Planu, pole Asystenta), a iOS nie mówi aplikacji, kiedy
        // pasek się zwinął albo rozwinął (np. stuknięciem w zwiniętą ikonę) —
        // przyklejany do niego pasek szukania nachodził potem na zakładki.
        .tabBarMinimizeBehavior(.never)
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

    /// Pigułka kcal zakładki `to` zacznie od twarzy pigułki `from` — tylko
    /// między Planem a Pulpitem i tylko raz na przejście.
    private func prepareGoalBarHandoff(from: DashboardTab, to: DashboardTab) {
        let tabs: Set<DashboardTab> = [.plan, .calendar]
        guard from != to, tabs.contains(from), tabs.contains(to),
              chrome.goalBarHandoff[to] == nil,
              let face = chrome.goalBarFaces[from]
        else { return }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { chrome.goalBarHandoff[to] = face }
    }

    /// Podpis zakładki z ikoną, która podskakuje przy wyborze (6.10.2026,
    /// Rafał: „mała animacja na ikony w nav, jak zmieniam strony”). Systemowy
    /// pasek może efektu nie pokazać — wtedy zostaje sama soczewka szkła.
    private func tabLabel(_ tab: DashboardTab, _ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .symbolEffect(.bounce.down, options: .nonRepeating, value: bounces[tab, default: 0])
        }
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
