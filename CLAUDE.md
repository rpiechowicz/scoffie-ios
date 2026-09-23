# Scoffie — iOS (SwiftUI)

Aplikacja iOS dla backendu `rpiechowicz/scoffie-backend`. Pełny kontekst projektu,
decyzje i stan prac: w repo backendu — `CLAUDE.md`, `docs/handover/2026-08-28-stan.md`,
`docs/handover/memory/`. Rozmawiamy po polsku, na „ty”.

## Build i praca
- Tylko Mac. Build bez Xcode GUI:
  `xcodebuild -project "Scoffie.xcodeproj" -scheme "Scoffie" -destination "generic/platform=iOS Simulator" -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64 EXCLUDED_ARCHS=x86_64`
  (log do pliku, potem `grep -E "error:|BUILD (SUCCEEDED|FAILED)"`). Brak targetu testów — regresje
  sprawdza się ręcznie na telefonie; fizyczny iPhone łączy się po LAN IP Maca, nie `localhost`.
- **Szybka kontrola typów bez pełnego builda (~30 s zamiast ~4 min)** — jedyny sposób, żeby
  sprawdzić kod pisany na Windowsie (tam nie ma Xcode). Musi mieć TE SAME flagi co Xcode,
  inaczej przepuszcza błędy (patrz niżej):
  ```sh
  SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
  DD=~/Library/Developer/Xcode/DerivedData/Scoffie-*/Build/Products/Debug-iphonesimulator
  FEATURES="-D DEBUG -enable-testing -enable-bare-slash-regex \
    -enable-upcoming-feature DisableOutwardActorInference \
    -enable-upcoming-feature InferSendableFromCaptures \
    -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
    -enable-upcoming-feature MemberImportVisibility \
    -enable-upcoming-feature InferIsolatedConformances \
    -enable-upcoming-feature NonisolatedNonsendingByDefault"
  find Scoffie -name '*.swift' -exec xcrun swiftc -typecheck -sdk "$SDK" \
    -target arm64-apple-ios26.0-simulator -swift-version 5 \
    -Xfrontend -default-isolation=MainActor ${=FEATURES} \
    -I "$DD" -F "$DD" -F "$DD/PackageFrameworks" {} +
  ```
  `-I/-F` wskazują zbudowane pakiety SPM (SocketIO) — bez nich leci `no such module`.
  Pojedynczy wzorzec sprawdza się w 2 s w osobnym pliku próbnym z tymi samymi flagami.
- **Pułapka SE-0418 (`InferSendableFromCaptures`, włączone w tym projekcie):** referencja do
  metody obok `nil` w wyrażeniu warunkowym (`cond ? nil : metoda`) daje dwa równorzędne
  rozwiązania typu. Kompilator NIE wskazuje tej linii — mówi `ambiguous use of 'init'`
  o kilkadziesiąt linii wyżej, przy najbliższym kontenerze SwiftUI (np. `ScrollView`).
  Jawny typ nie pomaga; pomaga domknięcie: `cond ? nil : { metoda() }`.
- **Logika briefingu asystenta**: `sh Scripts/assistant-logic-check.sh` — kompiluje
  `Models/Assistant/AssistantBriefing.swift` (TYLKO Foundation) ze scenariuszami
  w `Scripts/AssistantLogic/main.swift` i sprawdza priorytety pustego ekranu (pula > nowe konto
  > pusty tydzień > dziś > wieczór+jutro > brakująca pora główna > przyszły tydzień pod koniec
  tygodnia > realny brak w bilansie > gotowe > weekend). Nowa sytuacja = nowy `Kind` w resolverze
  + scenariusz tutaj. Widok (`AssistantBriefingCard`) NIE liczy nic sam.
- **Kontrakt kart asystenta**: `sh Scripts/card-contract-check.sh` — kompiluje DTO kart razem
  z wzorcem odpowiedzi serwera i sprawdza, czy wszystko się dekoduje. Jedyna automatyczna
  kontrola w tym repo (nie ma targetu testów) i jedyna rzecz, która potrafi zepsuć się CAŁKIEM
  po cichu: zmiana nazwy pola w backendzie nie da błędu, tylko karta zniknie z ekranu. Wzorzec
  odświeża `scripts/dump-card-fixtures.ts` w backendzie.
