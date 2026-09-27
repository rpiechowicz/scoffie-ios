# iOS: incremental catalog sync + porcje per osoba — raport

Data: 2026-09-27
Gałąź: `feature/catalog-sync-per-user-portions` (świeża z `main` @ `017ecb3`; stare gałęzie NIE zmergowane)
Backend: PR N2-1 https://github.com/rpiechowicz/scoffie-backend/pull/208 (`fix/catalog-change-commit-order` → `develop`, nie zmergowany)
Kontrakty czytane z `scoffie-backend` `origin/develop` @ `31044a4`.
Live API: 0 wywołań. Railway, flagi, GitHub Actions — nietknięte.

**Status kompilacji: NIESKOMPILOWANE.** Na tej maszynie (Windows) nie ma Xcode/swiftc. Sprawdzone: składnia
tree-sitterem (235 plików, 0 błędów), liczby i format na drucie — równoważnikiem w Pythonie. Dwa sprawdziany
czekają na macOS: `sh Scripts/catalog-sync-check.sh`, `sh Scripts/plan-portions-check.sh`. Przed mergem: build
Xcode + oba sprawdziany + przejście ręczne z listy na końcu.

## ETAP B — stare gałęzie: klasyfikacja

`main` ma drzewo identyczne z bazą obu starych gałęzi (`4a1288c`, `git diff` pusty) — obie to pojedyncze commity
(moje, 26.09), nic z nich nie jest na `main`. Portowane selektywnie, nie mergowane.

### `claude/catalog-sync` (`120b7c7`)

| Zmiana | Werdykt | Co zrobione |
|---|---|---|
| `BackendCatalogSyncDTOs.swift` | nadal potrzebna | 1:1 — pola zgodne z `CatalogSnapshotPage`/`CatalogChangesPage` |
| `WebSocketRecipeTransportClient`: `catalog:snapshot`, `catalog:changes`, `recipes:householdState` | nadal potrzebna | 1:1 — `revision`/`untilRevision`/`cursor` POMIJANE, gdy `nil` (serwer: `null` = RESET_REQUIRED `UNKNOWN_REVISION`) |
| `CatalogSyncApplier.swift` (stan + bufor) | wymaga adaptacji | → `CatalogSync.swift`: silnik przebiegu na kopii stanu, walidacja rewizji stron, kursor w miejscu, anulowanie, limit stron |
| `RecipeProtocols` / `ApiRecipeRepository` | wymaga adaptacji | strony generyczne; klucz = id małymi literami; kopia katalogu bez serca (plik publiczny przeżywa wylogowanie) |
| `RecipeCatalogStore` | wymaga adaptacji | jeden plik bez wersji → koperta z wersją; brak powiązania z kontem → osobny plik domu z właścicielem; stara droga `recipes:findAll` przy KAŻDYM błędzie → tylko brak ACK / 503; ponawianie 3× na 3× socketu (do ~54 s) → tylko 429; RESET nie zapisywany → zapisywany; `loadRecipeDetail` bez zapisu → zapis do właściwej części; wylogowanie kasowało katalog → tylko stan domu |
| `Scripts/CatalogSync` + `catalog-sync-check.sh` | wymaga adaptacji | 38 scenariuszy na silniku z serwerem na niby |

### `claude/per-user-portions` (`afffa44`)

| Zmiana | Werdykt | Co zrobione |
|---|---|---|
| `PlanMeal.portions: [String: Double]` | wymaga adaptacji | `portionUnits: [String: Int]` — jednostki 1/20 jak w bazie, bez drugiego zaokrąglania |
| `portion(for:)`, `servingsPerPerson/nutritionPerPerson(memberId:)`, `isCustomServings` | nadal potrzebna | port; reguły jak serwer (brak wpisu = 1,00; bez osoby = średnia) |
| `MealCalendarStore` `keptPortions` | **odrzucić** | gubił alokację przy zmianie audytorium, podmianie dania i stepperze — dokładnie to, czego nie wolno; zastąpione `PlanPortions.forWrite` |
| `WeeklyPlanStore` DTO + wysyłka `portions` | wymaga adaptacji | jednostki ↔ porcje; DTO 1:1 |
| kcal osoby: Asystent, Kalendarz, `PlanDayNutrition`, `PlanDayTimeline`, `WeeklyPlanView`, przypomnienia (`SessionStore`) | nadal potrzebna | `git apply` hunków bez konfliktu (sygnatury zachowane) |
| `PLAN_PORTIONS_INVALID` w `UserFacingErrorMapper` | nadal potrzebna | 1:1 |
| `Scripts/PlanPortions` (kompilował `RecipesModel` + `SavedMealPlan` + `PlanDayNutrition`) | przestarzała | nowy sprawdzian na czystym `PlanPortions.swift` |

