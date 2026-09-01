import Foundation

// Karty asystenta — kontrakt z `src/agent/cards/agent-cards.ts`.
//
// Odpowiedź asystenta przestaje być akapitem: `kind` mówi, czym jest
// wiadomość, a `card` niesie treść w kształcie, który da się narysować i na
// którym da się postawić przycisk.
//
// Trzy reguły, których ten plik pilnuje po stronie telefonu:
//
// 1. **Nieznana karta nigdy nie psuje rozmowy.** Nowy `kind` z serwera ma się
//    zdekodować jako `.unknown` i zniknąć z ekranu — wiadomość zostaje przy
//    swoim `text`, który broni się sam. Dlatego dekodery poniżej NIE rzucają:
//    build sprzed rok ma dalej działać przeciw dzisiejszemu serwerowi.
// 2. **Napisy przychodzą z serwera.** „Obiad", „Poniedziałek", etykiety
//    przycisków — klient ich nie wymyśla i nie tłumaczy kodów. Nowy rodzaj
//    karty nie wymaga wtedy wydania aplikacji.
// 3. **Klient odsyła sam `proposalId`.** Nie zna stanu docelowego i nie ma
//    jak podmienić tego, co się zapisze.

/// Deklaracja wysyłana z każdą wiadomością: „ten build umie narysować kartę".
enum AgentClientCapability {
    static let cardsV1 = "cards.v1"
}

/// Przycisk w karcie. Napis jest z serwera, zachowanie wybiera `type`.
struct AgentCardActionDTO: Decodable, Equatable, Identifiable {
    enum Kind: String, Decodable {
        case apply = "APPLY"
        case undo = "UNDO"
        case openPlan = "OPEN_PLAN"
    }

    let type: Kind
    let proposalId: String?
    let label: String
    /// `PRIMARY` | `SECONDARY` — o wyglądzie decyduje klient.
    let style: String

    var id: String { "\(type.rawValue)-\(proposalId ?? "none")" }
    var isPrimary: Bool { style == "PRIMARY" }
}

/// Stan karty — liczony przez serwer PRZY ODCZYCIE, nie zapisany w niej.
///
/// Dzięki temu karta w historii mówi prawdę: po tygodniu, na drugim telefonie
/// i po ręcznej zmianie planu. Klient nie zgaduje, czy przycisk coś jeszcze
/// zrobi — pyta o to `canApply` i `canUndo`.
struct AgentCardStateDTO: Decodable, Equatable {
    let status: String
    let canApply: Bool
    let canUndo: Bool
    let until: String?

    var isPending: Bool { status == "PENDING" }
    var isApplied: Bool { status == "APPLIED" }
    var isUndone: Bool { status == "UNDONE" }
}

struct PlanWeekCardSlotDTO: Decodable, Equatable, Identifiable {
    let mealType: String
    /// „Obiad" — gotowy napis, nie kod slotu.
    let mealLabel: String
    let recipeId: String
    let title: String
    /// Kalorie NA PORCJĘ: karta mówi o talerzu, nie o garnku.
    let kcalPerServing: Int
    let prepTimeMinutes: Int
    /// Puste = całe gospodarstwo.
    let participantIds: [String]
    /// `NEW` | `KEPT` — po tym widać, co propozycja naprawdę zmienia.
    let change: String

    var id: String { "\(mealType)-\(recipeId)" }
    var isNew: Bool { change == "NEW" }
}

struct PlanWeekCardDayDTO: Decodable, Equatable, Identifiable {
    let dayOfWeek: String
    /// „Poniedziałek".
    let dayLabel: String
    let date: String
    let slots: [PlanWeekCardSlotDTO]
    let kcalTotal: Int

    var id: String { date }
}

struct PlanWeekCardRemovalDTO: Decodable, Equatable, Identifiable {
    let dayLabel: String
    let mealLabel: String
    let title: String

    var id: String { "\(dayLabel)-\(mealLabel)-\(title)" }
}

struct PlanWeekCardSummaryDTO: Decodable, Equatable {
    let meals: Int
    let created: Int
    let updated: Int
    let removed: Int
    let averageKcalPerDay: Int
    /// Cel pytającego; `nil`, gdy nie ma go w preferencjach.
    let targetKcalPerDay: Int?
}

