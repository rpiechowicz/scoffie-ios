# Scoffie — iOS (SwiftUI)

Aplikacja iOS dla backendu `rpiechowicz/scoffie-backend`. Pełny kontekst projektu,
decyzje i stan prac: w repo backendu — `CLAUDE.md`, `docs/handover/2026-08-28-stan.md`,
`docs/handover/memory/`. Rozmawiamy po polsku, na „ty”.

> `AGENTS.md` (instrukcje Codexa) ma DOKŁADNIE tę samą treść co ten plik.
> Edytuj `CLAUDE.md`, a potem `cp CLAUDE.md AGENTS.md` w tym samym commicie —
> CI sprawdza, że są identyczne. Git nie zachowuje dowiązań, a ręczna kopia
> już się rozjechała: do 1.10.2026 Codex czytał tu instrukcje sprzed tygodnia.

## Prościej, „jak od Apple” (6.10.2026) — NADRZĘDNE wobec starszych zapisów niżej

Rafał: „bardzo chcę się wzorować na Apple — ładne, czytelne, ale funkcjonalne”. Audyt pokazał przekombinowanie
(76 arkuszy i zero nawigacji w głąb, własny pasek zakładek, ~950 stałych rozmiarów czcionki, teatr animacji),
runda 6.10.2026 zmieniła to w całej aplikacji. Gdy akapit niżej mówi coś innego — obowiązuje ten.
- **Arkusze**: najwyżej JEDEN arkusz + małe okno akcji (`Menu`, `confirmationDialog`, koło godzin na 1/3). Dalszy
  krok z wnętrza arkusza = PUSH w `NavigationStack` arkusza z systemowym paskiem („wstecz” + tytuł;
  `.scPushedPage(tytuł)` z `Components/SCPushedPage.swift` daje tło strony, pasek i tint terakoty), pierwszy ekran
  arkusza zostaje z `EditorialSheetHeader` + `.toolbar(.hidden)`. `task`/alert arkusza z pushami stawiać na
  `NavigationStack`, nie na pierwszym ekranie (inaczej anulują się pod wepchniętym ekranem). Klocek używany i w
  arkuszu, i na zwykłym ekranie (kreator) dostaje tryb `isPushed:` / `onEdit:`. Rafał LUBI arkusze — wiersz
  Ustawień dalej otwiera arkusz; zakazane jest piętrzenie. Kategoria Przepisów = push w stosie zakładki.
- **Najpierw komponent systemowy** (`TabView`, `Menu`, `Toggle`, `Stepper`, `navigationDestination`, `safeAreaBar`,
  `confirmationDialog`, `SFSafariViewController`); własny tylko z konkretnym powodem zapisanym tutaj.
- **Ruch mówi, że coś się ZMIENIŁO**, nie dekoruje otwarcia: bez kaskad wejścia, liczenia od zera, osiadania zdjęć,
  pisania gotowego tekstu. Animują się zmiany (porcje, zapis, odhaczanie, rolowanie cyfr przy zmianie).
- **Pasek nawigacji zakładek**: Plan, Dziś, Ustawienia i korzeń Przepisów mają `.toolbar(.hidden, for: .navigationBar)`
  (nagłówek rysuje treść). `NavBarHitTestPassthrough` USUNIĘTY 6.10.2026 — pod systemowym `TabView` przestał działać
  i pusty pasek zjadał stuknięcia w koszyk i „…” Planu; nie wracać. Pasek pokazują tylko wepchnięte ekrany.
- **Dynamic Type**: rozmiary z makiet przez `.font(.sc(size:weight:design:))` (`Components/SCDynamicType.swift`),
  NIGDY `.system(size:)` w nowym kodzie. Przy domyślnym rozmiarze tekstu = makieta co do punktu; większy rośnie
  krzywą najbliższego stylu systemowego (`SCDynamicType.style(for:)`), limit xxL (`SCDynamicType.cap`, to samo
  `.dynamicTypeSize(...)` na korzeniu dla stylów systemowych i `@ScaledMetric`). `Font.sc` liczy przy budowaniu
  widoku (typ zostaje `Font` — działa w `Text + Text` i `-> Text`), więc zmianę w trakcie łapie przebudowa pulpitu
  (`scRefreshesOnDynamicType()` w `DashboardView`). Tokeny Gotuj (`SCCookTextStyle.font`) też idą przez `.sc` —
  generator w scoffie-design. Wygląd sprawdzać też przy „Większym tekście” na xxL (ciasno: dok Gotuj, kapsuły,
  talerze, plakietki).
- **Zakładki**: Przepisy · Plan · **Pulpit** · Asystent · Ustawienia — systemowy `TabView` (akapit „Dolne menu”).
  „Pulpit” (6.10.2026 wieczór; wcześniej „Mój dzień”, „Dziś”) ma w pasku ZNAK SCOFFIE (`Assets.xcassets/ScoffieTabMark`, SVG-szablon z geometrii
  `SCScoffieMark.markPath`); pozostałe ikony podskakują przy wyborze (`symbolEffect(.bounce.down)` w `tabLabel`, licznik
  `bounces`) — niesprawdzone, czy systemowy pasek to pokazuje. Nagłówek ekranu zostaje „Dziś” / „Wczoraj” / „Jutro”.
  Plan = „co jemy w domu” (tydzień, cały dom, edycja, kalorie każdej osoby); Dziś = „mój dzień” (tylko moje posiłki,
  wczoraj · dziś · jutro, odhaczanie, Gotuj). Planowanie ma jedno miejsce: Plan.
- **Dziś** (dawny Kalendarz; `CalendarView` + `CalendarTodayHeader`, `DashboardTab.calendar`, ikona
  `fork.knife.circle`): duży tytuł „Dziś” / „Wczoraj” / „Jutro”, data słowami, szklane ‹ › i ↩ poza dziś; BEZ
  `EditorialWeekBar` (został w Planie i „Dodaj do planu”). Zakres wczoraj · dziś · jutro (`DayPager(datesViewModel:
  nil, range:)`, gest za krawędź wraca sprężyną). Start i nowa doba (`todayKey`: zegar strony, `scenePhase`, wejście
  na zakładkę) = dziś. Własny dzień, bez `DatesViewModel` — osobny tydzień Kalendarza z 4.10 (`calendarDatesViewModel`)
  USUNIĘTY. Tygodnie trzech dni wczytywane raz na dobę (`loadDayWindow`: sąsiedni pierwszy, oglądany ostatni — nasłuch
  socketu idzie za tygodniem oglądanego dnia). Pigułka = `PlanDayGoalBar(planned:)` w TYM SAMYM jednym wierszu co Plan (kcal + B/T/W, zjedzone; plan dnia
  bladą warstwą pod torami) — zdanie „Zjedzone X z Y kcal · w planie Z” USUNIĘTE 6.10.2026 wieczorem (Rafał: „kompaktowe,
  czytelne, w 1 wierszu”; dwa układy psuły przejście). Przejście Plan ↔ Pulpit = jeden komponent, który zmienia stan (Rafał 6.10.2026): menu, ZANIM
  przełączy zakładkę (wiązanie `selection` w `NavigationMenu`; „Zaplanuj” na Pulpicie woła `SCTabBarChrome.prepareGoalBarHandoff`
  sam przed `dashboardTab = .plan` — przygotowanie po fakcie w `onChange` USUNIĘTE: twarz dochodziła klatkę za późno
  i potrafiła utknąć do następnej wizyty), wkłada twarz wychodzącej
  pigułki (`PlanDayGoalFace` z `SCTabBarChrome.goalBarFaces`) do `goalBarHandoff[docelowa]`; pierwsza klatka nowej zakładki
  rysuje ją, potem pigułka zdejmuje ją JEDNĄ sprężyną (`PlanDayGoalBar.animation`, ta sama przy każdej zmianie liczb;
  sprężyna zmienia cel w locie, gdy zakładka dociąga dzień) — liczba i pasek każdej kolumny razem, BEZ opóźnień między
  kolumnami (restartowały ruch). Plan i Pulpit przyczepiają pigułkę jedną drogą (`PlanDayGoalBar.dock` w `safeAreaBar`). Nie wracać do dwóch
  układów ani do animowania wysokości szkła. Zakres wczoraj · dziś · jutro jest CELOWY — dalsze dni ogląda się i planuje w Planie. Pusta pora / pusty dzień dziś i jutro = „Zaplanuj” (pierwsza pigułka w kolorze pory + pusty talerz jako
  przycisk) → `SessionStore.planSlotRequest` (`PlanSlotRequest`) + `dashboardTab = .plan`; Plan zdejmuje prośbę,
  `DatesViewModel.show(day:)`, otwiera „Wybierz przepis” na tę porę („dla kogo”: `[]` = cały dom, `[ja]`, gdy ktoś
  inny ma w porze swoje danie); wczoraj — tylko podpowiedź „Zaplanujesz w Planie”.
- **Loader**: zimny start z pamięci podręcznej (katalog z pliku + co najmniej jedno danie bieżącego tygodnia z pliku,
  `loadStartupDataFromCache`) = `.ready` po miniaturach tygodnia (≤ 0,5 s), reszta `prepareStartupData` nad pulpitem;
  pierwsze 0,3 s procesu loader jest samym tłem; bez minimum 1,34 s i bez czekania na pełny obrót (zejście 0,25 s, znak
  dokręca w trakcie gaśnięcia). Pełna fala i pełny obrót TYLKO po logowaniu / kreatorze (`enterAppUnderLoader`,
  `loaderEndsOnFullTurn`). Kolejność i limity rozgrzewki zdjęć bez zmian (WatchdogTermination).
- **Przepisy**: kategoria = PUSH (`RecipeCategoryScreen`: systemowy pasek z dużym tytułem i „wstecz”; cały nagłówek
  sekcji to przycisk; ten sam pływający `RecipesSearchBar` z `searchPrompt(for:)` szuka w kategorii — przyczepiony
  tak jak na korzeniu, zmieniać RAZEM). Korzeń: `.toolbar(.hidden)` zamiast `NavBarHitTestPassthrough`; kapsuła
  `compactTitles[.recipes]` odkładana na czas kategorii; fraza korzenia nie przechodzi do kategorii. Pasek szukania
  na korzeniu i w kategorii = `recipesSearchDock` (jedna droga), stoi nad paskiem zakładek, który się NIE zwija.
  Zjeżdżanie paska szukania obok zwiniętej ikony (liczone z przewijania) USUNIĘTE tego samego dnia: iOS nie mówi, kiedy
  pasek się rozwija (np. stuknięciem w zwiniętą ikonę), i pasek szukania nachodził na zakładki. Krążek Filtrów BEZ `GlassEffectContainer` (w grupie był martwy
  pod systemowym `TabView`), plakietka wprost na krążku. Arkusz „Filtry” (6.10.2026 wieczór, po pięciu rundach podglądu
  w artefakcie — Rafał: „przekombinowane” → „za smutno” → „prościej, ale z kolorem”): w kategorii rodzaj dania =
  kółka ze zdjęciem dania NA STAŁE (`RecipeFacetPhotoGrid`: ≤ 5 w rzędzie, więcej — rzędy po 4 z KRÓTKĄ nazwą w jednej
  linii, `RecipeFacetOption.shortTitle` — wariant R1; śniadania bez krótkich nazw; etykieta zawsze „Rodzaj dania”), smak = dwa kafle ze
  zdjęciem (`RecipeTasteTiles`, drugie stuknięcie odznacza); czas = przełącznik Liquid Glass (`RecipeFilterSegment`, L2: tor-
  kapsuła i JEDNA szklana soczewka w kolorze akcentu pod przyciskami, przesuwana sprężyną z „rozciągnięciem” — keyframe
  `LensSquish`; bez wstawiania soczewki od nowa i bez szkła w etykietach przycisków); filtry WSZYSTKICH przepisów (G1): na
  górze kuchnia — 8 kółek ze zdjęciem (`cuisineSection`), w liście „Okazje i sezon” i „Cechy” zamiast „Więcej filtrów”;
  reszta = JEDNA lista jak Ustawienia iOS (`RecipeFilterListMenuRow` / `RecipeFilterListButtonRow`: pełny kolorowy
  kafelek ikony, wartość po prawej, wybrana w kapsułce): mięso / pora kategorii → `Pane.facet`, trudność i kalorie
  (progi 300–800) = systemowe menu, dieta → kafelki, „Bez składników” (strona `RecipeExcludePage` ma ten sam tytuł), „Więcej filtrów” (`Pane.more`: cechy, kuchnia,
  okazje — każda wpycha kafelki). Wykres kalorii (`RecipeFilterKcalChart`) USUNIĘTY. Kafelki i siatki TYLKO na
  podstronach — nie wracać z nimi na wierzch. Zdjęcia kółek i smaku (6.10.2026: „ciut większe”, „bardziej pasujące”):
  rozmiar z szerokości kolumny (po 4 w rzędzie ~68 pt, po 5 ~61 pt, smak 44 pt), a przepisy na zdjęciach wybrane RĘCZNIE
  z arkuszy miniatur katalogu — `RecipeFilterCoverPicks` (rodzaj dania × kategoria, smak, kuchnia, a od wieczora 6.10
  też kafelki podstron: diety, cechy, okazje i sezon, mięso w obiadach i kolacjach, pora przekąsek — bez „Ulubionych”
  i „Thermomixa”; po dwa: główny i zapas), automat `RecipeCoverPicker` tylko, gdy wybranego nie ma w puli albo ukrywa go profil. „Filtry” działają
  NA ŻYWO (bez szkicu i „Pokaż”), stopka „N z M przepisów” + tekstowe „Gotowe” (lupa odpadła). Filtry kategorii =
  sekcja „Filtrów”, gdy lista stoi w kategorii (ekran albo zakładka wyników, `scope`), bez kuchni i okazji kategorii;
  bez zakresu — wiersze „Filtry kategorii”. Podstrony Filtrów („Więcej filtrów”, Wyklucz składniki → dział) i filtry
  „Wybierz przepis” (`RecipePlanFilterPage`) = push z systemowym „wstecz” i „Wyczyść”. „Wyczyść” wszędzie =
  `RecipeFilterOptions.reset(in: scope)`; nagłówek wyników i karta kategorii = `summaryLabels(in:)` (z filtrami
  kategorii); plakietka = `activeCount(in:)`. `RecipeCategorySheetView` i `RecipeCategoryFilterSheet` USUNIĘTE.
  Wyłączone dopasowanie (dieta + alergeny) trzyma TYLKO do końca uruchomienia
  (`RecipePersonalization.restoreForThisLaunch` w `RecipeCatalogStore.init`); dopóki trwa — żeton `RecipeFitOffChip`
  „Bez dopasowania · Włącz” na Przepisach i wiersz karty w „Wybierz przepis”. Nigdy trwałe i niewidoczne.
- **Szczegóły posiłku mają WŁASNY `NavigationStack`** (`RecipeDetailView.body`, 6.10.2026 wieczór): „Kto ile je”
  (`portionsPage`, `.scPushedPage("Kto ile je")`, „Cofnij” w pasku, „Zapisz porcje” w stopce; pigułka ze strzałką ›)
  i pełne „Dodaj do planu” (`AddToPlanSheet(isPushed: true)`: tytuł i „wstecz” w pasku, nad treścią samo danie bez
  krzyżyka) to PUSH w arkuszu szczegółów — arkusza na arkuszu tu już nie ma. `onAppear`, `task` i okno „Gotujesz już
  inne danie” stoją na stosie, nie na pierwszym ekranie (`page`).
