import ActivityKit
import AlarmKit
import Foundation

// Pliki w `Shared/` kompilują się do OBU targetów: aplikacji (domyślna
// izolacja MainActor) i rozszerzenia widżetów (bez niej) — stąd jawne
// `nonisolated` na każdym typie. Bez SwiftUI-owych żetonów aplikacji
// (`SCPalette`, `SCCook`): rozszerzenie ich nie ma.

/// Metadane alarmu Gotuj (`CookAlarmScheduler`).
nonisolated struct CookAlarmMetadata: AlarmMetadata {
    let timerId: String
}

/// Live Activity sesji gotowania (E5, wariant B z §8.4 planu): JEDNA
/// aktywność na sesję — krok, pierścień kroków albo timera wokół zdjęcia,
/// do dwóch timerów doku. Koniec timera dzwoni osobno (AlarmKit, alarm na
/// godzinę), więc aktywność tylko pokazuje. Odliczanie rysują widoki
/// czasowe (`Text(timerInterval:)`, `ProgressView(timerInterval:)`) — bez
/// aktualizacji co sekundę; aplikacja aktualizuje stan przy każdej zmianie
/// sesji (`CookLiveActivity`).
nonisolated struct CookActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        /// Bieżący krok, od 0.
        var stepIndex: Int
        var stepCount: Int
        var stepTitle: String
        /// „Dalej: Przełóż do piekarnika · 5 min” — gdy nic nie odlicza.
        var nextTitle: String?
        var nextTimerMinutes: Int?
        /// Kapsuły doku w kolejności kroków — najwyżej dwie (D33).
        var timers: [CookActivityTimer]
    }

    let recipeId: String
    let recipeTitle: String
}

/// Timer w Live Activity — tyle, ile trzeba do narysowania bez aplikacji.
nonisolated struct CookActivityTimer: Codable, Hashable, Identifiable {
    nonisolated enum Phase: String, Codable, Hashable {
        case running
        case paused
        case overdue
        /// Czeka na włączenie — kafel przerywany z warunkiem startu.
        case pending
    }

    let id: String
    /// RZECZ („Ziemniaki”), ≤ 14 znaków.
    let label: String
    /// Kolor timera jako 0xRRGGBB — każdy timer przepisu ma swój.
    let color: UInt32
    let phase: Phase
    /// Początek i koniec odliczania (`running`, `overdue`): pierścień i zegar
    /// liczą się z tego przedziału same, bez aktualizacji.
    let start: Date?
    let end: Date?
    /// Zostało (`paused`) albo cały czas (`pending`), w sekundach.
    let remaining: Double?
    /// Pełny czas z dodatkami „+min” — łuk pauzy liczy się od niego.
    let total: Double
    /// „Woda wrze?” — warunek startu timera, który czeka.
    let startLabel: String?
}

/// Zdjęcie dania dla Live Activity. Rozszerzenie nie pobiera obrazów z sieci,
/// więc aplikacja zapisuje małą miniaturę do kontenera App Group.
nonisolated enum CookActivityImage {
    static let appGroup = "group.app.scoffie.ios"

    static func url(recipeId: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("cook-activity", isDirectory: true)
            .appendingPathComponent("\(recipeId).jpg")
    }
}
