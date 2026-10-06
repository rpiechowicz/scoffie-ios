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
    /// Id wiadomości NA SERWERZE, gdy różni się od `id`. Pytanie wysłane w tej
    /// sesji stoi pod kluczem z telefonu (`clientMessageId` — od niego zależy
    /// tożsamość slotu tury), a serwer nadaje mu własne id (`202 messageId`).
    /// „Popraw pytanie” i „Spróbuj ponownie” muszą wskazać to drugie —
    /// z samym `clientMessageId` serwer odpowiadał 404.
    var serverId: String? = nil
    /// Tura, która skończyła się ZAPISEM planu — dymek dostaje skrót do Planu.
    var savedPlan: Bool = false
    /// Karta — propozycja tygodnia albo potwierdzenie zapisu. `nil` przy
    /// zwykłej odpowiedzi i przy rodzaju, którego ten build nie zna.
    var card: AgentCardDTO?
    /// „Uwzględniłem: …" — z czym serwer policzył tę odpowiedź.
    var usedContext: [String] = []
    /// Ślad tury pod odpowiedzią („Myślałem 42 s ›"). Z serwera
    /// (`AgentMessageDTO.thinking`, także w historii — od 27.09.2026) albo
    /// policzony z tury w tej sesji, gdy serwer go jeszcze nie oddaje.
    var thinking: AgentThinkingSummary? = nil
    /// Tura, która napisała wiadomość.
    var turnId: String? = nil
    /// Kciuk użytkownika pod odpowiedzią.
    var feedback: AgentFeedback? = nil
    /// Podpowiedź do kciuka w dół; `nil` = kciuk bez podpowiedzi.
    var feedbackNote: AgentFeedbackNoteDTO? = nil
    /// Własne zgłoszenie tej odpowiedzi — jest, to „Zgłoś” staje się „Popraw
    /// zgłoszenie” (serwer trzyma jedno na osobę i odpowiedź).
    var report: AgentMessageReportDTO? = nil
    /// Odpowiedź przyszła W TEJ SESJI i jeszcze nie stoi „odsłonięta”: zegar
    /// dopisywania dalej od szkicu (`AgentRevealClock.finishing` — tempo
    /// szkicu płynie dalej, reszta w ≤ 0,6 s) albo `whole` — przyszła cała
    /// i stoi od razu, razem z kartą. `nil` = historia z serwera i odpowiedzi
    /// już odsłonięte. Zdejmuje `markRevealed`.
    var reveal: AgentRevealClock? = nil
    /// Klucz miejsca w slocie ostatniej tury („turn-…") — ten sam, pod którym
    /// rysował się szkic. Dzięki niemu szkic i gotowa odpowiedź to JEDEN
    /// widok, a nie dwa przenikające się (runda 27.09.2026: „pisze jedno
    /// słowo, a potem przeskakuje i pokazuje całą odpowiedź”).
    var liveKey: String? = nil
    /// Szkic w trakcie tury — wiadomość pozorna, której nie ma w `messages`.
    var isDraft: Bool = false

    /// Tożsamość wiersza na ekranie i cel przewijania.
    var anchorID: String { liveKey ?? id }
}

enum AgentFeedback: String {
    case up = "UP"
    case down = "DOWN"
}

/// Ślad tury, który zostaje pod odpowiedzią: ile trwała i przez co przeszła.
struct AgentThinkingSummary: Equatable {
    /// Czas tury w sekundach, z dziesiątymi — wiersz „Myślałem 12,3 s" ma
    /// pokazać tę samą liczbę, na której stanął licznik. `nil` = nie dało
    /// się policzyć (brak znaczników z serwera i lokalnie).
    let duration: TimeInterval?
    let steps: [AgentProgressStepDTO]
    /// Start tury (zegar serwera) — oś „Jak pracowałem” liczy od niego
    /// sekundy kroków. `nil` = starszy serwer; oś liczy wtedy od 1. kroku.
    var startedAt: Date? = nil
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
    /// Twardy sufit czekania. Musi być WIĘKSZY niż `AI_TURN_TIMEOUT_MS`
    /// serwera (240 s) powiększony o leniwe domknięcie (5 s) — inaczej telefon
    /// mówi „nie zdążył" o turze, którą serwer właśnie kończy zapisywać.
    /// 330 s to te 245 s plus margines na sieć i na telefon, który przez
    /// chwilę leżał w tle.
    private static let pollTimeout: Duration = .seconds(330)
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
    /// Ostatni ruch w rozmowie — pytanie albo odpowiedź — z zegara telefonu,
    /// a po wczytaniu historii z `lastMessageAt` serwera. Od niego liczy się
    /// przerwa, po której następne wejście zaczyna NOWĄ rozmowę.
    private(set) var lastActivityAt: Date?
    /// Po przerwie: rozmowa ma zacząć się od zera, ale wiersz na serwerze
    /// powstaje dopiero z pierwszym pytaniem — inaczej każde zerknięcie na
    /// zakładkę zostawiałoby po sobie pustą rozmowę w historii.
    private var wantsFreshConversation = false
    private(set) var isSending = false
    /// `send()` zakłada rozmowę, a pytania jeszcze nie ma w liście — to okno
    /// (~0,5–2 s na zimnej ścieżce: pierwsze pytanie po zgodzie, po usunięciu
    /// rozmowy, wolna sieć) blokuje `canSend`, ale NIE jest turą: wskaźnik
    /// i „Stop" nie mają czego wskazywać, dopóki nie ma pytania.
    private(set) var isPreparing = false
    /// Kroki bieżącej tury — „Czytam plan tygodnia", „Zapisuję plan tygodnia".
    private(set) var progress: [AgentProgressStepDTO] = []
    /// Szkic odpowiedzi w trakcie tury (streaming z modelu przez odpytywanie):
    /// cały dotychczasowy tekst z serwera. Pusty = model jeszcze nie pisze.
    private(set) var draftText = ""
    /// Ile szkicu jest JUŻ na ekranie — jeden zegar dla szkicu i dla
    /// dopisywania gotowej odpowiedzi. Zmienia się tylko przy nowej porcji
    /// z serwera; widok liczy z niego liczbę znaków co klatkę.
    private(set) var draftReveal = AgentRevealClock()
    /// Tura, której szkic stoi (albo stał) w slocie — z niej klucz miejsca
    /// (`AgentChatMessage.liveKey`), wspólny dla szkicu i gotowej odpowiedzi.
    /// Zostaje po turze; zeruje go `resetTurnState()` razem z listą.
    private(set) var liveTurnId: String?

    /// Szkic jako wiadomość pozorna — rysowany tym samym widokiem i pod tym
    /// samym kluczem, co gotowa odpowiedź, która go zastąpi.
    var draftMessage: AgentChatMessage? {
        guard isSending, !draftText.isEmpty, let liveTurnId else { return nil }
        return AgentChatMessage(
            id: "draft-\(liveTurnId)",
            author: .assistant,
            text: draftText,
            createdAt: nil,
            reveal: draftReveal,
            liveKey: Self.liveKey(turnId: liveTurnId),
            isDraft: true
        )
    }

