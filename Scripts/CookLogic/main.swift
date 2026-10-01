import Foundation

// Logika trybu Gotuj (`Scoffie/Models/Cook/*`) na scenariuszu wzorcowym —
// Kotlet de volaille (backend `prisma/catalog/cook-scenarios-pl-v1.json`,
// zasady .6), bez Xcode GUI i bez targetu testów.
// Uruchomienie: `sh Scripts/cook-logic-check.sh`.
//
// `kotlet.json` = odpowiedź `recipes:cookScenario` z nazwami składników
// zamienionymi na stałe id + składniki przepisu (jak ze szczegółu, z działami
// i miarą kuchenną przypraw). Nowy scenariusz wzorcowy w backendzie = odśwież
// plik tym samym skryptem (opis w `Scripts/cook-logic-check.sh`).

var failures = 0

func check(_ condition: Bool, _ name: String) {
    if condition {
        print("OK   \(name)")
    } else {
        failures += 1
        print("BŁĄD \(name)")
    }
}

func equal<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
    if actual == expected {
        print("OK   \(name)")
    } else {
        failures += 1
        print("BŁĄD \(name): jest „\(actual)”, ma być „\(expected)”")
    }
}

struct Fixture: Decodable {
    struct RecipeIngredient: Decodable {
        let ingredientId: String
        let name: String
        let amount: Double
        let unit: String
        let department: String?
        let kitchenMeasure: KitchenMeasure?
    }

    let response: CookScenarioResponse
    let recipeIngredients: [RecipeIngredient]
}

let data = try Data(contentsOf: URL(fileURLWithPath: "Scripts/CookLogic/kotlet.json"))
let fixture = try JSONDecoder().decode(Fixture.self, from: data)

// MARK: - Dekodowanie

guard let envelope = fixture.response.scenario else {
    print("BŁĄD scenariusz: odpowiedź bez scenariusza")
    exit(1)
}
let scenario = envelope.content
equal(scenario.steps.count, 12, "dekodowanie: 12 kroków")
equal(scenario.basePortions, 2, "dekodowanie: porcje bazowe 2")
equal(scenario.timers.map(\.id), ["t-butter", "t-potatoes", "t-cutlets", "t-oven"], "dekodowanie: cztery timery po kolei")
equal(scenario.timer(id: "t-potatoes")?.trigger, .event, "dekodowanie: ziemniaki czekają na zdarzenie")
check(scenario.timer(id: "t-cutlets")?.hasRange == true, "dekodowanie: kotlety mają zakres 10–12 min")
equal(scenario.step(id: "s8")?.note?.kind, .warning, "dekodowanie: ostrzeżenie przy smażeniu")
equal(scenario.step(id: "s2")?.stageLabel, "W MIĘDZYCZASIE", "dekodowanie: etap z danych")
equal(scenario.step(id: "s1")?.stageLabel, nil, "dekodowanie: brak etapu = bez etykiety")

let unknown = #"{"id":"x","phase":"BAKE","title":"T","body":"","ingredients":[{"ingredientId":"a","amount":1,"unit":"g","part":"THIRD"}],"mentions":[],"note":{"kind":"FUN","text":"x"},"timer":null,"during":null,"scaleNote":null,"extra":1}"#
let unknownStep = try JSONDecoder().decode(CookStep.self, from: Data(unknown.utf8))
equal(unknownStep.phase, .unknown, "tolerancja: nieznana faza")
equal(unknownStep.ingredients.first?.part, .part, "tolerancja: nieznana część = sama ilość")
equal(unknownStep.note?.kind, .unknown, "tolerancja: nieznany rodzaj adnotacji")

