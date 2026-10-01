import AlarmKit
import Foundation
import SwiftUI

/// Koniec timera Gotuj jako ALARM SYSTEMOWY (AlarmKit, runda 11: „w ogóle
/// nie działa na zablokowanym ekranie”, „dźwięk minutnika systemowego”).
///
/// Wariant B z §8.4 planu (docs/workstreams/gotuj/README.md): alarm na
/// GODZINĘ KOŃCA (`Alarm.Schedule.fixed`), bez prezentacji odliczania.
/// AlarmKit z odliczaniem wymaga rozszerzenia widżetów — bez niego „system
/// może nieoczekiwanie zdjąć alarm i nie zadzwonić” (dokumentacja Apple) —
/// a alarm na godzinę go nie potrzebuje. Daje to, co Zegar: systemowy
/// dźwięk alarmu, dzwonienie mimo wyciszenia i trybu skupienia, pełny alert
/// na ekranie blokady i w Dynamic Island w chwili końca. Odliczanie
/// w Dynamic Island w trakcie = Live Activity w E5.
///
/// Stan jest liczony z sesji przy każdej zmianie (`sync`): każdy biegnący,
/// niewyciszony timer ma alarm o id wyliczonym z sesji, timera i godziny
/// końca — po „+2 min” godzina się zmienia, więc stary alarm odchodzi,
/// a nowy wchodzi; po restarcie aplikacji te same id pozwalają rozpoznać
/// alarmy, które już stoją w systemie. Timer po czasie zachowuje alarm,
/// który właśnie dzwoni (nie planuje nowego), aż do „Wycisz” / „Gotowe”.
///
/// Odmowa zgody (albo iOS bez AlarmKit) = dawna droga: powiadomienie w tle
/// (`CookTimerNotifications`) i dźwięk w aplikacji (`CookAlarmView`).
@MainActor
final class CookAlarmScheduler {
    static let shared = CookAlarmScheduler()

    /// „Zatrzymaj” na alercie systemowym (ekran blokady, Dynamic Island):
    /// timer i godzina końca alarmu, który zniknął po czasie. Sklep sesji
    /// wycisza wtedy timer — człowiek już zareagował.
    var onAcknowledged: ((_ timerId: String, _ end: Date) -> Void)?

    /// Alarmy, które ostatnio zaplanowaliśmy: id → timer i godzina końca.
    private var known: [UUID: (timerId: String, end: Date)] = [:]
    private var latest: CookSession?
    private var isSyncing = false
    private var needsResync = false
    private var observer: Task<Void, Never>?

    private init() {}

    /// Dzwonienie przejmuje system — zgoda na alarmy jest.
    var isAuthorized: Bool {
        AlarmManager.shared.authorizationState == .authorized
    }

    /// Któryś alarm Gotuj właśnie dzwoni systemowym dźwiękiem — ekran końca
    /// timera nie dokłada wtedy swojego.
    var isSystemAlerting: Bool {
        let alarms = (try? AlarmManager.shared.alarms) ?? []
        return alarms.contains { $0.state == .alerting }
    }

