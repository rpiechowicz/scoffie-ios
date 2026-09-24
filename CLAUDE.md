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
- **Logika powitania asystenta** (pusty ekran): `sh Scripts/assistant-logic-check.sh` — kompiluje
  `Models/Assistant/AssistantBriefing.swift` (TYLKO Foundation) ze scenariuszami
  w `Scripts/AssistantLogic/main.swift` i sprawdza priorytety 17 sytuacji (pula > nowe konto > późna
  pora 22–5 > pusty tydzień (≥ 3 dni do końca) > dziś pusto > „Za 40 minut obiad” (90 min przed porą)
  > brak śniadania / obiadu / kolacji dziś > wieczór: jutro puste / częściowe > przyszły tydzień pod
  koniec tygodnia > realny brak w bilansie > tydzień gotowy > weekend > wieczór: jutro gotowe > dzień
  gotowy). Nowa sytuacja = nowy `Kind` w resolverze + scenariusz tutaj. Widok (`AssistantEmptyState`)
  NIE liczy nic sam.
- Powitanie (23.09.2026) — makieta Claude Design „Scoffie - Asystent Empty State v2” (projekt
  `43b605d0-…`, `components/ae-*.jsx`), wariant A: znak 24 pt (większy niż w makiecie), otwarcie 28 semibold, zdanie pomocy 17,
  kontekst bez słów (talerzyki pór / najbliższe danie / pasek bilansu), główna akcja „soft” na
  szerokość treści i `AssistantChip`-y alternatyw — JEDEN blok przyklejony nad polem wiadomości
  (wolne miejsce nad nim; gdy wyższy niż ekran, startuje od otwarcia). Ostatnia alternatywa to zawsze
  „Mam inny pomysł” = sam fokus pola (akcje i kontekst gasną, otwarcie zostaje), a przykład w polu
  (`briefing.placeholder`) zmienia się z sytuacją. Bez liczenia braków („0 z 4”) i dat w tekście.
  Ruch: otwarcie (65 zn/s) i zdanie (170 zn/s) PISZĄ SIĘ — razem najwyżej 0,75 s, dłuższy tekst przyspiesza oba w tej samej proporcji (`typingBudget`) (`Components/SCTypedText.swift` — nienapisana końcówka jest
  przezroczysta, więc układ nie skacze), potem kaskada kontekstu i akcji, liczby przez `SCCountingText`;
  gra przy NOWEJ sytuacji, a przy wejściu na zakładkę tylko pierwszy raz po uruchomieniu aplikacji albo po 30 min przerwy (`AssistantGreetingMemory`, 24.09.2026 — „nie za każdym razem”; inaczej stoi gotowe), a ta sama sytuacja z inną liczbą tylko roluje
  (`numericText`). Akcje o JEDNEJ porze proszą o dania „do wyboru”, więc kończą się arkuszem wyboru
  posiłku (prompt serwera: jedna pora albo „do wyboru” = `offer_options`).
- Przegląd propozycji w arkuszu wyboru posiłku: karty dnia i tygodnia mają dania jako przyciski i wiersz
  „Przeglądaj dania” (`OptionsBrowseRow`, ten sam co w karcie OPTIONS) → `AssistantOptionsStorySheet`
  w trybie `.review` (`OptionsStoryMode`): tag = pora (· dzień), pod daniem „Zamień to danie” (wysyła
  „Zamień w tej propozycji …: X. Pokaż 3 inne dania na tę porę do wyboru.” → serwer oddaje OPTIONS →
  „Wybieram: …” → ta sama propozycja z nowym daniem), strona końcowa „Wszystko pasuje?” z zapisem.
  Po zapisaniu / nieaktualna propozycja = sam podgląd, bez przycisków zmian. Od 24.09.2026 nad nazwą dania
  stoją pigułki KIEDY (`ProposalWhenPills`: pora z ikoną w `cozyAccent` + „Dziś, 24 września”, po zapisie „W planie”),
  a strona końcowa idzie za STANEM propozycji (`OptionsStoryMode.review(…, status:)`, `ProposalEndCopy`): „Wszystko
  pasuje?” z listą zestawu i zgodą w SZAŁWII (`ProposalAcceptButton`), zapis NIE zamyka arkusza — „Wstawiam do planu…”
  przechodzi w „Jest w planie” + „Otwórz plan”; cofnięta / nieaktualna / wygasła mają własne słowa.
  Runda 15 (24.09.2026): na dole strony końcowej JEDEN przycisk (zapis → „Otwórz plan” → przy stanie bez zapisu
  „Napisz, co zmienić”), lista zestawu (`ProposalRecap`) = miniatura dania, pora z ikoną w kolorze pory, nazwa, kcal
  (tydzień: wiersz na dzień z trzema krążkami zdjęć), nad nią dzień i suma kcal; pod listą cichy odnośnik
  „Zaproponuj inne dania” (`ProposalRegenerateLink`, wysyła prośbę o nowy zestaw). Świeża propozycja dnia/tygodnia
  (PENDING, przyszła na żywo) otwiera ten arkusz SAMA, raz na wiadomość (`ProposalAutoPresent`), jak karta OPTIONS.
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
  → `main` → TestFlight przez **Xcode Cloud** (po stronie Rafała). GitHub Actions NIE buduje iOS od 23.09.2026
  (minuty macOS ×10 wyczerpywały limit) — jedyna kontrola kompilacji to Xcode Cloud albo Mac. Commity po polsku, `Co-Authored-By: Claude <noreply@anthropic.com>`.
