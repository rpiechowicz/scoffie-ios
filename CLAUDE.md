# Scoffie — iOS (SwiftUI)

Aplikacja iOS dla backendu `rpiechowicz/weakly-meals-backend`. Pełny kontekst projektu,
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

## Kontrakty z backendem (nie zmieniać jednostronnie)
- Błędy: `WsEnvelope` (`ok, data, error, message, code, status, details?, requestId`) i REST
  `{code, message, details?, requestId}`; `envelope.failure(fallback:)` → `RecipeDataError.server`;
  kopie po kodzie w `UserFacingErrorMapper.copyByCode` (parytet z `src/common/app-error-code.ts`).
  Odpowiedź z kodem nigdy nie jest „błędem łączności” (`ConnectivityErrorGate`).
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
  schowa obie pod „Więcej".
- Asystent AI (Faza 1) jedzie po REST, NIE po sockecie: `POST /agent/conversations/:id/messages`
  oddaje `202` z `turnId`, a odpowiedź zbiera się odpytywaniem `GET /agent/turns/:id` co sekundę
  (`AgentAPIClient` + `AgentStore`). Powód jest po obu stronach: tura trwa 25–60 s i musi przeżyć
  telefon w tle, a ack Socket.IO wygasa po kilku sekundach. `clientMessageId` (UUID z telefonu) jest
  kluczem idempotencji — ponowienie oddaje TĘ SAMĄ turę, zamiast płacić drugi raz za ten sam prompt.
  Daty (`weekStart` = poniedziałek, `clientToday`, `timeZone`) liczy TELEFON; serwer stoi w UTC.
  `AgentStore` wisi na `SessionStore`, a nie na arkuszu — rozmowa przeżywa zamknięcie asystenta.
  Kroki postępu (`turn.progress`) przychodzą z serwera jako gotowe zdania po polsku; nie tłumaczyć
  ich po stronie klienta. `AI_ENABLED=false` na serwerze = `503 AI_DISABLED` i ekran mówi to wprost.
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
  `IntegrationsAPIClient` robi jeden refresh i retry. Logout woła `POST /auth/logout`. Backend w
  `WS_AUTH_MODE=soft` wpuszcza jeszcze stare buildy bez tokenu; `strict` po adopcji tego buildu.