    /// Uzgadnia alarmy systemu z sesją. Wywołania w trakcie trwającego
    /// uzgadniania zlewają się w jedno kolejne — zawsze z NAJNOWSZĄ sesją.
    func sync(_ session: CookSession?) {
        latest = session
        startObservingIfNeeded()
        guard !isSyncing else {
            needsResync = true
            return
        }
        isSyncing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                self.needsResync = false
                await self.apply(self.latest)
            } while self.needsResync
            self.isSyncing = false
        }
    }

    // MARK: - Uzgadnianie

    private struct Plan {
        let timerId: String
        let end: Date
        let title: String
        let accent: CookTimerAccent
    }

    private func apply(_ session: CookSession?) async {
        let manager = AlarmManager.shared
        var desired: [UUID: Plan] = [:]
        if let session, session.stage == .steps {
            for run in session.timers.values where run.state == .running && !run.silenced {
                guard let end = run.endDate, let timer = session.scenario.timer(id: run.timerId) else { continue }
                let id = Self.alarmID(session: session, timerId: run.timerId, end: end)
                desired[id] = Plan(timerId: run.timerId, end: end, title: timer.alert.title, accent: run.accent)
            }
        }

        // Zgoda przy pierwszym starcie timera, nie przy wejściu w tryb (§8.3).
        if !desired.isEmpty, manager.authorizationState == .notDetermined {
            _ = try? await manager.requestAuthorization()
        }
        guard manager.authorizationState == .authorized else {
            known = [:]
            return
        }

        let existing = (try? manager.alarms) ?? []
        let existingIDs = Set(existing.map(\.id))
        for alarm in existing where desired[alarm.id] == nil {
            if alarm.state == .alerting {
                try? manager.stop(id: alarm.id)
            }
            try? manager.cancel(id: alarm.id)
        }

        let now = Date()
        for (id, plan) in desired where !existingIDs.contains(id) && plan.end > now.addingTimeInterval(1) {
            _ = try? await manager.schedule(id: id, configuration: Self.configuration(plan))
        }
        known = desired.mapValues { (timerId: $0.timerId, end: $0.end) }
    }

    private static func configuration(_ plan: Plan) -> AlarmManager.AlarmConfiguration<CookAlarmMetadata> {
        let title = LocalizedStringResource(stringLiteral: plan.title)
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            // Od 26.1 przycisk „Zatrzymaj” rysuje system.
            alert = AlarmPresentation.Alert(title: title)
        } else {
            alert = AlarmPresentation.Alert(
                title: title,
                stopButton: AlarmButton(text: "Wycisz", textColor: .white, systemImageName: "bell.slash")
            )
        }
        let attributes = AlarmAttributes<CookAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: CookAlarmMetadata(timerId: plan.timerId),
            tintColor: Self.tint(plan.accent)
        )
        // Bez `sound:` = domyślny dźwięk alarmu systemu.
        return .alarm(schedule: .fixed(plan.end), attributes: attributes)
    }

    /// Kolor timera rozwiązany do stałej wartości — atrybuty alarmu są
    /// zapisywane, a kolor zależny od motywu nie przeżyłby zapisu.
    private static func tint(_ accent: CookTimerAccent) -> Color {
        Color(accent.color.resolve(in: EnvironmentValues()))
    }

    /// Id alarmu z sesji, timera i godziny końca (ms) — te same dane dają to
    /// samo id także po restarcie aplikacji.
    private static func alarmID(session: CookSession, timerId: String, end: Date) -> UUID {
        let started = Int64((session.startedAt.timeIntervalSince1970 * 1000).rounded())
        let ends = Int64((end.timeIntervalSince1970 * 1000).rounded())
        let key = "cook|\(started)|\(timerId)|\(ends)"
        // FNV-1a na dwóch ziarnach = 128 bitów; kryptografia niepotrzebna,
        // liczy się tylko powtarzalność.
        var high: UInt64 = 0xcbf2_9ce4_8422_2325
        var low: UInt64 = 0x8422_2325_cbf2_9ce4
        for byte in key.utf8 {
            high = (high ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            low = (low ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 &+ 0x9e37_79b9
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8(truncatingIfNeeded: high >> (8 * UInt64(index)))
            bytes[index + 8] = UInt8(truncatingIfNeeded: low >> (8 * UInt64(index)))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return NSUUID(uuidBytes: bytes) as UUID
    }

    // MARK: - „Zatrzymaj” z systemu

    private func startObservingIfNeeded() {
        guard observer == nil else { return }
        observer = Task { @MainActor [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                self?.handle(alarms)
            }
        }
    }

    /// Alarm, który zniknął PO swojej godzinie, został zatrzymany na
    /// alercie systemu. Zniknięcia z naszej ręki (wyciszenie, „Gotowe”,
    /// „+2 min”) odsiewa sklep: wycisza tylko timer, który dalej biegnie
    /// z TĄ SAMĄ godziną końca i nie jest wyciszony.
    private func handle(_ alarms: [Alarm]) {
        let present = Set(alarms.map(\.id))
        let now = Date()
        for (id, info) in known where !present.contains(id) && info.end <= now {
            known[id] = nil
            onAcknowledged?(info.timerId, info.end)
        }
    }
}
