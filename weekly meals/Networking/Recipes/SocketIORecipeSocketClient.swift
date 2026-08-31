import Foundation
import SocketIO

/// Real Socket.IO-backed implementation of `RecipeSocketClient`.
/// Owns the connection lifecycle and provides bounded retries on ACK timeouts.
///
/// Od Fazy 0 handshake niesie access token (`connect(withPayload:)` →
/// `socket.handshake.auth.token` po stronie serwera). Tożsamość ustala
/// serwer z tokenu; `userId` w payloadach eventów zostaje na jedno wydanie
/// (serwer w trybie `soft` ignoruje je dla socketu z tokenem).
///
/// Odmowa serwera przychodzi jako `connect_error`, w tej bibliotece
/// zdarzenie `.error` z danymi `[["message": …, "data": ["code": "UNAUTHORIZED",
/// "reason": …]]]` — ten sam kanał, którym idą błędy silnika (`[String]`),
/// więc rozróżniamy po kształcie. Po odmowie zatrzymujemy auto-reconnect:
/// biblioteka wysyła przy nim token zapamiętany z pierwszego `connect`, więc
/// bez `reconnectWithFreshToken()` biłaby w serwer wygasłym tokenem bez końca.
///
/// Stan (`didAuthFail`, `isClosed`) żyje na `socketQueue` — tej samej kolejce,
/// na której biblioteka woła handlery (`.handleQueue`). Handlery nigdy nie
/// robią `socketQueue.sync` (deadlock); zmiany stanu idą przez `async`.
final class SocketIORecipeSocketClient: RecipeSocketClient {
    private let manager: SocketManager
    private let socket: SocketIOClient
    private let socketQueue = DispatchQueue(label: "weeklymeals.socket.io.serial")
    private let ackTimeoutSeconds: Double = 6
    private let maxAckAttempts: Int = 3
    /// Token czytany per `connect`, nie trzymany — Keychain jest źródłem
    /// prawdy, a po odświeżeniu kolejny connect bierze nową wartość.
    private let tokenProvider: () -> String?
    private var connectionObservers: [UUID: (Bool) -> Void] = [:]
    private var authFailureObservers: [UUID: (String) -> Void] = [:]
    private let connectionObserversQueue = DispatchQueue(label: "weeklymeals.socket.connection-observers")
    /// Po odmowie auth `connectIfNeeded` nie łączy — czeka na
    /// `reconnectWithFreshToken()` po refreshu albo na jedną próbę z foregroundu.
    private var didAuthFail = false
    /// Po `disconnect()` klient jest martwy na dobre (wylogowanie, wymiana
    /// socketu sesji). Bez tej flagi ponowienie acka „NO ACK" wskrzeszałoby
    /// stary socket przez `ensureConnected` — z ważnym tokenem i wszystkimi
    /// handlerami `households:*`, dublując zdarzenia w nowym sockecie.
    private var isClosed = false
    /// Serwer odpowiedział `connect_error` innym niż odmowa auth (np.
    /// `SERVICE_UNAVAILABLE` — baza padła w trakcie weryfikacji). Silnik zostaje
    /// otwarty, a klient tkwi w `.connecting` bez ponowienia; ponawiamy sami,
    /// z rosnącym odstępem, dopóki serwer nie wpuści albo nie odmówi.
    private var pendingTransientRetry = false
    private var transientRetryDelay: TimeInterval = 2
    private static let maxTransientRetryDelay: TimeInterval = 30

    /// Zdarzenie serwera tuż przed rozłączeniem po wygaśnięciu tokenu
    /// (`src/common/ws-auth.adapter.ts`, `WS_AUTH_EXPIRED_EVENT`).
    private static let authExpiredEvent = "auth:expired"

    private struct SocketClosedError: Error {}

    init(baseURL: URL, tokenProvider: @escaping () -> String? = { nil }) {
        self.tokenProvider = tokenProvider
        self.manager = SocketManager(
            socketURL: baseURL,
            config: [
                .log(false),
                .compress,
                .forceWebsockets(true),
                .handleQueue(socketQueue),
                // Domyślny backoff biblioteki potrafi czekać ~10 s z ponowieniem.
                // Po wybudzeniu z tła to całe okno, w którym każde odświeżenie
                // strzela w martwy socket i kończy się błędem łączności —
                // krótszy backoff zamyka je do ~1 s.
                .reconnectWait(1),
                .reconnectWaitMax(5)
            ]
        )
        self.socket = manager.defaultSocket
        registerConnectionLifecycleEvents()
        socketQueue.async { [weak self] in
            self?.connectWithToken()
        }
    }

