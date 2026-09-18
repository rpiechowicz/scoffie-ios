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
        case openShopping = "OPEN_SHOPPING"
        /// Wysyła gotowe zdanie jako zwykłą wiadomość. Nie zmienia niczego —
        /// stąd brak `proposalId` i brak stanu do sprawdzenia.
        case ask = "ASK"
    }

    /// Surowy typ z serwera. String, nie enum: szósty typ przycisku po
    /// stronie serwera nie ma prawa wywrócić dekodera całej karty (tydzień
    /// znikał razem z nieznanym guzikiem). Nieznane → `kind == nil` → klient
    /// go nie rysuje, reszta karty zostaje.
    let type: String
    var kind: Kind? { Kind(rawValue: type) }
    let proposalId: String?
    let label: String
    /// `PRIMARY` | `SECONDARY` — o wyglądzie decyduje klient.
    let style: String
    /// Wyłącznie dla `ASK`: treść wiadomości do wysłania.
    let prompt: String?

    var id: String { "\(type)-\(proposalId ?? label)" }
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

    /// Jedyny stan, o który ekran kart faktycznie pyta. Reszta wartości
    /// (`APPLIED`, `UNDONE`, `STALE`, `EXPIRED`, `FAILED`) przyjeżdża
    /// w `status` i tam zostaje — pomocniki na każdą z nich stały tu bez
    /// jednego wywołania.
    var isPending: Bool { status == "PENDING" }
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
    /// Miniatura dania; `nil`, gdy przepis nie ma zdjęcia albo serwer jest starszy.
    let imageUrl: String?
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
    /// „Pon" — siedem dni musi zmieścić się w karcie bez przewijania.
    /// Opcjonalne, bo starszy serwer tego pola nie oddaje.
    let dayShort: String?
    let date: String
    /// „1.09".
    let dateLabel: String?
    let slots: [PlanWeekCardSlotDTO]
    let kcalTotal: Int

    var id: String { date }
    var shortName: String { dayShort ?? dayLabel }
}

struct PlanWeekCardRemovalDTO: Decodable, Equatable, Identifiable {
    let dayLabel: String
    let mealLabel: String
    let title: String
    /// Od v2: identyfikatory slotu i JEDNO słowo powodu od modelu
    /// („powtórka", „ponad cel"). Starszy serwer ich nie oddaje.
    let dayOfWeek: String?
    let mealType: String?
    let recipeId: String?
    let reason: String?

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
    /// „300 kcal poniżej celu" — sam pasek mówi „ile", ale nie „ile brakuje".
    let goalNote: String?
}

/// Propozycja tygodnia — to, co użytkownik zatwierdza jednym kliknięciem.
struct PlanWeekCardDTO: Decodable, Equatable {
    let v: Int
    let proposalId: String
    let weekStart: String
    /// „Propozycja planu" — nadtytuł gotowy do pokazania.
    let eyebrow: String?
    /// „31 sierpnia – 6 września" — drugi wiersz nadtytułu.
    let eyebrowDetail: String?
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

struct PlanDayCardSummaryDTO: Decodable, Equatable {
    let meals: Int
    let kcalTotal: Int
    let targetKcalPerDay: Int?
    /// „zostaje 228" — ile jeszcze wchodzi w cel.
    let goalNote: String?
}

/// Propozycja JEDNEGO dnia — posiłek po posiłku, z sumą wobec celu.
struct PlanDayCardDTO: Decodable, Equatable {
    let v: Int
    let proposalId: String
    let weekStart: String
    let date: String
    let eyebrow: String?
    let eyebrowDetail: String?
    let title: String
    let subtitle: String?
    let slots: [PlanWeekCardSlotDTO]
    let removed: [PlanWeekCardRemovalDTO]
    let summary: PlanDayCardSummaryDTO
    let actions: [AgentCardActionDTO]
    var state: AgentCardStateDTO
}

/// Pytanie asystenta z gotowymi odpowiedziami.
///
/// Nie ma tu stanu ani propozycji — to jest wiadomość, która ZATRZYMUJE
/// zgadywanie. Odpowiedzi wysyłają się jak zwykłe wiadomości, więc w historii
/// zostaje to, co użytkownik „powiedział".
struct ClarifyCardDTO: Decodable, Equatable {
    let v: Int
    let question: String
    let hint: String?
    let actions: [AgentCardActionDTO]
}

/// Jedna pozycja karuzeli wyboru.
struct OptionsCardItemDTO: Decodable, Equatable, Identifiable {
    let recipeId: String
    let title: String
    let kcalPerServing: Int
    let prepTimeMinutes: Int
    /// Zdjęcie z katalogu; `nil`, gdy przepis go nie ma.
    let imageUrl: String?
    /// „Najszybsze" — jedno słowo, czym to danie się wyróżnia.
    let tag: String?
    /// Gotowe zdanie do wysłania po dotknięciu.
    let prompt: String