- **Sentry** (od 23.09.2026, projekt `scoffie/scoffie-ios`, region DE): `Models/Observability/CrashReporting.swift`,
  start w `ScoffieApp.init`, użytkownik (samo id) przez `CrashReporting.setUser` przy każdym przypisaniu
  `SessionStore.currentUserId`. Środowiska: `development` (DEBUG) / `testflight` / `production`. Bez zrzutów
  ekranu, hierarchii widoków i session replay (alergeny, kroki na ekranie); nagłówki śladu tylko do
  `api.scoffie.app`; 5xx zgłasza backend, nie telefon. dSYM wysyła faza „Upload dSYM to Sentry” przy
  archiwum (Release) na Macu, a w Xcode Cloud `ci_scripts/ci_post_xcodebuild.sh` (sekret `SENTRY_AUTH_TOKEN`
  w workflow, `sentry-cli` 3.8.0 przypięty sumą SHA-256); na Macu raz: `brew install getsentry/tools/sentry-cli && sentry-cli login`;
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
  z `disablesAnimations`. Nie dokładać przycisków, `matchedGeometryEffect` ani haptyki. Wejście na
  zakładkę (24.09.2026, prośba Rafała) = PRZENIKANIE: stara zakładka stoi pod spodem w pełnym kryciu, nowa
  nabiera krycia 0 → 1 NAD nią (0,2 s), krycie startowe w tej samej transakcji co wybór z paska
  (`NavigationMenu.tabSelection`, `leavingTab`); tło i wspólne elementy nie drgają. Runda 18 wyłaniała nową
  z gołego tła przy zgaszonej starej — „wygląda, jakby cały widok się zmieniał”. Bez Asystenta (własne
  powitanie), bez przy Reduce Motion, zmiany z kodu = cięcie.
  NIE wracać do `keyframeAnimator`/przesunięcia na całej stronie (`scTabEntrance`, runda 16) — Rafał: „totalnie
  zbugowane, przeskakuje”: ruszało od klatki w pełnym kryciu i przeliczało ekran zakładki w każdej klatce. Przy przewijaniu w dół pasek zwija się do samych ikon (Revolut):
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
  wartości, ciemny na palecie aplikacji. WYJĄTEK od 23.09.2026: powierzchnie (`card`, `cardStroke`,
  `field`) to żetony aplikacji (`scTileBg` / `scTileStroke` / `scChipBg`) w obu motywach, bez cienia —
  białe karty z makiety odstawały od reszty („wszystkie karty w tym samym kolorze”, decyzja Rafała).
  Nowa karta gdziekolwiek = `scTileBg` + `scTileStroke`; `scCardSurface`/`scInsetSurface` zostały tylko
  pod pływające kontrolki. Arkusze stoją na `AssistantSheetKit.swift`
  (`AssistantSheetScaffold` = eyebrow · tytuł · X, `AssistantGroup`, `AssistantRow`). Stan pracy
  (`AssistantThoughtLine`, faza `working`) to „Oddech łuku” (artefakt `claude.ai/artifact/7vwJmr2mCR8xTYnjAJ9F3s`):
  znak, łuk i status w TERAKOCIE (nie indygo z makiety — decyzja Rafała 21.09.2026), obrót 2,4 s,
  oddech 5 → 55 % obwodu 1,8 s, nigdy zamknięty. Od 21.09.2026 to DZIENNIK w jednej kolumnie
  (18 pt ikona + 10 pt, czyli linia znaku marki przy odpowiedzi): u góry ślad do ośmiu ostatnich
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
- Pusty stan Asystenta (runda 14): tryb „piszę” (akcje gasną) przełącza powiadomienie KLAWIATURY z jej
  krzywą (`AssistantView.greetingComposing`, `keyboardMoved`), nie fokus — fokus przychodził klatkę przed
  klawiaturą i powitanie skakało w dół i w górę. Nie przywracać `.animation(value: composing)`
  w `AssistantGreeting`. Puste pole ma JEDNĄ linię (`lineLimit(draft.isEmpty ? 1...1 : 1...8)`), bo
  dwuwierszowy przykład zwijał się przy pierwszej literze i ciągnął powitanie. Runda 15: akcje i kontekst NIE
  wypadają z układu — `GreetingCollapse` zwija zmierzoną wysokość do zera w krzywej klawiatury (krycie osobno,
  szybciej), a schowanie klawiatury rozwija powitanie w TYM SAMYM ruchu (`keyboardMoved(hiding:)`), nie po fokusie.
  Krzywa klawiatury jest jedna: `SCTabBarChrome.keyboardCurve` — także dla rezerwy pod dolnym menu (była `easeOut 0,25`).
- Żywy znak = `SCLivingMark` (`Components/`): nastroje idle (oddech 4,2 s + co 8 s rozejrzenie / mrugnięcie
  / pauza / obrót) · attentive · thinking (2,4 s obrót / 1,8 s oddech — liczby „Oddechu łuku”) · sleeping ·
  still, reakcje `cheer`/`nudge` (`keyframeAnimator`); staje przy nieaktywnej zakładce i przy Reduce Motion.
  Powitanie, kompaktowy nagłówek, jednorazowe podskoczenie przy świeżej odpowiedzi, karta puli. Drugiego
  kręcącego się znaku w linii myślenia NIE dokładać. Powitanie ma `lively: true` (runda 15, „ledwo zauważalna”):
  oddech 3,4 s o 10 % z unoszeniem, kołysanie ±5°, poświata do pełnej, zachowania co 5 s od 1,6 s
  (rozejrzenie · podskok · mrugnięcie · obrót), znak 26 pt. Ślad kroków w linii myślenia rośnie TYLKO w dół:
  bez kroków `transient`, każde zdanie raz, w miejscu pierwszego pojawienia, id = zdanie.
- Pusta pula jest znana PRZED kliknięciem (24.09.2026): `AgentStore.loadUsage` sam zakłada blokadę `.quota`,
  gdy `messages.remaining <= 0` (koniec: `resetsAt` / na próbie do planu), i zdejmuje ją, gdy pula ma zapas;
  wejście na zakładkę odświeża pulę (`refreshUsageIfStale`, 60 s), a `send` przy nieznanej puli pyta o nią,
  ZANIM wstawi dymek pytania — inaczej akcja powitania skakała w rozmowę i wracała z 429.
