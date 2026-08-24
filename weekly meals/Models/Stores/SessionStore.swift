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

    var weeklyMealStore: WeeklyMealStore?
    var recipeCatalogStore: RecipeCatalogStore?
    var shoppingListStore: ShoppingListStore?
    var datesViewModel = DatesViewModel()
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
    /// (wszystko z cache). Wartość zsynchronizowana z animacją kafelków
    /// w `StartupLoaderView`: niedziela (index 6) dopełnia się o
    /// `6 * 0.28 + 0.20 * 2.8 = 2.24 s` (stagger × index + ramp end %).
    /// Crossfade do dashboardu startuje dokładnie w momencie zakończenia
    /// wave'a — żaden kafelek się nie urywa przed zapełnieniem.
    private let startupMinimumDisplaySeconds: Double = 2.24

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
        weeklyMealStore?.refreshObservedState()
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
        } catch {
            authError = UserFacingErrorMapper.message(from: error)
            isAuthenticated = false
            clearRuntimeStores()
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
        guard let http = response as? HTTPURLResponse else {
            throw RecipeDataError.serverError(message: "Brak odpowiedzi HTTP z serwera.")
        }
        guard (200...299).contains(http.statusCode) else {
            let message = Self.decodeErrorMessage(data: data) ?? "Błąd logowania Apple (HTTP \(http.statusCode))."
            throw RecipeDataError.serverError(message: message)
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
    }

    private static func decodeErrorMessage(data: Data) -> String? {
        struct ErrorResponse: Codable { let message: String? }
        if let obj = try? JSONDecoder().decode(ErrorResponse.self, from: data), let msg = obj.message {
            return msg
        }
        return String(data: data, encoding: .utf8)
    }

    func logout() {
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

        let socket = realtimeSocket ?? SocketIORecipeSocketClient(baseURL: baseURL)

        do {
            let envelope: WsEnvelope<BackendDeletedUserDTO> = try await socket.emitWithAck(
                event: "users:delete",
                payload: ["userId": userId],
                as: WsEnvelope<BackendDeletedUserDTO>.self
            )

            guard envelope.ok else {
                authError = envelope.error ?? "Nie udało się usunąć konta. Spróbuj ponownie."
                return false
            }
        } catch {
            authError = UserFacingErrorMapper.message(from: error)
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
        NSLog(
            "[SessionStore] restoreSession userId=\(snapshot?.userId ?? "<nil>") householdId=\(snapshot?.householdId ?? "<nil>")"
        )
        guard let snapshot else {
            NSLog("[SessionStore] restoreSession EARLY RETURN — userId missing")
            return
        }

        syncPersistedSessionSnapshot(snapshot)
        currentUserId = snapshot.userId
        let householdId = snapshot.householdId
        let householdName = snapshot.householdName
        if let householdId, !householdId.isEmpty {
            bootstrapSession(
                userId: snapshot.userId,
                householdId: householdId,
                householdName: (householdName?.isEmpty == false ? householdName : nil)
            )
            // Podnosimy skopiowany z dysku snapshot domowników od razu — jeśli jest świeży,
            // sheet Gospodarstwo otworzy się bez pustego stanu nawet przy cold starcie.
            loadHouseholdMembersFromCacheIfFresh(for: householdId)
        } else {
            // Brak persisted householdu — musimy zapytać backend o membership.
            // Dopóki to nie zakończy się, trzymamy loader zamiast mignięcia NoHouseholdView.
            isRestoringSession = true
        }
        Task { [weak self] in
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
        let socketClient = SocketIORecipeSocketClient(baseURL: baseURL)
        self.realtimeSocket = socketClient

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

        self.weeklyMealStore = WeeklyMealStore(
            weeklyPlanRepository: ApiWeeklyPlanRepository(client: weeklyPlanTransport),
            currentUserId: userId
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

    private func clearRuntimeStores() {
        realtimeSocket?.off(event: "households:membersChanged")
        realtimeSocket?.off(event: "households:mealTypesChanged")
        realtimeSocket?.off(event: "households:mealTimesChanged")
        realtimeSocket = nil
        weeklyMealStore = nil
        recipeCatalogStore = nil
        shoppingListStore = nil
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

                // Dołączenie domownika ma być WIDOCZNE, a nie tylko odświeżone
                // po cichu na liście — o to prosił użytkownik, któremu ktoś
                // dołączył do gospodarstwa i nie dowiedział się o tym niczym.
                // Push wysyła backend; to jest kanał zapasowy na wypadek, gdyby
                // APNs nie działał (symulator, brak kluczy, odmowa uprawnień).
                if event.changedByUserId != nil, event.changedByUserId != self.currentUserId {
                    PlanChangeNotificationService.notifyHouseholdMembershipChange(
                        action: event.action,
                        householdId: currentHouseholdId,
                        changedByDisplayName: event.changedByDisplayName
                    )
                }

                // Nowy skład jedzie w ładunku, więc nie wracamy po niego na
                // serwer — dokładnie tak jak przy `mealTypesChanged`. Ten
                // dodatkowy round-trip był ostatnim miejscem, w którym
                // odświeżenie listy mogło po cichu przepaść.
                if let members = event.members {
                    self.applyHouseholdMembers(
                        members.map(HouseholdMemberSnapshot.init(backend:)),
                        householdId: currentHouseholdId
                    )
                    return
                }

                await self.refreshHouseholdMembers(force: true)
            }
        }

        // Rozgłoszenie po sockecie jest jednorazowe i nie ma powtórek: jeśli
        // aplikacja była w tle albo bez sieci, gdy ktoś dołączał, zdarzenie
        // przepada bezpowrotnie. Odzyskujemy je przy każdym (re)połączeniu —
        // ten sam wzorzec, którego używają już `WeeklyMealStore`
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

        let socket = realtimeSocket ?? SocketIORecipeSocketClient(baseURL: baseURL)
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

        let socket = realtimeSocket ?? SocketIORecipeSocketClient(baseURL: baseURL)
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

        let socket = realtimeSocket ?? SocketIORecipeSocketClient(baseURL: baseURL)
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

        isSigningIn = true
        authError = nil
        defer { isSigningIn = false }

        do {
            let socketClient = SocketIORecipeSocketClient(baseURL: baseURL)
            let envelope: WsEnvelope<BackendHouseholdDTO> = try await socketClient.emitWithAck(
                event: "households:create",
                payload: [
                    "userId": userId,
                    "data": ["name": trimmed]
                ],
                as: WsEnvelope<BackendHouseholdDTO>.self
            )

            guard envelope.ok, let household = envelope.data else {
                throw RecipeDataError.serverError(message: envelope.error ?? "Nie udało się utworzyć gospodarstwa.")
            }

            persistHousehold(id: household.id, name: household.name)
            bootstrapSession(userId: userId, householdId: household.id, householdName: household.name)
            weeklyMealStore?.resetLocalPlanningState()
            await registerPushDeviceIfPossible()
            isAuthenticated = true
        } catch {
            authError = UserFacingErrorMapper.message(from: error)
        }
    }

    func leaveCurrentHousehold() async {
        guard let userId = currentUserId, !userId.isEmpty,
              let householdId = currentHouseholdId, !householdId.isEmpty else { return }

        isSigningIn = true
        authError = nil
        defer { isSigningIn = false }

        do {
            let socketClient = SocketIORecipeSocketClient(baseURL: baseURL)
            let envelope: WsEnvelope<HouseholdLeaveAckDTO> = try await socketClient.emitWithAck(
                event: "households:leave",
                payload: [
                    "userId": userId,
                    "householdId": householdId
                ],
                as: WsEnvelope<HouseholdLeaveAckDTO>.self
            )

            if !envelope.ok {
                throw RecipeDataError.serverError(message: envelope.error ?? "Nie udało się opuścić gospodarstwa.")
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
            authError = UserFacingErrorMapper.message(from: error)
        }
    }

    func createInvitationLink() async throws -> URL {
        guard let userId = currentUserId, !userId.isEmpty,
              let householdId = currentHouseholdId, !householdId.isEmpty else {
            throw RecipeDataError.serverError(message: "Brak aktywnego gospodarstwa.")
        }

        let socketClient = SocketIORecipeSocketClient(baseURL: baseURL)
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
            throw RecipeDataError.serverError(message: envelope.error ?? "Nie udało się utworzyć zaproszenia.")
        }

        var components = URLComponents()
        components.scheme = "weeklymeals"
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

        let socketClient = realtimeSocket ?? SocketIORecipeSocketClient(baseURL: baseURL)
        let envelope: WsEnvelope<BackendInvitationPreviewDTO> = try await socketClient.emitWithAck(
            event: "households:previewInvitation",
            payload: [
                "userId": userId,
                "data": ["token": trimmedToken]
            ],
            as: WsEnvelope<BackendInvitationPreviewDTO>.self
        )

        guard envelope.ok, let data = envelope.data else {
            throw RecipeDataError.serverError(message: envelope.error ?? "Nie udało się sprawdzić zaproszenia.")
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

        let socketClient = realtimeSocket ?? SocketIORecipeSocketClient(baseURL: baseURL)
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
        weeklyMealStore?.resetLocalPlanningState()
        await registerPushDeviceIfPossible()
        isAuthenticated = true
        // Przyjęte zaproszenie znika ze skrzynki, a razem z nim wszystkie inne
        // do tego samego domu.
        await refreshPendingInvitations()
    }

    func acceptPendingInvitation(token: String, leaveOtherHouseholds: Bool = false) async {
        invitationPrompt = nil
        do {
            try await acceptInvitation(token: token, leaveOtherHouseholds: leaveOtherHouseholds)
        } catch is CancellationError {
            return
        } catch {
            authError = UserFacingErrorMapper.message(from: error)
        }
    }

    /// Świadoma odmowa — zaproszenie znika ze skrzynki i nie wraca po
    /// ponownym otwarciu linku.
    func declineInvitation(token: String) async {
        guard let userId = currentUserId, !userId.isEmpty else { return }
        let socket = realtimeSocket ?? SocketIORecipeSocketClient(baseURL: baseURL)
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
        let socket = realtimeSocket ?? SocketIORecipeSocketClient(baseURL: baseURL)
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
        guard url.scheme == "weeklymeals", url.host == "invite" else { return }
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
            authError = UserFacingErrorMapper.message(from: error)
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

    private func registerPushDeviceIfPossible() async {
        guard let userId = currentUserId, !userId.isEmpty else { return }
        guard let token = pendingPushDeviceToken, !token.isEmpty else { return }

        do {
            let socketClient = SocketIORecipeSocketClient(baseURL: baseURL)
            let envelope: WsEnvelope<PushDeviceRegisterAckDTO> = try await socketClient.emitWithAck(
                event: "notifications:registerDevice",
                payload: [
                    "userId": userId,
                    "data": [
                        "deviceToken": token,
                        "platform": "IOS",
                        "appBundleId": Bundle.main.bundleIdentifier ?? "weeklymeals",
                    ],
                ],
                as: WsEnvelope<PushDeviceRegisterAckDTO>.self
            )

            if !envelope.ok {
                throw RecipeDataError.serverError(message: envelope.error ?? "Nie udało się zarejestrować urządzenia.")
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

    private func restoreHouseholdIfNeeded() async {
        guard let userId = currentUserId, !userId.isEmpty else { return }
        guard currentHouseholdId == nil || currentHouseholdId?.isEmpty == true else { return }

        do {
            let socketClient = SocketIORecipeSocketClient(baseURL: baseURL)
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
                return
            }

            persistHousehold(id: household.id, name: household.name)
            bootstrapSession(userId: userId, householdId: household.id, householdName: household.name)
        } catch {
            NSLog("[SessionStore] restoreHouseholdIfNeeded FAILED error=\(error.localizedDescription)")
        }
    }

    private func persistSession(_ response: SessionResponse, appleUserIdentifier: String? = nil) {
        NSLog("[SessionStore] persistSession START userId=\(response.user.id) household=\(response.household?.id ?? "nil")")

        // Tokeny auth trafiają do Keychain (szyfrowany, chroniony przez Secure Enclave)
        let accessSaved = KeychainService.save(response.accessToken, forKey: Keys.accessToken)
        let refreshSaved = KeychainService.save(response.refreshToken, forKey: Keys.refreshToken)
        let userIdSaved = KeychainService.save(response.user.id, forKey: Keys.userId)
        NSLog("[SessionStore] keychain saved accessToken=\(accessSaved) refreshToken=\(refreshSaved)")
        NSLog("[SessionStore] keychain saved userId=\(userIdSaved)")

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
        persistOnboardingCompletedAt(response.user.onboardingCompletedAt)
        if let household = response.household {
            persistHousehold(id: household.id, name: household.name)
        } else {
            clearPersistedHousehold()
        }

        let writtenUserId = defaults.string(forKey: Keys.userId) ?? "<nil>"
        let writtenHouseholdId = defaults.string(forKey: Keys.householdId) ?? "<nil>"
        NSLog("[SessionStore] persistSession DONE readback userId=\(writtenUserId) householdId=\(writtenHouseholdId)")
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
        // Usuń tokeny z Keychain
        KeychainService.delete(forKey: Keys.accessToken)
        KeychainService.delete(forKey: Keys.refreshToken)
        KeychainService.delete(forKey: Keys.appleUserIdentifier)
        KeychainService.delete(forKey: Keys.userId)
        KeychainService.delete(forKey: Keys.householdId)
        KeychainService.delete(forKey: Keys.householdName)

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
        clearPersistedProfileFields()
        clearPersistedPreferences()
        onboardingCompletedAt = nil
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
            // Minimum display — jeśli warmup poszedł z cache w <2 s, dotrzymujemy
            // loaderowi 2 s, żeby przejście Auth/Loader/Dashboard było płynne a nie migotało.
            let elapsed = Date().timeIntervalSince(startedAt)
            if elapsed < minimumDisplay {
                let remaining = minimumDisplay - elapsed
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
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
                let socketClient = self.realtimeSocket ?? SocketIORecipeSocketClient(baseURL: self.baseURL)
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
                        self.authError = envelope.error
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
                    self.authError = UserFacingErrorMapper.message(from: error)
                }
            }
        }
        householdMembersTask = task
        await task.value
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
        let socket = realtimeSocket ?? SocketIORecipeSocketClient(baseURL: baseURL)

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
    /// row. Allergens, when supplied, replace the full set.
    @MainActor
    func saveUserPreferences(
        diet: String? = nil,
        calorieGoal: Int? = nil,
        allergens: [String]? = nil,
        goal: String? = nil,
        activityLevel: Int? = nil,
        proteinG: Int? = nil,
        fatG: Int? = nil,
        carbsG: Int? = nil,
        /// Wysyła jawne `null` na wszystkie trzy makra — czyli „przestań
        /// trzymać moje wartości i licz za mnie". Bez tego nie dałoby się
        /// wrócić do automatu, bo `nil` w parametrze znaczy „nie ruszaj".
        clearMacroOverrides: Bool = false
    ) async {
        guard let userId = currentUserId, !userId.isEmpty else { return }

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
            let normalised = allergens
                .map { $0.lowercased() }
                .sorted()
            data["allergens"] = normalised
            defaults.set(
                normalised.joined(separator: ","),
                forKey: PreferencesKeys.allergens
            )
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
        guard !data.isEmpty else { return }

        let socket = realtimeSocket ?? SocketIORecipeSocketClient(baseURL: baseURL)

        do {
            let _: WsEnvelope<BackendUserPreferencesDTO> = try await socket.emitWithAck(
                event: "users:preferences:update",
                payload: ["userId": userId, "data": data],
                as: WsEnvelope<BackendUserPreferencesDTO>.self
            )
        } catch {
            // Swallow — local AppStorage is already updated optimistically.
            // We retry on the next change.
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

        let socket = realtimeSocket ?? SocketIORecipeSocketClient(baseURL: baseURL)
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
    @MainActor
    func saveProfile(
        displayName: String? = nil,
        yearOfBirth: Int? = nil,
        heightCm: Int? = nil,
        weightKg: Double? = nil,
        sex: String? = nil
    ) async {
        guard let userId = currentUserId, !userId.isEmpty else { return }

        var data: [String: Any] = [:]
        if let displayName {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard !data.isEmpty else { return }

        let socket = realtimeSocket ?? SocketIORecipeSocketClient(baseURL: baseURL)

        do {
            let _: WsEnvelope<BackendUserProfileDTO> = try await socket.emitWithAck(
                event: "users:profile:update",
                payload: ["userId": userId, "data": data],
                as: WsEnvelope<BackendUserProfileDTO>.self
            )
        } catch {
            // Swallow — AppStorage is already updated optimistically. The
            // user can keep going through the welcome flow even on flaky
            // networks; the next `users:me` will reconcile.
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

        let socket = realtimeSocket ?? SocketIORecipeSocketClient(baseURL: baseURL)

        do {
            let envelope: WsEnvelope<BackendUserProfileDTO> = try await socket.emitWithAck(
                event: "users:onboarding:complete",
                payload: ["userId": userId],
                as: WsEnvelope<BackendUserProfileDTO>.self
            )
            if envelope.ok, let profile = envelope.data {
                persistOnboardingCompletedAt(profile.onboardingCompletedAt)
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

    private func userIdFromAccessToken() -> String? {
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
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userId = normalizedValue(object["sub"] as? String) else {
            return nil
        }

        NSLog("[SessionStore] restoreSession recovered userId from access token")
        return userId
    }
}