    var id: String { recipeId }
}

/// Kilka dań do wyboru — pytanie zadane obrazkami.
///
/// Bez propozycji i bez stanu: dotknięcie wysyła wiadomość, a dopiero
/// odpowiedź modelu kończy się czymś, co da się zatwierdzić.
struct OptionsCardDTO: Decodable, Equatable {
    let v: Int
    let eyebrow: String
    let title: String
    let options: [OptionsCardItemDTO]
    let actions: [AgentCardActionDTO]
}

/// Danie po jednej stronie podmiany.
struct SwapCardSideDTO: Decodable, Equatable {
    let recipeId: String
    let title: String
    let kcalPerServing: Int
    let prepTimeMinutes: Int
}

/// Różnica warta pokazania: „−18 min", „−230 kcal".
struct SwapCardDeltaDTO: Decodable, Equatable, Identifiable {
    let value: String
    let label: String
    /// Czy ta zmiana idzie w stronę, o którą prosił użytkownik.
    let good: Bool

    var id: String { "\(value)-\(label)" }
}

/// Podmiana jednego dania: PRZED i PO w jednej ramce.
struct SwapCardDTO: Decodable, Equatable {
    let v: Int
    let proposalId: String
    let weekStart: String
    let date: String
    let eyebrow: String
    let title: String
    /// `nil`, gdy slot był pusty — wtedy to nie podmiana, tylko dołożenie.
    let from: SwapCardSideDTO?
    let to: SwapCardSideDTO
    let deltas: [SwapCardDeltaDTO]
    let actions: [AgentCardActionDTO]
    var state: AgentCardStateDTO
}

/// Usunięcie jednego posiłku z planu.
///
/// Osobna karta, a nie podmiana z pustym „po": `SwapCardDTO.to` jest celowo
/// nieopcjonalne, bo cała karta podmiany opiera się na zestawieniu dwóch dań,
/// a tutaj nic nie wchodzi w to miejsce.
struct RemoveMealCardDTO: Decodable, Equatable {
    let v: Int
    let proposalId: String
    let weekStart: String
    let date: String
    let eyebrow: String
    let title: String
    /// Co znika z planu.
    let removed: SwapCardSideDTO
    /// Powód od modelu, gdy nie zmieścił się w tytule.
    let note: String?
    let actions: [AgentCardActionDTO]
    var state: AgentCardStateDTO
}

/// Jedna osoba przy wspólnym daniu.
struct HouseholdSplitPortionDTO: Decodable, Equatable, Identifiable {
    let userId: String
    let displayName: String
    /// „2 100 kcal · bez laktozy" — cel i ograniczenia prosto z profilu.
    let goalLabel: String
    /// Jak podać TEJ osobie; jedno zdanie od modelu.
    let note: String?
    let kcal: Int