- Wykorzystana pula = `AssistantQuotaKit.swift`: `AssistantQuotaFacts` (liczby z `AgentUsageDTO`, plan
  tylko jako „Polecamy”), `AssistantQuotaPanel` w powitaniu `trialExhausted` (paski wiadomości/zapisów,
  alternatywy Plan tygodnia · Lista zakupów · Historia rozmów) i `AssistantQuotaSpentCard` zamiast pola
  (próbna → plany; miesięczna → arkusz limitów). Runda 23 (24.09.2026, „średnio wygląda”): karta = kafel
  44 pt z drzemiącym `SCLivingMark` w tincie terakoty, etykieta „DARMOWA PULA” / „PULA NA TEN MIESIĄC”,
  tytuł „Wiadomości wykorzystane” / „Asystent odpoczywa”, jedno zdanie „Plan i zakupy działają dalej.”,
  wiersz „co dalej” `AssistantQuotaNextRow` (miesięczna: „Wraca 1 października” + pigułka „za 8 dni”;
  próba: „Polecamy „We dwoje”” · wiadomości/mies. + pigułka z ceną) i JEDNA akcja. Kreseczek zużycia
  w karcie nie ma (pełny pasek nic nie mówił) — zostały w panelu powitania, który ma ten sam wiersz
  „co dalej” zamiast osobnej stopki (`AssistantQuotaResetRow` usunięty).
- Przyciski Asystenta (runda 14): stopka karty = `AssistantButtonSize.compact` (42 pt rysowane, 44 dotyk,
  14 semibold), przycisk samodzielny (arkusz, stopka, plany) = `.regular` (46 pt, 15). Para =
  `AssistantActionPair`: równe połowy, gdy oba tytuły się mieszczą, inaczej stos z główną NA DOLE — główna
  zawsze ostatnia. Ikony: strzałki/szewrony za tytułem, reszta przed. Praca = kółko na STUKNIĘTYM przycisku
  w miejscu ikony, szerokość bez zmian, drugi przygaszony. Chipy `AssistantChip` 38 pt / 44 dotyk.
  Wysokości nie ustawiać ręcznie — `size:`.
- Szkic odpowiedzi i jej dopisywanie liczą się z JEDNEGO zegara (`AgentStore.draftReveal`,
  `AgentRevealClock`, 70–320 znaków/s): gotowa odpowiedź rusza od znaku, który JEST na ekranie
  (i od wspólnego początku ze szkicem), nie od długości szkicu z serwera — inaczej wskakuje naraz.
- Przewodnik „Poznaj aplikację” (`Views/Tour/`, runda 24, 24.09.2026): punkty kroków to cztery sprawdzone w kodzie
  funkcje w karcie z ptaszkami w kolorze kroku (`TourPointsCard`, kaskada `scReveal`) — źródło każdego twierdzenia
  w komentarzu przy `TourStep.all`. Zmieniasz / usuwasz funkcję → popraw punkt. Zdjęte jako nieprawdziwe:
  „Własne przepisy domu” (nie ma tworzenia przepisów), „z Waszych przepisów” u asystenta, „z powodem” przy
  podmianie. Kadr zdjęcia ma sufit wysokości (`TourMedia`, `tourViewport`), żeby na SE punkty mieściły się nad stopką.
- Loader startu stoi NAD korzeniem (`ScoffieApp.showsStartupLoader`), nie w gałęzi pulpitu:
  krycie kontenera bez `compositingGroup` schodzi na dzieci, więc przy przejściu korzenia przez
  loader prześwitywała zakładka. Gesty w arkuszach: poziome przewijanie przez
  `UIGestureRecognizerRepresentable` ruszające tylko przy ruchu poziomym (`OptionsPagePan`) —
  `DragGesture` na całym arkuszu zabiera systemowi zamykanie w dół.
