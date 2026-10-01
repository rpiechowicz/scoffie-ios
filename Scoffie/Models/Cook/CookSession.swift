import Foundation

/// Trwająca sesja gotowania — JEDEN serializowalny stan (§8.6): przepis,
/// kopia scenariusza, porcje, krok, timery. Zapisywany przy każdej zmianie
/// (`CookSessionStore`), więc przeżywa wyjście z aplikacji, blokadę telefonu
/// i zabicie procesu; w v2 ten sam stan dostanie asystent.
///
/// Timery pamiętamy jako DATĘ KOŃCA, nie licznik (§4.5) — odliczanie liczy się
/// zawsze od zegara, więc sesja po powrocie z tła albo po restarcie pokazuje
/// prawdę bez żadnego „doganiania”.
///
/// Czysta logika (Foundation) — sprawdzian: `sh Scripts/cook-logic-check.sh`.
struct CookSession: Codable, Equatable {
    /// Zmiana kształtu = podbij; stary plik sesji zostanie pominięty.
    static let currentFormat = 1

    enum Stage: String, Codable, Equatable {
        /// Powitanie: porcje, składniki, rady.
        case welcome
        /// Kroki (`stepIndex`).
        case steps
        /// „Smacznego!” — po ostatnim kroku.
        case finished
    }

    let format: Int
    let id: UUID
    let recipeId: UUID
    let recipeTitle: String
    /// Opis przepisu pod liczbami powitania (runda 6). `nil` = brak opisu
    /// albo sesja zapisana przed tą wersją (klucza nie ma w pliku).
    let recipeDescription: String?
    let imageURL: URL?
    /// Pora z planu (`MealSlot.rawValue`), gdy gotujemy danie z planu —
    /// „GOTUJEMY · OBIAD”. `nil` = spoza planu (D21).
    let mealSlotRaw: String?
    /// Dzień pozycji planu (`PlanWeek.dateKey`) — na niego „Zjedzone” odhacza
    /// danie. `nil` = spoza planu.
    let planDateKey: String?
    /// Trudność przepisu (`Difficulty.rawValue`) i kcal porcji — powitanie
    /// i zakończenie; scenariusz ich nie niesie, a sesja ma działać offline.
    let difficultyRaw: String?
    let kcalPerServing: Int?
    /// Kopia scenariusza z chwili startu — sesja dokańcza na SWOJEJ wersji,
    /// nawet gdy w trakcie przyjdzie nowsza (§4.7).
    let package: CookPackage
    /// Porcje tej sesji — tylko tu, plan zostaje bez zmian (D11).
    var portions: Int
    /// Porcje, z którymi sesja wystartowała (plan albo przepis) — podpis
    /// „tyle, ile w planie” znika, gdy użytkownik je zmieni.
    let defaultPortions: Int
    var stage: Stage
    var stepIndex: Int
    var timers: [String: CookTimerRun]
    /// Kroki, na których użytkownik już stał — z nich biorą się timery
    /// „do włączenia” spoza bieżącego kroku (wyzwalacz `EVENT`).
    var visitedStepIds: [String]
    /// Ile razy i o ile przedłużano timery — podpowiedź w arkuszu uwag po
    /// kciuku (§13.3: „Kotlety +4 min”) i sygnał dla panelu.
    var extensions: [CookTimerExtension]
    let startedAt: Date
    /// Stuknięcie „Zaczynamy” — od niego liczy się czas na zakończeniu.
    var cookingStartedAt: Date?
    var finishedAt: Date?

    init(
        id: UUID = UUID(),
        recipeId: UUID,
        recipeTitle: String,
        recipeDescription: String? = nil,
        imageURL: URL?,
        mealSlotRaw: String?,
        planDateKey: String? = nil,
        difficultyRaw: String? = nil,
        kcalPerServing: Int? = nil,
        package: CookPackage,
        portions: Int,
        startedAt: Date
    ) {
        self.format = Self.currentFormat
        self.id = id
        self.recipeId = recipeId
        self.recipeTitle = recipeTitle
        let description = recipeDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.recipeDescription = description.isEmpty ? nil : description
        self.imageURL = imageURL
        self.mealSlotRaw = mealSlotRaw
        self.planDateKey = planDateKey
        self.difficultyRaw = difficultyRaw
        self.kcalPerServing = kcalPerServing
        self.package = package
        self.portions = max(1, portions)
        self.defaultPortions = max(1, portions)
        self.stage = .welcome
        self.stepIndex = 0
        self.timers = [:]
        self.visitedStepIds = []
        self.extensions = []
        self.startedAt = startedAt
    }

