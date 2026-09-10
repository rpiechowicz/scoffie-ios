import AuthenticationServices
import Foundation
import Observation
import SwiftUI

/// Owns the user's auth session, household context, smart-startup loader,
/// and per-user preferences. Companion types live alongside this file:
///   - `SessionDTOs.swift`         — backend-shaped Codable DTOs
///   - `SessionPublicTypes.swift`  — InvitationPromptState / StartupPhase / HouseholdMemberSnapshot
///   - `Models/Environment/StoreEnvironmentKeys.swift` — SwiftUI Environment defaults

@MainActor
@Observable
final class SessionStore {
    private struct PersistedSessionSnapshot {
        let userId: String
        let householdId: String?
        let householdName: String?
    }

    private enum Keys {
        static let accessToken = "auth.accessToken"
        static let refreshToken = "auth.refreshToken"
        static let userId = "auth.userId"
        static let appleUserIdentifier = "auth.appleUserIdentifier"
        static let householdId = "auth.householdId"
        static let displayName = "settings.user.displayName"
        static let email = "settings.user.email"
        static let avatarUrl = "settings.user.avatarUrl"
        static let avatarColor = "settings.user.avatarColor"
        static let householdName = "settings.household.name"
        static let pushDeviceToken = "notifications.pushDeviceToken"
        // Welcome / onboarding state — persisted alongside the session so
        // we can decide whether to show the welcome flow on cold start.
        static let onboardingCompletedAt = "settings.user.onboardingCompletedAt"
    }

    private let baseURL = AppEnvironment.apiBaseURL

    /// Aktualny access token z Keychain. Używać do autoryzacji HTTP requestów.
    var currentAccessToken: String? {
        KeychainService.get(forKey: Keys.accessToken)
    }

    /// Aktualny refresh token z Keychain. Używać do odświeżania sesji.
    var currentRefreshToken: String? {
        KeychainService.get(forKey: Keys.refreshToken)
    }

    var isSigningIn = false
    var authError: String?
    var isAuthenticated = false
    var currentUserId: String?
    var currentHouseholdId: String?
    var currentHouseholdName: String?
    var invitationPrompt: InvitationPromptState?

    /// Zaproszenia czekające na tego użytkownika.
    ///
    /// Zaproszenie żyło dotąd wyłącznie jako link w komunikatorze: kto otworzył
    /// go w złym momencie — bo należał już do innego gospodarstwa albo po
    /// prostu zamknął alert — nie miał jak do niego wrócić. Skrzynka jest tym
    /// miejscem, do którego można wrócić.
    private(set) var pendingInvitations: [HouseholdInvitationSnapshot] = []
    var householdRealtimeVersion: Int = 0

    /// Posiłki, które planuje bieżące gospodarstwo (Ustawienia → „Posiłki
    /// w planie"). Wspólne dla całego domu — zmiana u jednej osoby przychodzi
    /// do pozostałych zdarzeniem `households:mealTypesChanged`.
    ///
    /// Hydratowane z `@AppStorage` na zimnym starcie, żeby pierwsza klatka
    /// Planu nie migała trójką podstawową, zanim wróci odpowiedź z serwera.
    var mealSlots: MealSlotConfiguration = MealSlotConfiguration(
        storageValue: UserDefaults.standard
            .string(forKey: MealSlotConfiguration.Keys.enabledSlots) ?? ""
    )
    /// Godziny posiłków. Wspólne dla gospodarstwa, dokładnie jak `mealSlots`
    /// — zmiana u jednej osoby przychodzi do pozostałych zdarzeniem
    /// `households:mealTimesChanged`. `UserDefaults` jest lustrem na zimny
    /// start i na offline, nie źródłem prawdy.
    var mealSlotSchedule: MealSlotSchedule = MealSlotSchedule(
        storageValue: UserDefaults.standard
            .string(forKey: MealSlotSchedule.Keys.times) ?? ""
    )

    /// `nil` when the user hasn't completed the welcome flow yet — UI gates
    /// the welcome screen on this. We hydrate it from AppStorage on cold
    /// start (so we don't flash the welcome screen for users who completed
    /// it on a previous launch) and refresh it from the backend when
    /// `users:me` resolves.
    var onboardingCompletedAt: Date?

    /// Bieżąca faza smart startup loadera.
    /// - `.idle` → brak sesji / brak gospodarstwa (Auth / NoHousehold)
    /// - `.warmingUp` → przygotowujemy dane przed wejściem do dashboardu
    /// - `.ready` → dashboard może się pokazać
    var startupPhase: StartupPhase = .idle
    /// `true` gdy trwa restore sesji i musimy dociągnąć household z backendu
    /// (persisted userId bez persisted householdId). UI trzyma wtedy loader
    /// zamiast mignięcia NoHouseholdView.
    var isRestoringSession: Bool = false

    /// Członkowie aktualnego gospodarstwa. Prealoaduje się w startupie i z cache,
    /// żeby Settings / Household sheet otwierało się z gotowymi danymi.
    var householdMembers: [HouseholdMemberSnapshot] = []
    var isLoadingHouseholdMembers: Bool = false
    private(set) var didLoadHouseholdMembers: Bool = false
    /// Kiedy skład gospodarstwa przyszedł z SERWERA (nie z pliku cache).
    ///
    /// `didLoadHouseholdMembers` odpowiada na pytanie „czy mam co narysować",
    /// a to na pytanie „czy to jeszcze aktualne". Zlanie ich w jedno było
    /// powodem, dla którego nowy domownik pojawiał się dopiero po wylogowaniu:
    /// flaga zapalona z 24-godzinnego cache'u blokowała każde kolejne pobranie,
    /// więc jedyną drogą do świeżej listy było wyczyszczenie stanu przy
    /// wylogowaniu.
    private var householdMembersLoadedAt: Date?

    /// Czy serwer potwierdził, że umie wysyłać powiadomienia push.
    ///
    /// Rozstrzyga, czy aplikacja ma jeszcze rysować własne lokalne
    /// powiadomienia o zmianach drugiego domownika. Gdy push działa — nie ma:
    /// byłby to drugi banner o tej samej treści, tylko innym tytułem.
    private(set) var isPushDeliveryActive: Bool = false

    var mealCalendarStore: MealCalendarStore?
    var recipeCatalogStore: RecipeCatalogStore?
    var shoppingListStore: ShoppingListStore?
    /// Integracja Cookidoo (Thermomix) — jedyny store gadający z backendem
    /// po REST z tokenem, patrz `IntegrationsAPIClient`.
    var cookidooIntegrationStore: CookidooIntegrationStore?
    /// Kroki z HealthKit (Apple Zdrowie / Garmin) — drugi klient REST-owy,
    /// ta sama zasada tokenu co przy Cookidoo.
    var healthStepsStore: HealthStepsStore?
    /// Rozmowa z asystentem AI. Wisi na sesji, a nie na arkuszu, bo tura
    /// potrafi trwać minutę — użytkownik ma prawo w tym czasie zamknąć
    /// asystenta, obejrzeć plan i wrócić po odpowiedź.
    var agentStore: AgentStore?
    /// Zgody z serwera (`/me/consents`) — bramka asystenta i wiersz w Ustawieniach.
    var consentStore: ConsentStore?
    /// „Pobierz moje dane" (`GET /me/export`).
    var dataExportClient: DataExportAPIClient?
    /// Zakupy App Store. Żyje tak długo jak sesja, a nie tyle co ekran planu:
    /// `Transaction.updates` przynosi odnowienia i zatwierdzone „Poproś
    /// o zakup" w dowolnym momencie, a każda taka transakcja musi trafić na
    /// serwer. Zamknięty ekran nie może tego przegapić.
    var subscriptionStore: SubscriptionStore?
    var datesViewModel = DatesViewModel()
    /// Zakładka dolnego menu. Tu, a nie w `NavigationMenu`, bo przełącza ją
    /// też asystent — skrót „Otwórz" po zapisaniu planu.
    var dashboardTab: DashboardTab = .calendar
    /// Prośba asystenta o otwarcie listy zakupów.
    ///
    /// Lista jest arkuszem WEWNĄTRZ Planu, więc samo przełączenie zakładki
    /// zostawiłoby użytkownika o jedno dotknięcie od tego, co obiecał
    /// przycisk. Flagę zdejmuje ekran, który ją obsłużył — inaczej arkusz
    /// otwierałby się przy każdym powrocie na Plan.
    var opensShoppingList = false
    private var realtimeSocket: RecipeSocketClient?
    private var pendingPushDeviceToken: String?
    private let appleSignInCoordinator = AppleSignInCoordinator()
    private var startupTask: Task<Void, Never>?
    private var householdMembersTask: Task<Void, Never>?
    private let householdMembersCacheMaxAge: TimeInterval = 60 * 60 * 24 // 24 h
    /// Jak długo świeżo pobrany skład uchodzi za aktualny. Krótko, bo pobranie
    /// to jeden lekki event po już otwartym sockecie, a koszt nieaktualnej
    /// listy jest wysoki: to od niej zależy liczba porcji i podział posiłków.
    private let householdMembersFreshness: TimeInterval = 60
    private let startupTimeoutSeconds: Double = 6
    private let startupImagePrefetchCount: Int = 12
    /// Loader nie znika szybciej niż po tym czasie — nawet przy cieplutkim starcie
    /// (wszystko z cache). Wartość bierze się wprost z choreografii
    /// `StartupLoaderView` (`LoaderMotion.waveEnd`): moment, w którym niedziela
    /// (ostatni kafelek) ma pełne wypełnienie, dorysowany ptaszek i domknięty pop.
    /// Crossfade do dashboardu startuje dokładnie wtedy — żaden kafelek się nie
    /// urywa przed zapełnieniem, a użytkownik widzi „pełny tydzień".
    private let startupMinimumDisplaySeconds: Double = StartupLoaderView.waveCompletionSeconds

    init() {
        pendingPushDeviceToken = UserDefaults.standard.string(forKey: Keys.pushDeviceToken)
        onboardingCompletedAt = Self.readPersistedOnboardingDate()
        restoreSession()
    }

    private static let onboardingDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func parseOnboardingDate(_ iso8601: String?) -> Date? {
        guard let iso8601, !iso8601.isEmpty else { return nil }
        if let date = onboardingDateFormatter.date(from: iso8601) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        return fallback.date(from: iso8601)
    }

    private static func readPersistedOnboardingDate() -> Date? {
        let raw = UserDefaults.standard.string(forKey: Keys.onboardingCompletedAt)
        return parseOnboardingDate(raw)
    }

    private func persistOnboardingCompletedAt(_ raw: String?) {
        let defaults = UserDefaults.standard
        if let raw, !raw.isEmpty {
            defaults.set(raw, forKey: Keys.onboardingCompletedAt)
            onboardingCompletedAt = Self.parseOnboardingDate(raw)
        } else {
            defaults.removeObject(forKey: Keys.onboardingCompletedAt)
            onboardingCompletedAt = nil
        }
    }

    func refreshRealtimeStoresOnForeground() {
        // Proces obudzony, zanim Keychain był dostępny — sesja czeka na
        // pierwsze wejście na pierwszy plan.
        if !isAuthenticated, restoreDeferredUntilKeychainAvailable {
            restoreSession()
            return
        }
        // Powrót z tła zeruje licznik odmów: pętla refresh→odmowa dostaje
        // jedną świeżą próbę.
        socketAuthRetryTask?.cancel()
        socketAuthRetryTask = nil
        socketAuthRetryCount = 0
        // Najpierw obudź socket, dopiero potem odświeżaj. iOS zrywa
        // połączenie w tle, a odświeżenia strzelające w martwy socket
        // kończyły się chwilowym „Problem z połączeniem na żywo",
        // które reconnect gasił pół sekundy później.
        //
        // Wyjątek: token już wygasł — nie budzimy socketu starym tokenem;
        // najpierw refresh (po `.refreshed` `refreshSessionTokens` sam podnosi
        // socket). Chroni to socket po wcześniejszej odmowie; własny
        // auto-reconnect biblioteki może jeszcze wysłać stary token — ewentualna
        // druga rotacja jest ograniczona licznikiem odmów.
        let tokenAlreadyExpired = accessTokenExpiry().map { $0 <= Date() } ?? false
        if !tokenAlreadyExpired {
            realtimeSocket?.reconnectIfNeeded()
        }
        // Token mógł zbliżyć się do wygaśnięcia, gdy aplikacja spała.
        Task { @MainActor [weak self] in
            await self?.refreshSessionTokensIfExpiringSoon()
        }
        mealCalendarStore?.refreshObservedState()
        shoppingListStore?.refreshCurrentWeek()
        // Skład gospodarstwa też — zmiany, które zaszły, gdy aplikacja spała,
        // nie mają innej drogi do ekranu. Bez tego nowy domownik czekał na
        // wylogowanie i ponowne zalogowanie. To samo dotyczy skrzynki
        // zaproszeń: mogło przyjść, gdy aplikacja była w tle.
        Task { @MainActor [weak self] in
            await self?.refreshHouseholdMembers(force: true)
            await self?.refreshPendingInvitations()
        }
        if let recipeCatalogStore {
            Task {
                await recipeCatalogStore.reload()
            }
        }
        // Kroki mogły przyrosnąć, gdy aplikacja spała (obserwator HK nie
        // działa w tle) — foreground to główny moment nadrobienia zaległości.
        if let healthStepsStore {
            Task { @MainActor in
                await healthStepsStore.refreshAndSync()
            }
        }
    }

    // MARK: - Sign in with Apple

    /// Uruchamia natywny ekran Sign in with Apple. Po pomyślnym logowaniu wysyła
    /// identityToken + rawNonce do backendu (`POST /auth/apple`), zapisuje sesję.
    func signInWithApple() async {
        isSigningIn = true
        authError = nil
        defer { isSigningIn = false }

        do {
            let appleResult = try await appleSignInCoordinator.start()
            try await exchangeAppleCredential(appleResult)
        } catch AppleSignInError.canceled {
            // Użytkownik anulował — nie pokazuj błędu.
            return
        } catch let error as AppleSignInError {
            authError = error.errorDescription
            isAuthenticated = false
            clearRuntimeStores()
            tearDownSessionSocket()
        } catch {
            authError = UserFacingErrorMapper.inlineMessage(from: error)
            isAuthenticated = false
            clearRuntimeStores()
            tearDownSessionSocket()
        }
    }