let none = try JSONDecoder().decode(CookScenarioResponse.self, from: Data(#"{"recipeId":"r","scenario":null}"#.utf8))
check(none.scenario == nil, "odpowiedź bez scenariusza = brak trybu Gotuj")

// MARK: - Paczka i ilości

let package = CookPackage(
    recipeId: UUID(uuidString: fixture.response.recipeId)!,
    version: envelope.version,
    rulesVersion: envelope.rulesVersion,
    scenario: scenario,
    ingredients: fixture.recipeIngredients.map {
        CookIngredientInfo(
            ingredientId: $0.ingredientId.uppercased(),
            name: $0.name,
            amount: $0.amount,
            unit: $0.unit,
            department: $0.department,
            kitchenMeasure: $0.kitchenMeasure
        )
    },
    savedAt: Date(timeIntervalSince1970: 0)
)

func step(_ id: String) -> CookStep { scenario.step(id: id)! }
func texts(_ id: String, _ portions: Int) -> [String] {
    package.lines(for: step(id), portions: portions).map { line in
        [line.name, line.partLabel, line.amountText].compactMap { $0 }.joined(separator: " · ")
    }
}

equal(texts("s1", 2), ["Masło · 30 g", "Koperek · połowa · 5 g"], "krok 1, 2 porcje: masło i połowa koperku")
equal(texts("s2", 2), ["Filet z kurczaka · 320 g", "Sól · szczypta", "Pieprz czarny · połowa · ¼ łyżeczki"], "krok 2: przyprawy miarą kuchenną")
equal(texts("s4", 3), ["Mąka pszenna · 30 g", "Jajko · 2 szt", "Bułka tarta · 75 g"], "krok 4, 3 porcje: jajko 1,5 → 2")
equal(texts("s10", 3).first, "Ogórek · 380 g", "krok 10, 3 porcje: ogórek 375 → 380 g (co 10 od 100)")
equal(texts("s1", 3), ["Masło · 45 g", "Koperek · połowa · 7,5 g"], "krok 1, 3 porcje: poniżej 10 g zostaje pół grama")
equal(texts("s4", 1)[1], "Jajko · 1 szt", "krok 4, 1 porcja: pół jajka → co najmniej 1")
equal(texts("s3", 1).first, "Ziemniak · 250 g", "krok 3, 1 porcja: 250 g")
equal(CookAmounts.scaled(12, unit: .gram, factor: 1), 12, "porcje scenariusza: liczby bez zaokrąglania")
equal(CookAmounts.scaled(36, unit: .gram, factor: 1.5), 55, "54 g → 55 g (co 5 poniżej 100)")

let all = package.allLines(portions: 2)
equal(all.count, 12, "cały przepis: 12 składników")
equal(all.first { $0.name == "Koperek" }?.amountText, "10 g", "cały przepis: koperek zsumowany z kroków")
equal(all.first { $0.name == "Sól" }?.amountText, "½ łyżeczki", "cały przepis: 3 g soli = ½ łyżeczki")
equal(package.mentionNames(for: step("s7")), ["Mąka pszenna", "Jajko", "Bułka tarta"], "przywołania bez ilości")
equal(package.scaleNote(for: step("s8"), portions: 3), nil, "nota skali: poniżej progu nic")
check(package.scaleNote(for: step("s8"), portions: 4) != nil, "nota skali: od 4 porcji")

// MARK: - Tokeny {count:…}

let rolls = "Na folii uformuj {count:rolls|wałeczek|wałeczki|wałeczków} grubości palca."
equal(CookAmounts.renderBody(rolls, portions: 2), "Na folii uformuj 2 wałeczki grubości palca.", "liczba sztuk: 2 wałeczki")
equal(CookAmounts.renderBody(rolls, portions: 5), "Na folii uformuj 5 wałeczków grubości palca.", "liczba sztuk: 5 wałeczków")
equal(CookAmounts.renderBody(rolls, portions: 1), "Na folii uformuj 1 wałeczek grubości palca.", "liczba sztuk: 1 wałeczek")
equal(CookAmounts.renderBody(rolls, portions: 2.5), "Na folii uformuj 3 wałeczki grubości palca.", "liczba sztuk: 2,5 porcji → 3")
equal(CookAmounts.renderBody("Weź {count:x|a|b}.", portions: 2), "Weź {count:x|a|b}.", "zepsuty token zostaje dosłownie")
equal(CookAmounts.renderBody("Bez końca {count:x|a|b|c", portions: 2), "Bez końca {count:x|a|b|c", "niedomknięty token zostaje dosłownie")
check(package.body(for: step("s2"), portions: 2).contains("wyjdą 2 kotlety"), "treść kroku 2: „wyjdą 2 kotlety”")

// MARK: - Zegar

equal(CookClock.text(581), "9:41", "zegar: 9:41")
equal(CookClock.text(3725), "1:02:05", "zegar: z godzinami")
equal(CookClock.overdueText(42), "+0:42", "zegar: po czasie")
equal(CookClock.duration(scenario.timer(id: "t-cutlets")!), "10–12 min", "zegar: zakres słowami")
equal(CookClock.duration(scenario.timer(id: "t-potatoes")!), "20 min", "zegar: bez zakresu")

// MARK: - Sesja: kroki i dok

let t0 = Date(timeIntervalSince1970: 1_000_000)
func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

var session = CookSession(
    recipeId: package.recipeId,
    recipeTitle: "Kotlet de volaille z ziemniakami i mizerią",
    imageURL: nil,
    mealSlotRaw: "lunch",
    package: package,
    portions: 2,
    startedAt: t0
)
equal(session.stage, .welcome, "sesja: zaczyna od powitania")
session.setPortions(3)
check(session.portionsChanged, "sesja: zmiana porcji tylko w sesji")
session.setPortions(2)
session.begin(now: t0)
equal(session.currentStep?.id, "s1", "sesja: Zaczynamy → krok 1")
check(session.isFirstStep, "sesja: pierwszy krok")

func dock(_ now: Date) -> [String] {
    session.dockTimers(now: now).map { item in
        let state: String
        switch item.status {
        case .pending: state = "czeka"
        case .running: state = "trwa"
        case .paused: state = "pauza"
        case .overdue: state = "po czasie"
        case .finished: state = "gotowe"
        }
        return "\(item.timer.id):\(state):\(item.accent.rawValue)"
    }
}

equal(dock(t0), ["t-butter:czeka:terracotta"], "dok: timer bieżącego kroku czeka na start")
session.startTimer("t-butter", now: t0)
equal(dock(t0), ["t-butter:trwa:terracotta"], "dok: masło trwa, terakota")
session.next(now: at(1))
equal(session.currentStep?.id, "s2", "sesja: krok 2 w międzyczasie")
equal(dock(at(1)), ["t-butter:trwa:terracotta"], "dok: krok bez timera — trwa tylko masło")
session.next(now: at(3))
equal(dock(at(3)), ["t-butter:trwa:terracotta", "t-potatoes:czeka:sage"], "dok: aktywny + do włączenia, każdy w swoim kolorze")
equal(session.dockCapsules(now: at(3)).map(\.timer.id), ["t-butter", "t-potatoes"], "kapsuły: włączony + do włączenia")
session.next(now: at(4))
equal(session.currentStep?.id, "s4", "sesja: krok 4, ziemniaki jeszcze nie ruszyły")
equal(dock(at(4)), ["t-butter:trwa:terracotta", "t-potatoes:czeka:sage"], "dok: „Gdy woda zawrze” nie gubi się po przejściu dalej")
session.startTimer("t-potatoes", now: at(5))
equal(dock(at(5)), ["t-butter:trwa:terracotta", "t-potatoes:trwa:sage"], "dok: dwa trwają, drugi w szałwii")
if case let .running(remaining, total, _) = session.status(of: "t-potatoes", now: at(10)) {
    equal(remaining, 15 * 60, "timer: data końca — zostało 15 min")
    equal(total, 20 * 60, "timer: pełny czas 20 min")
} else {
    check(false, "timer: ziemniaki trwają")
}
check(abs((session.status(of: "t-potatoes", now: at(10))?.remainingFraction ?? 0) - 0.75) < 0.0001, "pierścień: pozostały czas 0,75")

equal(dock(at(16)), ["t-butter:po czasie:terracotta", "t-potatoes:trwa:sage"], "dok: po czasie na początku")
equal(session.ringingTimer(now: at(16))?.timer.id, "t-butter", "koniec timera: masło dzwoni")
session.silenceTimer("t-butter")
equal(session.ringingTimer(now: at(16))?.timer.id, nil, "Wycisz: już nie dzwoni")
equal(dock(at(16)).first, "t-butter:po czasie:terracotta", "Wycisz: kapsuła dalej po czasie")
session.finishTimer("t-butter")
equal(dock(at(16)), ["t-potatoes:trwa:sage"], "Gotowe: masło znika z doku")

session.pauseTimer("t-potatoes", now: at(20))
equal(dock(at(30)), ["t-potatoes:pauza:sage"], "pauza: stoi, nie dzwoni")
session.resumeTimer("t-potatoes", now: at(30))
if case let .running(remaining, _, _) = session.status(of: "t-potatoes", now: at(30)) {
    // Start 5', 20 min → koniec 25'; pauza 20' → zostało 5 min, mimo 10 min postoju.
    equal(remaining, 5 * 60, "wznowienie: zostało tyle, ile w chwili pauzy")
} else {
    check(false, "wznowienie: trwa")
}

// Stała kolejność: kroki, nie pilność — włączenie timera z dalszego kroku,
// który skończy się wcześniej, nie zamienia kapsuł miejscami.
var lineup = CookSession(recipeId: package.recipeId, recipeTitle: "K", imageURL: nil, mealSlotRaw: nil, package: package, portions: 2, startedAt: t0)
lineup.begin(now: t0)
lineup.jump(to: 2)
lineup.startTimer("t-potatoes", now: t0)
lineup.jump(to: 7)
lineup.startTimer("t-cutlets", now: at(5))
// Ziemniaki kończą się w 20', kotlety w 15' — pilność stawia kotlety pierwsze.
equal(lineup.dockTimers(now: at(6)).map(\.timer.id), ["t-cutlets", "t-potatoes"], "pilność: najbliższy koniec pierwszy")
equal(lineup.timerLineup(now: at(6)).map(\.timer.id), ["t-potatoes", "t-cutlets"], "kolejność: krok, nie koniec")
equal(lineup.dockCapsules(now: at(6)).map(\.timer.id), ["t-potatoes", "t-cutlets"], "kapsuły: bez zamiany miejsc po starcie")
lineup.pauseTimer("t-potatoes", now: at(7))
equal(lineup.timerLineup(now: at(8)).map(\.timer.id), ["t-potatoes", "t-cutlets"], "kolejność: pauza nie przestawia")

// Więcej niż dwa naraz (poza planem scenariusza, D38): kapsuły dostają
// dwa najdawniej włączone, ustawione po kroku; arkusz pokazuje wszystkie.
var three = CookSession(recipeId: package.recipeId, recipeTitle: "K", imageURL: nil, mealSlotRaw: nil, package: package, portions: 2, startedAt: t0)
three.begin(now: t0)
three.startTimer("t-butter", now: t0)
three.jump(to: 2)
three.startTimer("t-potatoes", now: at(1))
three.jump(to: 7)
three.startTimer("t-cutlets", now: at(2))
equal(three.dockCapsules(now: at(3)).map(\.timer.id), ["t-butter", "t-potatoes"], "trzy timery: dwie najstarsze kapsuły, po kroku")
three.jump(to: 8)
three.startTimer("t-oven", now: at(2))
equal(three.dockCapsules(now: at(3)).map(\.timer.id), ["t-butter", "t-potatoes"], "cztery timery: dalej dwie najstarsze kapsuły")
equal(three.dockTimers(now: at(3)).first { $0.id == "t-oven" }?.accent, CookTimerAccent.rose, "kolor: czwarty timer — róż")
equal(three.timerLineup(now: at(3)).map(\.timer.id), ["t-butter", "t-potatoes", "t-cutlets", "t-oven"], "cztery timery: arkusz pokazuje wszystkie po kroku")
// Piekarnik (5 min od 2') po czasie w 8' — najmłodszy, a stoi w doku obok
// najstarszego: wyciszony pulsuje, więc nie może czekać za „+N”.
three.silenceTimer("t-oven")
equal(three.dockCapsules(now: at(8)).map(\.timer.id), ["t-butter", "t-oven"], "po czasie: zawsze w doku, obok najstarszego")

// Pominięty timer NOW nie wraca do doku.
var skipped = CookSession(recipeId: package.recipeId, recipeTitle: "K", imageURL: nil, mealSlotRaw: nil, package: package, portions: 2, startedAt: t0)
skipped.begin(now: t0)
skipped.next(now: t0)
equal(skipped.dockTimers(now: t0).map(\.timer.id), [], "dok: pominięty timer „teraz” nie wraca")

// Smażenie, „+2 min” dwa razy, „Gotowe — dalej”.
session.jump(to: 7)
equal(session.currentStep?.id, "s8", "skok: krok 8")
session.startTimer("t-cutlets", now: at(31))
// Ziemniaki po wznowieniu kończą się w 35', kotlety w 41' — najbliższy koniec pierwszy.
equal(dock(at(31)), ["t-potatoes:trwa:sage", "t-cutlets:trwa:indigo"], "kolor: każdy timer swój — kotlety indygo")
session.extendTimer("t-cutlets", by: 120, now: at(42))
if case let .running(remaining, total, _) = session.status(of: "t-cutlets", now: at(42)) {
    equal(remaining, 120, "+2 min po czasie: liczy się od teraz")
    equal(total, 12 * 60, "+2 min: pełny czas rośnie")
} else {
    check(false, "+2 min: znowu trwa")
}
session.extendTimer("t-cutlets", by: 120, now: at(44))
equal(session.extensionHint(), "Kotlety +4 min", "podpowiedź uwag: „Kotlety +4 min”")
session.finishTimerAndAdvance("t-cutlets", now: at(47))
equal(session.currentStep?.id, "s9", "Gotowe — dalej: następny krok")

// Zapis i odczyt sesji.
let encoded = try JSONEncoder().encode(session)
let decoded = try JSONDecoder().decode(CookSession.self, from: encoded)
check(decoded == session, "zapis: sesja wraca z pliku bez zmian")

// Koniec.
session.jump(to: 11)
check(session.isLastStep, "ostatni krok")
session.next(now: at(60))
equal(session.stage, .finished, "ostatni krok → Smacznego")
equal(session.dockTimers(now: at(60)).count, 0, "zakończenie: timery zgaszone")
equal(session.cookingMinutes(now: at(70)), 60, "zakończenie: czas od „Zaczynamy”")

print(failures == 0 ? "\nWszystko zgodne." : "\nBłędów: \(failures)")
exit(failures == 0 ? 0 : 1)