    var scenario: CookScenario { package.scenario }
    var steps: [CookStep] { scenario.steps }
    var stepCount: Int { steps.count }

    var currentStep: CookStep? {
        guard stage == .steps, steps.indices.contains(stepIndex) else { return nil }
        return steps[stepIndex]
    }

    var isFirstStep: Bool { stepIndex == 0 }
    var isLastStep: Bool { stepIndex == steps.count - 1 }

    /// Porcje różne od tych, z którymi sesja ruszyła.
    var portionsChanged: Bool { portions != defaultPortions }

    // MARK: - Nawigacja

    /// „Zaczynamy” na powitaniu.
    mutating func begin(now: Date) {
        guard stage == .welcome, !steps.isEmpty else { return }
        stage = .steps
        stepIndex = 0
        cookingStartedAt = cookingStartedAt ?? now
        markVisited()
    }

    mutating func next(now: Date) {
        guard stage == .steps else { return }
        if isLastStep {
            finish(now: now)
        } else {
            stepIndex += 1
            markVisited()
            restoreSkippedTimer()
        }
    }

    mutating func back() {
        guard stage == .steps else { return }
        if stepIndex > 0 {
            stepIndex -= 1
            restoreSkippedTimer()
        }
    }

    /// Skok do kroku — ekran debug i sprawdzian logiki. Arkusz Kroki od
    /// rundy 7 jest samym podglądem (stuknięcie w wiersz nie przenosi).
    mutating func jump(to index: Int) {
        guard stage == .steps, steps.indices.contains(index) else { return }
        stepIndex = index
        markVisited()
        restoreSkippedTimer()
    }

    /// Pominięty timer kroku, na którym użytkownik znów stanął, wraca jako
    /// „do włączenia” (runda 5: „Pomiń” nie dało się cofnąć — przypadkowe
    /// stuknięcie gubiło timer do końca gotowania). Samo „Pomiń” nikogo
    /// nie przenosi, więc na swoim kroku timer znika od razu.
    private mutating func restoreSkippedTimer() {
        guard let timerId = currentStep?.timer?.id, timers[timerId]?.state == .skipped else { return }
        timers[timerId] = nil
    }

    mutating func setPortions(_ value: Int) {
        portions = min(max(1, value), Self.maxPortions)
    }

    /// Koniec gotowania: biegnące timery przestają mieć znaczenie, sesja
    /// przechodzi na „Smacznego!”.
    mutating func finish(now: Date) {
        stage = .finished
        finishedAt = finishedAt ?? now
        for id in timers.keys {
            timers[id]?.state = .finished
        }
    }

    private mutating func markVisited() {
        guard let step = currentStep, !visitedStepIds.contains(step.id) else { return }
        visitedStepIds.append(step.id)
    }

    /// Sufit steppera porcji — ten sam co w szczegółach przepisu.
    static let maxPortions = 12

    // MARK: - Timery

    mutating func startTimer(_ timerId: String, now: Date) {
        guard let timer = scenario.timer(id: timerId),
              let step = scenario.step(forTimer: timerId) else { return }
        if let run = timers[timerId], run.state != .finished, run.state != .skipped { return }
        timers[timerId] = CookTimerRun(
            timerId: timerId,
            stepId: step.id,
            state: .running,
            endDate: now.addingTimeInterval(TimeInterval(timer.minSeconds)),
            remaining: nil,
            silenced: false,
            extendedSeconds: 0,
            startedAt: now,
            accent: accent(for: timerId)
        )
    }