- **„Dodaj do planu”** w szczegółach z katalogu = systemowe `Menu`: „Dziś · pora” (tylko gdy pora jeszcze przed nami),
  „Jutro · pora”, „Inny dzień…” → `AddToPlanSheet` (push). Szybki zapis dla całego domu z porcjami ze steppera, szczegóły się
  zamykają, toast „Dodano do planu · Jutro · Obiad” z „Cofnij” (6.10.2026: `SCToast.action` — JEDNA akcja po prawej
  kapsuły, toast z nią trwa ≥ 5,5 s, a każda akcja ma własne `id` — dwa toasty o tej samej treści się NIE łączą; tylko przy
  NOWEJ pozycji, cofnięcie = `removeWeekSlot` tego przepisu i toast „Usunięto z planu”, ale tylko gdy wpis jest w stanie
  z chwili zapisu (`UndoStamp`: id, rewizja, osoby, porcje, odhaczenie — wszystko, bo odhaczenie nie podbija rewizji), inaczej „Nie cofam · Ktoś z domu
  zmienił już to danie”; serwer nie ma usuwania warunkowego (strict DTO — pole `expectedRevision` z develop iOS odbiłoby
  się od produkcji); dołączenie osób do dania i zamiana — bez „Cofnij”); reguły i zapis w `AddToPlanDraft` / `AddToPlanPortions`, wspólne
  z arkuszem — nie duplikować. „Zamiast: X” (cały dom) / „Jest już: X” (część domu) otwierają arkusz z `initialDate` /
  `initialSlot`; to samo danie = wyłączone „Już w planie”. Porcje w arkuszu stoją W TREŚCI pod „Posiłek”
  (`SCPortionKit`) — przycisk `chart.pie.fill` i arkusz porcji USUNIĘTE. Szczegóły posiłku otwierają się w gotowym
  stanie (bez `hasAppeared`, `detailReveal`, skali 1,12, wzrostu pierścieni, `CountingNumber`); animują się zmiany
  (porcje `DetailNutritionMotion.change` 0,8 s, cyfry `numericText` + `SCMotion.textRoll`, „mam w domu”, serce).
  `SCReveal` używa już tylko Gotuj.
- **Asystent**: przegląd propozycji dnia/tygodnia = JEDNA lista (akapit „Przegląd propozycji” niżej); SAMA otwiera się
  tylko karta OPTIONS. 👍 = sam kciuk (szałwia, `ThumbCheer`, haptyka) BEZ arkusza; 👎 = ocena od razu + PÓŁARKUSZ
  `AssistantSuggestionSheet` (`.medium/.large`, fokus pola → `.large`): „Słaba odpowiedź · Co nie zagrało?”, 4 powody
  bez opisów („Nie o to pytałem”, „Nietrafione dania”, „Za dużo tekstu”, „Za długo czekałem”), pole, „Wyślij”; po
  wysłaniu toast „Dzięki za podpowiedź”; „⋯” → „Co nie zagrało?” / „Popraw podpowiedź” tylko przy 👎 (zrzut
  `SCOFFIE_DEBUG_OPTIONS=podpowiedz`). Na żywo pisze
  się TYLKO szkic; gotowa odpowiedź będąca ciągiem dalszym widocznego szkicu domyka się w ≤ 0,6 s
  (`AgentRevealClock.finishWithin`), wszystko inne (`AgentRevealClock.whole`) stoi od razu w całości RAZEM z kartą
  i paskiem, jednym przenikaniem; odpowiedź, która szkicu nie kontynuuje, staje w JEGO miejscu po domknięciu szkicu
  (≤ 0,6 s). Nie wracać do pisania gotowej odpowiedzi ani do karty czekającej na koniec pisania. Nagłówek zakładki
  w trakcie tury = `.attentive` — kręci się JEDEN łuk w wierszu „myślę”. Zdanie „Możesz wyjść — wrócę z odpowiedzią.”
  prosi raz o zgodę na powiadomienia.
- **Wiersz listy = jeden klocek** (6.10.2026, artefakt „Ustawienia Scoffie”): `EditorialSettingsRow` i lista w Filtrach
  (`RecipeFilterListRowLabel`) mają te same wymiary — płaski kafelek `EditorialSettingsTileIcon` 30 pt (bez gradientu
  i poświaty, kolor w GŁĘBOKIM wariancie w obu motywach — `.environment(\.colorScheme, .light)` na wypełnieniu),
  tytuł 15 semibold, wartość 15 szara, wiersz 52 pt, kreska od tytułu (54 pt), strzałka 11 bold `scFaint`. W Ustawieniach
  każdy wiersz w SWOIM kolorze (Gospodarstwo indygo, Dieta szałwia, Posiłki masło, Asystent terakota, Powiadomienia
  koral, Wygląd lawenda `circle.lefthalf.filled`, Pomoc morska `questionmark`, Oceń róż `star.fill`, Prywatność szary
  `SettingsAccent.slate`), a arkusz bierze kolor wiersza; profil 56/17; wersja = podpis „Scoffie 1.0 (35)” pod
  „Wyloguj się” (wiersz „Wersja” i `EditorialSettingsInfoTile` USUNIĘTE).
- **„Twoje dane”** (`ProfileDetailsSheet`, 6.10.2026 wieczór — artefakt „Arkusze Ustawień”, sekcja 1, cztery rundy,
  „super, pasuje mi, koduj”; arkusze 2–8 z tego artefaktu czekają po kolei): nagłówek = PROFIL (`EditorialSheetHeader`
  z awatarem w `leading` i e-mailem w nowym slocie `detail` pod tytułem; ołówek obok krzyżyka → alert „Imię” z polem,
  jak nazwa gospodarstwa; w trybie `isPushed` ten sam profil stoi na górze treści). Na górze WYNIK: kcal na utrzymanie
  (`numericText`) i BMI na skali ocen (`BMIScale`: progi 18,5 · 25 · 30 na 15–35, znacznik jedzie sprężyną). Sylwetka =
  cztery `EditorialSettingsRow` (płeć indygo, rok morska, wzrost szałwia, waga róż, glif `chevron.up.chevron.down`,
  wartość w terakocie, gdy jej wybór jest otwarty) → MAŁY ARKUSZ na 1/3 (`ProfileFieldPickerSheet`, `.fraction(1/3)`
  jak koło godzin) z `presentationBackgroundInteraction(.enabled(upThrough:))`: reszta NIE gaśnie i przyjmuje dotyk —
  wynik zmienia się na oczach, a stuknięcie w inny wiersz podmienia wybór bez zamykania (`picking` / `pickerField`);
  zamyka krzyżyk, przeciągnięcie albo ten sam wiersz, zapis od razu (bez „Gotowe”). Płeć = kafle z „Nie podaję”,
  rok i wzrost = koło, waga = koło kilogramów i dziesiątych jak w Zdrowiu (dokładność 0,1 kg jak dawne pole).
  „Nie podaję” wybrane w TYM otwarciu = `saveProfile(clearSex: true)` → jawny `null` (pominięte pole serwer zostawia
  i stara płeć wracała z `users:me`); `users:me` z `sex: null` kasuje płeć zapamiętaną na innym telefonie
  (`persistProfileFields`), a niepotwierdzone skasowanie (zapis padł) leży w `settings.profile.sexClearPending`
  i `saveProfile` ponawia je przy każdym zapisie, aż serwer potwierdzi (inne pola leczą się same — zapis wysyła je
  zawsze; do tego czasu `users:me` nie wpisuje starej płci). Ołówek i „Usuń konto” przy otwartym małym arkuszu: najpierw zjazd, okno
  z `onDismiss` (`pendingAlert`) — alertu z widoku prezentującego arkusz system nie pokaże. Zapis przy zejściu
  (`onDisappear`) w OBU trybach — przeciągnięcie w dół anulowało debounce. Imię tnie `SessionStore.limitedDisplayName`
  (punkty kodowe, jak `@MaxLength` serwera). `SCWheelPicker` (`Components/`) = `UIPickerView` z kolumnami — WŁASNY,
  bo dwa `Picker(.wheel)` obok siebie nakładają obszary dotyku (UIKit liczy je z naturalnej szerokości koła); wartość
  wchodzi, gdy koło stanie; koło przestawia się TYLKO przy zmianie z zewnątrz (`shownRows`, nie `selectedRow` — to
  cofało wybiegające koło), a przycięty zapis (250 kg zeruje dziesiąte) dociąga w `didSelectRow`. Treningi =
  `SCIconTilePicker` (`Components/`, wariant A „Kafle”): ikona w kółku w kolorze wysiłku (0–1 indygo `sofa.fill`, 2–3
  szałwia, 4–5 terakota, 6+ `SCPalette.Toast.ember`), wybrany = pełne kółko (głęboki wariant) + szklana soczewka
  przesuwana sprężyną z `LensSquish` (wspólne z `RecipeFilterSegment`) + podskok ikony; BEZ podpisu z nazwą poziomu
  („to lekko aktywny usuń”). Pola tekstowe wzrostu/wagi i ich drafty USUNIĘTE. Kreator (krok 1–2) świadomie bez zmian.
- **Ustawienia**: zgoda na powiadomienia NIGDY przy starcie — `NotificationPermission.requestIfNotAsked()` w kontekście:
  Ustawienia → Powiadomienia („Włącz powiadomienia” / „Wyłączone w ustawieniach iOS” + „Otwórz ustawienia”), po wysłaniu
  zaproszenia domownika (`SCShareSheet(message:)`, `completed`), po dołączeniu z zaproszenia (pulpit odsłonięty,
  `asksNotificationsOnReveal`), przy „Możesz wyjść” u Asystenta i po PIERWSZYM daniu zapisanym w planie
  (`NotificationPermission.requestAfterPlanning`: „Wybierz przepis” — nowe danie — i „Dodaj do planu”; tam PRZED toastem,
  żeby okno systemu nie zjadło czasu na „Cofnij”); wiersz i arkusz
  czytają stan przy wejściu, otwarciu i powrocie na wierzch; przełączniki = systemowe `Toggle`. Push w arkuszach:
  Dieta → Alergeny (`AllergenSelectionField(onEdit:)`, `AllergenPickerSheet(isPushed:)`; w kreatorze dalej arkusz),
  Prywatność → Polityka / Regulamin / Pobierz moje dane (`LegalDocumentPage`, `DataExportPage`), Asystent i plan →
  Plany → dokumenty (`PlansSheet(isPushed:)`), „Twoje dane ›” (`ProfileDetailsSheet(isPushed:)`, zapis przy zejściu),
  Cookidoo → Thermomix. „Pomoc i FAQ” = `SCSafariView` z `https://scoffie.app/support/` (FAQ w kodzie USUNIĘTE — treść
  żyje w scoffie-web `src/pages/support/index.astro`). „Oceń aplikację” = `?action=write-review` w App Store, nie
  `requestReview()`.
- **Arkusze Ustawień** (6.10.2026 wieczór, artefakt „Arkusze Ustawień”, cztery rundy): Gospodarstwo — podtytuł samo
  „N osoby”, plakietki „Ty”/„Właściciel” w tincie, „Opuść gospodarstwo” NA KOŃCU listy (nie w stopce), nazwa domu 2–50
  znaków wszędzie (`SessionStore.householdNameLengthRange`). Dieta — KALORIE NA GÓRZE (Rafał), potem makro, cel, dieta,
  alergeny; listy celu i diety z kółkiem (dawny układ wygrał z menu), podpisy w jednej linii (kopie lokalne, `UserGoal`/
  `DietPreference` bez zmian — kreator); podpowiedź „Dla celu „…” wychodzi N kcal · Ustaw” w karcie kalorii.
  Powiadomienia — główny przełącznik jako wiersz (bez zgody „Włącz powiadomienia” / „Wyłączone w ustawieniach iOS ·
  Otwórz”), kanały „Dla Ciebie” / „Od domowników”. Wygląd — dawne trzy karty z podglądem, po polsku (Automatycznie,
  Jasny, Ciemny; `AppTheme.system.title` = „Automatycznie”). Posiłki w planie — JEDNA karta: pionowa oś dnia (godzina
  18 pt, kółko pory na linii, pełna nazwa), wyłączone pory na swoim miejscu z „+ Dodaj”; godzina = `MealTimeEditorSheet`
  na 1/3 z akcją „Wyłącz”/„Dodaj” obok krzyżyka; „Wyłącz” też przesunięciem (oś to `List` w karcie dla `swipeActions`);
  pozioma oś (`MealDayTimesCard`) została TYLKO w kreatorze — w Ustawieniach była nieczytelna. Asystent i plan — karta
  stanu na górze (`PlanStatusHero`: duża liczba pozostałych wiadomości, kropki w próbie, pasek po domownikach w planie),
  w próbie plany od razu w arkuszu (trzy kafle + „Wybierz X · cena”, zakup przez wspólne `PlanPurchase` z `PlansSheet`),
  płacący: „Zmień” → `PlansSheet` + „Zarządzaj subskrypcją ↗”; domownik: „Kto opłaca”. Prywatność — przypięty nagłówek,
  „Regulamin” (nie „Warunki korzystania”), wersja z `LegalDocMeta` jednym podpisem; „Pobierz moje dane” — karta pliku,
  „Zapisz albo wyślij” (`ShareLink`) w stopce. Wszystko niekompilowane w chwili zapisu (Linux) — sprawdzić na Macu.
- **Zakupy**: historia → miesiąc → lista = push w arkuszu Zakupów (`ShoppingHistoryRoute`, `ShoppingHistoryPage`,
  `ShoppingHistoryMonthPage`, `ShoppingArchivePage`, `pruneHistoryPath`); „Usuń całą historię” tylko w „…” Historii.
- **Gotuj**: JEDNA reguła stuknięcia w timer w doku (`CookDockTimer.dockTapAction`) — „do włączenia” = Start, każdy inny
  stan = arkusz Timery; pauza, wznowienie, „+1 min” (timer po czasie, wyciszony), „Pomiń” i „Gotowe” WYŁĄCZNIE
  w arkuszu. Kapsuła = jeden `Button`, bez menu przytrzymania (i bez `afterMenu`); glif w pierścieniu = stan, ▶ tylko
  przy „do włączenia” w parze, pojedyncza ma pigułkę „▶ Start” tylko przy „do włączenia”. Plakietka: rysunek 28, dotyk
  44 (`CookTimerBadge.touchHeight`). Ekran końca timera: na dole [„…” = systemowe menu: +2 / +5 min z nagłówkiem
  „Jeszcze chwilę? Było N min”, „Tylko wycisz” (wszystkie)] [„+1 min”] [„✓ Gotowe” w pełnym kolorze timera] — bez
  „Wycisz” w rogu i bez panelu „Jeszcze chwilę?”. Zrzut `gotuj-wyciszony`. Odstępy rzędu = tokeny
  `SCCook.Spacing.alarmActionGap` (10) i `alarmExtendInset` (22) — scoffie-design #25/#26 (6.10.2026); nieużywane
  `height.cookAlarmExtend` i `radius.cookAlarmPanel` usunięte z tokenów.

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
- Przegląd propozycji dnia/tygodnia (6.10.2026, „jak od Apple”) = JEDNA przewijana lista
  `AssistantProposalReviewSheet` (model `ProposalReview`), NIE strony „stories”. Nagłówek `EditorialSheetHeader`
  („PROPOZYCJA DNIA” / „PROPOZYCJA TYGODNIA”, dzień albo zakres tygodnia, akcent = `status.tint`), w domu z kilku osób
  `ProposalPersonFilter` („Wszyscy · Ty · Ania”, start „Wszyscy”), sekcje = dni (dzień = jedna sekcja bez etykiety),
  wiersz = pora z ikoną w kolorze pory · miniatura 44 · nazwa (2 linie) · kcal · „dla kogo” (`ProposalAudiencePill`,
  gdy nie cały dom) · zmiana wobec planu W WIERSZU: „Zamiast: …” (przekreślone; kilka nowych dań w jednej porze dzieli
  usunięcia tej pory PO KOLEI — jedno na danie, nadmiar ostatniemu — zamiast powtarzać to samo „Zamiast: X”; przy filtrze
  osoby usunięcia schowanego dania przechodzą na widoczne nowe danie tej pory albo stają osobno — `Row.absorbed`,
  `ProposalReview.filtered`), usunięcie
  z powodem („Usunięte · powtórka”), „Nowe” TYLKO gdy propozycja coś zostawia/usuwa. Filtr osób ŚWIADOMIE startuje od
  „Wszyscy” (6.10.2026): zapis obejmuje cały dom, więc najpierw widać całą propozycję. Usunięcia z dni bez nowych dań = własna sekcja.
  „Zamień to danie” = „…” (`Menu`) w wierszu + to samo pod przytrzymaniem, akcja po 0,35 s (po zamknięciu menu), tylko
  PENDING; zdanie bez zmian („Zamień w tej propozycji …: X. Pokaż 3 inne dania na tę porę do wyboru.” → serwer oddaje
  OPTIONS → „Wybieram: …” → ta sama propozycja z nowym daniem). Stopka `.scSheetFooter`: zdanie stanu
  (`ProposalEndCopy`) + JEDEN przycisk (zapis w szałwii `ProposalAcceptButton` → „Zapisuję…” / „Wstawiam do planu…” →
  „Jest w planie” + „Otwórz plan”; bez zapisu „Napisz, co zmienić”); zapis NIE zamyka arkusza; po zapisie ptaszki na
  miniaturach + haptyka; pod listą `ProposalRegenerateLink`. Bez kaskad przy wejściu. Stuknięcie w danie NIE otwiera
  szczegółów (`RecipeDetailView` zakłada bycie arkuszem). Karta w rozmowie: dotknięcie dania / „Przeglądaj dania”
  otwiera listę (od dotkniętego dania, `ProposalReviewFocus`). Świeża propozycja dnia/tygodnia NIE otwiera przeglądu
  sama (zasłaniał odpowiedź); sama otwiera się tylko karta OPTIONS — arkusz „stories” (`AssistantOptionsStorySheet`)
  został TYLKO dla wyboru z 3 dań. USUNIĘTE i nie wracać: tryb `.review` arkusza „stories” (`OptionsStoryMode`,
  `ProposalStory`, `ProposalStoryContext`), strona końcowa z `ProposalHero` / `ProposalRecap`, `ProposalPersonSwitcher`,
  filtr pory/dnia, półarkusz „Co się zmieni” (`AssistantPlanChangesSheet`, `ProposalChanges`) i wiersz „Co się zmieni”
  w karcie, `ProposalAutoPresent`, `AssistantOptionsCarouselCard`. Zrzut: `SCOFFIE_DEBUG_OPTIONS=propozycja`
  (`ProposalReviewDebugScreen`: lista, po 4 s „zapis”).
  Karta propozycji w ROZMOWIE (27.09.2026, „tekst się psuje”): data/zakres tygodnia stoi we własnym wierszu pod
  nadtytułem z ikoną kalendarza (`AssistantCardHead(detailBelow: true)`), nie w jednym wierszu z plakietką stanu
  (`lineLimit(1)` ucinał datę); inne karty dostają meta obok nadtytułu tylko, gdy cała się mieści (`ViewThatFits`).
  Pod „Przeglądaj dania” NIE ma wiersza „3 posiłki · 1460 kcal · zostaje 640” / „Śr. … kcal dziennie” — nie wracać.
  Nazwa dania w `AssistantMealRow` ma do dwóch linii zamiast ucinania. „Kto co je” (27.09.2026): klocki
  w `AssistantProposalPeople.swift` — `ProposalAudience` („Cały dom” / „Ania i Ty”, w domu jednoosobowym nic),
  `ProposalAudiencePill` (na `PlanWhoBadge` z Planu), `ProposalPersonFilter`; w karcie w rozmowie przy porze dopisek
  z imieniem, gdy danie NIE jest dla całego domu.
