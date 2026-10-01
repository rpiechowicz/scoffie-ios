import SwiftUI

#if DEBUG
/// Tryb Gotuj bez sesji i bez sieci, na scenariuszu kotleta (ten sam wzorzec
/// co `Scripts/cook-logic-check.sh`) — do porównania z makietą „Gotuj —
/// design”. Wejście przez `SCOFFIE_DEBUG_OPTIONS` (patrz
/// `AssistantOptionsDebugScreen`):
///
/// - `gotuj` / `gotuj-powitanie` — powitanie (WL1);
/// - `gotuj-krok` — krok 8, ziemniaki trwają, kotlety do włączenia (Y3K2);
/// - `gotuj-dwa` — krok 8, dwa timery trwają (Y3K3);
/// - `gotuj-jeden` — krok 10, jeden timer trwa (Y3K1);
/// - `gotuj-pauza` — krok 8, kotlety wstrzymane (Y3S „Jeden wstrzymany”);
/// - `gotuj-timery` / `gotuj-skladniki` — otwarty arkusz Timery / Składniki (Y3T1 / Y3I);
/// - `gotuj-alarm` — kotlety po czasie (ST4);
/// - `gotuj-wyjscie` — arkusz „Wychodzisz z gotowania?” z dwoma timerami (XW2);
/// - `gotuj-koniec` — zakończenie (EF8).
struct CookDebugScreen: View {
    let mode: String
    /// Raz na ekran — `@State`, żeby przerysowanie rodzica nie zaczynało sesji od nowa.
    @State private var store: CookSessionStore?

    init(mode: String) {
        self.mode = mode
        _store = State(initialValue: Self.store(for: mode))
    }

    var body: some View {
        if let store {
            CookModeView(
                store: store,
                onEaten: { _ in },
                initialSheet: Self.sheet(for: mode)
            )
        } else {
            Text("Nie udało się wczytać wzorca kotleta.")
        }
    }

    private static func sheet(for mode: String) -> CookSheet? {
        switch mode {
        case "gotuj-timery": .timers
        case "gotuj-skladniki": .ingredients
        case "gotuj-wyjscie": .exit
        default: nil
        }
    }

