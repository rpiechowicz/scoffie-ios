//
//  ScoffieApp.swift
//  Scoffie
//
//  Created by Rafi on 03/02/2026.
//

import Foundation
import SwiftUI
import UserNotifications

enum AppEnvironment {
    /// Adres backendu. Kolejność priorytetów:
    /// 1. Zmienna środowiskowa API_BASE_URL (przydatna przy lokalnym debugowaniu)
    /// 2. Info.plist → klucz API_BASE_URL (domyślnie produkcja)
    /// 3. Bezpieczny fallback: produkcja
    static let apiBaseURL: URL = {
        if let envRaw = ProcessInfo.processInfo.environment["API_BASE_URL"],
           let url = URL(string: envRaw) {
            return url
        }
        if let plistRaw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !plistRaw.isEmpty,
           let url = URL(string: plistRaw) {
            return url
        }
        return URL(string: "https://api.scoffie.app")!
    }()
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var sessionStore: SessionStore?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        #if DEBUG
        // Ekran porównania z makietą: bez pytania o powiadomienia i bez
        // toastu o sieci, które zasłaniałyby zrzut.
        if AssistantOptionsDebugScreen.requested != nil { return true }
        #endif
        // Nasłuch interfejsu startuje razem z aplikacją, żeby pierwsze
        // żądanie miało już z czym porównać swoje niepowodzenie.
        ConnectivityMonitor.shared.start()
        PlanChangeNotificationService.requestAuthorizationIfNeeded()
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        sessionStore?.updatePushDeviceToken(token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Ignore in simulator/dev without APNs entitlement.
    }

    /// Powiadomienie przyszło, gdy aplikacja jest NA WIERZCHU.
    ///
    /// Podsumowanie planu dostaje banner i dźwięk — dokładnie to, o co prosi
    /// backend (`interruption-level: active`, `sound: default`). Wcześniej
    /// klient zbijał je tu do `.list`, czyli cichego wpisu w Centrum
    /// powiadomień, i przy otwartej aplikacji domownik nie widział niczego.
    /// `.list` zostaje tam, gdzie użytkownik i tak patrzy na tę samą treść.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let type = Self.payloadType(of: notification)
        Self.cancelLocalFallbackIfRemote(notification, type: type)