## ETAP C — catalog sync

Kontrakt (backend = źródło prawdy): `catalog:snapshot {revision?, cursor?, limit≤500}` → `{mode:'SNAPSHOT', revision,
items, nextCursor}`; `catalog:changes {sinceRevision, untilRevision?, cursor?, limit≤500}` → `{mode:'DELTA',
fromRevision, revision, upserts, tombstones: string[], nextCursor}`; `RESET_REQUIRED` przychodzi w `ok:true`
(`UNKNOWN_REVISION` / `REVISION_PRUNED` / `FUTURE_REVISION`); rewizja `<epoka>.<numer>` nieprzezroczysta;
`nextCursor: null` = ostatnia strona; przepisy domu i ulubione osobno (`recipes:householdState`); brak push dla
katalogu (delta przy starcie, foreground, reconnect). Limit 120 zapytań/min na użytkownika.

Przepływ (`RecipeCatalogStore` + `CatalogSyncEngine`):
1. brak ważnego pliku → `catalog:snapshot` stronami po 500 do końca; rewizja z 1. strony odsyłana na kolejnych;
2. jest plik z rewizją → `catalog:changes(since)`; `untilRevision` = rewizja 1. strony; upserty + tombstone'y;
3. `RESET_REQUIRED` → rewizja znika (w pamięci i w pliku), stary katalog NIE jest naprawiany, zostaje na ekranie do
   końca snapshotu, snapshot od zera, atomowa podmiana.

**Atomowość.** Przebieg pracuje na KOPII stanu (wartość), nowy stan wraca dopiero po ostatniej stronie. Podmiana
= stan w pamięci + plik (katalog i rewizja w jednym pliku, `write(.atomic)` = plik tymczasowy + rename). Na dysku
jest zawsze albo stary komplet, albo nowy — nigdy pół snapshotu z rewizją końca.

| Przypadek | Obsługa |
|---|---|
| paginacja snapshotu / delty | pętla do `nextCursor == nil`; strony z inną rewizją = przebieg odrzucony; kursor w miejscu = przerwane; bezpiecznik 10 000 stron |
| `untilRevision`, `nextCursor` | z 1. strony delty; klucze pomijane, nie `null` |
| tombstones | usuwają też nieznane id; wiersz niemapowalny w delcie = tombstone |
| reconnect | debounce 300 ms → delta (zwykle pusta, 1 zapytanie) |
| przerwany sync / zabita aplikacja między stronami | nic nie podmienione; następny start od tej samej rewizji |
| duplikaty dostawy | upsert po id, idempotentne (sprawdzian) |
| uszkodzony plik | `.corrupted` (ucięty JSON, id bez przepisu, pusta rewizja) → plik usunięty, snapshot |
| stary format | wersja W pliku; v12 bez wersji → rozpoznany, pokazany tylko w pamięci do 1. snapshotu, potem usunięty |
| logout / login | wylogowanie kasuje stan domu (+ stare pliki); publiczny katalog zostaje → po zalogowaniu delta |
| zmiana konta / domu | plik domu z właścicielem `userId_householdId`; obcy ignorowany |
| brak sieci / 500 | działający katalog zostaje, komunikat inline |
| stary backend | tylko brak ACK (po 3 próbach socketu) albo `SERVICE_UNAVAILABLE` → `recipes:findAll` do końca (tylko w pamięci) |
| 429 | 2 ponowienia (2 s, 4 s); resztę ponawia socket |
| anulowanie | `CancellationError`, bez podmiany |

