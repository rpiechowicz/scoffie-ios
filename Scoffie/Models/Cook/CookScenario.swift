import Foundation

// Scenariusz trybu Gotuj — kształt z backendu (`recipes:cookScenario`,
// `src/recipes/cook-scenario/cook-scenario.types.ts`). Źródło decyzji:
// `docs/workstreams/gotuj/README.md` (§6 model danych, D38 kontrakt zasad .6).
//
// Zasady kontraktu, które ten plik trzyma:
// - ilości w krokach są dla `basePortions` porcji — skaluje telefon
//   (`CookAmounts`);
// - składnik wskazuje `ingredientId` (`Ingredient.id` katalogu składników),
//   nie wiersz przepisu — nazwę i jednostkę bierzemy ze szczegółu przepisu
//   (`CookPackage.ingredients`);
// - NIEZNANE pola pomijamy, a nieznane wartości słowników (faza, część, rodzaj
//   adnotacji, wyzwalacz timera) dostają `unknown` zamiast wywracać cały
//   scenariusz. Tylko FOUNDATION — plik wchodzi do `Scripts/cook-logic-check.sh`.

/// Odpowiedź `recipes:cookScenario`. `scenario == nil` = przepis nie ma trybu
/// Gotuj (brak scenariusza, przepis trywialny — D29 — albo nieaktualny).
struct CookScenarioResponse: Decodable {
    let recipeId: String
    let scenario: CookScenarioEnvelope?
}

/// Opublikowana wersja scenariusza.
struct CookScenarioEnvelope: Codable, Equatable {
    /// Rośnie z każdą publikacją; ta sama liczba przychodzi w katalogu jako
    /// `Recipe.cookScenarioVersion` — po niej telefon wie, że kopia jest aktualna.
    let version: Int
    let rulesVersion: String
    let content: CookScenario
}

struct CookScenario: Codable, Equatable {
    let schemaVersion: Int
    /// Porcje, dla których są ilości w krokach (= `Recipe.servings` przy pisaniu).
    let basePortions: Int
    /// Sztuka dania do odmiany („kotlet / kotlety / kotletów”) — opcjonalna.
    let portionUnit: CookPortionUnit?
    let totalMinutes: Int
    /// Rady kucharza na powitaniu (§13.1), najwyżej 3.
    let tips: [String]
    /// Rada „na następny raz” na zakończeniu (§13.3, D27).
    let nextTimeTip: String?
    let steps: [CookStep]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, basePortions, portionUnit, totalMinutes, tips, nextTimeTip, steps
    }

    init(
        schemaVersion: Int = 1,
        basePortions: Int,
        portionUnit: CookPortionUnit? = nil,
        totalMinutes: Int,
        tips: [String] = [],
        nextTimeTip: String? = nil,
        steps: [CookStep]
    ) {
        self.schemaVersion = schemaVersion
        self.basePortions = max(1, basePortions)
        self.portionUnit = portionUnit
        self.totalMinutes = max(0, totalMinutes)
        self.tips = tips
        self.nextTimeTip = nextTimeTip
        self.steps = steps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        // Klamra jak przy `Recipe.servings`: przez tę liczbę dzielą się ilości.
        basePortions = max(1, try container.decode(Int.self, forKey: .basePortions))
        portionUnit = try? container.decodeIfPresent(CookPortionUnit.self, forKey: .portionUnit)
        totalMinutes = max(0, try container.decodeIfPresent(Int.self, forKey: .totalMinutes) ?? 0)
        tips = try container.decodeIfPresent([String].self, forKey: .tips) ?? []
        nextTimeTip = try container.decodeIfPresent(String.self, forKey: .nextTimeTip)
        steps = try container.decode([CookStep].self, forKey: .steps)
    }

    /// Wszystkie timery scenariusza po `id` (kolejność kroków).
    var timers: [CookTimer] { steps.compactMap(\.timer) }

    func step(id: String) -> CookStep? { steps.first { $0.id == id } }

    func timer(id: String) -> CookTimer? { timers.first { $0.id == id } }

    /// Krok, który niesie timer o tym `id`.
    func step(forTimer timerId: String) -> CookStep? {
        steps.first { $0.timer?.id == timerId }
    }
}

struct CookPortionUnit: Codable, Equatable {
    let id: String
    /// Formy odmiany: dla 1, dla 2–4, dla 5+ („kotlet”, „kotlety”, „kotletów”).
    let forms: [String]
}

