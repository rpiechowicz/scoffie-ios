# Gotuj — tryb gotowania krok po kroku

Data założenia: 2026-09-29 · Status: **design v1 zatwierdzony 30.09 (§13)** · Platforma v1: iOS (backend globalny)

Kanwa designu (Claude Design): https://claude.ai/artifact/DEnbNj45aY4X9Xaq1siV4D — tylko ekrany zatwierdzone.
Gdzie §4 i §8 mówią co innego niż §13, **§13 ma pierwszeństwo**.

Ten plik jest jedynym źródłem prawdy o funkcji. Każda decyzja trafia do tabeli [Decyzje](#3-decyzje)
z datą; zmiana decyzji = nowy wiersz, stary zostaje przekreślony, nie znika.

---

## 1. Wizja w jednym akapicie

Użytkownik stoi w kuchni, stuka **Gotuj** i przechodzi w pełnoekranowy tryb, który prowadzi go przez
posiłek jak ktoś, kto gotował to danie sto razy. Na starcie widzi, co gotuje, dla ilu porcji, co
wyjąć i przygotować, i dostaje kilka rad od kucharza. Potem idzie krok po kroku: każdy krok mówi
jednym zdaniem, co zrobić teraz, a pod spodem prostymi słowami — jak. Ilości stoją przy kroku
(„2 jajka”, „połowa koperku, 5 g”), więc nikt nie przewija listy składników. Tam, gdzie coś się
gotuje, piecze albo chłodzi, jednym stuknięciem startuje systemowy timer — widoczny na ekranie
blokady, w Dynamic Island i dzwoniący nawet przy wyciszonym telefonie. Scenariusz układa pracę tak,
żeby wszystko było gotowe naraz: piekarnik nagrzewa się wtedy, kiedy będzie potrzebny, a mizerię
robisz, gdy kotlety dochodzą w piekarniku.

## 2. Zakres

### v1 (budujemy)

- Scenariusz gotowania dla **każdego przepisu katalogu** (1072) — napisany i sprawdzony **przed**
  wejściem użytkownika na widok. Żadnego generowania w locie.
- Scenariusze dla **przepisów domów** (asystent, własne, kopie z udostępnienia) — generowane w tle
  przy zapisie przepisu tym samym systemem (§7.6). Też gotowe przed wejściem.
- Pełnoekranowy widok Gotuj: powitanie → kroki → zakończenie.
- Skalowanie ilości do liczby porcji z zaokrąglaniem (§5.4).
- Timery systemowe (AlarmKit), Live Activity, Dynamic Island, ekran blokady, StandBy.
- Trwała sesja: wyjście, zablokowanie telefonu, zabicie apki przez system → wracasz tam, gdzie byłeś.
- Pełne animacje przejść, timerów i zakończenia.

### Poza v1

- Przepisy z Cookidoo — tam gotuje Thermomix, zostaje „Gotuj w Thermomixie”.
- Android — backend od początku globalny, więc Android podłączy się później bez zmian w danych.
- Kilka przepisów na jednej osi czasu (danie + dodatek `SIDE`) — model danych ma to dopuszczać (§6).

### v2 — pomysły zapisane, żeby nie uciekły

- **Zapytaj asystenta w trakcie gotowania** („czy dobrze mi idzie?”, „czym zastąpić śmietanę?”)
  z kontekstem sesji: przepis, krok, działające timery, porcje.
- **Zdjęcie potrawy** („czy tak ma wyglądać?”). Twarda zasada na przyszłość: asystent **nigdy**
  nie potwierdza bezpieczeństwa (np. dopieczenia drobiu) na podstawie zdjęcia — zawsze odsyła do
  temperatury w środku / czasu / wskazówki z kroku. Do zrobienia przy v2: koszt modelu z obrazem,
  polityka prywatności, zgoda asystenta.
- Czytanie kroków na głos (polski głos systemowy) i sterowanie głosem („dalej”, „ile zostało?”).
- Siri / App Shortcuts: „następny krok w Scoffie”.

Co v1 robi dla v2 już teraz: sesja gotowania ma jeden serializowalny stan (§8.6), który da się
przekazać asystentowi, a układ ekranu kroku ma zarezerwowane miejsce na przycisk asystenta.

## 3. Decyzje

| # | Data | Decyzja | Status |
|---|---|---|---|
| D1 | 29.09 | Scenariusz osobno dla każdego posiłku, oparty o przygotowanie i kroki; każdy krok rozbudowany tekstowo, prostym językiem | przyjęte |
| D2 | 29.09 | Scenariusz powstaje przez system (prompt budowany automatem → AI → walidatory → przegląd), nie ręcznie i nie w locie | przyjęte |
| D3 | 29.09 | Scenariusz globalny (backend, niezależny od platformy) | przyjęte |
| D4 | 29.09 | Ilości przy kroku, skalowane do porcji i zaokrąglane | przyjęte |
| D5 | 29.09 | Timery na AlarmKit (dzwonią mimo wyciszenia i Focus), prezentacja w Live Activity / Dynamic Island | przyjęte |
| D6 | 29.09 | Widok Gotuj jako pełny ekran (`fullScreenCover`), nie arkusz — nie da się go zamknąć przypadkiem | przyjęte |
| D7 | 29.09 | Bez listy do odhaczania składników — powitanie pokazuje, co przygotować, i tyle | przyjęte |
| D8 | 29.09 | Cookidoo poza zakresem; Android i Windows nie są ograniczeniem planu | przyjęte |
| D9 | 29.09 | Poziom szczegółu „pośredni”: nie tłumaczymy podstaw, tłumaczymy techniki (§5.1) | przyjęte |
| D10 | 29.09 | Przepis wzorcowy do designu i do promptu: **Kotlet de volaille z ziemniakami i mizerią** (§10) | przyjęte |
| D11 | 29.09 | Porcje: domyślnie tyle, ile w planie; na powitaniu widać „Gotujesz 2 porcje” i można zmienić tylko na tę sesję, bez ruszania planu (§4.3) | propozycja |
| D12 | 29.09 | ~~Wejścia: szczegóły posiłku/przepisu + skrót na wielkim talerzu Kalendarza w oknie „Pora gotować” + akcja w powiadomieniu „Pora gotować” (§4.1)~~ → D16 | zastąpione |
| D13 | 29.09 | Paywall: v1 za darmo dla wszystkich, gotowe pod flagę; decyzja o płatności razem z v2 (§12) | przyjęte 30.09 |
| D14 | 29.09 | Kolejność prac: dokument → scenariusz wzorcowy → Claude Design → model danych → system → iOS (§11) | propozycja |
| D15 | 29.09 | Scenariusz jest **zapisany w bazie na stałe** przy każdym przepisie — jak składniki i kroki. Uzupełnienie całego katalogu dopiero po designie | przyjęte |
| D16 | 29.09 | Gotuj na talerzu Kalendarza **zawsze** (nie tylko w oknie „Pora gotować”) — ktoś może gotować 2 h wcześniej, nie blokujemy. W oknie „Pora gotować” pigułka tylko mocniej akcentowana (§4.1) | przyjęte |
| D17 | 29.09 | ~~Design startuje od ekranu kroku: 4 kierunki na kanwie~~ → design zamknięty, D18–D27 | zastąpione |
| D18 | 30.09 | Ekran kroku: pasek T2, scena ze zdjęciem, składniki w szufladzie → arkusz, stopka F2b (§13.2) | przyjęte |
| D19 | 30.09 | Powitanie P1: porcje ze stepperem, szuflady **Składniki** i **Rady kucharza**, bez sprzętu (§13.1) | przyjęte |
| D20 | 30.09 | Zakończenie minimalistyczne: statystyki, rada „na następny raz”, ocena w wierszu, „Zjedzone”; uwagi po kciuku w arkuszu (§13.3) | przyjęte |
| D21 | 30.09 | Gotowanie spoza planu: po „Zjedzone” przepis **sam** trafia do dzisiejszego planu i jest odhaczony — bez żadnego UI (§13.4) | przyjęte |
| D22 | 30.09 | X w trakcie → arkusz „Wychodzisz?” (stany 0/1/2 timery); po wstrzymaniu talerz w Kalendarzu z pierścieniem kroków (§13.5) | przyjęte |
| D23 | 30.09 | Wejście z Kalendarza: przycisk play **na talerzu, z prawej**; pieczątka „zjedzone” z lewej jako **kółko z ptaszkiem** — zmiana istniejącego talerza (§13.6) | przyjęte |
| D24 | 30.09 | Wejście ze szczegółów przepisu: stopka „Dodaj do planu \| Gotuj” (Przepisy) albo „Zapisz porcje \| Gotuj” (Kalendarz); Cookidoo bez Gotuj (§13.6) | przyjęte |
| D25 | 30.09 | Dynamic Island, ekran blokady: jedna reguła — działa timer → wokół zdjęcia pierścień timera, brak → pierścień kroków; stany 0/1/2/czeka (§13.7) | przyjęte |
| D26 | 30.09 | ~~Kapsuła u góry ekranu kroku pokazuje tylko timery **spoza** bieżącego kroku~~ → timery przeniesione na dół (D34) | zastąpione |
| D27 | 30.09 | Scenariusz dostaje pola: rada „na następny raz”, zakres czasu timera (min–max); uwagi z oceny zbieramy z sesji (§13.8) | przyjęte |
| D28 | 30.09 | Auto-wpis do planu (§13.4): dania w tej porze **nikt nie zjadł → zastępujemy; ktoś już odhaczył → dopisujemy obok** | przyjęte |
| D29 | 30.09 | Przepisy trywialne (np. jogurt z granolą) **bez Gotuj** — system pisania oznacza je jako `SKIPPED` z powodem, przycisku nie ma | przyjęte |
| D30 | 30.09 | Czas „po ludzku”: kroki „w międzyczasie” mogą rozjechać się z timerem o minutę–dwie — nie liczymy co do sekundy (zapas max(2 min, 20%)) | przyjęte |
| D31 | 30.09 | Praktyczne wskazówki są pożądane — zawsze mówimy, **jak ustawić piekarnik** (góra–dół / termoobieg / grill; domyślnie góra–dół), czym wyłożyć blachę itp. Nadal nie zmieniamy składników, ilości, czasów ani temperatur | przyjęte |
| D32 | 30.09 | Literówki i brak polskich znaków = błąd do poprawy przed publikacją | przyjęte |
| D33 | 30.09 | **Najwyżej dwa odliczania naraz**; timer tylko na czekanie od 4 min — krótka, aktywna czynność przy garnku idzie tekstem z „po czym poznać” | przyjęte |
| D34 | 30.09 | **Dok na dole ekranu kroku**: wyspa ‹ · Składniki N · › zawsze w tym samym miejscu; **timery osobno nad nią** — każdy jako własna kapsuła, bez wspólnego kontenera. Jeden timer = cała szerokość (nazwa, czas, jeden przycisk, nic więcej); dwa = dwie kapsuły obok siebie. Najwyżej 2 (1 aktywny + 1 do włączenia albo 2 aktywne). Timer kroku startuje w kapsule (pulsuje łagodnie), nie w treści; w nagłówku nie ma już kapsuły timera (§13.2) | przyjęte |
| D35 | 30.09 | Koniec timera w apce = **pełny ekran**: pierścień, czas po terminie liczony w górę (zewnętrzny łuk co minutę), „Jeszcze chwilę?” +1 / +2 / +5 min, **Gotowe — dalej**, Wycisz; inne trwające timery wierszem „leci dalej”. Po „Wycisz” kapsuła timera pulsuje mocno, dopóki nie klikniesz Gotowe | przyjęte |
| D36 | 30.09 | Składniki: ikona produktu w kolorze **kategorii** (warzywa, nabiał, przyprawy, mięso, zboża/tłuszcze), ilości neutralne i pogrubione; „już w daniu” przygaszone z ptaszkiem. Przyprawy w miarach kuchennych (`kitchenMeasure`) | przyjęte |
| D37 | 30.09 | Teksty scenariusza pod dok (zasady .5, zmierzone w przeglądarce): **tytuł kroku ≤ 30 znaków** — krótkie polecenie, dwie linijki przy 40 pt (gdyby wyszły trzy, iOS zmniejsza do 32 pt); **treść ≤ 260** (tytuł + treść + adnotacja mieszczą się nad dokiem z dwoma timerami; scena i tak przewija się pod dokiem); **`startLabel` ≤ 20** — sam warunek startu („Gdy woda zawrze”, „Kotlety na patelni”), bez czasu: kapsuła „do włączenia” pokazuje go zamiast nazwy, arkusz Timery jako „Start: gdy woda zawrze” | przyjęte |
| D38 | 1.10 | Zasady .6 (przegląd całego systemu z Codexem, noc 30.09/1.10) — kontrakt dla telefonu: **token `{count:…}` tylko w `body`** (telefon podstawia liczbę wyłącznie tam); **„+1/+2/+5 min” z D35 przedłuża TEN SAM krok** — scenariusz planuje, że następny krok główny rusza po „Gotowe — dalej”, stąd najwyżej 2 odliczania naraz; **nazwa timera to rzecz** („Ziemniaki”, „Ciasto”), dwa biegnące razem mają różne nazwy; **oczekiwanie „na noc” albo ponad 12 h bez timera** — krok „Wstaw do lodówki na noc”, następny zaczyna się od „Rano…” (sesja musi przetrwać do następnego dnia, §8.6); **drugi wariant urządzenia** (zdanie „W piekarniku: …” w przepisach airfryera) tylko jako rada kucharza na powitaniu | przyjęte |
| D39 | 1.10 | Wygląd Gotuj z tokenów: wartości z makiety przeniesione do scoffie-design (`tokens/cook.json`, `docs/GOTUJ.md`), iOS bierze je z wygenerowanego `SCCookTokens.swift` (pierwszy generowany plik Swift — tylko nowa funkcja); Android dostanie te same liczby | propozycja |
| D40 | 1.10 | Ustalenia ponad makietą (docs/GOTUJ.md): łuk timera = POZOSTAŁY czas; kolor timera — terakota, a gdy ma ją już inny żywy timer — szałwia; ikony i kolory składników = działy z Zakupów (zamiast #D4A373 i #1C2A23); opis kroku zawsze 16 pt pod tytułem; szuflady powitania otwierają arkusz do połowy | propozycja |
| D41 | 1.10 | Składniki kroku po `ingredientId`, którego katalog na telefonie nie ma — telefon bierze scenariusz RAZEM ze szczegółem przepisu (`recipes:findById`) i trzyma paczkę offline; bez zmian w API | przyjęte |
| D42 | 1.10 | E4 bez timerów systemowych: koniec timera w aplikacji = pełny ekran (otwiera się sam także po „Wstrzymaj”, jak alarm w Zegarze), w tle zwykłe powiadomienie; AlarmKit i Live Activity w E5 | przyjęte |
| D47 | 1.10 | Runda 5 testów: nowy timer do włączenia nie wypycha kapsuły, która już stoi — idzie do plakietki (kapsuły do włączenia od najstarszego, cofa „bieżący krok pierwszy” z D46); plakietka mówi jedno zdanie bez powtórzeń; krok bez składników ma pusty stan; arkusz wyjścia i talerz PS1 pokazują wszystkie trwające timery (zawijane / dopasowane do rzędu); „Pomiń” da się cofnąć — pominięty wraca jako „do włączenia”, gdy znów stoisz na jego kroku | przyjęte |
| D46 | 1.10 | Runda 4 testów: timer do włączenia zostaje w doku od swojego kroku (pominięty przy „Dalej” też), chowa się po cofnięciu przed jego krok, „Pomiń” go odprawia; dok o stałej wysokości (wyspa nie skacze przy pojawieniu się kapsuły), kapsuła jednym układem płynnie przechodzi pojedyncza ↔ para; zamiast „+N” plakietka ze stanem ukrytych timerów; tarcza końca timera jak stoper, teksty w kole; składniki w działach sklepu | przyjęte |
| D45 | 1.10 | Runda 3 testów: powitanie, kroki i zakończenie to JEDEN ekran (`CookScreen` — zdjęcie i krzyżyk stoją w miejscu, zmienia się treść, stopka i dok); Timery i Składniki to arkusze systemu (Składniki na pół ekranu, przewijanie rozwija na cały; Timery na wysokość treści), dzwoniący timer zamyka arkusz; najwyżej dwie kapsuły — dwa najdawniej włączone timery, wolne miejsce dla timera do włączenia, timer po czasie zawsze w doku (cofa „do trzech” z D44); każdy timer ma swój kolor (akcent i kolory pór; cofa regułę „terakota, a gdy zajęta — szałwia” z D40); pierścień kroków przelewa barwę klinem po pełnych odcinkach | przyjęte |
| D44 | 1.10 | Runda 2 testów: dok jak dolne menu aplikacji (wyspa 60 pt, boki 20, krawędź bezpiecznego obszaru), wyspa rozwija się w kartę Składniki spod przycisku; timery w stałej kolejności kroków (bez zamiany miejsc przy starcie), do trzech kapsuł obok siebie, w parze/trójce pierścień jest przyciskiem; karta Timery jedną listą bez sekcji; łuk timera ubywa zgodnie z zegarem; pierścień kroków 36 pt jak krzyżyk, zaokrąglony, z przelewaniem barwy; alarm bez „leci dalej” | przyjęte |
| D43 | 1.10 | „Play” na talerzu Kalendarza ZAWSZE przy daniu z paczką scenariusza w telefonie — każdy dzień, każda pora (Rafał: „nie trzymaj się czasu gotowania”); pełna terakota z aureolą, gdy talerz „woła” (pora gotować / jeść, wstrzymane gotowanie), poza tym wariant „soft” — „mocniejszy w oknie Pora gotować” (§13.6). Talerz PS1 = sesja TEGO wpisu planu (przepis + dzień + pora); pierścień kroków z realną przerwą 3 pt (makieta: końce się stykają) | propozycja |

## 4. Przepływ użytkownika

### 4.1 Wejścia

1. **Szczegóły posiłku / przepisu** — przycisk **Gotuj** w stopce akcji (`AssistantStickyFooter`),
   obok akcji planu. Jedno miejsce implementacji, działa i z Kalendarza (zdjęcie talerza otwiera
   szczegóły), i z Przepisów.
2. **Wielki talerz w Kalendarzu** — pigułka **Gotuj** (wariant soft) obok pieczątki, **zawsze**
   dla dania ze scenariuszem (D16): kto chce gotować 2 h wcześniej, nie może być blokowany.
   W oknie „Pora gotować” (`CalendarPlate`, `isCooking`) pigułka jest mocniej akcentowana,
   razem z „oddechem” talerza; poza oknem stoi spokojnie. Zjedzone danie — pigułki nie ma.
3. **Powiadomienie „Pora gotować”** (`MealReminderService`) — akcja **Gotuj** otwiera od razu
   powitanie trybu gotowania.
4. **Trwająca sesja** — na talerzu i w szczegółach zamiast „Gotuj” stoi **Wróć do gotowania**
   (krok 5/12 · najbliższy timer). Stuknięcie w Live Activity też wraca do sesji.

Przycisk Gotuj jest tylko tam, gdzie scenariusz ma status `PUBLISHED` i jest w pamięci telefonu (§7.7).
Brak scenariusza = brak przycisku, bez wyszarzonych obietnic.

### 4.2 Szkielet widoku

```
Powitanie ──► Krok 1 ──► Krok 2 ──► … ──► Krok N ──► Smacznego
                 ▲                              │
                 └──── wstecz / skok z paska ◄──┘
Tacka timerów: przez cały czas, ponad krokami
```

- Pełny ekran, `interactiveDismissDisabled`. Zamknięcie (✕) pyta: **Wstrzymaj** (sesja zostaje,
  timery lecą) albo **Zakończ gotowanie** (timery kasowane).
- Ekran nie gaśnie (`isIdleTimerDisabled`) przez cały czas trybu.
- Nawigacja: duży przycisk **Dalej** w strefie kciuka + przesunięcie w bok. Wstecz zawsze możliwe.
- Pasek postępu z segmentami — stuknięcie w segment pokazuje listę kroków do skoku.

### 4.3 Powitanie

- Zdjęcie dania (wejście: to samo zdjęcie co w szczegółach, przejście `matchedGeometryEffect`),
  nazwa, czas łączny, trudność.
- **„Gotujesz 2 porcje”** ze stepperem. Domyślnie: suma porcji domowników na ten posiłek z planu;
  wejście z Przepisów (poza planem) — porcje przepisu. Zmiana działa tylko w tej sesji, plan zostaje.
  Krok steppera: 1 porcja (połówki z planu zaokrąglamy w górę do dania, patrz §5.4).
- **Sprzęt** — ikony (piekarnik, patelnia, garnek, folia, tłuczek…).
- **Składniki** — lista z ilościami już przeskalowanymi. Tylko do przeczytania, bez odhaczania (D7).
- **Rady kucharza** — 2–3 krótkie pro tipy, które zmieniają wynik (np. „zawijaj ciasno i zakładaj
  boki do środka — od tego zależy, czy masło zostanie w kotlecie”).
- Przycisk **Zaczynamy**.

### 4.4 Krok

Warstwy od najważniejszej (czytelne z metra, gdy telefon stoi oparty o ścianę):

1. **Nagłówek** — jedno zdanie w trybie rozkazującym: co robisz teraz. Duży krój.
2. **Składniki kroku** — pigułki z ilością: „masło · 30 g”, „koperek · połowa, 5 g”. Kolor pory
   posiłku / kategorii, ikona produktu.
3. **Jak** — 1–4 zdania prostym językiem.
4. Opcjonalnie jedna z adnotacji: **Po czym poznać** (wskazówka zmysłowa lub temperatura),
   **Uwaga** (bezpieczeństwo), **Rada**.
5. **Karta timera** (jeśli krok ma czas) — w strefie kciuka, nad „Dalej”:
   nazwa + czas + przycisk startu, którego etykieta mówi, kiedy go nacisnąć:
   „Schowane — odliczaj 15 min”, „Woda wrze — odliczaj 20 min”.
6. **W międzyczasie** — gdy krok da się robić, podczas gdy coś się gotuje, nagłówek dostaje
   wstęgę „Ziemniaki się gotują — w tym czasie:”.

### 4.5 Timery

- Start tylko z karty w kroku, jednym stuknięciem. Po starcie karta **odlatuje do tacki timerów**
  (animacja lotu) i żyje tam niezależnie od kroków.
- **Timer oczekujący**: niewłączony timer czeka w doku od swojego kroku dalej — także pominięty
  przy „Dalej” (runda 4; wcześniej tylko „gdy woda zawrze”). Nie gubi się; znika po cofnięciu
  przed jego krok albo po „Pomiń”.
- **Zakres** („10–12 min”): odliczamy do dolnej granicy, alarm mówi „Sprawdź kolor — jeśli blade,
  jeszcze 2 min” z akcjami **Gotowe** / **+2 min** (górna granica jako podpowiedź).
- Kilka timerów naraz — tacka pokazuje wszystkie, najbliższy na górze.
- Koniec timera w apce: pełnoekranowa nakładka z haptyką i dźwiękiem, akcje z definicji timera.
  Poza apką: alert AlarmKit (dzwoni mimo wyciszenia i Focus), te same akcje przez App Intents.
- Timer pamiętany jako **data końca**, nie licznik — przeżywa zabicie apki (§8.6).

### 4.6 Zakończenie

„Smacznego” z animacją, podsumowanie (czas gotowania), **Oznacz jako zjedzone** (istniejące
`eatenByUserIds`) i kciuk oceny (istniejące oceny). Zamyka sesję i Live Activity.

### 4.7 Przerwania

| Sytuacja | Zachowanie |
|---|---|
| Wyjście z apki / blokada | Sesja trwa, timery w AlarmKit, Live Activity pokazuje krok i najbliższy timer |
| System zabił apkę | Po starcie: „Wróć do gotowania” (talerz, szczegóły, Live Activity) |
| Druga sesja na inny przepis | v1: jedna sesja naraz; start nowej pyta o zakończenie starej |
| Scenariusz zmienił się w trakcie | Sesja dokańcza na swojej wersji (trzymana lokalnie) |
| Brak sieci w kuchni | Scenariusz i zdjęcie w pamięci telefonu, tryb działa w całości offline |

## 5. Zasady pisania scenariusza

To jest serce promptu i walidatorów (§7). Zmiana zasad = nowa `rulesVersion` i ponowne przejście.

### 5.1 Poziom szczegółu (D9)

- **Nie tłumaczymy podstaw**: jak pokroić cebulę, jak obrać ziemniaki, jak zagotować wodę.
- **Tłumaczymy techniki**, od których zależy wynik: zawijanie roladek, panierka, zeszklenie,
  zasmażka, ubijanie piany, temperowanie czekolady, wyrabianie ciasta.
- **Zawsze mówimy, po czym poznać**, że etap skończony: kolor, zapach, konsystencja, temperatura
  w środku.
- Jeden krok = jedna czynność z perspektywy rąk (może mieć kilka ruchów, ale jeden cel).
  Typowo 8–14 kroków na obiad, 3–6 na śniadanie. Bez sztucznego rozdrabniania.

### 5.2 Język i ton

- Druga osoba, tryb rozkazujący, polszczyzna kuchenna, bez żargonu („podsmaż”, nie „zrumień
  metodą Maillarda”).
- Nagłówek ≤ 60 znaków, „jak” ≤ 320 znaków, adnotacja ≤ 140 znaków, rada kucharza ≤ 140 znaków.
- Każda informacja raz: nie powtarzamy w „jak” tego, co jest w nagłówku albo pigułce.
- Liczby w tekście **tylko przez tokeny** (§5.4), żeby skalowały się z porcjami — z wyjątkiem
  czasów, temperatur i rozmiarów („0,5 cm”, „180°C”) oraz liczby z jednostką przepisanej
  **dosłownie z kroków przepisu**, gdy nie jest ilością składnika z listy („naczynie ok. 1,5 l”,
  „100 ml zimnej wody”, gdy wody nie ma w składnikach — telefon jej przy kroku nie pokaże).
  _Zasady 2026-09-30.2, po pilocie E3b._

### 5.3 Układ pracy

- Scenariusz **wolno przestawiać** względem kroków przepisu, jeśli dzięki temu wszystko jest gotowe
  naraz (np. ziemniaki startują wcześniej, piekarnik nagrzewa się ~15 min przed użyciem, a nie na
  starcie).
- **Nie wolno** zmieniać składników, ilości, temperatur ani czasów poza zakresem przepisu.
- Każdy czas oczekiwania **od 4 minut** (gotowanie, pieczenie, chłodzenie, marynowanie) to timer.
  Krótka, aktywna czynność przy garnku („podsmaż cebulę ok. 3 min”, „smaż po 3 min z każdej strony”)
  idzie tekstem z czasem i „po czym poznać” — bez timera (D33).
- **Najwyżej dwa odliczania naraz** — przy trzecim użytkownik się gubi (D33, stany wyspy 0/1/2).
- Jeden czas z przepisu = jeden timer. „Piecz 20–25 min, w połowie obróć” to jeden timer, a „w połowie
  obróć” idzie do treści kroku albo alarmu (zasady 2026-09-30.2).
- Kroki „w międzyczasie” wskazują timer, pod którym się mieszczą — **po ludzku**: minuta–dwie różnicy
  to nie problem (D30).
- Krok nagrzewania zawsze mówi, jak ustawić piekarnik; praktyczne wskazówki (papier na blachę, jaki
  garnek) są mile widziane (D31). _Zasady 2026-09-30.3._

### 5.4 Ilości, porcje, zaokrąglanie

- Składnik wchodzi do kroku **z ilością** tam, gdzie trafia do dania; później może być tylko
  przywołany bez ilości („z talerzy z panierką”). Suma ilości danego składnika = ilość w przepisie.
- Części opisujemy słowem i liczbą: „połowa koperku, 5 g”, „reszta oleju, 15 ml”.
- Skalowanie liniowe, potem zaokrąglenie wg typu:
  - sztuki (jajka, ząbki czosnku) — do całości, w górę od połowy; jajko w panierce zawsze w górę;
  - gramy — 5 g poniżej 100 g, 10 g powyżej; mililitry analogicznie;
  - przyprawy — miarą kuchenną z `KitchenAmount.format` (`measure:` = `Ingredient.kitchenMeasure`
    z backendu, od 30.09.2026): szczypta · ¼ · ½ · 1 · 1½ · 2 łyżeczki · łyżki co ½ do 4, więcej
    = gramy; liść laurowy, ziele angielskie, goździki w sztukach („2 liście”). Scenariusz trzyma
    gramy — konwersja tylko przy wyświetlaniu, ekran kroku Gotuj ma iść przez ten sam formatter;
  - łyżki/łyżeczki z przepisu — ta sama drabina.
- **Sztuki dania** (kotlety, wałeczki masła, gołąbki) liczone od porcji zaokrąglonych w górę:
  2,5 porcji z planu = 3 kotlety. Tekst używa tokenu z odmianą: `{count:rolls|wałeczek|wałeczki|wałeczków}`.
- Czasy **nie skalują się** w v1. Scenariusz może dodać notę skali („przy 4+ porcjach smaż w dwóch
  turach”), pokazywaną tylko, gdy porcje przekroczą próg.

### 5.5 Bezpieczeństwo

- Drób: w kroku kończącym obróbkę zawsze „Po czym poznać” z 74°C w środku albo „sok przezroczysty,
  bez różowego w środku”. Wieprzowina mielona: 71°C. Analogiczne reguły dla jajek na surowo i ryb.
- Alergeny: scenariusz nie może dodać składnika spoza przepisu — nawet „dla smaku”.
- Ostrzeżenia przy gorącym tłuszczu, parze, ostrzach — tylko tam, gdzie realnie grozi oparzenie.

## 6. Model danych scenariusza (szkic)

Szkic do potwierdzenia po designie (Etap 2). Nazwy pól po angielsku jak w reszcie API.

```jsonc
{
  "recipeId": "70d8db3e-…",
  "version": 3,                      // rośnie z każdą publikacją dla przepisu
  "recipeContentHash": "sha256:…",   // z tytułu, składników, kroków, porcji — zmiana = STALE
  "rulesVersion": "2026-09-29",
  "basePortions": 2,
  "portionUnit": { "id": "cutlet", "forms": ["kotlet", "kotlety", "kotletów"] }, // opcjonalne
  "totalMinutes": 50,
  "equipment": ["OVEN", "FRYING_PAN", "POT", "CLING_FILM", "MEAT_MALLET"],
  "tips": [ { "text": "…" } ],
  "steps": [
    {
      "id": "s1",
      "phase": "PREP",               // PREP | COOK | FINISH | SERVE — dla koloru i paska postępu
      "title": "Zrób masło koperkowe i schowaj je do zamrażarki",
      "body": "…",
      "ingredients": [
        { "recipeIngredientId": "…", "amount": 30, "unit": "g", "part": "ALL" },
        { "recipeIngredientId": "…", "amount": 5, "unit": "g", "part": "HALF" }
      ],
      "mentions": [],                // przywołania bez ilości
      "note": { "kind": "CUE" | "WARNING" | "TIP", "text": "…" },
      "timer": {
        "id": "t-butter",
        "label": "Masło",            // ≤ 14 znaków — Dynamic Island compact
        "minSeconds": 900, "maxSeconds": 900,
        "startLabel": "Schowane — odliczaj 15 min",
        "trigger": "NOW" | "EVENT",  // EVENT = „gdy woda zawrze” → timer oczekujący
        "alert": { "title": "Masło gotowe", "body": "Wyjmij wałeczki z zamrażarki" },
        "actions": ["DONE", "PLUS_2_MIN"]
      },
      "during": null,                // id timera, pod którym krok się mieści („w międzyczasie”)
      "scaleNote": null              // { "fromPortions": 4, "text": "…" }
    }
  ]
}
```

Przyszłość (nie v1): scenariusz złożony z kilku przepisów = te same kroki z polem `recipeId` na
kroku i wspólną osią timerów. Dlatego timer ma własne `id`, a nie numer kroku.

## 7. System pisania scenariuszy

Cel: 1072 scenariusze katalogu + scenariusze domów, spójne, poprawne i w jednym tonie. AI pisze
treść, ale **nie decyduje**, czy jest dobra — decyduje system.

### 7.1 Przebieg

```
przepis ──► budowa promptu ──► model (Structured Outputs) ──► walidatory twarde
                                                                   │ błąd → ponów z raportem (≤ 2×)
                                                                   ▼
                                                     recenzent AI (rubryka, ocena 1–5)
                                                                   │ < 4 → ponów / do ręki
                                                                   ▼
                                                    VALIDATED ──► przegląd w panelu ──► PUBLISHED
```

### 7.2 Budowa promptu

- Zasady z §5 (wersjonowane, `rulesVersion`), schemat JSON, słownik sprzętu i jednostek.
- Przepis: tytuł, porcje, trudność, sprzęt, składniki z `recipeIngredientId`, kroki, czas.
- **Wzorce**: scenariusz wzorcowy (§10) + z czasem 3–5 kolejnych z różnych typów dań (zupa,
  ciasto, sałatka bez obróbki, śniadanie w 5 minut). Wzorce są w repo i przechodzą te same walidatory.
- Model i parametry wybieramy przy implementacji (najnowszy dostępny Claude, Batch API dla katalogu).

### 7.3 Walidatory twarde (deterministyczne, w kodzie)

- Zgodność ze schematem i limity długości.
- Każdy składnik przepisu użyty; żaden spoza przepisu; suma ilości = ilość w przepisie (tolerancja
  zaokrąglenia).
- Liczby w tekście tylko w tokenach albo jako czas/temperatura/rozmiar.
- Timery: czasy mieszczą się w czasach z przepisu; `label` ≤ 14 znaków; każdy czas z przepisu ma timer.
- Układ: piekarnik nagrzany przed pierwszym użyciem; krok „w międzyczasie” mieści się w swoim timerze;
  żaden krok nie wymaga dwóch par rąk naraz.
- Bezpieczeństwo (§5.5): drób/mięso mielone/ryby mają wskazówkę dopieczenia.
- Czas łączny w rozsądnym zakresie od `prepTimeMinutes` (do ustalenia, np. ±30%).

### 7.4 Recenzent AI

Drugie, niezależne wywołanie ocenia wg rubryki: wierność przepisowi, jasność dla początkującego,
brak protekcjonalności (§5.1), ton, sensowność kolejności. Wynik i uzasadnienie zapisywane przy wersji.

### 7.5 Statusy, wersje, panel

- `DRAFT → VALIDATED → PUBLISHED`, poboczne `REJECTED`, `STALE` (przepis się zmienił — hash).
- Każda wersja zapisuje: prompt/rulesVersion, model, raport walidatorów, ocenę recenzenta, kto opublikował.
- **Panel admina**: lista z filtrem statusów, podgląd kroku tak jak na telefonie, diff między wersjami,
  **Opublikuj / Odrzuć / Wygeneruj ponownie**. Katalog: przegląd ręczny próbki (np. pierwsze 30 +
  losowe 5%), reszta publikuje się po przejściu walidatorów i recenzenta ≥ 4.
- Edycja przepisu w panelu → scenariusz `STALE` → automatyczne ponowne wygenerowanie.
- Scenariusz ujawnia błąd przepisu (np. kolejność) → poprawiamy przepis, nie łatamy scenariusza.

### 7.6 Przepisy domów

Generowanie w tle **przy zapisie** przepisu (kolejka, ten sam system, bez przeglądu ręcznego —
publikuje się po walidatorach i recenzencie). Zanim skończy, przycisku Gotuj nie ma. Nie przeszedł —
przycisku nie ma, a panel dostaje sygnał. Kopia z udostępnienia dziedziczy scenariusz oryginału
(hash się zgadza) zamiast generować nowy.

### 7.7 Dostarczenie do iOS

- Osobne zapytanie po scenariusz (nie w synchronizacji katalogu — to ciężkie dane, a potrzebne rzadko).
- Telefon **pobiera z wyprzedzeniem** scenariusze dań dzisiejszego i jutrzejszego planu oraz przy
  otwarciu szczegółów przepisu; trzyma je w pamięci razem ze zdjęciem. Dzięki temu Gotuj działa
  offline i „jest gotowe przed wejściem”.
- Odpowiedź z `version`; telefon ma najwyżej jedną wersję na przepis (+ tę z trwającej sesji).

## 8. iOS

### 8.1 Ekrany

Powitanie, Krok, Tacka timerów, Nakładka końca timera, Wstrzymaj/Zakończ, Smacznego, Wróć do gotowania
(talerz + szczegóły). Komponenty z `Scoffie/Components/` (wariant soft, `SCSheetFooter`,
`EditorialPrimaryActionButton`), karty `scTileBg + scTileStroke` bez cienia.

### 8.2 Ruch

- Wejście: zdjęcie ze szczegółów rośnie w tło powitania (`matchedGeometryEffect`).
- Kroki: przejście boczne z lekkim przesunięciem warstw (nagłówek szybciej niż „jak”), pigułki składników
  wchodzą kaskadą.
- Timer: start → karta odlatuje do tacki; odliczanie to pierścień/pasek z płynnym ubywaniem;
  ostatnia minuta — wyraźniejszy puls; koniec — nakładka + haptyka.
- Zakończenie: „Smacznego” z animacją talerza (nawiązanie do talerza z Kalendarza).
- Uwaga z doświadczenia: przejścia wstawiane przez `AnyTransition.modifier` nie animują — ruch opieramy
  na stanie (`Animatable` + `.modifier`), patrz notatki o `CalendarPlate`.

### 8.3 Timery — AlarmKit

- iOS 26 (target apki 26.0) → AlarmKit dostępny. Daje to, co aplikacja Zegar: alert pełnoekranowy,
  dźwięk mimo wyciszenia i Focus, odliczanie na ekranie blokady, w Dynamic Island i w StandBy.
- Każdy alarm ma stany: odliczanie, pauza, alert — każdy z własnymi tytułami i przyciskami
  (App Intents: **Gotowe**, **+2 min**).
- Wymaga `NSAlarmKitUsageDescription` i zgody użytkownika. Prośba o zgodę **przy pierwszym starcie
  timera**, nie na starcie trybu. Odmowa → timer działa w apce + zwykłe powiadomienie, a karta
  timera mówi uczciwie, że przy wyciszeniu nie zadzwoni.

### 8.4 Live Activity i Dynamic Island

- Nowy target Widget Extension + App Group (zakłada Rafał w Xcode).
- **Do rozstrzygnięcia spike'iem S1**: AlarmKit pokazuje odliczanie przez Live Activity z atrybutami
  alarmu — każdy timer to osobna aktywność, a Dynamic Island mieści sensownie dwie. Dwa warianty:
  - **A.** Tylko aktywności AlarmKit (po jednej na timer). Proste, ale nie widać kroku.
  - **B.** Jedna aktywność sesji (ActivityKit: krok N/M, najbliższy timer, liczba pozostałych) +
    AlarmKit jako sam alarm na godzinę końca, bez własnego odliczania. Lepsze UX, sprawdzić, czy
    AlarmKit pozwala na alarm bez prezentacji odliczania i jak to wygląda z dwoma timerami.
- Widoki do zaprojektowania: compact (leading: ikona dania/timera, trailing: czas), minimal, expanded
  (nazwa kroku, timery, **Dalej** / **Gotowe**), ekran blokady, StandBy.
- Apple Watch: Live Activity pojawia się w Smart Stack — sprawdzić w S1, czy i jak dzwoni na zegarku.

### 8.5 Czytelność w kuchni

Duży krój nagłówka (czytelny z ~1 m), obsługa Dynamic Type, cele dotyku ≥ 56 pt w strefie kciuka,
tryb poziomy na później, jasny i ciemny motyw.

### 8.6 Stan sesji

```
CookSession { recipeId, scenarioVersion, scenario (kopia), portions, stepId,
              timers: [{ id, state: pending|running|paused|done, endDate?, remaining?, alarmId? }],
              startedAt }
```

Zapis lokalny przy każdej zmianie. Jedna sesja naraz. Ten sam stan w przyszłości zasila asystenta (v2).

## 9. Brief dla Claude Design

**Wejście**: ten dokument + scenariusz wzorcowy z §10 (prawdziwe teksty, żadnego lorem ipsum —
długość tekstów jest częścią testu). Tokeny kolorów i typografii z `SCDesignSystem`.

**Ekrany i stany do zaprojektowania**:

1. Szczegóły posiłku z przyciskiem Gotuj + talerz Kalendarza z pigułką Gotuj w oknie „Pora gotować”.
2. Powitanie (2 porcje, zmiana na 3 — co się dzieje z ilościami).
3. Krok bez timera (s2), krok z timerem przed startem (s1), krok „w międzyczasie” (s10),
   krok z timerem oczekującym „gdy woda zawrze” (s3), krok z trudną techniką i długim „jak” (s6).
4. Tacka timerów: 1, 2 i 3 timery naraz; oczekujący; zakres 10–12 min.
5. Nakładka końca timera (w apce).
6. Wstrzymaj / Zakończ.
7. Smacznego.
8. Dynamic Island: compact, minimal, expanded; ekran blokady; StandBy; alert AlarmKit.
9. Ruch: wejście, przejście kroku, start timera (lot do tacki), koniec timera, zakończenie.

**Zasady**: tylko najważniejsze, każda informacja raz; „życie” przez kolor pór, ikony, zdjęcie
i pigułki, nie przez tekst; karty w jednym kolorze bez cienia (bez białych kart); kontrolki
z komponentów apki, nie rysowane od nowa; czytelność z metra.

**Pytania, na które design ma odpowiedzieć**: czy 12 kroków to nie za dużo dla kotleta; gdzie
naturalnie ląduje kciuk przy starcie timera; czy „w międzyczasie” czyta się bez objaśnień;
czy tacka nie zasłania treści przy 3 timerach.

## 10. Przepis wzorcowy: Kotlet de volaille z ziemniakami i mizerią

Wybrany, bo sprawdza wszystko naraz: trudna technika (zawijanie, podwójna panierka), timer
chłodzenia pracujący w tle, timer z oczekiwaniem na zdarzenie (woda zawrze), zakres (10–12 min),
trzy timery naraz, piekarnik nagrzewany w środku pracy, części składników (koperek, sól, pieprz),
sztuki do zaokrąglania (jajko, kotlety), drób (bezpieczeństwo), krok „w międzyczasie” i przestawienie
kolejności względem przepisu (w przepisie ziemniaki startują za późno). Drugi kandydat do sprawdzenia
później: Pieczeń rzymska z jajkiem i ziemniakami.

Id `70d8db3e-e896-460e-ba96-d53d02c1357f` · MEDIUM · 60 min · 2 porcje · sprzęt: OVEN.

### 10.1 Przepis dziś (źródło)

Składniki: filet z kurczaka 320 g, masło 30 g, koperek 10 g, jajko 1 szt, mąka pszenna 20 g,
bułka tarta 50 g, olej rzepakowy 30 ml, ziemniak 500 g, ogórek 250 g, śmietana 12% 60 g, sól 3 g,
pieprz czarny 1 g.

1. Miękkie masło wymieszaj z połową posiekanego koperku, uformuj 2 wałeczki i schowaj do zamrażarki na 15 minut.
2. Filet przekrój na 2 płaty, rozbij przez folię na cienkie kotlety (0,5 cm), posól i popieprz. Na każdym połóż wałeczek masła i zwiń ciasno, zakładając boki do środka, by masło nie wyciekło.
3. Obtocz roladki w mące, jajku i bułce tartej, potem jeszcze raz w jajku i bułce — podwójna panierka trzyma masło w środku.
4. Obierz ziemniaki i ugotuj w osolonej wodzie przez 20 minut.
5. Smaż kotlety na oleju na średnim ogniu 10–12 minut, obracając, aż będą złote ze wszystkich stron. Dopiecz 5 minut w piekarniku nagrzanym do 180°C (góra–dół).
6. Ogórek pokrój w cienkie plasterki, lekko posól, odciśnij i wymieszaj ze śmietaną i pieprzem. Podawaj kotlety z ziemniakami posypanymi resztą koperku i mizerią.

### 10.2 Scenariusz wzorcowy (wersja robocza do oceny tonu)

Pisany ręcznie wg §5 — ma skalibrować poziom szczegółu, zanim powstanie prompt. Oś czasu ~50 min:
masło chłodzi się od 0', ziemniaki gotują od ~25', kotlety smażą się 31'–43', piekarnik 43'–48'.

**Powitanie** — 2 porcje · ok. 50 min · średnio trudne
Sprzęt: piekarnik, patelnia, garnek, folia spożywcza, tłuczek (albo dno rondla), 3 głębokie talerze.
Rady kucharza:
- Masło musi być miękkie. Jeśli jest prosto z lodówki, rozgnieć je widelcem w ciepłej miseczce.
- Zawijaj ciasno i zakładaj boki do środka — od tego zależy, czy masło zostanie w kotlecie.
- Kotlet przekrój dopiero na talerzu, ostrożnie: w środku jest gorące masło.

**s1 · Zrób masło koperkowe i schowaj je do zamrażarki**
Pigułki: masło · 30 g · koperek · połowa, 5 g
Jak: Posiekaj cały koperek drobno i odłóż połowę — przyda się do ziemniaków. Masło rozgnieć
widelcem z koperkiem na gładką masę. Na folii uformuj {count:rolls|wałeczek|wałeczki|wałeczków}
grubości palca, zawiń szczelnie i połóż płasko w zamrażarce.
Timer: **Masło** · 15 min · „Schowane — odliczaj 15 min”

**s2 · W międzyczasie rozbij filety na cienkie kotlety** — *Masło twardnieje — w tym czasie:*
Pigułki: filet z kurczaka · 320 g · sól · 1 g · pieprz · ½ g
Jak: Każdy filet połóż płasko i przetnij poziomo na dwa cieńsze płaty, jak otwierając książkę —
z dwóch filetów wychodzą {count:cutlets|kotlet|kotlety|kotletów}. Przykryj folią i rozbijaj tłuczkiem od środka na zewnątrz, aż mięso będzie
miało ok. 0,5 cm grubości. Równa grubość = równe smażenie. Posól i popieprz z obu stron.
Rada: Folia nie pozwala mięsu się porwać i pryskać po kuchni.

**s3 · Obierz ziemniaki i nastaw wodę**
Pigułki: ziemniaki · 500 g · sól · 1,5 g
Jak: Większe ziemniaki przekrój na pół, żeby wszystkie ugotowały się w tym samym czasie. Zalej
je zimną wodą tak, by były przykryte, posól i postaw na dużym ogniu. Gdy woda zawrze, zmniejsz
ogień do średniego i włącz odliczanie.
Timer: **Ziemniaki** · 20 min · wyzwalacz: zdarzenie · „Woda wrze — odliczaj 20 min”
Alert końca: „Ziemniaki gotowe? Nóż ma wchodzić bez oporu.” · Gotowe / +2 min

**s4 · Przygotuj trzy talerze do panierki**
Pigułki: mąka · 20 g · jajko · 1 · bułka tarta · 50 g
Jak: Do pierwszego talerza wsyp mąkę, w drugim roztrzep jajko widelcem, do trzeciego wsyp bułkę
tartą. Ustaw je w rzędzie w tej kolejności — przyda się to przy podwójnej panierce.

**s5 · Nagrzej piekarnik do 180°C**
Jak: Góra–dół, bez termoobiegu. Za kwadrans kotlety trafią do środka na 5 minut.
*(nagrzewanie w środku pracy, nie na starcie — dokładnie tam, gdzie jest potrzebne)*

**s6 · Zawiń kotlety z masłem** — wymaga masła z s1 (tacka pokazuje, czy timer „Masło” już się skończył)
Jak: Wyjmij wałeczki z zamrażarki. Każdy połóż na brzegu kotleta, krótszym bokiem do siebie.
Zawiń raz, załóż boki kotleta do środka, jak przy naleśniku z nadzieniem, i zwijaj dalej ciasno
do końca. Łączeniem do dołu — tak roladka się nie rozwinie.
Po czym poznać: Z żadnej strony nie widać masła. Jeśli widać — dociśnij mięso palcami.

**s7 · Obtocz roladki podwójnie**
Wspomniane: mąka, jajko, bułka tarta (z talerzy z s4)
Jak: Każdą roladkę obtocz kolejno w mące, jajku i bułce tartej, a potem jeszcze raz w jajku
i bułce. Dociśnij panierkę dłońmi. Druga warstwa to zabezpieczenie — trzyma masło w środku
podczas smażenia.

**s8 · Smaż kotlety na złoto**
Pigułki: olej · 30 ml
Jak: Rozgrzej olej na patelni na średnim ogniu — jest gotowy, gdy okruch bułki od razu zaczyna
skwierczeć. Połóż kotlety łączeniem do dołu, żeby się zasklepiły. Obracaj co 3 minuty, aż będą
złote ze wszystkich stron.
Uwaga: Olej pryska — kładź kotlety od siebie.
Timer: **Kotlety** · 10–12 min · „Na patelni — odliczaj”
Alert (10 min): „Sprawdź kolor — jeśli blade, jeszcze 2 min.” · Gotowe / +2 min

**s9 · Przełóż kotlety do piekarnika na 5 minut**
Jak: Przełóż je do naczynia żaroodpornego albo na blachę i wstaw na środkową półkę.
Po czym poznać: W środku 74°C albo po nakłuciu wypływa przezroczysty sok, bez różowego.
Timer: **Piekarnik** · 5 min · „W piekarniku — odliczaj 5 min”

**s10 · W międzyczasie zrób mizerię** — *Kotlety w piekarniku — w tym czasie:*
Pigułki: ogórek · 250 g · sól · ½ g · śmietana · 60 g · pieprz · ½ g
Jak: Pokrój ogórek w cienkie plasterki, posól i odstaw na chwilę. Odciśnij wodę dłońmi —
mizeria nie będzie wodnista. Wymieszaj ze śmietaną i pieprzem.

**s11 · Odcedź ziemniaki i posyp koperkiem**
Pigułki: koperek · reszta, 5 g
Jak: Odcedź ziemniaki i odstaw na chwilę na gorącej płycie bez pokrywki, żeby odparowały. Posyp koperkiem.

**s12 · Podaj**
Jak: Na talerz połóż kotlet, ziemniaki i mizerię.
Uwaga: Kotlet przekrój dopiero na talerzu i ostrożnie — z środka wypłynie gorące masło.

Kontrola sum: sól 1 + 1,5 + 0,5 = 3 g ✓ · pieprz 0,5 + 0,5 = 1 g ✓ · koperek 5 + 5 = 10 g ✓ ·
pozostałe w całości raz ✓. Przy 3 porcjach: filet 480 g, 3 kotlety, 3 wałeczki, jajko 1,5 → **2**
(panierka zawsze w górę), bułka tarta 75 g, ogórek 380 g (zaokr. do 10 g).

## 11. Kolejność prac (Etapy)

| Etap | Co | Kto / gdzie | Wyjście |
|---|---|---|---|
| E0 | Ten dokument + scenariusz wzorcowy | Claude, repo | Rafał koryguje ton i poziom szczegółu §10.2 |
| E1 | ✅ Design w Claude Design na wzorcu — **zamknięty 30.09** (§13); ruch opisany w §8.2, do dopracowania przy S1 | Rafał + Claude Design | zatwierdzone ekrany |
| S1 | Spike AlarmKit + Live Activity (warianty A/B z §8.4), 3 timery naraz, zegarek | Claude pisze, Rafał buduje na Macu | wybór wariantu, zdjęcia z urządzenia — **równolegle z E1**, bo ogranicza design Dynamic Island |
| E2 | ✅ Model danych i API scenariusza (backend) — **na develop 30.09** (backend #256): tabela `RecipeCookScenario`, `Recipe.cookScenarioVersion` w delcie katalogu, WS `recipes:cookScenario`, loader `pnpm cook-scenarios:load` z wzorcem kotleta; zmiana przepisu unieważnia scenariusz w bazie (STALE) | Claude, backend | wzorzec na prod po wdrożeniu na main (loader przez `railway ssh`) |
| E3 | System pisania: prompt, walidatory, recenzent, panel — **E3a na develop 30.09** (backend #257: autor Opus 5.5, walidatory, recenzent Sonnet 5.5, `pnpm cook-scenarios:write`, tylko lokalnie); pilot 3/20: 0/3 za pierwszym podejściem → poprawki E3a.1 (#258) | Claude, backend + dashboard | pilot 20 przepisów różnych typów → przegląd → cały katalog |
| E4 | iOS: widok Gotuj na wzorcu, potem na API — **w toku od 1.10** (iOS `feat/gotuj-e4`, design `feat/gotuj-tokeny`): dane i sesja (`Models/Cook/`, sprawdzian `sh Scripts/cook-logic-check.sh`), widoki (`Views/Cook/`: powitanie, krok z dokiem, arkusze Timery i Składniki, koniec timera, wyjście, zakończenie), wejście ze szczegółów przepisu, zrzuty `SCOFFIE_DEBUG_OPTIONS=gotuj-*`. Na `develop` od 1.10 (Rafał testuje na Macu ekran po ekranie). Runda 1 testów: układ bez wyjeżdżania za ekran (zdjęcie nagłówka poszerzało treść), ruch tekstów i liczb jak w reszcie aplikacji; wejście z talerza Kalendarza (D23, D43: „play” z prawej, pieczątka z ptaszkiem z lewej, talerz PS1 po wstrzymaniu, zrzuty `plate`/`plate-gotujesz`). Runda 2: dok jak dolne menu, stała kolejność timerów (D44). Runda 3: jeden ekran trybu, arkusze Timery i Składniki, dwie kapsuły, kolor każdego timera (D45). Runda 4: pominięte timery czekają, dok bez skoków, plakietka stanu, tarcza alarmu, składniki w działach (D46). Runda 5: kapsuły się nie przesuwają, teksty plakietki, pusty krok, wszystkie timery w wyjściu i na talerzu (D47). Zostaje: D21 (wpis spoza planu — specyfikacja backendu), wysyłka ocen (API) | Claude, iOS | tryb działa end-to-end bez timerów systemowych |
| E5 | iOS: AlarmKit, Live Activity, Dynamic Island, wejścia z Kalendarza i powiadomienia | Claude + target od Rafała | pełne v1 |
| E6 | Scenariusze przepisów domów (generowanie przy zapisie) | Claude, backend | kolejka + sygnały w panelu |
| E7 | TestFlight, poprawki, prod za flagą | Rafał | premiera |

## 12. Ryzyka i otwarte pytania

| Ryzyko / pytanie | Co z tym robimy |
|---|---|
| Jakość 1072 scenariuszy | walidatory twarde + recenzent + pilot 20 + próbka ręczna (§7.5) |
| Tekst w scenariuszu rozjeżdża się z krokami w szczegółach przepisu | na razie dwa widoki tego samego; po v1 rozważyć krótkie kroki w szczegółach z nagłówków scenariusza |
| AlarmKit + Live Activity przy 2–3 timerach | spike S1 przed zamknięciem designu Dynamic Island |
| Użytkownik odmówi zgody na alarmy | tryb działa, karta timera uczciwie mówi o wyciszeniu (§8.3) |
| Odmiana liczebników po polsku przy skalowaniu | tokeny z formami (§5.4), walidator liczb w tekście |
| Przepisy trywialne (jogurt z granolą) | ✅ D29: bez Gotuj; kryterium ustala system pisania (brak obróbki cieplnej i timerów, ≤ 3 kroki) |
| Paywall (D13) | rekomendacja: v1 za darmo — koszt jest jednorazowy (katalog) i niski (domy), a funkcja to najlepszy materiał na zrzuty App Store i pierwsze wrażenie; płatność sensowna przy v2, gdzie każde pytanie ze zdjęciem realnie kosztuje. Flaga gotowa od początku |
| Auto-wpis do planu (D21) a danie, które już stało w tej porze | ✅ D28 |
| Zmiana pieczątki „zjedzone” w Kalendarzu (D23) | dotyczy całej apki, nie tylko Gotuj — wchodzi razem z wejściem na talerzu |
| **Otwarte (do decyzji Rafała):** trzy timery naraz poza planem scenariusza — użytkownik przedłuży timer (D35) i mimo to przejdzie dalej strzałką ‹ › (D34), a tam włączy kolejny | scenariusz tego nie planuje (D38, walidator: najwyżej 2), ale telefon musi to obsłużyć bez rozjechania doku — np. trzeci timer jako „+1” otwierający arkusz Timery. Do ustalenia przy E4 |

## 13. Design v1 — zatwierdzone ekrany (30.09.2026)

Wszystkie ekrany na kanwie: https://claude.ai/artifact/DEnbNj45aY4X9Xaq1siV4D (przykład: Kotlet de volaille).
Wspólne: ciemne tło `scPageBase`, akcenty z `SCPalette` (terakota = akcja i timery, szałwia = zrobione / zjedzone,
masło = rady, indygo i kolory działów tylko tam, gdzie niosą znaczenie). Odstęp w stopkach 12 pt, promień kafli 24 pt,
arkusze promień 40 z uchwytem, krzyżyk zawsze po prawej jak `SCSheetCloseButton`.

**Zdjęcie w nagłówku każdego ekranu trybu**: 330 pt, krycie 0,85, wtopione w tło (170 pt gradientu),
tytuł zaczyna się ~290 pt od góry — przejścia między ekranami nie skaczą.

### 13.1 Powitanie (P1)

Krzyżyk · zdjęcie · „GOTUJEMY · OBIAD” · tytuł + dopisek dania · meta (ok. 50 min · średnio trudne · 12 kroków) ·
karta „Gotujesz 2 porcje / tyle, ile w planie” ze stepperem 1:1 z `DetailServingsStepper` · szuflada **Składniki · 12**
(stos ikon produktów + skrót ilości) · szuflada **Rady kucharza · 3** · przycisk **Zaczynamy →**.
Sprzętu nie pokazujemy (pole może zostać w scenariuszu dla walidatora piekarnika).

### 13.2 Krok

- **Pasek u góry**: z lewej pierścień z 12 odcinków (zrobione szałwia, bieżący terakota) z numerem kroku, z prawej
  krzyżyk. **Timerów w nagłówku nie ma** (D34 — zastępuje D26).
- **Scena (S3)**: etap małymi literami w szałwii („SMAŻENIE”, „W MIĘDZYCZASIE”), tytuł 40 pt, opis 17 pt,
  ostrzeżenie maślaną linijką z ikoną. Numeru kroku nad tytułem nie ma — mówi go pierścień. Karty timera w treści
  też nie ma — timer kroku startuje w doku.
- **Dok (D34)**, strefa kciuka, pływający 16 pt od boków i 24 pt od dołu:
  - **wyspa** (68 pt, kapsuła): Wstecz (kółko 52) · **Składniki N** (koszyk + liczba; otwiera arkusz) · **Dalej**
    (sama strzałka, kółko 52); w ostatnim kroku strzałka → zielony ptaszek „Zakończ”; w pierwszym Wstecz przygaszone;
  - **timery nad wyspą** (10 pt odstępu), każdy osobną kapsułą 56 pt z nieprzezroczystym tłem i cieniem:
    - jeden → cała szerokość: pierścień, nazwa, czas i jeden przycisk (pauza / **▶ Start** / **Wznów** / **Gotowe**);
      w kapsule **do włączenia** zamiast nazwy stoi warunek startu ze scenariusza (`startLabel`, D37):
      „Kotlety na patelni · 10:00 · ▶ Start”;
    - dwa → dwie kapsuły obok siebie (pierścień, nazwa, czas); dotknięcie otwiera arkusz Timery;
    - **do włączenia** — obwódka terakoty, łagodne pulsowanie; **po czasie** — pełna terakota, dzwonek, mocne
      pulsowanie; **pauza** — przygaszona;
  - nic nie trwa i nic nie czeka → sama wyspa.
- **Arkusz Timery** (z kapsuły timera; wyspa zostaje pod nim): sekcje **TRWA** (pierścień = pauza, nazwa, „krok 3 ·
  z 20 min”, czas w kolorze timera), **W TYM KROKU** (karta z **▶ Start**, pulsuje, podpis „Start: kotlety na patelni”), **WSTRZYMANY** (przycisk wznowienia,
  „Stoi, dopóki go nie wznowisz — nie zadzwoni”).
- **Arkusz składników** (z wyspy; timery wiszą nad nim): przełącznik **Ten krok / Cały przepis**; sekcje
  **TERAZ**, **ZA CHWILĘ · KROK N+1** („odłóż — reszta z kroku 1”), **JUŻ W DANIU** (przygaszone, z ptaszkiem i numerem
  kroku). Wiersz: ikona produktu w kolorze kategorii (D36), nazwa, dopisek przy częściach, ilość z prawej.
- **Koniec timera w apce (D35)**: pełny ekran — przygaszone zdjęcie, pierścień „KOTLETY / +0:18 / po czasie · było
  10 min” (łuk zewnętrzny co minutę, dzwonek się kołysze), „Sprawdź, czy są złote” + wskazówka, inne timery
  („Ziemniaki 14:32 · leci dalej”), na dole „Jeszcze chwilę?” **+1 / +2 / +5 min** i **Gotowe — dalej**; Wycisz w rogu.
- Wszystkie stany doku i arkuszy: sekcja kanwy **„Dla developmentu — dok”**.

### 13.3 Zakończenie

Zdjęcie · „UGOTOWANE” · **Smacznego!** · nazwa dania · rząd trzech liczb między cienkimi liniami (czas · kroki ·
kcal porcji) · karta **NA NASTĘPNY RAZ** z ikoną żarówki w kolorze masła i jedną radą ze scenariusza ·
„Jak wyszło?” z dwoma kciukami w jednym wierszu · przycisk **✓ Zjedzone** (szałwia). Bez konfetti, bez pigułek.
Po kciuku arkusz do połowy **„Co byś zmienił?”**: ikona wybranego kciuka, pigułki (pierwsza podpowiedziana z sesji,
np. „Kotlety +4 min”, gdy dwa razy dodano +2 min), pole tekstowe, **Wyślij**. Kciuk zapisuje się także bez uwag.
Uwagi zasilają panel: wiele „+min” przy tym samym kroku = scenariusz do poprawki.

### 13.4 Gotowanie spoza planu (D21)

Użytkownik gotuje przepis, którego nie ma dziś w planie. Po **Zjedzone** system sam:
1. wybiera porę po godzinie i `suitableMealTypes` przepisu;
2. dopisuje przepis do dzisiejszego planu w tej porze i odhacza go jako zjedzony (per osoba, `PlanItemConsumption`);
3. danie, które stało w tej porze (slot może mieć kilka przepisów — `@@unique` dzień+pora+przepis):
   **nikt go jeszcze nie zjadł → zastępujemy je; ktoś już odhaczył → dopisujemy obok**, żeby nie kasować cudzego
   „zjedzone”. Plan jest wspólny dla domu — do potwierdzenia przy specyfikacji backendu.
Żadnego UI dla tej decyzji.

### 13.5 Wyjście i wstrzymanie

- **X w trakcie** → arkusz **„Wychodzisz z gotowania?”** + „Krok 8 z 12 · nazwa dania”, trwające timery jako
  pigułki na środku (0 / 1 / 2), dwa równe kafle obok siebie: **Wstrzymaj** („Timery lecą dalej” / bez timerów:
  „Wrócisz do tego kroku”; lekko wyróżniony) i **Zakończ** („Timery się wyłączą” / „Wyjdziesz z przepisu”),
  na dole **Gotuj dalej**. Bez krzyżyka w arkuszu i bez drugiego potwierdzenia.
- **Po wstrzymaniu** — Kalendarz (odtworzony 1:1 z `CalendarPlate`): obręcz talerza zamienia się w pierścień
  12 kroków, kicker „OBIAD · GOTUJESZ”, wielka linia „Krok 8 z 12”, pigułki działających timerów, play z prawej.

### 13.6 Wejścia

- **Kalendarz**: na talerzu **play z prawej** (pod kciukiem), zawsze dla dania ze scenariuszem, mocniejszy w oknie
  „Pora gotować”; **pieczątka „zjedzone” z lewej jako kółko z ptaszkiem** zamiast kropki (zmiana dla całej apki).
- **Szczegóły przepisu** (arkusz 1:1 z `RecipeDetail`): stopka dwóch przycisków — z Przepisów „+ Dodaj do planu” |
  **„▶ Gotuj”** (pełna terakota), z Kalendarza „✓ Zapisz porcje” (przygaszony do zmiany) | **„▶ Gotuj”**.
  Przepisy Cookidoo: tylko „Gotuj w Thermomixie”.

### 13.7 Poza apką

Jedna reguła: **działa timer → wokół zdjęcia pierścień timera; brak timera → pierścień kroków**.
- **Dynamic Island, kompakt**: zdjęcie w pierścieniu + „9:41” (bez timera: „8/12” w szałwii).
- **Minimal** (obok inna aktywność): samo zdjęcie w pierścieniu (timer / kroki wg reguły).
- **Rozwinięta**: nagłówek = zdjęcie w pierścieniu kroków + okrągły terakotowy **Dalej →**, „KROK 8 Z 12” + tytuł;
  pod nim stan: **1 timer** (kafel + „+1 min”), **2 timery** (dwa kafle), **bez timera** („Dalej: Przełóż do
  piekarnika · 5 min”), **timer czeka** (przerywany kafel „ZIEMNIAKI · CZEKA / Woda wrze? 20:00” + play).
  Treść omija aparat na środku.
- **Ekran blokady**: te same stany i ten sam nagłówek w większej karcie Live Activity.
- **Alarm (AlarmKit)**: systemowy; ustawiamy tytuł („Kotlety”), tekst i przyciski **+2 min** / **Gotowe**.

### 13.8 Co design dokłada do danych

- `tips[]` na powitaniu (już w §6) + **rada „na następny raz”** na zakończeniu (nowe pole scenariusza);
- timer: `label` ≤ 14 znaków (kompakt), `minSeconds`/`maxSeconds` (alert po min, „+2 min” do max);
- „Dalej: …” w wyspie i na ekranie blokady = tytuł następnego kroku + czas jego timera;
- uwagi z oceny: kciuk + pigułki + tekst + zdarzenia sesji (ile razy „+min”, przy którym kroku).