    static func liveKey(turnId: String) -> String { "turn-\(turnId)" }
    /// Epoka bieżącej tury — od niej wskaźnik liczy oddech glifu, połysk
    /// i próg „Możesz wyjść". Ustawiana w `send()`/`editMessage()` razem
    /// z `isSending`, żeby istniała od pierwszej klatki wskaźnika, a nie od
    /// powrotu POST; `followTurn` co najwyżej cofa ją na znacznik serwera.
    private(set) var turnStartedAt: Date?
    /// „Stop" wciśnięty, serwer jeszcze nie domknął — wiersz mówi „Zatrzymuję…".
    private(set) var isStopping = false
    /// Ostatnia tura powstała W TEJ SESJI: slot ostatniej tury dostaje wtedy
    /// minimalną wysokość okna (pytanie pod górną krawędzią, odpowiedź wyłania
    /// się pod nim). Rozmowa wczytana z historii tego nie dostaje — nie ma
    /// zostawiać ekranu pustki pod ostatnią odpowiedzią.
    private(set) var hasLiveTurnSlot = false
    /// Tożsamość tury w `followTurn` — `turnStartedAt` już nią nie jest, bo
    /// epoka wskaźnika nie ma prawa zniknąć w klatce, w której wskaźnik gaśnie.
    private var activeTurnToken: UUID?
    private(set) var errorMessage: String?
    /// Kod porażki OSTATNIEJ tury (`AI_TIMEOUT`, `AI_CANCELLED`, …) — ekran
    /// rysuje z niego kartę wyniku („To trwało za długo”), a nie tylko zdanie.
    /// `nil`, gdy błąd nie jest porażką tury (np. wysyłka nie doszła).
    private(set) var lastTurnErrorCode: String?
    /// Czy nieudana tura zdążyła COŚ zapisać. Karta wyniku mówi „Nic nie
    /// zmieniłem w planie” tylko wtedy, gdy to prawda.
    private(set) var lastTurnWrote = false
    /// Gotowe podpowiedzi pod błędem tury (po przekroczeniu czasu albo
    /// „Stop"): mniejszy zakres, bo to najczęstsza przyczyna przekroczenia
    /// czasu tury. Z serwera.
    private(set) var suggestions: [String] = []
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
    /// to próba (pokazać „Wybierz plan"), czy miesiąc (pokazać datę).
    private(set) var usage: AgentUsageDTO?
    @ObservationIgnored private var usageFetchedAt: Date?
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

    /// Lista rozmów z serwera (także pusta, świeżo założona — do niej idzie
    /// pierwsze pytanie).
    private(set) var conversations: [AgentConversationDTO] = []

    /// Historia do pokazania: bez rozmów, w których nic nie padło („Nowa
    /// rozmowa · Bez wiadomości”). Serwer od 24.09.2026 sam ich nie oddaje
    /// i kasuje po godzinie; ten filtr chroni przed starszym serwerem i przed
    /// rozmową założoną przed pytaniem, które odbiło się od puli.
    var historyConversations: [AgentConversationDTO] {
        conversations.filter { $0.title != nil || $0.lastMessageAt != nil || $0.activeTurnId != nil }
    }
    private(set) var isLoadingConversations = false

    /// Propozycja, na której właśnie pracuje serwer — kręciołek siedzi
    /// W KARCIE, bo to jej przycisk został naciśnięty. Blokujemy przy tym
    /// wszystkie karty naraz: dwa zapisy tego samego tygodnia w locie to
    /// pytanie, na które nie ma dobrej odpowiedzi.
    private(set) var busyProposalId: String?

    /// Asystent zmienił dane domu: zapisał tydzień („Dodaj do planu”,
    /// „Cofnij” albo tura z zapisem) albo odhaczył coś z rozmowy.
    /// `SessionStore` podpina tu odświeżenie listy zakupów i planu.
    ///
    /// Serwer rozgłasza to samo socketem, ale asystent jedzie po REST, a tura
    /// trwa minutę — gdy socket akurat się łączył (telefon bywał w tle),
    /// zdarzenie przepadało i lista zakupów zostawała sprzed planu.
    @ObservationIgnored var onHouseholdDataChanged: (() -> Void)?

    /// Co asystent pamięta o tym domu (pamięć wspólna dla gospodarstwa).
    private(set) var memory: [AgentMemoryNoteDTO] = []
    private(set) var isLoadingMemory = false

    /// Odpowiedzi, które przyszły, gdy użytkownik był na innej zakładce —
    /// kropka na ikonie asystenta zamyka pętlę „zapytaj, odejdź, wróć".
    private(set) var unseenAnswers = 0

    /// Powiadomienie o turze, która skończyła się poza ekranem. Zdejmuje je
    /// most w korzeniu aplikacji (`scBackgroundToast`) i od razu kasuje.
    private(set) var backgroundNotice: SCToast?

    /// Bez tego drugie identyczne powiadomienie nie zmieniłoby wartości
    /// (`SCToast` porównuje się po treści) i przepadłoby po cichu.
    func clearBackgroundNotice() {
        backgroundNotice = nil
    }

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

    var canSend: Bool { !isSending && !isPreparing && !isUnavailable && !isLocked }
    var isLocked: Bool { lockedUntil.map { $0 > Date() } ?? false }

    /// Po udanej zgodzie arkusz wraca do rozmowy; tekst do ponowienia czeka.
    func consentGranted() {
        needsConsent = false
        errorMessage = nil
    }

