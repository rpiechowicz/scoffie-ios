import Foundation
import UserNotifications

enum NotificationActorFormatter {
    static func firstName(from raw: String?) -> String {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return "Ktoś"
        }

        var candidate = trimmed
        if let atIndex = candidate.firstIndex(of: "@") {
            candidate = String(candidate[..<atIndex])
        }

        let separators = CharacterSet(charactersIn: " \t._-+")
        let token = candidate
            .components(separatedBy: separators)
            .first(where: { !$0.isEmpty }) ?? ""

        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "Ktoś" }

        return cleaned.prefix(1).uppercased() + String(cleaned.dropFirst())
    }
}

/// Identyfikatory wątków powiadomień. Wspólne dla powiadomień lokalnych i dla
/// pushy z backendu (`notifications.service.ts` ustawia `aps.thread-id` tą samą
/// konwencją), żeby system zwijał je w jeden stos zamiast w dwa.
enum NotificationThread {
    static func household(_ householdId: String) -> String { "household-\(householdId)" }
}

/// Prefiksy identyfikatorów powiadomień lokalnych. Po nich `AppDelegate`
/// rozpoznaje rodzaj powiadomienia i po nich kasuje zapas, gdy tę samą sprawę
/// dowiozło już push.
enum NotificationIdentifierPrefix {
    static let plan = "plan-change-"
    static let shopping = "shopping-change-"
    static let invitation = "invitation-"
    static let household = "household-"
}

/// Powiadomienia o tym, co w gospodarstwie zrobił KTOŚ INNY.
///
/// Historia tej klasy tłumaczy jej dzisiejszy kształt. Każde zdarzenie
/// z socketu zamieniało się tu natychmiast w osobne `UNNotificationRequest`
/// z losowym identyfikatorem, pełnym dźwiękiem i bannerem — równolegle do
/// pusha, który o tym samym zdarzeniu wysyłał backend. Ułożenie tygodnia przez
/// jedną osobę oznaczało u drugiej kilkadziesiąt bannerów, po dwa na kratkę
/// planu, i to przy otwartej aplikacji, która i tak odświeżała ekran na żywo.
///
/// Teraz obowiązują cztery zasady:
///
/// 1. **Push wygrywa, ale nie przez wyłączenie zapasu.** Gdy serwer
///    potwierdził, że umie wysyłać powiadomienia (`isPushDeliveryActive`),
///    lokalne czeka dłużej i kasuje się samo w chwili, gdy push naprawdę
///    przyjdzie (`cancelPendingFallback`). Wcześniej sama deklaracja serwera
///    „mam klucze APNs" gasiła kanał lokalny na stałe — a deklaracja to nie
///    dostarczenie: token z innego środowiska APNs, cofnięte uprawnienie czy
///    martwy klucz kończyły się ciszą w obu kanałach naraz.
/// 2. **Zbieranie zamiast strumienia.** Powiadomienie jest planowane z
///    opóźnieniem i pod STAŁYM identyfikatorem. Kolejne zdarzenie w tym samym
///    oknie nie dokłada bannera, tylko podmienia ten zaplanowany — `add`
///    z istniejącym identyfikatorem zastępuje oczekujące żądanie. Dzięki temu
///    całą sesję opisuje jedno zdanie, bez własnych timerów.
/// 3. **Tylko znane zdarzenia.** Brak gałęzi „cokolwiek innego": odhaczenie
///    posiłku czy techniczna synchronizacja planu nie są wiadomością dla
///    domownika. Wcześniej wpadały w `default` i wychodziły jako „Ktoś zmienił
///    plan posiłków".
/// 4. **Cicho.** Bez dźwięku, `interruptionLevel = .passive`, wspólny wątek
///    na gospodarstwo.
enum PlanChangeNotificationService {
    /// Czy backend potwierdził, że umie wysyłać pushe.
    ///
    /// Ustawiane przez `SessionStore` po `notifications:registerDevice`.
    /// Statyczne, a nie przekazywane parametrem, bo pytają o to `WeeklyMealStore`
    /// i `ShoppingListStore` — a one z założenia nie znają sesji ani jej
    /// preferencji. Domyślne `false` jest ostrożne: dopóki nie wiadomo, czy
    /// push dojedzie, lepiej pokazać powiadomienie lokalne niż nie pokazać
    /// żadnego.
    private(set) static var isPushDeliveryActive: Bool = false

    static func setPushDeliveryActive(_ isActive: Bool) {
        isPushDeliveryActive = isActive
    }

