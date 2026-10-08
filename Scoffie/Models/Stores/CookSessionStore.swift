import Foundation
import Observation
import SwiftUI
import UserNotifications

/// Trwająca sesja gotowania i jej zapis na dysk (§8.6).
///
/// Jedna sesja naraz (§4.7). Każda zmiana stanu idzie przez `update`, który
/// od razu zapisuje plik — po zabiciu aplikacji przez system talerz
/// i szczegóły pokazują „Wróć do gotowania” w tym samym kroku, z tymi samymi
/// timerami (liczonymi od dat końca, więc bez doganiania).
///
/// Widok trybu (`CookModeView`) stoi w `fullScreenCover` nad pulpitem;
/// `isPresented` to jego przełącznik. „Wstrzymaj” chowa widok, sesja zostaje;
/// „Zakończ” i „Zjedzone” sesję kończą.
@Observable
final class CookSessionStore {
    private(set) var session: CookSession?
    /// Pełny ekran trybu Gotuj nad pulpitem. Zmienia się WYŁĄCZNIE przez
    /// `setPresented` — bez systemowego wsuwania od dołu.
    private(set) var isPresented = false
    /// Konto i dom (`userId_householdId`) — sesja z pliku innego właściciela
    /// nie wraca.
    let ownerKey: String
    /// `false` = podgląd (ekran debug): bez pliku, żeby zrzut nie nadpisał
    /// prawdziwej sesji na tym telefonie.
    private let persists: Bool

    /// Czeka do najbliższego końca timera — wtedy, jeśli tryb jest schowany
    /// („Wstrzymaj”), pokazuje go z ekranem końca timera, jak alarm w Zegarze.
    @ObservationIgnored private var ringWatch: Task<Void, Never>?

    /// Timer właśnie zadzwonił, a tryb jest schowany. Pokazuje go
    /// `SessionStore` (najpierw zamyka arkusze pulpitu — pełnego ekranu nie da
    /// się pokazać nad otwartym arkuszem — i czeka na koniec startu).
    @ObservationIgnored var onRing: (() -> Void)?

    /// Sklep sesji, który właśnie żyje — dla przycisków Live Activity.
    static weak var current: CookSessionStore?
    /// Sklep odtworzony z pliku, gdy przycisk Live Activity obudził aplikację
    /// w tle, zanim sesja konta wstała (`forIntent`).
    private static var restoredForIntent: CookSessionStore?

    init(ownerKey: String) {
        self.ownerKey = ownerKey
        self.persists = true
        session = Self.load(ownerKey: ownerKey)
        // Prawdziwy sklep konta zastępuje ten odtworzony dla intencji —
        // stan i tak jest w pliku.
        Self.restoredForIntent = nil
        Self.current = self
        scheduleRingWatch()
        CookAlarmScheduler.shared.onAcknowledged = { [weak self] timerId, end in
            self?.acknowledgeSystemAlarm(timerId: timerId, end: end)
        }
        syncSystemAlarms()
    }

    /// Podgląd z gotową sesją — bez dysku i bez pilnowania alarmu.
    init(preview session: CookSession, isPresented: Bool = true) {
        self.ownerKey = "preview"
        self.persists = false
        self.session = session
        self.isPresented = isPresented
    }

    /// Nowa sesja. Poprzednia (inny przepis) znika — pytanie „zakończyć
    /// tamtą?” zadaje ekran, zanim tu przyjdzie (§4.7, jedna sesja naraz).
    func start(
        recipe: Recipe,
        package: CookPackage,
        portions: Int,
        mealSlot: MealSlot?,
        planDate: Date?,
        now: Date = Date()
    ) {
        let session = CookSession(
            recipeId: recipe.id,
            recipeTitle: recipe.name,
            recipeDescription: recipe.description,
            imageURL: recipe.imageURL,
            mealSlotRaw: mealSlot?.rawValue,
            planDateKey: planDate.map { PlanWeek.dateKey($0) },
            difficultyRaw: recipe.difficulty.rawValue,
            kcalPerServing: Self.kcalPerServing(recipe),
            package: package,
            portions: portions,
            startedAt: now
        )
        // Poprzednia sesja (inne danie) odchodzi razem ze swoimi powiadomieniami.
        CookTimerNotifications.cancelAll()
        self.session = session
        save()
        scheduleRingWatch()
        syncSystemAlarms()
        setPresented(true)
    }

    private static func kcalPerServing(_ recipe: Recipe) -> Int? {
        let value = recipe.nutrition.kcal / Double(max(1, recipe.servings))
        return value > 0 ? Int(value.rounded()) : nil
    }

    /// Tryb Gotuj naprawdę stoi na ekranie (`CookModeView` onAppear /
    /// onDisappear) — sam `isPresented` bywa `true` także wtedy, gdy pokazanie
    /// nad arkuszem przepadło.
    private(set) var isOnScreen = false
    /// Następne pokazanie bez przenikania (powrót z Live Activity — runda 12:
    /// „najpierw widzę kalendarz, a potem pokazuje się gotowanie”).
    @ObservationIgnored private var presentsInstantly = false

