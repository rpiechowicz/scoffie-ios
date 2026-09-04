import Foundation
import Observation

/// Kroki dzienne z HealthKit (Apple Zdrowie albo Garmin przez Zdrowie).
///
/// Wisi na `SessionStore` jak pozostałe store'y (budowany w `bootstrapSession`,
/// czyszczony przy wylogowaniu). Dwie pętle świeżości:
/// - lokalny odczyt HK (tani): `HKObserverQuery` na żywo + foreground +
///   zmiana wybranego dnia w Kalendarzu,
/// - wysyłka do backendu (PUT): dławiona do jednej na 5 min, chyba że
///   aplikacja właśnie wchodzi na wierzch albo schodzi w tło.
@MainActor
@Observable
final class HealthStepsStore {
    struct DaySteps: Equatable {
        let steps: Int
        let source: StepsSource
    }

    /// Klucze UserDefaults — widoki czytają flagę i cel przez `@AppStorage`
    /// z tych samych kluczy (to one gwarantują re-render), store trzyma
    /// lustro flagi jako stan `@Observable` na potrzeby własnych guardów.
    enum Keys {
        static let enabled = "settings.health.stepsEnabled"
        static let source = "settings.health.source"
        static let enabledAt = "settings.health.enabledAt"
        static let stepsGoal = "settings.health.stepsGoal"
    }

    static let defaultStepsGoal = 10_000

    /// Klucz = `MealCalendarStore.dateKey` — ten sam adres dnia, którym
    /// posługuje się cały Kalendarz.
    private(set) var stepsByDay: [String: DaySteps] = [:]
    private(set) var isBusy = false
    /// Integracja włączona, ale ostatni odczyt okna wrócił pusty — najpewniej
    /// odmowa odczytu w Zdrowiu (nie da się jej sprawdzić wprost) albo Garmin
    /// Connect nie zapisuje kroków. Arkusz pokazuje wtedy podpowiedź.
    private(set) var lastWindowWasEmpty = false
    private(set) var isEnabled: Bool
    private(set) var source: StepsSource

    private let service: HealthKitService
    private let client: IntegrationsAPIClient
    /// Rośnie przy każdym starcie odczytu okna — wynik starszego zapytania
    /// (np. sprzed przełączenia źródła) jest po powrocie z await odrzucany,
    /// zamiast nadpisać świeższy stan danymi ze starego filtra.
    private var refreshGeneration = 0
    /// Ostatnia PRÓBA wysyłki (nie sukces) — dławienie liczone od prób,
    /// inaczej przy padniętym backendzie każdy strzał obserwatora HK
    /// wywoływałby natychmiastowy, skazany na porażkę PUT.
    private var lastSyncAttemptAt: Date?
    private var lastSyncedEntries: [HealthStepsEntryDTO] = []
    private var throttledSyncTask: Task<Void, Never>?

    private static let syncThrottleSeconds: TimeInterval = 5 * 60
    /// Okno kroczące: dziś + 6 dni wstecz (ograniczone datą włączenia) —
    /// Garmin potrafi dopisać próbki do Zdrowia z opóźnieniem, więc sam
    /// dzień bieżący by nie wystarczył.
    private static let windowDaysBack = 6

    init(service: HealthKitService, client: IntegrationsAPIClient) {
        self.service = service
        self.client = client
        let defaults = UserDefaults.standard
        self.isEnabled = defaults.bool(forKey: Keys.enabled)
        self.source = StepsSource(rawValue: defaults.string(forKey: Keys.source) ?? "")
            ?? .appleHealth
    }

    var stepsGoal: Int {
        let value = UserDefaults.standard.integer(forKey: Keys.stepsGoal)
        return value > 0 ? value : Self.defaultStepsGoal
    }

    /// "yyyy-MM-dd" dnia włączenia integracji — do wiersza „Synchronizacja od…".
    var enabledAtKey: String? {
        UserDefaults.standard.string(forKey: Keys.enabledAt)
    }

    func steps(for date: Date) -> DaySteps? {
        stepsByDay[MealCalendarStore.dateKey(for: date)]
    }