    /// Kolor timera — każdy timer przepisu ma SWÓJ, po jego miejscu
    /// w scenariuszu (`CookTimerAccent.forTimer`). Ten sam od „do włączenia”
    /// do „Gotowe” i w każdej sesji tego przepisu.
    func accent(for timerId: String) -> CookTimerAccent {
        CookTimerAccent.forTimer(at: scenario.timers.firstIndex { $0.id == timerId } ?? 0)
    }

    mutating func pauseTimer(_ timerId: String, now: Date) {
        guard var run = timers[timerId], run.state == .running, let end = run.endDate else { return }
        // Po czasie nie ma czego pauzować — alarm kończy „Gotowe” albo „+min”.
        guard end > now else { return }
        run.state = .paused
        run.remaining = end.timeIntervalSince(now)
        run.endDate = nil
        timers[timerId] = run
    }

    mutating func resumeTimer(_ timerId: String, now: Date) {
        guard var run = timers[timerId], run.state == .paused else { return }
        run.state = .running
        run.endDate = now.addingTimeInterval(max(1, run.remaining ?? 0))
        run.remaining = nil
        timers[timerId] = run
    }

    /// „Jeszcze chwilę?” +1 / +2 / +5 min (D35): przedłuża TEN SAM timer
    /// (i krok — D38). Po czasie liczymy od teraz, przed końcem — od końca.
    mutating func extendTimer(_ timerId: String, by seconds: Int, now: Date) {
        guard var run = timers[timerId], seconds > 0 else { return }
        switch run.state {
        case .running:
            let base = max(run.endDate ?? now, now)
            run.endDate = base.addingTimeInterval(TimeInterval(seconds))
        case .paused:
            run.remaining = (run.remaining ?? 0) + TimeInterval(seconds)
        case .finished, .skipped:
            return
        }
        run.silenced = false
        run.extendedSeconds += seconds
        timers[timerId] = run
        extensions.append(CookTimerExtension(timerId: timerId, stepId: run.stepId, seconds: seconds, at: now))
    }

    /// „Wycisz” na ekranie końca timera: dzwonek milknie, kapsuła dalej
    /// mocno pulsuje, dopóki nie padnie „Gotowe” (D35).
    mutating func silenceTimer(_ timerId: String) {
        guard var run = timers[timerId], run.state == .running else { return }
        run.silenced = true
        timers[timerId] = run
    }

    /// „Pomiń” timer, który czeka na włączenie — znika z doku i z arkusza
    /// Timery. Pominięty przy „Dalej” zostaje w doku (runda 4), więc to
    /// jedyna droga, żeby niepotrzebny timer przestał zapraszać do startu.
    /// Nie jest „zrobiony”: wraca, gdy użytkownik znów stanie na jego kroku
    /// (`restoreSkippedTimer`).
    mutating func skipTimer(_ timerId: String, now: Date) {
        guard timers[timerId] == nil, let step = scenario.step(forTimer: timerId) else { return }
        timers[timerId] = CookTimerRun(
            timerId: timerId,
            stepId: step.id,
            state: .skipped,
            endDate: nil,
            remaining: nil,
            silenced: true,
            extendedSeconds: 0,
            startedAt: now,
            accent: accent(for: timerId)
        )
    }

    /// „Gotowe” — timer znika z doku. Działa też przed końcem („gotowe
    /// wcześniej” — kontrakt osi czasu, `CookStep.during`).
    mutating func finishTimer(_ timerId: String) {
        guard var run = timers[timerId] else { return }
        run.state = .finished
        run.silenced = true
        timers[timerId] = run
    }

    /// „Gotowe — dalej” na ekranie końca timera: timer zrobiony, a jeśli
    /// użytkownik stoi na jego kroku albo na kroku „w międzyczasie” pod nim —
    /// idziemy krok dalej (D38: następny krok główny rusza po alarmie).
    mutating func finishTimerAndAdvance(_ timerId: String, now: Date) {
        guard let run = timers[timerId] else { return }
        finishTimer(timerId)
        guard let step = currentStep else { return }
        if step.id == run.stepId || step.during == timerId {
            next(now: now)
        }
    }

