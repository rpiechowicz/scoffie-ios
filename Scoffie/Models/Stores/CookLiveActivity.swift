import ActivityKit
import Foundation
import SwiftUI
import UIKit

/// Live Activity sesji gotowania (E5, wariant B z §8.4): JEDNA aktywność na
/// sesję, widoki w rozszerzeniu `ScoffieCookActivity`, typy w `Shared/`.
///
/// Stan liczy się z sesji przy KAŻDEJ zmianie (`sync` — te same miejsca co
/// alarmy systemowe): aktywność rusza z pierwszym krokiem, aktualizuje się
/// przy zmianie kroku i timerów, kończy na zakończeniu albo „Zakończ”.
/// Odliczania nie odświeżamy co sekundę — widoki czasowe w rozszerzeniu
/// liczą same z dat początku i końca.
@MainActor
final class CookLiveActivity {
    static let shared = CookLiveActivity()

    private var latest: CookSession?
    private var syncTask: Task<Void, Never>?
    private var needsResync = false
    private var lastState: CookActivityAttributes.ContentState?

    private init() {}

    func sync(_ session: CookSession?) {
        latest = session
        guard syncTask == nil else {
            needsResync = true
            return
        }
        syncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                self.needsResync = false
                await self.apply(self.latest)
            } while self.needsResync
            self.syncTask = nil
        }
    }

    /// Czeka, aż aktywność dostanie ostatni stan — przycisk Live Activity
    /// oddaje wynik dopiero potem (`CookActivityCommands`).
    func settled() async {
        await syncTask?.value
    }

    private func apply(_ session: CookSession?) async {
        let running = Activity<CookActivityAttributes>.activities
        guard let session, session.stage == .steps else {
            for activity in running {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            lastState = nil
            return
        }

        let recipeId = session.recipeId.uuidString
        let state = Self.state(for: session, now: Date())
        for activity in running where activity.attributes.recipeId != recipeId {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        if let activity = running.first(where: { $0.attributes.recipeId == recipeId }) {
            guard state != lastState else { return }
            await activity.update(ActivityContent(state: state, staleDate: nil))
            lastState = state
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        await Self.writePhoto(for: session)
        let attributes = CookActivityAttributes(recipeId: recipeId, recipeTitle: session.recipeTitle)
        do {
            _ = try Activity<CookActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            lastState = state
        } catch {
            // Bez Live Activity gotowanie trwa dalej — alarm i tak zadzwoni.
        }
    }

    // MARK: - Stan

    static func state(for session: CookSession, now: Date) -> CookActivityAttributes.ContentState {
        let nextIndex = session.stepIndex + 1
        let next = session.steps.indices.contains(nextIndex) ? session.steps[nextIndex] : nil
        let nextMinutes = next?.timer.map { Int((Double($0.minSeconds) / 60).rounded()) }
        return CookActivityAttributes.ContentState(
            stepIndex: session.stepIndex,
            stepCount: session.stepCount,
            stepTitle: session.currentStep?.title ?? "",
            nextTitle: next?.title,
            nextTimerMinutes: nextMinutes,
            timers: session.dockCapsules(now: now).compactMap { timer(from: $0, session: session) }
        )
    }

    private static func timer(from item: CookDockTimer, session: CookSession) -> CookActivityTimer? {
        let color = rgb(item.accent)
        switch item.status {
        case let .pending(total):
            return CookActivityTimer(
                id: item.id, label: item.timer.label, color: color, phase: .pending,
                start: nil, end: nil, remaining: total, total: total, startLabel: item.timer.startLabel
            )
        case let .running(_, total, endDate):
            return CookActivityTimer(
                id: item.id, label: item.timer.label, color: color, phase: .running,
                start: endDate.addingTimeInterval(-total), end: endDate, remaining: nil, total: total, startLabel: nil
            )
        case let .paused(remaining, total):
            return CookActivityTimer(
                id: item.id, label: item.timer.label, color: color, phase: .paused,
                start: nil, end: nil, remaining: remaining, total: total, startLabel: nil
            )
        case let .overdue(_, total, _):
            let end = session.timers[item.id]?.endDate
            return CookActivityTimer(
                id: item.id, label: item.timer.label, color: color, phase: .overdue,
                start: end?.addingTimeInterval(-total), end: end, remaining: nil, total: total, startLabel: nil
            )
        case .finished:
            return nil
        }
    }

    /// Kolor timera w wariancie ciemnym (Dynamic Island i karta ekranu
    /// blokady stoją na ciemnym tle) jako 0xRRGGBB.
    private static func rgb(_ accent: CookTimerAccent) -> UInt32 {
        let resolved = UIColor(accent.color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> UInt32 {
            UInt32(max(0, min(255, (value * 255).rounded())))
        }
        return (channel(red) << 16) | (channel(green) << 8) | channel(blue)
    }

    // MARK: - Zdjęcie

    /// Miniatura 144 px do kontenera App Group — rozszerzenie nie sięga do
    /// sieci ani do pamięci podręcznej aplikacji.
    private static func writePhoto(for session: CookSession) async {
        guard let url = CookActivityImage.url(recipeId: session.recipeId.uuidString),
              !FileManager.default.fileExists(atPath: url.path),
              let imageURL = session.imageURL,
              let image = await ImagePrefetcher.image(for: imageURL, variant: .thumbnail),
              image.size.width > 0, image.size.height > 0 else { return }
        let side: CGFloat = 144
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let thumbnail = renderer.image { _ in
            let scale = max(side / image.size.width, side / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }
        guard let data = thumbnail.jpegData(compressionQuality: 0.8) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// Polecenia z przycisków Live Activity (`CookActivityIntent`) — te same
/// ruchy co w trybie Gotuj. Aplikacja bywa obudzona w tle, zanim sesja konta
/// wstanie: wtedy sklep sesji odtwarza się z pliku (`CookSessionStore.forIntent`).
enum CookActivityCommands {
    static func register() {
        CookActivityBridge.handler = { action, timerId in
            await handle(action, timerId: timerId)
        }
    }

    /// Zmiana sesji + czekanie, aż Live Activity i alarmy ją dostaną.
    static func handle(_ action: CookActivityAction, timerId: String) async {
        guard let store = CookSessionStore.forIntent() else { return }
        let now = Date()
        store.update { session in
            switch action {
            case .next:
                session.next(now: now)
            case .extend:
                session.extendTimer(timerId, by: 60, now: now)
            case .startTimer:
                session.startTimer(timerId, now: now)
            }
        }
        await CookLiveActivity.shared.settled()
        await CookAlarmScheduler.shared.settled()
    }
}