    var id: String { userId }
    /// Inicjał do awatara. Puste imię nie może dać pustego kółka.
    var initial: String {
        String(displayName.first.map(String.init) ?? "?").uppercased()
    }
}

/// Jedno danie, kilka talerzy.
struct HouseholdSplitCardDTO: Decodable, Equatable {
    let v: Int
    let proposalId: String
    let weekStart: String
    let date: String
    let eyebrow: String
    let title: String
    let prepTimeMinutes: Int
    let portions: [HouseholdSplitPortionDTO]
    let actions: [AgentCardActionDTO]
    var state: AgentCardStateDTO
}

/// Zmiana, która domyka brak: „Twarożek zamiast musli (śr.)" +24 g.
struct MacroGapBoosterDTO: Decodable, Equatable, Identifiable {
    let text: String
    let amount: Int
    /// Gotowe pytanie wysyłane strzałką przy TEJ zmianie. Starszy serwer
    /// nie oddaje pola — wtedy składamy zdanie sami z `text`.
    let prompt: String?

    var id: String { text }

    var askPrompt: String {
        prompt ?? "Zastosuj w planie tę zmianę: \(text). Pokaż mi ją jako propozycję."
    }

    /// „+24 g" / „−11 g" — znak jest treścią: przy tłuszczach zmiana idzie w dół.
    func amountLabel(unit: String) -> String {
        amount >= 0 ? "+\(amount) \(unit)" : "−\(abs(amount)) \(unit)"
    }
}

/// Luka między planem a celem — i zmiany, które ją domykają.
struct MacroGapCardDTO: Decodable, Equatable {
    let v: Int
    let eyebrow: String
    let title: String
    let macro: String
    /// „g" albo „kcal" — klient nie zgaduje jednostki.
    let unit: String
    let current: Int
    let target: Int
    let boosters: [MacroGapBoosterDTO]
    let actions: [AgentCardActionDTO]

    /// Ile z celu dowozi plan. Powyżej celu pasek nie rośnie dalej — to jest
    /// informacja „dowiezione", a nie konkurs.
    var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(current) / Double(target), 1)
    }
}

/// Dział sklepu z pozycjami.
/// Jedna pozycja działu z flagą odhaczenia (v2). Odhaczone = to, co ktoś
/// sam zaznaczył w Liście — nigdy „masz w domu".
struct ShoppingListCardEntryDTO: Decodable, Equatable, Identifiable {
    let label: String
    let isChecked: Bool

    var id: String { "\(isChecked ? 1 : 0)-\(label)" }
}

struct ShoppingListCardGroupDTO: Decodable, Equatable, Identifiable {
    let department: String
    /// Klucz działu (`DAIRY`) — pod ikonę; starszy serwer go nie oddaje.
    let departmentKey: String?
    /// Do kupienia — gotowe napisy. Zostaje dla zgodności ze starszym serwerem.
    let items: [String]
    /// Od v2: wszystkie pozycje działu, najpierw do kupienia, potem odhaczone.
    let entries: [ShoppingListCardEntryDTO]?
    /// Ile pozycji działu NIE zmieściło się w karcie.
    let hidden: Int?

    var id: String { department }

    /// Wpisy do narysowania: z `entries`, a bez nich — z `items` (nieodhaczone).
    var rows: [ShoppingListCardEntryDTO] {
        entries ?? items.map { ShoppingListCardEntryDTO(label: $0, isChecked: false) }
    }

    var remainingCount: Int { rows.filter { !$0.isChecked }.count }
}

/// Co trzeba kupić na ten tydzień.
struct ShoppingListCardDTO: Decodable, Equatable {
    let v: Int
    let weekStart: String
    let eyebrow: String
    let title: String
    let groups: [ShoppingListCardGroupDTO]
    let summary: ShoppingListCardSummaryDTO
    /// `nil`, gdy nic nie odhaczono — pusta linia mówiłaby o niczym.
    let checkedNote: String?
    /// Ile z 17 działów nie ma żadnej pozycji („+ 12 działów bez pozycji").
    let emptyDepartments: Int?
    let actions: [AgentCardActionDTO]
}