- **Kontrakt kart asystenta**: `sh Scripts/card-contract-check.sh` — kompiluje DTO kart razem
  z wzorcem odpowiedzi serwera i sprawdza, czy wszystko się dekoduje. Jedyna automatyczna
  kontrola w tym repo (nie ma targetu testów) i jedyna rzecz, która potrafi zepsuć się CAŁKIEM
  po cichu: zmiana nazwy pola w backendzie nie da błędu, tylko karta zniknie z ekranu. Wzorzec
  odświeża `scripts/dump-card-fixtures.ts` w backendzie.
- **Tryb Gotuj** (E4 od 1.10.2026, `docs/workstreams/gotuj/README.md`, wygląd: scoffie-design `docs/GOTUJ.md`):
  liczby wyglądu biorą się z `scoffie-design/tokens/cook.json` — `Components/SCCookTokens.swift` (`SCCook.*`) jest
  WYGENEROWANY (`npm run build` w design repo, kopia bajt w bajt, `npm run check:ios`); nie edytować ręcznie, nowa
  wartość = najpierw token. Logika w `Models/Cook/` (scenariusz, ilości §5.4, `{count:…}`, sesja i dok) tylko na
  Foundation — `sh Scripts/cook-logic-check.sh` na scenariuszu kotleta (`Scripts/CookLogic/kotlet.json`, odświeżany
  `make-fixture.mjs`). Scenariusz wskazuje składniki po `ingredientId`, które ma TYLKO szczegół przepisu —
  `CookScenarioStore` bierze `recipes:cookScenario` + `recipes:findById` i trzyma paczkę offline (przycisk „Gotuj”
  tylko, gdy paczka jest i `Recipe.cookScenarioVersion` się zgadza). Sesja (`CookSessionStore`) jedna, per konto+dom,
  timery jako DATY KOŃCA; każdy timer przepisu ma SWÓJ kolor (`CookTimerAccent.forTimer` po miejscu w scenariuszu:
  terakota, szałwia, indygo, róż, morska, lawenda, masło) — ten sam przed startem, w trakcie, po czasie i na alarmie
  (runda 3; dawne „terakota, a gdy zajęta — szałwia” odpadło). Widok (`Views/Cook/`)
  to `fullScreenCover` nad pulpitem (`ScoffieApp.dashboard`); wejścia idą przez `SessionStore.startCooking` /
  `resumeCooking`, które najpierw zamykają arkusze (ten sam ruch co przepis z linku). Timery i Składniki to ARKUSZE
  systemu (runda 3: karty rozwijane z doku „trochę się bugowały”) — jeden `.sheet(item:)` w `CookModeView`
  (`CookSheet`); Składniki na pół ekranu, przewijanie rozwija na cały (`.presentationContentInteraction(.resizes)`),
  Timery na wysokość treści (pomiar jak `PlanDayGoalSheet`); dzwoniący timer zamyka otwarty arkusz, bo widoku
  spod arkusza nie da się położyć nad nim. Koniec timera: pełny ekran także po „Wstrzymaj” (store sam
  otwiera tryb), a od rundy 11 ALARM SYSTEMOWY AlarmKit (`CookAlarmScheduler`, wariant B z §8.4): każdy biegnący,
  niewyciszony timer ma alarm na GODZINĘ KOŃCA (`Alarm.Schedule.fixed`, BEZ odliczania — AlarmKit z odliczaniem
  wymaga rozszerzenia widżetów, bez niego „system może zdjąć alarm i nie zadzwonić”), id z sesji + timera + końca,
  uzgadniany przy KAŻDEJ zmianie sesji (`syncSystemAlarms` w `update`/`start`/`end`/`clearCache`). Dźwięk alarmu
  systemu, dzwoni mimo wyciszenia i Focus, pełny alert na ekranie blokady; zgoda przy pierwszym starcie timera
  (`NSAlarmKitUsageDescription`). „Zatrzymaj” na alercie = „Wycisz” w aplikacji (`acknowledgeSystemAlarm`, tylko
  przy tej samej godzinie końca), ekran końca timera nie gra swojego 1005, gdy dzwoni system. Bez zgody — dawna
  droga: powiadomienie w tle (`CookTimerNotifications`) i 1005 w aplikacji. Live Activity (E5, 1.10.2026): target
  `ScoffieCookActivityExtension` (folder `ScoffieCookActivity/`, iOS 26.0, App Group `group.app.scoffie.ios`), JEDNA
  aktywność na sesję (`CookLiveActivity` w aplikacji, wariant B z §8.4): rusza z pierwszym krokiem, aktualizuje się przy
  każdej zmianie sesji (ta sama `syncSystemAlarms`), kończy na zakończeniu / „Zakończ” / wylogowaniu; odliczanie rysują
  widoki czasowe (`Text(timerInterval:)`, `ProgressView(timerInterval:)` — bez aktualizacji co sekundę). Typy wspólne
  dla obu targetów leżą w `Shared/` (osobna synchronizowana grupa w OBU targetach; każdy typ `nonisolated`, bo
  rozszerzenie nie ma domyślnej izolacji MainActor; bez `SCPalette`/`SCCook` — rozszerzenie ich nie ma): stan
  `CookActivityAttributes` (krok, „Dalej: …”, do dwóch kapsuł doku z kolorem 0xRRGGBB z ciemnego wariantu palety),
  `CookAlarmMetadata`, `CookActivityImage` (miniatura 144 px w App Group — rozszerzenie nie sięga do sieci) i przyciski
  `CookActivityIntent` (`LiveActivityIntent`: „Dalej →”, „+1 min”, ▶ timera, który czeka) — wykonuje je APLIKACJA przez
  `CookActivityBridge` → `CookActivityCommands` (rejestrowane w `AppDelegate`; po wybudzeniu w tle sklep sesji wstaje
  z pliku, `CookSessionStore.forIntent`). Intencja CZEKA na koniec polecenia (`CookActivityBridge` jest async,
  `CookLiveActivity.settled()` + `CookAlarmScheduler.settled()`) — runda 12: aplikacja obudzona przyciskiem na ekranie
  blokady usypiała zaraz po `perform` i krok dochodził do Live Activity z opóźnieniem. Wygląd z makiet DC3/DC5,
  MN4/MN6, ER1–4, LK0–3 (`CookActivityLook` — stałe z makiet, jeszcze nie tokeny): ekran blokady i (od rundy 12)
  rozwinięta wyspa mają JEDEN rząd — zdjęcie w pierścieniu kroków 44, „KROK…” + tytuł w jednej linii (w wyspie region
  `.center`), „Dalej” 44 — a pod nim sam stan (kafle 60 pt); tytuł POD nagłówkiem 48 pt przekraczał sufit wysokości
  wyspy (~160 pt) i dół był ucięty — nie wracać. Kompakt/minimal — pierścień timera, gdy działa (D25). Stuknięcie =
  `scoffie://gotuj` (`DeepLink.cooking`; przed końcem startu `cookingResumeRequested` → `resumeCookingIfRequested`)
  → `resumeCooking(instantly: true)`: tryb, który już stoi na ekranie (`CookSessionStore.isOnScreen`), ZOSTAJE —
  `dismissPresentedScreensAnimated` zamykał go razem z arkuszami i wjeżdżał od nowa, a spod niego mignął Kalendarz;
  wstrzymany pokazuje się bez przenikania (`takeInstantPresentation`). Szablony Xcode
  (widżet ekranu głównego, Control, intencja konfiguracji) USUNIĘTE — nie wracać. Zrzuty:
  `SCOFFIE_DEBUG_OPTIONS=gotuj|gotuj-krok|gotuj-dwa|gotuj-jeden|gotuj-pauza|gotuj-timery|gotuj-skladniki|gotuj-kroki|gotuj-alarm|gotuj-alarm-dwa|gotuj-wyjscie|gotuj-koniec`.
  Zdjęcie nagłówka (`CookHeaderPhoto`) leży w TLE pustej ramki, a treść przewijania ma `containerRelativeFrame(.horizontal)`
  — `scaledToFill` w samej ramce wysokości zgłaszał szerokość kadru (~580 pt) i tekst uciekał za lewą krawędź („bez
  marginesów”, 1.10.2026). Ruch (`CookLook.swift`): teksty `cookRoll` (`SCMotion.textRoll`), zegary `cookTicking`
  (0,3 s), łuki timerów dojeżdżają liniowo przez sekundę, wejście ekranów `cookReveal` (= `scReveal`), zmiana kroku =
  wszystkie teksty kroku rolują się w miejscu (runda 9 — dawny wjazd opisu z boku odpadł, niżej).
  Wejście z Kalendarza (D23, EC41): na talerzu „play” w PRAWYM dolnym rogu, gdy danie ma paczkę scenariusza
  (`CalendarPlateCooking.ready`) — TYLKO dziś (D58, 4.10.2026: „nie ma sensu gotować na jutro / wczoraj / przyszły
  tydzień”; szczegóły posiłku z planu tak samo, z katalogu zawsze, wstrzymane wznawialne w każdy dzień), każda pora
  (Rafał: „nie trzymaj się czasu gotowania”); pełna terakota
  z aureolą, gdy talerz „woła” (pora gotować / jeść / wstrzymane), poza tym „soft”. Pieczątka odhaczenia przeszła na LEWY dół i stoi TYLKO tam, gdzie da się odhaczyć (dziś i wstecz; 4.10.2026: „bez sensu na przyszłym tygodniu”); ptaszek TYLKO przy zjedzonym,
  „następne” = sama obwódka w kolorze pory (4.10.2026: „nie dawaj checku w kolorze”, `CalendarMealCheck`). Po „Wstrzymaj” talerz tego wpisu
  planu (przepis + dzień + pora) to PS1 (`.paused`): pierścień kroków zamiast obręczy pory, „OBIAD · GOTUJESZ”,
  „Krok 8 z 12” w terakocie i tykające pigułki trwających timerów zamiast czasu i kcal.
  Runda 2 testów (1.10.2026): dok stoi jak dolne menu aplikacji (wyspa 60 pt, 20 pt od boków, na krawędzi
  bezpiecznego obszaru; powierzchnia `cook.dockSurface` — w jasnym motywie ciepła biel, bo płótno = tło strony).
  Timery w doku (4.10.2026, druga runda): najwyżej DWIE pełne kapsuły (pojedyncza / para, `dockCapsules` limit 2),
  a KAŻDY kolejny timer = `CookTimerBadge` w rzędzie nad nimi (miejsce dawnej „+N”, `Height.overflowTab`): pierścień
  w kolorze timera + „12:04 · Ziemniaki”, po czasie na pełnym kolorze, „do włączenia” = ▶ + warunek startu (stuknięcie
  włącza; reszta stanów otwiera Timery); rząd przewija się w bok. Zwarte kapsuły po równo (pierwsza runda tego dnia)
  ODPADŁY — przebudowywały parę przy trzecim timerze, czwarty się nie mieścił, trzeciego nie dało się włączyć; nie
  wracać (tokeny `cookTimerCapsuleCompactMin`/`cookTimerTimeCompact` w scoffie-design są nieużywane).
  Porcje sesji co 0,5 (`CookSession.portions: Double`, 0,5…12, `clampPortions`; serwer — ocena i wpis „ugotowane” —
  dostaje całe w górę); teksty przez `CookPortionsText` („na 1,5 porcji”). Stopka powitania: odstępy 12 między kaflami.
  Dawniej — kapsuły: najwyżej DWIE (`CookSession.dockCapsules` — dwa najdawniej włączone timery, wolne miejsce bierze timer
  do włączenia, też od najstarszego: nowy NIE wypycha kapsuły, która już stoi, tylko idzie do plakietki — runda 5,
  „nie powinien 1 przesuwać”; timer PO CZASIE stoi w doku zawsze; runda 3 cofnęła trójkę), w kolejności kroków, nowa
  wjeżdża z boku, po którym staje; stuknięcie w kapsułę: „do
  włączenia” = Start, reszta = arkusz Timery (6.10.2026; dawny pierścień-przycisk w parze odpadł), „do włączenia” zawsze z warunkiem startu (D37). Arkusz Timery = jedna lista bez
  sekcji (`timerLineup`) — start ani pauza nie przestawiają timerów. Łuki timerów ubywają zgodnie ze wskazówkami
  zegara. Pierścień kroków 36 pt jak krzyżyk (`scSheetIconSurface`): pełne zaokrąglone odcinki odsłaniane KLINEM
  od środka (`CookStepArcs` + `CookStepWedges`) — runda 2 liczyła łuki z okrągłymi końcami i przy każdym kroku na
  końcach odcinków wyskakiwały kropki („progress przeskakuje”).
  Runda 3: JEDEN ekran trybu (`CookScreen`) na powitanie, kroki i koniec — zdjęcie, krzyżyk i przewijanie są te
  same, zmienia się treść pod zdjęciem (`CookWelcomeContent` / `CookStepScene` / `CookFinishContent`: stara gaśnie,
  nowa wchodzi kaskadą), stopka (`CookWelcomeFooter` / `CookFinishFooter` w `safeAreaInset`) i dok; pierścień
  kroków obok krzyżyka tylko w krokach. Nie wracać do osobnych ekranów etapów — krzyżyk wjeżdżał od nowa.
  Runda 4: timer do włączenia stoi w doku od SWOJEGO kroku dalej — pominięty przy „Dalej” nie znika (dawniej czekał tak
  tylko „Gdy woda zawrze”), chowa się dopiero po cofnięciu przed jego krok; niepotrzebny odprawia „Pomiń”
  (`CookSession.skipTimer`: wiersz arkusza Timery; menu przytrzymania kapsuły usunięte 6.10.2026) — stan `skipped`, nie „zrobiony”: wraca
  jako „do włączenia”, gdy użytkownik znów stanie na jego kroku (`restoreSkippedTimer`, runda 5 — przypadkowe
  „Pomiń” gubiło timer do końca gotowania). Dok ma STAŁĄ wysokość — puste miejsca na
  plakietkę, kapsuły i wyspę (`spacing.cookDockReserve` 162): wcześniej rząd kapsuł wchodził do `VStack` nad wyspą,
  dok rósł, a wyspa jechała inną krzywą niż kapsuły i podskakiwała — nie wracać. Kapsuła to JEDEN układ dla pojedynczej
  i pary (`CookTimerCapsule`: pierścień rośnie i dostaje glif, pigułka gaśnie, czas zmniejsza SKALA, nie krój) — `switch`
  na układzie podmieniał treść i przeskakiwał. Zamiast „+N” plakietka nad kapsułami (`CookOverflowTab`,
  `CookSession.dockOverflow`): znaczki stanu ukrytych timerów (`CookTimerMark`) + JEDNO krótkie zdanie bez powtórzeń
  (runda 5: „+2 · 2 trwają”): jeden — „Ziemniaki · 12:04”, „W piekarniku · włącz”; kilka w tym samym stanie — „2 timery
  trwają”; różne — „3 timery · 1 do włączenia”. Tarcza końca timera = stoper (`CookAlarmBezel`: 60 kresek,
  kropka ze smugą okrąża ją raz na minutę, kąt rośnie bez końca), w krążku trzy krótkie wiersze w szerokościach
  wpisanych w koło (`size.cookAlarmTextWidth` / `cookAlarmCounterWidth`, dłuższe maleją), „było 10 min” w nagłówku
  menu „…” (panel „Jeszcze chwilę?” usunięty 6.10.2026). Składniki w DZIAŁACH sklepu (`CookIngredientAisle`, kolejność `ProductConstants.isDepartment` —
  jak Zakupy i szczegóły przepisu): szuflada powitania i „Cały przepis” działami (wiersz mówi krok, „teraz”
  w terakocie), „Ten krok” zostaje TERAZ / ZA CHWILĘ, w środku działami.
  Runda 5: krok bez składników ma pusty stan (od rundy 10 `CookStepNoIngredients`: przygaszony koszyk, „Ten krok bez
  składników”, cichy dopisek „Następne wchodzą w kroku 6” — bez karty, ptaszka i przycisku, „minimalistycznie”).
  Trwające timery NIGDZIE nie są ucinane do dwóch:
  arkusz „Wychodzisz z gotowania?” zawija pigułki na środku (`AllergenChipFlow(alignment: .center)`) i ma wysokość
  treści POLICZONĄ przed pokazaniem (`CookExitSheet.estimatedHeight`: kroje UIKit, kafle, zawijanie pigułek; pomiar
  poprawia ułamki) i bez kaskady wejścia — runda 10: szacunek 400 pt kurczył się w trakcie wjazdu („niech się
  otwiera jak wszystkie inne”), talerz PS1 w Kalendarzu stawia wszystkie w JEDNYM rzędzie w najbogatszej postaci, która się mieści
  (`ViewThatFits`: z nazwami → same pierścienie z czasem → trzy i „+N”).
  Runda 6: etykieta nad tytułem na 322 pt (`spacing.cookTitleTop`, było 290) — tytuł pod zdjęciem, nie na nim.
  Pierścień kroków to PRZYCISK → arkusz Kroki (`CookStepsSheet`, `CookSheet.steps`). Runda 7 („nie dawaj tak, że jak
  klikam, to mi się otwiera; wykorzystaj całą przestrzeń”): od razu `.large`, SAM PODGLĄD — wiersz nie przenosi do kroku
  (`CookSession.jump` został dla debug i sprawdzianu); pasek `SCStepProgress` pod nagłówkiem, oś krążków (zrobiony =
  ptaszek w szałwii, bieżący = terakota na karcie w tincie, przeskoczony liczy się jak dalszy), tytuł 17 + dwie linie
  opisu (bieżący cztery), etap tylko przy zmianie, `SCTag` „Teraz” i timer kroku słowem. Powitanie mieści się BEZ
  przewijania (runda 7, liczone na 844 pt): tytuł `typography.cookWelcomeTitle` 32, opis przepisu
  (`CookSession.recipeDescription` z `Recipe.description`; stara sesja bez klucza = bez opisu) najwyżej 3 linie pod
  liczbami, w stopce karta porcji 52 pt NAD szufladami, szuflady Składniki i Rady kucharza OBOK SIEBIE (kafle 52 pt,
  jedna ikona, podpis „14 · na 2 porcje” / „3 rady”, strój kafla `scTileBg` + `scTileStroke`). Składniki (arkusz
  i szuflada): ikona i kolor alejki TYLKO w nagłówku działu (`CookSectionHeader(icon:)`), wiersze bez ikon — zrobione
  przygaszone z ptaszkiem w podpisie. Jasny motyw jak w aplikacji: arkusze trybu `cookSheetBackground`
  (= `SCPageBackground`, nie `scCanvas`); dok (wyspa, kapsuły, plakietka) = systemowe Liquid Glass (`cookDockGlass`:
  samo `glassEffect(.regular)`, barwa stanu nad szkłem, bez obwódki i cienia doku; „Dalej” w miękkiej terakocie).
  Runda 6 dała wyspie szkło paska zakładek z warstwą `scPageBase` 0,72 — matowa plama „strasznie różniąca się od
  reszty”; nie wracać. Ciemny motyw doku bez zmian. Zrzut: `SCOFFIE_DEBUG_OPTIONS=gotuj-kroki`.
  Runda 8: adnotacja kroku i „Na następny raz” na zakończeniu to JEDNA zwarta karta `CookNoteCard` (krążek
  `size.cookNoteIcon` z ikoną w kolorze rodzaju, nadtytuł „UWAGA” / „PO CZYM POZNAĆ” / „RADA” / „WIĘCEJ PORCJI” /
  „NA NASTĘPNY RAZ”, zdanie 14/500, `radius.cookNote`; uwaga na tincie masła, reszta na kaflu) — dawna linijka
  `CookNoteLine` i duża karta zakończenia usunięte. Ekran końca timera to JEDEN widok na wszystkie dzwoniące
  (`CookSession.ringingTimers`, kolejność kroków): przy kilku nad tarczą przełącznik kapsuł (dzwonek w kolorze timera,
  nazwa, czas po terminie, zaznaczenie przejeżdża `matchedGeometryEffect`), przełączenie stuknięciem albo przeciągnięciem
  tarczy — tło i panel stoją, aureole i podziałka przenikają (`.id` timera NA NICH, nie na całym ekranie — dawne
  `.id(ringing.id)` gasiło i zapalało cały alarm), kolor płynie, nazwa / tytuł / „było … min” rolują, treść przenika.
  „Gotowe” przy jednym zostawia ekran drugiemu, „Tylko wycisz” (w „…”) ucisza WSZYSTKIE dzwoniące. Zrzut: `gotuj-alarm-dwa`.
  Runda 9 („całość nieruszalna”; „opis i reszta z tą samą animacją tekstu co w aplikacji”): krok = nadtytuł w JEDNYM
  stałym wierszu „KROK 4 Z 12 · ETAP” (numer zawsze, etap dochodzi obok — tytuł nie skacze, gdy etap się pojawia) ·
  tytuł · opis · karty rad. Przy zmianie kroku widoki STOJĄ, tytuł / etap / numer rolują się w miejscu
  (`cookRoll`, wstecz w drugą stronę) — `.id(step.id)` z wjazdem opisu z boku usunięte, nie wracać. Opis z radami
  (runda 10) przechodzi w nowy jako CAŁY blok w miejscu (`cookParagraphSwap`: krycie + rozmycie 3 + 6 pt w kierunku
  kroku, krzywa `SCMotion.textRoll`) — `numericText` na kilku liniach łamał nowy tekst inaczej i ostatnie litery
  z kropką przeskakiwały między liniami; nie wracać do `cookRoll` na akapicie. Składników NA
  kroku nie ma (kapsułki pod tytułem odrzucone: „mam je w sheet, wcześniej było lepiej”). Arkusz Składniki „Ten krok”
  = same składniki bieżącego kroku w DZIAŁACH z ikoną i kolorem alejki jak „Cały przepis” (`aisleRows`, jedna droga dla
  obu widoków); „Teraz” / „Za chwilę” i sekcja następnego kroku usunięte („totalnie niepotrzebne”). Arkusz Kroki
  (runda 9): pasek postępu + „3 zrobione · 9 przed Tobą”, kroki w ETAPACH (nagłówek etapu z liczbą; bez etapu w danych —
  faza), zrobione zwinięte do jednej linii, bieżący na karcie z CAŁYM opisem, dalsze z dwiema liniami.
  „Pomiń” (od 6.10.2026 tylko z arkusza Timery): kapsuła schodzi z pary SWOIM bokiem (pojedyncza w lewo), zamiast
  maleć w miejscu pod rozciągającą się sąsiadką; wiersz arkusza Timery zjeżdża w prawo.
  Wejście w tryb i wyjście: pełny ekran BEZ wsuwania od dołu („ucina talerz i wsuwa się ekran”) — `isPresented` zmienia
  wyłącznie `CookSessionStore.setPresented` (transakcja `disablesAnimations`), `CookModeView` ma `presentationBackground
  (.clear)` i sam przenika nad pulpitem (0,32 s), a przy wyjściu najpierw gaśnie (`leave`, 0,22 s), dopiero potem woła
  `pause` / `end`. Koszyk na wyspie WOŁA, gdy krok przynosi składniki, a arkusza Składniki na tym kroku nikt jeszcze
  nie otworzył (runda 10, `CookBasketGlyph`): koszyk (kontur) w terakocie i KOŁYSANIE dzwonka z tarczy końca timera
  (`CookBellSwing` — wspólne z `CookBell`: 0° → 14° → −12° → 8° → 0° w 0,64 s, oś u góry) co `duration.cookBasketCall`
  (2,4 s), aż do stuknięcia w Składniki; krok już obejrzany (`basketSeenSteps`) i krok bez składników nie wołają,
  Reduce Motion — sam kolor. `symbolEffect(.wiggle)` z rundy 9 był za słaby, a seria ze skokiem 1,25, ±18°, pełną
  ikoną i terakotową plakietką — „zbyt intensywna i rzucająca się”; nie wracać do żadnego z nich. Liczba składników
  kroku (runda 11) to plakietka NAD koszykiem (`CookIslandBadge`: terakota, `size.cookIslandBadge` 17, środek
  `spacing.cookIslandBadgeInset` poza prawym górnym rogiem, poza kołysaniem koszyka). Widok STOI zawsze (runda 12:
  wstawiany w pusty `ZStack` zmieniał przy wejściu i wyjściu także położenie): pojawienie i zniknięcie = skala 0,2 ↔ 1
  + krycie w miejscu (sprężyna), znikając trzyma ostatnią liczbę, podskok 1,22 i rolowanie cyfr tylko przy zmianie
  liczby między krokami ze składnikami; słowo „Składniki” o `spacing.cookIslandLabelGap`.