    private static func store(for mode: String) -> CookSessionStore? {
        guard var session = session() else { return nil }
        let now = Date()
        func minutesAgo(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        switch mode {
        case "gotuj-krok", "gotuj-timery":
            session.begin(now: minutesAgo(40))
            session.jump(to: 2)
            session.startTimer("t-potatoes", now: minutesAgo(5.47))
            session.jump(to: 7)
        case "gotuj-dwa", "gotuj-wyjscie":
            session.begin(now: minutesAgo(40))
            session.jump(to: 2)
            session.startTimer("t-potatoes", now: minutesAgo(5.47))
            session.jump(to: 7)
            session.startTimer("t-cutlets", now: minutesAgo(0.32))
        case "gotuj-jeden", "gotuj-skladniki":
            session.begin(now: minutesAgo(45))
            session.jump(to: 8)
            session.startTimer("t-oven", now: minutesAgo(1.33))
            session.jump(to: 9)
        case "gotuj-pauza":
            session.begin(now: minutesAgo(40))
            session.jump(to: 7)
            session.startTimer("t-cutlets", now: minutesAgo(1))
            session.pauseTimer("t-cutlets", now: minutesAgo(0.68))
        case "gotuj-alarm":
            session.begin(now: minutesAgo(45))
            session.jump(to: 2)
            session.startTimer("t-potatoes", now: minutesAgo(5.47))
            session.jump(to: 7)
            session.startTimer("t-cutlets", now: minutesAgo(10.3))
        case "gotuj-koniec":
            session.begin(now: minutesAgo(52))
            session.jump(to: 11)
            session.next(now: now)
        default:
            break
        }
        let store = CookSessionStore(preview: session)
        return store
    }

    private static func session() -> CookSession? {
        guard let fixture = try? JSONDecoder().decode(Fixture.self, from: Data(json.utf8)),
              let envelope = fixture.response.scenario,
              let recipeId = UUID(uuidString: fixture.response.recipeId) else { return nil }
        let package = CookPackage(
            recipeId: recipeId,
            version: envelope.version,
            rulesVersion: envelope.rulesVersion,
            scenario: envelope.content,
            ingredients: fixture.recipeIngredients.map {
                CookIngredientInfo(
                    ingredientId: $0.ingredientId,
                    name: $0.name,
                    amount: $0.amount,
                    unit: $0.unit,
                    department: $0.department,
                    kitchenMeasure: $0.kitchenMeasure
                )
            },
            savedAt: Date()
        )
        return CookSession(
            recipeId: recipeId,
            recipeTitle: "Kotlet de volaille z ziemniakami i mizerią",
            imageURL: URL(string: "https://img.scoffie.app/recipe-images/70d8db3e-e896-460e-ba96-d53d02c1357f.webp"),
            mealSlotRaw: MealSlot.lunch.rawValue,
            planDateKey: PlanWeek.dateKey(Date()),
            difficultyRaw: Difficulty.medium.rawValue,
            kcalPerServing: 833,
            package: package,
            portions: 2,
            startedAt: Date()
        )
    }

    private struct Fixture: Decodable {
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

    /// Kopia `Scripts/CookLogic/kotlet.json` (odświeżana tym samym
    /// `make-fixture.mjs` — wklej wynik tutaj).
    private static let json = #"""
{
  "response": {
    "recipeId": "70d8db3e-e896-460e-ba96-d53d02c1357f",
    "scenario": {
      "version": 1,
      "rulesVersion": "2026-09-30.6",
      "content": {
        "schemaVersion": 1,
        "basePortions": 2,
        "portionUnit": {
          "id": "cutlet",
          "forms": [
            "kotlet",
            "kotlety",
            "kotletów"
          ]
        },
        "totalMinutes": 50,
        "tips": [
          "Masło musi być miękkie — prosto z lodówki rozgnieć je widelcem w ciepłej miseczce.",
          "Filety wybierz podobnej wielkości — kotlety usmażą się i dopieką w tym samym czasie.",
          "Przy obracaniu nie przekłuwaj kotletów widelcem — przez dziurkę wycieknie masło."
        ],
        "nextTimeTip": "Kotlety możesz zawinąć dzień wcześniej i trzymać w lodówce — obiad zajmie wtedy 25 minut.",
        "steps": [
          {
            "id": "s1",
            "phase": "PREP",
            "stage": null,
            "title": "Zrób masło koperkowe",
            "body": "Posiekaj cały koperek drobno i odłóż połowę — przyda się do ziemniaków. Masło rozgnieć widelcem z koperkiem na gładką masę. Na folii uformuj {count:rolls|wałeczek|wałeczki|wałeczków} grubości palca, zawiń szczelnie i połóż płasko w zamrażarce.",
            "ingredients": [
              {
                "ingredientId": "00000000-0000-4000-8000-000000000002",
                "amount": 30,
                "unit": "g",
                "part": "ALL"
              },
              {
                "ingredientId": "00000000-0000-4000-8000-000000000003",
                "amount": 5,
                "unit": "g",
                "part": "HALF"
              }
            ],
            "mentions": [],
            "note": null,
            "timer": {
              "id": "t-butter",
              "label": "Masło",
              "minSeconds": 900,
              "maxSeconds": 900,
              "trigger": "NOW",
              "startLabel": "Masło w zamrażarce",
              "alert": {
                "title": "Masło gotowe",
                "body": "Wyjmij wałeczki z zamrażarki."
              }
            },
            "during": null,
            "scaleNote": null
          },
          {
            "id": "s2",
            "phase": "PREP",
            "stage": "W MIĘDZYCZASIE",
            "title": "Rozbij filety na kotlety",
            "body": "Każdy filet przetnij poziomo na dwa płaty, jak otwierając książkę — wyjdą {count:cutlets|kotlet|kotlety|kotletów}. Przykryj folią i rozbij tłuczkiem od środka na ok. 0,5 cm — równa grubość to równe smażenie. Posól i popieprz z obu stron.",
            "ingredients": [
              {
                "ingredientId": "00000000-0000-4000-8000-000000000001",
                "amount": 320,
                "unit": "g",
                "part": "ALL"
              },
              {
                "ingredientId": "00000000-0000-4000-8000-000000000011",
                "amount": 1,
                "unit": "g",
                "part": "PART"
              },
              {
                "ingredientId": "00000000-0000-4000-8000-000000000012",
                "amount": 0.5,
                "unit": "g",
                "part": "HALF"
              }
            ],
            "mentions": [],
            "note": {
              "kind": "TIP",
              "text": "Folia nie pozwala mięsu się porwać i pryskać po kuchni."
            },
            "timer": null,
            "during": "t-butter",
            "scaleNote": null
          },
          {
            "id": "s3",
            "phase": "PREP",
            "stage": "W MIĘDZYCZASIE",
            "title": "Obierz i nastaw ziemniaki",
            "body": "Większe ziemniaki przekrój na pół, żeby wszystkie ugotowały się w tym samym czasie. Zalej je zimną wodą tak, by były przykryte, posól i postaw na dużym ogniu. Gdy woda zawrze, zmniejsz ogień do średniego i włącz odliczanie.",
            "ingredients": [
              {
                "ingredientId": "00000000-0000-4000-8000-000000000008",
                "amount": 500,
                "unit": "g",
                "part": "ALL"
              },
              {
                "ingredientId": "00000000-0000-4000-8000-000000000011",
                "amount": 1.5,
                "unit": "g",
                "part": "PART"
              }
            ],
            "mentions": [],
            "note": null,
            "timer": {
              "id": "t-potatoes",
              "label": "Ziemniaki",
              "minSeconds": 1200,
              "maxSeconds": 1200,
              "trigger": "EVENT",
              "startLabel": "Gdy woda zawrze",
              "alert": {
                "title": "Ziemniaki gotowe?",
                "body": "Nóż ma wchodzić bez oporu."
              }
            },
            "during": "t-butter",
            "scaleNote": {
              "fromPortions": 5,
              "text": "Przy tylu porcjach weź największy garnek — woda ma przykryć ziemniaki."
            }
          },
          {
            "id": "s4",
            "phase": "PREP",
            "stage": "W MIĘDZYCZASIE",
            "title": "Przygotuj panierkę",
            "body": "Do pierwszego talerza wsyp mąkę, w drugim roztrzep jajko widelcem, do trzeciego wsyp bułkę tartą. Ustaw je w rzędzie w tej kolejności — przyda się to przy podwójnej panierce.",
            "ingredients": [
              {
                "ingredientId": "00000000-0000-4000-8000-000000000005",
                "amount": 20,
                "unit": "g",
                "part": "ALL"
              },
              {
                "ingredientId": "00000000-0000-4000-8000-000000000004",
                "amount": 1,
                "unit": "szt",
                "part": "ALL"
              },
              {
                "ingredientId": "00000000-0000-4000-8000-000000000006",
                "amount": 50,
                "unit": "g",
                "part": "ALL"
              }
            ],
            "mentions": [],
            "note": null,
            "timer": null,
            "during": "t-butter",
            "scaleNote": null
          },
          {
            "id": "s5",
            "phase": "COOK",
            "stage": null,
            "title": "Nagrzej piekarnik do 180°C",
            "body": "Ustaw grzanie góra–dół, bez termoobiegu. Nagrzeje się, zanim usmażysz kotlety.",
            "ingredients": [],
            "mentions": [],
            "note": null,
            "timer": null,
            "during": null,
            "scaleNote": null
          },
          {
            "id": "s6",
            "phase": "PREP",
            "stage": null,
            "title": "Zawiń kotlety z masłem",
            "body": "Wyjmij wałeczki z zamrażarki. Każdy połóż na krótszym brzegu kotleta. Zawiń raz, załóż boki kotleta do środka, jak przy naleśniku z nadzieniem, i zwijaj dalej ciasno do końca. Łączeniem do dołu — tak roladka się nie rozwinie.",
            "ingredients": [],
            "mentions": [
              "00000000-0000-4000-8000-000000000002",
              "00000000-0000-4000-8000-000000000001"
            ],
            "note": {
              "kind": "CUE",
              "text": "Z żadnej strony nie widać masła. Jeśli widać — dociśnij mięso palcami."
            },
            "timer": null,
            "during": null,
            "scaleNote": null
          },
          {
            "id": "s7",
            "phase": "PREP",
            "stage": null,
            "title": "Obtocz roladki podwójnie",
            "body": "Każdą roladkę obtocz kolejno w mące, jajku i bułce tartej, a potem jeszcze raz w jajku i bułce. Dociśnij panierkę dłońmi. Druga warstwa to zabezpieczenie — trzyma masło w środku podczas smażenia.",
            "ingredients": [],
            "mentions": [
              "00000000-0000-4000-8000-000000000005",
              "00000000-0000-4000-8000-000000000004",
              "00000000-0000-4000-8000-000000000006"
            ],
            "note": null,
            "timer": null,
            "during": null,
            "scaleNote": null
          },
          {
            "id": "s8",
            "phase": "COOK",
            "stage": "SMAŻENIE",
            "title": "Smaż kotlety na złoto",
            "body": "Rozgrzej olej na patelni na średnim ogniu — jest gotowy, gdy okruch bułki od razu zaczyna skwierczeć. Połóż kotlety łączeniem do dołu, żeby się zasklepiły. Obracaj co 3 minuty, aż będą złote ze wszystkich stron.",
            "ingredients": [
              {
                "ingredientId": "00000000-0000-4000-8000-000000000007",
                "amount": 30,
                "unit": "ml",
                "part": "ALL"
              }
            ],
            "mentions": [],
            "note": {
              "kind": "WARNING",
              "text": "Olej pryska — kładź kotlety od siebie."
            },
            "timer": {
              "id": "t-cutlets",
              "label": "Kotlety",
              "minSeconds": 600,
              "maxSeconds": 720,
              "trigger": "NOW",
              "startLabel": "Kotlety na patelni",
              "alert": {
                "title": "Sprawdź kolor",
                "body": "Blade? Dosmaż jeszcze chwilę."
              }
            },
            "during": null,
            "scaleNote": {
              "fromPortions": 4,
              "text": "Smaż w dwóch turach — ciasna patelnia gotuje zamiast smażyć."
            }
          },
          {
            "id": "s9",
            "phase": "COOK",
            "stage": null,
            "title": "Dopiecz w piekarniku",
            "body": "Przełóż je do naczynia żaroodpornego albo na blachę i wstaw na środkową półkę.",
            "ingredients": [],
            "mentions": [
              "00000000-0000-4000-8000-000000000001"
            ],
            "note": {
              "kind": "CUE",
              "text": "W środku 74°C albo po nakłuciu wypływa przezroczysty sok, bez różowego."
            },
            "timer": {
              "id": "t-oven",
              "label": "Kotlety",
              "minSeconds": 300,
              "maxSeconds": 300,
              "trigger": "NOW",
              "startLabel": "W piekarniku",
              "alert": {
                "title": "Kotlety gotowe",
                "body": "Wyjmij je z piekarnika."
              }
            },
            "during": null,
            "scaleNote": null
          },
          {
            "id": "s10",
            "phase": "PREP",
            "stage": "W MIĘDZYCZASIE",
            "title": "Zrób mizerię",
            "body": "Pokrój ogórek w cienkie plasterki, posól i odstaw na chwilę. Odciśnij wodę dłońmi — mizeria nie będzie wodnista. Wymieszaj ze śmietaną i pieprzem.",
            "ingredients": [
              {
                "ingredientId": "00000000-0000-4000-8000-000000000009",
                "amount": 250,
                "unit": "g",
                "part": "ALL"
              },
              {
                "ingredientId": "00000000-0000-4000-8000-000000000011",
                "amount": 0.5,
                "unit": "g",
                "part": "REST"
              },
              {
                "ingredientId": "00000000-0000-4000-8000-000000000010",
                "amount": 60,
                "unit": "g",
                "part": "ALL"
              },
              {
                "ingredientId": "00000000-0000-4000-8000-000000000012",
                "amount": 0.5,
                "unit": "g",
                "part": "REST"
              }
            ],
            "mentions": [],
            "note": null,
            "timer": null,
            "during": "t-oven",
            "scaleNote": null
          },
          {
            "id": "s11",
            "phase": "FINISH",
            "stage": null,
            "title": "Odcedź ziemniaki",
            "body": "Postaw garnek na chwilę na gorącej płycie bez pokrywki, żeby odparowały, i posyp resztą koperku.",
            "ingredients": [
              {
                "ingredientId": "00000000-0000-4000-8000-000000000003",
                "amount": 5,
                "unit": "g",
                "part": "REST"
              }
            ],
            "mentions": [],
            "note": null,
            "timer": null,
            "during": null,
            "scaleNote": null
          },
          {
            "id": "s12",
            "phase": "SERVE",
            "stage": null,
            "title": "Podaj",
            "body": "Na talerz połóż kotlet, ziemniaki i mizerię.",
            "ingredients": [],
            "mentions": [],
            "note": {
              "kind": "WARNING",
              "text": "Kotlet przekrój dopiero na talerzu i ostrożnie — ze środka wypłynie gorące masło."
            },
            "timer": null,
            "during": null,
            "scaleNote": null
          }
        ]
      }
    }
  },
  "recipeIngredients": [
    {
      "ingredientId": "00000000-0000-4000-8000-000000000001",
      "name": "Filet z kurczaka",
      "amount": 320,
      "unit": "g",
      "department": "Mięso",
      "kitchenMeasure": null
    },
    {
      "ingredientId": "00000000-0000-4000-8000-000000000002",
      "name": "Masło",
      "amount": 30,
      "unit": "g",
      "department": "Nabiał i jajko",
      "kitchenMeasure": null
    },
    {
      "ingredientId": "00000000-0000-4000-8000-000000000003",
      "name": "Koperek",
      "amount": 10,
      "unit": "g",
      "department": "Warzywa",
      "kitchenMeasure": null
    },
    {
      "ingredientId": "00000000-0000-4000-8000-000000000004",
      "name": "Jajko",
      "amount": 1,
      "unit": "szt",
      "department": "Nabiał i jajko",
      "kitchenMeasure": null
    },
    {
      "ingredientId": "00000000-0000-4000-8000-000000000005",
      "name": "Mąka pszenna",
      "amount": 20,
      "unit": "g",
      "department": "Zboża i makarony",
      "kitchenMeasure": null
    },
    {
      "ingredientId": "00000000-0000-4000-8000-000000000006",
      "name": "Bułka tarta",
      "amount": 50,
      "unit": "g",
      "department": "Piekarnia",
      "kitchenMeasure": null
    },
    {
      "ingredientId": "00000000-0000-4000-8000-000000000007",
      "name": "Olej rzepakowy",
      "amount": 30,
      "unit": "ml",
      "department": "Olej i tłuszcz",
      "kitchenMeasure": null
    },
    {
      "ingredientId": "00000000-0000-4000-8000-000000000008",
      "name": "Ziemniak",
      "amount": 500,
      "unit": "g",
      "department": "Warzywa",
      "kitchenMeasure": null
    },
    {
      "ingredientId": "00000000-0000-4000-8000-000000000009",
      "name": "Ogórek",
      "amount": 250,
      "unit": "g",
      "department": "Warzywa",
      "kitchenMeasure": null
    },
    {
      "ingredientId": "00000000-0000-4000-8000-000000000010",
      "name": "Śmietana 12",
      "amount": 60,
      "unit": "g",
      "department": "Nabiał i jajko",
      "kitchenMeasure": null
    },
    {
      "ingredientId": "00000000-0000-4000-8000-000000000011",
      "name": "Sól",
      "amount": 3,
      "unit": "g",
      "department": "Przyprawy i sosy",
      "kitchenMeasure": {
        "kind": "spoon",
        "per": 6
      }
    },
    {
      "ingredientId": "00000000-0000-4000-8000-000000000012",
      "name": "Pieprz czarny",
      "amount": 1,
      "unit": "g",
      "department": "Przyprawy i sosy",
      "kitchenMeasure": {
        "kind": "spoon",
        "per": 2.3
      }
    }
  ]
}
"""#
}
#endif