    /// Ile czekamy, zanim zaplanowane powiadomienie wyjdzie. Tyle samo, co
    /// okno zbierania po stronie backendu (`PUSH_BATCH_QUIET_MS`), żeby oba
    /// kanały opisywały tę samą jednostkę czasu.
    private static let batchWindowSeconds: TimeInterval = 60

    /// Ile czeka powiadomienie lokalne, gdy push jest zadeklarowany jako
    /// działający. Dłużej niż okno zbierania backendu, żeby push zdążył
    /// przyjść i skasować zapas — a jeśli nie przyjdzie, użytkownik i tak
    /// dostaje informację zamiast ciszy.
    private static let pushFallbackDelaySeconds: TimeInterval = 150

    /// Ile zmian zebrało się pod danym identyfikatorem i kiedy doszła ostatnia.
    ///
    /// Znacznik czasu jest tu zamiast callbacku „dostarczono": system nie
    /// informuje o wysłaniu zaplanowanego powiadomienia, a bez zerowania
    /// licznik rósłby przez całą dobę i drugie podsumowanie mówiłoby o
    /// „47 zmianach", z których 40 użytkownik przeczytał godzinę wcześniej.
    /// Przerwa dłuższa niż okno zbierania znaczy, że poprzednia paczka już
    /// wyszła — więc następna zaczyna liczyć od zera.
    private static var pendingBatches: [String: (count: Int, lastEventAt: Date)] = [:]
    private static let pendingBatchesLock = NSLock()

    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Zmiana planu zrobiona przez innego domownika.
    ///
    /// Nie rysuje nic, gdy backend wysyła pushe — inaczej ta sama informacja
    /// dotarłaby dwa razy, raz jako push, raz jako lokalny banner.
    static func notifyRemotePlanChange(
        action: String?,
        weekStart: String,
        householdId: String?,
        changedByDisplayName: String?,
        dayOfWeek: String? = nil,
        mealType: String? = nil
    ) {
        guard isNotificationsEnabled, isPlanNotificationsEnabled else { return }
        guard let household = householdId, !household.isEmpty else { return }

        let actor = NotificationActorFormatter.firstName(from: changedByDisplayName)
        guard let single = singleChangeText(
            for: action,
            actor: actor,
            dayOfWeek: dayOfWeek,
            mealType: mealType
        ) else { return }

        let identifier = "\(NotificationIdentifierPrefix.plan)\(household)-\(weekStart)"
        let count = bumpPendingCount(for: identifier)
        let body = count <= 1
            ? single
            : "\(actor) wprowadził/a \(count) \(PolishPlural.form(count, one: "zmianę", few: "zmiany", many: "zmian")) w planie."

        schedule(
            identifier: identifier,
            threadIdentifier: NotificationThread.household(household),
            title: "Plan posiłków",
            body: body
        )
    }

    /// Zmiana na liście zakupów zrobiona przez innego domownika.
    static func notifyRemoteShoppingListChange(
        action: String?,
        householdId: String?,
        changedByDisplayName: String?,
        isChecked: Bool? = nil
    ) {
        guard isNotificationsEnabled, isShoppingNotificationsEnabled else { return }
        guard let household = householdId, !household.isEmpty else { return }

        let actor = NotificationActorFormatter.firstName(from: changedByDisplayName)
        guard let single = shoppingChangeText(for: action, actor: actor, isChecked: isChecked) else {
            return
        }

        let identifier = "\(NotificationIdentifierPrefix.shopping)\(household)"
        let count = bumpPendingCount(for: identifier)
        let body = count <= 1
            ? single
            : "\(actor) zaktualizował/a listę zakupów (\(count) \(PolishPlural.form(count, one: "zmiana", few: "zmiany", many: "zmian")))."

        schedule(
            identifier: identifier,
            threadIdentifier: NotificationThread.household(household),
            title: "Lista zakupów",
            body: body
        )
    }