- Polski cudzysłów: `„…”`. W literale `String` zamknięcie prostym `"` KOŃCZY literał w połowie
  zdania — objaw to `Invalid character in source file` + `Expected ',' separator`. Kontrola:
  linia, w której liczba `„` ≠ liczba `”`, a nie jest komentarzem.
- Repo leży w iCloud Desktop — pliki bywają „dataless”; gdy git/xcodebuild wisi przy 0 % CPU,
  zmaterializuj: `find Scoffie -type f -exec cat {} + > /dev/null`.
- Gałęzie z `develop` po `git fetch --prune`, od razu `git push -u origin <gałąź>`; PR → `develop`
  → `main` → TestFlight (po stronie Rafała). Commity po polsku, `Co-Authored-By: Claude <noreply@anthropic.com>`.
- **Sentry** (od 23.09.2026, projekt `scoffie/scoffie-ios`, region DE): `Models/Observability/CrashReporting.swift`,
  start w `ScoffieApp.init`, użytkownik (samo id) przez `CrashReporting.setUser` przy każdym przypisaniu
  `SessionStore.currentUserId`. Środowiska: `development` (DEBUG) / `testflight` / `production`. Bez zrzutów
  ekranu, hierarchii widoków i session replay (alergeny, kroki na ekranie); nagłówki śladu tylko do
  `api.scoffie.app`; 5xx zgłasza backend, nie telefon. dSYM wysyła faza „Upload dSYM to Sentry” przy
  archiwum (Release) — na Macu raz: `brew install getsentry/tools/sentry-cli && sentry-cli login`;
  bez tego build przechodzi z ostrzeżeniem, ale crashe są bez nazw funkcji.

## Kontrakty z backendem (nie zmieniać jednostronnie)
- Błędy: `WsEnvelope` (`ok, data, error, message, code, status, details?, requestId`) i REST
  `{code, message, details?, requestId}`; `envelope.failure(fallback:)` → `RecipeDataError.server`;
  kopie po kodzie w `UserFacingErrorMapper.copyByCode` (parytet z `src/common/app-error-code.ts`).
  Odpowiedź z kodem nigdy nie jest „błędem łączności”.
- **Błędy do pokazania biorą się WYŁĄCZNIE z `UserFacingErrorMapper.inlineMessage(from:)`**, nie
  z `message(from:)`. `inlineMessage` oddaje `nil` dla błędów łączności i melduje je
  w `ConnectivityMonitor`; brak sieci ma w aplikacji dokładnie jedno miejsce — trwały pasek
  toastu u góry, zapalany dopiero po 6 s nieprzerwanych kłopotów. Nie dopisywać zdań w rodzaju
  „Sprawdź internet” przy ekranach ani przyciskach. `message(from:)` zostaje surowym mapowaniem
  dla samego toastu.
- Alergeny: `enum Allergen` rawValue = id z `src/common/allergens.ts`; nowa wartość NAJPIERW na
  serwerze. Przepis niesie `allergens`/`dietTags` z serwera (`RecipeDietProfile.fromServerTags`);
  heurystyka `RecipeDietClassifier` tylko gdy pola są `nil`. Pusta lista = fakt, nie brak danych.
- Cache katalogu `recipes_catalog_cache_v12.json` — po zmianie kształtu `Recipe` podbić wersję
  (komentarz w `RecipeCatalogStore.cacheFileURL`); kasowany przy wylogowaniu.
- `plannedServings` = porcje łączne; sloty per gospodarstwo + `suitableMealTypes`; tydzień od
  poniedziałku przez `PlanWeek`.
