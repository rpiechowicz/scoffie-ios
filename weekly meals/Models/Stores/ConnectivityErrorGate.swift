import Foundation

/// Tłumi mignięcia banera „Problem z połączeniem na żywo. Spróbuj ponownie.".
///
/// Po powrocie aplikacji z tła odświeżenia strzelają w socket, który po
/// wybudzeniu jeszcze nie wstał — pierwszy strzał kończy się błędem
/// łączności, a 250–300 ms później reconnect i ponowny load go naprawiają.
/// Pokazywanie takiego błędu od razu dawało czerwony alert na pół sekundy
/// na każdym widoku dashboardu.
///
/// Zasada: błąd łączności trafia do `errorMessage` dopiero, gdy utrzyma się
/// przez `delay` bez udanego odświeżenia. Każdy start nowego loadu (i każdy
/// sukces) woła `reset()` i kasuje komunikat, który nie zdążył się pokazać.
/// Błędy inne niż łącznościowe (walidacja, uprawnienia) pokazują się jak
/// dotąd — natychmiast.
@MainActor
final class ConnectivityErrorGate {
    private var pendingTask: Task<Void, Never>?
    private let delay: Duration

    // `nonisolated`, bo bramkę tworzą w property initializerach także store'y,
    // które same nie są przypięte do MainActora (WeeklyMealStore, katalog).
    nonisolated init(delay: Duration = .seconds(2)) {
        self.delay = delay
    }

    /// Publikuje komunikat błędu przez `present` — od razu dla zwykłych
    /// błędów, z opóźnieniem dla błędów łączności.
    func publish(_ error: Error, present: @escaping @MainActor (String) -> Void) {
        let message = UserFacingErrorMapper.message(from: error)
        guard UserFacingErrorMapper.isConnectivityIssue(error) else {
            reset()
            present(message)
            return
        }
        pendingTask?.cancel()
        pendingTask = Task { @MainActor [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            present(message)
        }
    }

    /// Anuluje oczekujący komunikat — wołane na początku każdego loadu,
    /// żeby chwilowy błąd naprawiony przez reconnect nigdy nie mignął.
    func reset() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}