    /// Ktoś dołączył do gospodarstwa albo je opuścił.
    ///
    /// Jedyne powiadomienie wysyłane od razu i z dźwiękiem: to zdarzenie
    /// zdarza się raz na kilka miesięcy, a użytkownik, który właśnie wysłał
    /// zaproszenie, na nie czeka.
    static func notifyHouseholdMembershipChange(
        action: String?,
        householdId: String?,
        changedByDisplayName: String?,
        affectedDisplayName: String? = nil
    ) {
        let normalizedAction = action?.uppercased()
        // Usunięcia domownika backend nie wysyła pushem (adresatów wylicza już
        // PO zmianie składu), więc kanał lokalny nie może się wyłączać, gdy
        // push działa — inaczej to zdarzenie nie miałoby ŻADNEGO kanału.
        if normalizedAction != "REMOVE_MEMBER" {
            guard !isPushDeliveryActive else { return }
        }
        // Tylko główny przełącznik — kanał gospodarstwa nie ma osobnego
        // wyciszenia. To zdarzenie jest za rzadkie i za ważne, żeby dało się
        // je zgubić jednym tapnięciem w Ustawieniach.
        guard isNotificationsEnabled else { return }
        guard let household = householdId, !household.isEmpty else { return }

        let actor = NotificationActorFormatter.firstName(from: changedByDisplayName)
        let body: String
        switch normalizedAction {
        case "ACCEPT_INVITATION":
            body = "\(actor) dołączył/a do Twojego gospodarstwa."
        case "LEAVE":
            body = "\(actor) opuścił/a Twoje gospodarstwo."
        case "REMOVE_MEMBER":
            if let affected = affectedDisplayName, !affected.isEmpty {
                body = "\(actor) usunął/ęła \(NotificationActorFormatter.firstName(from: affected)) z gospodarstwa."
            } else {
                body = "\(actor) usunął/ęła domownika z gospodarstwa."
            }
        default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Gospodarstwo"
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = NotificationThread.household(household)

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "household-\(household)-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
        )
    }

