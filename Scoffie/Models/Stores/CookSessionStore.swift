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
    /// Pełny ekran trybu Gotuj nad pulpitem.
    var isPresented = false
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

    init(ownerKey: String) {
        self.ownerKey = ownerKey
        self.persists = true
        session = Self.load(ownerKey: ownerKey)
        scheduleRingWatch()
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
        isPresented = true
    }

    private static func kcalPerServing(_ recipe: Recipe) -> Int? {
        let value = recipe.nutrition.kcal / Double(max(1, recipe.servings))
        return value > 0 ? Int(value.rounded()) : nil
    }

    /// Powrót do wstrzymanej sesji (talerz, szczegóły, Live Activity).
    func resume() {
        guard session != nil else { return }
        if isPresented {
            // Przełącznik został na `true`, a ekranu nie ma (pokazanie nad
            // arkuszem przepadło) — przejście false → true, żeby SwiftUI
            // pokazało go od nowa.
            isPresented = false
            Task { @MainActor [weak self] in self?.isPresented = true }
        } else {
            isPresented = true
        }
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
    }

    /// „Wstrzymaj”: widok znika, sesja i timery zostają.
    func pause() {
        isPresented = false
    }

    /// „Zakończ gotowanie” / „Zjedzone”: koniec sesji.
    func end() {
        isPresented = false
        session = nil
        ringWatch?.cancel()
        ringWatch = nil
        guard persists else { return }
        CookTimerNotifications.cancelAll()
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    // MARK: - Koniec timera poza ekranem trybu

    /// Aplikacja w tle: koniec każdego biegnącego timera dzwoni zwykłym
    /// powiadomieniem. E4 — bez AlarmKit; ten przejmie to w E5 (dzwoni mimo
    /// wyciszenia, Dynamic Island, ekran blokady).
    func appWentToBackground() {
        CookTimerNotifications.schedule(for: session)
    }

    /// Na wierzchu dzwoni ekran końca timera, nie baner.
    func appBecameActive() {
        // Synchronicznie, po znanych id — asynchroniczne `cancelAll` przy
        // szybkim „wierzch → tło” zdjęłoby świeżo zaplanowane powiadomienie.
        CookTimerNotifications.remove(for: session)
        scheduleRingWatch()
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
                    self.isPresented = true
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
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var fileURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cook-session-v1.json")
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