enum CookStepPhase: String, Codable, Equatable {
    case prep = "PREP"
    case cook = "COOK"
    case finish = "FINISH"
    case serve = "SERVE"
    case unknown = "UNKNOWN"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }
}

/// Jaką część składnika zużywa krok — `ALL` w jednym kroku, `HALF`/`REST`
/// z podpisem („połowa”, „reszta”), `PART` bez słowa, sama ilość.
enum CookIngredientPart: String, Codable, Equatable {
    case all = "ALL"
    case half = "HALF"
    case rest = "REST"
    case part = "PART"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // Nieznana część = sama ilość, bez słowa — nic nie obiecujemy.
        self = Self(rawValue: raw) ?? .part
    }
}

enum CookNoteKind: String, Codable, Equatable {
    /// „Po czym poznać” — wskazówka zmysłowa albo temperatura.
    case cue = "CUE"
    /// Bezpieczeństwo (gorący tłuszcz, para) — maślana linijka z ikoną (§13.2).
    case warning = "WARNING"
    case tip = "TIP"
    case unknown = "UNKNOWN"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }
}

/// `now` = odliczanie od stuknięcia; `event` = czeka na zdarzenie („Gdy woda
/// zawrze”) — taki timer zostaje w doku „do włączenia”, gdy użytkownik
/// pójdzie dalej (§4.5).
enum CookTimerTrigger: String, Codable, Equatable {
    case now = "NOW"
    case event = "EVENT"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .now
    }
}

struct CookStepIngredient: Codable, Equatable {
    /// `Ingredient.id` katalogu składników (nie id wiersza przepisu).
    let ingredientId: String
    /// Ilość w jednostce przepisu, dla `basePortions`.
    let amount: Double
    /// Ta sama jednostka co w składnikach przepisu („g”, „ml”, „szt”…).
    let unit: String
    let part: CookIngredientPart
}

struct CookStepNote: Codable, Equatable {
    let kind: CookNoteKind
    let text: String
}

struct CookTimerAlert: Codable, Equatable {
    let title: String
    let body: String
}

struct CookTimer: Codable, Equatable {
    let id: String
    /// Nazwa w kapsule, Dynamic Island i alercie — RZECZ („Ziemniaki”), ≤ 14 znaków.
    let label: String
    /// Po tylu sekundach dzwoni alarm.
    let minSeconds: Int
    /// Górna granica zakresu („10–12 min”); `== minSeconds` = bez zakresu.
    let maxSeconds: Int
    let trigger: CookTimerTrigger
    /// SAM warunek startu na kapsule „do włączenia” („Gdy woda zawrze”) — bez czasu (D37).
    let startLabel: String
    let alert: CookTimerAlert

    var hasRange: Bool { maxSeconds > minSeconds }
}

struct CookScaleNote: Codable, Equatable {
    let fromPortions: Int
    let text: String
}

struct CookStep: Codable, Equatable, Identifiable {
    /// Stabilne w obrębie scenariusza („s1”…).
    let id: String
    let phase: CookStepPhase
    /// Etykieta nad tytułem („SMAŻENIE”, „W MIĘDZYCZASIE”); `nil` = z fazy.
    let stage: String?
    /// Co robisz teraz — krótkie polecenie, ≤ 30 znaków w zasadach .5.
    let title: String
    /// Jak — jedyne miejsce z tokenami `{count:…}` (D38).
    let body: String
    let ingredients: [CookStepIngredient]
    /// Przywołania bez ilości (`ingredientId`) — „z talerzy z panierką”.
    let mentions: [String]
    let note: CookStepNote?
    let timer: CookTimer?
    /// `id` timera z wcześniejszego kroku, pod którym ten krok się mieści
    /// („W MIĘDZYCZASIE”).
    let during: String?
    /// Nota skali — pokazywana dopiero od `fromPortions` porcji.
    let scaleNote: CookScaleNote?

    private enum CodingKeys: String, CodingKey {
        case id, phase, stage, title, body, ingredients, mentions, note, timer, during, scaleNote
    }