- Polski cudzysłów: `„…”`. W literale `String` zamknięcie prostym `"` KOŃCZY literał w połowie
  zdania — objaw to `Invalid character in source file` + `Expected ',' separator`. Kontrola:
  linia, w której liczba `„` ≠ liczba `”`, a nie jest komentarzem.
- Repo leży w iCloud Desktop — pliki bywają „dataless”; gdy git/xcodebuild wisi przy 0 % CPU,
  zmaterializuj: `find Scoffie -type f -exec cat {} + > /dev/null`.
- Gałęzie z `develop` po `git fetch --prune`, od razu `git push -u origin <gałąź>`; PR → `develop`
  → `main` → TestFlight przez **Xcode Cloud** (po stronie Rafała). GitHub Actions NIE buduje iOS od 23.09.2026
  (minuty macOS ×10 wyczerpywały limit) — jedyna kontrola kompilacji to Xcode Cloud albo Mac. Commity po polsku, `Co-Authored-By: Claude <noreply@anthropic.com>`.
  Merge do `main` bez buildu (28.09.2026: f7d10e3 — zdarzenie doszło do Xcode Cloud, check suite „queued”,
  build nie wystartował, Apple bez awarii): ręczny Start Build workflow „Default” na `main` (App Store Connect
  → Xcode Cloud albo Xcode → Product → Xcode Cloud) albo kolejny commit na `main`. Czy build ruszył, widać po
  check runie „Scoffie | Default | Archive - iOS” przy commicie (`gh api …/commits/<sha>/check-runs`).
- **Sentry** (od 23.09.2026, projekt `scoffie/scoffie-ios`, region DE): `Models/Observability/CrashReporting.swift`,
  start w `ScoffieApp.init`, użytkownik (samo id) przez `CrashReporting.setUser` przy każdym przypisaniu
  `SessionStore.currentUserId`. Środowiska: `development` (DEBUG) / `testflight` / `production`. Bez zrzutów
  ekranu, hierarchii widoków i session replay (alergeny, kroki na ekranie); nagłówki śladu tylko do
  `api.scoffie.app`; 5xx zgłasza backend, nie telefon. dSYM wysyła faza „Upload dSYM to Sentry” przy
  archiwum (Release) na Macu, a w Xcode Cloud `ci_scripts/ci_post_xcodebuild.sh` (sekret `SENTRY_AUTH_TOKEN`
  w workflow, `sentry-cli` 3.8.0 przypięty sumą SHA-256); na Macu raz: `brew install getsentry/tools/sentry-cli && sentry-cli login`;
  bez tego build przechodzi z ostrzeżeniem, ale crashe są bez nazw funkcji.

## Kontrakty z backendem (nie zmieniać jednostronnie)
- **Minimalna wersja** (2.10.2026): `Components/SCAppUpdateGate.swift` pyta `GET /public/app-version?platform=ios&version=`
  przy starcie i po powrocie na wierzch (≤ raz na minutę), BEZ logowania; `updateRequired` = ekran „Zaktualizuj Scoffie”
  we własnym oknie nad wszystkim (`alert + 2`, nad toastami i zasłoną). Każdy błąd przepuszcza, wersji nie porównujemy
  na telefonie. Próg ustawia się w panelu (Sterowanie, `APP_MIN_VERSION_IOS`). Kontrakt na zawsze — nie zmieniać adresu ani pól.
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
- Udostępnianie przepisów (29.09.2026, kontrakt w repo backendu): KAŻDY link idzie przez `DeepLink`
  (`Models/Session/DeepLink.swift`, sprawdzian `sh Scripts/deep-link-check.sh`) — zaproszenie, przepis
  katalogu (`/przepis/<slug|uuid>`), przepis domu (`/przepis/u/<token>`), schemat `scoffie://`. Link przed
  zalogowaniem leży w `session.pendingDeepLink` (adres, stary klucz zaproszenia czytany przy migracji);
  przepis otwiera `DashboardView` dopiero nad odsłoniętym pulpitem (`RecipeLinkSheet`, `recipes:openShared`).
  Cudzy przepis = `RecipeDetailContext.shared`: tylko odczyt, „Zapisz u siebie” i plan na KOPII
  (`recipes:saveShared`). „Udostępnij” w szczegółach i pod przytrzymaniem karty to jedna droga
  (`RecipeShareKit.swift` → `SCShareSheet`, `recipes:shared` dopiero po `completed`); „Wyłącz link” tylko przy
  `Recipe.shareUrl` (z `recipes:householdState`).
- Cache katalogu `recipes_catalog_cache_v12.json` — po zmianie kształtu `Recipe` podbić wersję
  (komentarz w `RecipeCatalogStore.cacheFileURL`); kasowany przy wylogowaniu.
- `plannedServings` = porcje łączne; sloty per gospodarstwo + `suitableMealTypes`; tydzień od
  poniedziałku przez `PlanWeek`.