    // MARK: - Stan timerów dla ekranu

    /// Stan jednego timera w chwili `now`.
    func status(of timerId: String, now: Date) -> CookTimerStatus? {
        guard let timer = scenario.timer(id: timerId) else { return nil }
        guard let run = timers[timerId] else {
            return .pending(total: TimeInterval(timer.minSeconds))
        }
        let total = TimeInterval(timer.minSeconds + run.extendedSeconds)
        switch run.state {
        case .finished, .skipped:
            return .finished
        case .paused:
            return .paused(remaining: run.remaining ?? 0, total: total)
        case .running:
            let end = run.endDate ?? now
            if end > now {
                return .running(remaining: end.timeIntervalSince(now), total: total, endDate: end)
            }
            return .overdue(over: now.timeIntervalSince(end), total: total, silenced: run.silenced)
        }
    }

    /// Timery w doku nad wyspą (D34): najpierw te, które wymagają uwagi
    /// (po czasie), potem biegnące od najbliższego końca, wstrzymane, a na
    /// końcu „do włączenia” — timer z kroku, na którym użytkownik już stanął
    /// (bieżący albo wcześniejszy), jeszcze nie włączony. Pominięty przy
    /// „Dalej” nie znika (runda 4 testów: „żebym przez przypadek go nie
    /// pominął” — wcześniej czekał tak tylko „Gdy woda zawrze”); chowa się
    /// dopiero po cofnięciu PRZED jego krok.
    func dockTimers(now: Date) -> [CookDockTimer] {
        var attention: [CookDockTimer] = []
        var running: [(Date, CookDockTimer)] = []
        var paused: [CookDockTimer] = []
        var pending: [CookDockTimer] = []

        for timer in scenario.timers {
            guard let status = self.status(of: timer.id, now: now),
                  let stepIndex = steps.firstIndex(where: { $0.timer?.id == timer.id }) else { continue }
            let item = CookDockTimer(
                timer: timer,
                stepIndex: stepIndex,
                status: status,
                accent: timers[timer.id]?.accent ?? accent(for: timer.id)
            )
            switch status {
            case .overdue:
                attention.append(item)
            case let .running(_, _, endDate):
                running.append((endDate, item))
            case .paused:
                paused.append(item)
            case .pending:
                guard stage == .steps else { continue }
                let isCurrent = stepIndex == self.stepIndex
                let wasReached = stepIndex < self.stepIndex && visitedStepIds.contains(steps[stepIndex].id)
                if isCurrent || wasReached {
                    pending.append(item)
                }
            case .finished:
                continue
            }
        }
        return attention
            + running.sorted { $0.0 < $1.0 }.map { $0.1 }
            + paused
            + pending
    }

    /// Timery w doku, w karcie Timery i w pigułkach — w KOLEJNOŚCI
    /// SCENARIUSZA (krok, który niesie timer), niezależnie od stanu.
    /// Włączenie, pauza, koniec czy „+min” nie przestawiają ich miejscami
    /// (Rafał, 1.10.2026: „nie powinny timery się zamieniać miejscami, jak
    /// załączam”) — kolejność pilności z `dockTimers` przesuwała świeżo
    /// włączony timer na początek, gdy kończył się przed tamtym. Krok ma
    /// najwyżej jeden timer, więc kolejność jest jednoznaczna.
    func timerLineup(now: Date) -> [CookDockTimer] {
        dockTimers(now: now).sorted { $0.stepIndex < $1.stepIndex }
    }