    /// POST /auth/apple z identityToken, rawNonce oraz (tylko na pierwszym
    /// logowaniu) imieniem i adresem email.
    private func exchangeAppleCredential(_ credential: AppleSignInResult) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/apple"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = AppleSignInRequest(
            identityToken: credential.identityToken,
            rawNonce: credential.rawNonce,
            givenName: credential.givenName,
            familyName: credential.familyName,
            email: credential.email
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        // Doszliśmy do serwera — niepowodzenie transportu poleciałoby wyżej
        // jako `URLError` i zameldowało się w monitorze przez `inlineMessage`.
        ConnectivityMonitor.noteResponse()
        guard let http = response as? HTTPURLResponse else {
            throw RecipeDataError.serverError(message: "Brak odpowiedzi HTTP z serwera.")
        }
        guard (200...299).contains(http.statusCode) else {
            // Ten sam kontrakt co reszta REST: `{code, message, requestId}`.
            let decoded = try? JSONDecoder().decode(BackendHttpErrorDTO.self, from: data)
            let fallback = "Błąd logowania Apple (HTTP \(http.statusCode))."
            throw RecipeDataError.server(
                code: decoded?.code ?? (http.statusCode == 401 ? "UNAUTHORIZED" : "HTTP_ERROR"),
                message: decoded?.message ?? fallback,
                status: http.statusCode,
                requestId: decoded?.requestId
            )
        }

        let decoded = try JSONDecoder().decode(SessionResponse.self, from: data)
        persistSession(decoded, appleUserIdentifier: credential.userIdentifier)
        if let household = decoded.household {
            bootstrapSession(userId: decoded.user.id, householdId: household.id, householdName: household.name)
        } else {
            currentUserId = decoded.user.id
            currentHouseholdId = nil
            currentHouseholdName = nil
        }
        await registerPushDeviceIfPossible()
        isAuthenticated = true