/// Propozycja tygodnia — to, co użytkownik zatwierdza jednym kliknięciem.
struct PlanWeekCardDTO: Decodable, Equatable {
    let v: Int
    let proposalId: String
    let weekStart: String
    let title: String
    /// Jedno zdanie modelu „dlaczego tak"; `nil`, gdy nic nie dopisał.
    let subtitle: String?
    let days: [PlanWeekCardDayDTO]
    /// Co ZNIKNIE po zapisaniu — zmiana planu nigdy nie jest cicha.
    let removed: [PlanWeekCardRemovalDTO]
    let summary: PlanWeekCardSummaryDTO
    let actions: [AgentCardActionDTO]
    /// `var`, bo po zatwierdzeniu poprawiamy stan karty NA MIEJSCU — patrz
    /// `AgentCardDTO.withState`.
    var state: AgentCardStateDTO
}

struct AppliedCardSummaryDTO: Decodable, Equatable {
    let created: Int
    let updated: Int
    let removed: Int
}

/// Potwierdzenie zapisu — z „Cofnij" W WIADOMOŚCI, nie w toaście.
///
/// Toast znika po trzech sekundach i zabiera ze sobą jedyną drogę odwrotu.
struct AppliedCardDTO: Decodable, Equatable {
    let v: Int
    let proposalId: String
    let weekStart: String
    let title: String
    let summary: AppliedCardSummaryDTO
    /// Czego „Cofnij" NIE przywróci — użytkownik ma to wiedzieć PRZED kliknięciem.
    let notes: [String]
    let actions: [AgentCardActionDTO]
    var state: AgentCardStateDTO
}

/// Karta wiadomości — jeden z rodzajów albo `.unknown`.
///
/// `init(from:)` NIE RZUCA. To jest cała umowa o zgodność wstecz: serwer może
/// dorzucić nowy rodzaj karty w każdej chwili, a build, który go nie zna,
/// pokaże samo zdanie zamiast wywrócić dekodowanie całej rozmowy.
enum AgentCardDTO: Decodable, Equatable {
    case planWeek(PlanWeekCardDTO)
    case applied(AppliedCardDTO)
    case unknown

    private enum CodingKeys: String, CodingKey { case kind }

    init(from decoder: Decoder) throws {
        guard
            let container = try? decoder.container(keyedBy: CodingKeys.self),
            let kind = try? container.decode(String.self, forKey: .kind)
        else {
            self = .unknown
            return
        }

        switch kind {
        case "PLAN_WEEK":
            if let card = try? PlanWeekCardDTO(from: decoder) {
                self = .planWeek(card)
            } else {
                self = .unknown
            }
        case "APPLIED":
            if let card = try? AppliedCardDTO(from: decoder) {
                self = .applied(card)
            } else {
                self = .unknown
            }
        default:
            self = .unknown
        }
    }

    /// Propozycja, której dotyczy karta — po niej rozpoznajemy, którą kartę
    /// odświeżyć po zatwierdzeniu i na którą nałożyć kręciołek.
    var proposalId: String? {
        switch self {
        case .planWeek(let card): return card.proposalId
        case .applied(let card): return card.proposalId
        case .unknown: return nil
        }
    }

    var state: AgentCardStateDTO? {
        switch self {
        case .planWeek(let card): return card.state
        case .applied(let card): return card.state
        case .unknown: return nil
        }
    }

    /// Kopia karty z nowym stanem.
    ///
    /// Po zatwierdzeniu propozycji karta W HISTORII musi przestać zapraszać do
    /// kliknięcia — natychmiast, nie po ponownym wczytaniu rozmowy. Stan
    /// bierzemy z odpowiedzi serwera (liczy go tak samo dla obu kart tej samej
    /// propozycji), więc to jest przepisanie prawdy, a nie zgadywanie.
    func withState(_ state: AgentCardStateDTO) -> AgentCardDTO {
        switch self {
        case .planWeek(var card):
            card.state = state
            return .planWeek(card)
        case .applied(var card):
            card.state = state
            return .applied(card)
        case .unknown:
            return .unknown
        }
    }
}

/// Odpowiedź na zatwierdzenie i cofnięcie propozycji.
struct AgentProposalActionResultDTO: Decodable {
    let proposalId: String
    /// `APPLIED` | `UNDONE`.
    let status: String
    /// Wiadomość, która właśnie powstała — doklejamy ją bez odpytywania.
    let message: AgentMessageDTO
    let changes: AgentProposalChangesDTO
}

struct AgentProposalChangesDTO: Decodable, Equatable {
    let created: Int
    let updated: Int
    let deleted: Int
}