    var todaySteps: Int? {
        steps(for: Date())?.steps
    }

    // MARK: - Włączanie / wyłączanie

    /// Prosi o dostęp do Zdrowia i włącza integrację. Zwraca komunikat błędu
    /// do pokazania inline albo `nil` przy sukcesie. UWAGA: systemowy arkusz
    /// uprawnień pojawia się tylko za pierwszym razem — odmowy nie umiemy
    /// potem wykryć, więc „sukces" znaczy „integracja włączona", nie „dane płyną".
    func enable(source: StepsSource) async -> String? {
        guard !isBusy else { return nil }
        guard HealthKitService.isAvailable else {
            return "Zdrowie nie jest dostępne na tym urządzeniu."
        }
        isBusy = true
        defer { isBusy = false }

        do {
            try await service.requestReadAuthorization()
        } catch {
            return "Nie udało się poprosić o dostęp do Zdrowia. Spróbuj ponownie."
        }

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Keys.enabled)
        defaults.set(source.rawValue, forKey: Keys.source)
        // Bez backfillu: synchronizujemy od dnia włączenia. Ponowne włączenie
        // zaczyna od nowa — dni przerwy przepadają świadomie.
        defaults.set(MealCalendarStore.dateKey(for: Date()), forKey: Keys.enabledAt)
        isEnabled = true
        self.source = source