- Dolne menu: Przepisy · Plan · Kalendarz · **Asystent** · Ustawienia. „Produkty" NIE są już
  zakładką — lista zakupów wchodzi przyciskiem z nagłówka Planu tygodnia (`ProductsView` jako
  arkusz z `topPadding: 24`, bo domyślne 78 pt odsuwa tytuł od Dynamic Island, a nie od uchwytu
  arkusza). Piąte miejsce w menu jest zajęte — nowa zakładka wymaga wyjęcia innej, inaczej iOS
  schowa obie pod „Więcej". Pasek jest WŁASNY (`SCFloatingTabBar` w `overlay`), a kontener
  zakładek też: `NavigationMenu` to `ZStack`, NIE `TabView`. Wszystkie zakładki budują się po kolei
  POD loaderem startowym (pulpit wchodzi do drzewa pod `StartupLoaderView`, loader gaśnie nad
  gotowym ekranem) i potem zmieniają tylko widoczność — przełączenie jest cięciem w jednej klatce.
  Skutek: `onAppear` ekranu zakładki odpala się RAZ, pod loaderem. „Użytkownik wszedł na zakładkę"
  to `@Environment(\.scTabIsActive)` + `onChange(of:initial:)`; ciągłe animacje (`TimelineView`)
  mają na niewybranej zakładce stać. Pasek ma JEDEN gest na całość: pigułka idzie za palcem
  (stuknięcie i przeciąganie w bok jak w iOS 26), zakładka zmienia się po puszczeniu, w transakcji
  z `disablesAnimations`. Nie dokładać przycisków, `matchedGeometryEffect`, haptyki ani fade'ów
  przy wejściu na zakładkę. Przy przewijaniu w dół pasek zwija się do samych ikon (Revolut):
  główny `ScrollView` zakładki melduje kierunek przez `scTracksTabBarCompaction()`; rezerwa
  miejsca pod treścią (`scReservesTabBarSpace()`, WEWNĄTRZ `NavigationStack`) jest stała i schodzi
  do zera przy klawiaturze.
- Zdjęcia: `CachedAsyncImage(url:variant:)`. Domyślna `.thumbnail` (512 px, ~1 MB w pamięci, JPEG
  na dysku) — listy, kafelki, talerze; `.large` tylko dla okładki szczegółów i dużych kart
  (pokazuje miniaturę, dopóki duża się nie zdekoduje). Oryginały to PNG 1024² po 4 MB po
  zdekodowaniu — w `.large` cały katalog NIE mieści się w pamięci i listy zaczynają migać.
  Start (`SessionStore.prepareStartupData`) czeka na miniatury CAŁEGO katalogu i bieżącego tygodnia.
- Asystent AI (Faza 1) jedzie po REST, NIE po sockecie: `POST /agent/conversations/:id/messages`
  oddaje `202` z `turnId`, a odpowiedź zbiera się odpytywaniem `GET /agent/turns/:id` co sekundę
  (`AgentAPIClient` + `AgentStore`). Powód jest po obu stronach: tura trwa 25–240 s (sufit `AI_TURN_TIMEOUT_MS`,
  od 6.09.2026 podniesiony z 90 s) i musi przeżyć telefon w tle, a ack
  Socket.IO wygasa po kilku sekundach. Sufit odpytywania na telefonie
  (`AgentStore.pollTimeout`) MUSI zostawać nad sufitem serwera. `clientMessageId` (UUID z telefonu) jest
  kluczem idempotencji — ponowienie oddaje TĘ SAMĄ turę, zamiast płacić drugi raz za ten sam prompt.
  Daty (`weekStart` = poniedziałek, `clientToday`, `timeZone`) liczy TELEFON; serwer stoi w UTC.
  `AgentStore` wisi na `SessionStore`, a nie na arkuszu — rozmowa przeżywa zamknięcie asystenta.
  Kroki postępu (`turn.progress`) przychodzą z serwera jako gotowe zdania po polsku; nie tłumaczyć
  ich po stronie klienta. `AI_ENABLED=false` na serwerze = `503 AI_DISABLED` i ekran mówi to wprost.
- **Źródło makiet asystenta** to dwa artefakty Claude Design (bundle React): „Scoffie — Asystent v4”
  (`claude.ai/artifact/VRQX2MccxwjMNTSvbFLU1U`: ekrany, stan pracy, karty, stany karty, arkusze,
  język systemu) i „Dynamic Empty States” (`claude.ai/artifact/43pdC2GemR7abQDdGepU65`: 12 wariantów
  briefingu, kółka zamiast kafelków, reguły priorytetu). Rozpakowanie: manifest base64+gzip w HTML.
  Liczby z `kit.jsx` (`L`) siedzą w `AssistantLook` (`AssistantCardKit.swift`) — jasny motyw co do
  wartości, ciemny na palecie aplikacji. Arkusze stoją na `AssistantSheetKit.swift`
  (`AssistantSheetScaffold` = eyebrow · tytuł · X, `AssistantGroup`, `AssistantRow`). Stan pracy
  (`AssistantThoughtLine`, faza `working`) to „Oddech łuku” (artefakt `claude.ai/artifact/7vwJmr2mCR8xTYnjAJ9F3s`):
  znak, łuk i status w TERAKOCIE (nie indygo z makiety — decyzja Rafała 21.09.2026), obrót 2,4 s,
  oddech 5 → 55 % obwodu 1,8 s, nigdy zamknięty. Od 21.09.2026 to DZIENNIK w jednej kolumnie
  (18 pt ikona + 10 pt, czyli linia znaku marki przy odpowiedzi): u góry ślad trzech ostatnich
  zrobionych kroków (ptaszek + zdanie, zapis w szałwii), POD nim bieżący krok (łuk 18 pt bez znaku,
  status z przebłyskiem, sekundy po prawej), „Możesz wyjść” wcięte do tekstu; bez paska; „Myślałem 42 s” stoi POD tekstem odpowiedzi (`AssistantVoice`), nie nad nim.