    deinit {
        // Klient może zniknąć bez `disconnect()` (ostatnia referencja puszczona
        // w trakcie wymiany socketu) — manager żyje własnym timerem reconnectu
        // i bez tego wysłałby jeszcze CONNECT z zapamiętanym tokenem.
        manager.reconnects = false
        manager.disconnect()
    }

    /// `connect(withPayload:)` — payload trafia do pakietu CONNECT, czyli do
    /// `handshake.auth` na serwerze. Bez tokenu (brak sesji) łączymy jak dawniej;
    /// serwer w trybie `soft` wpuszcza taki socket jako legacy.
    private func connectWithToken() {
        if let token = tokenProvider(), !token.isEmpty {
            socket.connect(withPayload: ["token": token])
        } else {
            socket.connect()
        }
    }

    private func registerConnectionLifecycleEvents() {
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            guard let self else { return }
            // Handler biegnie na socketQueue — bez `sync`.
            self.pendingTransientRetry = false
            self.transientRetryDelay = 2
            self.notifyConnectionObservers(isConnected: true)
        }
        // `.reconnect` w tej bibliotece oznacza POCZĄTEK próby ponownego
        // połączenia (status `.connecting`), nie jej sukces — sukces przyjdzie
        // jako `.connect`. Dawniej oba dawały „połączono", więc obserwatorzy
        // strzelali odświeżeniami w martwy socket.
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            self?.notifyConnectionObservers(isConnected: false)
        }
        socket.on(clientEvent: .error) { [weak self] data, _ in
            guard let self else { return }
            if let reason = Self.authRejectionReason(in: data) {
                self.handleAuthFailure(reason: reason)
            } else if Self.isServerConnectError(data) {
                self.scheduleTransientRetry()
                self.notifyConnectionObservers(isConnected: false)
            } else {
                self.notifyConnectionObservers(isConnected: false)
            }
        }
        socket.on(Self.authExpiredEvent) { [weak self] _, _ in
            self?.handleAuthFailure(reason: "expired")
        }
    }

    /// `connect_error` z serwera: `[{"message": String, "data": {"code": "UNAUTHORIZED", "reason": String, …}}]`.
    /// Błąd silnika to `[String]` — wtedy `nil`.
    private static func authRejectionReason(in data: [Any]) -> String? {
        guard let first = data.first as? [String: Any],
              let payload = first["data"] as? [String: Any],
              (payload["code"] as? String) == "UNAUTHORIZED"
        else { return nil }
        return (payload["reason"] as? String) ?? "unauthorized"
    }

    /// `connect_error` z serwera (słownik `message`/`data`) — w odróżnieniu od
    /// błędu silnika (`[String]`), po którym biblioteka sama reconnectuje.
    private static func isServerConnectError(_ data: [Any]) -> Bool {
        data.first is [String: Any]
    }

    /// Po `SERVICE_UNAVAILABLE` (i każdym nie-auth `connect_error`) silnik jest
    /// otwarty, a namespace nie — biblioteka nie ponawia. `connect(withPayload:)`
    /// na `.connecting` wysyła nowy pakiet CONNECT tym samym silnikiem.
    private func scheduleTransientRetry() {
        socketQueue.async { [weak self] in
            guard let self, !self.isClosed, !self.didAuthFail else { return }
            self.pendingTransientRetry = true
            let delay = self.transientRetryDelay
            self.transientRetryDelay = min(delay * 2, Self.maxTransientRetryDelay)
            self.socketQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !self.isClosed, !self.didAuthFail,
                      self.pendingTransientRetry, self.socket.status == .connecting
                else { return }
                self.connectWithToken()
            }
        }
    }

    private func handleAuthFailure(reason: String) {
        socketQueue.async { [weak self] in
            guard let self, !self.didAuthFail, !self.isClosed else { return }
            self.pendingTransientRetry = false
            self.didAuthFail = true
            self.manager.reconnects = false
            self.manager.disconnect()
            self.notifyConnectionObservers(isConnected: false)
            self.notifyAuthFailureObservers(reason: reason)
        }
    }

    private func notifyConnectionObservers(isConnected: Bool) {
        connectionObserversQueue.async { [weak self] in
            guard let self else { return }
            let handlers = self.connectionObservers.values
            for handler in handlers {
                handler(isConnected)
            }
        }
    }

    private func notifyAuthFailureObservers(reason: String) {
        connectionObserversQueue.async { [weak self] in
            guard let self else { return }
            let handlers = self.authFailureObservers.values
            for handler in handlers {
                handler(reason)
            }
        }
    }

    private func socketStatus() -> SocketIOStatus {
        socketQueue.sync {
            socket.status
        }
    }

    private func isAuthFailed() -> Bool {
        socketQueue.sync {
            didAuthFail
        }
    }

    private func isClosedForGood() -> Bool {
        socketQueue.sync {
            isClosed
        }
    }

    private func connectIfNeeded() {
        socketQueue.async { [weak self] in
            guard let self, !self.isClosed, !self.didAuthFail else { return }
            if self.socket.status != .connected && self.socket.status != .connecting {
                self.connectWithToken()
            }
        }
    }

    /// Jawne wznowienie po powrocie aplikacji z tła. iOS zrywa połączenie,
    /// gdy proces śpi, a bez tego wołania pierwszy foregroundowy request
    /// odkrywał martwy socket dopiero własnym timeoutem.
    ///
    /// Po odmowie auth to JEDNA ograniczona próba z aktualnym tokenem
    /// z `tokenProvider` (refresh mógł pójść inną ścieżką, np. po 401 z REST,
    /// albo padł na sieci): ponowna odmowa znów ustawi `didAuthFail`
    /// i zatrzyma auto-reconnect, więc nie ma pętli — jest jeden handshake
    /// per foreground.
    func reconnectIfNeeded() {
        socketQueue.async { [weak self] in
            guard let self, !self.isClosed else { return }
            self.didAuthFail = false
            self.manager.reconnects = true
            if self.socket.status != .connected && self.socket.status != .connecting {
                self.connectWithToken()
            } else if self.socket.status == .connecting && self.pendingTransientRetry {
                // Handshake zawieszony po `connect_error` serwera — nowy CONNECT
                // tym samym silnikiem, bez czekania na zaplanowane ponowienie.
                self.connectWithToken()
            }
        }
    }

    func reconnectWithFreshToken() {
        socketQueue.async { [weak self] in
            guard let self, !self.isClosed else { return }
            // Zdrowy socket (refresh proaktywny albo po 401 z REST) zostaje —
            // także handshake w locie: token w nim jest ważny do `exp`, a wtedy
            // serwer sam wyśle `auth:expired` i przejdziemy tę ścieżkę z flagą.
            // DISCONNECT dla jeszcze niepołączonego namespace'u serwer traktuje
            // jako `invalid state` i zamyka cały silnik.
            if !self.didAuthFail
                && (self.socket.status == .connected || self.socket.status == .connecting) {
                return
            }
            self.didAuthFail = false
            self.manager.reconnects = true
            // Świeży token wchodzi tylko przez nowy pakiet CONNECT: połączony
            // socket rozłączamy na poziomie namespace'u (engine zostaje),
            // a `connect(withPayload:)` przechodzi handshake od nowa.
            if self.socket.status == .connected {
                self.socket.disconnect()
            }
            self.connectWithToken()
        }
    }

    func disconnect() {
        // Mocna referencja do managera: blok ma się wykonać nawet, gdy klient
        // zostanie zwolniony zanim kolejka do niego dojdzie — inaczej manager
        // z `reconnects = true` dokończyłby własny cykl reconnectu.
        let manager = self.manager
        socketQueue.async { [weak self] in
            self?.isClosed = true
            manager.reconnects = false
            manager.disconnect()
        }
    }

    private func ensureConnected() async throws {
        if socketStatus() == .connected { return }
        if isClosedForGood() { throw SocketClosedError() }

        connectIfNeeded()

        // Po odmowie auth nie rzucamy od razu: `SessionStore` robi refresh
        // i `reconnectWithFreshToken()` w ciągu ~1 RTT, a natychmiastowe
        // UNAUTHORIZED malowałoby „Sesja wygasła" na każdym ekranie dokładnie
        // w chwili, gdy sesja jest naprawiana. Odmowa dostaje pełne okno raz.
        var budget = 30
        var sawAuthFailure = false
        while budget > 0 {
            if socketStatus() == .connected { return }
            if isClosedForGood() { throw SocketClosedError() }
            if !sawAuthFailure, isAuthFailed() {
                sawAuthFailure = true
                budget = 30
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            budget -= 1
        }

        // Także po odmowie auth zgłaszamy błąd ŁĄCZNOŚCI: werdykt „sesja
        // wygasła" należy do `SessionStore` (refresh → reconnect albo logout),
        // a tu socket po prostu jeszcze nie wrócił — np. refresh padł na sieci
        // i czeka na ponowienie. Kopia z kodem UNAUTHORIZED kazałaby się
        // logować ponownie przy ważnej sesji.
        throw RecipeDataError.serverError(message: "Brak połączenia WebSocket z serwerem.")
    }

    private func requestAck(event: String, payload: [String: Any], timeout: Double) async throws -> [Any] {
        let safePayload = try makeSafePayload(payload, event: event)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Any], Error>) in
            let continuationLock = NSLock()
            var didResume = false

            func resumeOnce(_ result: Result<[Any], Error>) {
                continuationLock.lock()
                if didResume {
                    continuationLock.unlock()
                    return
                }
                didResume = true
                continuationLock.unlock()

                switch result {
                case .success(let items):
                    continuation.resume(returning: items)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            socketQueue.async { [weak self] in
                guard let self else {
                    resumeOnce(.failure(RecipeDataError.serverError(message: "Brak klienta WebSocket.")))
                    return
                }

                self.socket.emitWithAck(event, safePayload).timingOut(after: timeout) { items in
                    if let first = items.first as? String, first == "NO ACK" {
                        resumeOnce(.failure(RecipeDataError.serverError(message: "Brak ACK dla eventu \(event).")))
                        return
                    }
                    resumeOnce(.success(items))
                }
            }
        }
    }

    private func makeSafePayload(_ payload: [String: Any], event: String) throws -> [String: Any] {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw RecipeDataError.serverError(
                message: "Nieprawidłowy payload JSON dla eventu \(event)."
            )
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = object as? [String: Any] else {
            throw RecipeDataError.serverError(
                message: "Nie udało się zbudować payloadu JSON dla eventu \(event)."
            )
        }
        return dictionary
    }

    func emitWithAck<T: Decodable>(event: String, payload: [String: Any], as: T.Type) async throws -> T {
        var lastError: Error?

        for attempt in 1...maxAckAttempts {
            do {
                try await ensureConnected()
                let raw = try await requestAck(event: event, payload: payload, timeout: ackTimeoutSeconds)

                guard let first = raw.first else {
                    throw RecipeDataError.serverError(message: "Pusta odpowiedź dla eventu \(event).")
                }
                guard JSONSerialization.isValidJSONObject(first) else {
                    throw RecipeDataError.serverError(message: "Nieprawidłowy format odpowiedzi dla eventu \(event).")
                }

                let payloadObject = first
                return try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async {
                        do {
                            let data = try JSONSerialization.data(withJSONObject: payloadObject)
                            let decoded = try JSONDecoder().decode(T.self, from: data)
                            continuation.resume(returning: decoded)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            } catch {
                // Socket zamknięty na dobre — ponawianie czekałoby na martwym
                // połączeniu; wołający i tak dostał już nowy socket sesji.
                if error is SocketClosedError {
                    throw RecipeDataError.serverError(message: "Połączenie WebSocket zostało zamknięte.")
                }
                lastError = error
                // Odmowa auth nie jest przejściowa — ponawianie trzy razy
                // tylko odwlekałoby refresh/wylogowanie.
                if case RecipeDataError.server(let code, _, _, _) = error, code == "UNAUTHORIZED" {
                    throw error
                }
                if attempt < maxAckAttempts {
                    let backoffMs = UInt64(250 * attempt)
                    try await Task.sleep(nanoseconds: backoffMs * 1_000_000)
                    continue
                }
            }
        }

        if let lastError {
            throw lastError
        }
        throw RecipeDataError.serverError(message: "Nie udało się wykonać eventu \(event).")
    }

    func on(event: String, handler: @escaping ([Any]) -> Void) {
        socketQueue.async { [weak self] in
            guard let self else { return }
            self.socket.on(event) { data, _ in
                handler(data)
            }
        }
    }

    func off(event: String) {
        // Mocna referencja jak w `disconnect()` — zdjęcie handlerów ma dojść
        // do skutku także po zwolnieniu klienta (socket żyje z managerem).
        let socket = self.socket
        socketQueue.async {
            socket.off(event)
        }
    }

    func observeConnection(_ handler: @escaping (Bool) -> Void) {
        let id = UUID()
        connectionObserversQueue.async { [weak self] in
            self?.connectionObservers[id] = handler
        }
    }

    func observeAuthFailure(_ handler: @escaping (String) -> Void) {
        let id = UUID()
        connectionObserversQueue.async { [weak self] in
            self?.authFailureObservers[id] = handler
        }
    }
}

// MARK: - No-op fallback used when transport is not yet configured (previews, env defaults)

final class UnconfiguredRecipeSocketClient: RecipeSocketClient {
    func emitWithAck<T: Decodable>(event: String, payload: [String: Any], as: T.Type) async throws -> T {
        throw RecipeDataError.transportNotConfigured
    }

    func on(event: String, handler: @escaping ([Any]) -> Void) {}

    func off(event: String) {}

    func observeConnection(_ handler: @escaping (Bool) -> Void) {}
}
