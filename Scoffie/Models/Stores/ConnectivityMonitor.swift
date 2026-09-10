import Foundation
import Network
import Observation

/// Jedna prawda o tym, czy aplikacja ma łączność — i jedyne miejsce, które ma
/// prawo o tym powiedzieć użytkownikowi.
///
/// # Dlaczego nie sam `NWPathMonitor`
///
/// Odczyt interfejsu mówi, że telefon MA DOKĄD wysłać pakiet, a nie że pakiet
/// dojdzie. Wi-Fi w hotelu z portalem logowania, router bez WAN, backend
/// leżący przy działającym internecie — w każdym z tych przypadków ścieżka
/// jest `satisfied`, a aplikacja nie działa. Apple wprost odradza sprawdzanie
/// łączności PRZED żądaniem właśnie dlatego.
///
/// Dlatego monitor łączy dwa źródła:
/// - **interfejs** (`NWPathMonitor`) — szybki, ale tylko poszlaka,
/// - **prawdziwy ruch** — czy z serwera przyszła JAKAKOLWIEK odpowiedź.
///   Odpowiedź 500 jest tu tak samo dobrym dowodem łączności jak 200.
///
/// # Dlaczego z opóźnieniem
///
/// Tak robią aplikacje, na których to działa dobrze (Slack, Gmail, Spotify):
/// wolno biją na alarm, natychmiast odwołują. Sieć w telefonie rwie się co
/// chwilę — przy przełączaniu Wi-Fi na LTE, przy wyjściu z windy, przy
/// wybudzeniu aplikacji z tła. Pasek pokazany po pierwszym nieudanym żądaniu
/// migałby kilkanaście razy dziennie bez żadnego pożytku, bo zanim
/// użytkownik zdąży go przeczytać, sieć już wraca.
///
/// Stąd asymetria: **offline ogłaszamy dopiero po `offlineDelay` nieprzerwanych
/// kłopotów, a powrót — natychmiast**. Zawyżona zwłoka kosztuje kilka sekund
/// niewiedzy; zaniżona kosztuje wiarygodność paska, który krzyczy po nic.
@MainActor
@Observable
final class ConnectivityMonitor {
    /// Sieć jest jedna, więc i monitor jest jeden. Sięgają po niego także
    /// store, które nie są widokami i nie mają jak dostać nic ze środowiska.
    static let shared = ConnectivityMonitor()

    /// Stan OGŁOSZONY — ten, na którym opiera się pasek. Nie jest tym samym,
    /// co „ostatnie żądanie padło": zapala się dopiero, gdy kłopoty trwają.
    private(set) var isOffline = false

    /// Czy telefon w ogóle MA gdzie wysłać pakiet.
    ///
    /// Publiczne, bo rozstrzyga, co powiedzieć: przy braku interfejsu winne
    /// jest łącze użytkownika, a przy interfejsie działającym i padających
    /// żądaniach — droga do serwera. Zwalanie tego drugiego na „sprawdź
    /// internet" wysyła człowieka do restartu routera, który niczego nie
    /// naprawi.
    private(set) var isPathSatisfied = true

    /// Ile muszą trwać nieprzerwane kłopoty, zanim powiemy o nich
    /// użytkownikowi. Sześć sekund to z jednej strony wyraźnie więcej niż
    /// przełączenie Wi-Fi na LTE albo reconnect socketu po powrocie z tła
    /// (~0,3 s), z drugiej — wciąż na tyle krótko, że nikt nie zdąży uznać
    /// zastygniętego ekranu za zepsutą aplikację.
    private static let offlineDelay: Duration = .seconds(6)

    /// Ile czekamy na potwierdzenie ruchem po powrocie interfejsu. Sam powrót
    /// Wi-Fi nie jest dowodem — patrz portal logowania w komentarzu klasy.
    private static let recoveryGrace: Duration = .seconds(1.5)

    private let pathMonitor = NWPathMonitor()
    private var isStarted = false
    /// Znacznik nieudanego żądania. `nil` znaczy „od ostatniego resetu nic nie
    /// padło" i jest warunkiem ogłoszenia powrotu.
    private var lastFailureAt: Date?
    private var suspicion: Task<Void, Never>?
    private var recovery: Task<Void, Never>?

    private init() {}

    /// Startuje nasłuch interfejsu. Wołane raz, z korzenia aplikacji.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        pathMonitor.pathUpdateHandler = { path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                ConnectivityMonitor.shared.apply(pathSatisfied: satisfied)
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "app.scoffie.connectivity"))
    }

    // MARK: - Wejścia z warstwy sieci
    //
    // `nonisolated`, bo woła je kod żądań, który nie stoi na głównym aktorze.
    // Przeskok na główny wątek kosztuje jedno zadanie na żądanie HTTP — przy
    // rzeczy, która i tak właśnie poszła przez radio, to nie jest koszt.

    /// Serwer odpowiedział — cokolwiek by nie odpowiedział.
    ///
    /// To jest najmocniejszy dowód łączności, jaki aplikacja może mieć, więc
    /// gasi pasek NATYCHMIAST, bez żadnej zwłoki.
    nonisolated static func noteResponse() {
        Task { @MainActor in shared.applyResponse() }
    }

    /// Transport padł, zanim doszło do odpowiedzi — offline, DNS, timeout,
    /// zerwany socket.
    nonisolated static func noteTransportFailure() {
        Task { @MainActor in shared.applyFailure() }
    }

    // MARK: - Maszyna stanów

    private func applyResponse() {
        lastFailureAt = nil
        cancelPending()
        isOffline = false
    }

    private func applyFailure() {
        lastFailureAt = .now
        recovery?.cancel()
        recovery = nil
        beginSuspicion()
    }

    private func apply(pathSatisfied satisfied: Bool) {
        guard satisfied != isPathSatisfied else { return }
        isPathSatisfied = satisfied

        guard satisfied else {
            // Brak interfejsu to jedyny przypadek, w którym wiemy na pewno,
            // że nic nie przejdzie. Ale nadal czekamy `offlineDelay` — tryb
            // samolotowy włączony na dwie sekundy przez przypadek nie musi
            // zostawiać po sobie komunikatu.
            beginSuspicion()
            return
        }

        // Interfejs wrócił. To jeszcze nie znaczy, że jest internet, więc nie
        // gasimy paska od razu — dajemy sieci chwilę i gasimy tylko wtedy,
        // gdy w tym czasie nic nie padło. Pierwsze nowe niepowodzenie uzbroi
        // podejrzenie od nowa i pasek zostanie.
        scheduleRecovery()
    }

    private func beginSuspicion() {
        // Podejrzenie liczy się od PIERWSZEGO kłopotu, więc kolejne go nie
        // przedłużają — inaczej sypiąca się seria żądań w kółko odsuwałaby
        // moment, w którym w ogóle cokolwiek powiemy.
        guard !isOffline, suspicion == nil else { return }
        suspicion = Task { [weak self] in
            try? await Task.sleep(for: Self.offlineDelay)
            guard !Task.isCancelled else { return }
            self?.declareOffline()
        }
    }

    private func declareOffline() {
        suspicion = nil
        isOffline = true
    }

    private func scheduleRecovery() {
        cancelPending()
        lastFailureAt = nil
        recovery = Task { [weak self] in
            try? await Task.sleep(for: Self.recoveryGrace)
            guard !Task.isCancelled, let self else { return }
            guard self.isPathSatisfied, self.lastFailureAt == nil else { return }
            self.isOffline = false
        }
    }

    private func cancelPending() {
        suspicion?.cancel()
        suspicion = nil
        recovery?.cancel()
        recovery = nil
    }
}
