import UIKit

/// Prośba do systemu o kilkadziesiąt sekund na dokończenie pracy, która
/// właśnie trwa — także wtedy, gdy aplikacja schodzi w tło albo została
/// obudzona cichym pushem i zaraz zostanie uśpiona.
///
/// Powód jej istnienia jest konkretny i kosztował sesje użytkowników.
/// Rotacja refresh tokenu ma dwa kroki, których NIE WOLNO rozdzielić: serwer
/// unieważnia stary token i wydaje nowy, a telefon musi ten nowy zapisać.
/// Między nimi jest żądanie sieciowe. iOS może uśpić proces dokładnie tam —
/// najłatwiej po cichym pushu, bo `completionHandler` wraca od razu i system
/// uznaje, że praca się skończyła. Wtedy serwer ma token zrotowany, a telefon
/// poprzedni; przy następnym uruchomieniu wygląda to jak kradzież i kończy się
/// wylogowaniem ze WSZYSTKICH urządzeń.
///
/// Asercja nie daje gwarancji (system może ją odebrać — stąd `expiration`),
/// ale zamienia „proces ginie w połowie" z rzeczy normalnej w rzadką.
@MainActor
final class BackgroundActivity {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    /// Zaczyna asercję. `end()` MUSI dojść po zakończeniu pracy — asercja,
    /// której nikt nie kończy, jest w iOS powodem ubicia aplikacji.
    static func begin(name: String) -> BackgroundActivity {
        let activity = BackgroundActivity()
        activity.identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            // System odbiera czas: kończymy asercję sami, zanim zrobi to za nas
            // zabiciem procesu. Praca w locie i tak może nie zdążyć — od tego
            // jest okno ratunku po stronie serwera.
            activity.end()
        }
        return activity
    }

    /// Idempotentne: podwójne `endBackgroundTask` tym samym identyfikatorem
    /// jest błędem API, a `end()` woła i wywołujący, i `expiration`.
    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