- Zmiana korzenia (logowanie, kreator, pulpit, wylogowanie, usunięcie konta) idzie JEDNĄ drogą:
  `SCSessionCurtain` (`Components/`, własne okno nad arkuszami, pod toastami) — zasłona w kolorze tła
  w górę, `ScoffieApp.showRootScreen` przestawia korzeń bez animacji (na AKTUALNY cel), zasłona w dół.
  Korzeń nie ma już własnego crossfade'u (pulpit wjeżdżał z loaderem i prześwitywał Kalendarz).
  Loader schodzi TYLKO na pełnym obrocie znaku (runda 21–22): SAM znak (`SCScoffieMark(markRotation:)`, kafel stoi)
  robi obrót ease-in-out na każdą falę dni, a cała choreografia (fala, refleks, oddech, kropki) idzie jednym taktem 1,34 s
  (`LoaderMotion.logoRotation`, `StartupLoaderView.turnSeconds`), a `ScoffieApp.loaderShown` czeka po
  `wantsStartupLoader == false` do końca bieżącego obrotu (`remainingToFullTurn`) — 1,5 obrotu = do końca drugiego.
  Runda 24 (24.09.2026): na tym końcu znak STAJE (`loaderRestElapsed` → `StartupLoaderView(restElapsed:)`,
  `LoaderMotion.motionElapsed`) — zegar szedł dalej i w 0,4 s gaśnięcia planszy ruszał trzeci obrót („zaczyna
  kręcić, a aplikacja już wchodzi”). Po spoczynku nie startuje żaden nowy cykl (obrót, oddech, refleks, kropki).
  WYJĄTEK — wejście do aplikacji (logowanie / kreator → pulpit): ZAWSZE loader startu, bez zasłony
  (`enterAppUnderLoader`, runda 18 — Rafał: „po logowaniu ZAWSZE ma się włączyć loading”): loader
  przenika się nad logowaniem (`entryLoaderHold`), korzeń przechodzi pod nim, loader schodzi po całej fali
  kafelków i `startupPhase == .ready` (sufit 12 s). Nie uzależniać go od fazy startu — bywała gotowa, zanim
  ktokolwiek zobaczył loader, i zasłona schodziła prosto na Kalendarz.
  Koniec sesji z ręki użytkownika = `SessionStore.signOut()` / `deleteAccount()`: najpierw
  `await sessionCurtain.cover()`, dopiero potem czyszczenie `UserDefaults` i store. Gołe `logout()`
  zostaje dla wylogowań wymuszonych (odmowa serwera, cofnięte Apple ID).
  Pod zasłoną, przed podmianą: `dismissPresentedScreens()` zamyka BEZ animacji arkusze starego
  korzenia (inaczej UIKit zamykał je sam, z animacją, już nad ekranem logowania), klawiatura chowa
  się razem z wejściem zasłony. Ekran, z którego się wychodzi, nie wraca do stanu spoczynku
  pod wchodzącą zasłoną: spinner logowania trzyma `isAuthenticated`, przycisk kroku 5 —
  `currentHouseholdId`. Logowanie BEZ domu czeka na `users:me` (limit 4 s) przed `isAuthenticated`,
  bo to ono mówi, czy kreator zaczyna od przewodnika, od kroku 5, czy od razu pulpit — dociągnięte
  po wejściu przestawiało kreator albo korzeń drugi raz na oczach użytkownika.
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
- Filtry przepisów v3 (23.09.2026) — makieta Claude Design „Scoffie - Przepisy v3 - Filtry”
  (projekt `43b605d0-…`, `components/filtry-final.jsx`). `RecipeFilterSheet` + klocki w
  `RecipeFilterKit.swift` + arkusze-dzieci `RecipeExcludeSheets.swift`. Po uwagach Rafała (23.09):
  wykluczanie to JEDEN kafelek w Filtrach, a szukanie + działy mieszkają w `RecipeExcludeSheet`
  (dział → `RecipeExcludeCategorySheet`); czas i trudność to dwa kafelki z menu w jednym rzędzie;
  kalorie to WYKRES, KTÓRY JEST SUWAKIEM (`RecipeFilterKcalChart`): słupki rozkładu
  (`RecipeFilterIndex.kcalHistogram`, przy pozostałych filtrach, bez samego limitu) stoją dokładnie
  na przedziałach skali, limit to pionowa kreska z gałką na osi, którą prowadzi się po całym wykresie;
  osobnego toru z wypełnieniem nie ma (Rafał: „zrezygnuj z tego Progressu”). Limit stoi dużą liczbą
  na górze karty, obok krzyżyk, który go zdejmuje, i „Do celu”; cel = szałwiowy odcinek NA osi z podpisem
  „500 · Twój cel · 800” — nigdy napis nad słupkami, bo przecinała go kreska. Aktywny przycisk
  filtrów na Przepisach = wariant „podświetlony”
  (`SCCircleIconLabel(highlighted:)`), nie pełna terakota. Przełącznik „Dopasowane do Ciebie” jest
  TYLKO w Filtrach (z podsumowaniem profilu i liczbą ukrytych) — różdżka w nagłówku Przepisów
  i `RecipePersonalizationSheet` zniknęły jako duplikat; pusty ekran przez dietę ma własny przycisk
  „Pokaż wszystkie przepisy”. Kafelek wyboru (`SCChoiceTile`, `Components/`) = miniatura ZDJĘCIA
  DANIA z tą cechą + nazwa + liczba przepisów; zaznaczenie = tint, obwódka wokół miniatury i znaczek
  z ptaszkiem (nie samo pole wyboru — „smutne”, Rafał 23.09). Zdjęcia dobiera `RecipeFilterCovers`
  / `RecipeFacetCovers` raz na otwarcie, z puli przed filtrami, każdy przepis na jednym kafelku;
  miniatura BEZ przybliżenia (zdjęcia katalogu to 1344×768 z talerzem na środku — `scaledToFill`
  w kwadracie już wycina środek, a dawne ×1,45 ucinało rant każdego talerza, runda 9);
  bez zdjęcia glif — i najpierw dania, których profil NIE ukrywa (kafelek nie pokaże dania z alergenem
  z Ustawień). Wspólny dla Diety/Cech i filtrów kategorii. Runda 14 postawiła kafelek PIONOWO (miniatura nad nazwą), 24.09 wrócił
  POZIOMY (miniatura 38 z lewej, obok nazwa i liczba) — Rafał: „podobało mi się bardziej, jak jest w 1 linii”;
  jedno długie słowo („Niskotłuszczowe”) maleje do 0,8, kilka słów schodzi do drugiej linii. Siatka
  `RecipeFilterTileGrid` stoi na `RecipeFilterTileGridLayout`: każdy kafelek ma wysokość najwyższego
  w CAŁEJ siatce, nie w wierszu.
  Wszystkie liczby w arkuszu idą przez `RecipeFilterOptions.matches(RecipeFilterFacts)` —
  tę samą regułę, którą filtruje lista, więc „Pokaż” nie może się rozjechać z listą; fakty
  per przepis trzyma `RecipeFilterFactsCache`, pulę arkusza `RecipeFilterIndex` (liczona leniwie
  raz na otwarcie). Wykluczanie składników jest po stronie telefonu, po nazwie i dziale
  z listy przepisów (`RecipeIngredient.department` = dział sklepu, te same alejki co Zakupy);
  grupa („Papryka · wszystkie”) = wspólny pierwszy wyraz w JEDNYM dziale, bez przyimka jako
  drugiego wyrazu (`IngredientExclusion.groupStem`). Odejścia od makiety: cechy „Jedno naczynie /
  Do pudełka / Budżetowe / Na zimno” zastąpione policzalnymi (katalog ich nie niesie),
  „Mięso i ryby / Zioła” to prawdziwe działy sklepu, kategoria składników ma krzyżyk zamiast
  „wstecz”, przyciski „soft”, szukanie kończy „Gotowe” zamiast „Anuluj”, a składniki to CHMURA
  PIGUŁEK (`RecipeExclusionPill` w `RecipeExclusionFlow`), nie wiersze z „Wyklucz” przy każdym —
  terakota = wykluczony, przerywana obwódka = wykluczony z całą grupą. Grupa („Papryka”) ma
  strzałkę i ROZWIJA rodzaje w panelu na całą szerokość chmury (tam „Wszystkie”); sama nie
  wyklucza. Działy mają ikony i barwy alejek Zakupów (`ProductConstants.departmentIcon/Color`),
  wyniki szukania są pogrupowane po działach.
