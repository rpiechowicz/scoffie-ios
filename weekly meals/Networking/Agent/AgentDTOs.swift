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
    /// Opcjonalne, bo starszy serwer tych pól nie oddaje.
    let messageCount: Int?
    /// Tura, która JESZCZE BIEGNIE w tej rozmowie — po niej klient poznaje,
    /// że jest do czego wrócić po zamknięciu aplikacji.
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
    /// Dziś zawsze `TEXT`; serwer rezerwuje inne rodzaje na karty w kliencie.
    let kind: String
    let text: String
    let clientMessageId: String?
    let turnId: String?
    let createdAt: String
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
struct AgentPostMessageRequestDTO: Encodable {
    let clientMessageId: String
    let text: String
    let weekStart: String
    let clientToday: String
    let timeZone: String
}
