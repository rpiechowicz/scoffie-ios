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
    /// `PREFERENCE` | `CONSTRAINT` | `HABIT` — grupa na ekranie pamięci.
    /// Opcjonalne, bo starszy serwer tego pola nie oddaje (wtedy: preferencje).
    let kind: String?
    let createdByUserId: String?
    let createdAt: String

    var group: AgentMemoryGroup { AgentMemoryGroup(rawValue: kind ?? "") ?? .preference }
}

/// Grupy notatek — kolejność jak na ekranie „Co o Was pamięta".
enum AgentMemoryGroup: String, CaseIterable, Identifiable {
    case preference = "PREFERENCE"
    case constraint = "CONSTRAINT"
    case habit = "HABIT"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preference: return "Preferencje"
        case .constraint: return "Ograniczenia"
        case .habit: return "Zwyczaje"
        }
    }
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
    /// „Uwzględniłem: …" — z czym serwer policzył TĘ odpowiedź (tydzień,
    /// dla kogo, cel). Tylko przy odpowiedziach asystenta; starszy serwer
    /// nie oddaje pola.
    let usedContext: [String]?
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
    /// `PLANNING` = od tego kroku turę prowadzi dokładniejszy model
    /// (`start_planning`). Rysowane jako osobny moment z licznikiem, nie
    /// jako kolejna linijka.
    let phase: String?
    /// Krok PRZEJŚCIOWY (`think`): model czyta wyniki narzędzi i decyduje, co
    /// dalej — pokazywany na żywo, pomijany w podsumowaniu po turze. Brak
    /// pola = zwykły krok (starszy serwer go nie oddaje).
    let transient: Bool?

    var isHandoff: Bool { phase == "PLANNING" }
    var isTransient: Bool { transient == true }
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
    /// Gotowe podpowiedzi pod błędem (po `AI_TIMEOUT` / `AI_CANCELLED`):
    /// mniejszy zakres, bo to najczęstsza przyczyna przekroczenia czasu.
    let suggestions: [String]?
    /// Narastający tekst odpowiedzi, TYLKO gdy tura biegnie — cały
    /// dotychczasowy, nie przyrost. Starszy serwer go nie oddaje.
    let draftText: String?
    let startedAt: String
    let finishedAt: String?

    var isFinished: Bool { status != "RUNNING" }
}

// MARK: - Kontekst chipów i limity

struct AgentQuotaDTO: Decodable, Equatable {
    let used: Int
    let limit: Int
    let remaining: Int

    /// Ile z puli poszło; powyżej limitu pasek nie rośnie dalej.
    var fraction: Double {
        guard limit > 0 else { return 0 }
        return min(Double(used) / Double(limit), 1)
    }
}

struct AgentUsageByUserDTO: Decodable, Equatable, Identifiable {
    let userId: String
    let displayName: String
    let messages: Int

    var id: String { userId }
}

/// `GET /agent/usage` — „ile mi zostało" i kto ile zużył.
struct AgentUsageDTO: Decodable, Equatable {
    let householdId: String
    /// `YYYY-MM` (PRO) albo `trial` (jednorazowa pula na próbę).
    let period: String
    /// Kiedy pula wraca; `nil` na próbie — nie odnawia się.
    let resetsAt: String?
    /// Czy pula wraca co miesiąc; starszy serwer nie oddaje pola (= tak).
    let renews: Bool?
    /// `TRIAL` albo `PRO` (starszy serwer: `FREE` = pula miesięczna).
    let tier: String
    /// Skąd PRO: `SUBSCRIPTION`, `GRANTED` (nadanie), `ENV`; `TRIAL` na próbie.
    let source: String?
    /// Nazwa kupionego planu (Solo/Duet/Rodzina); `nil` = limity z konfiguracji.
    let product: String?
    let messages: AgentQuotaDTO
    let plans: AgentQuotaDTO
    /// Rozkład na domowników w tym okresie; starszy serwer nie oddaje pola.
    let byUser: [AgentUsageByUserDTO]?

    /// Imię osoby, której subskrypcja napędza ten dom; `null` poza subskrypcją.
    let payerName: String?
    /// Czy to pytający płaci. Opcjonalne, bo starszy serwer tego nie oddaje.
    let isPayer: Bool?

    var isTrial: Bool { tier == "TRIAL" }
    /// Domyślnie NIE płatnik: brak informacji nie może dawać komuś dostępu do
    /// cudzej subskrypcji w Ustawieniach iOS.
    var isThePayer: Bool { isPayer ?? false }
    /// „Zarządzaj subskrypcją" ma sens tylko, gdy PRO pochodzi z App Store.
    /// „Zarządzaj subskrypcją" widzi WYŁĄCZNIE płatnik.
    ///
    /// Dotąd warunek brzmiał „dom ma subskrypcję", więc przycisk dostawał też
    /// domownik, który za nic nie płaci — i lądował w Ustawieniach iOS, gdzie
    /// nie ma żadnej subskrypcji do zarządzania. Teraz decyduje `isPayer`
    /// z serwera, bo tylko on wie, czyj `identityHash` stoi przy umowie.
}

// MARK: - Żądania

struct AgentCreateConversationRequestDTO: Encodable {
    let householdId: String
}

/// Zatwierdzenie propozycji. `force` = „Zapisz mimo to" z karty STALE:
/// plan zmienił się od propozycji, użytkownik to widzi i mimo to zapisuje.
/// Serwer pomija wtedy porównanie z odciskiem tygodnia, ale nie walidację.
struct AgentApplyProposalRequestDTO: Encodable {
    let force: Bool
}

/// Wiadomość do asystenta.
///
/// Daty liczy TELEFON: serwer stoi w UTC i nie ma prawa zgadywać, który
/// dzień jest „dziś" ani od którego poniedziałku zaczyna się tydzień
/// użytkownika. `clientMessageId` jest kluczem idempotencji — ponowione
/// żądanie po utraconej odpowiedzi oddaje TĘ SAMĄ turę, zamiast płacić
/// drugi raz za ten sam prompt.
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
    /// Co ten build umie narysować. Serwer w trybie `soft` po tym poznaje,
    /// że wolno mu skończyć turę propozycją zamiast zapisem.
    let clientCapabilities: [String] = [AgentClientCapability.cardsV1]
}