- Stopka z przyciskiem na dole arkusza = JEDNA: `SCSheetFooter` / `.scSheetFooter { … }`
  (`Components/SCSheetFooter.swift`, wzór z szczegółów posiłku): kryjąca płyta w kolorze tła
  (`scPageBase`, czyli dół `SCPageBackground`) + cień krawędzi NAD nią, bez kreski i bez szkła.
  Cień to `SCEdgeShade` (`Components/SCEdgeShade.swift`) — JEDEN na górę i dół: górny pasek
  szczegółów posiłku (84 pt, przyciski stoją na nim) i jego lustro nad stopką (56 pt, zaczyna się
  na krawędzi płyty, nie wchodzi na przycisk). Rafał: „bardzo mi się podoba shadow górny, zrób taki
  sam od dołu”. Na przewijanej treści przez `.scSheetFooter` (`safeAreaInset`, cień WLICZONY
  w wysokość — przewinięta do końca treść kończy się nad nim), pod listą w `VStack` jako ostatnie
  dziecko — wtedy cień leży na liście i lista MUSI mieć na dole `.padding(.bottom,
  SCEdgeShade.bottomHeight)`. Przycisk pełnej szerokości = `EditorialPrimaryActionButton`,
  obok liczb = `RecipeFilterFooterButton`. `AssistantStickyFooter` i `AssistantSheetFooter` to już
  tylko nakładki na nią; kreator, przewodnik i wprowadzenie Asystenta też (`SCStepFooter`, runda 14).
- Przepływy krok po kroku (kreator „Poznajmy się”, przewodnik „Poznaj aplikację”, wprowadzenie Asystenta,
  runda 14) stoją na `Components/SCStepFlow.swift`: `SCStepHeader` (kafel `SCHeaderIconWell` 48, eyebrow
  10,5/1,4, tytuł 28 heavy, najwyżej jedno zdanie), `SCStepFeatureCard` i `SCStepFooter` = płyta
  `SCSheetFooter` z cieniem, nad przyciskiem wiersz 36 pt: krążek „Wstecz” · pasek `SCStepProgress`
  (odcinki na całą szerokość, bieżący nalewa się od lewej) albo odnośnik „Pomiń…” · licznik „2/5”; pod
  spodem `EditorialPrimaryActionButton`. JEDNA instancja na cały przepływ, żeby pasek się animował.
  `WelcomeFooter`, `WelcomeStepper`, `WelcomeStepHeader`, `TourFooter`, `TourBackground`, `AssistantTickRow`
  usunięte; kreator i przewodnik na `SCPageBackground`, margines 20, sekcje `WelcomeSection`, wiersze celu
  i diety jak w Ustawieniach, bez akapitów objaśnień.
- Przypięty nagłówek nad przewijaną treścią arkusza = BEZ kreski: `.scScrollEdgeFade()` na
  `ScrollView` (`Components/SCScrollEdgeFade.swift`) — górny brzeg treści gaśnie (maska, więc działa
  na każdym tle, także z poświatą `SCPageBackground`), dopiero gdy treść wjedzie pod nagłówek. Wzór:
  szczegóły posiłku. Nagłówek stoi NAD `ScrollView` w `VStack` — nie przewija się i nie zwija
  (zwijany „Filtrów”, z tytułem przeskakującym na środek, zniknął 23.09 na prośbę Rafała). Tak stoją
  też filtry kategorii, oba arkusze wykluczania, lista kategorii, wybór przepisu do planu, „Dodaj do
  planu”, Dieta, FAQ, Profil, Posiłki w planie, gospodarstwo, zgłoszenie odpowiedzi i wszystkie arkusze
  na `AssistantSheetScaffold` (runda 8). Wyjątek: `PlanDayGoalSheet` mierzy wysokość treści pod
  detent, więc nagłówek zostaje w mierzonej treści. Plan tygodnia też bez kreski pod nagłówkiem —
  `scScrollEdgeFade` na przewijanej gałęzi `DayPager`. Maska sięga pod pasek domowy (`ignoresSafeArea`).
- Plany asystenta: to, co dom MA, bierze się WYŁĄCZNIE z serwera (`BillingStateDTO.subscriptions`
  z `alive`, potem `AgentUsageDTO.source == "SUBSCRIPTION"` + `product`). Liczba domowników
  (`PlansSheet.plan(forHousehold:)`) tylko PODPOWIADA („Polecany”, „polecamy We dwoje”) — nigdy nie
  pisze „Twój …”. Kiedyś „Twój dom” przy planie z liczby osób czytało się jak kupiony plan.
- Alergeny w Ustawieniach → „Dieta i alergeny”: sam wynik (`AllergenSummaryCard` — „Omijamy 3 alergeny ·
  ukrywa 84 przepisy” + etykiety), wybór w osobnym arkuszu (`AllergenPickerSheet`: trzy grupy, ikona
  i jedno zdanie przy każdym alergenie, pole wyboru). Trzy układy w samym arkuszu diety odpadły
  (chmura, kafle z opisami, siatka pigułek — „dalej nie jest ładne UX”). Od 24.09.2026 kreator stoi
  na TYM SAMYM mechanizmie: `AllergenSelectionField` (karta + arkusz, stan arkusza w środku) w obu
  miejscach; siatka 3 × 5 (`AllergenPicker`) usunięta — nie robić drugiego wyboru alergenów.
- Pory posiłków = `MealDayTimesCard` (oś dnia z kreatora: ikona pory, godzina na kapsułce, krótka nazwa),
  JEDNA w kroku 4 kreatora i w Ustawieniach → „Posiłki w planie” (osobny `MealTimesSheet` z listą
  wierszy usunięty 24.09.2026). Stuknięcie w posiłek = koło godzin w arkuszu `.medium`
  (`MealTimeEditorSheet`). Kreator trzyma godziny lokalnie i wysyła po utworzeniu gospodarstwa
  (tylko gdy różne od domyślnych), Ustawienia zapisują od razu.
- Filtry kategorii (23.09.2026): przycisk obok krzyżyka w liście kategorii → `RecipeCategoryFilterSheet`
  (ten sam układ co „Filtry”, akcent kategorii). Aspekty i reguły w `RecipeCategoryFacets` —
  liczone z NAZWY dania i składników (katalog nie ma tagów), sprawdzone na 495 przepisach
  z `prisma/catalog`; nowe słowo kluczowe = sprawdź pokrycie na katalogu, nie na oko. W obrębie
  aspektu LUB, między aspektami I. Wybór żyje w `RecipeFilterOptions.categoryFilters`, więc lista,
  stopka „Filtrów” i liczniki liczą się jedną regułą; `activeCount` (plakietka w nagłówku) liczy
  TYLKO filtry globalne, „Wyczyść” w każdym arkuszu czyści tylko swoje piętro (`resetGlobal`)
  i działa od razu, bez „Pokaż”.