        startObserving()
        await refreshAndSync()
        return nil
    }

    /// Przełączenie Apple ↔ Garmin: nowy odczyt całego okna i re-sync —
    /// upsert po stronie backendu nadpisze okno wierszami z nowym źródłem.
    func setSource(_ newSource: StepsSource) async {
        guard newSource != source else { return }
        source = newSource
        UserDefaults.standard.set(newSource.rawValue, forKey: Keys.source)
        stepsByDay = [:]
        lastSyncedEntries = []
        await refreshAndSync()
    }

    /// Tylko flaga po stronie aplikacji + czyszczenie cache. Uprawnień
    /// HealthKit nie da się cofnąć programowo (użytkownik robi to w
    /// Ustawieniach systemu). Kopia kroków na serwerze jest kasowana —
    /// polityka prywatności §7 obiecuje to przy wyłączeniu.
    func disable() {
        let client = self.client
        Task { try? await client.deleteHealthSteps() }
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: Keys.enabled)
        defaults.removeObject(forKey: Keys.enabledAt)
        isEnabled = false
        stepsByDay = [:]
        lastWindowWasEmpty = false
        lastSyncedEntries = []
        lastSyncAttemptAt = nil
        throttledSyncTask?.cancel()
        throttledSyncTask = nil
        service.stopObserving()
    }

    // MARK: - Świeżość danych

    /// Pełny cykl: lokalny odczyt okna + natychmiastowa wysyłka. Wołany przy
    /// starcie sesji, foregroundzie i po zmianach konfiguracji.
    func refreshAndSync() async {
        await refreshLocal()
        await syncNow()
    }

    /// Uzbraja `HKObserverQuery` — nowe próbki w Zdrowiu (spacer, zapis
    /// z Garmin Connect) odświeżają licznik na żywo, bez pollingu.
    func startObserving() {
        guard isEnabled, HealthKitService.isAvailable else { return }
        service.observeStepChanges { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refreshLocal()
                self.scheduleThrottledSync()
            }
        }
    }

    func stopObserving() {
        service.stopObserving()
        throttledSyncTask?.cancel()
        throttledSyncTask = nil
    }

    /// Leniwy odczyt pojedynczego dnia spoza okna (przeglądanie przeszłości
    /// w Kalendarzu) — tylko lokalnie, bez wysyłki: backend dostaje wyłącznie
    /// kroczące okno od dnia włączenia.
    func refreshIfNeeded(for date: Date) async {
        guard isEnabled, HealthKitService.isAvailable else { return }
        let key = MealCalendarStore.dateKey(for: date)
        guard stepsByDay[key] == nil else { return }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        guard day <= calendar.startOfDay(for: Date()) else { return }
        // Źródło łapane PRZED await i sprawdzane PO — wynik zapytania ze
        // starym filtrem nie może dostać etykiety nowego źródła.
        let queriedSource = source
        guard let samples = try? await service.dailySteps(from: day, to: day, source: queriedSource),
              let sample = samples.first,
              queriedSource == source
        else { return }
        stepsByDay[sample.dateKey] = DaySteps(steps: sample.steps, source: queriedSource)
    }

    /// Odczyt kroczącego okna z HealthKit do `stepsByDay`. Błędy połykane —
    /// chwilowy problem z HK nie może wyzerować widocznego licznika.
    /// Współbieżne odczyty są dozwolone (HK to udźwignie); wygrywa najnowszy:
    /// starszy wynik jest po await odrzucany po numerze generacji, więc ani
    /// nie nadpisze świeższych danych, ani nie przemyci starego źródła.
    private func refreshLocal() async {
        guard isEnabled, HealthKitService.isAvailable else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let queriedSource = source

        let window = syncWindow()
        guard let samples = try? await service.dailySteps(
            from: window.from, to: window.to, source: queriedSource
        ) else { return }
        guard generation == refreshGeneration, queriedSource == source else { return }

        for sample in samples {
            stepsByDay[sample.dateKey] = DaySteps(steps: sample.steps, source: queriedSource)
        }
        lastWindowWasEmpty = samples.isEmpty
    }

    // MARK: - Wysyłka do backendu

    /// Natychmiastowy PUT okna (pomijany, gdy nic się nie zmieniło od
    /// ostatniej udanej wysyłki). Błędy sieci połykane — baza jest
    /// write-mostly, UI żyje z lokalnego odczytu HK.
    func syncNow() async {
        guard isEnabled else { return }
        let entries = currentWindowEntries()
        guard !entries.isEmpty, entries != lastSyncedEntries else { return }
        lastSyncAttemptAt = Date()
        guard let _ = try? await client.syncHealthSteps(entries: entries) else { return }
        lastSyncedEntries = entries
    }

    /// Wysyłka dławiona do jednej na `syncThrottleSeconds` — obserwator HK
    /// potrafi strzelać seriami (każda próbka z osobna), a statystyki nie
    /// potrzebują real-time.
    private func scheduleThrottledSync() {
        guard isEnabled, throttledSyncTask == nil else { return }
        let elapsed = lastSyncAttemptAt.map { Date().timeIntervalSince($0) } ?? .infinity
        let delay = max(0, Self.syncThrottleSeconds - elapsed)
        throttledSyncTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard let self, !Task.isCancelled else { return }
            self.throttledSyncTask = nil
            await self.syncNow()
        }
    }

    // MARK: - Okno

    private func syncWindow() -> (from: Date, to: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let windowStart = calendar.date(byAdding: .day, value: -Self.windowDaysBack, to: today)
            ?? today
        let enabledAt = enabledAtKey.flatMap(Self.parseDateKey)
            .map { calendar.startOfDay(for: $0) }
        return (from: max(windowStart, enabledAt ?? windowStart), to: today)
    }

    private func currentWindowEntries() -> [HealthStepsEntryDTO] {
        let window = syncWindow()
        let calendar = Calendar.current
        let goal = stepsGoal
        var entries: [HealthStepsEntryDTO] = []
        var day = window.from
        while day <= window.to {
            let key = MealCalendarStore.dateKey(for: day)
            if let sample = stepsByDay[key] {
                entries.append(HealthStepsEntryDTO(
                    date: key,
                    steps: sample.steps,
                    stepsGoal: goal,
                    source: sample.source.rawValue
                ))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return entries
    }

    /// Odwrotność `MealCalendarStore.dateKey` — ta sama konfiguracja formattera
    /// (en_US_POSIX + strefa telefonu), inaczej klucze by się rozjechały.
    private static let dateKeyParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func parseDateKey(_ raw: String) -> Date? {
        dateKeyParser.date(from: raw)
    }
}
