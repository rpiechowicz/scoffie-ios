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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
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
                }
            }
            .onOpenURL { url in
                sessionStore.handleIncomingURL(url)
            }
            .alert(
                "Dołączyć do gospodarstwa?",
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
                Button("Dołącz") {
                    Task {
                        await sessionStore.acceptPendingInvitation(token: prompt.token)
                    }
                }
            } message: { prompt in
                Text(prompt.message)
            }
        }
    }
}