- Karuzela na Przepisach: karta 330 pt (nie 420 z makiety) — zdjęcia są kwadratowe i przy 420
  `scaledToFill` skalował je do wysokości, przybliżając talerz. Kolejność kart jest ZAMROŻONA
  (`featuredOrder`) między ułożeniami (wyszukiwanie, filtry, dopasowanie, doba, katalog): ranking
  stawia ulubione na przodzie i polubienie przestawiało karty pod palcem — następne stuknięcie
  otwierało inny przepis. Serce na karcie to osobny przycisk NAD kartą (nie obrazek w niej).
- Serce ulubionych = `RecipeFavouriteButton` (szczegóły posiłku i karuzela). Wyskok serca przy dodaniu
  (`BurstHeart`) = TRWAŁY widok w nakładce + `keyframeAnimator` na liczniku dodań (każdy tor od
  `MoveKeyframe`, serce wchodzi od krycia 0), nie wstawiany widok z `Task.sleep` — wstawienie i uśpienie
  przycinały pierwszą fazę dodawania (runda 10). Stan LOKALNY, zapis do
  katalogu 650 ms po ostatnim stuknięciu, już po wyskoku serca — natychmiastowy zapis przeliczał
  pod arkuszem całą listę Przepisów w trakcie animacji (przycinało się na Macu). Zapis to WARTOŚĆ
  (`RecipeCatalogStore.setFavourite(recipeId:to:)`, no-op przy zgodnym stanie), nie przełączenie —
  przełącznik liczony od nieaktualnej kopii przestawiał serce w złą stronę. Arkusz szczegółów dostaje
  ŻYWY przepis z katalogu (`recipes.first { $0.id == … } ?? kopia`) i nikt nie podmienia po zapisie
  `selectedRecipe` / `detailTarget` — przypisanie otwierało zamknięty arkusz albo wpisywało stary
  przepis do nowego.
- Wjazd szczegółów posiłku jak wybór posiłku u Asystenta: `hasAppeared` w `.task` po 80 ms (klatka
  oddechu — w `onAppear` padało w klatce wstawienia i nic nie grało), zdjęcie osiada z 1,12, sekcje
  kaskadą (`smooth 0,55`, opóźnienie 0,10 + 0,05·n), serce i krzyżyk wchodzą z treścią; arkusz ma
  rogi 40 pt i KRYJĄCE tło prezentacji (`recipeDetailSheet()` w `RecipeDetail.swift`) we wszystkich czterech miejscach otwarcia — przy `.clear` na pierwszych klatkach wjazdu prześwitywała na dole biała kreska ekranu pod spodem (24.09.2026).
- Nagłówek „Filtrów” i filtrów kategorii = `RecipeFilterHeader`: `EditorialSheetHeader` z kafelkiem,
  zdaniem o zasięgu jako `subtitle` i „Wyczyść” obok krzyżyka. Linijka „Aktywne: …” pod spodem
  zniknęła w rundzie 9 („niepotrzebne”) — co działa, widać na kafelkach. „Wyczyść” obok krzyżyka
  (`RecipeFilterClearButton` — od 24.09 SAMA ikona w terakotowym krążku 36 pt, słowo tylko dla VoiceOver)
  mają też oba arkusze wykluczania (dział czyści swój dział, główny — wszystko) i wybór alergenów
  w Ustawieniach (zostają id alergenów nieznanych tej wersji — unia z `SettingsView`).
- „Wybierz przepis” w Planie (`PlanSlotPickerSheet`) i lista kategorii na Przepisach
  (`RecipeCategorySheetView`) to JEDEN układ z `RecipeListKit.swift` (runda 8, 23.09.2026 — Rafał:
  „żeby wszystko trzymało się kupy, nie było nic, co jest odrębnie nowe”): `RecipeListSheetTop`
  (nagłówek + `SCSearchField`, przypięte; BEZ pigułek z opcjami — runda 10: „od tego mamy filtry”,
  zawężanie tylko w `RecipeCategoryFilterSheet` pod przyciskiem filtrów w nagłówku),
  `RecipeListContextCard` (karta `scTileBg`: wiersz diety
  „Dieta wegetariańska · bez: gluten · ukrywa 12 przepisów” w kolorze diety i wiersz „Filtry
  z Przepisów” z „Wyczyść” — runda 9 zamiast kolorowego pudełka „Lista zawężona…”; na liście
  KATEGORII wiersza diety nie ma od rundy 12 — dieta to dopisek w podtytule nagłówka
  „118 przepisów · dieta wegetariańska” / „· bez Twoich alergenów”, gdy coś ukrywa; opis filtrów
  z `RecipeFilterOptions.summaryLabels`), `RecipeRowStack` z `EditorialRecipeRow` (`.chevron` otwiera przepis,
  `.selection(isOn:)` zaznacza — kółko `SCRadioMark` w terakocie jak w Ustawieniach, tło wiersza
  w tincie akcentu; wybrany przepis schowany przez filtry pokazuje stopka) i `RecipeListEmptyState`
  (runda 10: karta z kafelkiem POWODU w tincie — lupa, filtry, serce, dieta, ikona pory — tytuł, zdanie
  i akcja, która powód zdejmuje, jako `EditorialPrimaryActionButton`; druga akcja tekstem). W wyborze do
  planu: akcent i ikona PORY
  (`slot.cozyAccent`, `slot.icon`), data i godzina w `subtitle`, filtry kategorii `slot.baseCategory`
  bez aspektu „Pora w planie” (`RecipeCategoryFacets.facets(forPicking:slot:)`, arkusz filtrów
  z `slot:`; wartości dań z INNYCH kategorii liczone w aspektach kategorii pory —
  `RecipeFilterFactsCache.facetValues(for:in:)`); „Ulubione” to kafelek „Twoje przepisy” w tym arkuszu
  (`favouritesOnly:`, plakietka filtrów liczy go jako jeden filtr). Lista to ZAWSZE przepisy tej pory
  (`fits(slot)`) — „Wszystkie pory” usunięte w rundzie 10 („nie chcę jeść obiadu na śniadanie”).
  „Dla kogo” (`PlanAudienceChips`, w domu jednoosobowym jedno zdanie) stoi w STOPCE nad przyciskiem —
  tam, gdzie zapada decyzja. Filtry wyboru do planu są własne (nie z Przepisów).