Rozróżnienie stanów: ważny stary katalog + offline = pokazany, rewizja zostaje; uszkodzony = snapshot (katalog
pusty, jeśli nie ma v12); RESET_REQUIRED = katalog pokazany, rewizja skasowana, snapshot.

## ETAP D — porcje per osoba

Kontrakt: `PlanItem.portions: [{userId, servings}]` — ZAWSZE w odpowiedzi (puste = bez alokacji), `servings`
wielokrotność 0,05, 0,1…6 na osobę, Σ ≤ 12, klucze = dokładnie audytorium („Wspólne” = cały dom);
`plannedServings = ceil(Σ)`. Flaga `AI_PLANNER_PER_USER_PORTIONS` steruje TYLKO planerem — API zawsze przyjmuje
i oddaje `portions`. Na prod flaga `false` → alokacje dziś nie powstają; UI porcji uśpione do czasu włączenia.

**Najważniejsze: zapis pozycji bez `portions` KASUJE alokację** (także `[]`). Semantyka iOS (jedno miejsce:
`MealCalendarStore.upsertWeekSlot` → `PlanPortions.forWrite`):

| Działanie | Co idzie na serwer |
|---|---|
| edytor porcji w szczegółach (+/− jednej osoby) | PEŁNA alokacja z jedną zmianą |
| stepper porcji łącznych | pozycja bez alokacji: jak dotąd. Z alokacją stepper jest UKRYTY (zastąpiony edytorem) — jawne `plannedServings` = świadomy równy podział |
| zmiana „kto je” (`saveAudienceOnly`) | alokacja przeniesiona: zostający bez zmian, dochodzący 1,00 (reguła serwera przy dołączeniu do domu), odchodzący znika |
| zamiana dania („Zmień przepis”, `replaceRecipeId`) | porcje osób przechodzą na nowe danie (serwer ich NIE przenosi — decyzja klienta, patrz API GAP 2) |
| dołączenie do tego samego dania (AddToPlan, wybór w slocie) | jak zmiana „kto je” |
| „Wspólne” bez listy domowników | alokacja wspólnej pozycji = cały dom; gdy trzeba ją zmienić, a skład nie dojechał → zapis WSTRZYMANY z komunikatem (zamiast cichego skasowania) |
| usunięcie dania / dnia / tygodnia | bez zmian (kaskada na serwerze) |
| odhaczenie „zjedzone” | bez zmian (serwer nie rusza porcji, iOS edytuje w miejscu) |
| kopiowanie / przenoszenie slotu | w iOS nie istnieje (backend też nie ma takich zdarzeń) |
| potwierdzenie zapisu / odświeżenie tygodnia / `weekChanged` | alokacja z serwera (prawda), mapowana na jednostki |

Legacy: brak `portions` (stary serwer, stary `meal_plans.json`) = równy podział jak dotąd; `isCustomServings` nie
dokleja „3 porcje” przy alokacji.

Kalorie: backend nie podaje kcal per pozycja per osoba (jest tylko bilans dnia `weeklyPlans:balance`), więc iOS
liczy TYM SAMYM wzorem co `daily-balance.util.ts`: porcja osoby / `max(1, recipe.servings)` × makra całego przepisu
(`Recipe.nutrition(forServings:)` — sprawdzone, identyczny). Karty Asystenta: kcal z serwera, bez zmian.

### BLOCKER / API GAP (backend)

1. **Brak kontroli wersji pozycji** (last-write-wins). Klient musi odsyłać pełną alokację; gdy inny telefon zmienił
   ją chwilę wcześniej (przed `weekChanged`), zapis ją nadpisze. Potrzebne: wersja/ETag pozycji w `upsertWeekSlot`
   albo zdarzenie „ustaw porcję jednej osoby”. Nie blokuje wydania (okno małe, flaga off), ale jest realne.
2. **Zamiana dania nie przelicza porcji** — serwer ich nie przenosi, a planer (`portionsForChoice`) nie jest
   wystawiony. iOS przenosi porcje osób 1:1; właściwe byłoby przeliczenie po stronie serwera.
