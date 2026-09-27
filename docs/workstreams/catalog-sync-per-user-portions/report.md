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

## Addendum — review patch (2026-09-27)

Trzy poprawki, trzy commity. Backend N2-1 (#208) bez zmian. Nic nie zmergowane, nie wdrożone; Railway, flagi
i GitHub Actions nietknięte. **Kod Swift nadal NIESKOMPILOWANY** — patrz „Weryfikacja”.

Sekcje ETAP D (tabela „Działanie → co idzie na serwer”) i ETAP E (edytor porcji ze stepperami) powyżej są
**nieaktualne** — zastępuje je punkt 3 niżej.

### 1. Catalog sync — błędne mapowanie przesuwało rewizję (`767e87b`)

**Root cause** (odtworzone przeglądem kodu i odwzorowane w sprawdzianie — uruchomienie wymaga macOS):
`ApiRecipeRepository` robił `compactMap` na przepisach snapshotu (niemapowalny = pominięty) i zamieniał niemapowalny
upsert delty na tombstone; strona z brakującymi `items`/`upserts`/`tombstones` dawała `?? []`. Silnik kończył przebieg
i zapisywał nową rewizję, więc następna delta startowała ZA zmianą — przepis, którego serwer nie usunął (np.
`mealType` nieznany temu buildowi, id spoza UUID), znikał z telefonu do następnego snapshotu.

**Poprawka:**
- `Scoffie/Networking/Recipes/CatalogSyncMapping.swift` (nowy): jedyne miejsce DTO → strona. Każdy z tych przypadków
  rzuca `CatalogSyncResponseError` i odrzuca cały przebieg:
  - niemapowalny przepis (`unmappableRecipe`);
  - brak `items` / `upserts` / `tombstones` / `fromRevision` / klucza `nextCursor` (`missingField`);
  - tryb spoza zdarzenia: DELTA z `catalog:snapshot`, SNAPSHOT z `catalog:changes` (`unexpectedMode`);
  - pusta rewizja;
  - `fromRevision` ≠ żądane `sinceRevision`.

  Silnik składa stan na kopii, więc katalog i rewizja zostają bez zmian. Tombstone'y pochodzą wyłącznie z jawnego
  `tombstones` serwera. Brak heurystycznego pomijania.
- `BackendCatalogSyncDTOs.swift`: własny dekoder odróżnia `"nextCursor": null` (ostatnia strona) od braku klucza.
- `ApiRecipeRepository.swift`: snapshot i delta przez `CatalogSyncMapping` z `toAppRecipe()`.
- Poza zakresem (bez rewizji, bez zmian): `recipes:findAll` (stara droga) i `recipes:householdState` nadal pomijają
  niemapowalne przepisy — tam nie ma rewizji do przesunięcia.

**Testy** (`Scripts/CatalogSync/main.swift` §12, 17 asercji). Pełna ścieżka adaptera: JSON strony →
`BackendCatalog*PageDTO` → `CatalogSyncMapping` → `BackendRecipeDTO.toAppRecipe()` → silnik. Kompiluje prawdziwe
`MealSlot`, `RecipesModel`, `BackendRecipeDTOs`; zaślepka dotyczy tylko `AppEnvironment.apiBaseURL`. Scenariusze:
- nieznany `mealType` na 2. stronie snapshotu;
- id spoza UUID na ostatniej stronie;
- niemapowalny upsert na 2. stronie delty — NIE tombstone, stan i rewizja bez zmian;
- brak każdego wymaganego pola (6);
- zły tryb (2);
- obca `fromRevision`;
- ponowienie po poprawce serwera dostarcza odrzucony przepis;
- jawny tombstone usuwa.

### 2. Wylogowanie / zmiana konta — stara sesja nie odtwarza cache (`5841399`)

**Root cause:** chroniła tylko szeregowa kolejka zapisów. Scenariusz: zapytanie A startuje → wylogowanie kasuje
plik → odpowiedź A wraca do NIEunieważnionej instancji → ta publikuje wynik i dopisuje zapis do kolejki PO
kasowaniu. Efekt: prywatny stan domu A wracał na dysk. Po zmianie konta spóźniona odpowiedź A mogła nadpisać cache
B (publiczny katalog starszą rewizją).

**Poprawka:**
- `Scoffie/Models/Components/CatalogSyncCore.swift` (nowy, czysta logika):
  - `CatalogSyncCore` trzyma stan sesji i zapis; każde `await` kończy się `checkValid()`, a unieważniona sesja nic
    nie publikuje;
  - `CatalogCacheGate` pozwala pisać tylko aktywnemu tokenowi. Token jest sprawdzany pod zamkiem w chwili zapisu —
    także przy zapisie, który czekał w kolejce;
  - `activate` nowej sesji odbiera prawo zapisu poprzedniej.
- `RecipeCatalogStore` jako fasada:
  - `invalidate()` odbiera token i anuluje sync (przebieg biegnie w `reloadTask`, silnik sprawdza anulowanie między
    stronami), debounce'y oraz oczekujące zapisy serduszek;
  - callbacki starej sesji (serduszka, `recipes:changed`, reconnect) sprawdzają ważność.
- `SessionStore`: `invalidate()` przed zastąpieniem store'u nową sesją oraz przy wylogowaniu, PRZED kasowaniem
  prywatnego pliku.
- Polityka bez zmian: publiczny katalog przeżywa wylogowanie, plik domu znika.

**Testy** (§13, 17 asercji). Deterministyczne i bez sleepów: odpowiedź kończy `Controlled.resume`, start zapytania
potwierdza continuation, kolejkę zapisu da się wstrzymać (`suspend`) i opróżnić (`flush`). Sprawdzany jest stan
w pamięci i zawartość plików:
- 13a: A → wylogowanie → odpowiedź A.
- 13b: A → przełączenie na B → odpowiedź B → spóźniona odpowiedź A (delta i dom): pliki = B, rewizja B.
- 13c: zapis czekający w kolejce przy unieważnieniu oraz przy przejęciu przez nową sesję.
- 13d: ponowne logowanie na to samo konto.

### 3. Porcje per osoba — edycja zablokowana, API GAP (`0fc58ff`)

**Root cause:** `upsertWeekSlot` / `applyWeekPlan` na serwerze przy każdym zapisie pozycji zastępują CAŁĄ alokację
(`portions: { deleteMany: {}, create }`), a brak pola ją kasuje. Nie ma wersji ani CAS. Pełna alokacja odesłana
ze starej kopii cofa zmianę innego telefonu:
1. A i B czytają plan.
2. A zapisuje porcję Rafała.
3. B zapisuje porcję Asi ze starą porcją Rafała.
4. Zmiana A znika.

„Odśwież tuż przed zapisem” okna nie zamyka, więc nie zostało użyte.

**Poprawka:**
- iOS nie wysyła pola `portions` (usunięte z `WeeklyPlanRepository` i transportu). *Korekta (addendum 2): to NIE
  czyni zapisu bezpiecznym — zapis bez `portions` serwer traktuje jako skasowanie alokacji, więc pozycja z alokacją
  nieznaną telefonowi nadal może ją stracić.*
- `PlanPortions.upsertDecision`: zapis, który dotyka pozycji z alokacją, jest odrzucany PRZED zapisem
  optymistycznym i przed repozytorium. Pozycja dotknięta to ten sam przepis w slocie (serwer ją przepisuje) albo
  danie podmieniane (serwer je usuwa). Użytkownik dostaje `editBlockedMessage` przez toast
  (`ScoffieApp .scErrorToast`) i w arkuszu wyboru.
- Szczegóły posiłku z alokacją: „Twoja porcja: 1,25”, lista osób z porcjami i makra z porcji patrzącego — bez
  stepperów. Pod listą krótki komunikat, a „Zapisz porcje” jest nieaktywne.

**Dokładne ograniczenia** (pozycja z alokacją = `portions` niepuste):

| Ścieżka | Zachowanie |
|---|---|
| edytor jednej osoby | usunięty (porcje tylko do odczytu) |
| zmiana „kto je” (`PlanSlotPickerSheet.saveAudienceOnly`) | zablokowana, komunikat |
| zamiana przepisu z porcjami na inny, także na ten sam | zablokowana, komunikat |
| zamiana dania bez porcji na danie, które w slocie ma porcje | zablokowana (przepisałaby tamtą pozycję) |
| dołączenie do istniejącej pozycji (AddToPlan, wybór w slocie) | zablokowane, komunikat |
| stepper porcji łącznych | ukryty w szczegółach; gdyby zapis przyszedł — zablokowany |
| nowe danie obok dania z porcjami (inna pozycja) | działa |
| usunięcie dania / dnia / tygodnia, „zjedzone” | działa (nie przepisuje alokacji) |
| pozycje bez alokacji (legacy) | działa jak dotąd, równy podział |
| odczyt: kcal osoby, „porcja 1,25”, potwierdzenia, `weekChanged` | działa |

**Testy:**
- `Scripts/PlanPortions/main.swift`, 20 asercji: tabela decyzji (5 zablokowanych, 5 przepuszczonych, w tym legacy),
  jednostki, etykiety i komunikat.
- `plan-portions-check.sh` ma regresję statyczną: zapis planu nie zawiera `"portions"`. Na starym kodzie (`2f9690b`)
  wykrywa `data["portions"]` — sprawdzone.

### Backend API GAP — porcje per osoba

**Stan dziś:**
- `PlanItem` nie ma wersji.
- `upsertWeekSlot` zastępuje całą alokację albo kasuje ją, gdy pola brak (także `[]`).
- `replaceRecipeId` usuwa pozycję razem z porcjami.
- `applyWeekPlan` przy slocie bez `portions` kasuje alokację.
- Narzędzia AI (`toSlots`) porcji nie przekazują.

**Opcja A — kontrola wersji (CAS) zapisu pozycji:**
- `PlanItem.version Int` (albo `updatedAt` jako token), zwracane w każdym payloadzie pozycji.
- `upsertWeekSlot` przyjmuje `expectedVersion`, a `applyWeekPlan` `slots[].expectedVersion`.
- Niezgodność → `409 PLAN_ITEM_CONFLICT` z aktualną pozycją. Nic się nie zapisuje.
- Zapis bez `expectedVersion` na pozycji z alokacją → 409 (albo 428), nie ciche nadpisanie.

**Opcja B — atomowa zmiana porcji jednej osoby:**
- `weeklyPlans:setPortion { weekStart, dayOfWeek, mealType, recipeId, userId, servings, expectedVersion? }`.
- Jedna transakcja pod zamkiem tygodnia: `UPDATE` jednego `PlanItemPortion`, `plannedServings = ceil(Σ)`,
  broadcast `weekChanged`.
- Porcje innych osób nietknięte, więc A i B zmieniające RÓŻNE osoby nie kolidują.

**Zachowanie przy konflikcie i brzegach:**
- Konflikt wersji → 409 z bieżącym stanem, klient pokazuje go i prosi o ponowienie.
- Zmiana audytorium: serwer sam przenosi alokację w tej samej transakcji (zostający bez zmian, dochodzący 1,00,
  odchodzący usunięci — reguła, którą już stosuje przy zmianie składu domu) i przyjmuje `expectedVersion`.
- Zamiana dania: jawny parametr `portionPolicy: KEEP | RESET | PLANNER` zamiast cichego kasowania.
- Przekroczenie Σ > 12 albo porcja spoza 0,1–6 → `PLAN_PORTIONS_INVALID` z `details`, bez obcinania.

**Rekomendacja:** B dla edytora (brak konfliktów przy różnych osobach) + A na wszystkich zapisach pozycji (audytorium,
zamiana, stepper, `applyWeekPlan`, apply propozycji Asystenta). Do tego naprawa `toSlots`, żeby narzędzia AI
zachowywały porcje, i ograniczenia `PlanPortionDto` w OpenAPI (min/max/multipleOf).

**Kryteria odblokowania edycji iOS:**
1. Wersja pozycji w payloadach i `expectedVersion` na każdym zapisie pozycji. E2E z dwoma równoległymi zapisami:
   brak utraconej zmiany i 409 dla spóźnionego.
2. `setPortion` (albo równoważne) z e2e „A zmienia Rafała, B zmienia Asię → obie zmiany zostają”.
3. Zmiana audytorium i zamiana dania zachowują porcje po stronie serwera (e2e).
4. Narzędzia AI nie gubią porcji (e2e).
5. Po stronie iOS: obsługa 409 (odświeżenie + komunikat) i sprawdzian na macOS.

### Weryfikacja

| Kontrola | Wynik |
|---|---|
| `sh Scripts/catalog-sync-check.sh` | **BLOCKED / NOT RUN** — brak macOS (Xcode/swiftc) |
| `sh Scripts/plan-portions-check.sh` | **BLOCKED / NOT RUN** — brak macOS. Uruchomiona tylko jego część powłokowa (regresja statyczna): OK; na starym kodzie — wykrycie |
| build / typecheck Xcode z ustawieniami projektu | **BLOCKED / NOT RUN** — brak macOS |
| pomocniczo (NIE zastępuje powyższych): parser składni tree-sitter | 237 plików, 0 błędów składni; nie sprawdza typów ani semantyki |

Liczby z Pythona w sekcji „Testy” wyżej były pomocnicze; nie zastępują wyników Swift.

### SHA

| Commit | Opis |
|---|---|
| `767e87b` | fix: niemapowalny przepis odrzuca przebieg sync zamiast przesuwać rewizję |
| `5841399` | fix: sesja katalogu z cyklem życia — spóźniona odpowiedź nie odtwarza cache |
| `0fc58ff` | fix: porcje per osoba tylko do odczytu — zapis bez kontroli wersji zablokowany |
| (ten commit) | docs: addendum |

### Gotowość (osobno)

- **Catalog sync — NOT READY.** Kod po poprawkach 1–2 kompletny, ale nieskompilowany. Nieuruchomione: sprawdzian,
  build i przejście ręczne. Warunek wstępny: backend #208 na prod.
- **Odczyt porcji — NOT READY.** Logika i UI tylko do odczytu gotowe, nieskompilowane. Na prod flaga planera jest
  off, więc alokacje dziś nie powstają.
- **Edycja porcji — BLOCKED (API GAP).** Świadomie wyłączona do czasu spełnienia kryteriów odblokowania.

Nie deklaruję READY do merge'a: wymagane kontrole na macOS nie zostały wykonane.

## Addendum 2 — review patch (2026-09-27)

Backend, N2-1, Railway i flagi nietknięte; nic nie zmergowane. **Build i sprawdziany Swift: NOT RUN — do ręcznej
weryfikacji na macOS** (lista poleceń niżej). Nie deklaruję, że przeszły.

### Co zmieniono

- **`23d43e8`** — `RecipeCatalogStore.reload()`: `Task<Void, Never> { [weak self] in guard let self … }` zamiast
  `Task { [weak self] in await self?.performReload() }`. Tamta forma wyprowadzała `Task<Void?, Never>`, niezgodny
  z polem `reloadTask`. Przejrzane pozostałe przechowywane zadania (`pendingRealtimeReloadTask`,
  `pendingHouseholdRefreshTask`, `pendingFavoriteTasks`): mają ciała wielowyrażeniowe, więc typ jest `Void` — bez
  zmian. Nieprzechowywane `Task { … }` nie tworzą konfliktu typu — bez zmian (bez refactoru).
- **`321074f`** — komentarze (`PlanPortions`, `MealCalendarStore`, `WeeklyPlanStore`) rozdzielają trzy rzeczy:
  gwarancję klienta, pozostały race i warunek serwera (poniżej).
- **`de04177`** — test granicy store → repozytorium: prawdziwy `MealCalendarStore` i atrapa `WeeklyPlanRepository`
  zapisująca wywołania. Szczegóły w „Testy”.
- Korekta w addendum wyżej: zdanie „niebezpiecznego zapytania nie da się zbudować” było nieprawdziwe i zostało
  poprawione. Zapis BEZ `portions` też jest niebezpieczny — serwer kasuje wtedy alokację.

### Zakres gwarancji lokalnej blokady

1. **Zabezpieczenie klienta — dotyczy tylko alokacji ZNANYCH telefonowi.** Zapis pozycji, która według lokalnego
   stanu ma alokację (to samo danie w slocie albo danie podmieniane), nie wychodzi z telefonu: `false`, zero zapytań,
   bez zmiany optymistycznej. iOS nigdy nie wysyła `portions`.
2. **Pozostały race przy nieaktualnym stanie — NIE zamknięty.**
   1. Telefon ma pozycję bez alokacji.
   2. Serwer (planer, inny klient, narzędzie Asystenta) dodaje alokację.
   3. Telefon nie dostał jeszcze `weekChanged` ani odświeżenia.
   4. Zwykły zapis pozycji (zmiana „kto je”, stepper, zamiana dania) idzie bez `portions`, a serwer **kasuje**
      alokację i wraca do równego podziału.

   Usunięcie `portions` z transportu tego nie chroni — właśnie brak pola powoduje kasowanie. Odświeżenie tuż przed
   zapisem też nie: alokacja może powstać między odczytem a zapisem.
3. **Wymagane zabezpieczenie backendowe przed uruchomieniem alokacji** (poniżej). Flaga
   `AI_PLANNER_PER_USER_PORTIONS=false` NIE jest kontrolą dostępu do zapisów alokacji. API przyjmuje i zapisuje
   `portions` niezależnie od flagi — flaga steruje tylko planerem.

### Backend API GAP — warunek przed uruchomieniem alokacji

- **Atomowość:** odczyt bieżącego stanu pozycji (czy ma alokację, w jakiej wersji) i decyzja o zapisie muszą zapaść
  w TEJ SAMEJ transakcji. Dziś zapisy planu i tak biorą `lockWeekForWrite` na początku transakcji.
- **Legacy upsert nie może niejawnie kasować alokacji:** `upsertWeekSlot` bez `portions` na pozycji, która ma
  alokację, kończy się odmową (albo jawną polityką), nie `deleteMany`.
- **To samo dotyczy każdej operacji przepisującej pozycję:**
  - `replaceRecipeId` (usuwa pozycję z porcjami);
  - `applyWeekPlan` (slot bez `portions` na pozycji z alokacją = naruszenie, `applied:false`);
  - apply i undo propozycji Asystenta;
  - narzędzia AI (`toSlots` gubi porcje).
- **Odpowiedź konfliktu:** `409` z kodem np. `PLAN_PORTIONS_CONFLICT`, `details: [planItemId]` i bieżącym stanem
  pozycji (z `portions` i wersją). Nic się nie zapisuje i nie ma broadcastu. W `applyWeekPlan` —
  `violations[{ index, code: 'PLAN_PORTIONS_CONFLICT' }]`, nic się nie zapisuje. Klient pokazuje komunikat
  i odświeża tydzień.
- **Kontrola wersji / pojedyncza porcja:** bez zmian względem addendum 1 (opcje A: `expectedVersion`,
  B: `setPortion`). Dopiero z nimi można odblokować edycję porcji w iOS.

**Wymagany test backendowy (e2e na żywej bazie, zatrzaski jak w `catalog-change-commit-order.e2e`):**
1. Pozycja bez alokacji.
2. Klient A czyta tydzień (brak porcji).
3. Transakcja B ustawia alokację i trzyma zamek tygodnia.
4. A wysyła `upsertWeekSlot` bez `portions` (zmiana audytorium) i czeka na zamek.
5. B commituje.

Oczekiwane: A dostaje `409 PLAN_PORTIONS_CONFLICT`, alokacja B nietknięta, `plannedServings` bez zmian, brak
broadcastu od A.

Warianty:
- to samo dla `replaceRecipeId` i dla `applyWeekPlan` (naruszenie, `applied:false`);
- wariant sekwencyjny: B commituje przed wysłaniem A — ten sam wynik;
- kontrola: A na pozycji, która alokacji nie ma — zapis przechodzi jak dziś.

### Testy

| Kontrola | Status |
|---|---|
| Powłokowa część `plan-portions-check.sh` (regresja „zapis bez `"portions"`”) | uruchomiona: OK (bez zmian od addendum 1) |
| `sh Scripts/catalog-sync-check.sh` | **NOT RUN** — przygotowane, do weryfikacji na macOS |
| `sh Scripts/plan-portions-check.sh` (część Swift) | **NOT RUN** — przygotowane, do weryfikacji na macOS |
| `sh Scripts/plan-store-check.sh` (nowy, 21 asercji) | **NOT RUN** — przygotowane, do weryfikacji na macOS |
| build Xcode | **NOT RUN** — do weryfikacji na macOS |
| pomocniczo (nie zastępuje powyższych): składnia tree-sitter | 0 błędów w zmienionych plikach |

`plan-store-check.sh` kompiluje prawdziwy `MealCalendarStore.swift` z domknięciem zależności: 22 pliki, bez
`ScoffieApp.swift`. Zaślepki są dwie: `AppEnvironment.apiBaseURL` oraz kolory `scCanvas`/`scLabel` z podglądu
w `PolishPlural.swift` (`SCDesignSystem` jest na UIKit). Scenariusze:
- 1a–c: pozycja ze znaną alokacją — kto je / stepper / ponowny zapis → `false`, zero zapytań, slot bez zmian,
  komunikat;
- 2: zamiana dania z alokacją → zero zapytań;
- 3: zamiana na danie z alokacją → zero zapytań;
- 4: nowe danie obok → dokładnie jedno zapytanie o oczekiwanych polach, sąsiednia alokacja nietknięta;
- 5a–c: legacy (kto je / stepper / zamiana) → jedno zapytanie, dotychczasowy wpis optymistyczny.

Program odmawia startu, jeśli Documents nie leży w katalogu z `CFFIXED_USER_HOME` — store pisze do Documents
i przy starcie kasuje `saved_plan.json`.

### Polecenia dla Rafała (macOS, katalog `scoffie-ios`)

```sh
git fetch origin && git checkout feature/catalog-sync-per-user-portions && git pull --ff-only
sh Scripts/catalog-sync-check.sh
sh Scripts/plan-portions-check.sh
sh Scripts/plan-store-check.sh
xcodebuild -project "Scoffie.xcodeproj" -scheme "Scoffie" -destination "generic/platform=iOS Simulator" build CODE_SIGNING_ALLOWED=NO
```

Każdy sprawdzian kończy się `WSZYSTKO OK` (kod 0) albo listą `BŁĄD …` (kod 1). Jeśli `plan-store-check.sh` nie
skompiluje `#Preview` z `PolishPlural.swift`, skrypt już dodaje `-plugin-path` platformy macOS, gdy katalog
istnieje — wtedy zgłoś błąd kompilacji, nie obchodź go. Potem przejście ręczne z sekcji „Testy” raportu głównego.

### SHA

| Commit | Opis |
|---|---|
| `23d43e8` | fix: jawny typ zadania w `RecipeCatalogStore.reload()` |
| `321074f` | docs(plan): zakres blokady porcji — tylko alokacje znane lokalnie |
| `de04177` | test(plan): granica `MealCalendarStore` → repozytorium |
| (ten commit) | docs: addendum 2 |

### Status (osobno)

- **Gotowość kodu do kolejnego review:** TAK — poprawki z tej rundy w kodzie, komentarze i raport spójne.
- **Weryfikacja na macOS:** OCZEKUJE — trzy sprawdziany i build NOT RUN; nic nie jest READY do merge'a przed nimi.
- **Blocker backendowy przed bezpiecznym uruchomieniem alokacji:** OTWARTY. Atomowa odmowa zapisu bez `portions`
  na pozycji z alokacją (także `replaceRecipeId`, `applyWeekPlan`, apply/undo Asystenta, narzędzia AI), 409
  z bieżącym stanem, test interleavingu powyżej. Do tego czasu alokacji nie wolno tworzyć na prod — także poza
  planerem.

## Addendum 3 — edycja porcji odblokowana, krok 0,5 (2026-09-27)

Backend zamknął API GAP: rewizje i tokeny (#212), `portionPolicy` (#215), krok 0,5 (#222) — na produkcji,
`AI_PLANNER_PER_USER_PORTIONS=true`. Kontrakt: `scoffie-backend/docs/workstreams/plan-portions-safe-editing/ios-contract.md`
+ §16 raportu `per-user-portions-write-safety`.

### Co zmieniono

| Obszar | Zmiana |
| --- | --- |
| Model | `PlanMeal.revision` + `portionRevisions` (z `items[].revision`, `portions[].revision`); `canEditPortions` = są tokeny pozycji i każdej osoby. Cache bez tokenów dekoduje się jako „nie znam” |
| Porcja osoby | `MealCalendarStore.setPortions` → `weeklyPlans:setPortion` osobno dla każdej zmienionej osoby, z JEJ tokenem; ack podmienia porcje i tokeny (starszy ack nie cofa stanu) |
| Zapis pozycji z alokacją | zamiast blokady: `portionPolicy: PRESERVE` + `expectedRevision`; przy zamianie zawsze `expectedTargetRevision` (`null` = celu nie ma); bez `plannedServings`. Alokacja bez tokenów → brak zapytania, odświeżenie |
| Błędy | `PLAN_REVISION_CONFLICT` / `PLAN_REVISION_REQUIRED` / `PLAN_PORTIONS_CONFLICT` / `PLAN_ITEM_NOT_FOUND` → cofnięcie wpisu optymistycznego + odświeżenie tygodnia, bez ponowienia; nowe kopie w `UserFacingErrorMapper` |
| UI | szczegóły posiłku: przy każdej osobie stepper co 0,5 (0,5–6, plus gaśnie przy sumie 12), makra i składniki liczą się na bieżąco, zapis „Zapisz porcje”. Ten sam `DetailServingsStepper` co porcje łączne (krok i etykieta z parametru). Etykiety „1”, „1,5”, „0,5” |
| Arkusz porcji w slocie | danie z porcjami per osoba da się zawęzić „Zamień” (dotąd zostawało „obok”) — serwer przelicza przez `PRESERVE` |

### Testy

| Sprawdzian | Wynik |
| --- | --- |
| tree-sitter (składnia zmienionych plików + skryptów), CRLF, duplikaty typów | OK (Windows) |
| `sh Scripts/plan-portions-check.sh` — przepisany: etykiety, stepper, decyzja `PRESERVE`/`blocked`/`send` | **NOT RUN** — macOS |
| `sh Scripts/plan-store-check.sh` — `PRESERVE` z tokenami, zamiana z parą tokenów, `setPortion` per osoba, konflikt → cofnięcie bez ponowienia | **NOT RUN** — macOS |
| build Xcode | **NOT RUN** — macOS |

Polecenia jak w addendum 2. Ręcznie na TestFlight / symulatorze: plan ułożony przez Asystenta (porcje per osoba) → szczegóły
posiłku → zmień porcję → „Zapisz porcje”; drugi telefon zmienia tę samą porcję w międzyczasie → komunikat i świeży plan.