struct ShoppingListCardSummaryDTO: Decodable, Equatable {
    let remaining: Int
    let checked: Int
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
    /// „2 nowe pozycje, 1 usunięta · 1–7 września".
    let subtitle: String?
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
    case planDay(PlanDayCardDTO)
    case options(OptionsCardDTO)
    case swap(SwapCardDTO)
    case removeMeal(RemoveMealCardDTO)
    case householdSplit(HouseholdSplitCardDTO)
    case macroGap(MacroGapCardDTO)
    case shoppingList(ShoppingListCardDTO)
    case clarify(ClarifyCardDTO)
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
        case "PLAN_DAY":
            if let card = try? PlanDayCardDTO(from: decoder) {
                self = .planDay(card)
            } else {
                self = .unknown
            }
        case "OPTIONS":
            if let card = try? OptionsCardDTO(from: decoder) {
                self = .options(card)
            } else {
                self = .unknown
            }
        case "SWAP":
            if let card = try? SwapCardDTO(from: decoder) {
                self = .swap(card)
            } else {
                self = .unknown
            }
        case "REMOVE_MEAL":
            if let card = try? RemoveMealCardDTO(from: decoder) {
                self = .removeMeal(card)
            } else {
                self = .unknown
            }
        case "HOUSEHOLD_SPLIT":
            if let card = try? HouseholdSplitCardDTO(from: decoder) {
                self = .householdSplit(card)
            } else {
                self = .unknown
            }
        case "MACRO_GAP":
            if let card = try? MacroGapCardDTO(from: decoder) {
                self = .macroGap(card)
            } else {
                self = .unknown
            }
        case "SHOPPING_LIST":
            if let card = try? ShoppingListCardDTO(from: decoder) {
                self = .shoppingList(card)
            } else {
                self = .unknown
            }
        case "CLARIFY":
            if let card = try? ClarifyCardDTO(from: decoder) {
                self = .clarify(card)
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
        case .planDay(let card): return card.proposalId
        case .swap(let card): return card.proposalId
        case .removeMeal(let card): return card.proposalId
        case .householdSplit(let card): return card.proposalId
        case .applied(let card): return card.proposalId
        case .options, .macroGap, .shoppingList, .clarify, .unknown:
            return nil
        }
    }

    /// Czy karta ZASTĘPUJE tekst wiadomości, zamiast go uzupełniać.
    ///
    /// Prawie zawsze karta jest dodatkiem — model pisze zdanie, karta pokazuje
    /// liczby. Pytanie jest wyjątkiem: jego treść JEST kartą, więc pokazanie
    /// obu znaczyłoby to samo pytanie dwa razy pod rząd.
    var replacesText: Bool {
        if case .clarify = self { return true }
        return false
    }

    /// Pytanie z gotowymi odpowiedziami — jedyna karta, której wygląd
    /// zależy od NASTĘPNEJ wiadomości użytkownika (zaznaczona jest
    /// stuknięta odpowiedź).
    var isClarify: Bool {
        if case .clarify = self { return true }
        return false
    }

    var state: AgentCardStateDTO? {
        switch self {
        case .planWeek(let card): return card.state
        case .planDay(let card): return card.state
        case .swap(let card): return card.state
        case .removeMeal(let card): return card.state
        case .householdSplit(let card): return card.state
        case .applied(let card): return card.state
        case .options, .macroGap, .shoppingList, .clarify, .unknown:
            return nil
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
        case .planDay(var card):
            card.state = state
            return .planDay(card)
        case .swap(var card):
            card.state = state
            return .swap(card)
        case .removeMeal(var card):
            card.state = state
            return .removeMeal(card)
        case .householdSplit(var card):
            card.state = state
            return .householdSplit(card)
        case .applied(var card):
            card.state = state
            return .applied(card)
        case .options, .macroGap, .shoppingList, .clarify, .unknown:
            return self
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