        switch type {
        case .householdMembers:
            completionHandler([.banner, .sound])
        case .householdInvitation:
            // Zaproszenie przychodzi w chwili, gdy użytkownik właśnie otworzył
            // link i patrzy na alert z tą samą treścią. Banner byłby drugą
            // kopią tego, co widzi; powiadomienie ma tu jedno zadanie —
            // zostać w Centrum powiadomień na później.
            completionHandler([.list])
        case .weeklyPlan:
            completionHandler([.banner, .sound])
        case .shoppingList:
            completionHandler([.list])
        case .assistantTurn:
            // Przy aplikacji na wierzchu mówi o tym KAPSUŁA, nie systemowy
            // baner: `AgentStore` wystawia toast z własnego odpytywania, więc
            // sygnał dociera niezależnie od zgody na powiadomienia, a baner
            // i kapsuła biją się o ten sam pas ekranu. Push zostaje przy swojej
            // prawdziwej robocie — dosięgnąć człowieka przy zamkniętej apce.
            completionHandler([.list])
        case .mealReminder:
            // Baner bez dźwięku. Przypomnienie o gotowaniu jest wezwaniem
            // i przy zamkniętej apce ma zadzwonić, ale człowiek z telefonem
            // w ręku nie potrzebuje, żeby mu w tej ręce zawibrował — a łuk
            // w Kalendarzu mówi mu to samo bez bannera.
            completionHandler([.banner])
        case .unknown:
            completionHandler([.banner])
        }
    }

    /// Kasuje czekające powiadomienie lokalne, gdy tę samą sprawę dowiozło
    /// już push. Tylko dla pushy — zaplanowane lokalne nie ma kasować samo
    /// siebie w chwili wyświetlenia.
    private static func cancelLocalFallbackIfRemote(
        _ notification: UNNotification,
        type: PushPayloadType
    ) {
        guard notification.request.trigger is UNPushNotificationTrigger else { return }
        cancelLocalFallback(for: type)
    }

    private static func cancelLocalFallback(for type: PushPayloadType) {
        switch type {
        case .weeklyPlan:
            PlanChangeNotificationService.cancelPendingFallback(
                prefix: NotificationIdentifierPrefix.plan
            )
        case .shoppingList:
            PlanChangeNotificationService.cancelPendingFallback(
                prefix: NotificationIdentifierPrefix.shopping
            )
        case .householdMembers, .householdInvitation, .assistantTurn, .mealReminder, .unknown:
            break
        }
    }

    /// Użytkownik stuknął w powiadomienie.
    ///
    /// Zdarzenia realtime bywają zgubione (socket rozłączony w tle), więc
    /// stuknięcie traktujemy jako moment na dociągnięcie prawdy — inaczej
    /// aplikacja otwierałaby się na tym samym nieaktualnym ekranie, o którym
    /// powiadomienie właśnie mówiło, że jest nieaktualny.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Paczka została dostarczona — kolejne zmiany zaczynają liczyć od zera.
        PlanChangeNotificationService.resetPendingCount(
            for: response.notification.request.identifier
        )
        let type = Self.payloadType(of: response.notification)
        Self.cancelLocalFallbackIfRemote(response.notification, type: type)
        handle(payloadType: type, tapped: true)
        completionHandler()
    }

    /// Cichy push (albo push dostarczony, gdy aplikacja ma chwilę na pracę).
    ///
    /// `completionHandler` dochodzi PO pracy, nie przed nią — i to nie jest
    /// kosmetyka. Dotąd wracał natychmiast, a robota szła w odpalonych obok
    /// `Task`-ach: dla systemu znaczyło to „skończyłem", więc miał prawo uśpić
    /// proces w dowolnym momencie tego, co jeszcze trwało. Gdy akurat trwała
    /// rotacja refresh tokenu, telefon zostawał ze zrotowanym tokenem i przy
    /// następnym uruchomieniu — choćby za cztery dni — wyglądał dla serwera
    /// na kradzież. Objawem było „Sesja wygasła" po dłuższej przerwie
    /// od aplikacji, bez żadnej winy użytkownika.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let type = Self.payloadType(ofUserInfo: userInfo)
        Self.cancelLocalFallback(for: type)
        Task { @MainActor in
            let activity = BackgroundActivity.begin(name: "silent-push")
            await self.perform(payloadType: type)
            activity.end()
            completionHandler(.newData)
        }
    }

    /// Stuknięcie w powiadomienie: aplikacja i tak wchodzi na pierwszy plan,
    /// więc nie ma czego podtrzymywać — praca leci obok.
    private func handle(payloadType: PushPayloadType, tapped: Bool = false) {
        Task { @MainActor in
            await perform(payloadType: payloadType, tapped: tapped)
        }
    }

    @MainActor
    private func perform(payloadType: PushPayloadType, tapped: Bool = false) async {
        guard let sessionStore else { return }
        switch payloadType {
        case .assistantTurn:
            // „Asystent odpowiedział" ma otwierać rozmowę — ale tylko po
            // stuknięciu; cichy push nie przełącza zakładek nikomu pod ręką.
            if tapped {
                sessionStore.dashboardTab = .assistant
            }
        case .householdMembers:
            await sessionStore.refreshHouseholdMembers(force: true)
        case .householdInvitation:
            await sessionStore.refreshPendingInvitations()
        case .weeklyPlan, .shoppingList:
            sessionStore.refreshRealtimeStoresOnForeground()
        case .mealReminder:
            // „Pora gotować" prowadzi do Kalendarza — tam stoi łuk doby
            // z tym samym posiłkiem, jego godziną i przyciskiem odhaczenia.
            // Tylko po stuknięciu: powiadomienie, które samo przestawia
            // zakładkę komuś pod ręką, byłoby napadem, nie przypomnieniem.
            if tapped {
                sessionStore.dashboardTab = .calendar
            }
        case .unknown:
            break
        }
    }

    /// Rodzaj powiadomienia. Backend wkłada go do `data.type`
    /// (`notifications.service.ts`), a powiadomienia lokalne rozpoznajemy po
    /// prefiksie identyfikatora — ten sam podział, dwa źródła.
    enum PushPayloadType {
        case weeklyPlan
        case shoppingList
        case householdMembers
        case householdInvitation
        /// Odpowiedź asystenta gotowa (`ASSISTANT_TURN_FINISHED`).
        case assistantTurn
        /// Własny dzień: pora gotować, pora jeść, wieczorne podsumowanie
        /// (`MealReminderService`). Wyłącznie lokalne — backend takich
        /// powiadomień nie wysyła, bo to telefon zna rozkład godzin
        /// gospodarstwa i swoją strefę czasową.
        case mealReminder
        case unknown
    }

    private static func payloadType(of notification: UNNotification) -> PushPayloadType {
        let fromPayload = payloadType(ofUserInfo: notification.request.content.userInfo)
        guard case .unknown = fromPayload else { return fromPayload }

        let identifier = notification.request.identifier
        if identifier.hasPrefix(NotificationIdentifierPrefix.plan) { return .weeklyPlan }
        if identifier.hasPrefix(NotificationIdentifierPrefix.shopping) { return .shoppingList }
        if identifier.hasPrefix(NotificationIdentifierPrefix.invitation) { return .householdInvitation }
        // Przypomnienia mają trzy różne prefiksy, więc pyta o nie sam serwis.
        if MealReminderService.isOurs(identifier) { return .mealReminder }
        if identifier.hasPrefix(NotificationIdentifierPrefix.household) { return .householdMembers }
        return .unknown
    }

    private static func payloadType(ofUserInfo userInfo: [AnyHashable: Any]) -> PushPayloadType {
        let data = userInfo["data"] as? [AnyHashable: Any]
        switch data?["type"] as? String {
        case "WEEKLY_PLAN_CHANGED":       return .weeklyPlan
        case "SHOPPING_LIST_CHANGED":     return .shoppingList
        case "HOUSEHOLD_MEMBERS_CHANGED": return .householdMembers
        case "HOUSEHOLD_INVITATION":      return .householdInvitation
        case "ASSISTANT_TURN_FINISHED":   return .assistantTurn
        default:                          return .unknown
        }
    }
}