- Dolne menu: Przepisy · Plan · **Dziś** · Asystent · Ustawienia — od 6.10.2026 SYSTEMOWY `TabView(selection:
  $session.dashboardTab)` z pięcioma `Tab` (iOS 26, `NavigationMenu.swift`), `.tint` terakota, `.badge` nowych
  odpowiedzi Asystenta, `.tabBarMinimizeBehavior(.never)` (6.10.2026: zwinięty pasek rozjeżdżał się ze wstawkami nad nim — nie wracać
  do `.onScrollDown` bez akcesorium `tabViewBottomAccessory`, które zna stan paska); zmiana zakładki = cięcie systemu. „Produkty” NIE są
  zakładką — lista zakupów wchodzi przyciskiem z nagłówka Planu (`ProductsView` jako arkusz z `topPadding: 24`, bo
  domyślne 78 pt odsuwa tytuł od Dynamic Island). Piąte miejsce zajęte — nowa zakładka wymaga wyjęcia innej (inaczej
  iOS schowa obie pod „Więcej”). Zakładka buduje się przy PIERWSZYM wyborze i potem żyje; „wszedł na zakładkę” =
  `@Environment(\.scTabIsActive)` (ustawiane z `selection == tab`) + `onChange(of:initial:)`, ciągłe animacje
  (`TimelineView`) na niewybranej stoją. Co ma działać bez otwarcia zakładki, robi start sesji
  (`SessionStore.prepareUnbuiltTabs`: rozmowa i pula Asystenta). Wstawki nad paskiem = `safeAreaBar(edge: .bottom)` +
  `scrollEdgeEffectStyle(.soft, for: .bottom)` w treści zakładki (pasek szukania Przepisów — też na ekranie
  kategorii, pigułka Planu, pole Asystenta); pigułka Pulpitu też `safeAreaBar` (`PlanDayGoalBar.dock`, wspólne z Planem). `SCTabBarChrome` niesie
  już tylko `compactTitles`, `keyboardCurve` i `goalBarFaces` (przejście pigułek kcal); `SCStatusBarBlur` i `SCCompactTitle` to nakładka nad `TabView`.
  USUNIĘTE i nie wracać: własny `SCFloatingTabBar`, `ZStack` zamiast `TabView`, budowanie wszystkich zakładek pod
  loaderem, gest pigułki, przenikanie `tabSelection` / `leavingTab`, zwijanie „Revolut” (`scTracksTabBarCompaction`),
  rezerwa `scReservesTabBarSpace`, `ownBottomEdge`, `goalSnapshot`.
- Liquid Glass (4.10.2026, wzór: Telegram na iOS 26 — Rafał: „więcej iOS liquid”) = `Components/SCGlass.swift`.
  (6.10.2026: dolne menu jest SYSTEMOWE — zapisy niżej o szkle menu, pasie pod menu, `ownBottomEdge` i soczewce
  pod palcem są nieaktualne.)
  Szkło TYLKO na tym, co PŁYWA nad treścią: `scChromeGlass` (czyste `.regular`, bez kryjącej warstwy `scPageBase`
  0,72 — „matowa plama”, jak w Gotuj runda 6) dla dolnego menu, pola i krążka wysyłania Asystenta (jeden
  `GlassEffectContainer`), „na dół rozmowy”, pigułki „Cel dnia”, toastu cofania i krążków NA ZDJĘCIU
  (`SCSheetIconSurface(onImage: true)`: serce, udostępnij, krzyżyk szczegółów, pierścień kroków Gotuj);
  `scPhotoGlass` (`.clear` + czerń 0,32) dla serca i pigułek na zdjęciu karty karuzeli. Karty, wiersze i pola
  w przewijaniu zostają w stroju kafla. Czytelność daje `SCScrollEdgeBlur` POD szkłem: treść chowa się —
  rozmywa i gaśnie w tło — zamiast przebijać ostro: pod paskiem stanu (`SCStatusBarBlur`, jeden w `NavigationMenu`,
  tylko w górnym bezpiecznym obszarze — niżej są tytuły zakładek i „wstecz”), pod menu (tło `SCFloatingTabBar`)
  albo od elementu nad menu w dół (pole Asystenta, pigułka Planu — wtedy pas menu gaśnie,
  `NavigationMenu.ownBottomEdge`, żeby dwa materiały nie dały progu). Własny pas, nie `scrollEdgeEffectStyle` +
  `safeAreaBar`: zakładki przewijają pod górnym obszarem (`ignoresSafeArea`) i paski stoją w `overlay`.
  Menu: wybraną zakładkę mówi KOLOR ikony i podpisu (terakota, reszta `scLabel`); neutralna soczewka tylko pod
  palcem (Rafał: „na active ikona ma mieć kolor, a nie cały state”) — nie wracać do terakotowej pigułki w spoczynku.
  Runda 2 (4.10.2026): szkło mają też krążki nagłówków (`SCCircleIconLabel` — podświetlony = `tint` akcentu; rząd
  akcji Planu w `GlassEffectContainer`), krzyżyk i sąsiedzi w KAŻDYM arkuszu (`SCSheetIconSurface`, `onImage` zmienia
  już tylko kolor glifu), „Wyczyść” (`RecipeFilterClearButton`) i „Wróć do dziś” (szkło w tincie terakoty),
  pasek szukania Przepisów (`RecipesSearchBar`, jedna grupa) i karta skrótu nad polem Asystenta — w grupie
  `composerGlass` z polem i „Wyślij” (`glassEffectID`), więc wyrasta z pola i w nie wsiąka. Po przewinięciu dużego
  tytułu (Przepisy, Ustawienia: `scReportsCompactTitle`) pod paskiem stanu staje szklana kapsuła z tytułem
  (`SCCompactTitle`, rysuje `NavigationMenu` z `SCTabBarChrome.compactTitles`), a pas rozmycia schodzi pod nią.
  Toast (`SCToastHost`) świadomie BEZ szkła: wyrasta z Dynamic Island jako czerń i stygnie do koloru — szkło nie
  zacznie się czernią wyspy, a toast niesie błędy, które mają być czytelne zawsze.
  Runda 3 (4.10.2026, „wszystkie możliwe buttony w stylu liquid, na każdym sheet, każdy X”): wariant „soft” TO JEST
  szkło — `SCSoftSurface`/`scSoftCapsule` = `scChromeGlass` w tincie akcentu (0,22 / ciemny 0,30), interaktywne, bez
  obwódki; idą przez to `SCSoftButton`, `EditorialPrimaryActionButton`, `AssistantPrimaryButton`, `SCDestructiveButton`,
  `RecipeFilterFooterButton`, akcje szczegółów posiłku. Neutralne szkło: `AssistantGhostButton`,
  `AssistantIconActionButton`, `AssistantChip`, `SCSoftIconButton` („Wstecz”), `SCStepper`, chipy wyboru
  (`scChoiceSurface(.chip)`; kafle `.tile` zostają kartami). „Gotuj” = szkło w PEŁNEJ terakocie. Przełączniki: tor płaski,
  wybrany = szklana soczewka (osoby w „Cel dnia”, osoby w przeglądzie propozycji, „Ten krok / Cały przepis” w Gotuj,
  „Zamień / Dodaj obok”). Akcent na element stojący NA szkle (przycisk „Wyślij”, „Cofnij” w toaście) = `tint` tego
  jednego szkła albo zwykłe wypełnienie — bez drugiego szkła z `scSoftSurface` na pierwszym.
  INTERAKTYWNE szkło (`scChromeGlass(interactive: true)`) TYLKO tam, gdzie widok ma własny gest (dolne menu,
  pigułka „Cel dnia”) — NIGDY w etykiecie ani kontenerze przycisku: z `.buttonStyle(.plain)` przechwytywało na iOS 26
  stuknięcie („Dalej” w „Jak działa Asystent” nic nie robiło, 4.10.2026). Szkło w etykiecie `Menu` — TYLKO gdy jest
  CAŁĄ etykietą (krążek „…”, „Dla kogo”): iOS 26 bierze je za źródło animacji menu, więc szklany krążek „+” w szerokim
  wierszu „Dodaj posiłek” znikał i rozlewał się w terakotową kapsułę na cały wiersz (TestFlight 5.10.2026) — tam płaski
  tint. Reakcja na dotyk = `PlanPressStyle`
  (`EditorialPrimaryActionButton`, `SCSoftButton` przeszły z `.plain`). Też szkło (4.10): strzałki tygodnia
  (`EditorialWeekBar`, „Dodaj do planu”), „Wyczyść filtry”, strzałka nagłówka sekcji Przepisów, „Otwórz” u Asystenta,
  „Ustaw/Policz/Odrzuć/…” w Ustawieniach, chipy „Dla kogo”, kciuki oceny Gotuj. Serce ulubionych = podskok glifu +
  `ThumbCheer` w terakocie (jak „like” w Gotuj).
  Gotuj (4.10.2026; alarm od 6.10: „Gotowe” = szkło w PEŁNYM kolorze timera — decyzja 6.10.2026 wieczór: ZOSTAJE pełne, jak
  „Zatrzymaj” w Zegarze iOS; pismo `CookTimerAccent.ink(_:)`: tło strony, ale ciemne na musztardzie w jasnym motywie i jasne
  na indygo w ciemnym — „+1 min” i „…” neutralne): szkło na „Gotuj dalej”, stepperze porcji powitania, „Pomiń” w Timerach,
  pigułkach powodów oceny (`scChoiceSurface`). Przyciski nagłówka arkusza (krzyżyk, serce, „Cofnij/Wyczyść”, „…” w Zakupach) = 38 pt z glifem `scLabel`
  (`SCSheetIconLabel.size`) — 36 pt z szarym glifem wyglądało na płaskie kółko, 44 było „ciut za duże”.
  Ciemny dok (`cookDockGlass` w ciemnym = bez szkła, `cookIslandSurface`,
  kapsuły, plakietka) ŚWIADOMIE bez zmian do decyzji Rafała. Makieta pola we wprowadzeniu Asystenta = strój prawdziwego pola.
- Zdjęcia: `CachedAsyncImage(url:variant:)`. Domyślna `.thumbnail` (512 px, ~1 MB w pamięci, JPEG
  na dysku) — listy, kafelki, talerze; `.large` tylko dla okładki szczegółów i dużych kart
  (pokazuje miniaturę, dopóki duża się nie zdekoduje). Oryginały to PNG 1024² po 4 MB po
  zdekodowaniu — w `.large` cały katalog NIE mieści się w pamięci i listy zaczynają migać.
  Pamięć mieści ~256 miniatur (`totalCostLimit` 256 MB), katalog ma ponad 1000 — start
  (`SessionStore.prepareStartupData`) czeka na pierwsze 160 miniatur katalogu i bieżący tydzień, reszta
  dociąga się w tle. Rozgrzewka (`ImagePrefetcher`) biegnie NAJWYŻEJ 8 naraz (przesuwne okno), dysk
  przycina się co 64 zapisy, ostrzeżenie o pamięci czyści pamięć podręczną — bez tego zimny start
  (świeża instalacja, App Review) kończył się WatchdogTermination (Sentry SCOFFIE-IOS-1, 27–30.09.2026).
  Nie wracać do `withTaskGroup` z zadaniem na każdy adres.
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
  Od 24.09.2026 to `AssistantMaintenanceView` zamiast rozmowy; pole wiadomości znika. Od 6.10.2026 (wersja A
  z artefaktu „Asystent na przerwie”) pusty stan NA ŚRODKU: krążek z żywym znakiem i kluczem (oddech, klucz kiwa się
  co ~3 s), „Asystent ma przerwę”, jedno zdanie, szklany „Sprawdź ponownie” (= `AgentStore.recheckAvailability`,
  kręciołek w miejscu strzałki; „jeszcze nie” = drgnięcie, haptyka, zdanie pod spodem); ciche sprawdzenie przy każdym
  wejściu na zakładkę zostaje. Powrót na oczach = `AssistantView.comebackHold` (1,3 s): klucz odpada, znak podskakuje
  (`cheer`), tytuł roluje się na „Asystent wrócił”, potem powitanie i pole. Licznik puli w nagłówku schowany na czas
  przerwy (`showsMaintenance`). Bez kaskady wejścia; karta trzech kafli „Działa jak zawsze” USUNIĘTA (wyglądały na
  przyciski, nic nie robiły). Pula wyczerpana to inny stan (`AssistantQuotaSpentCard`).
- Czysta kartka po przerwie (`AgentStore.rotateIfStale`): 30 min ciszy w rozmowie ALBO 10 min nieobecności
  na zakładce/w tle (`staleAfterAway`, od `setVisible(false)` / `noteWentToBackground`) przy rozmowie bez
  propozycji PENDING; tura w biegu nigdy. Zamiana czyści `AssistantGreetingMemory.forget()`, więc powitanie
  pisze się od nowa. Pole wiadomości w jasnym motywie: krem #F3ECE0 (`AssistantLook.input`), nie biel.
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
  w planie” tylko gdy `AgentStore.lastTurnWrote == false`), nie notka z wykrzyknikiem. Od 27.09.2026
  w stroju nagłówka arkusza: kafelek z ikoną sytuacji · eyebrow · tytuł w 1. osobie bez kropki, JEDNO
  zdanie, „Plan bez zmian” jako `SCTag` w szałwii i „Spróbuj ponownie” jako `AssistantPrimaryButton`
  w treści (bez stopki z kreską); wchodzi łagodnie, po zwinięciu wiersza „myślę” (`outcomeTransition`). Na żywo
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
  Wysokości nie ustawiać ręcznie — `size:`. Od 27.09.2026 („inny daj jako ikonę, a zapisz na resztę”): poboczna
  Z GLIFEM obok głównej = sam krążek `AssistantIconActionButton` (kształt „Wyczyść” z Filtrów, ale SZARY — pole
  + obwódka jak `AssistantGhostButton`; tytuł tylko dla VoiceOver), główna na resztę szerokości; bez glifu („Zapisz
  mimo to”) zostaje para słów. Zapis propozycji („Zapisz niedzielę”, „Dodaj do planu”) w SZAŁWII
  (`AssistantCardActions(primaryTint:)`, `AssistantPrimaryButton(tint:)`) — „ponów szary, zapisz na zielono”.
  Poboczne propozycji mają glify (`reviseIcon`): Zmień coś ✎, Inny zestaw / Zmień danie ⟳, Szukaj dalej 🔍, Zostaw ✕.
- Szkic odpowiedzi i jej dopisywanie liczą się z JEDNEGO zegara (`AgentStore.draftReveal`,
  `AgentRevealClock`): gotowa odpowiedź rusza od znaku, który JEST na ekranie (i od wspólnego
  początku ze szkicem), nie od długości szkicu z serwera — inaczej wskakuje naraz. Od 27.09.2026
  (Rafał: „pisze jedno słowo, a potem przeskakuje i pokazuje całą odpowiedź”) szkic i gotowa
  odpowiedź to JEDEN widok: szkic jest wiadomością pozorną (`AgentStore.draftMessage`), ostatnia
  odpowiedź tury dostaje jego klucz (`liveKey` → `anchorID` = „turn-…”), a zegar żyje W WIADOMOŚCI
  (`AgentChatMessage.reveal`, nie w `@State` widoku). Od 6.10.2026 na żywo pisze się TYLKO szkic: ciąg dalszy
  widocznego szkicu domyka się w ≤ 0,6 s (`AgentRevealClock.finishWithin`, `finishing` bez sufitu `maxRate`),
  wszystko inne (`AgentRevealClock.whole`) stoi od razu w całości razem z kartą i paskiem (`isRevealing` patrzy na
  `startsComplete`); odpowiedź, która szkicu NIE kontynuuje (`answerContinuesDraft`), czeka w `letDraftFinish` na
  domknięcie szkicu (≤ 0,6 s) i staje cała W JEGO miejscu (ten sam `liveKey`). `lastAnswerContinuedDraft` usunięte.
  Szkic pisze się od 18 zn/s (`draftMinRate`; pierwsza porcja z serwera to zwykle jedno słowo, a serwer zapisuje
  szkic najwyżej raz na sekundę).
  Tekst jest ZŁOŻONY od pierwszej klatki, nienapisane przezroczyste, ostatnie 14 znaków rampą krycia
  (`AssistantReveal` w `AssistantAnswer.swift`) — słowa nie przeskakują do następnej linii, a dalsze
  akapity i listy czekają w zarezerwowanym miejscu. Wiersz „myślę” zwija się przy PIERWSZYM słowie
  szkicu, nie na końcu tury (tekst nie podskakuje). Rozmowa idzie za porcjami szkicu (`scrollTo`
  początku odpowiedzi), dopóki użytkownik sam nie chwyci listy (`followsAnswer`, `onScrollPhaseChange`).
