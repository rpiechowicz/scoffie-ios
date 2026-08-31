import Foundation
import Observation

/// Wiadomość w widoku czatu.
///
/// Osobny typ od `AgentMessageDTO`, bo widok potrzebuje czegoś, czego serwer
/// nie ma: wiadomości WYSŁANEJ, ale jeszcze niepotwierdzonej. Bez tego dymek
/// użytkownika pojawiałby się dopiero po odpowiedzi serwera i pisanie
/// wyglądałoby na zawieszone.
struct AgentChatMessage: Identifiable, Equatable {
    enum Author {
        case user
        case assistant
    }

    let id: String
    let author: Author
    let text: String
    let createdAt: Date?
    var isPending: Bool = false
    /// Tura, która skończyła się ZAPISEM planu — dymek dostaje skrót do Planu.
    var savedPlan: Bool = false
}

/// Stan rozmowy z asystentem AI.
///
/// Wisi na `SessionStore` jak pozostałe store'y (budowany w `bootstrapSession`,
/// czyszczony przy wylogowaniu), więc rozmowa przeżywa zamknięcie arkusza —
/// tura potrafi trwać minutę, a użytkownik w tym czasie wraca do planu.
///
/// Tura NIE jest zwykłym żądaniem: serwer przyjmuje wiadomość (`202`) i oddaje
/// identyfikator, a odpowiedź przychodzi przez odpytywanie. Tutaj żyje cała ta
/// pętla — widok zna wyłącznie listę wiadomości, kroki postępu i to, czy
/// asystent właśnie pracuje.
@MainActor
@Observable
final class AgentStore {
    /// Co ile odpytywać stan tury. Sekunda to kompromis: krok postępu ma się
    /// pojawić „od razu", a limit odpytywania na serwerze jest sześć razy
    /// wyższy niż limit wysyłki właśnie po to, żeby czekanie na własną turę
    /// nie kończyło się odmową.
    private static let pollInterval: Duration = .seconds(1)
    /// Twardy sufit czekania. Serwer przerywa turę po 90 s, a leniwe domknięcie
    /// dokłada margines; po trzech minutach dalsze pytanie nie ma sensu.
    private static let pollTimeout: Duration = .seconds(180)
    /// Ile razy z rzędu wolno nie dostać odpowiedzi, zanim uznamy, że to koniec.
    /// Jedna zgubiona odpowiedź w tunelu nie może przerywać tury, za którą
    /// użytkownik już zapłacił kwotą.
    private static let maxPollFailures = 5

    private(set) var messages: [AgentChatMessage] = []
    private(set) var isSending = false
    /// Kroki bieżącej tury — „Czytam plan tygodnia", „Zapisuję plan tygodnia".
    private(set) var progress: [AgentProgressStepDTO] = []
    private(set) var errorMessage: String?
    /// Asystent wyłączony na serwerze (`AI_DISABLED`) — ekran mówi to wprost,
    /// zamiast udawać, że wiadomość poszła.
    private(set) var isUnavailable = false
    private(set) var isLoadingHistory = false
    /// Treść wiadomości, która NIE doszła do serwera — do ponowienia jednym
    /// przyciskiem. Ustawiana tylko wtedy, gdy wiadomość wypadła z historii;
    /// przy turze, która ruszyła i się nie domknęła, ponowienie oznaczałoby
    /// drugą kwotę za to samo.
    private(set) var retryText: String?

    private let client: AgentAPIClient
    private let householdId: String
    private var conversationId: String?
    /// Tura, która może jeszcze biec — po powrocie do arkusza wracamy do niej,
    /// zamiast pokazywać rozmowę bez odpowiedzi.
    private var pendingTurnId: String?

    init(client: AgentAPIClient, householdId: String) {
        self.client = client
        self.householdId = householdId
    }

    var canSend: Bool { !isSending && !isUnavailable }

    /// Otwarcie ekranu: historia rozmowy i ewentualny powrót do tury w biegu.
    func openIfNeeded() async {
        if conversationId == nil {
            await loadOrCreateConversation()
        }
        if let pendingTurnId, !isSending {
            await followTurn(turnId: pendingTurnId)
        }
    }

    /// Wysyła wiadomość i czeka na odpowiedź, pokazując po drodze postęp.
    func send(text: String, weekStart: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canSend else { return }

        errorMessage = nil
        retryText = nil
        isSending = true
        progress = []
        defer { isSending = false }

        if conversationId == nil {
            await loadOrCreateConversation()
        }
        guard let conversationId else { return }

        // Klucz idempotencji zostaje ten sam przy ponowieniu — serwer odda tę
        // samą turę, zamiast policzyć drugą kwotę za ten sam prompt.
        let clientMessageId = UUID().uuidString
        messages.append(
            AgentChatMessage(
                id: clientMessageId,
                author: .user,
                text: trimmed,
                createdAt: Date(),
                isPending: true
            )
        )

        do {
            let accepted = try await client.postMessage(
                conversationId: conversationId,
                request: AgentPostMessageRequestDTO(
                    clientMessageId: clientMessageId,
                    text: trimmed,
                    weekStart: weekStart,
                    clientToday: PlanWeek.dateKey(Date()),
                    timeZone: TimeZone.current.identifier
                )
            )
            confirmPendingMessage(clientMessageId)
            pendingTurnId = accepted.turnId
            await followTurn(turnId: accepted.turnId)
        } catch {
            handle(error)
            // Wiadomość, która nie doszła, nie ma prawa zostać w historii jako
            // wysłana — inaczej użytkownik czekałby na odpowiedź, której nikt
            // nie zamówił. Treść zostaje do ponowienia jednym przyciskiem.
            messages.removeAll { $0.id == clientMessageId }
            retryText = trimmed
        }
    }