    func markOnScreen(_ value: Bool) {
        isOnScreen = value
    }

    /// `CookModeView` pyta przy wejściu, czy pokazać się od razu.
    func takeInstantPresentation() -> Bool {
        defer { presentsInstantly = false }
        return presentsInstantly
    }

    /// Powrót do wstrzymanej sesji (talerz, szczegóły, Live Activity).
    /// `instantly` — bez przenikania nad pulpitem.
    func resume(instantly: Bool = false) {
        guard session != nil else { return }
        // Tryb już stoi na ekranie — nic do roboty (dawniej znikał i wjeżdżał
        // od nowa, a spod niego mignął Kalendarz).
        if isPresented, isOnScreen { return }
        presentsInstantly = instantly
        if isPresented {
            // Przełącznik został na `true`, a ekranu nie ma (pokazanie nad
            // arkuszem przepadło) — przejście false → true, żeby SwiftUI
            // pokazało go od nowa.
            setPresented(false)
            Task { @MainActor [weak self] in self?.setPresented(true) }
        } else {
            setPresented(true)
        }
    }

    /// Pełny ekran pokazuje się i chowa BEZ animacji systemu (wsuwanie od
    /// dołu zasłaniało talerz, z którego ruszało gotowanie — „ucina talerz
    /// i wsuwa się ekran”). Ruch robi `CookModeView`: przy wejściu przenika
    /// nad pulpitem, przy wyjściu najpierw gaśnie, a dopiero potem woła
    /// `pause` / `end`.
    func setPresented(_ value: Bool) {
        guard isPresented != value else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isPresented = value }
    }

    /// Sesja dla tego przepisu — „Wróć do gotowania” zamiast „Gotuj”.
    func activeSession(for recipeId: UUID) -> CookSession? {
        guard let session, session.recipeId == recipeId, session.stage != .finished else { return nil }
        return session
    }

    /// Jedyna droga zmiany stanu: zmiana + zapis.
    func update(_ change: (inout CookSession) -> Void) {
        guard var current = session else { return }
        change(&current)
        guard current != session else { return }
        session = current
        save()
        scheduleRingWatch()
        syncSystemAlarms()
    }

    /// „Wstrzymaj”: widok znika, sesja i timery zostają.
    func pause() {
        setPresented(false)
    }

    /// „Zakończ gotowanie” / „Zjedzone”: koniec sesji.
    func end() {
        setPresented(false)
        session = nil
        ringWatch?.cancel()
        ringWatch = nil
        guard persists else { return }
        CookTimerNotifications.cancelAll()
        CookAlarmScheduler.shared.sync(nil)
        CookLiveActivity.shared.sync(nil)
        // Także ze starego miejsca (7.10.2026), gdyby migracja go nie przeniosła.
        AppCacheDirectory.removeEverywhere(Self.fileURL.lastPathComponent)
    }

    // MARK: - Koniec timera poza ekranem trybu

    /// Aplikacja w tle: koniec timera dzwoni ALARMEM SYSTEMOWYM
    /// (`CookAlarmScheduler`, runda 11 — mimo wyciszenia, na ekranie blokady).
    /// Zwykłe powiadomienie zostaje tylko jako zapas, gdy zgody na alarmy nie
    /// ma — inaczej koniec timera dzwoniłby dwa razy.
    func appWentToBackground() {
        if CookAlarmScheduler.shared.isAuthorized {
            CookTimerNotifications.remove(for: session)
        } else {
            CookTimerNotifications.schedule(for: session)
        }
    }

    /// Na wierzchu dzwoni ekran końca timera, nie baner.
    func appBecameActive() {
        // Synchronicznie, po znanych id — asynchroniczne `cancelAll` przy
        // szybkim „wierzch → tło” zdjęłoby świeżo zaplanowane powiadomienie.
        CookTimerNotifications.remove(for: session)
        scheduleRingWatch()
        syncSystemAlarms()
    }

    // MARK: - Alarmy systemowe (AlarmKit)

    /// Alarmy systemowe i Live Activity idą za sesją przy każdej zmianie.
    private func syncSystemAlarms() {
        guard persists else { return }
        CookAlarmScheduler.shared.sync(session)
        CookLiveActivity.shared.sync(session)
    }

    /// Sklep dla przycisku Live Activity (`CookActivityCommands`): żywy albo
    /// odtworzony z pliku — po wybudzeniu w tle sesja konta jeszcze nie stoi,
    /// a stan gotowania jest w pliku. Właściciel bierze się z pliku.
    static func forIntent() -> CookSessionStore? {
        if let live = Self.current { return live }
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(StoredSession.self, from: data) else { return nil }
        let store = CookSessionStore(ownerKey: stored.ownerKey)
        guard store.session != nil else { return nil }
        restoredForIntent = store
        return store
    }

    /// „Zatrzymaj” na alercie systemu = „Wycisz” w aplikacji. Tylko timer,
    /// który dalej biegnie z tą samą godziną końca — alarm zdjęty z naszej
    /// ręki („Gotowe”, „+2 min”, wyciszenie) niczego tu nie zmienia.
    private func acknowledgeSystemAlarm(timerId: String, end: Date) {
        guard let run = session?.timers[timerId],
              run.state == .running, !run.silenced, run.endDate == end else { return }
        update { $0.silenceTimer(timerId) }
    }

    private func scheduleRingWatch() {
        ringWatch?.cancel()
        ringWatch = nil
        guard persists, let session, session.stage == .steps else { return }
        let now = Date()
        let next = session.timers.values
            .filter { $0.state == .running && !$0.silenced }
            .compactMap(\.endDate)
            .filter { $0 > now }
            .min()
        let ringsNow = session.ringingTimer(now: now) != nil
        guard ringsNow || next != nil else { return }
        ringWatch = Task { @MainActor [weak self] in
            if let next, !ringsNow {
                try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)))
            }
            guard !Task.isCancelled, let self, let session = self.session else { return }
            if session.ringingTimer(now: Date()) != nil, !self.isPresented {
                if let onRing = self.onRing {
                    onRing()
                } else {
                    self.setPresented(true)
                }
            }
            if !ringsNow {
                self.scheduleRingWatch()
            }
        }
    }

    // MARK: - Dysk

    /// Sesja należy do konta — po wylogowaniu nie ma prawa wrócić u kogoś innego.
    static func clearCache() {
        // Także ze starego miejsca (7.10.2026), gdyby migracja go nie przeniosła.
        AppCacheDirectory.removeEverywhere(fileURL.lastPathComponent)
        // Alarm systemowy i Live Activity przeżyłyby wylogowanie.
        CookAlarmScheduler.shared.sync(nil)
        CookLiveActivity.shared.sync(nil)
    }

    /// 7.10.2026 (audyt 2.5): w katalogu offline wykluczonym z kopii zapasowej
    /// (wcześniej sam `Application Support`) — stary plik przenosi `AppCacheDirectory`.
    private static var fileURL: URL {
        AppCacheDirectory.url(for: "cook-session-v1.json")
    }

    private func save() {
        guard persists, let session else { return }
        do {
            let directory = Self.fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(StoredSession(ownerKey: ownerKey, session: session))
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            // Bez zapisu sesja żyje do końca procesu — gotowanie trwa dalej.
        }
    }

    private static func load(ownerKey: String) -> CookSession? {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(StoredSession.self, from: data),
              stored.ownerKey == ownerKey,
              stored.session.format == CookSession.currentFormat else { return nil }
        let session = stored.session
        // Stara sesja nie wraca — to już nie jest „to samo gotowanie”. Granica
        // to 36 h od startu, a nie doba czy północ, bo scenariusz bywa „na noc”
        // (D38: ciasto w lodówce do rana, następny krok zaczyna się od „Rano…”).
        guard Date().timeIntervalSince(session.startedAt) < 36 * 60 * 60 else { return nil }
        return session.stage == .finished ? nil : session
    }
}