- Odpowiedź asystenta (27.09.2026, „odpowiedzi są ściśnięte”): kolejne linie to JEDEN akapit
  (złamanie w środku), pusta linia go zamyka; akapit 16 pt, interlinia 6, bez ujemnego trackingu,
  16 pt między kawałkami, nagłówek sekcji 15/600 (nie wersaliki 11 pt), lista 15 pt. Pod CAŁĄ
  odpowiedzią (tekst + karta) pasek `AssistantAnswerFooter`: podpis „✦ Myślałem 42 s ›” (rozwijana karta
  z krokami W ROZMOWIE odpadła: „do usunięcia”; wieczorem tego dnia podpis otwiera półarkusz
  `AssistantThinkingSheet` — kroki tury po kolei z glifem rodzaju pracy, zapisy w szałwii, „Odpowiedź gotowa”) oraz
  👍 · 👎 · „⋯” (udostępnij, zgłoś / popraw zgłoszenie, przy podpowiedzi „Popraw podpowiedź”). Po 👎 wiersz
  „Co poprawić? Podpowiedz” → `AssistantSuggestionSheet` (powody `AGENT_FEEDBACK_TAGS` + zdanie, ten sam PUT
  feedback z `tags`/`comment`, historia oddaje `feedbackNote`); to NIE zgłoszenie — działa też przy odpowiedzi
  zgłoszonej, idzie do działu „Oceny” w panelu. Napisu „Zgłoszone — dzięki” nie ma („bez sensu”). Runda 3:
  👎 SAM otwiera arkusz „Słaba odpowiedź · Co poprawić?” (ocena zapisuje się od razu, krzyżyk zostawia sam kciuk) —
  pigułka w pasku odpadła, bo przestawiała układ („przeskakuje, jak zmieniam like”); pasek ma zawsze ten sam układ.
  Arkusz = LISTA 4 powodów w jednej karcie (krążek w kolorze powodu · nazwa · `SCCheckbox`, bez `withAnimation`
  i podmiany glifu — „animacje check za wolne”) + pole; prawe wcięcie paska = lewe (glif „⋯” 28 pt
  od brzegu). „Jak pracowałem”: tytuł = co tura zrobiła (`ThinkingHeadline`: „Ułożyłem plan”, „Dobrałem dania”…),
  kafelek = stała ikona przebiegu `point.3.filled.connected.trianglepath.dotted` w terakocie, czas kapsułką obok krzyżyka.
  Runda 5 („serio pokazuj, co się działo”): oś z danych tury — krok = `done` (czas przeszły z serwera) + `detail` (fakty
  z wejścia i wyniku narzędzia) + sekunda tury („0:08”, od `thinking.startedAt`); przerwy ≥ 2 s na myślenie to ciche
  wiersze… — ZASTĄPIONE w rundzie 8: wiersz = JEDNA akcja (ikona · zdanie w czasie przeszłym · fakty · czas trwania
  po prawej), akcja trwa od swojego początku do początku następnej (pierwsza od startu, ostatnia do końca tury),
  granice zaokrąglone przed odjęciem — suma = czas w nagłówku; BEZ wierszy przerw, „Napisałem odpowiedź”, „Wyniku”.
  Runda 9: ZAWSZE pierwszy wiersz „Przemyślałem, od czego zacząć” (mózg) — prawdziwe myślenie przed 1. akcją
  w widełkach 2–10 s (`ThinkingEntry.startRange`), różnica zjeżdża z/do pierwszej akcji, suma bez zmian.
  Runda 10: tytuł nagłówka = EFEKT jako rzeczownik („Propozycja planu gotowa”, „Dania do wyboru”, „Plan zapisany”),
  nie czasownik — „Ułożyłem plan” powtarzał wiersz osi; fakty pod krokiem najwyżej 2 linie (backend skraca plan do
  zakresu i wyniku).
  Tytuły „Jak pracowałem” KRÓTKIE („Plan gotowy”, „Zamiennik”), kompaktowy
  nagłówek arkusza ma tytuł zawsze w jednej linii. Kciuki i „⋯” TYLKO pod odpowiedzią modelu
  (`turnId != nil`) — potwierdzenia zapisu/cofnięcia serwer pisze bez tury i odmawia ich oceny. Od 6.10.2026 👍 bez arkusza, 👎 = półarkusz „Co nie zagrało?”
  (patrz „Prościej…” na górze); zaznaczony kciuk w górę szałwia, w dół terakota. Półarkusze „Jak pracowałem”
  i „Co poprawić?” mają kompaktowy nagłówek (`EditorialSheetHeader(compact:)` / `AssistantSheetScaffold(compact:)`:
  kafelek 36, tytuł 19); oś kroków bez karty, kolor = rodzaj pracy (`ThinkingKind`). Bez kopiowania w pasku („co nam to daje
  realnego?”) — „Kopiuj” zostaje pod przytrzymaniem. 👎 pokazuje „Co było nie tak? Opisz” → arkusz
  zgłoszenia. Zgłoszenie JEDNO na osobę i odpowiedź: serwer poprawia istniejące (`AgentReport`
  po `userId+messageId`, wraca do panelu jako NEW), historia oddaje własne (`AgentMessageDTO.report`),
  a arkusz otwiera się jako „Popraw zgłoszenie” z tym samym powodem i komentarzem. Czas i kroki przychodzą z serwera (`AgentMessageDTO.thinking`, także
  w HISTORII — wcześniej „Myślałem” żyło tylko w pamięci sesji), ocena to `feedback` +
  `PUT agent/messages/:id/feedback {rating: UP|DOWN|null}` (backend: `AgentMessageFeedback`,
  migracja `20260927120000_agent_message_feedback`). Zrzuty: `SCOFFIE_DEBUG_OPTIONS=rozmowa|rozmowa-pisze`.
- Nagłówek rozmowy (27.09.2026, „shadow jak na detail meal, a nie divider”) stoi w `safeAreaInset(edge: .top)`
  jak pole na dole: rozmowa przejeżdża POD nim, a gdy jest przewinięta, pod nagłówkiem leży `AssistantHeaderShade`
  (tło strony przez maskę — poświata się zgadza; 16 pt na nagłówku + 28 pod nim). Krycie cienia idzie ZA przesunięciem
  listy (`headerShade`: pełne po 24 pt, co 1/12, bez animacji) — przełącznik z animacją spóźniał się przy szybkim
  przewijaniu. Przykład w polu w rozmowie zależy od OSTATNIEJ odpowiedzi (`AssistantComposerHint`: propozycja — zmiana
  z nazwą dania z karty, zapis — następny krok, dania do wyboru — życzenie, zakupy, bilans, pytanie), wariant z ziarna
  id wiadomości; nie powtarza przycisków karty. Pytania z odpowiedzią W APLIKACJI („pokaż listę zakupów”, „jak ugotować…”, „daj przepis”) telefon
  NIE wysyła (`AssistantAppShortcut`): nad polem karta z przejściem (Plan → Zakupy / Przepisy) i „Zapytaj mimo to” —
  tura kosztuje i zjada wiadomość z puli; backend wycofał `show_shopping_list` z modelu i każe odsyłać jednym zdaniem. Oceny 👍/👎 wymagają backendu
  z `PUT agent/messages/:id/feedback` — aplikacja zawsze woła `api.scoffie.app`, więc bez backendu na `main` kciuk wraca
  z toastem „Nie zapisałem oceny”.
- Pytanie wysłane w tej sesji stoi pod kluczem z telefonu (`clientMessageId` — od niego zależy
  `slotKey`), a serwer ma je pod własnym id: `AgentChatMessage.serverId` (z `202 messageId`). „Popraw
  pytanie” wysyła `serverId ?? id` (sam `clientMessageId` dawał 404). „Spróbuj ponownie” po nieudanej
  turze idzie drogą poprawki (`editMessage` z tą samą treścią), nie nową wiadomością — rozmowa nie ma
  dwóch identycznych pytań pod rząd. Nieudana tura za 0 zł oddaje wiadomość z puli (backend, 27.09.2026).
- Loader startu stoi NAD korzeniem (`ScoffieApp.showsStartupLoader`), nie w gałęzi pulpitu:
  krycie kontenera bez `compositingGroup` schodzi na dzieci, więc przy przejściu korzenia przez
  loader prześwitywała zakładka. Gesty w arkuszach: poziome przewijanie przez
  `UIGestureRecognizerRepresentable` ruszające tylko przy ruchu poziomym (`OptionsPagePan`) —
  `DragGesture` na całym arkuszu zabiera systemowi zamykanie w dół.
- Zmiana korzenia (logowanie, kreator, pulpit, wylogowanie, usunięcie konta) idzie JEDNĄ drogą:
  `SCSessionCurtain` (`Components/`, własne okno nad arkuszami, pod toastami) — zasłona w kolorze tła
  w górę, `ScoffieApp.showRootScreen` przestawia korzeń bez animacji (na AKTUALNY cel), zasłona w dół.
  Korzeń nie ma już własnego crossfade'u (pulpit wjeżdżał z loaderem i prześwitywał Kalendarz).
  Loader WEJŚCIA (po logowaniu / kreatorze; od 6.10.2026 tylko on — zimny start patrz „Prościej…” na górze)
  schodzi TYLKO na pełnym obrocie znaku (runda 21–22): SAM znak (`SCScoffieMark(markRotation:)`, kafel stoi)
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
  „Kto ile je” (posiłek z planu z porcjami osób) to od 4.10.2026 NIE sekcja w przewijaniu, tylko szklana pigułka
  przyczepiona nad przyciskami (`portionsPill`, jak „Cel dnia”): awatary, „Do ugotowania · 3,5 porcji”, › →
  od 6.10.2026 PUSH w stosie arkusza szczegółów (`portionsPage`, tytuł „Kto ile je” w pasku; do tego dnia półarkusz
  `.medium/.large` z nagłówkiem „Kto ile je · Porcje” — arkusz na arkuszu, nie wracać; od 4.10.2026 wieczorem
  „w stylu iOS” — linia `SCPortionSummary` „Razem · 3,5 porcji · kcal” nad listą, BEZ karty i paska podziału; grupa
  `SCPortionList`/`SCPortionRow` jak w Ustawieniach iOS — awatar 34, imię + „· Ty”, kcal pod spodem, z prawej liczba
  i SYSTEMOWY `Stepper` (strony wyłączane przez `nil`); zmieniona niezapisana porcja = liczba w terakocie). Ten sam
  zestaw (`Components/SCPortionKit.swift`) w „Dodaj do planu”. Duży pierścień z kaflami po dwa (wcześniej tego dnia)
  odpadł — „bardziej czytelne”. Po zmianie w stopce ekranu „Zapisz porcje”, a w pasku „Cofnij”; ten sam zapis
  też pod pigułką.
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
  TYLKO w Filtrach — od 4.10.2026 jako różdżka OBOK krzyżyka (`RecipeFilterHeader(fitIsOn:)`, włączona = tint
  szałwii; karta na górze arkusza usunięta), a podtytuł nagłówka mówi „Dopasowane do Ciebie · ukrywa N przepisów” — różdżka w nagłówku Przepisów
  i `RecipePersonalizationSheet` zniknęły jako duplikat; pusty ekran przez dietę ma własny przycisk
  „Pokaż wszystkie przepisy”. Kafelek wyboru (`SCChoiceTile`, `Components/`; od 27.09.2026 STAŁA wysokość 70 pt
  na dwie linie nazwy, miniatura 54 pt W KARCIE z równym odstępem 8 pt od góry, dołu i lewej (wersja „na całą
  wysokość” odrzucona — „jako card było lepsze”), nazwa ZAWSZE 14 pt bez zmniejszania —
  długie słowo łamie się miękkim dzieleniem „Wysoko-/białkowe”, `SCChoiceTile.hyphenated`) = miniatura ZDJĘCIA
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
  (`Components/SCSheetFooter.swift`). Od 4.10.2026 BEZ TŁA (Rafał, kilka razy: „usuń ten shadow pod buttonem,
  zrób to natywnie, aby pokazywało się, co jest pod spodem”; „każdy sheet… tylko button liquid i pokazuje się
  płynnie”): bez kryjącej płyty, bez `SCEdgeShade`, bez rozmytego pasa (`SCFooterScrim` usunięty) — same szklane
  przyciski. `.scSheetFooter` = systemowe `safeAreaBar(edge: .bottom)`: treść przejeżdża pod przyciskami i kończy
  się nad nimi; pod przyciskami TYLKO natywny efekt krawędzi systemu (wyłączony na chwilę w #282, przywrócony:
  „dodaj z powrotem ten natywny shadow, jednak to ma sens”) — ZAWSZE jawnie miękki: `scSheetFooterEdge()`
  (= `scrollEdgeEffectStyle(.soft, for: .bottom)`) przy KAŻDYM dolnym `safeAreaBar`. Domyślne `.automatic` w buildzie
  z Xcode Cloud (TestFlight, 5.10.2026) wyszło jako `.hard`: kreska i ciemniejsze tło pod przyciskami, których lokalny
  build nie miał. „Zapisz porcje” w szczegółach posiłku pojawia się dopiero, gdy jest co zapisać (`showsPlanAction`). Tak samo szczegóły posiłku
  (`RecipeDetail.primaryActionBar` w `safeAreaBar` na `ScrollView`) i przegląd propozycji.
  `SCEdgeShade` został TYLKO pod górnym paskiem szczegółów posiłku (84 pt) — Rafał: „bardzo mi się podoba shadow górny”. Pod listą w `VStack` jako ostatnie dziecko lista ma na dole tylko oddech (16 pt). Przycisk pełnej szerokości = `EditorialPrimaryActionButton`,
  obok liczb = `RecipeFilterFooterButton` („Pokaż” w Filtrach USUNIĘTE 6.10.2026 — filtry działają na żywo,
  stopka ma „N z M” i tekstowe „Gotowe”). `AssistantStickyFooter` i `AssistantSheetFooter` to już
  tylko nakładki na nią; kreator, przewodnik i wprowadzenie Asystenta też (`SCStepFooter`, runda 14).
- Przepływy krok po kroku (kreator „Poznajmy się”, przewodnik „Poznaj aplikację”, wprowadzenie Asystenta,
  runda 14) stoją na `Components/SCStepFlow.swift`: `SCStepHeader` (kafel `SCHeaderIconWell` 48, eyebrow
  10,5/1,4, tytuł 28 heavy, najwyżej jedno zdanie), `SCStepFeatureCard` i `SCStepFooter` = płyta
  `SCSheetFooter` z cieniem, nad przyciskiem wiersz 36 pt: krążek „Wstecz” · pasek `SCStepProgress`
  (odcinki na całą szerokość, bieżący nalewa się od lewej) albo odnośnik „Pomiń…” · licznik „2/5”; pod
  spodem `EditorialPrimaryActionButton`. JEDNA instancja na cały przepływ, żeby pasek się animował.
  `WelcomeFooter`, `WelcomeStepper`, `WelcomeStepHeader`, `TourFooter`, `TourBackground`, `AssistantTickRow`
  usunięte; kreator i przewodnik na `SCPageBackground`, margines 20, sekcje `WelcomeSection`, wiersze celu
  i diety jak w Ustawieniach, bez akapitów objaśnień. `SCStepHeader(typing:)` = tytuł i opis PISZĄ SIĘ
  (`SCTypedText`, tempo powitania Asystenta: 65 / 170 zn/s, razem ≤ 0,9 s) — używa tego tylko Asystent.
