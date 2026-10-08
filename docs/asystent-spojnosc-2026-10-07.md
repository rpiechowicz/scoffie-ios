# Asystent — spójność z nowym językiem arkuszy (7.10.2026)

Wzorzec: Ustawienia i kreator po #341–#347, #354–#356 — `EditorialSheetHeader`, listy
`EditorialSheetSectionLabel` + `EditorialSettingsCardGroup` + `EditorialSettingsRow`, karty
`scTileBg` + `scTileStroke` bez cienia, stopka `scSheetFooter`, dalszy krok = push, jeden arkusz naraz.

Legenda: ✅ poprawione w tej gałęzi · ⏸ świadomie zostawione (powód obok).

## Wspólne klocki (`AssistantSheetKit`, `AssistantCapabilitiesKit`)
- ✅ `AssistantGroup` — własna kopia etykiety sekcji + karty (promień 20, kolorowe tytuły, dopisek po prawej) → `EditorialSheetSectionLabel` + `EditorialSettingsCardGroup`; usunięte.
- ✅ `AssistantRow` — własny wiersz (tytuł 15,5, kreska `AssistantLook.hair` nad wierszem, inne wcięcia) → `EditorialSettingsRow` (dostał `subtitle:` i `wrapsText:`); usunięty.
- ✅ `AssistantTile` — kafelek w tincie 36 pt zamiast pełnego `EditorialSettingsTileIcon` 30 pt; usunięty.
- ✅ Martwe kopie: `AssistantSheetFooter`, `AssistantStickyFooter`, `AssistantIconTile`, `AssistantTextButton`, `AssistantCardMetrics.listRadius` — usunięte.
- ⏸ `AssistantSheetScaffold` / `AssistantSheetHeader` — już nakładki na `EditorialSheetHeader` + `scSheetFooter`; stoją na nich też `PlansSheet` i `PlanAccessSheet` z Ustawień (wcięcie 16 pt zatwierdzone w #342).

## Arkusze
- ✅ **Co potrafi** — `AssistantGroup`/`AssistantRow`/`AssistantTile`, kolorowe tytuły grup i dopiski („Najczęściej”) → lista Ustawień, kafelek w kolorze grupy, przykład w podpisie.
- ✅ **Rozmowy** — własna pigułka szukania na dole (krem, dwa cienie), wiersze bez kafelka, pusty stan z własnym krojem → `RecipeListSheetTop` (nagłówek + `SCSearchField` przypięte), `EditorialSettingsRow`, `RecipeListEmptyState`.
- ✅ **Co o Was pamięta** — zdanie objaśnień w podtytule, licznik liczący od zera (`CountingNumber`), „Usuń wszystkie” jako terakotowy napis, własny pusty stan → podtytuł „N z 30 notatek”, `SCDestructiveButton` w stopce, wiersze z kafelkiem grupy, `RecipeListEmptyState`.
- ✅ **Zgłoś odpowiedź** — własny szkielet, własna lista powodów (bez kafelków), przycisk-kapsuła na końcu przewijanej treści → `AssistantSheetScaffold`, `EditorialSettingsRow` + `SCRadioMark`, `EditorialPrimaryActionButton` w stopce.
- ✅ **Co nie zagrało?** — krążki w tincie, kreska `AssistantLook.hair`, promień 20 → `EditorialSettingsRow` + `SCCheckbox`, pole w karcie 18.
- ✅ **Jak pracowałem** — kaskada wierszy przy otwarciu (`scReveal`) → oś stoi od razu. ⏸ kapsuła czasu obok krzyżyka (informacja, nie akcja — szklana pigułka udawałaby przycisk).
- ✅ **Zgoda (menu ⋯)** — ARKUSZ NA ARKUSZU (polityka prywatności) → push `LegalDocumentPage`; płyta stanu w tincie szałwii i ostrzeżenie „od 16 lat” w tincie terakoty (łamały „jeden kolor kart”) → wiersze w karcie; potwierdzenia → `EditorialSettingsRow` + `SCCheckbox`; odnośnik do polityki → wiersz listy.
- ✅ **Przegląd propozycji** — własna karta dnia (promień 20, kreska w kolorze obwódki), prywatna kopia przycisku `ProposalAcceptButton` → `EditorialSettingsCardGroup`, `AssistantPrimaryButton(tint:)`.
- ⏸ **Jak działa Asystent** — przepływ kroków (wprowadzenie v2 zatwierdzone); stopka `SCStepFooter` jako ostatnie dziecko `VStack`, nie `safeAreaBar` jak w kreatorze, i zapas `AssistantIntroLayout.bottom` po dawnym cieniu — zmiana przesuwa wyśrodkowanie stron, do sprawdzenia na Macu.
- ⏸ **Krok „Zgoda” w zakładce** — klocki jak w arkuszu (wspólne `sections`), układ i treść bez zmian; polityka dalej arkuszem (to jedyny arkusz nad zakładką).
- ⏸ **Karta limitu** (`AssistantQuotaSpentCard`, #352) — karta już na `AssistantCard` (`scTileBg`), krzyżyk i poza `GlassEffectContainer` zostają.
- ⏸ **Przerwa** (`AssistantMaintenanceView`, wersja A) — zatwierdzona, bez zmian.
- ⏸ **Arkusze z `AssistantView`** (10 × `.sheet`) — każdy pojedynczy, żaden nie otwiera drugiego arkusza po poprawce zgody; `PlanAccessSheet` i `PlansSheet` pushują same.
- ⏸ **Arkusze z `AssistantCards`** (3 × `.sheet`) — przegląd propozycji (poprawiony) i wybór posiłku (zdjęcie na całą górę — świadomy wyjątek od nagłówka).
- ⏸ `.system(size:)` — brak w Asystencie. Cienie w kartach rozmowy to cienie tekstu i miniatur na zdjęciach (1 pt), nie kart.