/// Powiadomienia końca timerów, gdy aplikacja jest w tle (E4).
enum CookTimerNotifications {
    private static let prefix = NotificationIdentifierPrefix.cookTimer

    static func schedule(for session: CookSession?) {
        guard let session, session.stage == .steps else {
            cancelAll()
            return
        }
        let now = Date()
        let center = UNUserNotificationCenter.current()
        // Zdejmowanie po znanych id, synchronicznie — `cancelAll` czyta listę
        // asynchronicznie i potrafiłby zdjąć to, co zaraz dodamy.
        remove(for: session)
        for run in session.timers.values where run.state == .running && !run.silenced {
            guard let end = run.endDate, end > now, let timer = session.scenario.timer(id: run.timerId) else { continue }
            let content = UNMutableNotificationContent()
            content.title = timer.alert.title
            content.body = timer.alert.body
            content.sound = .default
            content.interruptionLevel = .active
            content.threadIdentifier = "cook"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSince(now)), repeats: false)
            center.add(UNNotificationRequest(identifier: prefix + run.timerId, content: content, trigger: trigger))
        }
    }

    /// Zdejmuje oczekujące i dostarczone powiadomienia timerów tej sesji —
    /// synchronicznie, po znanych id.
    static func remove(for session: CookSession?) {
        guard let session else { return }
        let ids = session.scenario.timers.map { prefix + $0.id }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        let prefix = Self.prefix
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            guard !ids.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}

/// Plik sesji: właściciel + stan.
private struct StoredSession: Codable {
    let ownerKey: String
    let session: CookSession
}