    /// Kciuk pod odpowiedzią. Na ekranie od razu; gdy serwer odmówi, wraca
    /// poprzedni stan, a komunikat (albo `nil`) dostaje wywołujący.
    func setFeedback(_ rating: AgentFeedback?, for messageId: String) async -> String? {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return nil }
        let previous = messages[index].feedback
        let previousNote = messages[index].feedbackNote
        guard previous != rating else { return nil }
        messages[index].feedback = rating
        // Każda zmiana oceny (kierunek albo zdjęcie) zdejmuje podpowiedź —
        // serwer robi to samo.
        messages[index].feedbackNote = nil
        do {
            try await client.rateMessage(id: messageId, rating: rating?.rawValue)
            return nil
        } catch {
            // Tylko jeśli nikt w międzyczasie nie przestawił kciuka.
            if let again = messages.firstIndex(where: { $0.id == messageId }),
               messages[again].feedback == rating {
                messages[again].feedback = previous
                messages[again].feedbackNote = previousNote
            }
            return UserFacingErrorMapper.inlineMessage(from: error)
        }
    }

    /// Ocena z podpowiedzią (powody + zdanie — „Co nie zagrało?” po kciuku
    /// w dół; kciuk w górę od 6.10.2026 podpowiedzi nie zbiera). Oddaje
    /// komunikat błędu albo `nil`. Ekran zmienia się dopiero po odpowiedzi
    /// serwera — arkusz czeka na wynik i sam pokazuje błąd.
    func suggest(
        messageId: String,
        rating: AgentFeedback,
        tags: [String],
        comment: String?
    ) async -> String? {
        do {
            try await client.rateMessage(
                id: messageId,
                rating: rating.rawValue,
                tags: tags,
                comment: comment
            )
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages[index].feedback = rating
                messages[index].feedbackNote = tags.isEmpty && comment == nil
                    ? nil
                    : AgentFeedbackNoteDTO(tags: tags, comment: comment)
            }
            return nil
        } catch {
            return UserFacingErrorMapper.inlineMessage(from: error)
        }
    }

    /// „Zgłoś odpowiedź" / „Popraw zgłoszenie" — oddaje komunikat błędu albo
    /// `nil`. Serwer trzyma jedno zgłoszenie na osobę i odpowiedź, więc drugie
    /// wysłanie je poprawia; tu zapamiętujemy, co wysłano.
    func report(messageId: String, reason: String, comment: String?) async -> String? {
        do {
            try await client.reportMessage(id: messageId, reason: reason, comment: comment)
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages[index].report = AgentMessageReportDTO(reason: reason, comment: comment)
            }
            return nil
        } catch {
            return UserFacingErrorMapper.inlineMessage(from: error)
        }
    }

    /// Po takiej przerwie od ostatniego ruchu rozmowa jest STARA: następne
    /// wejście zaczyna nową. Pół godziny, bo tyle trwa „wyszedłem do sklepu"
    /// — krótsza przerwa to wciąż ta sama sprawa („a podmień jeszcze wtorek"),
    /// a dopisywanie do wczorajszej rozmowy kończyło się tym, że pytanie
    /// o dzisiejszy obiad lądowało pod planem sprzed tygodnia i asystent
    /// odpowiadał w tamtym kontekście.
    static let staleAfter: TimeInterval = 30 * 60
    /// Zimny start jest surowszy: aplikacja zamknięta i otwarta „po chwili"
    /// ma zaczynać od czystej kartki. Trzy minuty zostają na jeden przypadek —
    /// odpowiedź doszła, iOS ubił proces, użytkownik wraca ją przeczytać.
    static let staleAfterRelaunch: TimeInterval = 3 * 60
    /// Nieobecność na zakładce (inna zakładka albo aplikacja w tle), po której
    /// SKOŃCZONA rozmowa ustępuje czystej kartce — 24.09.2026: „zaplanowałem
    /// dzień, wracam po chwili, a tam dalej stara rozmowa”. Ten sam wzorzec co
    /// w aplikacji ChatGPT (powrót = nowy czat, stary w historii); publicznego
    /// progu żaden z dużych czatów nie podaje, więc 10 min — dłużej niż
    /// zerknięcie do Planu po zapisie, krócej niż „wyszedłem do sklepu”.
    /// Przerwa liczy się i od wyjścia, i od ostatniego ruchu w rozmowie.
    static let staleAfterAway: TimeInterval = 10 * 60
    /// Kiedy użytkownik zszedł z zakładki (albo aplikacja poszła w tło).
    /// `nil` = jest na zakładce.
    @ObservationIgnored private var awaySince: Date?

    /// Otwarcie zakładki: historia rozmowy i ewentualny powrót do tury w biegu.
    func openIfNeeded() async {
        if conversationId == nil, !wantsFreshConversation {
            await loadOrCreateConversation()
        } else {
            rotateIfStale()
        }
        if let pendingTurnId, !isSending {
            await follow(turnId: pendingTurnId)
        }
    }

    /// Powrót na wierzch (zakładka, pierwszy plan) po przerwie: zaczynamy
    /// od zera, chyba że tura jeszcze biegnie — wtedy jest do czego wracać.
    /// `true` = ekran dostał czystą kartkę (powitanie ma się napisać od nowa).
    @discardableResult
    func rotateIfStale() -> Bool {
        let away = awaySince.map { Date().timeIntervalSince($0) }
        // Powrót z tła na INNEJ zakładce nie kończy nieobecności na tej —
        // liczy się dopiero wejście tutaj.
        if isVisible { awaySince = nil }
        guard conversationId != nil, !isSending, pendingTurnId == nil else { return false }
        guard let lastActivityAt else { return false }
        let idle = Date().timeIntervalSince(lastActivityAt)
        // Długa cisza w rozmowie zamyka ją zawsze — także wtedy, gdy ktoś
        // cały czas stał na zakładce.
        if idle > Self.staleAfter {
            beginFreshConversation()
            return true
        }
        // Krótszy próg tylko po NIEOBECNOŚCI i tylko dla rozmowy, która nie
        // czeka na decyzję: propozycja dnia / tygodnia z „Dodaj do planu”
        // zostaje do pełnego `staleAfter`.
        guard let away, away > Self.staleAfterAway, idle > Self.staleAfterAway,
              !hasPendingProposal else { return false }
        beginFreshConversation()
        return true
    }

    /// Ostatnia odpowiedź asystenta niesie propozycję czekającą na zapis.
    private var hasPendingProposal: Bool {
        guard let last = messages.last(where: { $0.author == .assistant }) else { return false }
        return last.card?.state?.isPending == true
    }

    /// Czysta kartka bez wiersza na serwerze — powstanie z pierwszym pytaniem.
    private func beginFreshConversation() {
        resetTurnState()
        conversationId = nil
        messages = []
        lastActivityAt = nil
        wantsFreshConversation = true
    }

    /// Rozmowa do wysłania: świeża po przerwie albo ostatnia z serwera.
    private func ensureConversation() async {
        if conversationId != nil { return }
        if !wantsFreshConversation {
            await loadOrCreateConversation()
            // Rozmowa z serwera — jest do czego pisać. Bez żadnej
            // `loadOrCreateConversation` zostawia czystą kartkę i zakładamy
            // ją poniżej, dopiero teraz, gdy pytanie naprawdę idzie.
            if conversationId != nil || !wantsFreshConversation { return }
        }
        do {
            let conversation = try await client.createConversation(householdId: householdId)
            conversationId = conversation.id
            conversations.insert(conversation, at: 0)
            wantsFreshConversation = false
        } catch {
            handle(error)
        }
    }

    /// Ekran wszedł na wierzch albo z niego zszedł. Po tym poznajemy, czy
    /// odpowiedź trzeba jeszcze zgłosić kropką na zakładce.
    func setVisible(_ visible: Bool) {
        if isVisible, !visible { awaySince = Date() }
        isVisible = visible
        if visible { unseenAnswers = 0 }
    }

    /// Aplikacja zeszła w tło, gdy zakładka była na wierzchu — to też
    /// nieobecność (`staleAfterAway`), choć zakładka się nie zmieniła.
    func noteWentToBackground() {
        guard isVisible, awaySince == nil else { return }
        awaySince = Date()
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
        lastTurnErrorCode = nil
        lastTurnWrote = false
        suggestions = []
        retryText = nil
        retryClientMessageId = nil
        // Nie `defer`: flaga ma żyć tylko przez zakładanie rozmowy, a `send()`
        // wraca dopiero po całej turze (`follow`).
        isPreparing = true
        // Pula nieznana (pierwsze pytanie zaraz po starcie, odczyt przy
        // wejściu jeszcze w drodze) — najpierw pytamy o nią, dopiero potem
        // pytanie trafia do rozmowy. Pusta pula = blokada tu, BEZ dymka
        // pytania, który serwer i tak zaraz by odrzucił.
        if usage == nil {
            _ = await loadUsage()
            guard !isLocked else {
                isPreparing = false
                return false
            }
        }
        await ensureConversation()
        isPreparing = false
        guard let conversationId else {
            // Bez rozmowy nie ma dokąd wysłać, ale tekst musi mieć drogę
            // powrotu — inaczej użytkownik zostaje z błędem i pustym polem.
            retryText = trimmed
            retryClientMessageId = clientMessageId
            return false
        }
        let sentInConversation = conversationId
        // Cała tura rusza dopiero TU, w JEDNEJ transakcji z dopisaniem pytania.
        // Wcześniej `isSending` szło w górę przed założeniem rozmowy i wiersz
        // „Zastanawiam się…" stał pod pustym stanem albo szkieletem historii,
        // a potem przeskakiwał pod pytanie, gdy `loadOrCreateConversation()`
        // podmieniła listę. Epoka razem z `isSending`: od pierwszej klatki
        // wskaźnika, nie od powrotu POST — inaczej wiersz stał bez zegara.
        isSending = true
        progress = []
        draftText = ""
        turnStartedAt = Date()
        lastActivityAt = Date()
        isStopping = false
        hasLiveTurnSlot = true
        defer { isSending = false }
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
            confirmPendingMessage(clientMessageId, serverId: accepted.messageId)
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
            hasLiveTurnSlot = false
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
    ///
    /// Wskaźnik NIE gaśnie przed odpowiedzią serwera: wiersz mówi
    /// „Zatrzymuję…", a pętla odpytywania sama zobaczy domknięcie (DONE =
    /// odpowiedź, CANCELLED = notka). Dotąd wskaźnik znikał i wracał od zera
    /// z czerwoną notką pod spodem, co czytało się jak zignorowany przycisk.
    func stopWaiting() {
        guard isSending, !isStopping else { return }
        guard let turnId = pendingTurnId else {
            // Tura nie zdążyła ruszyć na serwerze — jak dotąd: przestajemy czekać.
            abandonTurnLocally()
            return
        }
        isStopping = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let turn = try await self.client.cancelTurn(id: turnId)
                // Strażnik tożsamości: użytkownik mógł już wysłać NOWĄ wiadomość
                // albo pętla sama zdążyła domknąć tę turę.
                guard self.pendingTurnId == turnId, self.isStopping else { return }
                // Runner jest w środku narzędzia (`stopRequested`) — pętla
                // odpytywania dokończy, wiersz dalej mówi „Zatrzymuję…".
                guard turn.isFinished else { return }
                // Domykamy TU, bo pętla może właśnie spać: najpierw odbieramy
                // jej tożsamość, żeby jej `defer` niczego nie ruszył dwa razy.
                // Wszystko poniżej jest synchroniczne — jedna transakcja,
                // jeden crossfade w slocie tury.
                self.activeTurnToken = nil
                self.turnTask?.cancel()
                self.turnTask = nil
                self.pendingTurnId = nil
                if turn.status == "DONE" {
                    // Zdążył przed sygnałem — odpowiedź jest, pokazujemy ją.
                    self.errorMessage = nil
                    self.apply(finished: turn)
                } else {
                    self.errorMessage = UserFacingErrorMapper.copy(forCode: "AI_CANCELLED")
                        ?? "Zatrzymane. Plan bez zmian."
                    self.lastTurnErrorCode = turn.errorCode ?? "AI_CANCELLED"
                    self.lastTurnWrote = turn.progress.contains { $0.writes == true }
                    self.suggestions = turn.suggestions ?? []
                }
                self.isSending = false
                self.isStopping = false
                self.progress = []
                self.draftText = ""
            } catch {
                guard self.pendingTurnId == turnId else { return }
                // Starszy serwer bez trasy: dawne zachowanie.
                self.abandonTurnLocally()
            }
        }
    }

    /// Przestajemy czekać po stronie telefonu; tura na serwerze biegnie dalej
    /// i identyfikator zostaje, żeby po powrocie na zakładkę do niej wrócić.
    private func abandonTurnLocally() {
        activeTurnToken = nil
        turnTask?.cancel()
        turnTask = nil
        isSending = false
        isStopping = false
        progress = []
        draftText = ""
        errorMessage = "Przestałem czekać. Asystent kończy w tle — wróć tu za chwilę po odpowiedź."
        lastTurnErrorCode = "LOCAL_ABANDONED"
        lastTurnWrote = false
    }

    /// „Ile mi zostało" — do arkusza limitów; nie zasłania błędów rozmowy.
    func loadUsage() async -> AgentUsageDTO? {
        let loaded = try? await client.usage(householdId: householdId)
        if let loaded {
            usage = loaded
            usageFetchedAt = Date()
            if loaded.messages.remaining <= 0 {
                // Pula pusta WEDŁUG SERWERA — blokada od razu, a nie dopiero
                // po odmowie wysyłki. Dotąd stuknięcie w akcję powitania
                // wrzucało pytanie do rozmowy, a sekundę później 429 je
                // zabierało i pokazywało limit: skok w rozmowę i z powrotem.
                lockReason = .quota
                lockedUntil = Self.quotaLockEnd(for: loaded)
            } else if lockReason == .quota {
                // Pula znów ma zapas (PRO, nadanie, odnowienie, korekta limitu
                // na próbie) — blokada schodzi bez restartu aplikacji.
                lockedUntil = nil
                lockReason = nil
            }
        }
        return loaded
    }

    /// Do kiedy trzyma blokada pustej puli: do odnowienia, a na próbie
    /// (i przy puli bez odnowienia) — do wyboru planu.
    private static func quotaLockEnd(for usage: AgentUsageDTO) -> Date {
        if let iso = usage.resetsAt, let date = parseTimestamp(iso), date > Date() {
            return date
        }
        if usage.isTrial || usage.renews == false {
            return .distantFuture
        }
        return Date().addingTimeInterval(60 * 60)
    }

    /// Wejście na zakładkę: pula świeża, ZANIM ktoś stuknie w akcję.
    /// Odczyt młodszy niż `maxAge` wystarcza — po każdej turze i tak
    /// przychodzi nowy (`apply(finished:)`).
    func refreshUsageIfStale(maxAge: TimeInterval = 60) async {
        if let usageFetchedAt, Date().timeIntervalSince(usageFetchedAt) < maxAge { return }
        _ = await loadUsage()
    }

    /// Pole zablokowane przez wyczerpaną pulę na PRÓBIE — bez odnowienia,
    /// więc zamiast „spróbuj za moment" jest „Wybierz plan".
    var isLockedByTrialQuota: Bool {
        isLocked && lockReason == .quota && usage?.isTrial == true
    }

    enum LockReason { case quota, budget, pause }
    private(set) var lockReason: LockReason?

    /// „Sprawdź ponownie” na ekranie przerwy (`AssistantMaintenanceView`).
    /// Ta sama droga co wejście na zakładkę — udany odczyt rozmów zdejmuje
    /// `isUnavailable`, a 503 `AI_DISABLED` zostawia go na miejscu.
    /// `true` = asystent wrócił.
    @discardableResult
    func recheckAvailability() async -> Bool {
        guard !isCheckingAvailability else { return !isUnavailable }
        isCheckingAvailability = true
        defer { isCheckingAvailability = false }
        await loadOrCreateConversation()
        return !isUnavailable
    }

    private(set) var isCheckingAvailability = false

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

    /// Odpowiedź odsłoniła się do końca — od teraz rysuje się w całości,
    /// także po przeprowadzce wiersza ze slotu do części przed nim.
    func markRevealed(id: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }), messages[index].reveal != nil else { return }
        messages[index].reveal = nil
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
        // Świadomy wybór z historii: to jest „teraz", nie data ostatniej
        // wiadomości — inaczej stara rozmowa zamykałaby się przy najbliższym
        // powrocie na zakładkę, zanim ktokolwiek zdążył coś w niej napisać.
        wantsFreshConversation = false
        lastActivityAt = Date()
        await loadMessages(conversationId: id)
    }

    /// Zaczyna pustą rozmowę. Nowa rozmowa nie zna poprzednich wiadomości —
    /// od tego jest pamięć asystenta (notatki gospodarstwa).
    ///
    /// Czysta kartka OD RAZU, bez żądania do serwera: wiersz rozmowy powstaje
    /// z pierwszym pytaniem (`ensureConversation`), tak samo jak po przerwie.
    /// Dotąd przycisk czekał na `POST /agent/conversations`, a przez ten czas
    /// ekran pokazywał szkielet historii (`isLoadingHistory`) i dopiero potem
    /// pusty stan — dwa przeskoki zamiast jednego przejścia, do tego każde
    /// stuknięcie zostawiało w historii pustą rozmowę bez tytułu.
    func startNewConversation() async {
        // Już na czystej kartce — nie ma czego zaczynać od nowa.
        if conversationId == nil, messages.isEmpty, !isSending {
            wantsFreshConversation = true
            return
        }
        beginFreshConversation()
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

            // Zimny start po przerwie: ostatnia rozmowa zostaje w historii,
            // a zakładka otwiera się na czystej kartce. Wyjątek to tura,
            // która wciąż biegnie — wtedy trzeba do niej wrócić po odpowiedź.
            if let existing = mine.first, existing.activeTurnId == nil,
               Self.isStale(existing, after: Self.staleAfterRelaunch) {
                conversationId = nil
                messages = []
                lastActivityAt = nil
                wantsFreshConversation = true
                isUnavailable = false
                return
            }

            // Bez żadnej rozmowy: czysta kartka, a wiersz na serwerze powstaje
            // z pierwszym pytaniem (`ensureConversation`). Dotąd zakładaliśmy
            // go tutaj — przy starcie, po „Usuń” i po „Usuń historię” — i każdy
            // taki, w którym nikt nic nie napisał, wisiał potem w historii
            // jako „Nowa rozmowa · Bez wiadomości”.
            guard let conversation = mine.first else {
                conversationId = nil
                messages = []
                lastActivityAt = nil
                wantsFreshConversation = true
                isUnavailable = false
                return
            }
            conversationId = conversation.id
            // Tura, która biegła, gdy aplikacja została ubita: identyfikator
            // przychodzi z serwera, bo w pamięci telefonu go już nie ma.
            pendingTurnId = conversation.activeTurnId
            messages = try await loadAllMessages(conversationId: conversation.id)
            hasLiveTurnSlot = false
            lastActivityAt = Self.parseTimestamp(conversation.lastMessageAt)
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
            hasLiveTurnSlot = false
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
        activeTurnToken = nil
        turnTask?.cancel()
        turnTask = nil
        isSending = false
        isStopping = false
        progress = []
        draftText = ""
        // Tu podmienia się cała lista, więc skok epoki jest niewidoczny.
        turnStartedAt = nil
        liveTurnId = nil
        hasLiveTurnSlot = false
        pendingTurnId = nil
        errorMessage = nil
        lastTurnErrorCode = nil
        lastTurnWrote = false
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
        // Token jest tożsamością TEJ tury. Sprzątamy po sobie tylko wtedy, gdy
        // nikt nas nie zastąpił: anulowana tura kończy się po tym, jak
        // użytkownik zdążył wysłać następną, i bez tego gasiłaby jej wskaźnik.
        let token = UUID()
        activeTurnToken = token
        isSending = true
        // Klucz miejsca szkicu — nowa tura to nowe miejsce w slocie.
        if liveTurnId != turnId {
            liveTurnId = turnId
            draftReveal = AgentRevealClock()
        }
        // Powrót na zakładkę / relaunch: `send()` nie ustawiło epoki, a widok
        // nie ma prawa dostać `nil` — inaczej „Możesz wyjść" pojawia się od razu.
        if turnStartedAt == nil { turnStartedAt = Date() }
        var adoptedServerStart = false
        defer {
            if activeTurnToken == token {
                activeTurnToken = nil
                isSending = false
                isStopping = false
                progress = []
                draftText = ""
                // `turnStartedAt` ZOSTAJE: to epoka gasnącego wskaźnika. Nową
                // ustawia następne `send()`, a `resetTurnState()` zeruje ją
                // razem z całą listą.
            }
        }

        let deadline = ContinuousClock.now + Self.pollTimeout
        var failures = 0

        while ContinuousClock.now < deadline {
            if Task.isCancelled { return }
            do {
                let turn = try await client.turn(id: turnId)
                // „Stop" mógł domknąć turę w czasie tego żądania — wtedy
                // odpowiedź jest już w rozmowie i nie wolno dopisać jej drugi raz.
                guard activeTurnToken == token, !Task.isCancelled else { return }
                failures = 0
                if !adoptedServerStart, let serverStart = Self.parseTimestamp(turn.startedAt) {
                    adoptedServerStart = true
                    // Jeden zegar (serwera) i nigdy w przód: powrót na zakładkę
                    // w minucie tury nie ma pokazywać jej jako świeżej.
                    if let local = turnStartedAt {
                        if serverStart < local { turnStartedAt = serverStart }
                    } else {
                        turnStartedAt = serverStart
                    }
                }

                guard turn.isFinished else {
                    // Bez przypisania przy każdym odpytaniu: `@Observable`
                    // powiadamia bez porównania i co sekundę przebudowywał
                    // cały ekran rozmowy.
                    if progress != turn.progress { progress = turn.progress }
                    let draft = turn.draftText ?? ""
                    if draft != draftText { receiveDraft(draft) }
                    try await Task.sleep(for: Self.pollInterval)
                    continue
                }

                // Ostatniego kroku NIE przypisujemy — kroki trafią do „Myślałem"
                // z `turn.progress`, a wskaźnik nie ma zmieniać koloru w klatce,
                // w której gaśnie.
                // Szkic, którego gotowa odpowiedź NIE kontynuuje, szybko się
                // domyka — dopiero potem w jego miejscu staje odpowiedź.
                await letDraftFinish(before: turn)
                guard activeTurnToken == token, !Task.isCancelled else { return }
                pendingTurnId = nil
                // Komunikat z poprzedniej, nieudanej próby nie ma prawa wisieć
                // pod świeżą odpowiedzią.
                errorMessage = nil
                lastTurnErrorCode = nil
                apply(finished: turn)
                return
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                failures += 1
                if failures >= Self.maxPollFailures {
                    handle(error)
                    // Odpytywanie się poddało, ale tura biegnie dalej na
                    // serwerze — a od kiedy push przy aplikacji na wierzchu
                    // schodzi do Centrum powiadomień, to jedyny sygnał, jaki
                    // ta osoba dostanie.
                    noteUnfinishedTurnInBackground()
                    return
                }
                try? await Task.sleep(for: Self.pollInterval)
            }
        }

        // Sufit czasu. Zanim powiemy „nie zdążył", pytamy JESZCZE RAZ: pętla
        // mogła stać w tle razem z całą aplikacją, a odpowiedź czekać od dawna.
        let lastLook = try? await client.turn(id: turnId)
        guard activeTurnToken == token else { return }
        if let turn = lastLook, turn.isFinished {
            pendingTurnId = nil
            apply(finished: turn)
            return
        }
        // Identyfikatora nie kasujemy — po powrocie na zakładkę spróbujemy
        // jeszcze raz.
        errorMessage = "Asystent nie odpowiedział na czas. Wróć tu za chwilę — odpowiedź może już czekać."
        lastTurnErrorCode = "LOCAL_TIMEOUT"
        lastTurnWrote = false
        noteUnfinishedTurnInBackground()
    }

    /// Czy gotowa odpowiedź jest dalszym ciągiem tego, co szkic JUŻ pokazał.
    /// Tak — dopisuje się dalej w tym samym widoku. Nie (np. zdanie serwera po
    /// planowaniu zamiast wstępu modelu) — szkic najpierw się domyka
    /// (`letDraftFinish`), bo podmiana urwałaby pisanie w pół słowa.
    private func answerContinuesDraft(_ answer: String, at now: Date) -> Bool {
        guard !draftText.isEmpty else { return true }
        let shown = draftReveal.count(at: now, limit: draftText.count)
        return AgentRevealClock.commonPrefixCount(draftText, answer) >= shown
    }

    /// Odpowiedź, która szkicu NIE kontynuuje. 27.09.2026 (Rafał: „przerywa
    /// mu pisanie w połowie, bo już jest odpowiedź z serwera — tak nie może
    /// być”) szkic dopisywał się swoim tempem, stał 0,8 s, a odpowiedź pisała
    /// się potem od początku — do 5 s czekania na coś, co już było gotowe.
    /// Od 6.10.2026 („ruch ma mówić, że coś się zmieniło”) szkic domyka się
    /// SZYBKO — reszta w `AgentRevealClock.finishWithin` (≤ 0,6 s) — i zaraz
    /// potem `apply(finished:)` stawia w jego miejscu całą odpowiedź jednym
    /// przenikaniem. Nie urywa w pół słowa, ale też nie każe czekać.
    private func letDraftFinish(before turn: AgentTurnDTO) async {
        guard turn.status == "DONE", liveTurnId == turn.id, !draftText.isEmpty,
              let answer = turn.messages?.last(where: { $0.role == "ASSISTANT" })
        else { return }
        let now = Date()
        guard !answerContinuesDraft(answer.text, at: now) else { return }
        let total = draftText.count
        let shown = draftReveal.count(at: now, limit: total)
        // Nic jeszcze nie widać — nie ma czego domykać; już domknięty — też.
        guard shown > 0, shown < total else { return }
        draftReveal = AgentRevealClock.finishing(after: draftReveal, at: now, from: shown, total: total)
        let wait = draftReveal.finishDate(total: total).timeIntervalSince(now)
        try? await Task.sleep(for: .seconds(min(max(0, wait), AgentRevealClock.finishWithin)))
    }

    /// Nowa porcja szkicu. Zegar zaczyna od tego, co już widać (i co nowy
    /// tekst kontynuuje), a tempo dobiera tak, żeby zaległość zeszła
    /// w ~1,5 s — dłużej niż odstęp odpytywania (serwer zapisuje szkic
    /// najwyżej raz na sekundę), więc tekst płynie bez zatrzymań między
    /// porcjami. Dolna granica jest NISKA (`draftMinRate`): pierwsza porcja
    /// to zwykle jedno słowo, które przy 70 zn/s wskakiwało w 0,1 s i stało
    /// sekundę do następnej porcji — „pisze jedno słowo, a potem przeskakuje”.
    /// Górna — `maxRate`: porcja tysiąca znaków ma się PISAĆ, a nie wskakiwać.
    private func receiveDraft(_ draft: String) {
        let now = Date()
        let shown = draftReveal.count(at: now, limit: draftText.count)
        let start = min(shown, AgentRevealClock.commonPrefixCount(draftText, draft))
        let backlog = Double(max(0, draft.count - start))
        draftReveal = AgentRevealClock(
            anchorDate: now,
            anchorCount: start,
            rate: min(AgentRevealClock.maxRate, max(AgentRevealClock.draftMinRate, backlog / 1.5))
        )
        draftText = draft
    }

    /// Tura, która się nie udała, gdy nikt na nią nie patrzył.
    ///
    /// Mocniejszy przypadek niż udana odpowiedź, bo tu nie ma ŻADNEGO innego
    /// kanału: `unseenAnswers` rośnie wyłącznie przy sukcesie, więc plakietka
    /// na zakładce się nie zapala, a push `ASSISTANT_TURN_FINISHED` nie obejmuje
    /// tury, z której klient zrezygnował. `ErrorNote` z powodem i przyciskiem
    /// „Ponów" rysuje się w rozmowie, na którą nikt nie patrzy — człowiek czeka
    /// na coś, co nigdy nie przyjdzie, często zapłaciwszy za to z limitu.
    ///
    /// Podtytuł jest celowo krótki i ogólny: pełne zdanie z mappera bywa długie
    /// i stoi już w rozmowie, obok ponowienia.
    private func noteUnfinishedTurnInBackground(
        style: SCToast.Style = .error,
        title: String = "Asystent nie dokończył",
        message: String = "Pytanie zostało w rozmowie."
    ) {
        guard !isVisible else { return }
        backgroundNotice = SCToast(style: style, title: title, message: message)
    }

    private func apply(finished turn: AgentTurnDTO) {
        lastActivityAt = Date()
        // Każda domknięta tura zjadła wiadomość z puli (kwota schodzi na
        // starcie i wraca tylko przy porażce serwera), a kapsułka w nagłówku
        // liczyła ją z JEDNEGO odczytu przy otwarciu zakładki — po trzech
        // pytaniach dalej pokazywała stan sprzed rozmowy.
        Task { [weak self] in _ = await self?.loadUsage() }
        // Także tura nieudana, która zdążyła coś zapisać — lista zakupów
        // ma pokazać to, co naprawdę jest w planie.
        if turn.progress.contains(where: { $0.writes == true }) {
            onHouseholdDataChanged?()
        }
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
            if !answers.isEmpty {
                // Serwer od 27.09.2026 oddaje ślad przy odpowiedzi sam (ten sam,
                // który wróci z historią); starszy — liczymy z tury.
                if answers[answers.count - 1].thinking == nil {
                    answers[answers.count - 1].thinking = Self.thinkingSummary(for: turn, localStart: turnStartedAt)
                }
                let now = Date()
                let last = answers.count - 1
                // Szkic tej tury stoi na ekranie — ostatnia odpowiedź zajmuje
                // jego miejsce (ten sam klucz), więc to JEDEN widok: tekst
                // zmienia się w miejscu, zamiast przenikać w nowy widok, który
                // przez chwilę stałby pod gasnącym szkicem i potem podskoczył.
                let draftOnScreen = liveTurnId == turn.id && !draftText.isEmpty
                if draftOnScreen {
                    answers[last].liveKey = Self.liveKey(turnId: turn.id)
                }
                // Dopisuje się TYLKO ciąg dalszy szkicu, który był na ekranie —
                // od znaku, który JEST widoczny (nie od długości szkicu
                // z serwera: szkic dogania serwer z opóźnieniem) i od
                // wspólnego początku (nie `hasPrefix`: drobna różnica na końcu
                // szkicu zerowała odsłanianie). Tym samym zegarem
                // (`draftReveal` → `finishing`): tempo nie zmienia się skokowo,
                // a reszta schodzi w ≤ 0,6 s. Zegar żyje w wiadomości, więc
                // przebudowa wiersza nie zaczyna pisania od nowa.
                //
                // Wszystko inne — odpowiedź bez szkicu, odpowiedź, która szkicu
                // nie kontynuuje (szkic już się domknął w `letDraftFinish`),
                // i wcześniejsze odpowiedzi tury — stoi od razu w CAŁOŚCI
                // (`whole`), razem z kartą, jednym przenikaniem slotu
                // (6.10.2026: dawniej pisała się od zera do 3,5 s, a karta
                // czekała na koniec tego teatru). Szkic, z którego nic jeszcze
                // nie widać (porcja przyszła tuż przed końcem tury), to jak
                // brak szkicu — odpowiedź stoi cała.
                let shown = draftReveal.count(at: now, limit: draftText.count)
                let continues = draftOnScreen && shown > 0
                    && answerContinuesDraft(answers[last].text, at: now)
                for index in answers.indices {
                    let total = answers[index].text.count
                    if index == last, continues {
                        let from = min(shown, AgentRevealClock.commonPrefixCount(draftText, answers[index].text))
                        answers[index].reveal = AgentRevealClock.finishing(
                            after: draftReveal,
                            at: now,
                            from: from,
                            total: total
                        )
                    } else {
                        answers[index].reveal = AgentRevealClock.whole(total: total, at: now)
                    }
                }
            }
            if answers.isEmpty {
                errorMessage = "Asystent nie miał nic do powiedzenia. Spróbuj zapytać inaczej."
                lastTurnErrorCode = "AI_EMPTY_ANSWER"
                lastTurnWrote = savedPlan
                // Tura się domknęła, ale bez odpowiedzi: `unseenAnswers` nie
                // rośnie, więc plakietka na zakładce się nie zapali i nikt
                // poza ekranem by się o tym nie dowiedział.
                noteUnfinishedTurnInBackground()
            } else {
                messages.append(contentsOf: answers)
                if !isVisible {
                    unseenAnswers += answers.count
                    // Pytanie zadane i porzucone: tura biegnie 25-60 s, więc
                    // użytkownik zdążył przejść na plan. Jedynym sygnałem była
                    // dotąd liczba na pasku zakładek — kropka na DOLE ekranu,
                    // gdy patrzy się na górę.
                    backgroundNotice = SCToast(
                        style: .success,
                        title: "Asystent odpowiedział",
                        message: "Odpowiedź czeka w rozmowie."
                    )
                }
                // Tytuł rozmowy nadaje serwer z PIERWSZEJ wiadomości, a lista
                // historii ma go pokazać bez ręcznego odświeżania.
                Task { [weak self] in await self?.refreshConversationsQuietly() }
            }
        case "LIMITED":
            errorMessage = copy(forCode: turn.errorCode)
                ?? "Limit asystenta został wyczerpany."
            lastTurnErrorCode = turn.errorCode ?? "AI_QUOTA_EXCEEDED"
            lastTurnWrote = false
            // Wyczerpana pula to STAN konta, nie awaria — więc masło („uwaga"),
            // nie alarm. Ta sama kapsuła co przy padniętym serwerze mówiłaby,
            // że coś się zepsuło, a nic się nie zepsuło.
            noteUnfinishedTurnInBackground(
                style: .warning,
                title: "Limit asystenta wyczerpany",
                message: "Pula odnowi się w nowym miesiącu."
            )
        default:
            errorMessage = copy(forCode: turn.errorCode)
                ?? "Asystent nie dokończył zadania. Spróbuj ponownie."
            lastTurnErrorCode = turn.errorCode ?? "AI_PROVIDER_ERROR"
            lastTurnWrote = turn.progress.contains { $0.writes == true }
            // Podpowiedzi z serwera („tylko obiady", „3 dni") — tylko tam,
            // gdzie serwer je dał, czyli po czasie i po „Stop".
            suggestions = turn.suggestions ?? []
            noteUnfinishedTurnInBackground()
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
        lastTurnErrorCode = nil
        lastTurnWrote = false
        retryText = nil
        retryClientMessageId = nil
        isSending = true
        progress = []
        draftText = ""
        // Jak w `send()`: epoka i slot od pierwszej klatki wskaźnika.
        turnStartedAt = Date()
        hasLiveTurnSlot = true
        isStopping = false
        defer { isSending = false }

        // Serwer zna pytanie pod SWOIM id (pytanie z tej sesji ma lokalne).
        let targetId = messages[index].serverId ?? messageId
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
                    messageId: targetId,
                    text: trimmed,
                    weekStart: weekStart,
                    clientToday: PlanWeek.dateKey(Date()),
                    timeZone: TimeZone.current.identifier
                )
            )
            confirmPendingMessage(clientMessageId, serverId: accepted.messageId)
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
            hasLiveTurnSlot = false
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
            // przy następnym otwarciu, a plan i zakupy dostają broadcast
            // z serwera (`weeklyPlans:weekChanged`) i, na wypadek gdyby
            // socket go zgubił, odświeżenie wprost.
            onHouseholdDataChanged?()
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
                // `loadUsage` sam ustawia koniec blokady z odczytu puli.
                Task { _ = await loadUsage() }
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
        errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
    }

    /// Kod porażki tury (`AgentTurn.errorCode`) na kopię dla użytkownika.
    /// Tura nie jest odpowiedzią HTTP, więc nie ma tu błędu do zmapowania —
    /// jest sam kod.
    private func copy(forCode code: String?) -> String? {
        guard let code else { return nil }
        return UserFacingErrorMapper.copy(forCode: code)
    }

    private func confirmPendingMessage(_ id: String, serverId: String? = nil) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].isPending = false
        if let serverId, serverId != id { messages[index].serverId = serverId }
    }

    /// Serwer oddaje znaczniki z milisekundami (`2026-08-31T12:00:00.123Z`),
    /// więc goły `ISO8601DateFormatter` bez tej opcji zwracałby `nil`.
    private static let timestampParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Rozmowa bez ruchu dłużej niż `after`. Brak `lastMessageAt` (rozmowa
    /// założona i porzucona bez pytania) liczy się jako stara — nie ma do
    /// czego wracać.
    private static func isStale(_ conversation: AgentConversationDTO, after: TimeInterval) -> Bool {
        guard let last = parseTimestamp(conversation.lastMessageAt) else { return true }
        return Date().timeIntervalSince(last) > after
    }

    static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return timestampParser.date(from: raw)
    }

    /// Czas z PARY serwerowej (`startedAt`/`finishedAt` — jeden zegar), więc
    /// nie zależy od zegara telefonu; lokalny start tylko w zastępstwie.
    private static func thinkingSummary(for turn: AgentTurnDTO, localStart: Date?) -> AgentThinkingSummary {
        let start = parseTimestamp(turn.startedAt) ?? localStart
        let end = parseTimestamp(turn.finishedAt) ?? Date()
        var duration: TimeInterval?
        if let start {
            duration = max(0, end.timeIntervalSince(start))
        }
        // Bez kroków przejściowych (`think`, `read`, `reason`, `write`): na
        // żywo mówią, co dzieje się teraz, ale po turze byłyby tym samym
        // zdaniem co drugi wiersz listy „Myślałem". Serwer od 19.09.2026 sam
        // je zdejmuje przy domknięciu; filtr zostaje dla starszego serwera.
        return AgentThinkingSummary(
            duration: duration,
            steps: turn.progress.filter { !$0.isTransient },
            startedAt: start
        )
    }

    private static func chatMessage(from dto: AgentMessageDTO) -> AgentChatMessage {
        AgentChatMessage(
            id: dto.id,
            author: dto.role == "USER" ? .user : .assistant,
            text: dto.text,
            createdAt: timestampParser.date(from: dto.createdAt),
            card: dto.card,
            usedContext: dto.usedContext ?? [],
            // Ślad tury z serwera — także w rozmowie otwartej z historii
            // (do 27.09.2026 „Myślałem” istniało tylko w pamięci sesji).
            thinking: dto.thinking.map { thinking in
                AgentThinkingSummary(
                    duration: thinking.durationMs.map { Double($0) / 1000 },
                    steps: thinking.steps.filter { !$0.isTransient },
                    startedAt: parseTimestamp(thinking.startedAt)
                )
            },
            turnId: dto.turnId,
            feedback: dto.feedback.flatMap(AgentFeedback.init(rawValue:)),
            feedbackNote: dto.feedbackNote,
            report: dto.report
        )
    }
}

