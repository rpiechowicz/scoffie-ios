import Foundation

// DTO asystenta AI — kształt 1:1 z `src/agent/` w backendzie.
//
// Asystent jedzie po REST, nie po sockecie, i to jest świadome: tura trwa
// dziesiątki sekund, kosztuje pieniądze i musi przeżyć telefon wchodzący
// w tło. Stąd `202 Accepted` z identyfikatorem tury i odpytywanie stanu,
// zamiast czekania na ack, który by się nie doczekał.

/// Rozmowa — jedna per użytkownik, przypięta do gospodarstwa.
struct AgentConversationDTO: Decodable, Identifiable, Equatable {
    let id: String
    let householdId: String
    let status: String
    /// Nadawany przez serwer z PIERWSZEJ wiadomości; starsze rozmowy mają `nil`.
    let title: String?
    let lastMessageAt: String?
    let createdAt: String
    /// Początek ostatniej wiadomości — bez tego lista rozmów jest listą dat.
    let preview: String?
    /// Tura, która JESZCZE BIEGNIE w tej rozmowie — po niej klient poznaje,
    /// że jest do czego wrócić po zamknięciu aplikacji. Opcjonalne, bo starszy
    /// serwer tego pola nie oddaje.
    let activeTurnId: String?
}

/// Notatka pamięci asystenta — jedno trwałe zdanie o gospodarstwie.
struct AgentMemoryNoteDTO: Decodable, Identifiable, Equatable {
    let id: String
    let text: String
    let createdByUserId: String?
    let createdAt: String
}

struct AgentMessageDTO: Decodable, Identifiable, Equatable {
    let id: String
    /// `USER` albo `ASSISTANT`.
    let role: String
    /// `TEXT` | `PLAN_WEEK` | `APPLIED` — czym JEST ta wiadomość.
    let kind: String
    let text: String
    let clientMessageId: String?
    let turnId: String?
    let createdAt: String
    /// Karta — DODATEK do `text`, nigdy zamiennik. Starszy serwer i zwykła
    /// odpowiedź tekstowa dają `nil`, a nieznany rodzaj `.unknown`: w obu
    /// wypadkach zostaje zdanie, które broni się samo.
    let card: AgentCardDTO?
}

struct AgentMessagesResponseDTO: Decodable {
    let messages: [AgentMessageDTO]
}

/// Odpowiedź na wysłanie wiadomości: tura ruszyła, odpowiedzi jeszcze nie ma.
struct AgentAcceptedTurnDTO: Decodable {
    let turnId: String
    let messageId: String
    let status: String
    let requestId: String
}

/// Krok postępu tury — co asystent robi w tej chwili.
///
/// `label` to gotowe zdanie po polsku z serwera, więc nowy krok nie wymaga
/// wydania aplikacji. `tool` zostaje dla ikony i na wypadek, gdybyśmy
/// kiedyś chcieli własnej kopii.
struct AgentProgressStepDTO: Decodable, Equatable {
    let tool: String
    let label: String
    let at: String
    /// Czy krok ZMIENIŁ dane gospodarstwa — po tym poznajemy, że po turze
    /// jest co otworzyć. Opcjonalne, bo tury sprzed tego pola siedzą
    /// w bazie i muszą się nadal dekodować.
    let writes: Bool?
}

struct AgentTurnUsageDTO: Decodable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let costMicroUsd: Int
}

struct AgentTurnDTO: Decodable, Equatable {
    let id: String
    let conversationId: String
    /// `RUNNING` | `DONE` | `FAILED` | `LIMITED`.
    let status: String
    let progress: [AgentProgressStepDTO]
    let errorCode: String?
    /// Wypełnione dopiero przy `DONE`.
    let messages: [AgentMessageDTO]?
    let usage: AgentTurnUsageDTO?
    let startedAt: String
    let finishedAt: String?

    var isFinished: Bool { status != "RUNNING" }
}

// MARK: - Żądania

struct AgentCreateConversationRequestDTO: Encodable {
    let householdId: String
}

/// Wiadomość do asystenta.
///
/// Daty liczy TELEFON: serwer stoi w UTC i nie ma prawa zgadywać, który
/// dzień jest „dziś" ani od którego poniedziałku zaczyna się tydzień
/// użytkownika. `clientMessageId` jest kluczem idempotencji — ponowione
/// żądanie po utraconej odpowiedzi oddaje TĘ SAMĄ turę, zamiast płacić
/// drugi raz za ten sam prompt.
/// Zdjęcie dołączone do wiadomości.
///
/// Serwer go NIE ZAPISUJE — idzie prosto do modelu i znika razem z turą.
/// Dlatego jedzie w kopercie wiadomości, a nie osobnym wysyłaniem pliku:
/// nie ma czego wgrywać, jest tylko co pokazać.
struct AgentImageRequestDTO: Encodable {
    let mediaType: String
    /// base64 bez prefiksu `data:`.
    let data: String
}

/// Poprawienie własnego pytania.
///
/// Nie jest to edycja tekstu w miejscu: serwer wycofuje poprawianą wiadomość
/// i wszystko, co po niej, a potem uruchamia nową turę. Dlatego koperta jest
/// ta sama co przy wysyłce, z jednym polem więcej.
struct AgentEditMessageRequestDTO: Encodable {
    let clientMessageId: String
    let messageId: String
    let text: String
    let weekStart: String
    let clientToday: String
    let timeZone: String
    let clientCapabilities: [String] = [AgentClientCapability.cardsV1]
}

struct AgentPostMessageRequestDTO: Encodable {
    let clientMessageId: String
    let text: String
    let weekStart: String
    let clientToday: String
    let timeZone: String
    let image: AgentImageRequestDTO?
    /// Co ten build umie narysować. Serwer w trybie `soft` po tym poznaje,
    /// że wolno mu skończyć turę propozycją zamiast zapisem.
    let clientCapabilities: [String] = [AgentClientCapability.cardsV1]
}
