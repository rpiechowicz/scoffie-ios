import Foundation
import SocketIO

/// Real Socket.IO-backed implementation of `RecipeSocketClient`.
/// Owns the connection lifecycle and provides bounded retries on ACK timeouts.
final class SocketIORecipeSocketClient: RecipeSocketClient {
    private let manager: SocketManager
    private let socket: SocketIOClient
    private let socketQueue = DispatchQueue(label: "weeklymeals.socket.io.serial")
    private let ackTimeoutSeconds: Double = 6
    private let maxAckAttempts: Int = 3
    private var connectionObservers: [UUID: (Bool) -> Void] = [:]
    private let connectionObserversQueue = DispatchQueue(label: "weeklymeals.socket.connection-observers")

    init(baseURL: URL) {
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
            self?.socket.connect()
        }
    }

    private func registerConnectionLifecycleEvents() {
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            self?.notifyConnectionObservers(isConnected: true)
        }
        socket.on(clientEvent: .reconnect) { [weak self] _, _ in
            self?.notifyConnectionObservers(isConnected: true)
        }
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            self?.notifyConnectionObservers(isConnected: false)
        }
        socket.on(clientEvent: .error) { [weak self] _, _ in
            self?.notifyConnectionObservers(isConnected: false)
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

    private func socketStatus() -> SocketIOStatus {
        socketQueue.sync {
            socket.status
        }
    }

    private func connectIfNeeded() {
        socketQueue.async { [weak self] in
            guard let self else { return }
            if self.socket.status != .connected && self.socket.status != .connecting {
                self.socket.connect()
            }
        }
    }

    /// Jawne wznowienie po powrocie aplikacji z tła. iOS zrywa połączenie,
    /// gdy proces śpi, a bez tego wołania pierwszy foregroundowy request
    /// odkrywał martwy socket dopiero własnym timeoutem.
    func reconnectIfNeeded() {
        connectIfNeeded()
    }

    private func ensureConnected() async throws {
        if socketStatus() == .connected { return }

        connectIfNeeded()

        for _ in 0..<30 {
            if socketStatus() == .connected { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

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
                lastError = error
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
        socketQueue.async { [weak self] in
            self?.socket.off(event)
        }
    }

    func observeConnection(_ handler: @escaping (Bool) -> Void) {
        let id = UUID()
        connectionObserversQueue.async { [weak self] in
            self?.connectionObservers[id] = handler
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
