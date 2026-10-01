import AppIntents
import Foundation

/// Co przycisk Live Activity każe zrobić sesji gotowania.
nonisolated enum CookActivityAction: String, Sendable {
    /// „Dalej →” — następny krok (na ostatnim: zakończ).
    case next
    /// „+1 min” przy jedynym biegnącym timerze.
    case extend
    /// ▶ na kaflu timera, który czeka na włączenie.
    case startTimer
}

/// Przycisk w Dynamic Island / na ekranie blokady (`Button(intent:)`).
/// `LiveActivityIntent` wykonuje się w PROCESIE APLIKACJI (system budzi ją
/// w tle, jeśli trzeba) — rozszerzenie tylko rysuje przycisk. Logikę sesji
/// zna wyłącznie aplikacja, więc intencja oddaje polecenie przez
/// `CookActivityBridge`, który aplikacja podpina przy starcie.
nonisolated struct CookActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Gotowanie"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Akcja")
    var action: String

    @Parameter(title: "Timer")
    var timerId: String

    init() {}

    init(_ action: CookActivityAction, timerId: String = "") {
        self.action = action.rawValue
        self.timerId = timerId
    }

    func perform() async throws -> some IntentResult {
        if let action = CookActivityAction(rawValue: action) {
            await CookActivityBridge.run(action, timerId: timerId)
        }
        return .result()
    }
}

/// Most z intencji do sesji gotowania w aplikacji (`CookActivityCommands`).
/// W rozszerzeniu zostaje pusty — tam intencja się nie wykonuje.
nonisolated enum CookActivityBridge {
    @MainActor static var handler: (@MainActor (CookActivityAction, String) -> Void)?

    static func run(_ action: CookActivityAction, timerId: String) async {
        await MainActor.run {
            handler?(action, timerId)
        }
    }
}
