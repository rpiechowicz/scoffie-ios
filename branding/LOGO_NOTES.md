# Weekly Meals Logo

Aktualny kierunek (v3 "WM Steam", Recraft): **Steaming Bowl** — terakotowa
miska (#BE4834), z której żółta para (#ECD034) układa się w litery `WM`
(Weekly Meals). Wygenerowane w Recraft AI, wyczyszczone z metadanych C2PA.
Cieplejsze i bardziej ilustracyjne niż v2, dalej czytelne w skali tiny
(28pt) i hero (140pt+).

## Pliki

- `weekly-meals-logo-v3.svg` — źródło 1024×1024 na kremowym tle (#F7F7F2).
  To jest aktualny logo source.
- `weekly-meals-logo-v3-transparent.svg` — sama grafika bez tła (do użycia
  na dowolnym tle).
- `weekly-meals-logo-v3-mark.svg` — monochromatyczny znak (`currentColor`)
  do użycia jako pojedynczy kolor (np. share-sheet glyph).

App icons w `Assets.xcassets/AppIcon.appiconset/` są wyeksportowane z v3
(przez `qlmanage`): primary (kremowe tło), dark (gradient #3A2A20→#1A1411),
tinted (grayscale na #1C1C1C).

### Legacy (zostają dla referencji, nie są aktualnym kierunkiem)

- `weekly-meals-logo-bowl.svg` (+ `-light`, `-mark`) — v2 "Cozy Kitchen"
  Steaming Bowl (miska + 3 strugi pary w abstrakcyjne `W`).
- `weekly-meals-logo-icon.svg`, `weekly-meals-logo-mark.svg` — pierwszy
  monogram `W`.
- `weekly-meals-app-icon-v2.svg` (+ `-dark-v2`, `-tinted-v2`) — App Store
  icon z monogramem `W` (wymienione na v3).

## SwiftUI

Logo jest renderowane natywnie przez `WMSteamingBowlLogo`
(`weekly meals/Components/WMSteamingBowlLogo.swift`) — Canvas-based,
wektorowo, bez aliasingu i bez bundlowania PNG-ów. Ścieżki przeniesione
1:1 z `weekly-meals-logo-v3.svg` (viewBox 1024 ÷ 10.24 → 100×100);
pominięte są cztery subpikselowe ścieżki-łatki generatora
(#F9F19F/#CC8568/#D8B7A1 — szwy antyaliasingu, na ciemnym tle
błyszczałyby jako drobiny). Parametry:

- `size` — bok kwadratu (px)
- `mono` — true → jednokolorowy znak, tło = `bgCard` z palety
- `palette` — `.auto` (śledzi `ColorScheme`), `.dark`, `.light`

## Design intent

- Misa = kuchnia, prostota, codzienność.
- Para w kształcie liter `WM` = Weekly Meals; naturalna kontynuacja
  motywu "para znad miski" z v2.
- Terakota + żółć + krem — zgodne z "cozy kitchen" paletą (`WMPalette`
  w `Components/WMDesignSystem.swift`).
