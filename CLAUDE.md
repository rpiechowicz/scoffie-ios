# Weekly Meals — iOS (SwiftUI)

Aplikacja iOS dla backendu `rpiechowicz/weakly-meals-backend`. Pełny kontekst projektu,
decyzje i stan prac: w repo backendu — `CLAUDE.md`, `docs/handover/2026-08-28-stan.md`,
`docs/handover/memory/`. Rozmawiamy po polsku, na „ty”.

## Build i praca
- Tylko Mac. Build bez Xcode GUI:
  `xcodebuild -project "weekly meals.xcodeproj" -scheme "weekly meals" -destination "generic/platform=iOS Simulator" -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64 EXCLUDED_ARCHS=x86_64`
  (log do pliku, potem `grep -E "error:|BUILD (SUCCEEDED|FAILED)"`). Brak targetu testów — regresje
  sprawdza się ręcznie na telefonie; fizyczny iPhone łączy się po LAN IP Maca, nie `localhost`.
- Repo leży w iCloud Desktop — pliki bywają „dataless”; gdy git/xcodebuild wisi przy 0 % CPU,
  zmaterializuj: `find "weekly meals" -type f -exec cat {} + > /dev/null`.
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
- WebSocket z auth (Faza 0): access token w handshake (`SocketIORecipeSocketClient(baseURL:tokenProvider:)`
  → `connect(withPayload: ["token"])`); JEDEN socket sesji z `SessionStore.sessionSocket()` — nie tworzyć
  nowych `SocketIORecipeSocketClient` w kodzie sesji. Odmowa serwera (`connect_error` z `data.code ==
  "UNAUTHORIZED"`, `auth:expired`) → `observeAuthFailure` → `refreshSessionTokens()` (single-flight,
  `POST /auth/refresh`) → `reconnectWithFreshToken()` albo `logout()`. `userId` w payloadach eventów jest
  ignorowane przez serwer dla socketu z tokenem — zostaje na jedno wydanie. REST 401 →
  `IntegrationsAPIClient` robi jeden refresh i retry. Logout woła `POST /auth/logout`. Backend w
  `WS_AUTH_MODE=soft` wpuszcza jeszcze stare buildy bez tokenu; `strict` po adopcji tego buildu.