- „Dodaj do planu” ze szczegółów (`AddToPlanSheet`, od nowa w rundzie 14 — „paskudny, zrób porządnie”):
  TYLKO znane klocki. Nagłówek = zdjęcie dania (`EditorialRecipeCover` 58 pt) + „DODAJ DO PLANU” + nazwa
  + fakty z ikonami (czas, kcal) + krzyżyk. „Kiedy” = tydzień w karcie dokładnie jak `EditorialWeekBar`
  (podpis „TEN TYDZIEŃ · …”, „Wróć do dziś”, strzałki 26 pt, przejeżdżające podkreślenie, przeciąganie
  w bok, miniony dzień przekreślony i nieklikalny, liczby rolują). „Posiłek” = od 24.09 kafle pór, układ wg liczby pór
  (`SlotTileLayout`: 1–2 poziome w rzędzie, 3 pionowe obok siebie, 4 = 2 × 2 poziome, 5–6 = 3 kolumny pionowe;
  ikona w kolorze pory, nazwa, godzina z `mealSlotSchedule` — i NIC więcej (runda 20: danie w kaflach „brzydkie”); podmianę mówi JEDNA karta „ZAMIENISZ · danie” ze zdjęciem nad zdaniem stopki;
  wybrany = `scChoiceSurface(.tile)` w `cozyAccent`) — lista wierszy z radiem odpadła („nie do końca mi się
  podoba”). „Dla kogo” = `PlanAudienceChips`. „Porcje” = JEDEN wiersz: „Porcje”, rolująca liczba, `SCStepper`. Stopka `scSheetFooter`: rolujące zdanie „Środa, 24 września · Obiad” (+ „dla całego domu”) i przycisk „Dodaj do planu” / „Zamień w planie” / „Już jest w planie”. Sekcje
  wjeżdżają kaskadą `scReveal` (`Components/SCReveal.swift` — wyniesione ze szczegółów posiłku), lista ma
  `scrollBounceBehavior(.basedOnSize)` (gdy się mieści, nie odbija). Karty w `clipShape` = `strokeBorder`,
  nie `stroke` (clip zjadał pół obwódki). `EditorialPrimaryActionButton` roluje tytuł (`numericText`) —
  działa tylko w animowanej transakcji.
- Ten sam przepis w tej samej porze dla drugiej osoby = SUMA audytoriów, a nie nadpisanie
  (`PlanAudienceChips.merged(_:with:members:)`, runda 10): pozycja planu to para (pora, przepis), więc
  zapis „posiłek1 dla user2” przepisywał „posiłek1 dla user1” i user1 zostawał bez jedzenia. Suma
  obejmująca cały dom zwija się do „Wspólne”. Obowiązuje w „Wybierz przepis” i w „Dodaj do planu”.
- Kalorie na Planie liczy się NA OSOBĘ (runda 9, 23.09.2026): pigułka nad menu sumuje dzień osoby
  z soczewki „…”, a przy „Cały dom” — tego, kto trzyma telefon (`nutritionPersonId`,
  `visibleTo(memberId:)` w każdej porze). Suma całego domu dodawała dwa różne obiady do jednego
  osobistego celu (~3000 kcal na osobę, która zje jeden). Arkusz „Cel dnia” (`PlanDayGoalSheet`
  z `people: [PlanDayPerson]`) ma przy wielu domownikach przełącznik osób obok krzyżyka
  (`PlanPersonSwitcher`: awatary, wybrana osoba z imieniem na tincie swojego koloru): dania, suma
  i CEL tej osoby. Cele domowników przychodzą z serwera w `households:memberPreferences`
  (`targets: {calorieGoal, macros}` — policzone w `toMemberContext`, BEZ sylwetki) →
  `HouseholdMemberPreferences.targets`. Domownik bez celu (albo bez makr) dostaje cel z domyślnej
  sylwetki — rocznik 2000, 70 kg, 170 cm, bez płci (BMR −78), aktywność 2–3 — w JEDNYM miejscu:
  `DailyNutritionTargets.forMember` (runda 17). Arkusz ma dla każdej osoby tę samą strukturę: tor
  legendy stoi zawsze (bez celu niewidoczny), miejsce na podpowiedź o makrach trzyma się, gdy
  potrzebuje jej ktokolwiek, przełącznik to SAME awatary (runda 19: imię pod ramę najdłuższego zostawiało pustkę — nie wracać do imienia; kapsuła nie zmienia
  szerokości), a podtytuł z imieniem przenika (`subtitleTransition: .opacity`), zamiast rolować litery. Przełącznik (runda 12, wróciła wersja z rundy 9 dopracowana):
  kompaktowa kapsuła OBOK krzyżyka (`accessory` nagłówka, runda 13: mniejsza — awatary 22 pt, wysokość 26, imię 12 pt) z obwódką w kolorze osoby,
  wybrana osoba rozwija imię na tincie (`matchedGeometryEffect`, sprężyna); podtytuł mówi, czyj to
  dzień („Twój dzień · 3 z 4 posiłków” / „Dzień: Ania · …”). Pełnoszerokościowe zakładki z rundy 11
  odpadły. Kalendarz NIE ma przełącznika — tylko „ja” (runda 11).
  Oś dnia dalej pokazuje dania wszystkich obok siebie — zmieniło się tylko to, co się sumuje.
- `DayPager` (runda 11): nowy dzień wchodzi do drzewa BEZ animacji, gdy strona jest niewidoczna
  (między zjazdem a wjazdem), a przewijanie ma `.id` dnia — pełny ↔ pusty dzień szarpał wjazdem.
  Powrót do bieżącego tygodnia w pasku dni = „↩ Wróć do dziś” (samo „DZIŚ” czytało się jak znacznik dnia).
