import SwiftUI

/// Wspólne krzywe ruchu treści — jedno miejsce zamiast liczb rozsianych
/// po ekranach.
enum SCMotion {
    /// Tekst przechodzący w nowy tekst w miejscu (`contentTransition(.numericText())`):
    /// danie w danie, liczba w liczbę, słowo w słowo. Ta sama krzywa, którą
    /// w arkuszu wyboru posiłku u Asystenta przechodzi nazwa dania
    /// (`smooth` 0,42 s) — Kalendarz rolował dotąd `easeInOut` 0,30 s
    /// i wyglądał na „inną animację” niż reszta aplikacji (24.09.2026).
    static let textRoll: Animation = .smooth(duration: 0.42)
}
