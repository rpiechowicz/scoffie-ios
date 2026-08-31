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
/// czyszczony przy wylogowaniu), więc rozmowa przeżywa przejście na inną
/// zakładkę — tura potrafi trwać minutę, a użytkownik w tym czasie ogląda plan.
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
    /// Tyle wiadomości oddaje jedna strona historii (kontrakt serwera).
    private static let messagesPageSize = 100
    /// Sufit stron historii — 2000 wiadomości to więcej, niż ktokolwiek napisze
    /// w jednej rozmowie, a bez sufitu błąd serwera dałby pętlę bez końca.
    private static let maxHistoryPages = 20

    private(set) var messages: [AgentChatMessage] = []
    private(set) var isSending = false
    /// Kroki bieżącej tury — „Czytam plan tygodnia", „Zapisuję plan tygodnia".
    private(set) var progress: [AgentProgressStepDTO] = []
    /// Kiedy ruszyła bieżąca tura — ekran pokazuje przy postępie upływ sekund,
    /// bo między krokami bywa kilkanaście sekund ciszy.
    private(set) var turnStartedAt: Date?
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
    /// Klucz idempotencji NIEUDANEJ wysyłki.
    ///
    /// Ponowienie MUSI iść z tym samym kluczem: żądanie mogło dojść do serwera
    /// i dopiero odpowiedź zginąć po drodze. Nowy klucz znaczyłby drugą turę,
    /// drugą kwotę i drugi rachunek za to samo pytanie.
    private var retryClientMessageId: String?

    /// Lista rozmów do panelu historii.
    private(set) var conversations: [AgentConversationDTO] = []
    private(set) var isLoadingConversations = false

    /// Co asystent pamięta o tym domu (pamięć wspólna dla gospodarstwa).
    private(set) var memory: [AgentMemoryNoteDTO] = []
    private(set) var isLoadingMemory = false

    /// Odpowiedzi, które przyszły, gdy użytkownik był na innej zakładce —
    /// kropka na ikonie asystenta zamyka pętlę „zapytaj, odejdź, wróć".
    private(set) var unseenAnswers = 0

    private let client: AgentAPIClient
    private let householdId: String
    private(set) var conversationId: String?
    /// Tura, która może jeszcze biec — po powrocie na zakładkę wracamy do niej,
    /// zamiast pokazywać rozmowę bez odpowiedzi.
    private var pendingTurnId: String?
    /// Zadanie odpytywania — istnieje po to, żeby dało się przestać czekać.
    private var turnTask: Task<Void, Never>?
    private var isVisible = false

    init(client: AgentAPIClient, householdId: String) {
        self.client = client
        self.householdId = householdId
    }

    var canSend: Bool { !isSending && !isUnavailable }

    /// Otwarcie zakładki: historia rozmowy i ewentualny powrót do tury w biegu.
    func openIfNeeded() async {
        if conversationId == nil {
            await loadOrCreateConversation()
        }
        if let pendingTurnId, !isSending {
            await follow(turnId: pendingTurnId)
        }
    }

    /// Ekran wszedł na wierzch albo z niego zszedł. Po tym poznajemy, czy
    /// odpowiedź trzeba jeszcze zgłosić kropką na zakładce.
    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible { unseenAnswers = 0 }
    }

    /// Wysyła wiadomość i czeka na odpowiedź, pokazując po drodze postęp.
    /// `false` = wiadomość nie doszła do serwera (ekran ma oddać tekst do pola).
    @discardableResult
    func send(
        text: String,
        weekStart: String,
        clientMessageId: String = UUID().uuidString
    ) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canSend else { return false }

        errorMessage = nil
        retryText = nil
        retryClientMessageId = nil
        isSending = true
        progress = []
        defer { isSending = false }

        if conversationId == nil {
            await loadOrCreateConversation()
        }
        guard let conversationId else {
            // Bez rozmowy nie ma dokąd wysłać, ale tekst musi mieć drogę
            // powrotu — inaczej użytkownik zostaje z błędem i pustym polem.
            retryText = trimmed
            retryClientMessageId = clientMessageId
            return false
        }
        let sentInConversation = conversationId
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
            // Rozmowa mogła się w tym czasie przełączyć — wtedy ta tura
            // należy do POPRZEDNIEJ i nie ma prawa dopisać odpowiedzi tutaj.
            guard sentInConversation == self.conversationId else { return true }
            confirmPendingMessage(clientMessageId)
            pendingTurnId = accepted.turnId
            await follow(turnId: accepted.turnId)
            return true
        } catch {
            // Serwer pilnuje „jednej tury naraz". Zamiast pokazywać błąd,
            // wracamy do tury, która wciąż biegnie — to dokładnie ta, na którą
            // użytkownik czeka (typowo po wciśnięciu „stop").
            if isTurnInProgress(error), let pendingTurnId {
                messages.removeAll { $0.id == clientMessageId }
                await follow(turnId: pendingTurnId)
                return false
            }
            handle(error)
            // Wiadomość, która nie doszła, nie ma prawa zostać w historii jako
            // wysłana — inaczej użytkownik czekałby na odpowiedź, której nikt
            // nie zamówił. Treść i KLUCZ zostają do ponowienia.
            messages.removeAll { $0.id == clientMessageId }
            retryText = trimmed
            retryClientMessageId = clientMessageId
            return false
        }
    }

    /// Ponawia wiadomość, która nie doszła do serwera — tym samym kluczem
    /// idempotencji, bo poprzednie żądanie mogło jednak dojść.
    func retry(weekStart: String) async {
        guard let text = retryText else { return }
        let key = retryClientMessageId ?? UUID().uuidString
        await send(text: text, weekStart: weekStart, clientMessageId: key)
    }

    private func isTurnInProgress(_ error: Error) -> Bool {
        if case let BackendAPIError.backend(code, _, _) = error {
            return code == "AI_TURN_IN_PROGRESS"
        }
        return false
    }

    /// Przestaje czekać na turę.
    ///
    /// NIE anuluje pracy modelu — ta biegnie na serwerze i tak czy owak
    /// zostanie policzona. Zatrzymujemy tylko odpytywanie, a identyfikator
    /// tury zostaje: po powrocie na zakładkę odpowiedź może już czekać.
    func stopWaiting() {
        guard isSending else { return }
        turnTask?.cancel()
        turnTask = nil
        isSending = false
        progress = []
        turnStartedAt = nil
        errorMessage = "Przestałem czekać. Asystent kończy w tle — wróć tu za chwilę po odpowiedź."
    }

    // MARK: - Rozmowy

    func refreshConversations() async {
        isLoadingConversations = true
        defer { isLoadingConversations = false }
        do {
            conversations = try await client.listConversations()
                .filter { $0.householdId == householdId }
            isUnavailable = false
        } catch {
            handle(error)
        }
    }

    /// Odświeżenie listy w tle — bez dotykania komunikatu błędu.
    ///
    /// Wołane po udanej turze, żeby lista dostała tytuł nowej rozmowy. Gdyby
    /// szło przez `refreshConversations`, nieudane odświeżenie wyświetlałoby
    /// błąd POD poprawną odpowiedzią — i to o czymś, o co nikt nie prosił.
    private func refreshConversationsQuietly() async {
        guard let fresh = try? await client.listConversations() else { return }
        conversations = fresh.filter { $0.householdId == householdId }
    }

    /// Przełącza widok na inną rozmowę.
    ///
    /// Tura, która akurat biegnie, zostaje ze swoją rozmową — `pendingTurnId`
    /// jest czyszczony, bo należał do TAMTEJ rozmowy, a jej odpowiedź i tak
    /// dopisze się na serwerze. Inaczej odpowiedź z jednej rozmowy wpadłaby
    /// do drugiej.
    func select(conversationId id: String) async {
        guard id != conversationId else { return }
        resetTurnState()
        conversationId = id
        messages = []
        await loadMessages(conversationId: id)
    }

    /// Zaczyna pustą rozmowę. Nowa rozmowa nie zna poprzednich wiadomości —
    /// od tego jest pamięć asystenta (notatki gospodarstwa).
    func startNewConversation() async {
        resetTurnState()
        messages = []
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            let conversation = try await client.createConversation(
                householdId: householdId
            )
            conversationId = conversation.id
            conversations.insert(conversation, at: 0)
        } catch {
            handle(error)
        }
    }

    func deleteConversation(id: String) async {
        do {
            try await client.deleteConversation(id: id)
            conversations.removeAll { $0.id == id }
            if id == conversationId {
                resetTurnState()
                conversationId = nil
                messages = []
                await loadOrCreateConversation()
            }
        } catch {
            handle(error)
        }
    }

    /// Kasuje rozmowy tego użytkownika na serwerze (RODO) i czyści ekran.
    func deleteAllConversations() async {
        do {
            try await client.deleteAllConversations()
            resetTurnState()
            messages = []
            conversations = []
            conversationId = nil
            unseenAnswers = 0
            // Bez tego zostaje ekran bez rozmowy: pierwsza wiadomość i tak
            // musiałaby ją założyć, tylko z opóźnieniem i bez historii.
            await loadOrCreateConversation()
        } catch {
            handle(error)
        }
    }

    // MARK: - Pamięć

    func refreshMemory() async {
        isLoadingMemory = true
        defer { isLoadingMemory = false }
        do {
            memory = try await client.memory(householdId: householdId)
        } catch {
            handle(error)
        }
    }

    func forgetMemory(noteId: String) async {
        do {
            try await client.forgetMemory(noteId: noteId)
            memory.removeAll { $0.id == noteId }
        } catch {
            handle(error)
        }
    }

    // MARK: - Wczytywanie rozmowy

    private func loadOrCreateConversation() async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            // Rozmowy wracają od najnowszej — bierzemy tę z bieżącego
            // gospodarstwa, żeby po przeprowadzce nie dopisywać do cudzego domu.
            let mine = try await client.listConversations()
                .filter { $0.householdId == householdId }
            conversations = mine

            let conversation: AgentConversationDTO
            if let existing = mine.first {
                conversation = existing
            } else {
                conversation = try await client.createConversation(
                    householdId: householdId
                )
                conversations = [conversation]
            }
            conversationId = conversation.id
            // Tura, która biegła, gdy aplikacja została ubita: identyfikator
            // przychodzi z serwera, bo w pamięci telefonu go już nie ma.
            pendingTurnId = conversation.activeTurnId
            messages = try await loadAllMessages(conversationId: conversation.id)
            isUnavailable = false
        } catch {
            handle(error)
        }
    }

    private func loadMessages(conversationId id: String) async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            messages = try await loadAllMessages(conversationId: id)
            pendingTurnId = conversations
                .first { $0.id == id }?
                .activeTurnId
        } catch {
            handle(error)
        }
    }

    /// Historia rozmowy w całości.
    ///
    /// Serwer oddaje po sto wiadomości na stronę i podaje kursor. Bez pętli
    /// rozmowa dłuższa niż sto wiadomości urywała się w połowie, a klient nawet
    /// o tym nie wiedział — sufit stron jest po to, żeby błąd po stronie
    /// serwera nie zamienił się w nieskończone pobieranie.
    private func loadAllMessages(conversationId id: String) async throws -> [AgentChatMessage] {
        var all: [AgentChatMessage] = []
        var cursor: String?
        for _ in 0..<Self.maxHistoryPages {
            let page = try await client.messages(conversationId: id, after: cursor)
            all.append(contentsOf: page.map { Self.chatMessage(from: $0) })
            guard page.count == Self.messagesPageSize, let last = page.last else { break }
            cursor = last.id
        }
        return all
    }

    private func resetTurnState() {
        turnTask?.cancel()
        turnTask = nil
        isSending = false
        progress = []
        turnStartedAt = nil
        pendingTurnId = nil
        errorMessage = nil
    }

    // MARK: - Tura

    /// Odpytywanie w osobnym zadaniu, żeby dało się je przerwać `stopWaiting`.
    private func follow(turnId: String) async {
        // `guard let self` robi z tego domknięcie WIELOINSTRUKCYJNE, więc
        // zadanie ma typ `Task<Void, Never>`. Zapis jednoinstrukcyjny
        // z `await self?.followTurn(...)` dawał `Task<Void?, Never>` przez
        // opcjonalne łańcuchowanie i nie dało się go przypisać do `turnTask`.
        let task = Task { [weak self] in
            guard let self else { return }
            await self.followTurn(turnId: turnId)
        }
        turnTask = task
        await task.value
        if turnTask == task { turnTask = nil }
    }

    private func followTurn(turnId: String) async {
        // Znacznik startu jest tożsamością TEJ tury. Sprzątamy po sobie tylko
        // wtedy, gdy nikt nas nie zastąpił: anulowana tura kończy się po tym,
        // jak użytkownik zdążył wysłać następną, i bez tego warunku gasiłaby
        // jej kręciołek i kroki postępu.
        let startedAt = Date()
        isSending = true
        turnStartedAt = startedAt
        defer {
            if turnStartedAt == startedAt {
                isSending = false
                progress = []
                turnStartedAt = nil
            }
        }

        let deadline = ContinuousClock.now + Self.pollTimeout
        var failures = 0

        while ContinuousClock.now < deadline {
            if Task.isCancelled { return }
            do {
                let turn = try await client.turn(id: turnId)
                failures = 0
                progress = turn.progress

                guard turn.isFinished else {
                    try await Task.sleep(for: Self.pollInterval)
                    continue
                }

                pendingTurnId = nil
                // Komunikat z poprzedniej, nieudanej próby nie ma prawa wisieć
                // pod świeżą odpowiedzią.
                errorMessage = nil
                apply(finished: turn)
                return
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                failures += 1
                if failures >= Self.maxPollFailures {
                    handle(error)
                    return
                }
                try? await Task.sleep(for: Self.pollInterval)
            }
        }

        // Sufit czasu. Zanim powiemy „nie zdążył", pytamy JESZCZE RAZ: pętla
        // mogła stać w tle razem z całą aplikacją, a odpowiedź czekać od dawna.
        if let turn = try? await client.turn(id: turnId), turn.isFinished {
            pendingTurnId = nil
            apply(finished: turn)
            return
        }
        // Identyfikatora nie kasujemy — po powrocie na zakładkę spróbujemy
        // jeszcze raz.
        errorMessage = "Asystent nie odpowiedział na czas. Wróć tu za chwilę — odpowiedź może już czekać."
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
                if !isVisible { unseenAnswers += answers.count }
                // Tytuł rozmowy nadaje serwer z PIERWSZEJ wiadomości, a lista
                // historii ma go pokazać bez ręcznego odświeżania.
                Task { [weak self] in await self?.refreshConversationsQuietly() }
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

    static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return timestampParser.date(from: raw)
    }

    private static func chatMessage(from dto: AgentMessageDTO) -> AgentChatMessage {
        AgentChatMessage(
            id: dto.id,
            author: dto.role == "USER" ? .user : .assistant,
            text: dto.text,
            createdAt: timestampParser.date(from: dto.createdAt)
        )
    }
}