- Asystent w nagłówku Planu = pigułka „✦ Ułóż” (`PlanAssistantPill`, soft, z podpisem), nie
  podświetlone kółko z iskierkami; karta pustego tygodnia w `PlanDayTimeline` = kafelek, „ASYSTENT”,
  tytuł, jedno zdanie i `EditorialPrimaryActionButton` (runda 9, „przerób na aktualne standardy”).
- Puste stany Zakupów (`ProductsView`, 24.09.2026 — „design jest stary, uspójnij”) stoją na `RecipeListEmptyState` (ma teraz opcjonalny `eyebrow`): tydzień bez planu = „LISTA ZAKUPÓW · Tydzień bez planu” + „Ułóż z Asystentem” (przełącza zakładkę i zamyka arkusz) i „Wróć do Planu”; plan jest, lista pusta = „Lista jest pusta” bez akcji; „Na dziś” bez produktów i otwarta rewizja bez nowych = ptaszek w szałwii („Na dziś masz wszystko” + „Pokaż całą listę”); pusta historia — ten sam klocek. Karta z koszykiem 78 pt i dwoma szarymi chipami usunięta.
- Kalendarz bez linii pod talerzykami (runda 9: „Tym kończysz dzień”, „Następny: …”, „Potem: …” —
  „tego nie potrzebujemy”; `CalendarDayLine`/`CalendarDayNote` usunięte, wysokość idzie na talerz).
  Przełożenie dania (stuknięcie talerzyka) ROLUJE cyfry i tekst (`.numericText()`): wielki wiersz
  ma tożsamość „danie / pustka” (`headlineKey`), nie po daniu — między daniami roluje ZAWSZE, także „Zjedzone” ↔
  „za 4 h” (runda 23: klucz cyfry/słowa przenikał to kryciem i „nie było naszej animacji”); kryciem tylko pusty dzień / pora;
  nazwa dania i nadpis („OBIAD · 14:00”) też rolują (nadpis przenika się tylko pora z godziną ↔ bez).
  Stuknięcie w talerzyk, który talerz pokazałby sam (następny za zegarem), ZDEJMUJE przypięcie.
- Wspólne kontrolki (runda 8): nagłówek arkusza = `EditorialSheetHeader` z opcjonalnym `icon`
  (kafelek `SCHeaderIconWell` w tincie akcentu), `accent` (kolor eyebrow) i `subtitle` — nie rysować
  nagłówka z kafelkiem ręcznie (stoją na nim filtry, lista kategorii, wybór do planu, dział składników,
  gospodarstwo). Pole szukania = `SCSearchField` (kapsuła 44 pt, krzyżyk, obwódka przy fokusie; przy
  fokusie z zewnątrz obwódkę podaje ekran przez `isActive`) — jedyny wyjątek to pływające pole
  rozmów Asystenta. Wybór „jedno z wielu” = `SCRadioMark` (obwódka + kropka), „wiele” = `SCCheckbox`.
  Podpowiedź szukania kategorii: `RecipesConstants.searchPrompt(for:)` („Szukaj w śniadaniach”, nie „w śniadania”).
- Po audycie spójności (runda 8, 23.09.2026, 26 punktów): akcja niszcząca = `SCDestructiveButton`
  (soft kapsuła w ciepłej czerwieni: wyloguj, usuń konto, opuść gospodarstwo, odłącz Cookidoo/Zdrowie);
  błąd przy polu = `SCInlineErrorText` (terakota, NIGDY `Color.red`, i bez „sprawdź połączenie” —
  sam skutek); zaznaczony chip/karta = `.scChoiceSurface` (`.chip`: pigułki filtrów, płeć/aktywność
  w Profilu i kreatorze; `.tile`: liczby `SCChoiceTile` — motyw, posiłki w planie, źródło kroków;
  bez gradientu i cienia); karty szczegółów
  posiłku = `scTileBg` + `scTileStroke` bez cienia; etykiety sekcji WSZĘDZIE 10,5 pt bold, tracking 1,4,
  `scFaint` (lista Ustawień, arkusze, grupy Asystenta, „Kroki”, „Dla kogo”). Asystent: nagłówki arkuszy
  (`AssistantSheetHeader`) rysuje `EditorialSheetHeader` (krzyżyk `SCSheetCloseButton`), tytuł zakładki
  to `EditorialPageHeader`, przycisk wysyłania „soft”. Świadomie zostały: kreski w historii i archiwum Zakupów (ten sam układ co ekran Zakupów),
  `ShoppingSheetHeader`.
- Ustawienia → Gospodarstwo (23.09.2026, trzy rundy tego samego dnia — „za dużo tekstu”, potem
  „znów pusto i smutno”): nagłówek z ikoną domu, nazwą, ołówkiem i jedną linijką „3 osoby · wspólny
  plan i lista zakupów”; domownicy: sama tożsamość — awatar, imię, plakietki „TY” / „WŁAŚCICIEL”
  (dieta i alergeny usunięte w rundzie 10: „to tu nie ma sensu”); zaproszenie (link jednorazowy, 7 dni)
  i „Opuść gospodarstwo” PRZYPIĘTE w stopce arkusza (`scSheetFooter`, runda 10) — od 23.09 zaproszenie
  to dwuwierszowy przycisk „Zaproś domownika · Link dla jednej osoby · ważny 7 dni” NAD „Opuść”. Wcześniej: nazwa w nagłówku
  z ołówkiem obok krzyżyka (`EditorialSheetHeader` ma opcjonalne `accessory`; zmienia właściciel
  przez `households:updateName`, pozostali dociągają ją po `membersChanged`/`UPDATE_NAME` odczytem
  `households:findById`), zaproszenie jako wiersz listy (link 7 dni), „Opuść” na dole. NIC więcej — Rafał:
  „tylko najważniejsze rzeczy”, bez powtarzania nazwy, liczników i objaśnień. „Czego nie jem” (wykluczone
  składniki + limit czasu na danie) USUNIĘTE: walidator planu i prompt dalej czytają te kolumny,
  więc każdy zapis diety wysyła `excludedIngredientIds: []` + `maxPrepTimeMinutes: null`,
  a `loadUserPreferences` jednorazowo czyści stare wartości na serwerze. Polityka prywatności
  nadal wymienia te dane — do zdjęcia w następnej wersji polityki (spiętej w 3 repo).
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