- UI asystenta (redesign 19.09.2026): wszystkie karty stoją na atomach z `AssistantCardKit.swift`
  (`AssistantCard` z tonem neutral/sage/indigo/muted, `AssistantCardHead` z pigułką stanu
  `AssistantStatusChip`, `AssistantCardActions` — jedna akcja = pełna szerokość, dwie = wtórna
  po lewej i główna po prawej, nawigacja = wiersz z chevronem; `AssistantProposalFooter` liczy
  akcje ze stanu z serwera). Stan propozycji jest TEKSTEM (`AssistantCardStatus.title`), nie
  tylko kolorem. Porażka tury to `AssistantOutcomeCard` (bez czerwieni; „Nic nie zmieniłem
  w planie” tylko gdy `AgentStore.lastTurnWrote == false`), nie notka z wykrzyknikiem. Na żywo
  wiersz „myślę” pokazuje JEDEN bieżący status + `AssistantArcSpinner` (łuk krąży i oddycha, sygnał, nie procent)
  + kontekst słowami z aplikacji — nazwy narzędzi nie wychodzą na ekran. Podglądy kart biorą
  wzorce z `Previews/AssistantPreviewFixtures.swift` (kopia JSON-ów z `Scripts/CardContract`).
- Wybór posiłku (karta OPTIONS, 21.09.2026) — makieta Claude Design „Asystent — Wybór posiłku”
  (`claude.ai/design/p/43b605d0-57b7-4ad4-9744-6c4996fcf103`, „L jako arkusz”). `AssistantOptionsCard`
  to kotwica w rozmowie (świeża odpowiedź otwiera arkusz sama, RAZ na wiadomość), a
  `AssistantOptionsStorySheet` to JEDEN trwały układ na wszystkie dania: sloty o wysokości
  najdłuższego dania, tekst przypięty do dołu (eyebrow dojeżdża nad krótszą nazwę), zdjęcia
  przenikają nad sobą, cyfry rolują, pasek makro zmienia proporcje w miejscu — NIE podmieniać
  strony w całości, bo wraca skakanie układu. Opis, makro i liczbę składników, których stara
  karta z historii nie ma, dociąga katalog (`OptionsDishFacts`). Odejścia od makiety (decyzje
  Rafała): przyciski asystenta są „soft” (`scSoftCapsule` w `AssistantPrimaryButton`, neutralny
  `AssistantGhostButton`), liczba składników stoi w rzędzie z kcal i min zamiast szarej linijki,
  wiersz „Uwzględniłem: …” usunięty z rozmowy. `Kes size=n` z makiety to dysk 0,68·n
  (`SCMarkShape` wypełnia całą ramkę). Animację w liściu zawężać przez `animation(_:body:)`
  albo `geometryGroup()` — zwykłe `.animation(value:)` nadpisuje ruch nadany przez rodzica.
- Szkic odpowiedzi i jej dopisywanie liczą się z JEDNEGO zegara (`AgentStore.draftReveal`,
  `AgentRevealClock`, 70–320 znaków/s): gotowa odpowiedź rusza od znaku, który JEST na ekranie
  (i od wspólnego początku ze szkicem), nie od długości szkicu z serwera — inaczej wskakuje naraz.