    /// Ponawia wiadomość, która nie doszła do serwera.
    func retry(weekStart: String) async {
        guard let text = retryText else { return }
        await send(text: text, weekStart: weekStart)
    }

    /// Kasuje rozmowy tego użytkownika na serwerze (RODO) i czyści ekran.
    func deleteAllConversations() async {
        do {
            try await client.deleteAllConversations()
            messages = []
            progress = []
            conversationId = nil
            pendingTurnId = nil
            errorMessage = nil
        } catch {
            handle(error)
        }
    }

    // MARK: - Rozmowa

    private func loadOrCreateConversation() async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            // Rozmowy wracają od najnowszej — bierzemy tę z bieżącego
            // gospodarstwa, żeby po przeprowadzce nie dopisywać do cudzego domu.
            let existing = try await client.listConversations()
                .first { $0.householdId == householdId }
            let conversation: AgentConversationDTO
            if let existing {
                conversation = existing
            } else {
                conversation = try await client.createConversation(householdId: householdId)
            }
            conversationId = conversation.id
            messages = try await client.messages(conversationId: conversation.id)
                .map { Self.chatMessage(from: $0) }
            isUnavailable = false
        } catch {
            handle(error)
        }
    }

    // MARK: - Tura

    private func followTurn(turnId: String) async {
        isSending = true
        defer {
            isSending = false
            progress = []
        }

        let deadline = ContinuousClock.now + Self.pollTimeout
        var failures = 0

        while ContinuousClock.now < deadline {
            do {
                let turn = try await client.turn(id: turnId)
                failures = 0
                progress = turn.progress

                guard turn.isFinished else {
                    try await Task.sleep(for: Self.pollInterval)
                    continue
                }

                pendingTurnId = nil
                apply(finished: turn)
                return
            } catch is CancellationError {
                return
            } catch {
                failures += 1
                if failures >= Self.maxPollFailures {
                    handle(error)
                    return
                }
                try? await Task.sleep(for: Self.pollInterval)
            }
        }

        // Sufit czasu. Tura mogła się domknąć po naszej stronie ciszy, więc
        // nie kasujemy jej identyfikatora — po ponownym otwarciu ekranu
        // sięgniemy po nią jeszcze raz.
        errorMessage = "Asystent nie odpowiedział na czas. Otwórz rozmowę za chwilę — odpowiedź może już tam być."
    }

    private func apply(finished turn: AgentTurnDTO) {
        switch turn.status {
        case "DONE":
            // `apply_week_plan` biegnie w każdej turze najpierw jako próba,
            // więc o zapisie decyduje flaga z serwera, nie nazwa narzędzia.
            let savedPlan = turn.progress.contains {
                $0.tool == "apply_week_plan" && $0.writes == true
            }
            var answers = (turn.messages ?? [])
                .filter { $0.role == "ASSISTANT" }
                .map { Self.chatMessage(from: $0) }
            if savedPlan, !answers.isEmpty {
                answers[answers.count - 1].savedPlan = true
            }
            if answers.isEmpty {
                errorMessage = "Asystent nie miał nic do powiedzenia. Spróbuj zapytać inaczej."
            } else {
                messages.append(contentsOf: answers)
            }
        case "LIMITED":
            errorMessage = copy(forCode: turn.errorCode)
                ?? "Limit asystenta został wyczerpany."
        default:
            errorMessage = copy(forCode: turn.errorCode)
                ?? "Asystent nie dokończył zadania. Spróbuj ponownie."
        }
    }

    // MARK: - Błędy

    private func handle(_ error: Error) {
        if case let BackendAPIError.backend(code, _, _) = error, code == "AI_DISABLED" {
            isUnavailable = true
            errorMessage = UserFacingErrorMapper.message(from: error)
            return
        }
        errorMessage = UserFacingErrorMapper.message(from: error)
    }

    /// Kod porażki tury (`AgentTurn.errorCode`) na kopię dla użytkownika.
    /// Tura nie jest odpowiedzią HTTP, więc nie ma tu błędu do zmapowania —
    /// jest sam kod.
    private func copy(forCode code: String?) -> String? {
        guard let code else { return nil }
        return UserFacingErrorMapper.copy(forCode: code)
    }

    private func confirmPendingMessage(_ id: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].isPending = false
    }

    /// Serwer oddaje znaczniki z milisekundami (`2026-08-31T12:00:00.123Z`),
    /// więc goły `ISO8601DateFormatter` bez tej opcji zwracałby `nil`.
    private static let timestampParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func chatMessage(from dto: AgentMessageDTO) -> AgentChatMessage {
        AgentChatMessage(
            id: dto.id,
            author: dto.role == "USER" ? .user : .assistant,
            text: dto.text,
            createdAt: timestampParser.date(from: dto.createdAt)
        )
    }
}