    init(
        id: String,
        phase: CookStepPhase,
        stage: String? = nil,
        title: String,
        body: String,
        ingredients: [CookStepIngredient] = [],
        mentions: [String] = [],
        note: CookStepNote? = nil,
        timer: CookTimer? = nil,
        during: String? = nil,
        scaleNote: CookScaleNote? = nil
    ) {
        self.id = id
        self.phase = phase
        self.stage = stage
        self.title = title
        self.body = body
        self.ingredients = ingredients
        self.mentions = mentions
        self.note = note
        self.timer = timer
        self.during = during
        self.scaleNote = scaleNote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        phase = try container.decodeIfPresent(CookStepPhase.self, forKey: .phase) ?? .unknown
        stage = try container.decodeIfPresent(String.self, forKey: .stage)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        ingredients = try container.decodeIfPresent([CookStepIngredient].self, forKey: .ingredients) ?? []
        mentions = try container.decodeIfPresent([String].self, forKey: .mentions) ?? []
        // Obca adnotacja albo timer gubią tylko siebie, nie cały krok.
        note = try? container.decodeIfPresent(CookStepNote.self, forKey: .note)
        timer = try? container.decodeIfPresent(CookTimer.self, forKey: .timer)
        during = try container.decodeIfPresent(String.self, forKey: .during)
        scaleNote = try? container.decodeIfPresent(CookScaleNote.self, forKey: .scaleNote)
    }

    /// Etykieta nad tytułem: z kroku, a bez niej — nic. Z fazy nie zgadujemy
    /// słowa, bo „PRZYGOTOWANIE” nad połową kroków nic nie mówi (§13.2 —
    /// etap tylko tam, gdzie niesie znaczenie).
    var stageLabel: String? {
        guard let stage = stage?.trimmingCharacters(in: .whitespacesAndNewlines), !stage.isEmpty else {
            return nil
        }
        return stage
    }
}

// MARK: - Paczka offline

/// Scenariusz razem ze składnikami przepisu — wszystko, czego tryb Gotuj
/// potrzebuje bez sieci (§4.7 „Brak sieci w kuchni”).
///
/// Składniki są tu, bo scenariusz wskazuje je po `ingredientId`, a katalog
/// na telefonie tego pola nie niesie — ma je tylko szczegół przepisu
/// (`recipes:findById`). Paczka powstaje raz, przy pobraniu, i od tej chwili
/// nie zależy od stanu katalogu.
struct CookPackage: Codable, Equatable {
    /// Zmiana kształtu paczki = podbij; stary plik zostanie pominięty.
    static let currentFormat = 1

    let format: Int
    let recipeId: UUID
    let version: Int
    let rulesVersion: String
    let scenario: CookScenario
    let ingredients: [CookIngredientInfo]
    let savedAt: Date

    init(
        recipeId: UUID,
        version: Int,
        rulesVersion: String,
        scenario: CookScenario,
        ingredients: [CookIngredientInfo],
        savedAt: Date
    ) {
        self.format = Self.currentFormat
        self.recipeId = recipeId
        self.version = version
        self.rulesVersion = rulesVersion
        self.scenario = scenario
        self.ingredients = ingredients
        self.savedAt = savedAt
    }

    /// Składnik przepisu po `ingredientId` scenariusza (wielkość liter bez
    /// znaczenia — UUID przychodzi z serwera małymi literami, a `UUID`
    /// w Swifcie wypisuje wielkie).
    func ingredient(_ ingredientId: String) -> CookIngredientInfo? {
        let key = ingredientId.lowercased()
        return ingredients.first { $0.ingredientId == key }
    }
}

/// Składnik przepisu w paczce: to, co trzeba, żeby pokazać ilość po ludzku.
struct CookIngredientInfo: Codable, Equatable {
    /// `Ingredient.id` katalogu składników, małymi literami.
    let ingredientId: String
    let name: String
    /// Ilość w CAŁYM przepisie (dla `Recipe.servings`) — do arkusza
    /// „Cały przepis” i sprawdzenia sum.
    let amount: Double
    let unit: String
    /// Dział sklepu („Warzywa i owoce”, „Przyprawy i sosy”…) — kolor ikony
    /// w arkuszu składników (D36) i miara kuchenna przypraw.
    let department: String?
    let kitchenMeasure: KitchenMeasure?

    init(
        ingredientId: String,
        name: String,
        amount: Double,
        unit: String,
        department: String?,
        kitchenMeasure: KitchenMeasure?
    ) {
        self.ingredientId = ingredientId.lowercased()
        self.name = name
        self.amount = amount
        self.unit = unit
        self.department = department
        self.kitchenMeasure = kitchenMeasure
    }
}
