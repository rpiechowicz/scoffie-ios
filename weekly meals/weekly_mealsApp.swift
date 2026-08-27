//
//  weekly_mealsApp.swift
//  weekly meals
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
        return URL(string: "https://weakly-meals-backend-production.up.railway.app")!
    }()
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var sessionStore: SessionStore?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
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
        case .householdMembers, .householdInvitation, .unknown:
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
        handle(payloadType: type)
        completionHandler()
    }

    /// Cichy push (albo push dostarczony, gdy aplikacja ma chwilę na pracę).
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let type = Self.payloadType(ofUserInfo: userInfo)
        Self.cancelLocalFallback(for: type)
        handle(payloadType: type)
        completionHandler(.newData)
    }

    private func handle(payloadType: PushPayloadType) {
        guard let sessionStore else { return }
        switch payloadType {
        case .householdMembers:
            Task { @MainActor in
                await sessionStore.refreshHouseholdMembers(force: true)
            }
        case .householdInvitation:
            Task { @MainActor in
                await sessionStore.refreshPendingInvitations()
            }
        case .weeklyPlan, .shoppingList:
            Task { @MainActor in
                sessionStore.refreshRealtimeStoresOnForeground()
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
        case unknown
    }

    private static func payloadType(of notification: UNNotification) -> PushPayloadType {
        let fromPayload = payloadType(ofUserInfo: notification.request.content.userInfo)
        guard case .unknown = fromPayload else { return fromPayload }

        let identifier = notification.request.identifier
        if identifier.hasPrefix(NotificationIdentifierPrefix.plan) { return .weeklyPlan }
        if identifier.hasPrefix(NotificationIdentifierPrefix.shopping) { return .shoppingList }
        if identifier.hasPrefix(NotificationIdentifierPrefix.invitation) { return .householdInvitation }
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
        default:                          return .unknown
        }
    }
}

@main
struct weekly_mealsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var sessionStore = SessionStore()
    @AppStorage("settings.theme") private var themeRawValue: String = AppTheme.system.rawValue
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
        // household land on step 4 (household creation only). Routing
        // logic in `rootScreen(_:)` decides the initial step.
        if sessionStore.currentHouseholdId?.isEmpty ?? true {
            return .welcome
        }
        return sessionStore.startupPhase == .ready ? .dashboard : .loader
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
            WelcomeView(
                initialDisplayName: UserDefaults.standard.string(forKey: "settings.user.displayName") ?? "",
                isCreatingHousehold: sessionStore.isSigningIn,
                errorMessage: sessionStore.authError,
                // Already onboarded but missing a household (left it,
                // backend lost membership, etc.) → jump straight to the
                // household-creation step instead of re-asking for
                // profile/preferences they already filled in.
                initialStep: sessionStore.onboardingCompletedAt != nil ? 4 : 1
            )
        case .loader:
            StartupLoaderView()
        case .dashboard:
            if let mealStore = sessionStore.weeklyMealStore,
               let recipeCatalogStore = sessionStore.recipeCatalogStore,
               let shoppingListStore = sessionStore.shoppingListStore {
                DashboardView()
                    .environment(\.weeklyMealStore, mealStore)
                    .environment(\.datesViewModel, sessionStore.datesViewModel)
                    .environment(\.recipeCatalogStore, recipeCatalogStore)
                    .environment(\.shoppingListStore, shoppingListStore)
            } else {
                // Stores nie powinny być nil gdy startupPhase == .ready,
                // ale na wszelki wypadek pokażemy loader niż pusty ekran.
                StartupLoaderView()
            }
        }
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
            }
            .animation(.easeInOut(duration: 0.45), value: currentRootScreen)
            .environment(\.sessionStore, sessionStore)
            .preferredColorScheme((AppTheme(rawValue: themeRawValue) ?? .system).colorScheme)
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