    /// Kapsuły nad wyspą — najwyżej dwie (D33; runda 3 testów: „max 2 —
    /// te najstarsze, które już działają”). Pierwszeństwo mają włączone
    /// timery (trwa, wstrzymany) od najdawniej włączonego; miejsce, które
    /// zostanie, bierze timer do włączenia — też od najstarszego (wcześniejszy
    /// krok). Nowy timer do włączenia NIE wypycha kapsuły, która już stoi,
    /// tylko idzie do plakietki (runda 5: „nie powinien 1 przesuwać, tylko
    /// 3 powinien być w tym chipie u góry”). Wyjątek: timer PO CZASIE stoi
    /// w doku zawsze — wyciszony pulsuje, dopóki nie padnie „Gotowe”, więc nie
    /// może czekać za plakietką. Reszta jest w plakietce nad kapsułami
    /// (`dockOverflow`) i w arkuszu Timery. Na ekranie kapsuły stoją
    /// w kolejności kroków.
    func dockCapsules(now: Date, limit: Int = 2) -> [CookDockTimer] {
        let all = dockTimers(now: now)
        let overdue = all.filter { if case .overdue = $0.status { true } else { false } }
        let started = all
            .filter {
                switch $0.status {
                case .running, .paused: true
                case .pending, .overdue, .finished: false
                }
            }
            .sorted { (timers[$0.id]?.startedAt ?? .distantFuture) < (timers[$1.id]?.startedAt ?? .distantFuture) }
        let waiting = all
            .filter { if case .pending = $0.status { true } else { false } }
            .sorted { $0.stepIndex < $1.stepIndex }
        let chosen = Set((overdue + started + waiting).prefix(limit).map(\.id))
        return all.filter { chosen.contains($0.id) }.sorted { $0.stepIndex < $1.stepIndex }
    }

    /// Timery, które nie zmieściły się w kapsułach — plakietka nad nimi mówi,
    /// co się z nimi dzieje (runda 4: „że timer idzie, że trzeba włączyć,
    /// że jest wstrzymany”). Kolejność pilności z `dockTimers`.
    func dockOverflow(now: Date, limit: Int = 2) -> [CookDockTimer] {
        let shown = Set(dockCapsules(now: now, limit: limit).map(\.id))
        return dockTimers(now: now).filter { !shown.contains($0.id) }
    }

    /// Najbliższy biegnący timer — Live Activity i „Wróć do gotowania”.
    func nearestRunningTimer(now: Date) -> CookDockTimer? {
        dockTimers(now: now).first {
            if case .running = $0.status { return true }
            if case .overdue = $0.status { return true }
            return false
        }
    }

    /// Timer, który właśnie przekroczył czas i jeszcze nie był wyciszony —
    /// ten otwiera pełny ekran końca timera (D35).
    func ringingTimer(now: Date) -> CookDockTimer? {
        dockTimers(now: now).first {
            if case let .overdue(_, _, silenced) = $0.status { return !silenced }
            return false
        }
    }

    /// Czas gotowania na zakończeniu („52 min”) — od „Zaczynamy”.
    func cookingMinutes(now: Date) -> Int {
        let start = cookingStartedAt ?? startedAt
        let end = finishedAt ?? now
        return max(1, Int((end.timeIntervalSince(start) / 60).rounded()))
    }

    /// Podpowiedź do arkusza uwag (§13.3): timer przedłużany co najmniej dwa
    /// razy — „Kotlety +4 min”.
    func extensionHint() -> String? {
        var totals: [String: (count: Int, seconds: Int)] = [:]
        for item in extensions {
            let current = totals[item.timerId] ?? (0, 0)
            totals[item.timerId] = (current.count + 1, current.seconds + item.seconds)
        }
        guard let best = totals.filter({ $0.value.count >= 2 }).max(by: { $0.value.seconds < $1.value.seconds }),
              let timer = scenario.timer(id: best.key) else { return nil }
        return "\(timer.label) +\(best.value.seconds / 60) min"
    }
}

/// Timer włączony w tej sesji. Brak wpisu = jeszcze nie ruszył.
struct CookTimerRun: Codable, Equatable {
    enum State: String, Codable, Equatable {
        case running
        case paused
        /// „Gotowe” — znika z doku.
        case finished
        /// „Pomiń” — znika z doku jak zrobiony, ale wraca jako „do włączenia”,
        /// gdy użytkownik znów stanie na jego kroku.
        case skipped
    }