- Loader startu stoi NAD korzeniem (`ScoffieApp.showsStartupLoader`), nie w gałęzi pulpitu:
  krycie kontenera bez `compositingGroup` schodzi na dzieci, więc przy przejściu korzenia przez
  loader prześwitywała zakładka. Gesty w arkuszach: poziome przewijanie przez
  `UIGestureRecognizerRepresentable` ruszające tylko przy ruchu poziomym (`OptionsPagePan`) —
  `DragGesture` na całym arkuszu zabiera systemowi zamykanie w dół.
- Szczegóły posiłku v2 (21.09.2026) — makieta Claude Design „Scoffie — Szczegóły Posiłku v2”
  (projekt `43b605d0-…`, `components/detail-v2.jsx`, sekcja „final”). Stepper porcji siedzi
  w nagłówku „Wartości odżywcze”; pod nim porcja na tle celu dnia (`PlanGoalRings` +
  `PlanGoalLegendRow`, kolory `SCMacroPalette`) zamiast donuta z makiety, a przycisk na dole
  w zwykłym wariancie „soft” — decyzje Rafała 21.09. „Mam w domu” to stan WIZYTY; „Do zakupów” wysyła brakujące przez
  `weeklyPlans:addRecipeExtras` na tydzień z Planu (nie wcześniejszy niż bieżący) — tylko
  z katalogu, bo posiłek z planu ma składniki na liście od początku. Dopisane pozycje listy
  mają `addedFrom` i menu „Usuń dopisane z przepisu” pod przytrzymaniem.
  Zrzuty: `SCOFFIE_DEBUG_OPTIONS=detail|detail-planned` (+ `SCOFFIE_DEBUG_DETAIL_SCROLL=<pt>`,
  `SCOFFIE_DEBUG_DETAIL_HAVE=<n>`).
- Wygląd sprawdzamy NA ZRZUCIE, nie po samym buildzie: `SCOFFIE_DEBUG_OPTIONS=0…n|card|buttons|
  auth|auth-error|legal|thought|plate` (+ `SCOFFIE_DEBUG_OPTIONS_AUTOPLAY` do nagrania animacji) otwiera ekrany
  z `Previews/AssistantOptionsDebugScreen.swift` bez sesji i bez alertów systemowych; tylko DEBUG.
  Uruchamiać na OSOBNYM symulatorze (`SIMCTL_CHILD_…=… xcrun simctl launch`), nie na roboczym.
- Ekran logowania nie przewija się: elastyczne jest hero z kaflami (150–280 pt) i odstęp nad
  przyciskiem; poniżej 700 pt kafle funkcji tracą podpisy. Arkusze dokumentów
  (`LegalDocumentSheet`) stoją na `EditorialSheetHeader`, nagłówek NAD przewijaną treścią.
- REST-owy błąd nazywa się `BackendAPIError` (dawniej `IntegrationsAPIError`) — od asystenta klientów
  uwierzytelnionych jest dwóch (`IntegrationsAPIClient`, `AgentAPIClient`) i oba rzucają ten sam typ.
- `recipes:changed` (`{householdId, recipeId, action, changedByUserId}`) — przepis gospodarstwa
  powstał, zmienił się albo został wycofany, także ręką asystenta. `RecipeCatalogStore` przeładowuje
  katalog Z DEBOUNCE 300 ms, bo asystent potrafi zapisać kilka przepisów pod rząd.
- WebSocket z auth (Faza 0): access token w handshake (`SocketIORecipeSocketClient(baseURL:tokenProvider:)`
  → `connect(withPayload: ["token"])`); JEDEN socket sesji z `SessionStore.sessionSocket()` — nie tworzyć
  nowych `SocketIORecipeSocketClient` w kodzie sesji. Odmowa serwera (`connect_error` z `data.code ==
  "UNAUTHORIZED"`, `auth:expired`) → `observeAuthFailure` → `refreshSessionTokens()` (single-flight,
  `POST /auth/refresh`) → `reconnectWithFreshToken()` albo `logout()`. `userId` w payloadach eventów jest
  ignorowane przez serwer dla socketu z tokenem — zostaje na jedno wydanie. REST 401 →
  `IntegrationsAPIClient` robi jeden refresh i retry. Logout woła `POST /auth/logout`. Produkcja
  backendu chodzi w `WS_AUTH_MODE=strict` (od 5.09.2026 `soft` na produkcji = odmowa startu), więc
  socket bez tokenu nie wchodzi; pole `userId` w payloadach można już zdjąć w kolejnym wydaniu.