- Wprowadzenie Asystenta v2 (24.09.2026, Rafał: „nieaktualne… zrób od nowa”, „button wstecz taki sam jak na
  onboardingu aplikacji”, „po poznawaniu od razu klawiatura, a nie chcę”) — makieta Claude Design
  „Scoffie — Asystent · Wprowadzenie v2” (`claude.ai/artifact/6pXaTCJ3VDrcrTSmmPCGwU`). CZTERY ekrany zamiast
  sześciu: Powitanie → Planowanie → Ty decydujesz → Zgoda (`AssistantView.IntroStep`), zgoda NA KOŃCU, po niej
  od razu rozmowa — BEZ fokusu pola (dawne `startConversation` wysuwało klawiaturę po 0,35 s; nie wracać).
  Na czas wprowadzenia zakładka NIE ma nagłówka „Asystent” (strona od góry jak w przewodniku). Strony w
  `AssistantIntroPages.swift` (wspólne z arkuszem menu „Jak działa Asystent” = `AssistantHowItWorksView`):
  powitanie = JEDEN zwarty blok na środku wolnego miejsca (v3, Rafał: „dużo wolnej przestrzeni”): żywy znak 52
  (`SCLivingMark` lively, podskok po tytule) z oddechem 38 pt nad sobą — poświata i podskok muszą zmieścić się
  pod górną krawędzią przewijanej strony (v2: „od góry za bardzo przycięte”), „Cześć! Jestem Twoim Asystentem”
  (Asystent mówi w 1. osobie), pole wiadomości w stroju prawdziwego (kapsuła 50 + krążek „soft”), w którym
  przykłady piszą się same, i etykiety. Planowanie i Ty decydujesz = SCENKA z PRAWDZIWYCH klocków rozmowy
  (bez ramki wokół — karta w karcie ściska) + `SCStepHeader` + etykiety `SCTag` (Components/, wspólne
  z alergenami w Ustawieniach) zamiast karty punktów. Scenki na PRAWDZIWYCH daniach z katalogu odsianych dietą
  i alergenami z Ustawień (`AssistantIntroDish.pool` → `RecipePersonalization.excludes`): dymek jak
  `AssistantUserBubble` pisze „Coś lekkiego na kolację”, karta „Do wyboru · kolacja” (`AssistantCard`,
  `AssistantCardHead`, `AssistantMealRow`) — kcal liczą się od zera, potem wybór (ptaszek, reszta przygasa);
  karta propozycji dnia [Inny zestaw][Zapisz dzień] → kręciołek → szałwia, „Zapisane”, [Cofnij][Otwórz plan]
  (`AssistantCardActions`, tytuły rolują). Karta stoi w układzie od pierwszej klatki (opacity), a kcal wchodzą
  przez `kcal: shown ? … : 0` — wtedy liczą się NA OCZACH. Jedna `SCStepFooter` (`.besidePrimary`), powitanie ma
  „Pomiń wprowadzenie” (→ zgoda), pasek 3 odcinki. Każdy punkt sprawdzony w backendzie (komentarz na górze
  pliku): alergeny = `collectPlanViolations` sprawdza KAŻDEGO domownika; cofnięcie = okno
  `AI_PROPOSAL_UNDO_WINDOW_MS` (domyślnie 1 h — NIE pisać „w ciągu doby”). Menu ⋯ „Co potrafi Asystent” bez karty
  „Jedna zasada” i bez opisów/miniatur (`AssistantThumb`, `AssistantExchangePreview` usunięte), zgoda z menu:
  status z kafelkiem + `SCDestructiveButton` „Cofnij zgodę”. Licznik potwierdzeń „0 z 2” roluje (`numericText`).
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
  wierszy usunięty 24.09.2026). Stuknięcie w posiłek = koło godzin w arkuszu na 1/3 ekranu
  (`MealTimeEditorSheet`, `.fraction(1/3)`, kompaktowy nagłówek, koło 100–150 pt — 4.10.2026). Kreator trzyma godziny lokalnie i wysyła po utworzeniu gospodarstwa
  (tylko gdy różne od domyślnych), Ustawienia zapisują od razu.
- Filtry kategorii: aspekty i reguły w `RecipeCategoryFacets` — liczone z NAZWY dania i składników (katalog nie ma
  tagów), sprawdzone na 495 przepisach z `prisma/catalog`; nowe słowo kluczowe = sprawdź pokrycie na katalogu, nie
  na oko. W obrębie aspektu LUB, między aspektami I. Wybór żyje w `RecipeFilterOptions.categoryFilters`; od 6.10.2026
  to SEKCJA „Filtrów” (nie osobny arkusz), a plakietka, „Wyczyść” i nagłówek wyników liczą je razem z globalnymi
  (`activeCount(in:)`, `reset(in:)`, `summaryLabels(in:)`).
- Taksonomia katalogu 1000 (28.09.2026): serwer dowozi w liście, synchronizacji katalogu i szczególe
  `cuisine`, `dishType`, `seasons`, `occasions`, `equipment`, `features` → `Recipe.taxonomy`
  (`Models/Components/RecipeTaxonomy.swift`; `nil` = stary backend / cache sprzed zmiany → heurystyka).
  Plik cache katalogu podbity do wersji 2 (stary nie ma taksonomii, delta nie dośle niezmienionych).
  „Filtry”: sekcje „Kuchnia” (`RecipeCuisine`, 8 kafelków, bez OTHER) i „Okazje i sezon” (`RecipeMoment`:
  Wigilia, Boże Narodzenie, Wielkanoc, Grill, Impreza + 4 pory roku; pora łapie tylko dania SEZONOWE) —
  w obrębie sekcji LUB; w „Cechach” doszły „Airfryer” i „Do pudełka” (AND jak reszta cech).
  Filtry kategorii: rodzaj dania z `dishType` serwera (mapowanie per kategoria w `RecipeCategoryFacets`,
  `MAIN` → kafelek dodatku ze składników; heurystyka z nazwy, gdy `dishType == nil` — przepisy domu, stary backend) + te same aspekty
  „Kuchnia” i „Okazje i sezon”, które chowają opcje bez przepisów w puli (`hidesEmptyOptions`).
  Kontrola: `sh Scripts/catalog-sync-check.sh` (sekcja 14 — taksonomia z JSON-a i przez plik cache).
- „Więcej filtrów” (28.09.2026, Rafał: „mnóstwo podkategorii, nieczytelne — sheet na pół ekranu”): w „Filtrach”
  na wierzchu zostają dopasowanie, czas i trudność, kalorie i dieta; Cechy, Kuchnia oraz Okazje i sezon to WIERSZE
  jednej karty (`RecipeFilterPickerRow` w `RecipeFilterPickerGroup`: ikona w tincie — cechy indygo, kuchnia szałwia,
  okazje róż — tytuł, wybrane jako pigułki + plakietka, bez wyboru przykłady opcji). Stuknięcie = półarkusz
  `RecipeFilterPickerSheet` (`.medium/.large`, nagłówek `compact`, „Wyczyść” tylko swojej grupy, stopka „N z M” +
  „Gotowe”) z TYMI SAMYMI kafelkami, piszącymi na żywo do kopii roboczej rodzica. Wszystkie podarkusze „Filtrów”
  idą jednym `sheet(item: $openPane)`. Filtry kategorii: kuchnia i okazje (`hidesEmptyOptions`) tak samo.
