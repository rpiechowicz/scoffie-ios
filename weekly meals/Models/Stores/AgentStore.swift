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
    /// Karta — propozycja tygodnia albo potwierdzenie zapisu. `nil` przy
    /// zwykłej odpowiedzi i przy rodzaju, którego ten build nie zna.
    var card: AgentCardDTO?
    /// „Uwzględniłem: …" — z czym serwer policzył tę odpowiedź.
    var usedContext: [String] = []
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
    /// Gotowe podpowiedzi pod błędem tury (po przekroczeniu czasu albo
    /// „Stop"): mniejszy zakres, bo to najczęstsza przyczyna 90 s. Z serwera.
    private(set) var suggestions: [String] = []
    /// Kontekst chipów i arkusza osób — z `GET /agent/context`; `nil`, dopóki
    /// nie przyjdzie (wtedy chipy liczą się po staremu z cache'ów sesji).
    private(set) var context: AgentContextDTO?
    /// Asystent wyłączony na serwerze (`AI_DISABLED`) — ekran mówi to wprost,
    /// zamiast udawać, że wiadomość poszła.
    private(set) var isUnavailable = false
    /// 403 `AI_CONSENT_REQUIRED` — rozmowa czeka na zgodę (arkusz blokujący
    /// w `AssistantView`); tekst wiadomości zostaje w `retryText`.
    private(set) var needsConsent = false
    /// Pole zablokowane po 429 / wyczerpanej kwocie / pauzie — do tej chwili.
    /// Bez tego użytkownik klikał „wyślij" w kółko i za każdym razem dostawał
    /// ten sam błąd zamiast informacji, kiedy spróbować.
    private(set) var lockedUntil: Date?
    /// Ostatnio pobrane limity — po 429 pole wiadomości musi wiedzieć, czy
    /// to próba (pokazać „Odblokuj PRO"), czy miesiąc (pokazać datę).
    private(set) var usage: AgentUsageDTO?
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

    /// Propozycja, na której właśnie pracuje serwer — kręciołek siedzi
    /// W KARCIE, bo to jej przycisk został naciśnięty. Blokujemy przy tym
    /// wszystkie karty naraz: dwa zapisy tego samego tygodnia w locie to
    /// pytanie, na które nie ma dobrej odpowiedzi.
    private(set) var busyProposalId: String?

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

    var canSend: Bool { !isSending && !isUnavailable && !isLocked }
    var isLocked: Bool { lockedUntil.map { $0 > Date() } ?? false }

    /// Po udanej zgodzie arkusz wraca do rozmowy; tekst do ponowienia czeka.
    func consentGranted() {
        needsConsent = false
        errorMessage = nil
    }

    /// Arkusz zamknięty bez zgody — błąd pod rozmową zostaje, arkusz nie wraca sam.
    func consentDismissed() {
        needsConsent = false
    }

    /// „Zgłoś odpowiedź" — oddaje komunikat błędu albo `nil`.
    func report(messageId: String, reason: String, comment: String?) async -> String? {
        do {
            try await client.reportMessage(id: messageId, reason: reason, comment: comment)
            return nil
        } catch {
            return UserFacingErrorMapper.message(from: error)
        }
    }

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
        scopeUserIds: [String] = [],
        clientMessageId: String = UUID().uuidString
    ) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canSend else { return false }

        errorMessage = nil
        suggestions = []
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
                    timeZone: TimeZone.current.identifier,
                    scopeUserIds: scopeUserIds.isEmpty ? nil : scopeUserIds
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

    /// „Stop" — przerywa turę NA SERWERZE.
    ///
    /// Do v2 przycisk tylko przestawał odpytywać, a model liczył dalej i
    /// odpowiedź spadała po chwili jak grom z jasnego nieba. Teraz serwer
    /// domyka turę jako `AI_CANCELLED`, oddaje kwotę i podpowiada mniejszy
    /// zakres. Gdy serwer jest starszy i nie zna tej trasy, zostaje dawne
    /// zachowanie: przestajemy czekać, identyfikator tury zostaje.
    func stopWaiting() {
        guard isSending else { return }
        let turnId = pendingTurnId
        turnTask?.cancel()
        turnTask = nil
        isSending = false
        progress = []
        turnStartedAt = nil

        guard let turnId else {
            errorMessage = "Przestałem czekać. Asystent kończy w tle — wróć tu za chwilę po odpowiedź."
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let turn = try await self.client.cancelTurn(id: turnId)
                // Strażnik tożsamości jak w `followTurn`: użytkownik mógł już
                // wysłać NOWĄ wiadomość, a ten komunikat dotyczy poprzedniej.
                guard self.pendingTurnId == turnId else { return }
                if turn.isFinished {
                    self.pendingTurnId = nil
                    if turn.status == "DONE" {
                        // Zdążył przed sygnałem — odpowiedź jest, pokazujemy ją.
                        self.apply(finished: turn)
                    } else {
                        self.errorMessage = UserFacingErrorMapper.copy(forCode: "AI_CANCELLED")
                            ?? "Zatrzymane. Plan bez zmian."
                        self.suggestions = turn.suggestions ?? []
                    }
                } else {
                    // Runner jest w środku narzędzia i nie zdążył domknąć
                    // (serwer mówi `stopRequested`). Mówimy to wprost i
                    // odpytujemy dalej — inaczej „Stop" wyglądał na zignorowany.
                    self.errorMessage = "Zatrzymuję. Asystent kończy bieżący krok — chwila."
                    await self.follow(turnId: turnId)
                }
            } catch {
                self.errorMessage = "Przestałem czekać. Asystent kończy w tle — wróć tu za chwilę po odpowiedź."
            }
        }
    }

    /// Kontekst chipów. Cicho: brak odpowiedzi zostawia chipy liczone po
    /// staremu, a nie komunikat o błędzie pod rozmową.
    func refreshContext(weekStart: String?) async {
        guard let fresh = try? await client.context(householdId: householdId, weekStart: weekStart)
        else { return }
        context = fresh
    }

    /// „Ile mi zostało" — do arkusza limitów; nie zasłania błędów rozmowy.
    func loadUsage() async -> AgentUsageDTO? {
        let loaded = try? await client.usage(householdId: householdId)
        if let loaded {
            usage = loaded
            // Po włączeniu PRO (albo ręcznym nadaniu) blokada „do PRO" znika
            // bez restartu aplikacji.
            if !loaded.isTrial, lockReason == .quota, lockedUntil == .distantFuture {
                lockedUntil = nil
                lockReason = nil
            }
        }
        return loaded
    }

    /// Pole zablokowane przez wyczerpaną pulę na PRÓBIE — bez odnowienia,
    /// więc zamiast „spróbuj za moment" jest „Odblokuj PRO".
    var isLockedByTrialQuota: Bool {
        isLocked && lockReason == .quota && usage?.isTrial == true
    }

    enum LockReason { case quota, budget, pause }
    private(set) var lockReason: LockReason?

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

    /// „Usuń wszystkie notatki" — nieodwracalne; plan i przepisy zostają.
    func forgetAllMemory() async {
        do {
            try await client.forgetAllMemory(householdId: householdId)
            memory = []
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
        suggestions = []
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
            // Podpowiedzi z serwera („tylko obiady", „3 dni") — tylko tam,
            // gdzie serwer je dał, czyli po czasie i po „Stop".
            suggestions = turn.suggestions ?? []
        }
    }

    // MARK: - Poprawianie pytania

    /// Poprawia własne pytanie: wycofuje je razem z tym, co po nim, i pyta od nowa.
    ///
    /// Lokalnie robimy dokładnie to, co zrobi serwer — usuwamy wiadomości od
    /// poprawianej w dół i dopisujemy nową. Gdyby poprawka odmówiła, historia
    /// z serwera i tak jest nietknięta, więc po błędzie po prostu ją
    /// przeładowujemy zamiast zgadywać, co zostało cofnięte.
    @discardableResult
    func editMessage(
        messageId: String,
        text: String,
        weekStart: String,
        clientMessageId: String = UUID().uuidString
    ) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            canSend,
            let conversationId,
            let index = messages.firstIndex(where: { $0.id == messageId })
        else { return false }

        errorMessage = nil
        retryText = nil
        retryClientMessageId = nil
        isSending = true
        progress = []
        defer { isSending = false }

        let withdrawn = Array(messages[index...])
        messages.removeSubrange(index...)
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
            let accepted = try await client.editMessage(
                conversationId: conversationId,
                request: AgentEditMessageRequestDTO(
                    clientMessageId: clientMessageId,
                    messageId: messageId,
                    text: trimmed,
                    weekStart: weekStart,
                    clientToday: PlanWeek.dateKey(Date()),
                    timeZone: TimeZone.current.identifier
                )
            )
            confirmPendingMessage(clientMessageId)
            pendingTurnId = accepted.turnId
            await follow(turnId: accepted.turnId)
            return true
        } catch {
            handle(error)
            // Serwer cofnął ukrycie, więc wracamy do stanu sprzed poprawki.
            // Odtwarzamy go z pamięci, a nie z sieci: to jest ten sam zestaw
            // wiadomości, a ponowne pobranie w błędzie sieci i tak by padło.
            messages.removeAll { $0.id == clientMessageId }
            messages.append(contentsOf: withdrawn)
            return false
        }
    }

    // MARK: - Propozycje

    /// „Dodaj do planu" — jedyny moment, w którym asystent zmienia tydzień.
    ///
    /// Bez modelu i bez tury: klient odsyła sam identyfikator, serwer ma
    /// u siebie policzony stan docelowy. Wiadomość potwierdzającą doklejamy
    /// z odpowiedzi, więc plan i rozmowa zmieniają się w tej samej chwili.
    func applyProposal(id: String, force: Bool = false) async {
        await runProposalAction(id: id) { [client] in
            try await client.applyProposal(id: id, force: force)
        }
    }

    /// „Cofnij". Serwer odmówi, jeśli ktoś w domu ruszył plan PO zapisie —
    /// cofnięcie nie ma prawa skasować cudzej zmiany.
    func undoProposal(id: String) async {
        await runProposalAction(id: id) { [client] in
            try await client.undoProposal(id: id)
        }
    }

    private func runProposalAction(
        id: String,
        _ action: @escaping () async throws -> AgentProposalActionResultDTO
    ) async {
        guard busyProposalId == nil else { return }
        busyProposalId = id
        errorMessage = nil
        defer { busyProposalId = nil }

        do {
            let result = try await action()
            let message = Self.chatMessage(from: result.message)
            // Podwójne kliknięcie oddaje TĘ SAMĄ wiadomość, nie drugą —
            // stąd podmiana po id zamiast ślepego dopisania.
            if let existing = messages.firstIndex(where: { $0.id == message.id }) {
                messages[existing] = message
            } else {
                messages.append(message)
            }
            refreshCardState(proposalId: result.proposalId, from: result.message.card?.state)
            // Plan tygodnia właśnie się zmienił — lista rozmów pokaże to
            // przy następnym otwarciu, a zakładka Plan dostaje broadcast
            // z serwera (`weeklyPlans:weekChanged`).
            Task { [weak self] in await self?.refreshConversationsQuietly() }
        } catch {
            handle(error)
        }
    }

    /// Przepisuje stan na WSZYSTKIE karty tej propozycji.
    ///
    /// Propozycja i potwierdzenie to dwie wiadomości o jednej rzeczy: gdy
    /// tydzień zostaje zapisany, karta propozycji w historii musi przestać
    /// pokazywać „Dodaj do planu" natychmiast, a nie po ponownym wczytaniu
    /// rozmowy. Stan jest z serwera — nie zgadujemy go tutaj.
    private func refreshCardState(proposalId: String, from state: AgentCardStateDTO?) {
        guard let state else { return }
        for index in messages.indices
        where messages[index].card?.proposalId == proposalId {
            messages[index].card = messages[index].card?.withState(state)
        }
    }

    // MARK: - Błędy

    private func handle(_ error: Error) {
        if case let BackendAPIError.backend(code, _, _) = error {
            switch code {
            case "AI_DISABLED":
                isUnavailable = true
            case "AI_CONSENT_REQUIRED":
                // Arkusz zgody zamiast gołego błędu — kopia błędu i tak
                // zostaje pod rozmową na wypadek zamknięcia arkusza.
                needsConsent = true
            case "AI_QUOTA_EXCEEDED":
                lockReason = .quota
                lockedUntil = Date().addingTimeInterval(60 * 60)
                // Próba czy miesiąc? Tylko serwer to wie — odświeżamy limity,
                // żeby pole pokazało właściwy krok, a nie „spróbuj za moment".
                // W PRO blokada trwa do odnowienia puli (po godzinie ten sam
                // błąd wracał jak bumerang), na próbie — do PRO.
                Task {
                    guard let loaded = await loadUsage() else { return }
                    if let iso = loaded.resetsAt, let date = Self.parseTimestamp(iso), date > Date() {
                        lockedUntil = date
                    } else if loaded.isTrial {
                        lockedUntil = .distantFuture
                    }
                }
            case "AI_BUDGET_PAUSED":
                lockReason = .budget
                lockedUntil = Date().addingTimeInterval(15 * 60)
            case "AI_UPSTREAM_PAUSED", "TOO_MANY_REQUESTS":
                lockReason = .pause
                lockedUntil = Date().addingTimeInterval(60)
            default:
                break
            }
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
            createdAt: timestampParser.date(from: dto.createdAt),
            card: dto.card,
            usedContext: dto.usedContext ?? []
        )
    }
}