@main
struct ScoffieApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var sessionStore = SessionStore()
    /// Kolejka wewnętrznych powiadomień. Jedna na aplikację — kapsuła udaje
    /// Dynamic Island, a wyspa jest jedna.
    @State private var toastCenter = SCToastCenter()
    @AppStorage("settings.theme") private var themeRawValue: String = AppTheme.system.rawValue

    private var appTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .system }
    @Environment(\.scenePhase) private var scenePhase

    /// Klucz dla `.task(id:)` uruchamiającego smart startup loader.
    /// Zmiana klucza (logowanie, restore, switch householdu) re-odpala warmup;
    /// dla tego samego kontekstu Swift nie powtarza taska.
    private var startupTaskID: String {
        let auth = sessionStore.isAuthenticated ? "1" : "0"
        let household = sessionStore.currentHouseholdId ?? ""
        return "\(auth)|\(household)"
    }

    /// Stabilny identyfikator aktualnie widocznego ekranu. Sterowany przez niego
    /// jest crossfade między Auth / Welcome / Loader / Dashboard.
    private enum RootScreen: Equatable {
        case auth
        case welcome
        case loader
        case dashboard
    }

    private var currentRootScreen: RootScreen {
        if !sessionStore.isAuthenticated {
            return .auth
        }
        if sessionStore.isRestoringSession, sessionStore.currentHouseholdId == nil {
            return .loader
        }
        // No household → welcome flow. New users start at step 1 (full
        // onboarding); users who already finished onboarding but have no
        // household land on step 5 (household creation only). Routing
        // logic in `rootScreen(_:)` decides the initial step.
        if sessionStore.currentHouseholdId?.isEmpty ?? true {
            return .welcome
        }
        // Pulpit wchodzi do drzewa, gdy tylko ma swoje store — JESZCZE pod
        // loaderem (patrz gałąź `.dashboard`). Osobny ekran loadera zostaje
        // na chwilę, w której nie ma czego budować.
        return hasDashboardStores ? .dashboard : .loader
    }

    private var hasDashboardStores: Bool {
        sessionStore.mealCalendarStore != nil
            && sessionStore.recipeCatalogStore != nil
            && sessionStore.shoppingListStore != nil
    }

    private var isStartupReady: Bool { sessionStore.startupPhase == .ready }

    /// Loader startu: osobny ekran, zanim są store pulpitu, a potem plansza
    /// nad budującym się pod nią pulpitem, dopóki start nie jest gotowy.
    private var showsStartupLoader: Bool {
        switch currentRootScreen {
        case .loader: return true
        case .dashboard: return !isStartupReady
        case .auth, .welcome: return false
        }
    }

    @ViewBuilder
    private func rootScreen(_ screen: RootScreen) -> some View {
        switch screen {
        case .auth:
            AuthView(
                isLoading: sessionStore.isSigningIn,
                errorMessage: sessionStore.authError,
                onSignInWithAppleTap: {
                    Task {
                        await sessionStore.signInWithApple()
                    }
                }
            )
        case .welcome:
            WelcomeFlowView(
                initialDisplayName: UserDefaults.standard.string(forKey: "settings.user.displayName") ?? "",
                isCreatingHousehold: sessionStore.isSigningIn,
                errorMessage: sessionStore.authError,
                // Already onboarded but missing a household (left it,
                // backend lost membership, etc.) → jump straight to the
                // household-creation step instead of re-asking for
                // profile/preferences they already filled in.
                initialStep: sessionStore.onboardingCompletedAt != nil
                    ? WelcomeView.householdOnlyStep
                    : 1
            )
        case .loader:
            // Sam loader stoi nad korzeniem (`showsStartupLoader`) — tu tylko
            // tło, żeby przejście korzenia nie miało czego pokazać.
            StartupCanvas()
        case .dashboard:
            if let mealStore = sessionStore.mealCalendarStore,
               let recipeCatalogStore = sessionStore.recipeCatalogStore,
               let shoppingListStore = sessionStore.shoppingListStore {
                // Pulpit buduje się POD loaderem: zakładki, ich dane i zdjęcia
                // są gotowe, zanim ktokolwiek je zobaczy. Wejście do aplikacji
                // to potem samo zgaśnięcie loadera nad stojącym ekranem —
                // wcześniej w tych samych klatkach budował się cały pulpit,
                // skalował korzeń i wyłaniała pierwsza zakładka, i to było
                // widać jako zgubione klatki.
                //
                // Loader NIE mieszka w tej gałęzi (patrz `showsStartupLoader`):
                // gałąź wjeżdża przejściem korzenia z `.opacity`, a krycie
                // kontenera bez `compositingGroup` schodzi na każde dziecko
                // osobno — przez pół sekundy przejścia „loader → pulpit”
                // przez półprzezroczysty loader prześwitywała zakładka pod nim.
                dashboard(
                    mealStore: mealStore,
                    recipeCatalogStore: recipeCatalogStore,
                    shoppingListStore: shoppingListStore
                )
                .allowsHitTesting(isStartupReady)
                .accessibilityHidden(!isStartupReady)
            } else {
                // Stores nie powinny być nil w tej gałęzi — loader i tak
                // stoi nad korzeniem, więc wystarczy tło.
                StartupCanvas()
            }
        }
    }

    private func dashboard(
        mealStore: MealCalendarStore,
        recipeCatalogStore: RecipeCatalogStore,
        shoppingListStore: ShoppingListStore
    ) -> some View {
        DashboardView()
            // Inne gospodarstwo = inny pulpit: stan ekranów (wybrany
            // dzień, filtry, przewinięcie) nie przechodzi między domami.
            .id(sessionStore.currentHouseholdId ?? "")
            .environment(\.mealCalendarStore, mealStore)
            .environment(\.datesViewModel, sessionStore.datesViewModel)
            .environment(\.recipeCatalogStore, recipeCatalogStore)
            .environment(\.shoppingListStore, shoppingListStore)
            // Błędy trzech głównych store zamieniają się w toast tutaj,
            // a nie na ekranach, które je wywołały. Wcześniej każdy
            // z nich rysował własny czerwony wiersz — widoczny tylko
            // na swojej zakładce i rozpychający układ w chwili, gdy
            // treść pod spodem i tak się przestawiała.
            .scErrorToast(mealStore.errorMessage)
            .scErrorToast(recipeCatalogStore.errorMessage)
            .scErrorToast(shoppingListStore.errorMessage)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                rootScreen(currentRootScreen)
                    .id(currentRootScreen)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 1.015)),
                            removal: .opacity.combined(with: .scale(scale: 0.985))
                        )
                    )

                // JEDEN loader na cały start, nad korzeniem i poza jego
                // tożsamością: przejście „loader → pulpit pod loaderem” dzieje
                // się pod nieprzezroczystą planszą, więc nie ma czego pokazać,
                // a fala kafelków nie zaczyna się od nowa w połowie.
                if showsStartupLoader {
                    StartupLoaderView()
                        .zIndex(1)
                        .transition(.opacity)
                }
                #if DEBUG
                // Porównanie karty wyboru z makietą — patrz `AssistantOptionsDebugScreen`.
                if let debugScreen = AssistantOptionsDebugScreen.requested { debugScreen }
                #endif
            }
            .animation(.easeInOut(duration: 0.45), value: currentRootScreen)
            .animation(.easeOut(duration: 0.4), value: showsStartupLoader)
            .environment(\.sessionStore, sessionStore)
            // Kolejność ma znaczenie: każdy z mostów poniżej musi stać POD
            // `scToastLayer` w drzewie, bo to ona wstawia `\.toasts`
            // do środowiska.
            //
            // Zdarzenia BEZ EKRANU: tura asystenta, która skończyła się, gdy
            // użytkownik patrzył na plan, i zakup dogadany z Apple w tle.
            //
            // Wiszą TUTAJ, a nie w gałęzi pulpitu, i to jest istotne: gałąź
            // pulpitu ma `.id(currentRootScreen)`, więc przy każdym przejściu
            // korzenia (loader, powitanie, zmiana gospodarstwa) budowałaby się
            // od nowa i brała bieżącą wartość za punkt odniesienia. A zakup
            // odtworzony przez StoreKit dociera właśnie w oknie loadera.
            .scBackgroundToast(
                sessionStore.agentStore?.backgroundNotice,
                onShown: { sessionStore.agentStore?.clearBackgroundNotice() }
            )
            .scBackgroundToast(
                sessionStore.subscriptionStore?.backgroundNotice,
                onShown: { sessionStore.subscriptionStore?.clearBackgroundNotice() }
            )
            .scConnectivityToast()
            // Motyw podany JAWNIE: warstwa toastów mieszka w osobnym oknie,
            // do którego `preferredColorScheme` nie dociera.
            .scToastLayer(toastCenter, colorScheme: appTheme.colorScheme)
            .preferredColorScheme(appTheme.colorScheme)
            .task(id: startupTaskID) {
                await sessionStore.runStartupIfNeeded()
            }
            .onAppear {
                appDelegate.sessionStore = sessionStore
            }
            .onChange(of: scenePhase) { _, newValue in
                if newValue == .active {
                    sessionStore.refreshRealtimeStoresOnForeground()
                } else if newValue == .background {
                    // Chwila, w której powiadomienia lokalne zaczynają być
                    // jedynym kanałem: aplikacja właśnie przestała być na
                    // wierzchu, a plan jest świeży po całej sesji. Rozkład
                    // układa się od zera, więc powtórzenie nic nie kosztuje.
                    sessionStore.rescheduleMealReminders()
                    // Ostatnia szansa na wysyłkę kroków — w tle obserwator HK
                    // nie działa i dławienie PUT mogło zjeść ostatnią zmianę.
                    // Asercja background taska, bo iOS potrafi zawiesić proces
                    // szybciej, niż domknie się request; bez niej ten hook
                    // istniałby głównie na papierze.
                    if let healthStepsStore = sessionStore.healthStepsStore {
                        var backgroundTask: UIBackgroundTaskIdentifier = .invalid
                        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "health-steps-sync") {
                            UIApplication.shared.endBackgroundTask(backgroundTask)
                            backgroundTask = .invalid
                        }
                        Task { @MainActor in
                            await healthStepsStore.syncNow()
                            if backgroundTask != .invalid {
                                UIApplication.shared.endBackgroundTask(backgroundTask)
                                backgroundTask = .invalid
                            }
                        }
                    }
                }
            }
            .onOpenURL { url in
                sessionStore.handleIncomingURL(url)
            }
            // Tytuł i etykieta przycisku biorą się z samego zaproszenia, bo
            // „Dołącz" i „Przenieś się" to dwie różne decyzje: druga oznacza
            // utratę dostępu do dotychczasowego planu i listy zakupów, a bywa
            // że także skasowanie opuszczanego gospodarstwa. Rola
            // `.destructive` jest tam nie dla ozdoby — to jedyny moment, w
            // którym da się z tego wycofać.
            .alert(
                sessionStore.invitationPrompt?.title ?? "Dołączyć do gospodarstwa?",
                isPresented: Binding(
                    get: { sessionStore.invitationPrompt != nil },
                    set: { isPresented in
                        if !isPresented {
                            sessionStore.dismissInvitationPrompt()
                        }
                    }
                ),
                presenting: sessionStore.invitationPrompt
            ) { prompt in
                Button("Nie teraz", role: .cancel) {
                    sessionStore.dismissInvitationPrompt()
                }
                Button(prompt.confirmLabel, role: prompt.requiresLeave ? .destructive : nil) {
                    Task {
                        await sessionStore.acceptPendingInvitation(
                            token: prompt.token,
                            leaveOtherHouseholds: prompt.requiresLeave
                        )
                    }
                }
            } message: { prompt in
                Text(prompt.message)
            }
        }
    }
}

/// Tło loadera bez samego loadera — pod planszą startu, która stoi nad
/// korzeniem (`ScoffieApp.showsStartupLoader`).
private struct StartupCanvas: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Color.scCanvas(scheme)
            .ignoresSafeArea()
    }
}