/// Zegar „pisania” odpowiedzi: od znaku `anchorCount` w chwili `anchorDate`
/// przybywa `rate` znaków na sekundę. Czysta funkcja czasu — widok liczy
/// z niej co klatkę, a sklep wie w każdej chwili, ile jest na ekranie.
///
/// Pisze się na żywo tylko SZKIC (to informacja „model pisze”). Gotowa
/// odpowiedź najwyżej domyka szkic, który już widać (`finishing`, ≤ 0,6 s),
/// a przyszła cała — stoi od razu (`whole`).
struct AgentRevealClock: Equatable {
    /// Najwolniej, jak domyka się tekst (znaki/s) — krótka reszta nie wlecze się.
    static let minRate: Double = 90
    /// Najwolniej, jak pisze się szkic — nisko, żeby pierwsze słowo nie
    /// wskakiwało i nie stało do następnej porcji z serwera.
    static let draftMinRate: Double = 18
    /// Najszybciej pisze się SZKIC — powyżej tekst przestaje się pisać,
    /// a zaczyna wskakiwać porcjami z serwera.
    static let maxRate: Double = 320
    /// Domknięcie trwa najwyżej tyle (6.10.2026; było 3,5 s): to koniec
    /// tekstu, który już stoi na ekranie, a nie drugi teatr pisania.
    static let finishWithin: TimeInterval = 0.6