    /// Informacja dla OSOBY USUNIĘTEJ z gospodarstwa — lokalny kanał jest tu
    /// jedyny: backend nie może jej wysłać pusha, bo po usunięciu nie jest już
    /// adresatem powiadomień gospodarstwa. Bez tego aplikacja po prostu
    /// przełączała się na ekran „Brak gospodarstwa" bez słowa wyjaśnienia.
    static func notifyRemovedFromHousehold(
        householdId: String?,
        householdName: String?
    ) {
        guard isNotificationsEnabled else { return }
        guard let household = householdId, !household.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "Gospodarstwo"
        if let name = householdName, !name.isEmpty {
            content.body = "Usunięto Cię z gospodarstwa \(name)."
        } else {
            content.body = "Usunięto Cię z gospodarstwa."
        }
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = NotificationThread.household(household)

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "household-\(household)-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
        )
    }

    // MARK: - Wysyłka

    private static func schedule(
        identifier: String,
        threadIdentifier: String,
        title: String,
        body: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // Bez dźwięku i bez przerywania — to jest informacja, a nie wezwanie.
        content.sound = nil
        content.interruptionLevel = .passive
        content.threadIdentifier = threadIdentifier

        // Wyzwalacz czasowy jest tu mechanizmem zbierania, nie opóźnieniem dla
        // samego opóźnienia: dopóki żądanie czeka, kolejne `add` z tym samym
        // identyfikatorem je PODMIENIA. Ostatnia zmiana w sesji decyduje więc
        // o treści, a użytkownik dostaje jeden banner zamiast serii.
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: isPushDeliveryActive
                    ? pushFallbackDelaySeconds
                    : batchWindowSeconds,
                repeats: false
            )
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Push o tej samej sprawie już dotarł — czekający zapas lokalny jest
    /// zbędny i zniknąłby jako druga kopia tej samej wiadomości.
    static func cancelPendingFallback(prefix: String) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
            guard !identifiers.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            identifiers.forEach { resetPendingCount(for: $0) }
        }
    }

    /// Zwiększa licznik zmian dla identyfikatora i zwraca nową wartość.
    private static func bumpPendingCount(for identifier: String) -> Int {
        pendingBatchesLock.lock()
        defer { pendingBatchesLock.unlock() }

        let now = Date()
        let previous = pendingBatches[identifier]
        let isSameBatch = previous.map {
            now.timeIntervalSince($0.lastEventAt) < batchWindowSeconds
        } ?? false

        let next = isSameBatch ? (previous?.count ?? 0) + 1 : 1
        pendingBatches[identifier] = (count: next, lastEventAt: now)
        return next
    }

    /// Woła się z delegata po stuknięciu w powiadomienie — od tej chwili
    /// kolejna zmiana na pewno zaczyna nową paczkę, nawet gdyby przyszła
    /// w tej samej sekundzie.
    static func resetPendingCount(for identifier: String) {
        pendingBatchesLock.lock()
        pendingBatches[identifier] = nil
        pendingBatchesLock.unlock()
    }

    // MARK: - Treści

    /// `nil` = to zdarzenie nie zasługuje na powiadomienie.
    ///
    /// Brak gałęzi domyślnej jest tu celowy. Backend rozgłasza po sockecie
    /// także zdarzenia czysto techniczne (`SET_MEAL_EATEN`, `SAVE_PLAN_SYNC`),
    /// świadomie NIE wysyłając dla nich pusha — a klient odpalał na nie
    /// „Ktoś zmienił plan posiłków", czyli dokładnie to powiadomienie, którego
    /// serwer postanowił nie wysyłać.
    private static func singleChangeText(
        for action: String?,
        actor: String,
        dayOfWeek: String?,
        mealType: String?
    ) -> String? {
        let meal = mapMealType(mealType).lowercased()
        let day = mapDayOfWeek(dayOfWeek).lowercased()

        switch action?.uppercased() {
        case "UPSERT_SLOT":
            if dayOfWeek != nil, mealType != nil {
                return "\(actor) zmienił/a \(meal) na \(day)."
            }
            return "\(actor) zaktualizował/a plan posiłków."
        case "REMOVE_SLOT":
            if dayOfWeek != nil, mealType != nil {
                return "\(actor) usunął/ęła \(meal) z planu na \(day)."
            }
            return "\(actor) usunął/ęła pozycję z planu posiłków."
        case "CLEAR_PLAN":
            return "\(actor) usunął/ęła plan posiłków na ten tydzień."
        case "SAVE_PLAN":
            return "\(actor) ustawił/a plan posiłków na ten tydzień."
        default:
            return nil
        }
    }

    private static func shoppingChangeText(
        for action: String?,
        actor: String,
        isChecked: Bool?
    ) -> String? {
        switch action?.uppercased() {
        case "SET_ITEM_CHECKED":
            // Odhaczenie POJEDYNCZEGO produktu nigdy nie jest wiadomością —
            // wiadomością są dopiero zrobione zakupy, czyli kilkanaście
            // odhaczeń w jednym oknie. Zbieranie robi to za nas.
            guard isChecked == true else { return nil }
            return "\(actor) odhaczył/a produkt na liście zakupów."
        case "ARCHIVE_LIST":
            return "\(actor) zamknął/ęła listę zakupów."
        default:
            // Historia list (przywrócenie, usunięcie archiwum) to porządki we
            // własnych danych, nie zdarzenie dla domownika.
            return nil
        }
    }

    /// Nazwa slotu w bierniku — wchodzi w zdania typu „Marek zmienił Kolację
    /// na środę", dlatego „Kolację", a nie „Kolacja". To samo tłumaczenie stoi
    /// po stronie backendu (`notification-copy.util.ts`), bo powiadomienie push
    /// składa się tam, a nie tutaj.
    private static func mapMealType(_ value: String?) -> String {
        guard let slot = value.flatMap({ MealSlot(backendMealType: $0) }) else {
            return "Posiłek"
        }
        switch slot {
        case .breakfast:       return "Śniadanie"
        case .secondBreakfast: return "II śniadanie"
        case .lunch:           return "Obiad"
        case .afternoonSnack:  return "Podwieczorek"
        case .dinner:          return "Kolację"
        case .snack:           return "Przekąskę"
        }
    }

    private static func mapDayOfWeek(_ value: String?) -> String {
        switch value?.uppercased() {
        case "MON": return "Poniedziałek"
        case "TUE": return "Wtorek"
        case "WED": return "Środę"
        case "THU": return "Czwartek"
        case "FRI": return "Piątek"
        case "SAT": return "Sobotę"
        case "SUN": return "Niedzielę"
        default:    return "wybrany dzień"
        }
    }

    // MARK: - Przełączniki z Ustawień
    //
    // Te same klucze czyta `SettingsView`, a `SessionStore` wysyła ich wartości
    // na backend (`users:preferences:update`) — bez tego wyciszenie powiadomień
    // uciszałoby wyłącznie kanał lokalny, a pushe leciałyby dalej.

    static var isNotificationsEnabled: Bool {
        boolSetting("settings.notifications.enabled")
    }

    static var isPlanNotificationsEnabled: Bool {
        boolSetting("settings.notifications.planReminders")
    }

    static var isShoppingNotificationsEnabled: Bool {
        boolSetting("settings.notifications.shoppingReminders")
    }

    private static func boolSetting(_ key: String) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil { return true }
        return defaults.bool(forKey: key)
    }
}