    let timerId: String
    let stepId: String
    var state: State
    /// Kiedy zadzwoni (tylko `running`); po tej dacie timer jest „po czasie”.
    var endDate: Date?
    /// Ile zostało w chwili pauzy (tylko `paused`).
    var remaining: TimeInterval?
    /// Alarm wyciszony („Wycisz”) — kapsuła pulsuje, ale nie otwiera ekranu końca.
    var silenced: Bool
    /// Suma „+min” — pierścień liczy postęp od pełnego czasu z dodatkami.
    var extendedSeconds: Int
    let startedAt: Date
    let accent: CookTimerAccent
}

/// Kolor timera — pierścień, etykieta, obwódka, przycisk i alarm. Każdy
/// timer przepisu ma swój (runda 3 testów, 1.10.2026: „każdy inny timer inny
/// kolor — kolory posiłków”): po kolei terakota, szałwia, indygo, róż,
/// morska, lawenda, masło — akcent aplikacji i kolory pór posiłków. Bez
/// SwiftUI: kolor rozwiązuje widok.
enum CookTimerAccent: String, Codable, Equatable, CaseIterable {
    case terracotta
    case sage
    case indigo
    case rose
    case teal
    case lavender
    case butter

    /// Kolor `index`-tego timera scenariusza; po siedmiu — od początku.
    static func forTimer(at index: Int) -> CookTimerAccent {
        let count = allCases.count
        return allCases[((index % count) + count) % count]
    }

    /// Nieznany kolor z pliku nowszej wersji = terakota, a nie utracona sesja.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CookTimerAccent(rawValue: raw) ?? .terracotta
    }
}

struct CookTimerExtension: Codable, Equatable {
    let timerId: String
    let stepId: String
    let seconds: Int
    let at: Date
}

/// Stan timera do narysowania.
enum CookTimerStatus: Equatable {
    /// Czeka na start (kapsuła z obwódką, łagodny puls).
    case pending(total: TimeInterval)
    case running(remaining: TimeInterval, total: TimeInterval, endDate: Date)
    /// Wstrzymany — przygaszony, nie zadzwoni.
    case paused(remaining: TimeInterval, total: TimeInterval)
    /// Po czasie — pełny kolor timera, dzwonek, mocny puls; licznik idzie w górę.
    case overdue(over: TimeInterval, total: TimeInterval, silenced: Bool)
    case finished

    /// Ułamek, który ZOSTAŁ (1 → 0) — pierścień ubywa razem z czasem.
    var remainingFraction: Double {
        switch self {
        case .pending: 1
        case let .running(remaining, total, _): total > 0 ? min(1, max(0, remaining / total)) : 0
        case let .paused(remaining, total): total > 0 ? min(1, max(0, remaining / total)) : 0
        case .overdue, .finished: 0
        }
    }
}

/// Kapsuła w doku.
struct CookDockTimer: Equatable, Identifiable {
    let timer: CookTimer
    /// Indeks kroku, który ten timer niesie („krok 3”).
    let stepIndex: Int
    let status: CookTimerStatus
    /// Kolor timera — ten sam przed startem, w trakcie i po czasie.
    let accent: CookTimerAccent

    var id: String { timer.id }
}

/// Zegar timera: „9:41”, „1:02:05”, a po czasie „+0:18”.
enum CookClock {
    static func text(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func overdueText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return "+" + String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Czas timera słowami do podpisów: „15 min”, „10–12 min”, „1 h 20 min”.
    static func duration(_ timer: CookTimer) -> String {
        let low = minutesText(timer.minSeconds)
        guard timer.hasRange else { return low }
        // „10–12 min”; zakres przez godzinę słowami w całości: „50 min – 1 h 10 min”.
        guard timer.maxSeconds < 3600 else { return "\(low) – \(minutesText(timer.maxSeconds))" }
        return "\(Int((Double(timer.minSeconds) / 60).rounded(.up)))–\(minutesText(timer.maxSeconds))"
    }

    static func minutesText(_ seconds: Int) -> String {
        let minutes = Int((Double(seconds) / 60).rounded(.up))
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m == 0 ? "\(h) h" : "\(h) h \(m) min"
        }
        return "\(minutes) min"
    }
}