    /// Zegar domknięcia: od znaku `from`, bez szarpnięcia tempa względem
    /// szkicu (`after`) — nie wolniej niż on, nie wolniej niż `minRate`
    /// i tak, żeby reszta zeszła w `finishWithin`. Bez sufitu `maxRate`:
    /// przy długiej reszcie wydłużał domknięcie do kilku sekund, a tekst
    /// stoi w układzie od pierwszej klatki, więc szybki koniec to przesuwająca
    /// się rampa krycia, nie skaczące litery.
    static func finishing(after previous: AgentRevealClock?, at now: Date, from: Int, total: Int) -> AgentRevealClock {
        let remaining = Double(max(0, total - from))
        let rate = max(minRate, previous?.rate ?? 0, remaining / finishWithin)
        return AgentRevealClock(anchorDate: now, anchorCount: from, rate: rate)
    }

    /// Odpowiedź, która przyszła CAŁA: świeża (z tej sesji — karta może sama
    /// otworzyć arkusz, znak raz podskoczy), ale nic się nie pisze — zegar
    /// startuje od ostatniego znaku.
    static func whole(total: Int, at now: Date) -> AgentRevealClock {
        AgentRevealClock(anchorDate: now, anchorCount: total)
    }

    /// Nic do dopisania już na starcie (`whole`) — karta i pasek pod tekstem
    /// nie czekają.
    func startsComplete(total: Int) -> Bool { anchorCount >= total }

    /// Kiedy zegar dojdzie do `total` znaków.
    func finishDate(total: Int) -> Date {
        let remaining = Double(max(0, total - anchorCount))
        return anchorDate.addingTimeInterval(rate > 0 ? remaining / rate : 0)
    }

    var anchorDate: Date = .distantPast
    var anchorCount = 0
    var rate: Double = AgentRevealClock.minRate

    func count(at date: Date, limit: Int) -> Int {
        let elapsed = max(0, date.timeIntervalSince(anchorDate))
        return min(limit, anchorCount + Int(elapsed * rate))
    }

    /// Długość wspólnego początku dwóch tekstów, w znakach (`Character`).
    static func commonPrefixCount(_ a: String, _ b: String) -> Int {
        var count = 0
        for (left, right) in zip(a, b) {
            guard left == right else { break }
            count += 1
        }
        return count
    }
}