        // Odpowiedź auth niesie tylko tożsamość i dom. Sylwetka (rok
        // urodzenia, wzrost, waga, płeć) mieszka w bazie i wracała na ekran
        // dopiero przy `users:me` po RESTARCIE aplikacji — wylogowanie
        // i ponowne zalogowanie wyglądało więc jak reset ustawień profilu,
        // bo logout czyści lokalne kopie. Dociągamy pełny profil od razu,
        // w tle, żeby nie przedłużać spinnera logowania.
        Task { [weak self] in
            await self?.restoreHouseholdIfNeeded()
        }
    }

    func logout() {
        // Trwający refresh: `cancel()` przerywa żądanie w locie, a gdy odpowiedź
        // już przyszła, przed zapisem tokenów `refreshSessionTokens` sprawdza,
        // czy refresh token w Keychain to nadal ten użyty — po
        // `clearPersistedSession()` nie jest, więc nowa para nie wskrzesi sesji.
        refreshTask?.cancel()
        refreshTask = nil
        proactiveRefreshTimerTask?.cancel()
        proactiveRefreshTimerTask = nil
        socketAuthRetryTask?.cancel()
        socketAuthRetryTask = nil
        socketAuthRetryCount = 0
        // Best-effort: refresh token przestaje działać także po stronie
        // serwera (dotąd logout był tylko lokalny, a token żył jeszcze 30 dni).
        if let refreshToken = currentRefreshToken, !refreshToken.isEmpty {
            let client = AuthAPIClient(baseURL: baseURL)
            Task.detached {
                try? await client.logout(refreshToken: refreshToken)
            }
        }
        // Token push przestaje należeć do tego konta — inaczej poprzedni
        // użytkownik telefonu dostawał pushe cudzego domu. Best-effort, przed
        // zamknięciem socketu sesji.
        unregisterPushDeviceBestEffort()
        tearDownSessionSocket()
        clearPersistedSession()
        clearHouseholdMembersCache()
        clearRuntimeStores()
        isAuthenticated = false
        authError = nil
        currentUserId = nil
        currentHouseholdId = nil
        currentHouseholdName = nil
        startupPhase = .idle
        isRestoringSession = false
        // Następne logowanie ma zacząć od Kalendarza, a nie od zakładki,
        // na której ktoś zostawił poprzednią sesję.
        dashboardTab = .calendar
    }

    /// Trwale usuwa konto: wypisuje z gospodarstwa, kasuje użytkownika po
    /// stronie backendu, a na koniec czyści sesję lokalnie.
    ///
    /// Kolejność jest istotna. `logout()` leci dopiero po potwierdzeniu
    /// z serwera — gdyby poszedł wcześniej, nieudane żądanie zostawiłoby
    /// wylogowanego użytkownika z żywym kontem i bez sposobu, żeby spróbować
    /// ponownie. Zwraca `false`, gdy kasowanie się nie powiodło; wtedy
    /// sesja zostaje nietknięta, a wywołujący pokazuje błąd.
    @MainActor
    func deleteAccount() async -> Bool {
        guard let userId = currentUserId, !userId.isEmpty else { return false }

        let socket = sessionSocket()

        // App Review 5.1.1(v): kasowanie konta ma unieważnić tokeny Sign in
        // with Apple. Serwer robi to kodem autoryzacji ze ŚWIEŻEJ autoryzacji
        // (kod z logowania żyje 5 minut), więc prosimy Apple jeszcze raz.
        // Anulowanie okna Apple nie blokuje kasowania — konto i tak znika,
        // a serwer unieważnia, co może.
        var payload: [String: Any] = ["userId": userId]
        if UserDefaults.standard.string(forKey: Keys.appleUserIdentifier) != nil,
           let code = try? await appleSignInCoordinator.start().authorizationCode,
           !code.isEmpty {
            payload["appleAuthorizationCode"] = code
        }

        do {
            let envelope: WsEnvelope<BackendDeletedUserDTO> = try await socket.emitWithAck(
                event: "users:delete",
                payload: payload,
                as: WsEnvelope<BackendDeletedUserDTO>.self
            )

            guard envelope.ok else {
                authError = UserFacingErrorMapper.message(
                    from: envelope.failure(fallback: "Nie udało się usunąć konta. Spróbuj ponownie.")
                )
                return false
            }
        } catch {
            authError = UserFacingErrorMapper.inlineMessage(from: error)
            return false
        }

        // Konto już nie istnieje, więc oprócz zwykłego wylogowania trzeba
        // zdjąć też dane profilowe i preferencje — inaczej następne logowanie
        // na tym urządzeniu zastałoby cudzy wzrost i cudzą dietę.
        clearPersistedProfileFields()
        clearPersistedPreferences()
        logout()
        return true
    }

    func updatePushDeviceToken(_ token: String) {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        pendingPushDeviceToken = normalized
        UserDefaults.standard.set(normalized, forKey: Keys.pushDeviceToken)
        Task { [weak self] in
            await self?.registerPushDeviceIfPossible()
        }
    }

    /// Na starcie aplikacji pytamy Apple o aktualny stan podpisanego wcześniej
    /// użytkownika. Wylogowujemy się tylko przy jawnym `.revoked` (user cofnął
    /// dostęp w Ustawieniach → Apple ID). `.notFound` bywa zwracane przejściowo,
    /// szczególnie na iOS Simulatorze po restarcie procesu — lokalny logout w
    /// tym przypadku kasowałby ważną sesję. Gdy token faktycznie wygaśnie,
    /// backend zwróci 401 i wtedy zadziała refresh/logout.
    func validateAppleCredentialStateIfNeeded() async {
        guard
            let userIdentifier = UserDefaults.standard.string(forKey: Keys.appleUserIdentifier),
            !userIdentifier.isEmpty
        else { return }

        let state = await AppleSignInCoordinator.currentCredentialState(for: userIdentifier)
        switch state {
        case .revoked:
            logout()
        case .authorized, .transferred, .notFound:
            break
        @unknown default:
            break
        }
    }

    private func restoreSession() {
        let snapshot = restoredSessionSnapshot()
        debugLog(
            "[SessionStore] restoreSession userId=\(snapshot?.userId ?? "<nil>") householdId=\(snapshot?.householdId ?? "<nil>")"
        )
        guard let snapshot else {
            debugLog("[SessionStore] restoreSession EARLY RETURN — userId missing")
            return
        }
        // Od Fazy 0 socket i REST wymagają tokenu. `userId` w UserDefaults
        // migruje z backupem telefonu, Keychain (ThisDeviceOnly) nie — bez
        // tokenu „zalogowana" sesja byłaby martwa na każdym ekranie.
        guard let accessToken = currentAccessToken, !accessToken.isEmpty else {
            let status = KeychainService.status(forKey: Keys.accessToken)
            if status == errSecItemNotFound {
                debugLog("[SessionStore] restoreSession EARLY RETURN — access token missing")
                clearPersistedSession()
            } else {
                // Keychain chwilowo niedostępny (proces obudzony przed pierwszym
                // odblokowaniem po restarcie, przejściowy błąd) — sesja żyje,
                // wrócimy do niej przy pierwszym wejściu na pierwszy plan.
                debugLog("[SessionStore] restoreSession deferred — keychain status \(status)")
                restoreDeferredUntilKeychainAvailable = true
            }
            return
        }
        restoreDeferredUntilKeychainAvailable = false

        syncPersistedSessionSnapshot(snapshot)
        currentUserId = snapshot.userId
        let householdId = snapshot.householdId
        let householdName = (snapshot.householdName?.isEmpty == false) ? snapshot.householdName : nil
        // Wygasły access token: socket łączyłby się od razu martwym tokenem
        // i każde żądanie startu dostawałoby odmowę, zanim refresh zdąży —
        // wtedy bootstrap czeka na nową parę.
        let tokenAlreadyExpired = accessTokenExpiry().map { $0 <= Date() } ?? false
        var deferredBootstrap = false
        if let householdId, !householdId.isEmpty, !tokenAlreadyExpired {
            bootstrapSession(
                userId: snapshot.userId,
                householdId: householdId,
                householdName: householdName
            )
            // Podnosimy skopiowany z dysku snapshot domowników od razu — jeśli jest świeży,
            // sheet Gospodarstwo otworzy się bez pustego stanu nawet przy cold starcie.
            loadHouseholdMembersFromCacheIfFresh(for: householdId)
        } else {
            // Brak persisted householdu (albo wygasły token) — loader zamiast
            // mignięcia NoHouseholdView, dopóki nie wrócimy z backendu.
            if let householdId, !householdId.isEmpty { deferredBootstrap = true }
            isRestoringSession = true
        }
        let snapshotUserId = snapshot.userId
        Task { [weak self] in
            // Najpierw token: wygasły access token dostałby od socketu i REST
            // same odmowy, a refresh po 401 tylko by to odwlekał.
            await self?.refreshSessionTokensIfExpiringSoon()
            if let self, deferredBootstrap, self.isAuthenticated,
               let householdId, !householdId.isEmpty {
                self.bootstrapSession(
                    userId: snapshotUserId,
                    householdId: householdId,
                    householdName: householdName
                )
                self.loadHouseholdMembersFromCacheIfFresh(for: householdId)
            }
            await self?.restoreHouseholdIfNeeded()
            await self?.registerPushDeviceIfPossible()
            await self?.validateAppleCredentialStateIfNeeded()
            await MainActor.run { [weak self] in
                self?.isRestoringSession = false
            }
        }
        isAuthenticated = true
    }

    private func bootstrapSession(userId: String, householdId: String, householdName: String? = nil) {
        let householdChanged = currentHouseholdId != householdId
        currentUserId = userId
        currentHouseholdId = householdId
        currentHouseholdName = householdName
        // Nowy rebootstrap (logowanie / switch household) — startup musi przejść ponownie.
        startupPhase = .idle
        if householdChanged {
            householdMembers = []
            didLoadHouseholdMembers = false
            householdMembersTask?.cancel()
            householdMembersTask = nil
        }
        let datesViewModel = DatesViewModel()
        self.datesViewModel = datesViewModel
        // Każde wejście do sesji (logowanie, restore po zimnym starcie,
        // zmiana gospodarstwa) zaczyna się od Kalendarza. Bez tego zakładka
        // zostawała tam, gdzie stała poprzednia sesja na tym telefonie —
        // wylogowanie i ponowne logowanie wrzucało użytkownika w Plan
        // tygodnia albo w Ustawienia zamiast na ekran „co dziś jem".
        dashboardTab = .calendar
        // Stary warmup (katalog na starym sockecie, poprzednie gospodarstwo)
        // nie ma już czego dociągać.
        startupTask?.cancel()
        startupTask = nil
        // Nowy socket sesji z tokenem w handshake — stary (inne gospodarstwo
        // albo świeże logowanie) zamykamy, żeby nie dublował obserwatorów.
        let socketClient = replaceSessionSocket()

        let recipeTransport = WebSocketRecipeTransportClient(
            socket: socketClient,
            userId: userId,
            householdId: householdId
        )
        let weeklyPlanTransport = WebSocketWeeklyPlanTransportClient(
            socket: socketClient,
            userId: userId,
            householdId: householdId
        )
        let shoppingTransport = WebSocketShoppingListTransportClient(
            socket: socketClient,
            userId: userId,
            householdId: householdId
        )

        self.mealCalendarStore = MealCalendarStore(
            weeklyPlanRepository: ApiWeeklyPlanRepository(client: weeklyPlanTransport),
            currentUserId: userId,
            cacheNamespace: "\(userId)_\(householdId)"
        )
        self.recipeCatalogStore = RecipeCatalogStore(
            repository: ApiRecipeRepository(client: recipeTransport)
        )
        let shoppingListStore = ShoppingListStore(
            repository: ApiShoppingListRepository(client: shoppingTransport),
            currentUserId: userId,
            cacheNamespace: "\(userId)_\(householdId)"
        )
        self.shoppingListStore = shoppingListStore

        let cookidooStore = CookidooIntegrationStore(
            client: IntegrationsAPIClient(
                baseURL: baseURL,
                tokenProvider: { [weak self] in self?.currentAccessToken },
                refreshSession: { [weak self] in
                    await self?.refreshSessionTokens() == .refreshed
                }
            )
        )
        self.cookidooIntegrationStore = cookidooStore
        // Stan integracji od razu przy starcie — ekran przepisu musi wiedzieć,
        // czy rysować „Gotuj w Thermomixie", zanim ktoś otworzy Ustawienia.
        Task { @MainActor in
            await cookidooStore.refresh()
        }

        let healthStore = HealthStepsStore(
            service: HealthKitService(),
            client: IntegrationsAPIClient(
                baseURL: baseURL,
                tokenProvider: { [weak self] in self?.currentAccessToken },
                refreshSession: { [weak self] in
                    await self?.refreshSessionTokens() == .refreshed
                }
            )
        )
        self.healthStepsStore = healthStore

        self.agentStore = AgentStore(
            client: AgentAPIClient(
                baseURL: baseURL,
                tokenProvider: { [weak self] in self?.currentAccessToken },
                refreshSession: { [weak self] in
                    await self?.refreshSessionTokens() == .refreshed
                }
            ),
            householdId: householdId
        )
        let restCore = BackendRESTCore(
            baseURL: baseURL,
            tokenProvider: { [weak self] in self?.currentAccessToken },
            refreshSession: { [weak self] in
                await self?.refreshSessionTokens() == .refreshed
            }
        )
        let consentStore = ConsentStore(client: ConsentsAPIClient(core: restCore))
        self.consentStore = consentStore
        self.dataExportClient = DataExportAPIClient(core: restCore)
        self.subscriptionStore = SubscriptionStore(
            client: BillingAPIClient(core: restCore),
            userId: currentUserId
        )
        // Stan zgód od razu: wiersz w Ustawieniach i bramka asystenta mają
        // wiedzieć, zanim ktoś stuknie.
        Task { @MainActor in
            await consentStore.refresh()
        }
        // Świeże kroki od razu przy starcie sesji + obserwacja na żywo.
        // Oba to no-opy, dopóki użytkownik nie włączy integracji w Ustawieniach.
        healthStore.startObserving()
        Task { @MainActor in
            await healthStore.refreshAndSync()
        }

        observeHouseholdRealtime()
        observeMealSlotsRealtime()

        let initialWeekStart = datesViewModel.weekStartISO
        Task {
            await shoppingListStore.load(weekStart: initialWeekStart)
        }

        // Pull the user's diet / kcal / allergens row so AppStorage
        // mirrors the backend before any view reads from it. Cached values
        // continue to display while this runs in the background.
        Task { @MainActor [weak self] in
            await self?.loadUserPreferences()
            // Strefa czasowa mogła się zmienić między sesjami (podróż), a
            // serwer potrzebuje jej do ciszy nocnej — odsyłamy stan
            // przełączników od razu po ich wczytaniu.
            await self?.syncNotificationPreferences()
        }

        // To samo dla zestawu posiłków gospodarstwa — Plan i Kalendarz
        // rysują sloty z `mealSlots`, więc lepiej mieć świeżą listę zanim
        // użytkownik zdąży przewinąć tydzień.
        Task { @MainActor [weak self] in
            await self?.loadMealSlotConfiguration()
        }

        // Skrzynka zaproszeń — zaproszenie mogło przyjść, gdy aplikacja była
        // wyłączona, a bez tego pobrania nie ma jak się o nim dowiedzieć.
        Task { @MainActor [weak self] in
            // Najpierw link odłożony przed zalogowaniem: dopiero on dopisuje
            // zaproszenie do skrzynki, więc kolejność ma znaczenie.
            await self?.replayStoredInvitationIfNeeded()
            await self?.refreshPendingInvitations()
        }

        // Recover from the rare "household exists but onboardingCompletedAt
        // is nil" state — the previous launch likely crashed between
        // createHousehold and completeOnboarding. We don't make the user
        // re-do the welcome flow; instead we flip the backend flag so the
        // next `users:me` returns a stable shape.
        if onboardingCompletedAt == nil {
            Task { @MainActor [weak self] in
                await self?.completeOnboarding()
            }
        }
    }

    /// `notifications:unregisterDevice` z zapamiętanym tokenem APNs.
    /// Nie czeka na odpowiedź: wylogowanie nie może wisieć na sieci.
    private func unregisterPushDeviceBestEffort() {
        guard let userId = currentUserId, !userId.isEmpty,
              let token = UserDefaults.standard.string(forKey: Keys.pushDeviceToken), !token.isEmpty
        else { return }
        let socketClient = sessionSocket()
        Task { @MainActor in
            let _: WsEnvelope<PushDeviceUnregisterAckDTO>? = try? await socketClient.emitWithAck(
                event: "notifications:unregisterDevice",
                payload: ["userId": userId, "data": ["deviceToken": token]],
                as: WsEnvelope<PushDeviceUnregisterAckDTO>.self
            )
        }
    }

    private func clearRuntimeStores() {
        realtimeSocket?.off(event: "households:membersChanged")
        realtimeSocket?.off(event: "households:mealTypesChanged")
        realtimeSocket?.off(event: "households:mealTimesChanged")
        // Socket sesji zostaje: to sprzątanie po gospodarstwie, nie po koncie
        // (wyjście z domu, usunięcie z domu). Serwer sam przepina pokoje;
        // wylogowanie zamyka go w `tearDownSessionSocket()`.
        mealCalendarStore = nil
        // Plan i lista zakupów leżą na dysku per konto+dom — po wyjściu z domu
        // albo wylogowaniu nie mają prawa zostać dla następnej osoby.
        MealCalendarStore.clearCache()
        ShoppingListStore.clearCache()
        // Plik cache katalogu nie jest przypisany do konta: bez tego następna
        // osoba zalogowana na tym telefonie widziała przez 12 h katalog
        // (ulubione, tytuły) poprzedniego gospodarstwa.
        RecipeCatalogStore.clearCache()
        recipeCatalogStore = nil
        shoppingListStore = nil
        cookidooIntegrationStore = nil
        healthStepsStore?.stopObserving()
        healthStepsStore = nil
        // Rozmowy zostają na serwerze (użytkownik kasuje je sam, świadomie) —
        // tu znika tylko stan w pamięci telefonu.
        agentStore = nil
        consentStore = nil
        dataExportClient = nil
        subscriptionStore = nil
        datesViewModel = DatesViewModel()
        startupTask?.cancel()
        startupTask = nil
        householdMembersTask?.cancel()
        householdMembersTask = nil
        householdMembers = []
        isLoadingHouseholdMembers = false
        didLoadHouseholdMembers = false
        householdMembersLoadedAt = nil
        pendingInvitations = []
        isPushDeliveryActive = false
    }

    private func observeHouseholdRealtime() {
        realtimeSocket?.off(event: "households:membersChanged")
        realtimeSocket?.on(event: "households:membersChanged") { [weak self] items in
            guard let self else { return }
            guard let first = items.first,
                  JSONSerialization.isValidJSONObject(first),
                  let data = try? JSONSerialization.data(withJSONObject: first),
                  let event = try? JSONDecoder().decode(BackendHouseholdMembersChangedDTO.self, from: data)
            else { return }

            Task { @MainActor in
                guard let currentHouseholdId = self.currentHouseholdId, !currentHouseholdId.isEmpty else { return }
                guard event.householdId == currentHouseholdId else { return }
                self.householdRealtimeVersion &+= 1

                let snapshots = event.members?.map(HouseholdMemberSnapshot.init(backend:))

                // Usunięcie MNIE: nowa lista przyszła bez mojego id. Zamiast
                // rysować dom, w którym mnie już nie ma, sprzątamy jak przy
                // własnym wyjściu — z osobnym powiadomieniem, bo różnica
                // między „opuściłem" a „usunięto mnie" jest dla użytkownika
                // całą treścią tego zdarzenia.
                if event.action == "REMOVE_MEMBER",
                   let snapshots,
                   let me = self.currentUserId,
                   !snapshots.contains(where: { $0.id == me }) {
                    await self.handleRemovedFromHousehold()
                    return
                }

                // Dołączenie domownika ma być WIDOCZNE, a nie tylko odświeżone
                // po cichu na liście — o to prosił użytkownik, któremu ktoś
                // dołączył do gospodarstwa i nie dowiedział się o tym niczym.
                // Push wysyła backend; to jest kanał zapasowy na wypadek, gdyby
                // APNs nie działał (symulator, brak kluczy, odmowa uprawnień).
                if event.changedByUserId != nil, event.changedByUserId != self.currentUserId {
                    PlanChangeNotificationService.notifyHouseholdMembershipChange(
                        action: event.action,
                        householdId: currentHouseholdId,
                        changedByDisplayName: event.changedByDisplayName,
                        // Kogo usunięto, liczymy z różnicy list — ładunek
                        // zdarzenia wozi tylko autora zmiany.
                        affectedDisplayName: self.removedMemberName(newMembers: snapshots)
                    )
                }

                // Nowy skład jedzie w ładunku, więc nie wracamy po niego na
                // serwer — dokładnie tak jak przy `mealTypesChanged`. Ten
                // dodatkowy round-trip był ostatnim miejscem, w którym
                // odświeżenie listy mogło po cichu przepaść.
                if let snapshots {
                    self.applyHouseholdMembers(snapshots, householdId: currentHouseholdId)
                    return
                }

                await self.refreshHouseholdMembers(force: true)
            }
        }

        // Rozgłoszenie po sockecie jest jednorazowe i nie ma powtórek: jeśli
        // aplikacja była w tle albo bez sieci, gdy ktoś dołączał, zdarzenie
        // przepada bezpowrotnie. Odzyskujemy je przy każdym (re)połączeniu —
        // ten sam wzorzec, którego używają już `MealCalendarStore`
        // i `ShoppingListStore`.
        realtimeSocket?.observeConnection { [weak self] isConnected in
            guard isConnected else { return }
            Task { @MainActor in
                await self?.refreshHouseholdMembers(force: true)
                await self?.refreshPendingInvitations()
            }
        }
    }

    /// Jedno miejsce, w którym skład gospodarstwa trafia do stanu i do cache'u.
    @MainActor
    private func applyHouseholdMembers(
        _ members: [HouseholdMemberSnapshot],
        householdId: String
    ) {
        householdMembers = members
        didLoadHouseholdMembers = true
        householdMembersLoadedAt = Date()
        saveHouseholdMembersCache(householdId: householdId, members: members)
        syncOwnAvatarColor(from: members)
    }

    /// Skład gospodarstwa jest źródłem prawdy o kolorach awatarów — także
    /// o WŁASNYM. Lokalny `settings.user.avatarColor` potrafił zostać przy
    /// `-1` na zawsze (logowanie na backendzie sprzed `avatarColor` w auth
    /// nie niesie koloru, a `users:me` leci dopiero przy restore sesji) —
    /// wtedy karta profilu w Ustawieniach świeciła fallbackiem z hasza,
    /// a listy domowników kolorem przydzielonym przez backend. Przepisanie
    /// własnego koloru przy KAŻDYM załadowaniu składu domyka tę lukę
    /// niezależnie od tego, którą drogą skład przyszedł (fetch, zdarzenie
    /// realtime, plik cache).
    private func syncOwnAvatarColor(from members: [HouseholdMemberSnapshot]) {
        guard let userId = currentUserId, !userId.isEmpty,
              let ownColor = members.first(where: { $0.id == userId })?.avatarColor
        else { return }
        UserDefaults.standard.set(ownColor, forKey: Keys.avatarColor)
    }

    /// Kogo ubyło względem obecnej listy — do treści powiadomienia
    /// o usunięciu. `nil`, gdy nikt nie zniknął albo zdarzenie przyszło
    /// bez nowej listy.
    private func removedMemberName(newMembers: [HouseholdMemberSnapshot]?) -> String? {
        guard let newMembers else { return nil }
        let newIds = Set(newMembers.map(\.id))
        return householdMembers.first { !newIds.contains($0.id) }?.displayName
    }

    /// Sprzątanie po usunięciu NAS z gospodarstwa przez właściciela — lustro
    /// pomyślnej ścieżki `leaveCurrentHousehold`, tylko bez round-tripa,
    /// bo członkostwa już nie ma.
    private func handleRemovedFromHousehold() async {
        PlanChangeNotificationService.notifyRemovedFromHousehold(
            householdId: currentHouseholdId,
            householdName: currentHouseholdName
        )
        clearPersistedHousehold()
        clearRuntimeStores()
        currentHouseholdId = nil
        currentHouseholdName = nil
        isAuthenticated = true
        // Jak po własnym wyjściu: użytkownik ląduje na ekranie zakładania
        // gospodarstwa, a czekające zaproszenia są tam jedyną alternatywą
        // dla zakładania własnego domu.
        await refreshPendingInvitations()
    }

    // MARK: - Posiłki planowane przez gospodarstwo

    private func observeMealSlotsRealtime() {
        realtimeSocket?.off(event: "households:mealTypesChanged")
        realtimeSocket?.on(event: "households:mealTypesChanged") { [weak self] items in
            guard let self else { return }
            guard let first = items.first,
                  JSONSerialization.isValidJSONObject(first),
                  let data = try? JSONSerialization.data(withJSONObject: first),
                  let event = try? JSONDecoder().decode(BackendHouseholdMealTypesChangedDTO.self, from: data)
            else { return }

            Task { @MainActor in
                guard let currentHouseholdId = self.currentHouseholdId, !currentHouseholdId.isEmpty else { return }
                guard event.householdId == currentHouseholdId else { return }
                // Ładunek niesie już nową listę, więc nie wracamy po nią na
                // serwer — plan przebudowuje się od razu u wszystkich w domu.
                self.applyMealSlots(MealSlotConfiguration(backendMealTypes: event.mealTypes))
            }
        }

        realtimeSocket?.off(event: "households:mealTimesChanged")
        realtimeSocket?.on(event: "households:mealTimesChanged") { [weak self] items in
            guard let self else { return }
            guard let first = items.first,
                  JSONSerialization.isValidJSONObject(first),
                  let data = try? JSONSerialization.data(withJSONObject: first),
                  let event = try? JSONDecoder().decode(BackendHouseholdMealTimesChangedDTO.self, from: data)
            else { return }

            Task { @MainActor in
                guard let currentHouseholdId = self.currentHouseholdId, !currentHouseholdId.isEmpty else { return }
                guard event.householdId == currentHouseholdId else { return }
                guard let times = MealSlotSchedule(backendMealSlotTimes: event.mealSlotTimes) else { return }
                self.applyMealSlotSchedule(times)
            }
        }
    }

    @MainActor
    private func applyMealSlots(_ configuration: MealSlotConfiguration) {
        mealSlots = configuration
        UserDefaults.standard.set(
            configuration.storageValue,
            forKey: MealSlotConfiguration.Keys.enabledSlots
        )
    }

    @MainActor
    private func applyMealSlotSchedule(_ schedule: MealSlotSchedule) {
        mealSlotSchedule = schedule
        UserDefaults.standard.set(schedule.storageValue, forKey: MealSlotSchedule.Keys.times)
    }

    /// Zapisuje godziny posiłków. Optymistycznie: UI zmienia się od razu,
    /// a przy błędzie wracamy do poprzedniego rozkładu — inaczej zegar
    /// w ustawieniach pokazywałby godzinę, której nikt poza tym telefonem
    /// nie zobaczy.
    @MainActor
    @discardableResult
    func saveMealSlotSchedule(_ schedule: MealSlotSchedule) async -> Bool {
        let previous = mealSlotSchedule
        applyMealSlotSchedule(schedule)

        guard let userId = currentUserId, !userId.isEmpty,
              let householdId = currentHouseholdId, !householdId.isEmpty else {
            // Brak sesji: zostaje lustro lokalne. To jedyna ścieżka, w której
            // rozkład nie jedzie na serwer, i nie jest błędem — po zalogowaniu
            // gospodarstwo i tak przyśle swój.
            return true
        }

        let socket = sessionSocket()
        do {
            let envelope: WsEnvelope<BackendHouseholdDTO> = try await socket.emitWithAck(
                event: "households:updateMealTimes",
                payload: [
                    "userId": userId,
                    "householdId": householdId,
                    "data": ["mealSlotTimes": schedule.backendMealSlotTimes]
                ],
                as: WsEnvelope<BackendHouseholdDTO>.self
            )
            guard envelope.ok, let household = envelope.data else {
                applyMealSlotSchedule(previous)
                return false
            }
            if let times = MealSlotSchedule(backendMealSlotTimes: household.mealSlotTimes) {
                applyMealSlotSchedule(times)
            }
            return true
        } catch {
            applyMealSlotSchedule(previous)
            return false
        }
    }

    /// Pobiera konfigurację posiłków bieżącego gospodarstwa.
    /// Ciche na błędach — lokalne lustro zostaje jako fallback offline.
    @MainActor
    func loadMealSlotConfiguration() async {
        guard let userId = currentUserId, !userId.isEmpty,
              let householdId = currentHouseholdId, !householdId.isEmpty else { return }

        let socket = sessionSocket()
        do {
            let envelope: WsEnvelope<BackendHouseholdDTO> = try await socket.emitWithAck(
                event: "households:findById",
                payload: ["userId": userId, "id": householdId],
                as: WsEnvelope<BackendHouseholdDTO>.self
            )
            guard envelope.ok, let household = envelope.data else { return }
            if let mealTypes = household.enabledMealTypes {
                applyMealSlots(MealSlotConfiguration(backendMealTypes: mealTypes))
            }
            if let times = MealSlotSchedule(backendMealSlotTimes: household.mealSlotTimes) {
                applyMealSlotSchedule(times)
            }
        } catch {
            // Cisza — konfiguracja posiłków nie jest krytyczna dla startu,
            // a lokalne lustro jest wystarczająco dobre do następnego wejścia.
        }
    }

    /// Zapisuje nowy zestaw posiłków. Zapis jest optymistyczny: UI zmienia się
    /// od razu, a przy błędzie wracamy do poprzedniego stanu — inaczej
    /// przełącznik w ustawieniach zostawałby „w połowie".
    @MainActor
    @discardableResult
    func saveMealSlotConfiguration(_ configuration: MealSlotConfiguration) async -> Bool {
        guard let userId = currentUserId, !userId.isEmpty,
              let householdId = currentHouseholdId, !householdId.isEmpty else { return false }

        let previous = mealSlots
        applyMealSlots(configuration)

        let socket = sessionSocket()
        do {
            let envelope: WsEnvelope<BackendHouseholdDTO> = try await socket.emitWithAck(
                event: "households:updateMealTypes",
                payload: [
                    "userId": userId,
                    "householdId": householdId,
                    "data": ["mealTypes": configuration.backendMealTypes]
                ],
                as: WsEnvelope<BackendHouseholdDTO>.self
            )
            guard envelope.ok, let household = envelope.data else {
                applyMealSlots(previous)
                return false
            }
            if let mealTypes = household.enabledMealTypes {
                applyMealSlots(MealSlotConfiguration(backendMealTypes: mealTypes))
            }
            return true
        } catch {
            applyMealSlots(previous)
            return false
        }
    }

    /// Granice nazwy gospodarstwa — parytet z `CreateHouseholdDto` (2…64) na
    /// serwerze, który od Fazy 0 waliduje je również na WebSockecie.
    static let householdNameLengthRange = 2...64

    static func isValidHouseholdName(_ name: String) -> Bool {
        householdNameLengthRange.contains(
            name.trimmingCharacters(in: .whitespacesAndNewlines).count
        )
    }

    /// Limit `displayName` z `UpdateProfileDto` (64). Przycinamy PRZED zapisem
    /// lokalnym i wysyłką, bo `saveProfile` zapisuje optymistycznie — dłuższa
    /// nazwa zostawałaby na telefonie, a serwer odrzucałby ją po cichu.
    static let displayNameMaxLength = 64

    func createHousehold(name: String) async {
        guard let userId = currentUserId, !userId.isEmpty else {
            authError = "Brak użytkownika sesji."
            return
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            authError = "Podaj nazwę gospodarstwa."
            return
        }
        guard Self.isValidHouseholdName(trimmed) else {
            authError = "Nazwa gospodarstwa musi mieć od 2 do 64 znaków."
            return
        }

        isSigningIn = true
        authError = nil
        defer { isSigningIn = false }

        do {
            let socketClient = sessionSocket()
            let envelope: WsEnvelope<BackendHouseholdDTO> = try await socketClient.emitWithAck(
                event: "households:create",
                payload: [
                    "userId": userId,
                    "data": ["name": trimmed]
                ],
                as: WsEnvelope<BackendHouseholdDTO>.self
            )

            guard envelope.ok, let household = envelope.data else {
                throw envelope.failure(fallback: "Nie udało się utworzyć gospodarstwa.")
            }

            persistHousehold(id: household.id, name: household.name)
            bootstrapSession(userId: userId, householdId: household.id, householdName: household.name)
            mealCalendarStore?.resetLocalPlanningState()
            await registerPushDeviceIfPossible()
            isAuthenticated = true
        } catch {
            authError = UserFacingErrorMapper.inlineMessage(from: error)
        }
    }

    func leaveCurrentHousehold() async {
        guard let userId = currentUserId, !userId.isEmpty,
              let householdId = currentHouseholdId, !householdId.isEmpty else { return }

        isSigningIn = true
        authError = nil
        defer { isSigningIn = false }

        do {
            let socketClient = sessionSocket()
            let envelope: WsEnvelope<HouseholdLeaveAckDTO> = try await socketClient.emitWithAck(
                event: "households:leave",
                payload: [
                    "userId": userId,
                    "householdId": householdId
                ],
                as: WsEnvelope<HouseholdLeaveAckDTO>.self
            )

            if !envelope.ok {
                throw envelope.failure(fallback: "Nie udało się opuścić gospodarstwa.")
            }

            clearPersistedHousehold()
            clearRuntimeStores()
            currentHouseholdId = nil
            currentHouseholdName = nil
            isAuthenticated = true
            // Po wyjściu użytkownik ląduje na ekranie zakładania gospodarstwa.
            // `clearRuntimeStores` wyczyściło skrzynkę, a to właśnie tam
            // czekające zaproszenie jest najbardziej potrzebne — bez tego
            // jedynym widocznym wyjściem byłoby założenie własnego domu.
            await refreshPendingInvitations()
        } catch is CancellationError {
            // Ignore task cancellation caused by view lifecycle updates.
            return
        } catch {
            authError = UserFacingErrorMapper.inlineMessage(from: error)
        }
    }

    /// Usunięcie domownika przez właściciela. Autoryzację rozstrzyga backend
    /// (`ensureOwner` + ochrona ostatniego właściciela) — UI pokazuje akcję
    /// tylko właścicielowi, więc błąd uprawnień to ostatnia linia obrony,
    /// a nie ścieżka, którą ktoś ma oglądać.
    @discardableResult
    func removeHouseholdMember(memberUserId: String) async -> Bool {
        guard let userId = currentUserId, !userId.isEmpty,
              let householdId = currentHouseholdId, !householdId.isEmpty,
              !memberUserId.isEmpty, memberUserId != userId else { return false }

        authError = nil
        do {
            let socketClient = sessionSocket()
            let envelope: WsEnvelope<BackendMembershipDTO> = try await socketClient.emitWithAck(
                event: "households:removeMember",
                payload: [
                    "userId": userId,
                    "householdId": householdId,
                    "memberUserId": memberUserId
                ],
                as: WsEnvelope<BackendMembershipDTO>.self
            )

            if !envelope.ok {
                throw envelope.failure(fallback: "Nie udało się usunąć domownika.")
            }

            // `membersChanged` przywiezie nową listę, ale bez gwarancji
            // kolejności względem acka — zdejmujemy osobę od razu, żeby wiersz
            // nie wracał na moment po zamknięciu alertu.
            householdMembers.removeAll { $0.id == memberUserId }
            await refreshHouseholdMembers(force: true)
            return true
        } catch is CancellationError {
            return false
        } catch {
            authError = UserFacingErrorMapper.inlineMessage(from: error)
            return false
        }
    }

    func createInvitationLink() async throws -> URL {
        guard let userId = currentUserId, !userId.isEmpty,
              let householdId = currentHouseholdId, !householdId.isEmpty else {
            throw RecipeDataError.serverError(message: "Brak aktywnego gospodarstwa.")
        }

        let socketClient = sessionSocket()
        let envelope: WsEnvelope<BackendInvitationDTO> = try await socketClient.emitWithAck(
            event: "households:createInvitation",
            payload: [
                "userId": userId,
                "householdId": householdId,
                "data": [:]
            ],
            as: WsEnvelope<BackendInvitationDTO>.self
        )

        guard envelope.ok, let invitation = envelope.data else {
            throw envelope.failure(fallback: "Nie udało się utworzyć zaproszenia.")
        }

        var components = URLComponents()
        components.scheme = "scoffie"
        components.host = "invite"
        components.queryItems = [
            URLQueryItem(name: "token", value: invitation.token)
        ]
        guard let url = components.url else {
            throw RecipeDataError.serverError(message: "Nie udało się zbudować linku zaproszenia.")
        }
        return url
    }

    private func previewInvitation(token: String) async throws -> BackendInvitationPreviewDTO {
        guard let userId = currentUserId, !userId.isEmpty else {
            throw RecipeDataError.serverError(message: "Zaloguj się, aby dołączyć do gospodarstwa.")
        }

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw RecipeDataError.serverError(message: "Nieprawidłowy token zaproszenia.")
        }

        let socketClient = sessionSocket()
        let envelope: WsEnvelope<BackendInvitationPreviewDTO> = try await socketClient.emitWithAck(
            event: "households:previewInvitation",
            payload: [
                "userId": userId,
                "data": ["token": trimmedToken]
            ],
            as: WsEnvelope<BackendInvitationPreviewDTO>.self
        )

        guard envelope.ok, let data = envelope.data else {
            throw envelope.failure(fallback: "Nie udało się sprawdzić zaproszenia.")
        }

        return data
    }

    /// - Parameter leaveOtherHouseholds: zgoda na opuszczenie dotychczasowego
    ///   gospodarstwa. Bez niej backend odpowie `INVITATION_REQUIRES_LEAVE` —
    ///   konto obsługuje jeden dom naraz, a taka decyzja nie może zapaść bez
    ///   pytania.
    func acceptInvitation(token: String, leaveOtherHouseholds: Bool = false) async throws {
        guard let userId = currentUserId, !userId.isEmpty else {
            throw RecipeDataError.serverError(message: "Brak użytkownika sesji.")
        }

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw RecipeDataError.serverError(message: "Nieprawidłowy token zaproszenia.")
        }

        isSigningIn = true
        authError = nil
        defer { isSigningIn = false }

        let socketClient = sessionSocket()
        let acceptEnvelope: WsEnvelope<BackendMembershipDTO> = try await socketClient.emitWithAck(
            event: "households:acceptInvitation",
            payload: [
                "userId": userId,
                "data": [
                    "token": trimmedToken,
                    "leaveOtherHouseholds": leaveOtherHouseholds
                ]
            ],
            as: WsEnvelope<BackendMembershipDTO>.self
        )

        guard acceptEnvelope.ok, let membership = acceptEnvelope.data else {
            throw RecipeDataError.serverError(message: acceptEnvelope.error ?? "Nie udało się dołączyć do gospodarstwa.")
        }

        let householdEnvelope: WsEnvelope<BackendHouseholdDTO> = try await socketClient.emitWithAck(
            event: "households:findById",
            payload: [
                "userId": userId,
                "id": membership.householdId
            ],
            as: WsEnvelope<BackendHouseholdDTO>.self
        )

        guard householdEnvelope.ok, let household = householdEnvelope.data else {
            throw RecipeDataError.serverError(message: householdEnvelope.error ?? "Dołączono, ale nie udało się pobrać danych gospodarstwa.")
        }

        persistHousehold(id: household.id, name: household.name)
        bootstrapSession(userId: userId, householdId: household.id, householdName: household.name)
        mealCalendarStore?.resetLocalPlanningState()
        await registerPushDeviceIfPossible()
        isAuthenticated = true
        // Przyjęte zaproszenie znika ze skrzynki, a razem z nim wszystkie inne
        // do tego samego domu.
        await refreshPendingInvitations()
        // Backend mógł właśnie zmienić kolor awatara (unika kolizji z nowymi
        // domownikami) — dociągamy go od razu, zamiast czekać na `users:me`
        // przy następnym starcie aplikacji.
        await syncAvatarColorFromBackend()
    }

    /// Pobiera aktualny `avatarColor` z backendu i utrwala go lokalnie.
    /// Cichy no-op przy błędzie sieci — kolor dojedzie przy następnym
    /// pełnym `users:me`.
    private func syncAvatarColorFromBackend() async {
        guard let userId = currentUserId, !userId.isEmpty else { return }
        let socket = sessionSocket()
        do {
            let envelope: WsEnvelope<BackendCurrentUserDTO> = try await socket.emitWithAck(
                event: "users:me",
                payload: ["userId": userId],
                as: WsEnvelope<BackendCurrentUserDTO>.self
            )
            guard envelope.ok, let color = envelope.data?.avatarColor else { return }
            UserDefaults.standard.set(color, forKey: Keys.avatarColor)
        } catch {
            // Patrz komentarz wyżej — brak sieci nie psuje przepływu dołączania.
        }
    }

    func acceptPendingInvitation(token: String, leaveOtherHouseholds: Bool = false) async {
        invitationPrompt = nil
        do {
            try await acceptInvitation(token: token, leaveOtherHouseholds: leaveOtherHouseholds)
        } catch is CancellationError {
            return
        } catch {
            authError = UserFacingErrorMapper.inlineMessage(from: error)
        }
    }

    /// Świadoma odmowa — zaproszenie znika ze skrzynki i nie wraca po
    /// ponownym otwarciu linku.
    func declineInvitation(token: String) async {
        guard let userId = currentUserId, !userId.isEmpty else { return }
        let socket = sessionSocket()
        do {
            let _: WsEnvelope<BackendMutationAckDTO> = try await socket.emitWithAck(
                event: "households:declineInvitation",
                payload: ["userId": userId, "data": ["token": token]],
                as: WsEnvelope<BackendMutationAckDTO>.self
            )
        } catch {
            // Odmowa jest nieistotna dla działania apki — jeśli nie przeszła,
            // zaproszenie po prostu zostanie na liście.
        }
        await refreshPendingInvitations()
    }

    /// Pobiera skrzynkę zaproszeń. Cicha przy błędzie: to lista pomocnicza,
    /// a nie warunek działania ekranu.
    @MainActor
    func refreshPendingInvitations() async {
        guard let userId = currentUserId, !userId.isEmpty else {
            pendingInvitations = []
            return
        }
        let socket = sessionSocket()
        do {
            let envelope: WsEnvelope<[BackendPendingInvitationDTO]> = try await socket.emitWithAck(
                event: "households:listPendingInvitations",
                payload: ["userId": userId],
                as: WsEnvelope<[BackendPendingInvitationDTO]>.self
            )
            guard envelope.ok, let data = envelope.data else { return }
            pendingInvitations = data.compactMap { dto in
                guard let household = dto.household else { return nil }
                return HouseholdInvitationSnapshot(
                    token: dto.token,
                    householdName: household.name,
                    invitedByDisplayName: dto.invitedByDisplayName,
                    expiresAtText: Self.formatInvitationExpiry(dto.expiresAt)
                )
            }
        } catch {
            // Starszy backend nie zna tego zdarzenia — brak skrzynki nie może
            // wywrócić ekranu Ustawień.
        }
    }

    func dismissInvitationPrompt() {
        invitationPrompt = nil
    }

    /// Token zaproszenia, który przyszedł, zanim było wiadomo, kim jest
    /// użytkownik.
    ///
    /// Link otwarty przed zalogowaniem przepadał: `previewInvitation` wymaga
    /// `userId`, więc kończyło się komunikatem „Zaloguj się" i tokenem
    /// wyrzuconym do kosza — a po zalogowaniu nie było już czego otworzyć.
    /// Trzymany w `UserDefaults`, bo logowanie przez Apple potrafi odesłać
    /// użytkownika poza aplikację.
    private static let pendingInvitationTokenKey = "session.pendingInvitationToken"

    private var storedInvitationToken: String? {
        get { UserDefaults.standard.string(forKey: Self.pendingInvitationTokenKey) }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: Self.pendingInvitationTokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pendingInvitationTokenKey)
            }
        }
    }

    /// Odtwarza zaproszenie odłożone przed zalogowaniem. Woła się po
    /// bootstrapie sesji.
    @MainActor
    private func replayStoredInvitationIfNeeded() async {
        guard let token = storedInvitationToken, !token.isEmpty else { return }
        guard let userId = currentUserId, !userId.isEmpty else { return }
        storedInvitationToken = nil
        await presentInvitation(token: token)
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "scoffie", url.host == "invite" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        guard let token = components.queryItems?.first(where: { $0.name == "token" })?.value else { return }

        guard currentUserId?.isEmpty == false else {
            // Odkładamy i wracamy do tego po zalogowaniu — zamiast kazać
            // użytkownikowi szukać linku po raz drugi.
            storedInvitationToken = token
            authError = "Zaloguj się, aby przyjąć zaproszenie do gospodarstwa."
            return
        }

        Task {
            await presentInvitation(token: token)
        }
    }

    /// Sprawdza zaproszenie i pokazuje pytanie, co z nim zrobić.
    @MainActor
    private func presentInvitation(token: String) async {
        do {
            let preview = try await previewInvitation(token: token)
            // Podgląd odkłada zaproszenie do skrzynki po stronie serwera, więc
            // odświeżamy ją niezależnie od tego, co użytkownik zrobi z alertem
            // — także wtedy, gdy go zamknie.
            await refreshPendingInvitations()

            switch preview.status {
            case "PENDING", "REQUIRES_LEAVE":
                let expiry = Self.formatInvitationExpiry(preview.expiresAt)
                invitationPrompt = InvitationPromptState(
                    token: preview.token,
                    householdName: preview.household?.name ?? "Gospodarstwo",
                    invitedByDisplayName: preview.invitedByDisplayName,
                    expiresAtText: expiry,
                    // `REQUIRES_LEAVE` niesie dom do opuszczenia; przy
                    // `PENDING` pole jest puste i alert wygląda jak dotąd.
                    currentHouseholdName: preview.currentHousehold?.name,
                    willDeleteCurrentHousehold: preview.willDeleteCurrentHousehold ?? false
                )
            case "ALREADY_MEMBER":
                authError = "Jesteś już członkiem tego gospodarstwa."
            case "EXPIRED":
                authError = "To zaproszenie wygasło."
            case "REDEEMED":
                authError = "Ten link zaproszenia został już wykorzystany. Poproś o nowy."
            case "DECLINED":
                authError = "To zaproszenie zostało odrzucone. Poproś o nowe."
            case "NOT_FOUND":
                authError = "Nie znaleziono zaproszenia. Sprawdź link."
            default:
                authError = "Nie można użyć tego zaproszenia."
            }
        } catch is CancellationError {
            return
        } catch {
            authError = UserFacingErrorMapper.inlineMessage(from: error)
        }
    }

    private static func formatInvitationExpiry(_ iso8601: String?) -> String? {
        guard let iso8601, !iso8601.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso8601) else { return nil }
        let output = DateFormatter()
        output.locale = Locale(identifier: "pl_PL")
        output.dateStyle = .medium
        output.timeStyle = .short
        return output.string(from: date)
    }

    /// Środowisko APNs tego buildu — musi odpowiadać `aps-environment`
    /// z uprawnień (Debug: development, Release: production).
    private static var apnsEnvironment: String {
        #if DEBUG
        "SANDBOX"
        #else
        "PRODUCTION"
        #endif
    }

    private func registerPushDeviceIfPossible() async {
        guard let userId = currentUserId, !userId.isEmpty else { return }
        guard let token = pendingPushDeviceToken, !token.isEmpty else { return }

        do {
            let socketClient = sessionSocket()
            let envelope: WsEnvelope<PushDeviceRegisterAckDTO> = try await socketClient.emitWithAck(
                event: "notifications:registerDevice",
                payload: [
                    "userId": userId,
                    "data": [
                        "deviceToken": token,
                        "platform": "IOS",
                        "appBundleId": Bundle.main.bundleIdentifier ?? "app.scoffie.ios",
                        // Token z buildu debugowego jest ważny wyłącznie na
                        // sandboksowym hoście APNs, a z TestFlight/App Store
                        // wyłącznie na produkcyjnym. Serwer musi to wiedzieć,
                        // bo pisze do obu flot naraz.
                        "apnsEnvironment": Self.apnsEnvironment,
                    ],
                ],
                as: WsEnvelope<PushDeviceRegisterAckDTO>.self
            )

            if !envelope.ok {
                throw envelope.failure(fallback: "Nie udało się zarejestrować urządzenia.")
            }

            let pushEnabled = envelope.data?.pushEnabled ?? false
            await MainActor.run { [weak self] in
                self?.isPushDeliveryActive = pushEnabled
                // Stores rysujące powiadomienia lokalne pytają o to statycznie —
                // nie znają sesji, a muszą wiedzieć, czy nie dublują pusha.
                PlanChangeNotificationService.setPushDeliveryActive(pushEnabled)
            }
        } catch {
            // App should continue normally even when push registration fails.
        }
    }

    /// Uzgadnia lokalne gospodarstwo ze stanem serwera przy starcie.
    ///
    /// Dwie role: (1) brak persisted householdu → może membership jednak
    /// istnieje (dotychczasowe zachowanie), (2) persisted household, którego
    /// już nie ma po stronie serwera — np. właściciel usunął nas, gdy
    /// aplikacja była wyłączona i zdarzenie socketowe przepadło. Bez tej
    /// drugiej gałęzi aplikacja startowała do „ducha": widoków gospodarstwa,
    /// w którym backend odrzucał każde zapytanie.
    private func restoreHouseholdIfNeeded() async {
        guard let userId = currentUserId, !userId.isEmpty else { return }
        let persistedHouseholdId =
            (currentHouseholdId?.isEmpty == false) ? currentHouseholdId : nil

        do {
            let socketClient = sessionSocket()
            let envelope: WsEnvelope<BackendCurrentUserDTO> = try await socketClient.emitWithAck(
                event: "users:me",
                payload: ["userId": userId],
                as: WsEnvelope<BackendCurrentUserDTO>.self
            )

            guard envelope.ok, let user = envelope.data else {
                return
            }

            let defaults = UserDefaults.standard
            defaults.set(user.displayName, forKey: Keys.displayName)
            defaults.set(user.email ?? "", forKey: Keys.email)
            if let avatarUrl = user.avatarUrl, !avatarUrl.isEmpty {
                defaults.set(avatarUrl, forKey: Keys.avatarUrl)
            } else {
                defaults.removeObject(forKey: Keys.avatarUrl)
            }
            persistProfileFields(
                yearOfBirth: user.yearOfBirth,
                heightCm: user.heightCm,
                weightKg: user.weightKg,
                sex: user.sex
            )
            defaults.set(user.avatarColor ?? -1, forKey: Keys.avatarColor)
            persistOnboardingCompletedAt(user.onboardingCompletedAt)

            guard let membership = user.memberships.first,
                  let household = membership.household else {
                // Serwer mówi wprost: brak członkostwa. Offline tu nie trafia —
                // błąd sieci ląduje w catch i zostawia stan bez zmian.
                if persistedHouseholdId != nil {
                    await handleRemovedFromHousehold()
                }
                return
            }

            guard household.id != persistedHouseholdId else {
                // Ten sam dom co na dysku — bootstrap poszedł już synchronicznie
                // w `restoreSession`, nie przebudowujemy stores drugi raz.
                return
            }

            persistHousehold(id: household.id, name: household.name)
            bootstrapSession(userId: userId, householdId: household.id, householdName: household.name)
        } catch {
            debugLog("[SessionStore] restoreHouseholdIfNeeded FAILED error=\(error.localizedDescription)")
        }
    }

    private func persistSession(_ response: SessionResponse, appleUserIdentifier: String? = nil) {
        debugLog("[SessionStore] persistSession START userId=\(response.user.id) household=\(response.household?.id ?? "nil")")

        // Tokeny auth trafiają do Keychain (szyfrowany, chroniony przez Secure Enclave)
        let accessSaved = KeychainService.save(response.accessToken, forKey: Keys.accessToken)
        let refreshSaved = KeychainService.save(response.refreshToken, forKey: Keys.refreshToken)
        let userIdSaved = KeychainService.save(response.user.id, forKey: Keys.userId)
        debugLog("[SessionStore] keychain saved accessToken=\(accessSaved) refreshToken=\(refreshSaved)")
        debugLog("[SessionStore] keychain saved userId=\(userIdSaved)")
        // Świeżo zalogowany telefon nie ma za sobą foregroundu, który
        // uzbroiłby termin odświeżenia — pierwsza godzina pracy bez
        // przechodzenia w tło skończyłaby się 401.
        armProactiveRefresh()

        // Legacy cleanup: wcześniejsze wersje trzymały tokeny w UserDefaults.
        // Usuwamy je, żeby nie mylić diagnostyki i nie wyciekały przy backupie.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.accessToken)
        defaults.removeObject(forKey: Keys.refreshToken)

        if let appleUserIdentifier, !appleUserIdentifier.isEmpty {
            KeychainService.save(appleUserIdentifier, forKey: Keys.appleUserIdentifier)
            defaults.set(appleUserIdentifier, forKey: Keys.appleUserIdentifier)
        }

        defaults.set(response.user.id, forKey: Keys.userId)
        defaults.set(response.user.displayName, forKey: Keys.displayName)
        defaults.set(response.user.email ?? "", forKey: Keys.email)
        // Apple Sign in doesn't provide a profile photo; avatarUrl is typically
        // nil for Apple users and surfaces initials-based fallback in the UI.
        // For Google / other providers it persists the real URL.
        if let avatarUrl = response.user.avatarUrl, !avatarUrl.isEmpty {
            defaults.set(avatarUrl, forKey: Keys.avatarUrl)
        } else {
            defaults.removeObject(forKey: Keys.avatarUrl)
        }
        // Kolor awatara prosto z logowania — bez tego do czasu pierwszego
        // `users:me` profil świecił fallbackiem z hasza, innym niż listy
        // domowników. `nil` (starszy backend / konto przed onboardingiem)
        // nie nadpisuje wartości, którą mogliśmy już zsynchronizować.
        if let avatarColor = response.user.avatarColor {
            defaults.set(avatarColor, forKey: Keys.avatarColor)
        }
        persistOnboardingCompletedAt(response.user.onboardingCompletedAt)
        if let household = response.household {
            persistHousehold(id: household.id, name: household.name)
        } else {
            clearPersistedHousehold()
        }

        let writtenUserId = defaults.string(forKey: Keys.userId) ?? "<nil>"
        let writtenHouseholdId = defaults.string(forKey: Keys.householdId) ?? "<nil>"
        debugLog("[SessionStore] persistSession DONE readback userId=\(writtenUserId) householdId=\(writtenHouseholdId)")
    }

    private func persistHousehold(id: String, name: String) {
        let defaults = UserDefaults.standard
        defaults.set(id, forKey: Keys.householdId)
        defaults.set(name, forKey: Keys.householdName)
        KeychainService.save(id, forKey: Keys.householdId)
        KeychainService.save(name, forKey: Keys.householdName)
    }

    private func clearPersistedHousehold() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.householdId)
        defaults.removeObject(forKey: Keys.householdName)
        KeychainService.delete(forKey: Keys.householdId)
        KeychainService.delete(forKey: Keys.householdName)
    }

    private func clearPersistedSession() {
        // Hero i onboarding asystenta są per konto, nie per telefon: kolejny
        // użytkownik (albo ten sam po usunięciu konta) ma je zobaczyć od nowa.
        AssistantIntroState.reset()
        ConsentStore.clearCache()
        // Odłożone zaproszenie należy do osoby, która je otworzyła — następna
        // zalogowana dostawała alert z cudzym domem i mogła do niego dołączyć.
        storedInvitationToken = nil
        // Cały Keychain aplikacji, nie sześć kluczy z nazwiska. Lista wpisów
        // do skasowania musiała być pilnowana ręcznie i pierwszy nowy klucz
        // zapisany przy logowaniu zostawał na telefonie po wylogowaniu —
        // czyli dokładnie to, czego art. 17 zabrania.
        KeychainService.deleteAll()

        // Usuń dane sesji z UserDefaults
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.userId)
        defaults.removeObject(forKey: Keys.householdId)
        defaults.removeObject(forKey: Keys.householdName)
        defaults.removeObject(forKey: Keys.appleUserIdentifier)
        defaults.removeObject(forKey: Keys.avatarUrl)
        defaults.removeObject(forKey: Keys.avatarColor)
        defaults.removeObject(forKey: Keys.displayName)
        defaults.removeObject(forKey: Keys.email)
        defaults.removeObject(forKey: Keys.onboardingCompletedAt)
        // Przewodnik „Poznaj aplikację" należy do konta, nie do telefonu:
        // bez tej linii kolejna osoba logująca się na tym urządzeniu
        // wpadałaby prosto w pytania o wzrost i alergeny, bo flaga
        // z poprzedniej sesji nadal leżałaby w `UserDefaults`.
        defaults.removeObject(forKey: TourCompletion.storageKey)
        clearPersistedProfileFields()
        clearPersistedPreferences()
        clearPersistedHealthIntegration()
        onboardingCompletedAt = nil
    }

    /// Integracja „Zdrowie" jest per konto: bez tego kolejna osoba zalogowana
    /// na tym telefonie odziedziczyłaby włączoną flagę i pierwszy sync
    /// wysłałby kroki poprzedniego użytkownika na jej konto.
    private func clearPersistedHealthIntegration() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: HealthStepsStore.Keys.enabled)
        defaults.removeObject(forKey: HealthStepsStore.Keys.source)
        defaults.removeObject(forKey: HealthStepsStore.Keys.enabledAt)
        defaults.removeObject(forKey: HealthStepsStore.Keys.stepsGoal)
    }

    /// Wipe diet / kcal / allergens / goal / activityLevel AppStorage so
    /// the welcome flow starts from clean defaults on the next sign-in.
    /// Without this a previous user's selections leak into the new
    /// session's welcome step 3 (radio dot pre-checked, allergen chips
    /// already filled).
    private func clearPersistedPreferences() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: PreferencesKeys.diet)
        defaults.removeObject(forKey: PreferencesKeys.calorieGoal)
        defaults.removeObject(forKey: PreferencesKeys.allergens)
        defaults.removeObject(forKey: PreferencesKeys.goal)
        defaults.removeObject(forKey: PreferencesKeys.activityLevel)
        defaults.removeObject(forKey: PreferencesKeys.proteinG)
        defaults.removeObject(forKey: PreferencesKeys.fatG)
        defaults.removeObject(forKey: PreferencesKeys.carbsG)
        // Posiłki i ich pory należą do GOSPODARSTWA, nie do telefonu.
        // Zostawione, wchodziły kolejnej osobie logującej się na tym
        // urządzeniu jako jej własne — a od kroku „Ile posiłków jecie?"
        // w kreatorze widać to wprost: podwieczorek zaznaczony przez
        // poprzedni dom czekałby już odhaczony.
        defaults.removeObject(forKey: MealSlotConfiguration.Keys.enabledSlots)
        defaults.removeObject(forKey: MealSlotSchedule.Keys.times)
    }

    private func restoredSessionSnapshot() -> PersistedSessionSnapshot? {
        let userId = persistedValue(forKey: Keys.userId) ?? userIdFromAccessToken()
        guard let userId else { return nil }

        return PersistedSessionSnapshot(
            userId: userId,
            householdId: persistedValue(forKey: Keys.householdId),
            householdName: persistedValue(forKey: Keys.householdName)
        )
    }

    private func syncPersistedSessionSnapshot(_ snapshot: PersistedSessionSnapshot) {
        let defaults = UserDefaults.standard
        defaults.set(snapshot.userId, forKey: Keys.userId)
        KeychainService.save(snapshot.userId, forKey: Keys.userId)

        if let householdId = snapshot.householdId {
            defaults.set(householdId, forKey: Keys.householdId)
            KeychainService.save(householdId, forKey: Keys.householdId)
        }
        if let householdName = snapshot.householdName {
            defaults.set(householdName, forKey: Keys.householdName)
            KeychainService.save(householdName, forKey: Keys.householdName)
        }
    }

    private func persistedValue(forKey key: String) -> String? {
        normalizedValue(UserDefaults.standard.string(forKey: key))
            ?? normalizedValue(KeychainService.get(forKey: key))
    }

    private func normalizedValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    // MARK: - Smart startup loader

    /// Jedno wejście dla warmupu po logowaniu / restore sesji.
    /// Idempotent — dla ciepłego startu i tak szybko wchodzi w `.ready`
    /// (cache przepisów, cache dysku obrazów, snapshot domowników).
    @MainActor
    func runStartupIfNeeded(force: Bool = false) async {
        guard isAuthenticated else {
            startupPhase = .idle
            return
        }
        guard let householdId = currentHouseholdId, !householdId.isEmpty else {
            // Brak householdu → UI pokazuje loader (jeśli restoreSession trwa)
            // lub NoHouseholdView. Warmup nie ma co przygotowywać.
            startupPhase = .idle
            return
        }
        if !force, startupPhase == .ready { return }

        startupTask?.cancel()
        let minimumDisplay = startupMinimumDisplaySeconds
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.startupPhase = .warmingUp
            let startedAt = Date()
            await self.runStartupWithTimeout()
            // Anulowany warmup (bootstrap nowego gospodarstwa w trakcie) nie
            // decyduje o fazie — nowy task sam przejdzie warmingUp → ready.
            guard !Task.isCancelled else { return }
            // Minimum display — jeśli warmup poszedł z cache w <2 s, dotrzymujemy
            // loaderowi 2 s, żeby przejście Auth/Loader/Dashboard było płynne a nie migotało.
            let elapsed = Date().timeIntervalSince(startedAt)
            if elapsed < minimumDisplay {
                let remaining = minimumDisplay - elapsed
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            // Nawet jeśli któryś krok się nie udał (offline / timeout),
            // wchodzimy w .ready — dashboard ma własne skeletony / cache.
            self.startupPhase = .ready
        }
        startupTask = task
        await task.value
    }

    private func runStartupWithTimeout() async {
        let timeoutSeconds = startupTimeoutSeconds
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                await self?.prepareStartupData()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    private func prepareStartupData() async {
        // Krytyczne pod pierwsze wejście — odpalamy równolegle.
        // Każdy krok jest bezpieczny wobec braku sieci (korzysta z cache /
        // ustawia errorMessage w storze zamiast rzucać).
        async let recipesReady: Void = prepareRecipesAndThumbnails()
        async let householdReady: Void = prepareHouseholdMembersSnapshot()
        _ = await (recipesReady, householdReady)
    }

    private func prepareRecipesAndThumbnails() async {
        guard let catalog = recipeCatalogStore else { return }
        await catalog.loadIfNeeded()
        let urls = Array(catalog.recipes.prefix(startupImagePrefetchCount).compactMap(\.imageURL))
        await ImagePrefetcher.prefetchAwaiting(urls)
    }

    private func prepareHouseholdMembersSnapshot() async {
        // Jeśli mamy świeży snapshot z cache albo już pobrany po realtime,
        // nie robimy drugiego round-tripa na starcie.
        if didLoadHouseholdMembers, !householdMembers.isEmpty {
            return
        }
        await refreshHouseholdMembers(force: false)
    }

    // MARK: - Household members snapshot

    @MainActor
    func refreshHouseholdMembers(force: Bool = false) async {
        guard let userId = currentUserId, !userId.isEmpty,
              let householdId = currentHouseholdId, !householdId.isEmpty else {
            householdMembers = []
            didLoadHouseholdMembers = false
            return
        }
        if !force, isLoadingHouseholdMembers { return }
        // Świeżość, a nie samo „już coś mam". Poprzedni warunek zamykał drogę
        // do serwera na zawsze, gdy tylko lista raz się pojawiła — także wtedy,
        // gdy pochodziła z pliku cache sprzed doby.
        if !force, didLoadHouseholdMembers, !householdMembers.isEmpty,
           let loadedAt = householdMembersLoadedAt,
           Date().timeIntervalSince(loadedAt) < householdMembersFreshness {
            return
        }

        householdMembersTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isLoadingHouseholdMembers = true
            defer { self.isLoadingHouseholdMembers = false }
            do {
                // Ten sam socket, którym chodzi cała reszta aplikacji.
                // Osobne połączenie na każde odświeżenie oznaczało pełny
                // handshake (i do 3 s czekania) na jedynej ścieżce, która
                // dowoziła nowego domownika — a przy zdalnym serwerze to
                // czekanie potrafiło się nie zmieścić i pobranie cicho padało.
                let socketClient = self.sessionSocket()
                let envelope: WsEnvelope<[BackendHouseholdMemberDTO]> = try await socketClient.emitWithAck(
                    event: "households:listMembers",
                    payload: [
                        "userId": userId,
                        "householdId": householdId
                    ],
                    as: WsEnvelope<[BackendHouseholdMemberDTO]>.self
                )

                guard envelope.ok, let data = envelope.data else {
                    if !self.didLoadHouseholdMembers {
                        self.authError = UserFacingErrorMapper.message(
                            from: envelope.failure(fallback: "Nie udało się pobrać domowników.")
                        )
                    }
                    return
                }

                let snapshots = data.map(HouseholdMemberSnapshot.init(backend:))
                self.applyHouseholdMembers(snapshots, householdId: householdId)
            } catch is CancellationError {
                return
            } catch {
                // Offline / błąd sieci — zostawiamy to, co już mamy (cache / poprzedni pull).
                if !self.didLoadHouseholdMembers, self.householdMembers.isEmpty {
                    self.authError = UserFacingErrorMapper.inlineMessage(from: error)
                }
            }
        }
        householdMembersTask = task
        await task.value
    }

    /// Wyszukiwarka składników — ta sama, z której korzysta asystent.
    ///
    /// Handler `ingredients:search` istniał na serwerze od Fazy 1, ale żaden
    /// ekran go nie wołał: składniki wybierał wyłącznie model. Ekran „czego
    /// nie jem" potrzebuje dokładnie tego samego, bo wykluczenia trzymamy
    /// jako IDENTYFIKATORY — wpisana z ręki nazwa nie miałaby jak trafić
    /// w skład przepisu.
    func searchIngredients(query: String, limit: Int = 20) async -> [BackendIngredientHitDTO] {
        guard let userId = currentUserId, !userId.isEmpty else { return [] }
        do {
            let socketClient = sessionSocket()
            let envelope: WsEnvelope<[BackendIngredientHitDTO]> = try await socketClient.emitWithAck(
                event: "ingredients:search",
                payload: [
                    "userId": userId,
                    "filters": ["query": query, "limit": limit],
                ],
                as: WsEnvelope<[BackendIngredientHitDTO]>.self
            )
            guard envelope.ok, let data = envelope.data else { return [] }
            return data
        } catch {
            // Cicho: lista pokaże „nic nie znaleziono", a użytkownik spróbuje
            // jeszcze raz. To ekran ustawień, nie ścieżka krytyczna.
            return []
        }
    }

    // MARK: - User preferences (diet, kcal, allergens)
    //
    // Source of truth lives in `@AppStorage` so SwiftUI views read it
    // synchronously. SessionStore mirrors writes to the backend so the row
    // persists across devices and powers other views (e.g. Calendar's kcal
    // target). On first session bootstrap, we pull the row from the server
    // and seed local storage — overwriting the AppStorage defaults.

    private enum PreferencesKeys {
        static let diet = "settings.diet.preference"
        static let calorieGoal = "settings.diet.calorieGoal"
        static let allergens = "settings.diet.allergens"
        static let goal = "settings.diet.goal"
        static let activityLevel = "settings.diet.activityLevel"
        static let proteinG = "settings.diet.proteinG"
        static let fatG = "settings.diet.fatG"
        static let carbsG = "settings.diet.carbsG"
        /// Identyfikatory składników po przecinku — tak samo jak alergeny.
        static let excludedIngredients = "settings.diet.excludedIngredients"
        /// 0 = bez ograniczenia (AppStorage nie ma `nil` dla `Int`).
        static let maxPrepTimeMinutes = "settings.diet.maxPrepTimeMinutes"
    }

    /// Klucze przełączników z ekranu „Powiadomienia". Te same stringi czyta
    /// `SettingsView` przez `@AppStorage` i `PlanChangeNotificationService`.
    enum NotificationKeys {
        static let enabled = "settings.notifications.enabled"
        static let plan = "settings.notifications.planReminders"
        static let shopping = "settings.notifications.shoppingReminders"
    }

    private enum ProfileKeys {
        static let yearOfBirth = "settings.profile.yearOfBirth"
        static let heightCm = "settings.profile.heightCm"
        static let weightKg = "settings.profile.weightKg"
        static let sex = "settings.profile.sex"
    }

    private func persistProfileFields(
        yearOfBirth: Int?,
        heightCm: Int?,
        weightKg: Double?,
        sex: String?
    ) {
        let defaults = UserDefaults.standard
        if let yearOfBirth { defaults.set(yearOfBirth, forKey: ProfileKeys.yearOfBirth) }
        if let heightCm { defaults.set(heightCm, forKey: ProfileKeys.heightCm) }
        if let weightKg { defaults.set(weightKg, forKey: ProfileKeys.weightKg) }
        // Backend oddaje `MALE` / `FEMALE`, iOS trzyma małymi literami —
        // ta sama konwencja co przy diecie i celu.
        if let sex { defaults.set(sex.lowercased(), forKey: ProfileKeys.sex) }
    }

    private func clearPersistedProfileFields() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: ProfileKeys.yearOfBirth)
        defaults.removeObject(forKey: ProfileKeys.heightCm)
        defaults.removeObject(forKey: ProfileKeys.weightKg)
        defaults.removeObject(forKey: ProfileKeys.sex)
    }

    /// Pull the user's preferences row from the backend and write into
    /// AppStorage. Silent on failure — local cache stays as fallback so
    /// the UI keeps working offline.
    @MainActor
    func loadUserPreferences() async {
        guard let userId = currentUserId, !userId.isEmpty else { return }
        let socket = sessionSocket()

        do {
            let envelope: WsEnvelope<BackendUserPreferencesDTO> = try await socket.emitWithAck(
                event: "users:preferences:get",
                payload: ["userId": userId],
                as: WsEnvelope<BackendUserPreferencesDTO>.self
            )
            guard envelope.ok, let prefs = envelope.data else { return }

            let defaults = UserDefaults.standard
            // Przez `backendValue`, nie przez `lowercased()` — patrz komentarz
            // przy `DietPreference.backendValue`.
            if let diet = DietPreference(backendValue: prefs.dietPreference) {
                defaults.set(diet.rawValue, forKey: PreferencesKeys.diet)
            }
            defaults.set(prefs.calorieGoal, forKey: PreferencesKeys.calorieGoal)
            defaults.set(
                prefs.allergens
                    .map { $0.lowercased() }
                    .sorted()
                    .joined(separator: ","),
                forKey: PreferencesKeys.allergens
            )
            defaults.set(prefs.goal.lowercased(), forKey: PreferencesKeys.goal)
            defaults.set(prefs.activityLevel, forKey: PreferencesKeys.activityLevel)
            // −1 to sentinel „licz za mnie" po stronie iOS; backend trzyma
            // tam `null`. Tłumaczenie w obie strony siedzi wyłącznie tutaj.
            defaults.set(prefs.proteinG ?? -1, forKey: PreferencesKeys.proteinG)
            defaults.set(prefs.fatG ?? -1, forKey: PreferencesKeys.fatG)
            defaults.set(prefs.carbsG ?? -1, forKey: PreferencesKeys.carbsG)

            // Ograniczenia bywają ustawione też z rozmowy z asystentem, więc
            // serwer jest tu źródłem prawdy. `nil` znaczy „backend sprzed tej
            // zmiany" — wtedy nie ruszamy tego, co użytkownik ma lokalnie.
            if let excluded = prefs.excludedIngredientIds {
                defaults.set(
                    excluded.sorted().joined(separator: ","),
                    forKey: PreferencesKeys.excludedIngredients
                )
            }
            // 0 = brak ograniczenia; AppStorage nie ma `nil` dla `Int`.
            defaults.set(
                prefs.maxPrepTimeMinutes ?? 0,
                forKey: PreferencesKeys.maxPrepTimeMinutes
            )

            // Przełączniki powiadomień są teraz danymi konta, nie ustawieniem
            // urządzenia: to serwer decyduje, czy wysłać pusha, więc to on
            // trzyma prawdę. Backend sprzed tej zmiany przysyła `nil`
            // i wtedy nie ruszamy tego, co użytkownik ustawił lokalnie.
            if let planPush = prefs.pushPlanChanges {
                defaults.set(planPush, forKey: NotificationKeys.plan)
            }
            if let shoppingPush = prefs.pushShoppingList {
                defaults.set(shoppingPush, forKey: NotificationKeys.shopping)
            }
            // `pushHousehold` i `pushQuietHours` celowo nie mają lustra w
            // ustawieniach: gospodarstwo powiadamia zawsze (steruje nim tylko
            // główny przełącznik), a cisza nocna jest zachowaniem aplikacji,
            // nie preferencją. Kolumny w bazie zostają — `syncNotification-
            // Preferences` trzyma je w ryzach przy każdym starcie sesji.
        } catch {
            // Swallow — preferences are non-critical, AppStorage default
            // applies. Will retry on the next session bootstrap.
        }
    }

    /// Push the supplied preferences slice to the backend. Pass only the
    /// fields you want to change — the backend merges with the existing
    /// row. Allergens, when supplied, replace the full set — dlatego callerzy
    /// MUSZĄ wysyłać sumę „znane ∪ nieznane" (`SettingsView.allergensPayload`,
    /// `WelcomeView.unknownAllergens`). Wysłanie samych rozpoznanych wartości
    /// kasuje z konta alergen ustawiony na nowszej wersji aplikacji.
    /// Serwer odrzuca id spoza `src/common/allergens.ts` całym payloadem
    /// (`code: "VALIDATION_ERROR"`), więc nowa wartość enuma musi najpierw
    /// wyjść na backend.
    @MainActor
    @discardableResult
    func saveUserPreferences(
        diet: String? = nil,
        calorieGoal: Int? = nil,
        allergens: [String]? = nil,
        goal: String? = nil,
        activityLevel: Int? = nil,
        proteinG: Int? = nil,
        fatG: Int? = nil,
        carbsG: Int? = nil,
        /// Czego domownik nie je. Pusta tablica kasuje wykluczenia.
        excludedIngredientIds: [String]? = nil,
        /// Maksymalny czas gotowania; `clearMaxPrepTime` kasuje ograniczenie.
        maxPrepTimeMinutes: Int? = nil,
        clearMaxPrepTime: Bool = false,
        /// Wysyła jawne `null` na wszystkie trzy makra — czyli „przestań
        /// trzymać moje wartości i licz za mnie". Bez tego nie dałoby się
        /// wrócić do automatu, bo `nil` w parametrze znaczy „nie ruszaj".
        clearMacroOverrides: Bool = false
    ) async -> Bool {
        guard let userId = currentUserId, !userId.isEmpty else { return false }

        // Mirror to AppStorage so the welcome flow survives a kill-restart
        // mid-flow and SettingsView reads the latest values without a
        // round-trip. Settings already drives @AppStorage directly, so
        // writing the same keys here is idempotent.
        let defaults = UserDefaults.standard
        var data: [String: Any] = [:]
        if let diet, let preference = DietPreference(rawValue: diet) {
            data["dietPreference"] = preference.backendValue
            defaults.set(preference.rawValue, forKey: PreferencesKeys.diet)
        }
        if let calorieGoal {
            data["calorieGoal"] = calorieGoal
            defaults.set(calorieGoal, forKey: PreferencesKeys.calorieGoal)
        }
        if let allergens {
            // Dedupe i trim tutaj, bo DTO ma `@ArrayUnique` tylko na ścieżce
            // HTTP — po WebSockecie nic nie pilnuje, a „gluten,gluten" w
            // AppStorage psułoby liczniki chipów.
            let normalised = Array(Set(
                allergens
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty }
            )).sorted()
            data["allergens"] = normalised
            defaults.set(
                normalised.joined(separator: ","),
                forKey: PreferencesKeys.allergens
            )
        }
        if let excludedIngredientIds {
            let normalised = Array(Set(excludedIngredientIds)).sorted()
            data["excludedIngredientIds"] = normalised
            defaults.set(
                normalised.joined(separator: ","),
                forKey: PreferencesKeys.excludedIngredients
            )
        }
        if clearMaxPrepTime {
            // Jawny `null`, nie pominięte pole: pominięcie znaczy „nie ruszaj",
            // więc bez tego nie dałoby się skasować ograniczenia.
            data["maxPrepTimeMinutes"] = NSNull()
            defaults.set(0, forKey: PreferencesKeys.maxPrepTimeMinutes)
        } else if let maxPrepTimeMinutes {
            data["maxPrepTimeMinutes"] = maxPrepTimeMinutes
            defaults.set(maxPrepTimeMinutes, forKey: PreferencesKeys.maxPrepTimeMinutes)
        }
        if let goal {
            data["goal"] = goal.uppercased()
            defaults.set(goal.lowercased(), forKey: PreferencesKeys.goal)
        }
        if let activityLevel {
            data["activityLevel"] = activityLevel
            defaults.set(activityLevel, forKey: PreferencesKeys.activityLevel)
        }
        if clearMacroOverrides {
            data["proteinG"] = NSNull()
            data["fatG"] = NSNull()
            data["carbsG"] = NSNull()
            defaults.set(-1, forKey: PreferencesKeys.proteinG)
            defaults.set(-1, forKey: PreferencesKeys.fatG)
            defaults.set(-1, forKey: PreferencesKeys.carbsG)
        } else {
            if let proteinG {
                data["proteinG"] = proteinG
                defaults.set(proteinG, forKey: PreferencesKeys.proteinG)
            }
            if let fatG {
                data["fatG"] = fatG
                defaults.set(fatG, forKey: PreferencesKeys.fatG)
            }
            if let carbsG {
                data["carbsG"] = carbsG
                defaults.set(carbsG, forKey: PreferencesKeys.carbsG)
            }
        }
        guard !data.isEmpty else { return true }

        let socket = sessionSocket()

        do {
            let envelope: WsEnvelope<BackendUserPreferencesDTO> = try await socket.emitWithAck(
                event: "users:preferences:update",
                payload: ["userId": userId, "data": data],
                as: WsEnvelope<BackendUserPreferencesDTO>.self
            )
            // Odrzucenie (np. `VALIDATION_ERROR` na nieznanym alergenie) też
            // dekoduje się poprawnie — bez tego logu wyglądało jak udany zapis,
            // a AppStorage trzymał wartość, której serwer nie przyjął.
            if !envelope.ok {
                #if DEBUG
                print("[SessionStore] users:preferences:update odrzucone: \(envelope.code ?? "?") \(envelope.error ?? "") requestId=\(envelope.requestId ?? "-")")
                #endif
            }
            return envelope.ok
        } catch {
            // AppStorage jest już zaktualizowany optymistycznie; wynik mówi
            // wywołującemu (kreator), że serwer tego jeszcze nie ma.
            return false
        }
    }

    /// Wysyła na backend stan przełączników powiadomień.
    ///
    /// Musi istnieć, bo od tej zmiany to serwer decyduje, czy wysłać pusha.
    /// Wcześniej przełączniki żyły wyłącznie w `UserDefaults` i wyciszały
    /// jedynie powiadomienia rysowane lokalnie — wyłączenie „Powiadomień"
    /// w Ustawieniach nie zatrzymywało niczego, co przychodziło z zewnątrz,
    /// więc z perspektywy użytkownika ten przełącznik był popsuty.
    ///
    /// Główny przełącznik wyłącza wszystkie kanały naraz: serwer nie ma
    /// osobnego pola „wszystko", a trzy `false` znaczą dokładnie to samo
    /// i nie wymagają kolejnej kolumny.
    ///
    /// Dwa pola idą na sztywno. `pushHousehold` podąża wyłącznie za głównym
    /// przełącznikiem — dołączenie domownika jest zbyt rzadkie i zbyt ważne,
    /// żeby dało się je wyciszyć osobno. `pushQuietHours` jest zawsze `true`:
    /// cisza nocna to zachowanie aplikacji, nie preferencja, a wysyłanie tu
    /// stałej pilnuje też baz, w których ktoś zdążył przestawić kolumnę,
    /// zanim przełącznik zniknął z ekranu.
    @MainActor
    func syncNotificationPreferences() async {
        guard let userId = currentUserId, !userId.isEmpty else { return }
        let defaults = UserDefaults.standard

        func flag(_ key: String) -> Bool {
            if defaults.object(forKey: key) == nil { return true }
            return defaults.bool(forKey: key)
        }

        let master = flag(NotificationKeys.enabled)
        let data: [String: Any] = [
            "pushPlanChanges": master && flag(NotificationKeys.plan),
            "pushShoppingList": master && flag(NotificationKeys.shopping),
            "pushHousehold": master,
            "pushQuietHours": true,
            // Strefa z telefonu — bez niej cisza nocna liczyłaby się w strefie
            // kontenera, czyli zwykle w UTC.
            "timeZone": TimeZone.current.identifier,
        ]

        let socket = sessionSocket()
        do {
            let _: WsEnvelope<BackendUserPreferencesDTO> = try await socket.emitWithAck(
                event: "users:preferences:update",
                payload: ["userId": userId, "data": data],
                as: WsEnvelope<BackendUserPreferencesDTO>.self
            )
        } catch {
            // Przełączniki działają lokalnie od razu; ponowimy przy następnej
            // zmianie albo przy starcie sesji.
        }
    }

    // MARK: - Welcome flow (first login)
    //
    // Called from the four welcome steps. Each step persists optimistically
    // (UserDefaults / AppStorage) so the UI shows the saved values even if
    // the user kills the app mid-flow; the matching backend round-trip runs
    // afterwards. Network failures are swallowed — the welcome flow degrades
    // gracefully and we'll re-sync on next launch via `users:me`.

    /// Persist the profile slice (display name + biometrics) for the
    /// welcome flow's step 1. Updates AppStorage immediately, then mirrors
    /// to the backend via `users:profile:update`.
    @discardableResult
    @MainActor
    func saveProfile(
        displayName: String? = nil,
        yearOfBirth: Int? = nil,
        heightCm: Int? = nil,
        weightKg: Double? = nil,
        sex: String? = nil
    ) async -> Bool {
        guard let userId = currentUserId, !userId.isEmpty else { return false }

        var data: [String: Any] = [:]
        if let displayName {
            let trimmed = String(
                displayName
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(Self.displayNameMaxLength)
            )
            if !trimmed.isEmpty {
                data["displayName"] = trimmed
                UserDefaults.standard.set(trimmed, forKey: Keys.displayName)
            }
        }
        if let yearOfBirth {
            data["yearOfBirth"] = yearOfBirth
            UserDefaults.standard.set(yearOfBirth, forKey: ProfileKeys.yearOfBirth)
        }
        if let heightCm {
            data["heightCm"] = heightCm
            UserDefaults.standard.set(heightCm, forKey: ProfileKeys.heightCm)
        }
        if let weightKg {
            // Jedno miejsce po przecinku — tyle waliduje backend i tyle
            // pokazuje pole. Bez tego 83.30000000000001 z arytmetyki Double
            // wywracałoby walidację `maxDecimalPlaces: 1`.
            let rounded = (weightKg * 10).rounded() / 10
            data["weightKg"] = rounded
            UserDefaults.standard.set(rounded, forKey: ProfileKeys.weightKg)
        }
        if let sex, !sex.isEmpty {
            data["sex"] = sex.uppercased()
            UserDefaults.standard.set(sex.lowercased(), forKey: ProfileKeys.sex)
        }
        guard !data.isEmpty else { return true }

        let socket = sessionSocket()

        do {
            let envelope: WsEnvelope<BackendUserProfileDTO> = try await socket.emitWithAck(
                event: "users:profile:update",
                payload: ["userId": userId, "data": data],
                as: WsEnvelope<BackendUserProfileDTO>.self
            )
            return envelope.ok
        } catch {
            // AppStorage jest już zaktualizowany optymistycznie; kreator
            // pokaże ostrzeżenie i ponowi przy następnym „Dalej".
            return false
        }
    }

    /// Mark the welcome flow as complete on the backend. iOS optimistically
    /// updates `onboardingCompletedAt` so the dashboard becomes available
    /// immediately, then issues the round-trip in the background.
    @MainActor
    func completeOnboarding() async {
        guard let userId = currentUserId, !userId.isEmpty else { return }

        let now = Date()
        let nowIso = Self.onboardingDateFormatter.string(from: now)
        persistOnboardingCompletedAt(nowIso)

        let socket = sessionSocket()

        do {
            let envelope: WsEnvelope<BackendUserProfileDTO> = try await socket.emitWithAck(
                event: "users:onboarding:complete",
                payload: ["userId": userId],
                as: WsEnvelope<BackendUserProfileDTO>.self
            )
            if envelope.ok, let profile = envelope.data {
                persistOnboardingCompletedAt(profile.onboardingCompletedAt)
                // To TUTAJ backend przydziela kolor awatara — bez zapisania
                // go od razu świeży użytkownik do następnego `users:me`
                // oglądał swój profil w kolorze z hasza, a domownicy widzieli
                // go już w przydzielonym.
                if let avatarColor = profile.avatarColor {
                    UserDefaults.standard.set(avatarColor, forKey: Keys.avatarColor)
                }
            }
        } catch {
            // Optimistic flag is already set; backend will re-confirm on
            // the next `users:me`. If the device crashes before the round
            // trip lands, the worst case is the welcome flow re-shows
            // until the network succeeds.
        }
    }

    private var householdMembersCacheURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("household_members_cache_v1.json")
    }

    private func loadHouseholdMembersFromCacheIfFresh(for householdId: String) {
        guard let data = try? Data(contentsOf: householdMembersCacheURL) else { return }
        guard let payload = try? JSONDecoder().decode(HouseholdMembersCachePayload.self, from: data) else { return }
        guard payload.householdId == householdId else { return }
        guard Date().timeIntervalSince(payload.savedAt) <= householdMembersCacheMaxAge else { return }
        householdMembers = payload.members
        didLoadHouseholdMembers = !payload.members.isEmpty
        syncOwnAvatarColor(from: payload.members)
        // ŚWIADOMIE bez `householdMembersLoadedAt`: plik cache daje pierwszą
        // klatkę, a nie potwierdzenie aktualności. Zapisany tu znacznik czasu
        // udawałby świeże pobranie i blokował pytanie serwera przez kolejną
        // dobę — czyli dokładnie to, przez co skład gospodarstwa zastygał.
    }

    private func saveHouseholdMembersCache(householdId: String, members: [HouseholdMemberSnapshot]) {
        let payload = HouseholdMembersCachePayload(householdId: householdId, members: members, savedAt: Date())
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: householdMembersCacheURL, options: .atomic)
    }

    private func clearHouseholdMembersCache() {
        try? FileManager.default.removeItem(at: householdMembersCacheURL)
    }

    /// Claimy z access tokenu (bez weryfikacji podpisu — to robi serwer).
    private func accessTokenClaims() -> [String: Any]? {
        guard let token = currentAccessToken else { return nil }
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload.append(String(repeating: "=", count: 4 - remainder))
        }

        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func userIdFromAccessToken() -> String? {
        guard let claims = accessTokenClaims(),
              let userId = normalizedValue(claims["sub"] as? String) else {
            return nil
        }

        debugLog("[SessionStore] restoreSession recovered userId from access token")
        return userId
    }

    /// `exp` z access tokenu; `nil`, gdy tokenu nie ma albo nie niesie `exp`.
    private func accessTokenExpiry() -> Date? {
        guard let claims = accessTokenClaims() else { return nil }
        if let exp = claims["exp"] as? TimeInterval {
            return Date(timeIntervalSince1970: exp)
        }
        if let exp = claims["exp"] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(exp))
        }
        return nil
    }

    // MARK: - Socket sesji i odświeżanie tokenu

    /// Jeden socket sesji z tokenem w handshake, tworzony leniwie — także
    /// PRZED gospodarstwem (Welcome), bo od Fazy 0 każdy event wymaga
    /// tożsamości. Dawniej pięć miejsc otwierało własne, anonimowe połączenia.
    private func sessionSocket() -> RecipeSocketClient {
        if let realtimeSocket { return realtimeSocket }
        let socket = makeSessionSocket()
        realtimeSocket = socket
        return socket
    }

    /// Nowy socket sesji zamiast obecnego (bootstrap po logowaniu / zmianie
    /// domu) — stary zamykamy na dobre tą samą ścieżką co przy wylogowaniu,
    /// żeby nie dublował obserwatorów ani handlerów `households:*`.
    private func replaceSessionSocket() -> RecipeSocketClient {
        tearDownSessionSocket()
        let socket = makeSessionSocket()
        realtimeSocket = socket
        return socket
    }

    private func makeSessionSocket() -> RecipeSocketClient {
        let socket = SocketIORecipeSocketClient(
            baseURL: baseURL,
            tokenProvider: { [weak self] in self?.currentAccessToken }
        )
        socket.observeAuthFailure { [weak self] reason in
            Task { @MainActor [weak self] in
                await self?.handleSocketAuthFailure(reason: reason)
            }
        }
        // Udane połączenie zamyka ewentualną serię odmów.
        socket.observeConnection { [weak self] isConnected in
            guard isConnected else { return }
            Task { @MainActor [weak self] in
                self?.socketAuthRetryCount = 0
            }
        }
        return socket
    }

    private func tearDownSessionSocket() {
        socketAuthRetryTask?.cancel()
        socketAuthRetryTask = nil
        socketAuthRetryCount = 0
        realtimeSocket?.off(event: "households:membersChanged")
        realtimeSocket?.off(event: "households:mealTypesChanged")
        realtimeSocket?.off(event: "households:mealTimesChanged")
        realtimeSocket?.disconnect()
        realtimeSocket = nil
    }

    enum SessionRefreshOutcome: Equatable {
        /// Nowa para tokenów w Keychain.
        case refreshed
        /// Serwer odrzucił refresh token albo w Keychain nie ma go wcale —
        /// sesja nie do uratowania bez ponownego logowania.
        case rejected
        /// Brak sieci / błąd serwera — sesja zostaje, spróbujemy później.
        case unavailable
    }

    private var refreshTask: Task<SessionRefreshOutcome, Never>?
    /// Każde wejście na pierwszy plan odświeża parę tokenów: okno jest
    /// szersze niż życie access tokenu (godzina), więc warunek zawsze
    /// wypada na „tak". Zostaje jako bezpiecznik, gdyby serwer zaczął
    /// wydawać tokeny na dłużej.
    private static let proactiveRefreshWindow: TimeInterval = 7 * 24 * 3600
    /// Odświeżenie NIE czeka na wygaśnięcie. Access token żyje godzinę, a
    /// sesja spędzona w całości na pierwszym planie (gotowanie z listą
    /// zakupów, rozmowa z asystentem) nie ma foregroundu, który by ją
    /// odnowił — bez tego timera po godzinie przychodziło 401 i `auth:expired`
    /// z socketu w środku pracy. Sesja wracała sama, ale z mignięciem błędu.
    private var proactiveRefreshTimerTask: Task<Void, Never>?
    /// O ile przed `exp` uderzamy po nową parę.
    private static let proactiveRefreshLead: TimeInterval = 5 * 60
    /// Podłoga odstępu: token krótszy niż wyprzedzenie (albo już wygasły) nie
    /// może zamienić timera w pętlę odświeżeń.
    private static let minProactiveRefreshDelay: TimeInterval = 60
    /// Sesja czeka na dostępny Keychain (patrz `restoreSession`).
    private var restoreDeferredUntilKeychainAvailable = false
    /// Seria odmów socketu po udanych refreshach — hamulec na wypadek, gdy
    /// serwer odrzuca także świeże tokeny (rozjazd konfiguracji): backoff,
    /// a po `maxSocketAuthRetries` czekamy na następny foreground.
    private var socketAuthRetryCount = 0
    private var socketAuthRetryTask: Task<Void, Never>?
    private static let maxSocketAuthRetries = 5
    private static let sessionExpiredMessage = "Sesja wygasła. Zaloguj się ponownie."

    /// Jedna rotacja naraz. Równoległe 401 z REST i odmowa socketu nie mogą
    /// wysłać tego samego refresh tokenu dwa razy — drugi przebieg serwer
    /// uznałby za replay i unieważnił całą rodzinę tokenów.
    ///
    /// To jedyne miejsce, które decyduje o skutkach: `.rejected` kończy sesję,
    /// `.refreshed` podnosi socket (jeśli czekał po odmowie — zdrowy zostaje).
    @discardableResult
    func refreshSessionTokens() async -> SessionRefreshOutcome {
        if let refreshTask {
            // Czekający nie decydują — właściciel taska obsłuży wynik.
            return await refreshTask.value
        }
        let baseURL = self.baseURL
        let refreshToken = currentRefreshToken
        let task = Task<SessionRefreshOutcome, Never> {
            guard let refreshToken, !refreshToken.isEmpty else {
                // Brak refresh tokenu nie minie sam — bez ponownego logowania
                // sesji nie da się uratować.
                debugLog("[SessionStore] refreshSessionTokens — refresh token missing, session unrecoverable")
                return .rejected
            }
            let client = AuthAPIClient(baseURL: baseURL)
            do {
                let pair = try await client.refresh(refreshToken: refreshToken)
                // Wylogowanie / inne konto w trakcie żądania: nie wskrzeszaj
                // sesji zapisem nowej pary po `clearPersistedSession()`, a świeżo
                // wydany refresh token unieważnij (detached — ten Task może być
                // już anulowany, a URLSession odrzuciłby wtedy żądanie).
                guard !Task.isCancelled,
                      KeychainService.get(forKey: Keys.refreshToken) == refreshToken else {
                    Task.detached {
                        try? await client.logout(refreshToken: pair.refreshToken)
                    }
                    return .unavailable
                }
                KeychainService.save(pair.accessToken, forKey: Keys.accessToken)
                KeychainService.save(pair.refreshToken, forKey: Keys.refreshToken)
                return .refreshed
            } catch AuthAPIError.unauthorized {
                return .rejected
            } catch {
                return .unavailable
            }
        }
        refreshTask = task
        let outcome = await task.value
        // Nie zeruj nowszego taska założonego po logout()+relogin.
        if refreshTask == task { refreshTask = nil }
        switch outcome {
        case .refreshed:
            // Świeży token wchodzi tylko przez nowy pakiet CONNECT — klient
            // przepina socket, który czekał po odmowie; zdrowy zostawia.
            realtimeSocket?.reconnectWithFreshToken()
            if authError == Self.sessionExpiredMessage {
                authError = nil
            }
            armProactiveRefresh()
        case .rejected:
            handleSessionExpired()
        case .unavailable:
            // Offline / 5xx: sesja żyje dalej, więc termin musi zostać
            // uzbrojony — inaczej jedna chybiona próba zostawiałaby sesję bez
            // timera aż do następnego foregroundu. Wygasły token daje podłogę
            // (minuta), czyli ponowienie zamiast ciszy.
            armProactiveRefresh()
        }
        return outcome
    }

    private func refreshSessionTokensIfExpiringSoon() async {
        guard isAuthenticated || currentUserId != nil else { return }
        guard let expiry = accessTokenExpiry() else { return }
        guard expiry.timeIntervalSinceNow < Self.proactiveRefreshWindow else {
            armProactiveRefresh()
            return
        }
        await refreshSessionTokens()
    }

    /// Uzbraja jednorazowy termin na `exp - proactiveRefreshLead`. Każde
    /// wywołanie zastępuje poprzedni: świeża para = nowy termin. Wołane po
    /// zapisie tokenów (logowanie) i po każdym odświeżeniu, więc timer istnieje
    /// przez całe życie sesji, także bez ani jednego przejścia w tło.
    private func armProactiveRefresh() {
        proactiveRefreshTimerTask?.cancel()
        proactiveRefreshTimerTask = nil
        // Brak `exp` = brak tokenu w Keychain (albo token bez daty) — nie ma
        // czego pilnować.
        guard let expiry = accessTokenExpiry() else { return }
        let delay = max(
            expiry.timeIntervalSinceNow - Self.proactiveRefreshLead,
            Self.minProactiveRefreshDelay
        )
        proactiveRefreshTimerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            // `.refreshed` i `.unavailable` uzbrajają termin na nowo w
            // `refreshSessionTokens`; `.rejected` kończy sesję i timer ginie
            // razem z nią w `logout()`.
            await self.refreshSessionTokens()
        }
    }

    /// Serwer odrzucił socket (`connect_error UNAUTHORIZED` / `auth:expired`):
    /// odświeżamy tokeny — `refreshSessionTokens` sam podnosi socket albo
    /// kończy sesję. Seria odmów po udanych refreshach dostaje backoff
    /// (0, 2, 4, 8, 16 s) i limit; `.unavailable` (offline) zostawia socket
    /// do następnego foregroundu (`reconnectIfNeeded` robi jedną próbę).
    private func handleSocketAuthFailure(reason: String) async {
        debugLog("[SessionStore] socket auth failure reason=\(reason) retry=\(socketAuthRetryCount)")
        socketAuthRetryCount += 1
        guard socketAuthRetryCount <= Self.maxSocketAuthRetries else {
            debugLog("[SessionStore] socket auth failure loop — waiting for next foreground")
            return
        }
        if socketAuthRetryCount > 1 {
            let delay = UInt64(1 << (socketAuthRetryCount - 1)) * 1_000_000_000
            socketAuthRetryTask?.cancel()
            let waiter = Task<Void, Never> {
                try? await Task.sleep(nanoseconds: delay)
            }
            socketAuthRetryTask = waiter
            await waiter.value
            if waiter.isCancelled { return }
        }
        if await refreshSessionTokens() == .unavailable {
            // Offline / 5xx: socket czeka z flagą odmowy, więc bez ponowienia
            // każde żądanie kończyłoby się błędem łączności aż do foregroundu.
            // Ograniczone ponowienie tym samym licznikiem i backoffem.
            let delay = UInt64(1 << socketAuthRetryCount) * 1_000_000_000
            socketAuthRetryTask?.cancel()
            socketAuthRetryTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await self?.handleSocketAuthFailure(reason: reason)
            }
        }
    }

    private func handleSessionExpired() {
        guard isAuthenticated || currentUserId != nil else { return }
        logout()
        authError = Self.sessionExpiredMessage
    }
}