3. **Narzędzia AI gubią alokacje** (`propose_week_plan` / `propose_day_plan` / `apply_week_plan` → `toSlots` nie
   przekazuje `portions`) — zastosowanie takiej propozycji kasuje porcje w przepisanych pozycjach. Błąd backendu,
   nie iOS; do naprawy przed włączeniem flagi.
4. OpenAPI `PlanPortionDto` bez min/max/multipleOf — generowany klient (Android) nie zna reguł 0,05 / 0,1–6 / Σ≤12.
5. Brak kcal per pozycja per osoba w payloadzie — iOS powiela wzór serwera (jedno źródło reguły, dwie
   implementacje).

## ETAP E — UI

- Szczegóły posiłku z alokacją: nagłówek „TWOJA PORCJA: 1,25” (albo „ŚREDNIO: …”, gdy patrzący nie je), karta z
  osobami „Rafał (Ty) 1,25”, „Asia 0,80” i stepperem co 0,05 (granice serwera), „Zapisz porcje” wysyła całość;
  makra z porcji patrzącego, składniki z Σ („2,05 porcji”). Bez alokacji — ekran jak dotąd.
- Wiersz planu / talerz kalendarza: kcal z porcji osoby; dopisek „porcja 1,25” tylko gdy ≠ 1,00.
- Liczby zawsze z dwoma miejscami i przecinkiem, bez „units=25”; zaokrąglenie = jednostki serwera (0,05).

## ETAP F — cache

| Plik | Zawartość | Wersja |
|---|---|---|
| `recipe_catalog.json` | `CatalogCacheEnvelope { version, revision?, ids, items, savedAt }` — publiczny katalog | `version` W pliku (`currentVersion = 1`) |
| `recipe_catalog_household.json` | `HouseholdRecipeCacheEnvelope { version, ownerKey, recipes, favoriteRecipeIds, savedAt }` | `version` + właściciel |
| `recipes_catalog_cache_v*.json` | stary format | czytany raz (tylko v12, ≤12 h, w pamięci), usuwany po 1. snapshocie i przy wylogowaniu |

Zmiana kształtu `Recipe` albo znaczenia pól = podbić `CatalogCacheEnvelope.currentVersion` (stary plik → snapshot).
Świeżość katalogu wyznacza rewizja, nie wiek pliku.

## Testy

| Co | Wynik |
|---|---|
| składnia (tree-sitter-swift) całego projektu | 235 plików, 0 błędów (2 duplikaty nazw typów — bez zmian względem `main`) |
| format na drucie porcji 0,10…6,00 (Python, IEEE) | `units/20` == wartość z napisu „x.xx” dla wszystkich 119 wartości |
| etykiety / `ceil(Σ)` (Python) | „1,25”, „0,80”, „0,10”, „6,00”; 0,80+1,25 → 3; max 12 |
| `sh Scripts/catalog-sync-check.sh` (38 scenariuszy) | **DEFERRED** — wymaga macOS |
| `sh Scripts/plan-portions-check.sh` (28 scenariuszy) | **DEFERRED** — wymaga macOS |
| build Xcode | **DEFERRED** — wymaga macOS |

Przejście ręczne przed mergem: pierwsze uruchomienie (snapshot), drugie (delta 1 zapytanie), edycja przepisu w
panelu → foreground → zmiana widoczna; wylogowanie → zalogowanie (delta, bez przepisów domu poprzedniego konta);
tryb samolotowy (katalog zostaje); z flagą porcji ON na stagingu: szczegóły „Twoja porcja”, edycja jednej osoby,
zmiana „kto je”, „Zmień przepis” — alokacja przetrwała (odświeżenie tygodnia).

## Rollout

1. Backend #208 (N2-1) → `develop` → prod — **przed** wydaniem tej wersji iOS.
2. iOS: build + sprawdziany na macOS, TestFlight.
3. Porcje per osoba: UI uśpione przy fladze off; przed włączeniem flagi — API GAP 3 (narzędzia AI).

Znane różnice: kolejność przepisów w katalogu = kolejność serwera (po `id`), nie „najnowsze pierwsze” jak w
`recipes:findAll` — ekrany sortujące same (sekcje Przepisów) bez zmian; ekrany polegające na kolejności tablicy do
sprawdzenia w przejściu ręcznym.