- Przepisy jak Poczta na iOS 26 (4.10.2026, Rafał: „na dole wyszukiwarka, po lewej button od filtrów”): pływający
  `RecipesSearchBar` NAD dolnym menu (`safeAreaInset` jak pigułka Planu, zwija się z menu, rozmyty pas od niego w dół —
  `.recipes` w `NavigationMenu.ownBottomEdge`): szklany krążek filtrów 50 pt (tint + `scCountBadge` przy filtrach) ·
  szklana kapsuła pola BEZ krzyżyka w środku · przy fokusie krążek z krzyżykiem (czyści i chowa klawiaturę); przy
  klawiaturze jedzie nad nią. Zwija się z menu skalą 0,84 + jego spadek (0,94 było niewidoczne). Plakietka filtrów
  stoi w nakładce NAD `GlassEffectContainer` (w grupie była przycinana i przykrywana przez pole).
  Zakładki kategorii pod tytułem (`RecipeScopeTabs`, 4.10.2026 — świadomy wyjątek od „zawężanie tylko w Filtrach”,
  prośba Rafała): Wszystkie · Śniadania · Obiady · Kolacje · Przekąski · Ulubione, szklane kapsuły, wybrana w tincie
  kategorii; TYLKO w stanie wyników (fraza / „Filtry”), także nad pustym stanem — w zwykłym widoku ich nie ma
  (Rafał 4.10.2026). Zawężają wyniki („kuskus” → Obiady), każda z liczbą trafień; bez frazy i filtrów zakres wraca
  do „Wszystkie”. Lista wyników przy zmianie zakładki animuje się jak przy szukaniu (wiersze) — wjazd
  całej listy z boku (#305) odrzucony („ma zostać po staremu”). Animuje się ZAZNACZENIE: kolor stoi w każdej kapsule
  i tylko PRZENIKA w miejscu (easeInOut 0,24) — przejeżdżająca soczewka odrzucona („bardziej delikatnie”); haptyka. `body(forRecipes:)` oddaje KILKA widoków — w `ZStack` zawsze owinięte w `VStack` (#303 bez niego
  nałożył nagłówek, karuzelę i sekcje na siebie).
  Przejścia (4.10.2026, „przeskakuje, szczególnie z karuzelą”): stany leżą w `ZStack` od góry (w `VStack` wchodzący
  stał pod wychodzącym i podskakiwał); zwykły widok liczy się z `browseRecipes` (dieta + filtry kategorii, BEZ frazy
  i „Filtrów”) i STOI pod wynikami przezroczysty (karuzela nie buduje się od nowa), zwijany do zera po zgaśnięciu
  (`browseLayerCollapsed`); jeden ruch `RecipesView.stateMotion`. Pusto w wynikach = `RecipeNoResultsView` (bez karty
  i bez nagłówka „0 przepisów”: szklany krążek powodu z podskokiem, „Nic dla „fraza””, akcje w szkle — najpierw
  „Wszystkie kategorie · N”, „Pokaż mimo diety”, potem „Wyczyść filtry / frazę”).
  Na górze sam `EditorialPageHeader("Przepisy")` (`EditorialRecipesHeader` usunięty). Fraza ALBO filtry z „Filtrów”
  = STAN WYNIKÓW, jeden dla obu: `RecipeResultsHeader` (etykieta, duża liczba, „fraza” · filtry, szklane „Wyczyść”)
  i JEDNA płaska lista `RecipeRowStack` — bez karuzeli i sekcji („nie może być mocnego podziału na sekcje”); przy
  frazie najpierw nazwy zaczynające się nią, potem słowo, reszta nazw, sam opis. Dieta z profilu i filtry jednej
  kategorii zostają w zwykłym widoku (filtry kategorii = plakietka na strzałce sekcji).
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
- Szczegóły posiłku otwierają się w GOTOWYM stanie (6.10.2026 — dawny wjazd z `hasAppeared`, osiadaniem zdjęcia
  z 1,12 i kaskadą sekcji USUNIĘTY); arkusz ma rogi 40 pt i KRYJĄCE tło prezentacji (`recipeDetailSheet()`
  w `RecipeDetail.swift`) we wszystkich miejscach otwarcia — przy `.clear` na pierwszych klatkach wjazdu prześwitywała
  na dole biała kreska ekranu pod spodem (24.09.2026).
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
- „Dodaj do planu” ze szczegółów (`AddToPlanSheet`, od nowa w rundzie 14 — „paskudny, zrób porządnie”; od 6.10.2026
  ekran stosu szczegółów, `isPushed`): TYLKO znane klocki. Nagłówek = zdjęcie dania (`EditorialRecipeCover` 52 pt)
  + nazwa + fakty (czas, kcal); „Dodaj do planu” i „wstecz” w pasku systemu (w samodzielnym arkuszu — tylko podgląd —
  eyebrow i krzyżyk). „Kiedy” = tydzień w karcie dokładnie jak `EditorialWeekBar`
  (podpis „TEN TYDZIEŃ · …”, „Wróć do dziś”, strzałki 26 pt, przejeżdżające podkreślenie, przeciąganie
  w bok, miniony dzień przekreślony i nieklikalny, liczby rolują). „Posiłek” = od 24.09 kafle pór, układ wg liczby pór
  (`SlotTileLayout`: 1–2 poziome w rzędzie, 3 pionowe obok siebie, 4 = 2 × 2 poziome, 5–6 = 3 kolumny pionowe;
  ikona w kolorze pory, nazwa, godzina z `mealSlotSchedule` — i NIC więcej (runda 20: danie w kaflach „brzydkie”); podmianę mówi JEDNA karta „ZAMIENISZ · danie” ze zdjęciem nad zdaniem stopki;
  wybrany = `scChoiceSurface(.tile)` w `cozyAccent`) — lista wierszy z radiem odpadła („nie do końca mi się
  podoba”). „Dla kogo” = `PlanAudienceChips`. „Porcje” = szklany przycisk z liczbą porcji OBOK „Dodaj do planu” (`portionsButton`) → arkusz
  `portionsSheet` z `SCPortionSummary` + listą `SCPortionRow` (`Components/SCPortionKit.swift` — ten sam zestaw co
  arkusz porcji w szczegółach, 4.10.2026; linia „Razem” + wiersze z systemowym `Stepper`); suma ponad 12 = minus działa, zapis czeka (`portionsOverLimit`); jeden wiersz
  porcji łącznych tylko przed listą domowników / przy dołączaniu do dania w porze. Stopka `scSheetFooter`: rolujące zdanie „Środa, 24 września · Obiad” (+ „dla całego domu”) i przycisk „Dodaj do planu” / „Zamień w planie” / „Już jest w planie”. Sekcje
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
  wybrana osoba rozwija imię na tincie (`matchedGeometryEffect`, sprężyna). Arkusz NIE ma podtytułu
  (24.09.2026: „Twój dzień · 3 z 3 posiłków — bez sensu”; w Kalendarzu „1 z 5 zjedzone” też usunięte) — nie wracać. Pełnoszerokościowe zakładki z rundy 11
  odpadły. Kalendarz NIE ma przełącznika — tylko „ja” (runda 11).
  Oś dnia dalej pokazuje dania wszystkich obok siebie — zmieniło się tylko to, co się sumuje.
- „Wybierz przepis” w Planie, gdy w porze stoi INNE danie kogoś z wybranego „Dla kogo” (27.09.2026): nad przyciskiem
  `PlanSlotConflictCard` (strój „ZAMIENISZ”: zdjęcie, „OBIAD · ANIA MA JUŻ”, przełącznik „Zamień dla wszystkich /
  Dodaj obok”, domyślnie zamiana); przycisk idzie za wyborem („Zamień w planie”). Zamiana zabiera tamtemu daniu TYLKO
  osoby, które dostają nowe — danie bez nikogo znika (`removeWeekSlot`), reszta zostaje przy swoim (zawężone „Dla kogo”).
- `DayPager` (runda 11): nowy dzień wchodzi do drzewa BEZ animacji, gdy strona jest niewidoczna
  (między zjazdem a wjazdem), a przewijanie ma `.id` dnia — pełny ↔ pusty dzień szarpał wjazdem.
  Powrót do bieżącego tygodnia w pasku dni = SAM krążek z ikoną cofania (`SCWeekTodayButton`, 26 pt jak strzałki,
  terakota soft; 27.09.2026) — pigułka „↩ Wróć do dziś” zabierała miejsce i podpis tygodnia malał. Jeden komponent
  w pasku Planu/Kalendarza (`EditorialWeekBar`) i w „Dodaj do planu”.
- Nagłówek Planu = koszyk (z plakietką liczby do kupienia) i „…”. Pigułkę „✦ Ułóż” i jej arkusz „Ułożę Ci ten
  tydzień” (`PlanAssistantPill`, `PlanAssistantIntroSheet`) USUNIĘTO 4.10.2026 na prośbę Rafała — do Asystenta
  prowadzi zakładka i „Zaplanuj tydzień z asystentem” w „…”; nie wracać. Nagłówek dnia na osi = nazwa dnia
  i „DZIŚ” — plakietka „3 z 5” (kropki pór, `SCPipsBadge`) też usunięta. Karty pustego tygodnia nad osią NIE MA.
  Odstęp pasek dni → nazwa dnia = 14 pt w `PlanDayTimeline`, zero pod paskiem (jak w Kalendarzu). Plakietka
  `scCountBadge` bez kremowej obwódki (krążki są szkłem) i bez `GlassEffectContainer` wokół koszyka — grupa
  szkła nie może trzymać czegoś, co wystaje poza krążek. Kalendarz też bez plakietki „2 z 3” (4.10.2026).
  Pusta pora (`PlanTimelineEmptyRow`, 4.10.2026) = przerywany obrys z ikoną pory w jej kolorze, nazwą pory i szklanym
  „+” w kolorze pory — bez „Nic nie zaplanowano” / „Wybierz przepis” (powtarzały się w każdym wierszu). Obrys 56 pt, ikona
  i „+” 35 pt (52 „za małe”, 60 „za duże”). Strzałki
  i gest tygodnia (Plan) zaznaczają ZAWSZE poniedziałek nowego tygodnia (`DatesViewModel`); dziś daje
  „Wróć do dziś”. Tydzień ma TYLKO Plan (`SessionStore.datesViewModel`, też jego arkusze); zakładka Dziś trzyma
  swoje trzy dni (6.10.2026 — osobny tydzień Kalendarza z 4.10 usunięty). Socket słucha jednego tygodnia, więc wejście na zakładkę woła
  `MealCalendarStore.observeWeek` (inny tydzień = jedno odświeżenie). Loader: kafle dni to szkło w jednym
  `GlassEffectContainer`, kolor dnia wznosi się w szkle. Wiersz przepisu na listach (`EditorialRecipeRow`) = „min · kcal”, bez białka. Przełącznik osób
  w arkuszu „Cel dnia” ma wysokość krzyżyka (`SCSheetIconLabel.size`).
- „Dla kogo” w „Wybierz przepis” i „Dodaj do planu” (4.10.2026) = JEDEN mechanizm
  (`WeeklyPlan/Components/PlanAudiencePicker.swift`): szklany `PlanAudienceButton` obok przycisku zapisu (awatary
  wybranych / domek) → SYSTEMOWE menu iOS (od 4.10.2026 wieczorem, „uprościć”): `Toggle` „Cały dom”, sekcja „Osoby”
  z ptaszkami, `menuActionDismissBehavior(.disabled)` — zostaje otwarte przy zaznaczaniu kilku; wszystkie = „Cały
  dom”. Arkusz `PlanAudienceSheet` usunięty. Chipy w przewijaniu
  „Dodaj do planu” odpadły. Porcje w „Dodaj do planu” — ikona `chart.pie.fill`. Pusty stan Zakupów =
  `ShoppingEmptyHero` (szklany koszyk, wokół działy sklepu w swoich kolorach, unoszą się).
- Zakupy (4.10.2026): pasek postępu, który zjedzie pod górę, ma przypiętą kopię na szkle (`pinnedProgress`,
  pomiar `frame(in: .scrollView)`); „Na dziś” to NIE wiersz listy, tylko szklany przycisk przyklejony do dołu
  (`todayButton` w `.scSheetFooter`, ten sam `ShoppingTodayRow`).
- Puste stany Zakupów (`ProductsView`, 24.09.2026 — „design jest stary, uspójnij”) stoją na `RecipeListEmptyState` (ma teraz opcjonalny `eyebrow`): tydzień bez planu = „LISTA ZAKUPÓW · Tydzień bez planu” + „Ułóż z Asystentem” (przełącza zakładkę i zamyka arkusz) i „Wróć do Planu”; plan jest, lista pusta = „Lista jest pusta” bez akcji; „Na dziś” bez produktów i otwarta rewizja bez nowych = ptaszek w szałwii („Na dziś masz wszystko” + „Pokaż całą listę”); pusta historia — ten sam klocek. Karta z koszykiem 78 pt i dwoma szarymi chipami usunięta.
- Kalendarz bez linii pod talerzykami (runda 9: „Tym kończysz dzień”, „Następny: …”, „Potem: …” —
  „tego nie potrzebujemy”; `CalendarDayLine`/`CalendarDayNote` usunięte, wysokość idzie na talerz).
  Przełożenie dania (stuknięcie talerzyka) ROLUJE cyfry i tekst (`.numericText()`): wielki wiersz
  ma tożsamość „danie / pustka” (`headlineKey`), nie po daniu — między daniami roluje ZAWSZE, także „Zjedzone” ↔
  „za 4 h” (runda 23: klucz cyfry/słowa przenikał to kryciem i „nie było naszej animacji”). Runda 24 (24.09.2026): ŻADNEGO
  `.id`/krycia w podpisie ani nadpisie — danie ↔ pusta pora też roluje (wielki wiersz, nazwa jako pusty tekst w stałym przycisku,
  pierwsza pigułka o stałym id `lead` z ikoną `symbolEffect(.replace)`, nadpis z godziną ↔ bez). Pusty dzień nie potrzebuje klucza:
  każdy dzień to osobny widok z `.id` po dacie. Krzywa tekstu = `SCMotion.textRoll` (`smooth` 0,42 s, jak danie w arkuszu wyboru
  posiłku u Asystenta); `DayNavigationMotion.plateFade` to ta sama stała, więc zdjęcie kończy z tekstem. Nowe rolowanie tekstu
  gdziekolwiek → `SCMotion.textRoll`. Arkusz „Cel dnia” (Kalendarz i Plan) nie ma podtytułu.
  Stuknięcie w talerzyk, który talerz pokazałby sam (następny za zegarem), ZDEJMUJE przypięcie.
  Jasny motyw Kalendarza (1.10.2026, „dark super, light trochę gorzej”): światło sceny było strojone na czerni. W jasnym
  poświata i aureola świecą JASNĄ wersją koloru pory (`MealSlot.cozyGlow`, gotowanie — `cookingGlow`) i tylko pod
  talerzem, który woła (`CalendarPlateItem.glow(in:)`; przygaszone talerze bez poświaty — dawała szarą winietę), gęstszy
  środek poświaty, aureola o 40 % ciszej; cień talerza ciepły brąz 0,14 na promieniu 16 (czarny 0,22 / 26 zostawiał
  szary półksiężyc); zjedzone bez krycia (prześwitywał cień) — słabsze kolory + krem 0,3 na zdjęciu; obwódka talerza
  0,14; krążki pod pieczątką i „play” = `scCardSurface` + `scCardStroke` (`CalendarPlateWell`); talerz bez zdjęcia —
  ciepła biel z tintem pory i ikona w kolorze pory zamiast gradientu z czernią; talerzyki w pasku przygaszone słabiej
  (0,92 / zjedzone 0,72). Ciemny motyw bez zmian.
- KAŻDY arkusz poza szczegółami posiłku (27.09.2026, Rafał: „image, subtitle, title, X”) ma nagłówek
  jak „Ułożę Ci ten tydzień”: kafelek z ikoną (`SCHeaderIconWell`) · eyebrow w kolorze akcentu · tytuł ·
  krzyżyk. `AssistantSheetScaffold`/`AssistantSheetHeader`, `LegalDocumentSheet` i `ShoppingSheetHeader`
  mają `icon:`/`accent:`; w arkuszach Ustawień kafelek i eyebrow biorą kolor wiersza, który je otwiera.
  Świadomie bez kafelka: `AddToPlanSheet` (tę rolę gra zdjęcie dania), `AssistantOptionsStorySheet`
  (pełne zdjęcie jak szczegóły posiłku), `AssistantHowItWorksView` (przepływ kroków). Nowy arkusz =
  od razu z `icon:`.
- Nagłówek arkusza = JEDEN, `EditorialSheetHeader` (4.10.2026, Rafał: „1:1 wszędzie tak samo — globalny komponent
  ze slotami”): `icon` albo `leading` (własny widok, np. zdjęcie dania w „Dodaj do planu”), `eyebrow` (pusty = bez
  wiersza), `title`, `subtitle`, `accessory` (akcje obok krzyżyka), krzyżyk `SCSheetCloseButton`, `compact`.
  `ShoppingSheetHeader` i `AssistantSheetHeader` to nakładki na niego; arkusz wyjścia z Gotuj też na nim (krzyżyk =
  „Gotuj dalej”). Własny układ mają tylko arkusze ze zdjęciem na całą górę (szczegóły posiłku, wybór posiłku u Asystenta).
  Krążki nagłówka = czyste szkło + miękki cień (jak natywne szklane przyciski iOS 26); jasny tint z 4.10 robił
  z nich płaskie guziki „po staremu” — nie wracać. Zakupy: pasek nawigacji SCHOWANY (`.toolbar(.hidden)`), pusty
  pasek łapał stuknięcia w krzyżyk i „…” mimo `NavBarHitTestPassthrough`.
- Wspólne kontrolki (runda 8): nagłówek arkusza = `EditorialSheetHeader` z opcjonalnym `icon`
  (kafelek `SCHeaderIconWell` w tincie akcentu), `accent` (kolor eyebrow) i `subtitle` — nie rysować
  nagłówka z kafelkiem ręcznie (stoją na nim filtry, lista kategorii, wybór do planu, dział składników,
  gospodarstwo). Pole szukania = `SCSearchField` (kapsuła 44 pt, krzyżyk, obwódka przy fokusie; przy
  fokusie z zewnątrz obwódkę podaje ekran przez `isActive`) — wyjątki to pływające pole
  rozmów Asystenta i pasek szukania Przepisów (`RecipesSearchBar`). Wybór „jedno z wielu” = `SCRadioMark` (obwódka + kropka), „wiele” = `SCCheckbox`.
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
  to dwuwierszowy przycisk „Zaproś domownika · Link dla jednej osoby · ważny 7 dni” NAD „Opuść”; od 4.10.2026
  zaproszenie to OSTATNI wiersz karty „Domownicy” (`inviteRow`: przerywane kółko z plusem w miejscu awatara, tytuł
  w terakocie, warunki linku, szklany krążek udostępniania), a w stopce zostaje samo „Opuść”. Wcześniej: nazwa w nagłówku
  z ołówkiem obok krzyżyka (`EditorialSheetHeader` ma opcjonalne `accessory`; zmienia właściciel
  przez `households:updateName`, pozostali dociągają ją po `membersChanged`/`UPDATE_NAME` odczytem
  `households:findById`), zaproszenie jako wiersz listy (link 7 dni), „Opuść” na dole. NIC więcej — Rafał:
  „tylko najważniejsze rzeczy”, bez powtarzania nazwy, liczników i objaśnień. „Czego nie jem” (wykluczone
  składniki + limit czasu na danie) USUNIĘTE: walidator planu i prompt dalej czytają te kolumny,
  więc każdy zapis diety wysyła `excludedIngredientIds: []` + `maxPrepTimeMinutes: null`,
  a `loadUserPreferences` jednorazowo czyści stare wartości na serwerze. Polityka i regulamin 1.1
  (2.10.2026) już ich nie wymieniają, ekran zgody Asystenta też nie. Teksty w `AuthFooterView`
  są 1:1 ze stroną (scoffie-web `src/pages/{privacy,terms}`); po zmianie — Android
  `python scripts/gen-legal-content.py`.
- Wygląd sprawdzamy NA ZRZUCIE, nie po samym buildzie: `SCOFFIE_DEBUG_OPTIONS=0…n|card|buttons|
  auth|auth-error|legal|thought|plate|plate-gotujesz|tour-0…6|welcome-1…5|asystent-0…2|asystent-jak` (+ `SCOFFIE_DEBUG_OPTIONS_AUTOPLAY` do nagrania animacji) otwiera ekrany
  z `Previews/AssistantOptionsDebugScreen.swift` bez sesji i bez alertów systemowych; tylko DEBUG.
  Uruchamiać na OSOBNYM symulatorze (`SIMCTL_CHILD_…=… xcrun simctl launch`), nie na roboczym.
- Przewodnik „Poznaj aplikację” (`TourStep`, `Views/Tour/`, 24.09.2026 wieczór — Rafał: „podmień
  przewodnik”): krok = SAM PLAKAT z R2 (`TourStepView`) — pionowa grafika z własnym nagłówkiem, opisem
  i kartami aplikacji, te same co zrzuty w App Store. Bez `SCStepHeader` i karty funkcji nad/pod nim
  (dublowałyby tekst plakatu). Plakat mieści się W CAŁOŚCI bez przewijania: wysokość strony nad stopką,
  szerokość z proporcji 1080 : 2344, na środku; przed pobraniem tint koloru kroku w tym samym rozmiarze.
  `TourStep.title`/`lead` = tekst plakatu słowo w słowo — tylko dla VoiceOver. Pliki:
  `https://img.scoffie.app/onboarding/tour-{plan,recipes,shopping,assistant,settings}-v2.webp`
  (1080 × 2344, WebP q85, ~150–210 KB; `-v1` = dawne poziome ilustracje, zostają dla starszych wersji).
  Bucket `scoffie` (produkcyjny — lokalny token R2 w `.env` backendu jest nieaktualny, wysyłka przez
  `railway run` z katalogu backendu), `Cache-Control: immutable` na rok → NOWA grafika = NOWA wersja
  w nazwie (`TourStep.image(_:version:)`), nigdy nadpisanie. Wariant `CachedAsyncImage(.poster)` (do
  2400 px) — przy `.large` (1200 px) drobny tekst plakatu się rozmywał. `TourStep.prefetchImages()`
  rusza na ekranie logowania (`AuthView`) i przy wejściu w przepływ. Powitanie (`TourIntroView`)
  i „Teraz my poznajmy Ciebie” (`TourDoneView`) zostają rysowane w aplikacji.
- Przewodnik + kreator profilu = JEDEN przepływ w `WelcomeView` (24.09.2026, Rafał: „wszystko w jednym
  wielkim stepperze, aby nie przełączać”): `tourPhase` (0 powitanie, 1…5 kroki, 6 „Teraz my poznajmy
  Ciebie”, `nil` = kreator `step` 1…5), jedna stopka, jeden pasek na 11 odcinków, strony jadą na bok także
  na styku; „Wstecz” z 1. kroku kreatora wraca do przewodnika, „Pomiń…” skacze do kreatora.
  `FeatureTourView` usunięty; `WelcomeFlowView` tylko decyduje, czy przewodnik jest (pełna ścieżka i brak
  `TourCompletion`). Strony przewodnika dostają `padding(.bottom, footerHeight)`, bo stopka kreatora jest
  nakładką (pola nad klawiaturą). „Wstecz” w jednej linii z „Dalej”, po lewej
  (`SCStepFooter(backPlacement: .besidePrimary)`) w całym przepływie — od wprowadzenia v2 także u Asystenta.
  Krok 1 kreatora = układ Ustawień → „Twoje dane”: karta „Profil” (awatar + imię w miejscu, ołówek)
  i karta „Sylwetka” (płeć, rok z wiekiem, wzrost, waga na `scChipBg`) z `BodyMetricsSummaryRow` (BMI
  + kcal na utrzymanie, wspólny z `ProfileDetailsSheet`) — Rafał: „tak smutno wygląda”. Krok 1 mieści się
  BEZ przewijania (także 16e): karta profilu bez etykiety, „🔒 Tylko do obliczeń” w wierszu etykiety
  „Sylwetka”, odstępy 16. Krok 2: treningi w karcie „Aktywność” jak w „Twoich danych”. Krok 3: makro
  ZOSTAJE osobną sekcją „Makroskładniki” z trzema paskami, gramami i procentami (Rafał 24.09.2026: „daj
  tak samo jak było wcześniej” — połączenie z kartą celu w jeden pasek proporcji odrzucone). Krok 5 jak Ustawienia →
  Gospodarstwo: nazwa w miejscu (kafelek domu, ołówek) z podpowiedziami „Dom / Nasz dom / Mieszkanie”,
  karta „Domownicy” (Ty + „TY” / „WŁAŚCICIEL”, pod kreską „Domownicy dołączą z linku”). Licznik kroków
  w stopce ma szerokość z treści — „11/11” nie łamie się.
- Kreator profilu (`WelcomeView`) od 24.09.2026 BEZ paska nawigacji i BEZ „Wyloguj” (Rafał: „wywal”):
  nagłówek kroku od góry jak w przewodniku (`WelcomeLayout.topInset = TourLayout.top`), górny brzeg
  treści gaśnie przez `scScrollEdgeFade`. Wyjście z kreatora = dokończyć go albo zamknąć aplikację. Kreatora profilu (`Welcome*`) to NIE dotyczy — Rafał rozróżnia „onboarding aplikacji”
  (przewodnik) od „onboardingu usera” (kreator) i kreator ma zostać, jak jest.
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
