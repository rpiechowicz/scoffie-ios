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

    /// Kolejki domen (7.10.2026, przegląd gałęzi): zapis i odczyt diety
    /// (`users:preferences:update` / `get`) idą po kolei, tak samo zapis
    /// profilu i `users:me`. Odczyt nie biegnie więc równolegle z zapisem
    /// w locie (np. ponawianym po zgubionym ack), a dwa zapisy nie dojdą do
    /// serwera w odwrotnej kolejności. Strażniki `ensure…Baseline` stoją PRZED
    /// wejściem do kolejki zapisu — odczyt, na który czekają, sam wchodzi do
    /// kolejki, więc nic nie czeka na siebie.
    ///
    /// `logout()` podmienia obie kolejki na nowe (7.10.2026, przegląd): stare
    /// operacje kończą się na SWOJEJ instancji (trzymają ją w lokalnej stałej),
    /// a nowa sesja nie czeka na `emitWithAck` poprzedniej.
    private var preferencesSyncQueue = SessionSyncQueue()
    private var profileSyncQueue = SessionSyncQueue()
    /// Epoka sesji — rośnie przy każdym `logout()`. Operacja kolejki zapamiętuje
    /// ją (i konto) na wejściu i sprawdza zaraz po wejściu do kolejki oraz przy
    /// odpowiedzi: operacja poprzedniej sesji nie pisze do pliku, nie ustawia
    /// `sexClearPending` i nic nie wysyła (wyciek między kontami, 7.10.2026).
    private var sessionEpoch = 0

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

    /// Zasłona przejść między fazami aplikacji — patrz `SCSessionCurtain`.
    /// Korzeń (`ScoffieApp`) przestawia pod nią ekran, a koniec sesji
    /// czyści pod nią stan.
    let sessionCurtain = SCSessionCurtain()

    var mealCalendarStore: MealCalendarStore?
    var recipeCatalogStore: RecipeCatalogStore?
    /// Scenariusze trybu Gotuj w pamięci telefonu (§7.7 workstreamu Gotuj).
    var cookScenarioStore: CookScenarioStore?
    /// Trwająca sesja gotowania — jedna na telefon, zapisana na dysku.
    var cookSessionStore: CookSessionStore?
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
    /// Prośba zakładki „Dziś” o zaplanowanie pory (pusta pora → „Zaplanuj”):
    /// Plan pokazuje ten dzień i otwiera wybór przepisu. Zdejmuje ją Plan,
    /// który ją obsłużył — jak `opensShoppingList`.
    var planSlotRequest: PlanSlotRequest?
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
    /// Start z pamięci podręcznej czeka na miniatury bieżącego tygodnia
    /// najwyżej tyle. Z dysku to ułamek tego; zdjęcie, którego na dysku nie
    /// ma, nie trzyma pulpitu za loaderem — doczyta się nad nim.
    ///
    /// Minimalnego czasu loadera już nie ma (był tu `startupMinimumDisplaySeconds`
    /// = cała fala dni, 1,34 s, i to przy KAŻDYM zimnym starcie, także
    /// z katalogiem i tygodniem w pamięci podręcznej). Pełną falę gra tylko
    /// wejście do aplikacji po logowaniu (`ScoffieApp.enterAppUnderLoader`).
    private let cachedStartupImageBudgetSeconds: Double = 0.5

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
            // Onboarding zamknięty — szkic kreatora nie ma już czego wznawiać
            // (7.10.2026). Wylogowanie kasuje go razem z chronionym plikiem.
            WelcomeDraft.clear()
        } else {
            defaults.removeObject(forKey: Keys.onboardingCompletedAt)
            onboardingCompletedAt = nil
        }
    }

    func refreshRealtimeStoresOnForeground() {
        // Chroniony plik ustawień też bywa zamknięty, gdy proces wstał przed
        // pierwszym odblokowaniem — teraz telefon jest odblokowany (7.10.2026).
        SCProtectedSettings.shared.reloadIfNeeded()
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
        // Brak access tokenu liczy się tak samo jak wygasły: nie ma czym budzić
        // socketu, a próba kończyłaby się odmową serwera i pętlą ponowień
        // zamiast jednym odświeżeniem.
        let tokenUsable = currentAccessToken?.isEmpty == false
            && accessTokenExpiry().map { $0 > Date() } != false
        if tokenUsable {
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
        // Odczyt preferencji przy starcie sesji padł — bez potwierdzonej
        // kopii ekran diety nie zapisze zmian, a Przepisy nie znają alergenów
        // (7.10.2026). Ponawiamy przy każdym powrocie, dopóki się nie uda.
        if isAuthenticated, let userId = currentUserId, !userId.isEmpty,
           preferencesConfirmedForUserId != userId {
            Task { @MainActor [weak self] in
                await self?.loadUserPreferences()
            }
        }
        // To samo dla sylwetki: `users:me` przy starcie padł.
        if isAuthenticated, let userId = currentUserId, !userId.isEmpty,
           profileConfirmedForUserId != userId {
            Task { @MainActor [weak self] in
                await self?.restoreHouseholdIfNeeded()
            }
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
        // Rozkład przypomnień z tego, co JUŻ jest w pamięci. Świeży plan
        // dojedzie chwilę później i przeliczy go drugi raz — a gdyby nie
        // dojechał (offline), przypomnienia i tak stoją na wczorajszej
        // prawdzie zamiast na niczym.
        rescheduleMealReminders()
    }

    // MARK: - Przypomnienia o własnym dniu

    /// Układa systemowe przypomnienia o gotowaniu i porach posiłków
    /// (`MealReminderService`) z tego, co store planu ma teraz w pamięci.
    ///
    /// Mieszka tutaj, bo to jedyne miejsce, w którym spotykają się trzy
    /// rzeczy potrzebne do ułożenia rozkładu: plan tygodnia
    /// (`mealCalendarStore`), godziny gospodarstwa (`mealSlotSchedule`)
    /// i tożsamość użytkownika — bez niej nie da się odróżnić własnego obiadu
    /// od obiadu domownika.
    ///
    /// Wołać można ile razy się chce: serwis układa rozkład od zera.
    func rescheduleMealReminders() {
        guard let mealCalendarStore, isAuthenticated else {
            MealReminderService.cancelAll()
            return
        }

        let now = Date()
        let calendar = PlanWeek.calendar
        let today = calendar.startOfDay(for: now)
        // Tydzień, o którym wiemy na pewno, że jest wczytany. Dzień spoza
        // niego wchodzi do rozkładu tylko wtedy, gdy store ma go w pamięci
        // z wcześniejszego przeglądania — inaczej „brak posiłków" znaczyłoby
        // „nie wiem", a wieczorne podsumowanie ogłaszałoby pusty dzień
        // każdemu, kto po prostu nie zajrzał w przyszły tydzień.
        let loadedWeek = Set(
            PlanWeek.dates(from: PlanWeek.monday(of: now)).map(PlanWeek.dateKey)
        )
        var days: [MealReminderService.Day] = []
        for offset in 0..<MealReminderService.horizonDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            guard loadedWeek.contains(PlanWeek.dateKey(date))
                    || !mealCalendarStore.plan(for: date).plannedSlots.isEmpty
            else { continue }
            days.append(reminderDay(for: date, store: mealCalendarStore))
        }

        MealReminderService.reschedule(
            days: days,
            context: MealReminderService.Context(
                closedStreak: closedDayStreak(store: mealCalendarStore, calendar: calendar, today: today),
                pendingShoppingItems: shoppingListStore?.items.filter { !$0.isChecked }.count ?? 0
            ),
            now: now
        )
    }

    /// Jeden dzień planu przełożony na to, czego potrzebują powiadomienia.
    private func reminderDay(
        for date: Date,
        store: MealCalendarStore
    ) -> MealReminderService.Day {
        let userId = currentUserId
        let schedule = mealSlotSchedule
        let plan = store.plan(for: date)
        let memberCount = didLoadHouseholdMembers ? max(1, householdMembers.count) : nil

        var meals: [MealReminderService.Meal] = []
        for slot in mealSlots.visibleSlots(planned: plan.plannedSlots) {
            var mine = plan.meals(for: slot)
            if let userId {
                mine = mine.visibleTo(memberId: userId)
            }
            for meal in mine {
                meals.append(
                    MealReminderService.Meal(
                        slot: slot,
                        minutes: schedule.minutes(for: slot),
                        title: meal.recipe.name,
                        prepMinutes: max(0, meal.recipe.prepTimeMinutes),
                        kcal: Int(
                            meal.nutritionPerPerson(
                                knownHouseholdMemberCount: memberCount,
                                memberId: userId
                            )
                                .kcal
                                .rounded()
                        ),
                        isFavourite: meal.recipe.favourite,
                        isEaten: meal.isEaten(by: userId)
                    )
                )
            }
        }
        return MealReminderService.Day(date: date, meals: meals)
    }

    /// Ile dni z rzędu — licząc od dziś wstecz — zostało domkniętych, czyli
    /// miało posiłki i wszystkie odhaczone.
    ///
    /// Dzień BEZ ani jednego posiłku serii nie przerywa i nie liczy się do
    /// niej. Inaczej weekend bez planu kasowałby każdą serię, a nie ma czego
    /// domykać w dniu, w którym nic nie stało.
    ///
    /// Liczone z lokalnego cache'u planów, więc seria kończy się razem
    /// z wylogowaniem albo zmianą gospodarstwa — to nie jest odznaka na
    /// serwerze, tylko miła liczba dla kogoś, kto właśnie domknął dzień.
    private func closedDayStreak(
        store: MealCalendarStore,
        calendar: Calendar,
        today: Date
    ) -> Int {
        let userId = currentUserId
        var streak = 0

        for offset in 0..<MealReminderService.streakLookbackDays {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { break }
            let plan = store.plan(for: date)
            let slots = mealSlots.visibleSlots(planned: plan.plannedSlots)

            var total = 0
            var eaten = 0
            for slot in slots {
                var mine = plan.meals(for: slot)
                if let userId {
                    mine = mine.visibleTo(memberId: userId)
                }
                total += mine.count
                eaten += mine.filter { $0.isEaten(by: userId) }.count
            }

            if total == 0 { continue }
            guard eaten == total else { break }
            streak += 1
        }
        return streak
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
            CrashReporting.setUser(id: currentUserId)
            currentHouseholdId = nil
            currentHouseholdName = nil
        }
        await registerPushDeviceIfPossible()

        // Odpowiedź auth niesie tylko tożsamość i dom. Sylwetka (rok
        // urodzenia, wzrost, waga, płeć) mieszka w bazie i wracała na ekran
        // dopiero przy `users:me` po RESTARCIE aplikacji — wylogowanie
        // i ponowne zalogowanie wyglądało więc jak reset ustawień profilu,
        // bo logout czyści lokalne kopie.
        if decoded.household == nil {
            // Bez domu `users:me` decyduje, DOKĄD wejść: kto przeszedł już
            // onboarding, zaczyna od kroku gospodarstwa, a członkostwo
            // nieobecne w odpowiedzi auth prowadzi prosto na pulpit. Czekamy
            // na nie pod spinnerem logowania — dociągnięte po wejściu
            // przestawiało kreator (przewodnik → krok 5) albo cały korzeń
            // drugi raz, już na oczach użytkownika.
            await restoreHouseholdBeforeEntering()
        } else {
            // Z domem cel jest znany — profil dociąga się w tle, pod loaderem.
            Task { [weak self] in
                await self?.restoreHouseholdIfNeeded()
            }
        }
        isAuthenticated = true
    }

    /// `restoreHouseholdIfNeeded` z limitem czasu: brak sieci po udanym
    /// logowaniu nie może trzymać spinnera w nieskończoność. Po limicie
    /// wchodzimy z tym, co wiadomo — reszta dojdzie przy następnym `users:me`.
    private func restoreHouseholdBeforeEntering() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                await self?.restoreHouseholdIfNeeded()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    /// Wylogowanie z ręki użytkownika: najpierw zasłona, potem sprzątanie.
    ///
    /// `logout()` czyści stan od razu — store pulpitu znikają, a preferencje
    /// wracają do domyślnych pod otwartym jeszcze ekranem. Przy wymuszonym
    /// wylogowaniu (odmowa serwera, cofnięte Apple ID) liczy się czas; przy
    /// stuknięciu „Wyloguj” — to, żeby nic z tego nie było widać.
    func signOut() async {
        await sessionCurtain.cover()
        logout()
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
        preferencesConfirmedForUserId = nil
        profileConfirmedForUserId = nil
        // Trwające odczyty dokończą się same, ale ich wynik nie należy już do
        // nikogo (sprawdzają `currentUserId`); nowa sesja zaczyna własne.
        preferencesReadTask = nil
        preferencesReadUserId = nil
        householdRestoreTask = nil
        householdRestoreUserId = nil
        // Nowa epoka i nowe kolejki: operacje poprzedniego konta czekające
        // w kolejce kończą się zaraz po wejściu (strażnik epoki), a trwające
        // nie blokują logowania następnego konta.
        sessionEpoch &+= 1
        preferencesSyncQueue = SessionSyncQueue()
        profileSyncQueue = SessionSyncQueue()
        CrashReporting.setUser(id: currentUserId)
        currentHouseholdId = nil
        currentHouseholdName = nil
        startupPhase = .idle
        isRestoringSession = false
        // Następne logowanie ma zacząć od Kalendarza, a nie od zakładki,
        // na której ktoś zostawił poprzednią sesję.
        dashboardTab = .calendar
        planSlotRequest = nil
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
        //
        // Wszystko POD zasłoną: czyszczenie `UserDefaults` przestawia
        // otwarty arkusz profilu i Ustawienia na wartości domyślne, a to
        // było widać przez pół sekundy przed ekranem logowania.
        await sessionCurtain.cover()
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
        //
        // ALE: o sesji decyduje REFRESH token, nie access. Access token żyje
        // godzinę i jest odtwarzalny jednym żądaniem; refresh token jest
        // jedynym, którego nie da się odzyskać. Brak samego access tokenu przy
        // ŻYWYM refresh tokenie to nie koniec sesji, tylko stan przejściowy —
        // i to stan, który `refreshSessionTokens` zostawia CELOWO, gdy zapis
        // nowej pary padnie w połowie (refresh zapisany, access nie). Kasowanie
        // sesji w tym miejscu zamieniałoby jeden nieudany zapis w wylogowanie.
        let accessToken = currentAccessToken
        if accessToken?.isEmpty != false {
            let status = KeychainService.status(forKey: Keys.accessToken)
            let hasRefreshToken = currentRefreshToken?.isEmpty == false
            if status != errSecItemNotFound {
                // Keychain chwilowo niedostępny (proces obudzony przed pierwszym
                // odblokowaniem po restarcie, przejściowy błąd) — sesja żyje,
                // wrócimy do niej przy pierwszym wejściu na pierwszy plan.
                debugLog("[SessionStore] restoreSession deferred — keychain status \(status)")
                restoreDeferredUntilKeychainAvailable = true
                return
            }
            guard hasRefreshToken else {
                debugLog("[SessionStore] restoreSession EARLY RETURN — both tokens missing")
                clearPersistedSession()
                return
            }
            debugLog("[SessionStore] restoreSession — brak access tokenu, ale refresh token żyje: odzyskuję sesję")
        }
        restoreDeferredUntilKeychainAvailable = false

        syncPersistedSessionSnapshot(snapshot)
        currentUserId = snapshot.userId
        CrashReporting.setUser(id: currentUserId)
        let householdId = snapshot.householdId
        let householdName = (snapshot.householdName?.isEmpty == false) ? snapshot.householdName : nil
        // Wygasły access token: socket łączyłby się od razu martwym tokenem
        // i każde żądanie startu dostawałoby odmowę, zanim refresh zdąży —
        // wtedy bootstrap czeka na nową parę. Brak access tokenu liczy się tak
        // samo jak wygasły: nie ma czym wołać, więc bootstrap czeka.
        let tokenAlreadyExpired =
            accessToken?.isEmpty != false || accessTokenExpiry().map { $0 <= Date() } == true
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
        CrashReporting.setUser(id: currentUserId)
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
        planSlotRequest = nil
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
        // Poprzednia sesja katalogu (inne konto, inny dom, ponowne logowanie)
        // traci prawo zapisu i przestaje przyjmować spóźnione odpowiedzi,
        // ZANIM powstanie nowa — patrz `RecipeCatalogStore.invalidate()`.
        self.recipeCatalogStore?.invalidate()
        self.recipeCatalogStore = RecipeCatalogStore(
            repository: ApiRecipeRepository(client: recipeTransport),
            ownerKey: "\(userId)_\(householdId)"
        )
        self.cookScenarioStore?.invalidate()
        self.cookScenarioStore = CookScenarioStore(
            repository: ApiRecipeRepository(client: recipeTransport),
            ownerKey: "\(userId)_\(householdId)"
        )
        // Sesja gotowania przeżywa ponowne zbudowanie store'ów tego samego
        // konta i domu (restore po zimnym starcie, powrót połączenia); inny
        // właściciel dostaje czysty store, a cudzego pliku nie wczyta.
        let cookOwnerKey = "\(userId)_\(householdId)"
        if self.cookSessionStore?.ownerKey != cookOwnerKey {
            let cook = CookSessionStore(ownerKey: cookOwnerKey)
            cook.onRing = { [weak self] in
                Task { @MainActor in await self?.presentCookingIfRinging() }
            }
            self.cookSessionStore = cook
        }
        let shoppingListStore = ShoppingListStore(
            repository: ApiShoppingListRepository(client: shoppingTransport),
            currentUserId: userId,
            cacheNamespace: "\(userId)_\(householdId)"
        )
        self.shoppingListStore = shoppingListStore

        // Schowane funkcje (`FeatureFlags`) nie dostają store'u: bez niego nie
        // ma ani zapytań do serwera, ani odczytu HealthKit w tle.
        if FeatureFlags.thermomix {
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
        }

        let healthStore: HealthStepsStore? = FeatureFlags.health
            ? HealthStepsStore(
                service: HealthKitService(),
                client: IntegrationsAPIClient(
                    baseURL: baseURL,
                    tokenProvider: { [weak self] in self?.currentAccessToken },
                    refreshSession: { [weak self] in
                        await self?.refreshSessionTokens() == .refreshed
                    }
                )
            )
            : nil
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
        // Zapis asystenta (REST) odświeża zakupy i plan wprost — nie tylko
        // przez rozgłoszenie socketem, które przepada, gdy socket się łączy.
        self.agentStore?.onHouseholdDataChanged = { [weak self] in
            self?.shoppingListStore?.invalidateAllWeeks()
            self?.mealCalendarStore?.refreshObservedState()
        }
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
        if let healthStore {
            healthStore.startObserving()
            Task { @MainActor in
                await healthStore.refreshAndSync()
            }
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
            // zaproszenie do skrzynki, więc kolejność ma znaczenie. Przepis
            // z linku idzie stąd do kolejki pulpitu.
            await self?.replayStoredDeepLinkIfNeeded()
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
        // Zaplanowane przypomnienia przeżyłyby wylogowanie: `UNCalendar-
        // NotificationTrigger` nie wie nic o sesji i odpaliłby cudzy obiad
        // na telefonie, z którego ktoś już wyszedł.
        MealReminderService.cancelAll()
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
        // Stan domu w cache katalogu (przepisy gospodarstwa, ulubione) znika
        // razem z domem; publiczny katalog z rewizją zostaje — jest wspólny
        // dla wszystkich kont, a następne logowanie zrobi z niego deltę.
        // Najpierw unieważnienie (zapis czekający w kolejce już się nie
        // odbędzie, spóźniona odpowiedź niczego nie opublikuje), potem
        // kasowanie prywatnego pliku tą samą kolejką.
        recipeCatalogStore?.invalidate()
        RecipeCatalogStore.clearCache()
        recipeCatalogStore = nil
        // Paczki Gotuj niosą też przepisy domu, a sesja gotowania należy do
        // konta — obie znikają z domem.
        cookScenarioStore?.invalidate()
        cookScenarioStore = nil
        CookScenarioStore.clearCache()
        cookSessionStore?.end()
        cookSessionStore = nil
        CookSessionStore.clearCache()
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

                // Zmiana nazwy domu przychodzi tym samym zdarzeniem, ale bez
                // samej nazwy w ładunku — dociągamy ją odczytem gospodarstwa.
                if event.action == "UPDATE_NAME" {
                    await self.loadMealSlotConfiguration()
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
            // Ten sam odczyt niesie nazwę — właściciel mógł ją zmienić na
            // innym telefonie, a lokalne lustro trzyma tę z logowania.
            applyHouseholdName(household.name, householdId: household.id)
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

    /// Granice nazwy gospodarstwa — WSZĘDZIE w aplikacji 2…50 (6.10.2026:
    /// zakładanie w Ustawieniach miało 50, zmiana nazwy i kreator 64).
    /// Serwer (`CreateHouseholdDto` / `UpdateHouseholdDto`, 2…64, także na
    /// WebSockecie) jest luźniejszy, więc nic, co tu przejdzie, nie odbije się.
    static let householdNameLengthRange = 2...50

    static func isValidHouseholdName(_ name: String) -> Bool {
        householdNameLengthRange.contains(
            name.trimmingCharacters(in: .whitespacesAndNewlines).count
        )
    }

    /// Limit `displayName` z `UpdateProfileDto` (64). Przycinamy PRZED zapisem
    /// lokalnym i wysyłką, bo `saveProfile` zapisuje optymistycznie — dłuższa
    /// nazwa zostawałaby na telefonie, a serwer odrzucałby ją po cichu.
    static let displayNameMaxLength = 64

    /// Imię przycięte do limitu serwera. `@MaxLength` liczy PUNKTY KODOWE, nie
    /// znaki: emoji z łącznikiem to jeden znak, a kilka punktów, więc cięcie po
    /// `count` przepuszczało imię, które serwer odrzucał — razem z całym zapisem
    /// sylwetki. Odcinamy całe znaki od końca, aż zmieszczą się punkty kodowe.
    static func limitedDisplayName(_ name: String) -> String {
        var limited = name
        while limited.unicodeScalars.count > displayNameMaxLength {
            limited.removeLast()
        }
        return limited
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
        guard Self.isValidHouseholdName(trimmed) else {
            authError = "Nazwa gospodarstwa musi mieć od 2 do 50 znaków."
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

    /// Zmiana nazwy gospodarstwa. Serwer wpuszcza tylko właściciela
    /// (`ensureOwner`) i rozgłasza `membersChanged` z akcją `UPDATE_NAME`,
    /// po której pozostali domownicy dociągają nową nazwę.
    @MainActor
    @discardableResult
    func renameHousehold(to rawName: String) async -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let userId = currentUserId, !userId.isEmpty,
              let householdId = currentHouseholdId, !householdId.isEmpty else { return false }
        guard Self.isValidHouseholdName(name) else {
            authError = "Nazwa gospodarstwa musi mieć od 2 do 50 znaków."
            return false
        }
        guard name != currentHouseholdName else { return true }

        authError = nil
        do {
            let socketClient = sessionSocket()
            let envelope: WsEnvelope<BackendHouseholdDTO> = try await socketClient.emitWithAck(
                event: "households:updateName",
                payload: [
                    "userId": userId,
                    "householdId": householdId,
                    "data": ["name": name]
                ],
                as: WsEnvelope<BackendHouseholdDTO>.self
            )
            guard envelope.ok, let household = envelope.data else {
                throw envelope.failure(fallback: "Nie udało się zmienić nazwy gospodarstwa.")
            }
            applyHouseholdName(household.name, householdId: household.id)
            return true
        } catch is CancellationError {
            return false
        } catch {
            authError = UserFacingErrorMapper.inlineMessage(from: error)
            return false
        }
    }

    /// Nazwa do stanu i do lustra (`settings.household.name`, które czyta
    /// `@AppStorage` w Ustawieniach) — tylko dla bieżącego gospodarstwa.
    private func applyHouseholdName(_ name: String, householdId: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard householdId == currentHouseholdId, !trimmed.isEmpty, trimmed != currentHouseholdName else { return }
        currentHouseholdName = trimmed
        persistHousehold(id: householdId, name: trimmed)
    }

    /// Dieta i alergeny domowników — do arkusza gospodarstwa. Ciche na
    /// błędach: bez tych danych wiersze pokazują samą rolę.
    @MainActor
    func loadHouseholdMemberPreferences() async -> [String: HouseholdMemberPreferences] {
        guard let userId = currentUserId, !userId.isEmpty,
              let householdId = currentHouseholdId, !householdId.isEmpty else { return [:] }

        do {
            let socketClient = sessionSocket()
            let envelope: WsEnvelope<[BackendMemberContextDTO]> = try await socketClient.emitWithAck(
                event: "households:memberPreferences",
                payload: [
                    "userId": userId,
                    "householdId": householdId
                ],
                as: WsEnvelope<[BackendMemberContextDTO]>.self
            )
            guard envelope.ok, let rows = envelope.data else { return [:] }

            var result: [String: HouseholdMemberPreferences] = [:]
            for row in rows {
                let tokens = Set((row.allergens ?? []).map { $0.lowercased() })
                result[row.userId] = HouseholdMemberPreferences(
                    diet: row.dietPreference.flatMap { DietPreference(backendValue: $0) } ?? DietPreference.none,
                    allergens: Allergen.allCases.filter { tokens.contains($0.rawValue) },
                    targets: Self.nutritionTargets(from: row.targets)
                )
            }
            return result
        } catch {
            return [:]
        }
    }

    /// Cele dnia domownika z odpowiedzi serwera. Kalorie bez wartości (albo
    /// zero) to brak celu, a nie cel „0 kcal”, przy którym każdy posiłek
    /// świeciłby przekroczeniem.
    private static func nutritionTargets(from dto: BackendMemberContextDTO.Targets?) -> DailyNutritionTargets? {
        guard let dto, let kcal = dto.calorieGoal, kcal > 0 else { return nil }
        let macros = dto.macros.map {
            MacroTargets(
                proteinG: Int($0.proteinG.rounded()),
                fatG: Int($0.fatG.rounded()),
                carbsG: Int($0.carbsG.rounded())
            )
        }
        return DailyNutritionTargets(kcal: Int(kcal.rounded()), macros: macros)
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

        // Link https, nie schemat. `scoffie://invite?token=…` w iMessage czy
        // WhatsAppie jest martwy — nie klika się, nie ma podglądu, a odbiorca
        // widzi surowy token. Strona scoffie.app/zaproszenie/ ma kartę
        // z tytułem i obrazkiem, otwiera się wszędzie i dopiero po kliknięciu
        // na niej uruchamia aplikację tym samym schematem.
        //
        // Token idzie we FRAGMENCIE (`#…`), nie w ścieżce: fragment nigdy nie
        // opuszcza przeglądarki — nie trafia do serwera ani logów Cloudflare,
        // nie ma go w nagłówku Referer, a roboty podglądu linków go nie
        // dostają. Universal Links fragment zachowują, więc u kogoś, kto ma
        // aplikację, ten sam adres otwiera ją wprost (`DeepLink`), a strona
        // zostaje dla tych, którzy jej jeszcze nie mają.
        guard let url = DeepLink.invitation(token: invitation.token).url else {
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
        // Domownik z zaproszenia to ten, do kogo idą powiadomienia o zmianach
        // planu — o zgodę pytamy, gdy zobaczy pulpit (`DashboardView`), nie
        // przy starcie aplikacji (6.10.2026).
        asksNotificationsOnReveal = true
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

    /// Link, który przyszedł w chwili, gdy nie było go jak otworzyć.
    ///
    /// Zaproszenie otwarte przed zalogowaniem przepadało: `previewInvitation`
    /// wymaga `userId`, więc kończyło się komunikatem „Zaloguj się" i tokenem
    /// wyrzuconym do kosza — a po zalogowaniu nie było już czego otworzyć.
    /// Przepis czeka dłużej: aż będzie pulpit (logowanie, kreator, loader).
    /// Trzymany w `UserDefaults`, bo logowanie przez Apple potrafi odesłać
    /// użytkownika poza aplikację, a kreator — trwać do następnego uruchomienia.
    ///
    /// Jeden slot, ostatni link wygrywa: kto otworzył dwa, chce drugiego.
    /// W środku leży ADRES (`DeepLink.url`), nie własny format — czyta go
    /// ten sam parser, który czyta linki z zewnątrz.
    private static let pendingDeepLinkKey = "session.pendingDeepLink"
    /// Klucz sprzed `DeepLink` — sam token zaproszenia. Czytany, żeby
    /// zaproszenie odłożone przez poprzedni build nie zginęło przy
    /// aktualizacji; kasowany przy pierwszym zapisie.
    private static let legacyPendingInvitationTokenKey = "session.pendingInvitationToken"

    private var storedDeepLink: DeepLink? {
        get {
            let defaults = UserDefaults.standard
            if let raw = defaults.string(forKey: Self.pendingDeepLinkKey),
               let url = URL(string: raw),
               let link = DeepLink(url: url) {
                return link
            }
            if let token = defaults.string(forKey: Self.legacyPendingInvitationTokenKey), !token.isEmpty {
                return .invitation(token: token)
            }
            return nil
        }
        set {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: Self.legacyPendingInvitationTokenKey)
            if let raw = newValue?.url?.absoluteString {
                defaults.set(raw, forKey: Self.pendingDeepLinkKey)
            } else {
                defaults.removeObject(forKey: Self.pendingDeepLinkKey)
            }
        }
    }

    /// Przepis z linku, który czeka na pulpit (`DashboardView` otwiera go,
    /// gdy loader startu zejdzie). W pamięci — do obserwowania przez widok;
    /// na dysku leży równolegle w `storedDeepLink`, dopóki się nie otworzy.
    private(set) var pendingRecipeLink: RecipeLinkTarget?
    /// Po dołączeniu do domu z zaproszenia: prośba o zgodę na powiadomienia,
    /// gdy pulpit się odsłoni. Zdejmuje ją `DashboardView`.
    var asksNotificationsOnReveal = false

    /// Stuknięcie w Live Activity gotowania przed końcem startu — tryb Gotuj
    /// otwiera się nad gotowym pulpitem (`resumeCookingIfRequested`).
    var cookingResumeRequested = false

    /// Zdejmuje przepis z kolejki — w chwili, w której pulpit go otwiera.
    func takePendingRecipeLink() -> RecipeLinkTarget? {
        guard let target = pendingRecipeLink else { return nil }
        pendingRecipeLink = nil
        if case .recipe = storedDeepLink {
            storedDeepLink = nil
        }
        return target
    }

    /// Odtwarza link odłożony przed zalogowaniem. Woła się po bootstrapie
    /// sesji: zaproszenie pokazuje się od razu, przepis idzie do kolejki
    /// pulpitu (zostaje też na dysku, dopóki pulpit go nie otworzy).
    @MainActor
    private func replayStoredDeepLinkIfNeeded() async {
        guard let link = storedDeepLink else { return }
        guard let userId = currentUserId, !userId.isEmpty else { return }
        switch link {
        case .invitation(let token):
            storedDeepLink = nil
            await presentInvitation(token: token)
        case .recipe(let target):
            pendingRecipeLink = target
        case .cooking:
            storedDeepLink = nil
        }
    }

    /// Wejście każdego linku — Universal Link z `scoffie.app` albo schemat
    /// `scoffie://` (`ScoffieApp.onOpenURL`). Rozpoznaje `DeepLink`, reszta
    /// jest ignorowana.
    func handleIncomingURL(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }

        // Live Activity gotowania: sesja jest na tym telefonie — bez
        // odkładania do zalogowania. Przed końcem startu tylko zapamiętujemy
        // (`resumeCookingIfRequested` po `.ready`).
        if case .cooking = link {
            if startupPhase == .ready, cookSessionStore?.session != nil {
                Task { await resumeCooking(instantly: true) }
            } else {
                cookingResumeRequested = true
            }
            return
        }

        guard currentUserId?.isEmpty == false else {
            // Odkładamy i wracamy do tego po zalogowaniu — zamiast kazać
            // użytkownikowi szukać linku po raz drugi.
            storedDeepLink = link
            switch link {
            case .invitation:
                authError = "Zaloguj się, aby przyjąć zaproszenie do gospodarstwa."
            case .recipe:
                authError = "Zaloguj się, aby zobaczyć przepis."
            case .cooking:
                break
            }
            return
        }

        switch link {
        case .invitation(let token):
            Task {
                await presentInvitation(token: token)
            }
        case .recipe(let target):
            // Przepis otwiera pulpit — dopiero gdy jest (dom, koniec kreatora,
            // zejście loadera). Na dysk też: kreator potrafi trwać do
            // następnego uruchomienia aplikacji.
            storedDeepLink = link
            pendingRecipeLink = target
        case .cooking:
            break
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
    ///
    /// Jeden `users:me` naraz na konto (7.10.2026, Codex runda 2) — start
    /// sesji, logowanie, powrót na pierwszy plan i `ensureProfileBaseline`
    /// czekają na to samo zadanie (ten sam wyścig migawek co przy diecie).
    private func restoreHouseholdIfNeeded() async {
        guard let userId = currentUserId, !userId.isEmpty else { return }
        // Anulowanie czekającego (limit 4 s w `restoreHouseholdBeforeEntering`)
        // przechodzi na wspólne zadanie — jak wtedy, gdy `users:me` szło
        // w zadaniu dziecku: ponowienia `emitWithAck` kończą się na `sleep`.
        if let running = householdRestoreTask, householdRestoreUserId == userId {
            await withTaskCancellationHandler {
                await running.value
            } onCancel: {
                running.cancel()
            }
            return
        }
        let epoch = sessionEpoch
        let task = Task { @MainActor [weak self] () -> Void in
            guard let self else { return }
            await self.performHouseholdRestore(userId: userId, epoch: epoch)
        }
        householdRestoreTask = task
        householdRestoreUserId = userId
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if householdRestoreTask == task {
            householdRestoreTask = nil
            householdRestoreUserId = nil
        }
    }

    /// Właściwe `users:me` — tylko przez `restoreHouseholdIfNeeded`. Nie czeka
    /// na nic, co czeka na nie samo (`bootstrapSession` tylko odpala zadania).
    private func performHouseholdRestore(userId: String, epoch: Int) async {
        // W kolejce profilu: zapis „Twoich danych” w locie kończy się przed
        // `users:me` (7.10.2026). W środku nic nie czeka na tę kolejkę
        // (`bootstrapSession` tylko odpala zadania).
        let queue = profileSyncQueue
        await queue.enter()
        defer { queue.leave() }
        // Wylogowanie w czasie czekania — ta operacja należy do starej sesji.
        guard sessionEpoch == epoch, currentUserId == userId else { return }
        let persistedHouseholdId =
            (currentHouseholdId?.isEmpty == false) ? currentHouseholdId : nil
        let protectedStore = SCProtectedSettings.shared
        let profileGenerationAtStart = protectedStore.changeGeneration(.profile)

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
            // Wylogowanie / zmiana konta w trakcie — odpowiedź nie jest już nasza.
            guard sessionEpoch == epoch, currentUserId == userId else { return }

            let defaults = UserDefaults.standard
            // Sylwetkę i imię wpisujemy tylko, gdy w trakcie odczytu nie było
            // edycji ani zapisu „Twoich danych” — inaczej starsza migawka
            // nadpisałaby nowszą zmianę (7.10.2026). Wtedy też bez potwierdzenia.
            if protectedStore.changeGeneration(.profile) == profileGenerationAtStart {
                SCProtectedSettings.shared.set(user.displayName, forKey: Keys.displayName)
                SCProtectedSettings.shared.set(user.email ?? "", forKey: Keys.email)
                if let avatarUrl = user.avatarUrl, !avatarUrl.isEmpty {
                    SCProtectedSettings.shared.set(avatarUrl, forKey: Keys.avatarUrl)
                } else {
                    SCProtectedSettings.shared.removeObject(forKey: Keys.avatarUrl)
                }
                persistProfileFields(
                    yearOfBirth: user.yearOfBirth,
                    heightCm: user.heightCm,
                    weightKg: user.weightKg,
                    sex: user.sex
                )
                // Sylwetka i imię = serwer: „Twoje dane” mogą wysyłać pełny
                // zestaw (`ensureProfileBaseline`, 7.10.2026).
                profileConfirmedForUserId = userId
            } else {
                debugLog("[SessionStore] users:me — sylwetka starsza niż lokalna zmiana, pomijam")
            }
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

        // Tokeny auth trafiają do Keychain (szyfrowany, chroniony przez Secure
        // Enclave). Refresh token PIERWSZY, tą samą zasadą co przy odświeżaniu
        // (`refreshSessionTokens`): to on jest jedynym, z którego da się
        // odzyskać sesję, więc jeśli któryś zapis ma nie dojść, niech to będzie
        // ten odzyskiwalny.
        let refreshSaved = KeychainService.save(response.refreshToken, forKey: Keys.refreshToken)
        let accessSaved = KeychainService.save(response.accessToken, forKey: Keys.accessToken)
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
        SCProtectedSettings.shared.set(response.user.displayName, forKey: Keys.displayName)
        SCProtectedSettings.shared.set(response.user.email ?? "", forKey: Keys.email)
        // Apple Sign in doesn't provide a profile photo; avatarUrl is typically
        // nil for Apple users and surfaces initials-based fallback in the UI.
        // For Google / other providers it persists the real URL.
        if let avatarUrl = response.user.avatarUrl, !avatarUrl.isEmpty {
            SCProtectedSettings.shared.set(avatarUrl, forKey: Keys.avatarUrl)
        } else {
            SCProtectedSettings.shared.removeObject(forKey: Keys.avatarUrl)
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
        // Odłożony link należy do osoby, która go otworzyła — następna
        // zalogowana dostawała alert z cudzym domem i mogła do niego dołączyć.
        storedDeepLink = nil
        pendingRecipeLink = nil
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
        SCProtectedSettings.shared.removeObject(forKey: Keys.avatarUrl)
        defaults.removeObject(forKey: Keys.avatarColor)
        SCProtectedSettings.shared.removeObject(forKey: Keys.displayName)
        SCProtectedSettings.shared.removeObject(forKey: Keys.email)
        defaults.removeObject(forKey: Keys.onboardingCompletedAt)
        // Przewodnik „Poznaj aplikację" należy do konta, nie do telefonu:
        // bez tej linii kolejna osoba logująca się na tym urządzeniu
        // wpadałaby prosto w pytania o wzrost i alergeny, bo flaga
        // z poprzedniej sesji nadal leżałaby w `UserDefaults`.
        defaults.removeObject(forKey: TourCompletion.storageKey)
        clearPersistedProfileFields()
        clearPersistedPreferences()
        // Cały chroniony plik (profil, dieta, e-mail, imię — 7.10.2026), nie
        // tylko klucze wymienione wyżej: ta sama zasada co `KeychainService.deleteAll()`.
        SCProtectedSettings.shared.removeAll()
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
        SCProtectedSettings.shared.removeObject(forKey: PreferencesKeys.diet)
        SCProtectedSettings.shared.removeObject(forKey: PreferencesKeys.calorieGoal)
        SCProtectedSettings.shared.removeObject(forKey: PreferencesKeys.allergens)
        SCProtectedSettings.shared.removeObject(forKey: PreferencesKeys.goal)
        SCProtectedSettings.shared.removeObject(forKey: PreferencesKeys.activityLevel)
        SCProtectedSettings.shared.removeObject(forKey: PreferencesKeys.proteinG)
        SCProtectedSettings.shared.removeObject(forKey: PreferencesKeys.fatG)
        SCProtectedSettings.shared.removeObject(forKey: PreferencesKeys.carbsG)
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
    ///
    /// Dwie drogi do `.ready`:
    /// - z pamięci podręcznej (katalog z pliku i bieżący tydzień z planu na
    ///   dysku, `loadStartupDataFromCache`) — od razu, gdy miniatury tygodnia
    ///   są w pamięci (z dysku), bez sieci i bez minimalnego czasu; świeże
    ///   dane (`prepareStartupData`) dochodzą już nad pulpitem;
    /// - bez niej (świeża instalacja, pusty albo nieaktualny tydzień w pliku) —
    ///   `prepareStartupData` pod loaderem, z limitem `startupTimeoutSeconds`,
    ///   też bez minimalnego czasu.
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
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.startupPhase = .warmingUp
            // Zimny start z danymi w pamięci podręcznej: pierwszy ekran ma
            // z czego się narysować, więc loader nie czeka ani na sieć, ani
            // na żaden minimalny czas — tylko na miniatury tygodnia z dysku.
            let fromCache = self.loadStartupDataFromCache()
            if fromCache {
                await self.runCachedStartupWithTimeout()
            } else {
                await self.runStartupWithTimeout()
            }
            // Anulowany warmup (bootstrap nowego gospodarstwa w trakcie) nie
            // decyduje o fazie — nowy task sam przejdzie warmingUp → ready.
            guard !Task.isCancelled else { return }
            // Nawet jeśli któryś krok się nie udał (offline / timeout),
            // wchodzimy w .ready — dashboard ma własne skeletony / cache.
            self.startupPhase = .ready
            // Scenariusze Gotuj dań dziś i jutro — po starcie, w tle; nic na
            // nie nie czeka, a przycisk „Gotuj” pojawi się, gdy przyjdą.
            Task { @MainActor [weak self] in
                // Timer zadzwonił, zanim aplikacja wstała (zimny start) —
                // alarm dopiero nad gotowym pulpitem, nie nad loaderem.
                await self?.presentCookingIfRinging()
                await self?.resumeCookingIfRequested()
                await self?.prefetchCookScenarios()
            }
            self.prepareUnbuiltTabs()
            // Z pamięci podręcznej: świeży katalog, domownicy, tydzień z serwera
            // i pierwsze miniatury katalogu dochodzą już nad pulpitem — ta sama
            // praca co pod loaderem, w tej samej kolejności i z tymi samymi
            // limitami rozgrzewki zdjęć. W `startupTask`, więc wylogowanie
            // i zmiana gospodarstwa ją przerywają.
            if fromCache {
                await self.prepareStartupData()
            }
        }
        startupTask = task
        await task.value
    }

    /// Pulpit z pamięci podręcznej, bez sieci: katalog z pliku (synchronizacja
    /// rusza obok, jak w `RecipeCatalogStore.loadIfNeeded`) i bieżący tydzień
    /// z pliku planu (`MealCalendarStore` wczytuje go przy powstaniu).
    /// `true` = pierwszy ekran ma z czego się narysować.
    ///
    /// Pusty tydzień w pliku nie wystarcza: bywa nieaktualny (nowy tydzień,
    /// plan ułożony na innym telefonie), a Kalendarz, który po chwili sam się
    /// wypełnia, wyglądałby jak błąd — wtedy start czeka na serwer jak bez
    /// pamięci podręcznej.
    private func loadStartupDataFromCache() -> Bool {
        guard let catalog = recipeCatalogStore, let mealStore = mealCalendarStore else { return false }
        guard catalog.loadFromCacheIfPossible() else { return false }
        return datesViewModel.dates.contains { date in
            MealSlot.allCases.contains { slot in !mealStore.meals(for: date, slot: slot).isEmpty }
        }
    }

    /// Miniatury bieżącego tygodnia z pliku planu, najwyżej
    /// `cachedStartupImageBudgetSeconds` — talerz Kalendarza ma zdjęcie
    /// w klatce, w której loader gaśnie.
    private func runCachedStartupWithTimeout() async {
        let timeoutSeconds = cachedStartupImageBudgetSeconds
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                await self?.prefetchCachedWeekThumbnails()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    private func prefetchCachedWeekThumbnails() async {
        guard let mealStore = mealCalendarStore else { return }
        let urls = datesViewModel.dates
            .flatMap { date in MealSlot.allCases.flatMap { mealStore.meals(for: date, slot: $0) } }
            .compactMap(\.recipe.imageURL)
        await ImagePrefetcher.prefetchAwaiting(urls)
    }

    /// To, co zakładki robiły same, gdy budowały się wszystkie pod loaderem.
    ///
    /// Systemowy `TabView` (od 6.10.2026) buduje zakładkę dopiero przy jej
    /// pierwszym wyborze, a start pokazuje Kalendarz. Bez tego rozmowa
    /// asystenta czekałaby na pierwsze wejście w zakładkę: tura, która biegła,
    /// gdy aplikację zamknięto, nie dawałaby plakietki ani kapsuły „Asystent
    /// odpowiedział”, a pula byłaby nieznana do pierwszego kliknięcia.
    /// `AssistantView` woła to samo przy pierwszym wyborze — powtórka jest
    /// bezpieczna (otwarta rozmowa tylko sprawdza świeżość, tura w biegu nie
    /// jest śledzona drugi raz), a gdy zakładka Asystenta już stoi (start
    /// z powiadomienia „Asystent odpowiedział”), robi to sama.
    ///
    /// Pula osobno od rozmowy: `openIfNeeded` czeka na koniec tury w biegu
    /// (do kilku minut), a pula ma być znana od razu.
    ///
    /// Reszta zakładek nie potrzebuje niczego przed pierwszym wejściem:
    /// tydzień, zakupy (plakietka koszyka), domownicy i zgody ładuje start
    /// sesji, a cele domowników, link zaproszenia i stan widoków ładują
    /// ekrany przy pierwszym wyborze (`.task`, `onChange(of:initial:)`).
    private func prepareUnbuiltTabs() {
        guard let agentStore, dashboardTab != .assistant else { return }
        Task { _ = await agentStore.loadUsage() }
        Task { await agentStore.openIfNeeded() }
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
        async let weekReady: Void = prepareCurrentWeek()
        _ = await (recipesReady, householdReady, weekReady)
    }

    /// Katalog i miniatury: start czeka na pierwsze `startupThumbnailCount`,
    /// reszta trafia w tle na dysk (najwyżej kilka naraz, bez pamięci). Pamięć mieści ~256
    /// miniatur, a katalog ma ich ponad tysiąc — czekanie na wszystkie
    /// wydłużało loader i przy zimnym starcie (świeża instalacja, App Review)
    /// piętrzyło pobrane bajty aż do WatchdogTermination (27–30.09.2026).
    /// Po pierwszym pobraniu każda miniatura leży na dysku jako mały JPEG,
    /// więc lista dociąga brakujące w ułamku sekundy.
    private func prepareRecipesAndThumbnails() async {
        guard let catalog = recipeCatalogStore else { return }
        await catalog.loadIfNeeded()
        let urls = catalog.recipes.compactMap(\.imageURL)
        await ImagePrefetcher.prefetchAwaiting(Array(urls.prefix(Self.startupThumbnailCount)))
        // Reszta tylko na dysk — pamięć zostaje dla tych, które widać.
        ImagePrefetcher.warmDisk(Array(urls.dropFirst(Self.startupThumbnailCount)))
    }

    private static let startupThumbnailCount = 160

    /// Bieżący tydzień planu — Kalendarz i Plan stoją na nim od pierwszej
    /// klatki. Przepisy gospodarstwa (spoza katalogu) mają własne zdjęcia,
    /// więc ich miniatury też czekają tutaj.
    private func prepareCurrentWeek() async {
        guard let mealStore = mealCalendarStore else { return }
        let dates = datesViewModel.dates
        await mealStore.loadWeekPlanFromBackend(weekStart: datesViewModel.weekStartISO, dates: dates)
        let urls = dates
            .flatMap { date in MealSlot.allCases.flatMap { mealStore.meals(for: date, slot: $0) } }
            .compactMap(\.recipe.imageURL)
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
    // 7.10.2026: profil, dieta i dane konta leżą w `SCProtectedSettings`
    // (chroniony plik poza kopią zapasową), widoki czytają je przez
    // `@ProtectedSetting` — „AppStorage” niżej znaczy dziś ten magazyn.
    // W `UserDefaults` zostały tylko niewrażliwe klucze (powiadomienia,
    // `sexClearPending`, wygaszone „Czego nie jem”).
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
        /// „Nie podaję”, którego serwer jeszcze nie potwierdził (zapis padł) —
        /// ponawiane przy każdym kolejnym zapisie profilu. Inne pola leczą się
        /// same, bo zapis wysyła ich lokalną wartość; skasowanie płci — nie.
        static let sexClearPending = "settings.profile.sexClearPending"
    }

    private func persistProfileFields(
        yearOfBirth: Int?,
        heightCm: Int?,
        weightKg: Double?,
        sex: String?
    ) {
        let defaults = UserDefaults.standard
        if let yearOfBirth { SCProtectedSettings.shared.set(yearOfBirth, forKey: ProfileKeys.yearOfBirth) }
        if let heightCm { SCProtectedSettings.shared.set(heightCm, forKey: ProfileKeys.heightCm) }
        if let weightKg { SCProtectedSettings.shared.set(weightKg, forKey: ProfileKeys.weightKg) }
        // Backend oddaje `MALE` / `FEMALE`, iOS trzyma małymi literami —
        // ta sama konwencja co przy diecie i celu. `users:me` (jedyne wywołanie)
        // oddaje płeć ZAWSZE, `null` gdy jej nie podano — brak to więc fakt:
        // „Nie podaję” wybrane na innym telefonie kasuje tu zapamiętaną płeć,
        // inaczej następna edycja sylwetki odesłałaby starą z powrotem.
        if let sex {
            // Niepotwierdzone „Nie podaję” wygrywa ze starą płcią z serwera,
            // dopóki zapis go nie ponowi — inaczej arkusz pokazałby ją z powrotem.
            if defaults.string(forKey: ProfileKeys.sexClearPending) == nil {
                SCProtectedSettings.shared.set(sex.lowercased(), forKey: ProfileKeys.sex)
            }
        } else {
            // Flagi NIE zdejmujemy: spóźniony odczyt z `null` sprzed nowszego
            // „Nie podaję” skasowałby jej znacznik. Zdejmuje ją tylko
            // potwierdzony zapis (ponowny `null` serwerowi nie szkodzi).
            SCProtectedSettings.shared.removeObject(forKey: ProfileKeys.sex)
        }
    }

    private func clearPersistedProfileFields() {
        let defaults = UserDefaults.standard
        SCProtectedSettings.shared.removeObject(forKey: ProfileKeys.yearOfBirth)
        SCProtectedSettings.shared.removeObject(forKey: ProfileKeys.heightCm)
        SCProtectedSettings.shared.removeObject(forKey: ProfileKeys.weightKg)
        SCProtectedSettings.shared.removeObject(forKey: ProfileKeys.sex)
        defaults.removeObject(forKey: ProfileKeys.sexClearPending)
    }

    /// Pull the user's preferences row from the backend and write into
    /// AppStorage. Silent on failure — local cache stays as fallback so
    /// the UI keeps working offline.
    ///
    /// Jeden odczyt naraz na konto (7.10.2026, Codex runda 2): start sesji,
    /// powrót na pierwszy plan i `ensurePreferencesBaseline` czekają na TO SAMO
    /// zadanie. Dwa równoległe odczyty dawały dwie migawki, a spóźniona starsza
    /// nadpisywała nowszą edycję i arkusz diety odsyłał ją na serwer.
    @MainActor
    @discardableResult
    func loadUserPreferences() async -> Bool {
        guard let userId = currentUserId, !userId.isEmpty else { return false }
        if let running = preferencesReadTask, preferencesReadUserId == userId {
            return await running.value
        }
        let epoch = sessionEpoch
        let task = Task { @MainActor [weak self] () -> Bool in
            guard let self else { return false }
            return await self.performPreferencesRead(userId: userId, epoch: epoch)
        }
        preferencesReadTask = task
        preferencesReadUserId = userId
        let loaded = await task.value
        if preferencesReadTask == task {
            preferencesReadTask = nil
            preferencesReadUserId = nil
        }
        return loaded
    }

    /// Właściwy odczyt — woła go tylko `loadUserPreferences` (jedno zadanie).
    /// Nie woła `ensurePreferencesBaseline` (ani nic, co czeka na odczyt),
    /// więc zadanie nigdy nie czeka samo na siebie.
    @MainActor
    private func performPreferencesRead(userId: String, epoch: Int) async -> Bool {
        // W kolejce diety: zapis w locie kończy się, zanim odczyt zapyta
        // serwer. Sprzątanie „Czego nie jem” to zapis — idzie PO wyjściu
        // z kolejki (inaczej czekałoby na samo siebie).
        let queue = preferencesSyncQueue
        await queue.enter()
        let outcome = await readPreferencesInQueue(userId: userId, epoch: epoch)
        queue.leave()
        guard let hasLegacyRestrictions = outcome, sessionEpoch == epoch else { return false }
        if hasLegacyRestrictions {
            await saveUserPreferences(
                excludedIngredientIds: [],
                clearMaxPrepTime: true,
                confirmBaselineFirst: false
            )
        }
        return true
    }

    /// Sam odczyt, już w kolejce. `nil` = nieudany albo pominięty; inaczej:
    /// czy na serwerze zostały wygaszone ograniczenia „Czego nie jem”.
    @MainActor
    private func readPreferencesInQueue(userId: String, epoch: Int) async -> Bool? {
        // Wylogowanie w czasie czekania w kolejce — nic nie pytamy.
        guard sessionEpoch == epoch, currentUserId == userId else { return nil }
        let protectedStore = SCProtectedSettings.shared
        let generationAtStart = protectedStore.changeGeneration(.preferences)
        let socket = sessionSocket()

        do {
            let envelope: WsEnvelope<BackendUserPreferencesDTO> = try await socket.emitWithAck(
                event: "users:preferences:get",
                payload: ["userId": userId],
                as: WsEnvelope<BackendUserPreferencesDTO>.self
            )
            guard envelope.ok, let prefs = envelope.data else { return nil }
            // Odpowiedź po wylogowaniu / zmianie konta nie jest już nasza.
            guard sessionEpoch == epoch, currentUserId == userId else { return nil }
            // W trakcie odczytu była edycja z ręki — migawka serwera jest
            // starsza niż telefon. Nie nadpisujemy i NIE potwierdzamy (lokalne
            // wartości nie pochodzą z tej odpowiedzi).
            guard protectedStore.changeGeneration(.preferences) == generationAtStart else {
                debugLog("[SessionStore] users:preferences:get — odpowiedź starsza niż lokalna zmiana, pomijam")
                return nil
            }

            let hasLegacyRestrictions = applyPreferencesSnapshot(prefs)

            // Lokalna kopia = wiersz z serwera: od teraz wolno wysyłać z niej
            // pełny zestaw (`ensurePreferencesBaseline`, 7.10.2026), a listy
            // przepisów mogą jej ufać (`preferencesAvailability`).
            preferencesConfirmedForUserId = userId
            SCProtectedSettings.shared.markPreferencesTrusted()
            return hasLegacyRestrictions
        } catch {
            // Swallow — preferences are non-critical, AppStorage default
            // applies. Ponowienie: przy wejściu na pierwszy plan
            // (`refreshRealtimeStoresOnForeground`) i przed każdym zapisem
            // pełnego zestawu (`ensurePreferencesBaseline`).
            return nil
        }
    }

    /// Wpisuje wiersz preferencji z serwera do lokalnej kopii (odczyt albo
    /// odpowiedź na udany zapis). Zwraca, czy na serwerze zostały wygaszone
    /// ograniczenia „Czego nie jem” do skasowania. Bez liczników edycji —
    /// to hydratacja, nie zmiana z ręki, więc arkusze nie zapisują jej z powrotem.
    @MainActor
    @discardableResult
    private func applyPreferencesSnapshot(_ prefs: BackendUserPreferencesDTO) -> Bool {
        let defaults = UserDefaults.standard
        for (key, value) in Self.preferencesLocalValues(prefs) {
            SCProtectedSettings.shared.setValue(value, forKey: key)
        }

        // „Czego nie jem” (wykluczone składniki i limit czasu na danie)
        // zniknęło z aplikacji 23.09.2026 — wykluczanie składników żyje
        // teraz w filtrach przepisów. Kolumny na serwerze zostały, a
        // walidator planu dalej odrzuca przez nie dania; bez ekranu nikt
        // by takiej blokady nie zobaczył ani nie zdjął. Sprzątamy więc
        // wartości zapisane wcześniej: lokalnie od razu, na serwerze
        // jednym zapisem na końcu odczytu.
        defaults.removeObject(forKey: PreferencesKeys.excludedIngredients)
        defaults.removeObject(forKey: PreferencesKeys.maxPrepTimeMinutes)
        let hasLegacyRestrictions = !(prefs.excludedIngredientIds ?? []).isEmpty
            || prefs.maxPrepTimeMinutes != nil

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

        return hasLegacyRestrictions
    }

    /// Wiersz preferencji z serwera w postaci lokalnej kopii — JEDNO miejsce
    /// tłumaczenia (odczyt i odpowiedź na zapis). Wartość `nil` = usuń klucz;
    /// brak klucza w słowniku = nie ruszaj (np. nieznana dieta).
    private static func preferencesLocalValues(_ prefs: BackendUserPreferencesDTO) -> [String: SCProtectedValue?] {
        var values: [String: SCProtectedValue?] = [:]
        // Przez `backendValue`, nie przez `lowercased()` — patrz komentarz
        // przy `DietPreference.backendValue`.
        if let diet = DietPreference(backendValue: prefs.dietPreference) {
            values.updateValue(SCProtectedValue.string(diet.rawValue), forKey: PreferencesKeys.diet)
        }
        values.updateValue(SCProtectedValue.int(prefs.calorieGoal), forKey: PreferencesKeys.calorieGoal)
        values.updateValue(
            SCProtectedValue.string(prefs.allergens.map { $0.lowercased() }.sorted().joined(separator: ",")),
            forKey: PreferencesKeys.allergens
        )
        values.updateValue(SCProtectedValue.string(prefs.goal.lowercased()), forKey: PreferencesKeys.goal)
        values.updateValue(SCProtectedValue.int(prefs.activityLevel), forKey: PreferencesKeys.activityLevel)
        // −1 to sentinel „licz za mnie" po stronie iOS; backend trzyma
        // tam `null`. Tłumaczenie w obie strony siedzi wyłącznie tutaj.
        values.updateValue(SCProtectedValue.int(prefs.proteinG ?? -1), forKey: PreferencesKeys.proteinG)
        values.updateValue(SCProtectedValue.int(prefs.fatG ?? -1), forKey: PreferencesKeys.fatG)
        values.updateValue(SCProtectedValue.int(prefs.carbsG ?? -1), forKey: PreferencesKeys.carbsG)
        return values
    }

    /// Pole w `data` zapisu preferencji → klucz lokalnej kopii.
    private static let preferencesPayloadKeys: [String: String] = [
        "dietPreference": PreferencesKeys.diet,
        "calorieGoal": PreferencesKeys.calorieGoal,
        "allergens": PreferencesKeys.allergens,
        "goal": PreferencesKeys.goal,
        "activityLevel": PreferencesKeys.activityLevel,
        "proteinG": PreferencesKeys.proteinG,
        "fatG": PreferencesKeys.fatG,
        "carbsG": PreferencesKeys.carbsG,
    ]

    /// Lokalne wartości podanych kluczy w chwili wysłania zapisu.
    private static func protectedValues(of keys: [String]) -> [String: SCProtectedValue?] {
        var values: [String: SCProtectedValue?] = [:]
        for key in keys {
            // `updateValue`, nie `values[key] = …` — przypisanie `nil` przez
            // indeks USUWA klucz, a tu `nil` („brak wartości”) też jest stanem.
            values.updateValue(SCProtectedSettings.shared.value(forKey: key), forKey: key)
        }
        return values
    }

    /// Odpowiedź na udany zapis (7.10.2026, Codex runda 3): wpisuje wartości
    /// serwera TYLKO dla kluczy, które ten zapis wysłał, i tylko tam, gdzie
    /// lokalna wartość od wysłania się nie zmieniła. Reszta wiersza z
    /// odpowiedzi jest ignorowana — częściowy zapis (np. sama aktywność z
    /// „Twoich danych”) nie może nadpisać niezapisanej jeszcze zmiany alergenów.
    /// Zwraca, czy WSZYSTKIE wysłane klucze były od wysłania nietknięte.
    @MainActor
    @discardableResult
    private func mergeSavedValues(
        sent: [String: SCProtectedValue?],
        server: [String: SCProtectedValue?]
    ) -> Bool {
        let store = SCProtectedSettings.shared
        var untouched = true
        for (key, sentValue) in sent {
            guard store.value(forKey: key) == sentValue else {
                untouched = false
                continue
            }
            if let serverValue = server[key] {
                store.setValue(serverValue, forKey: key)
            }
        }
        return untouched
    }

    /// Czy listy przepisów znają dietę i alergeny (7.10.2026, Codex runda 4).
    enum PreferencesAvailability {
        /// Jest lokalna kopia albo potwierdzony odczyt — zwykły stan.
        case ready
        /// Brak lokalnej kopii, odczyt z serwera trwa.
        case loading
        /// Brak lokalnej kopii, ostatni odczyt się nie udał.
        case unavailable
    }

    /// Bez lokalnej kopii diety (odtworzony telefon, reinstalacja — plik
    /// ustawień nie jedzie w kopii zapasowej) puste alergeny NIE znaczą „bez
    /// alergii”. Listy przepisów mówią to wprost (`RecipePreferencesNotice`).
    /// Po aktualizacji aplikacji kopia jest (migracja), więc `.ready` od razu;
    /// bez zalogowanego konta też `.ready` — nie ma czego pokazywać.
    var preferencesAvailability: PreferencesAvailability {
        guard let userId = currentUserId, !userId.isEmpty else { return .ready }
        if preferencesConfirmedForUserId == userId || SCProtectedSettings.shared.hasTrustedPreferences {
            return .ready
        }
        return preferencesReadTask != nil ? .loading : .unavailable
    }

    /// Wynik `ensurePreferencesBaseline` / `ensureProfileBaseline`.
    enum ServerBaseline {
        /// Lokalna kopia potwierdzona odczytem z serwera — można wysyłać.
        case confirmed
        /// Kopia była niepotwierdzona i właśnie wczytała się z serwera. Zapis
        /// zbudowany na starej kopii NIE wychodzi — ekran pokazuje teraz
        /// prawdziwe wartości, użytkownik powtarza zmianę.
        case reloaded
        /// Nie udało się wczytać — nic nie wysyłamy.
        case unavailable
    }

    /// Strażnik przed wysłaniem pustych alergenów (7.10.2026, Codex do audytu
    /// 2.5). Chroniony plik ustawień nie jedzie w kopii zapasowej, a Keychain
    /// przeżywa reinstalację — sesja potrafi więc wstać z PUSTĄ lokalną kopią
    /// diety, a odczyt `users:preferences:get` przy starcie bywa nieudany
    /// (sieć). Ekran diety wysyła zawsze pełny zestaw, więc zmiana samych
    /// kalorii wysłałaby `allergens: []` i skasowała alergeny z konta.
    /// Pełny zestaw wychodzi więc tylko z kopii potwierdzonej odczytem z
    /// serwera w TYM procesie dla TEGO konta; w przeciwnym razie najpierw
    /// odczyt. Ten sam błąd istniał przed 7.10.2026 przy reinstalacji
    /// (Keychain zostaje, `UserDefaults` nie) i przy nieudanym odczycie po
    /// zalogowaniu na nowym telefonie.
    @MainActor
    func ensurePreferencesBaseline() async -> ServerBaseline {
        guard let userId = currentUserId, !userId.isEmpty else { return .unavailable }
        if preferencesConfirmedForUserId == userId { return .confirmed }
        let loaded = await loadUserPreferences()
        guard loaded, preferencesConfirmedForUserId == userId else { return .unavailable }
        return .reloaded
    }

    /// To samo dla sylwetki (rok, wzrost, waga, płeć) i imienia — „Twoje dane”
    /// wysyłają zawsze cały zestaw z lokalnej kopii, a ta po odtworzeniu
    /// telefonu albo reinstalacji jest pusta (wartości domyślne arkusza), dopóki
    /// nie dojdzie `users:me` (7.10.2026). Potwierdza `restoreHouseholdIfNeeded`
    /// (start sesji, logowanie, ponowienie przy wejściu na pierwszy plan).
    @MainActor
    func ensureProfileBaseline() async -> ServerBaseline {
        guard let userId = currentUserId, !userId.isEmpty else { return .unavailable }
        if profileConfirmedForUserId == userId { return .confirmed }
        await restoreHouseholdIfNeeded()
        guard profileConfirmedForUserId == userId else { return .unavailable }
        return .reloaded
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
        clearMacroOverrides: Bool = false,
        /// `false` tylko dla zapisu, który NIE pochodzi z lokalnej kopii
        /// preferencji: kreator (formularz, który użytkownik właśnie wypełnił)
        /// i sprzątanie „Czego nie jem” po udanym odczycie. Patrz
        /// `ensurePreferencesBaseline`.
        confirmBaselineFirst: Bool = true
    ) async -> Bool {
        guard let userId = currentUserId, !userId.isEmpty else { return false }
        let epoch = sessionEpoch
        // Zestaw zbudowany na niepotwierdzonej kopii (np. puste alergeny po
        // odtworzeniu telefonu) nie ma prawa nadpisać konta (7.10.2026).
        if confirmBaselineFirst, await ensurePreferencesBaseline() != .confirmed {
            return false
        }
        // Po strażniku, nie przed nim: jego odczyt sam wchodzi do kolejki.
        let queue = preferencesSyncQueue
        await queue.enter()
        defer { queue.leave() }
        // Wylogowanie w czasie czekania — zapis należy do starej sesji: nic
        // lokalnie, nic na serwer. Dalej do `emitWithAck` nie ma już `await`.
        guard sessionEpoch == epoch, currentUserId == userId else { return false }
        // Trwające odczyty są od teraz starsze niż telefon (7.10.2026).
        SCProtectedSettings.shared.noteLocalSave(.preferences)

        // Mirror to AppStorage so the welcome flow survives a kill-restart
        // mid-flow and SettingsView reads the latest values without a
        // round-trip. Settings already drives @AppStorage directly, so
        // writing the same keys here is idempotent.
        let defaults = UserDefaults.standard
        var data: [String: Any] = [:]
        if let diet, let preference = DietPreference(rawValue: diet) {
            data["dietPreference"] = preference.backendValue
            SCProtectedSettings.shared.set(preference.rawValue, forKey: PreferencesKeys.diet)
        }
        if let calorieGoal {
            data["calorieGoal"] = calorieGoal
            SCProtectedSettings.shared.set(calorieGoal, forKey: PreferencesKeys.calorieGoal)
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
            SCProtectedSettings.shared.set(
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
            SCProtectedSettings.shared.set(goal.lowercased(), forKey: PreferencesKeys.goal)
        }
        if let activityLevel {
            data["activityLevel"] = activityLevel
            SCProtectedSettings.shared.set(activityLevel, forKey: PreferencesKeys.activityLevel)
        }
        if clearMacroOverrides {
            data["proteinG"] = NSNull()
            data["fatG"] = NSNull()
            data["carbsG"] = NSNull()
            SCProtectedSettings.shared.set(-1, forKey: PreferencesKeys.proteinG)
            SCProtectedSettings.shared.set(-1, forKey: PreferencesKeys.fatG)
            SCProtectedSettings.shared.set(-1, forKey: PreferencesKeys.carbsG)
        } else {
            if let proteinG {
                data["proteinG"] = proteinG
                SCProtectedSettings.shared.set(proteinG, forKey: PreferencesKeys.proteinG)
            }
            if let fatG {
                data["fatG"] = fatG
                SCProtectedSettings.shared.set(fatG, forKey: PreferencesKeys.fatG)
            }
            if let carbsG {
                data["carbsG"] = carbsG
                SCProtectedSettings.shared.set(carbsG, forKey: PreferencesKeys.carbsG)
            }
        }
        guard !data.isEmpty else { return true }
        let sentKeys = data.keys.compactMap { Self.preferencesPayloadKeys[$0] }
        let sentValues = Self.protectedValues(of: sentKeys)
        // Zapis z alergenami i dietą (ekran diety, kreator) — to, co chroni
        // strażnik i czym listy odsiewają przepisy.
        let sendsAllergensAndDiet = sentKeys.contains(PreferencesKeys.allergens)
            && sentKeys.contains(PreferencesKeys.diet)

        let socket = sessionSocket()

        do {
            let envelope: WsEnvelope<BackendUserPreferencesDTO> = try await socket.emitWithAck(
                event: "users:preferences:update",
                payload: ["userId": userId, "data": data],
                as: WsEnvelope<BackendUserPreferencesDTO>.self
            )
            // Z odpowiedzi tylko WYSŁANE pola, nietknięte od wysłania
            // (`mergeSavedValues`). Udany zapis alergenów i diety bez zmiany
            // od wysłania = kopia alergenów jest stanem konta → znacznik
            // zaufanej kopii (listy przepisów). Bezpieczne, bo zapisy i odczyty
            // diety idą po kolei (`preferencesSyncQueue`). Bramki pełnego
            // zapisu (`preferencesConfirmedForUserId`) to nie zdejmuje — tę
            // daje tylko odczyt (zapis nie mówi nic o polach, których nie wysłał).
            if envelope.ok, let saved = envelope.data, sessionEpoch == epoch, currentUserId == userId {
                let untouched = mergeSavedValues(
                    sent: sentValues,
                    server: Self.preferencesLocalValues(saved)
                )
                if sendsAllergensAndDiet, untouched {
                    SCProtectedSettings.shared.markPreferencesTrusted()
                }
            }
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

    /// „Nie podaję” zatwierdzone w kreatorze — zamiar skasowania płci od razu
    /// w pliku, zanim zapis wejdzie do `profileSyncQueue` (7.10.2026, Codex
    /// runda 2). Ten sam znacznik `sexClearPending`, którym żyje „Twoje dane”:
    /// przeżywa zabicie aplikacji, każdy następny `saveProfile` bez płci
    /// wysyła `null`, `users:me` nie przywraca starej płci, a zdejmuje go
    /// dopiero zapis potwierdzony przez serwer albo wybór płci.
    @MainActor
    func markSexClearPending() {
        guard let userId = currentUserId, !userId.isEmpty else { return }
        if UserDefaults.standard.string(forKey: ProfileKeys.sexClearPending) == nil {
            UserDefaults.standard.set(UUID().uuidString, forKey: ProfileKeys.sexClearPending)
        }
        SCProtectedSettings.shared.removeObject(forKey: ProfileKeys.sex)
    }

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
        sex: String? = nil,
        /// „Nie podaję” w „Twoich danych” — jawny `null` dla płci. Pominięte
        /// pole znaczy dla serwera „nie ruszaj”, więc bez tego stara płeć
        /// zostawała w bazie i wracała z `users:me` po ponownym uruchomieniu.
        clearSex: Bool = false,
        /// `false` tylko dla kreatora (formularz, który użytkownik właśnie
        /// wypełnił). Patrz `ensureProfileBaseline`.
        confirmBaselineFirst: Bool = true
    ) async -> Bool {
        guard let userId = currentUserId, !userId.isEmpty else { return false }
        let epoch = sessionEpoch
        // Znacznik „Nie podaję” w chwili WYWOŁANIA — porównywany po wejściu
        // do kolejki (patrz gałąź z płcią niżej).
        let sexClearAtCall = UserDefaults.standard.string(forKey: ProfileKeys.sexClearPending)
        // Sylwetka z niepotwierdzonej kopii (wartości domyślne po odtworzeniu
        // telefonu) nie nadpisuje konta (7.10.2026). Niepotwierdzone „Nie
        // podaję” (`sexClearPending`) nie ginie: flaga zostaje i jedzie z
        // następnym zapisem, a `persistProfileFields` jej pilnuje.
        if confirmBaselineFirst, await ensureProfileBaseline() != .confirmed {
            return false
        }
        // Po strażniku, nie przed nim: jego `users:me` sam wchodzi do kolejki.
        let queue = profileSyncQueue
        await queue.enter()
        defer { queue.leave() }
        // Wylogowanie w czasie czekania — nic do pliku, żadnego
        // `sexClearPending`, nic na serwer. Dalej do `emitWithAck` bez `await`.
        guard sessionEpoch == epoch, currentUserId == userId else { return false }
        // Trwające `users:me` są od teraz starsze niż telefon (7.10.2026).
        SCProtectedSettings.shared.noteLocalSave(.profile)

        var data: [String: Any] = [:]
        if let displayName {
            let trimmed = Self.limitedDisplayName(
                displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if !trimmed.isEmpty {
                data["displayName"] = trimmed
                SCProtectedSettings.shared.set(trimmed, forKey: Keys.displayName)
            }
        }
        if let yearOfBirth {
            data["yearOfBirth"] = yearOfBirth
            SCProtectedSettings.shared.set(yearOfBirth, forKey: ProfileKeys.yearOfBirth)
        }
        if let heightCm {
            data["heightCm"] = heightCm
            SCProtectedSettings.shared.set(heightCm, forKey: ProfileKeys.heightCm)
        }
        if let weightKg {
            // Jedno miejsce po przecinku — tyle waliduje backend i tyle
            // pokazuje pole. Bez tego 83.30000000000001 z arytmetyki Double
            // wywracałoby walidację `maxDecimalPlaces: 1`.
            let rounded = (weightKg * 10).rounded() / 10
            data["weightKg"] = rounded
            SCProtectedSettings.shared.set(rounded, forKey: ProfileKeys.weightKg)
        }
        // Skasowanie płci: wybrane teraz albo niepotwierdzone z wcześniejszego
        // zapisu, który padł (`sexClearPending`) — ponawiamy je, dopóki serwer
        // nie potwierdzi, chyba że w międzyczasie wybrano płeć. Każde nowe
        // skasowanie dostaje własny znacznik: spóźnione potwierdzenie STARSZEGO
        // zapisu nie zdejmie flagi nowszego, który jeszcze nie doszedł.
        let pendingClear = UserDefaults.standard.string(forKey: ProfileKeys.sexClearPending)
        var clearToken: String?
        if clearSex || ((sex ?? "").isEmpty && pendingClear != nil) {
            let token = clearSex ? UUID().uuidString : (pendingClear ?? UUID().uuidString)
            clearToken = token
            data["sex"] = NSNull()
            SCProtectedSettings.shared.removeObject(forKey: ProfileKeys.sex)
            UserDefaults.standard.set(token, forKey: ProfileKeys.sexClearPending)
        } else if let sex, !sex.isEmpty, pendingClear == sexClearAtCall {
            data["sex"] = sex.uppercased()
            SCProtectedSettings.shared.set(sex.lowercased(), forKey: ProfileKeys.sex)
            UserDefaults.standard.removeObject(forKey: ProfileKeys.sexClearPending)
        }
        // Płeć z wywołania, po którym (w czasie czekania w kolejce) padło
        // nowsze „Nie podaję” (inny znacznik niż przy wywołaniu): ten zapis
        // płci nie wysyła i znacznika nie zdejmuje — nowszy zamiar wygrywa
        // (7.10.2026, Codex runda 3).
        guard !data.isEmpty else { return true }
        var sentProfileKeys: [String] = []
        if data["displayName"] != nil { sentProfileKeys.append(Keys.displayName) }
        if data["yearOfBirth"] != nil { sentProfileKeys.append(ProfileKeys.yearOfBirth) }
        if data["heightCm"] != nil { sentProfileKeys.append(ProfileKeys.heightCm) }
        if data["weightKg"] != nil { sentProfileKeys.append(ProfileKeys.weightKg) }
        if data["sex"] != nil { sentProfileKeys.append(ProfileKeys.sex) }
        let sentValues = Self.protectedValues(of: sentProfileKeys)
        // Pełny zestaw sylwetki i imienia — tylko on może potwierdzić kopię.
        let isFullSet = sentProfileKeys.count == 5

        let socket = sessionSocket()

        do {
            let envelope: WsEnvelope<BackendUserProfileDTO> = try await socket.emitWithAck(
                event: "users:profile:update",
                payload: ["userId": userId, "data": data],
                as: WsEnvelope<BackendUserProfileDTO>.self
            )
            if envelope.ok, let clearToken, sessionEpoch == epoch,
               UserDefaults.standard.string(forKey: ProfileKeys.sexClearPending) == clearToken {
                UserDefaults.standard.removeObject(forKey: ProfileKeys.sexClearPending)
            }
            // Z odpowiedzi tylko WYSŁANE pola, nietknięte od wysłania — jak
            // przy preferencjach (7.10.2026, Codex runda 3). Płeć: nowsze
            // „Nie podaję” zmieniło lokalną wartość, więc zostaje nietknięte
            // (a jego `sexClearPending` żyje dalej). Potwierdza tylko pełny
            // zestaw bez zmian w międzyczasie.
            if envelope.ok, let saved = envelope.data, sessionEpoch == epoch, currentUserId == userId {
                var server: [String: SCProtectedValue?] = [:]
                server.updateValue(SCProtectedValue.string(saved.displayName), forKey: Keys.displayName)
                if let year = saved.yearOfBirth {
                    server.updateValue(SCProtectedValue.int(year), forKey: ProfileKeys.yearOfBirth)
                }
                if let height = saved.heightCm {
                    server.updateValue(SCProtectedValue.int(height), forKey: ProfileKeys.heightCm)
                }
                if let weight = saved.weightKg {
                    server.updateValue(SCProtectedValue.double(weight), forKey: ProfileKeys.weightKg)
                }
                server.updateValue(saved.sex.map { SCProtectedValue.string($0.lowercased()) }, forKey: ProfileKeys.sex)
                let untouched = mergeSavedValues(sent: sentValues, server: server)
                if isFullSet, untouched {
                    profileConfirmedForUserId = userId
                }
            }
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

    /// 7.10.2026 (audyt 2.5): katalog offline poza kopią zapasową, nie
    /// `Documents` — stary plik przenosi `AppCacheDirectory`.
    private var householdMembersCacheURL: URL {
        AppCacheDirectory.url(for: "household_members_cache_v1.json")
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

    /// Także ze starego `Documents` (7.10.2026), gdyby migracja go nie przeniosła.
    private func clearHouseholdMembersCache() {
        AppCacheDirectory.removeEverywhere(householdMembersCacheURL.lastPathComponent)
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
    /// Wejście na pierwszy plan odświeża parę tokenów TYLKO wtedy, gdy do
    /// wygaśnięcia zostało mniej niż tyle.
    ///
    /// PIĘĆ MINUT, nie tydzień. Tydzień pochodził z czasów, gdy access token
    /// żył 30 dni; od audytu 5.09.2026 żyje GODZINĘ, więc warunek „mniej niż
    /// tydzień do wygaśnięcia" był zawsze prawdziwy i KAŻDE wejście na
    /// pierwszy plan — także obudzenie cichym pushem w tle — rotowało refresh
    /// token. A rotacja w tle bywa przerwana uśpieniem procesu: serwer token
    /// obraca, odpowiedź nie dojeżdża, w Keychain zostaje stary i następny
    /// start wygląda jak kradzież. Stąd „Sesja wygasła" po dłuższej przerwie
    /// od aplikacji. Serwer ratuje taką turę oknem łaski
    /// (`REFRESH_REUSE_GRACE_SECONDS`), ale pierwszym lekarstwem jest nie
    /// rotować bez potrzeby.
    ///
    /// Sama ta liczba nie wystarcza: sesja, która ani razu nie schodzi na
    /// drugi plan, nie ma czego wyzwolić i po godzinie dostaje 401. Od tego
    /// jest `armProactiveRefresh` — para dla tego okna, nie jego zamiennik.
    private static let proactiveRefreshWindow: TimeInterval = 5 * 60
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
    /// Konto, którego preferencje (dieta, alergeny, kcal, cel, makra,
    /// aktywność) wczytały się w tym procesie z serwera — patrz
    /// `ensurePreferencesBaseline` (7.10.2026). Celowo tylko w pamięci:
    /// każdy start sesji potwierdza kopię od nowa, a plik ustawień i tak
    /// nie przeżywa kopii zapasowej ani reinstalacji.
    private var preferencesConfirmedForUserId: String?
    /// Konto, którego sylwetka przyszła w tym procesie z `users:me` — patrz
    /// `ensureProfileBaseline` (7.10.2026). Też tylko w pamięci.
    private var profileConfirmedForUserId: String?
    /// Trwający odczyt preferencji / `users:me` — jeden na konto (7.10.2026).
    private var preferencesReadTask: Task<Bool, Never>?
    private var preferencesReadUserId: String?
    private var householdRestoreTask: Task<Void, Never>?
    private var householdRestoreUserId: String?
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
        // ROTACJA MUSI SIĘ DOKOŃCZYĆ, RAZ ZACZĘTA.
        //
        // Serwer unieważnia stary token w chwili, gdy wydaje nowy — więc od
        // wysłania żądania do zapisu odpowiedzi w Keychainie jest okno, w
        // którym uśpienie procesu kosztuje CAŁĄ SESJĘ: telefon zostaje ze
        // zrotowanym tokenem i przy następnym uruchomieniu wygląda dla serwera
        // na kradzież. Najłatwiej wejść w to okno po cichym pushu (system
        // uznaje pracę za skończoną, gdy wraca `completionHandler`), ale wpada
        // się w nie też terminem `armProactiveRefresh`, który trafi w moment
        // schodzenia w tło.
        //
        // Asercja obejmuje ŻĄDANIE RAZEM Z ZAPISEM, nie samo żądanie — to
        // zapis jest tu rzeczą nieodwracalną.
        let activity = BackgroundActivity.begin(name: "session-token-refresh")
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
                // REFRESH TOKEN PIERWSZY — i w OSOBNYM `guard`, nie jako drugi
                // warunek obok access tokenu. Jedno i drugie z tego samego
                // powodu.
                //
                // Serwer zrotował parę, więc token, którym właśnie się
                // posłużyliśmy, jest już martwy: jedyne, co trzyma sesję, to
                // nowy refresh token. Stan, którego trzeba za wszelką cenę
                // uniknąć, to ŚWIEŻY access token obok MARTWEGO refresh tokenu
                // — bo on wygląda zdrowo przez godzinę i pęka dopiero potem.
                // Można w niego wejść na dwa sposoby i oba są tu zamknięte:
                // proces ginie między zapisami (iOS ubija aplikację w tle,
                // aktualizacja z TestFlighta) albo zapis refresh tokenu pada,
                // a zapis access tokenu przechodzi.
                //
                // Ten drugi sposób jest gorszy, bo cichy i systematyczny:
                // `armProactiveRefresh` czyta `exp` ze świeżo zapisanego access
                // tokenu, więc następną próbę uzbraja dopiero za ~55 minut.
                // Godzinę później telefon pokazuje serwerowi zrotowany token
                // grubo POZA oknem łaski (60 s), a to dla backendu nie jest
                // zgubiona odpowiedź, tylko kradzież: `revokeTokenFamily`
                // kasuje rodzinę, podbija `tokenVersion` i zrywa socket na
                // WSZYSTKICH urządzeniach. Czyli dokładnie „wylogowanie po
                // godzinie" — objaw, który ta poprawka miała usunąć, gdyby
                // oba zapisy szły bezwarunkowo.
                guard await Self.persistRefreshToken(pair.refreshToken) else {
                    // Nie zapisaliśmy następcy, więc w Keychainie został token,
                    // który serwer właśnie zrotował. Backend oddałby za niego
                    // świeżą parę, dopóki nikt nie użył następcy — ale tylko
                    // przez okno łaski, a nasze jedyne automatyczne ponowienie
                    // (`minProactiveRefreshDelay`) celuje dokładnie w jego
                    // granicę. Kończymy więc sesję CZYSTO i od razu, zamiast
                    // zostawiać ponowienie, które z równym prawdopodobieństwem
                    // wyglądałoby dla serwera na kradzież i zabrało ze sobą
                    // sesje na pozostałych urządzeniach.
                    debugLog(
                        "[SessionStore] refreshSessionTokens — REFRESH TOKEN NOT PERSISTED, ending session"
                    )
                    return .rejected
                }
                // Access token jest odzyskiwalny: gdy jego zapis padnie,
                // w Keychainie zostaje stary (najwyżej wygasły) obok ŚWIEŻEGO
                // refresh tokenu, a z tego stanu wychodzi się jednym
                // odświeżeniem. Dlatego to nie koniec sesji, tylko
                // `.unavailable` — bez udawania, że para jest na miejscu.
                guard KeychainService.save(pair.accessToken, forKey: Keys.accessToken) else {
                    debugLog("[SessionStore] refreshSessionTokens — access token write failed")
                    return .unavailable
                }
                return .refreshed
            } catch AuthAPIError.unauthorized {
                return .rejected
            } catch {
                return .unavailable
            }
        }
        refreshTask = task
        let outcome = await task.value
        activity.end()
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

    /// Zapisuje refresh token, ponawiając próbę GRUBO w oknie łaski serwera.
    ///
    /// Odmowa Keychaina bywa chwilowa (pęcherz zajęty, proces obudzony w złym
    /// momencie), a stawką jest cała sesja — więc jedna próba to za mało.
    /// Trzy podejścia w sumie przez ~0,6 s: to nic wobec 60-sekundowego okna
    /// łaski backendu, w którym zrotowany token da się jeszcze wymienić na
    /// świeżą parę, a jednocześnie nie zamienia odświeżenia w zawieszkę.
    ///
    /// Odstępy rosną, bo jeśli pierwsza próba padła na zajętym pęcherzu, to
    /// druga w tej samej milisekundzie padnie z tego samego powodu.
    private static func persistRefreshToken(_ token: String) async -> Bool {
        for attempt in 0..<3 {
            if KeychainService.save(token, forKey: Keys.refreshToken) { return true }
            guard attempt < 2 else { break }
            // 0,2 s, potem 0,4 s. Jawny typ i jawne liczby, bez przesunięć
            // bitowych: tego pliku nie skompiluję na Windowsie, więc im mniej
            // wnioskowania, tym mniej okazji na literówkę widoczną dopiero w CI.
            let delay: UInt64 = attempt == 0 ? 200_000_000 : 400_000_000
            try? await Task.sleep(nanoseconds: delay)
        }
        return false
    }

    private func refreshSessionTokensIfExpiringSoon() async {
        guard isAuthenticated || currentUserId != nil else { return }
        guard let expiry = accessTokenExpiry() else {
            // Brak access tokenu (albo token bez daty ważności) przy ŻYWYM
            // refresh tokenie to nie jest „nie ma czego pilnować" — to jest
            // jedyny moment, w którym trzeba odświeżyć NATYCHMIAST. Wcześniej
            // ten `guard` wychodził po cichu, więc sesja odzyskana w
            // `restoreSession` bez access tokenu zostawała bez niego na zawsze:
            // każde żądanie 401, a nic nie sięgało po nową parę.
            if currentRefreshToken?.isEmpty == false {
                await refreshSessionTokens()
            }
            return
        }
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
        // Brak `exp` przy ŻYWYM refresh tokenie nie znaczy „nie ma czego
        // pilnować" — znaczy, że nie ma czym wołać i trzeba spróbować jak
        // najszybciej. Ten `guard` wychodził tu po cichu, więc sesja bez access
        // tokenu (nieudany zapis jednej połówki pary) zostawała BEZ TERMINU:
        // nic samo nie sięgało po nową parę aż do następnego wejścia na
        // pierwszy plan. Bez refresh tokenu nadal nie ma czego pilnować.
        let expiry = accessTokenExpiry()
        guard expiry != nil || currentRefreshToken?.isEmpty == false else { return }
        let delay = max(
            (expiry?.timeIntervalSinceNow ?? 0) - Self.proactiveRefreshLead,
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

/// Kolejka FIFO na głównym aktorze: operacje jednej domeny idą po kolei
/// (7.10.2026) — ten sam wzór co `ImageDecodeGate`, z limitem 1. Kto wszedł
/// (`enter`), MUSI wyjść (`leave`, najlepiej w `defer`); wyjście oddaje
/// kolejkę następnemu czekającemu bez zwalniania jej po drodze.
@MainActor
private final class SessionSyncQueue {
    private var isBusy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func leave() {
        if waiting.isEmpty {
            isBusy = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}
