# Logo Scoffie

## Znak

Dysk z wyciętym kęsem. Geometria: dysk R = 256 w środku (512, 512), kęs
r = 120,47 w (693, 331) — czyli pod kątem 45°. Jedna ścieżka, jedno
wypełnienie, viewBox 1024.

- `scoffie-logo.svg` — znak w terakocie `#B6643C`, przezroczyste tło.
- `scoffie-logo-mono.svg` — ten sam znak na `currentColor`.

Kolory pochodzą z `Scoffie/Components/SCDesignSystem.swift` (`SCPalette`):
terakota `#B6643C` (`terracottaDeep`), krem `#FAF6F0` (`canvasLight`),
terakota rozjaśniona `#DB8452` (`terracotta` w dark mode), tło ciemne
`#1A1411` (`canvasDark`).

Źródło: projekt Claude Design „Scoffie", artboard `Scoffie - Ikona App.html`.

## Ikona aplikacji

`Scoffie/Assets.xcassets/AppIcon.appiconset` — trzy pliki 1024 × 1024,
wszystkie z kwadratowymi rogami, bo squircle nakłada system:

| Plik | Format | Zawartość |
| --- | --- | --- |
| `app-icon-primary.png` | PNG RGB, bez alfy | `#B6643C` do krawędzi, znak `#FAF6F0` |
| `app-icon-dark.png` | PNG RGBA | przezroczyste tło, znak `#DB8452` |
| `app-icon-tinted.png` | PNG RGBA | przezroczyste tło, znak `#FFFFFF` w skali szarości |

Wariant podstawowy to ikona B (znak kremowy na terakotowej płycie), nie A
(terakotowy dysk na kremie). Na jasnej tapecie kremowa płyta znika, płyta
terakotowa trzyma się sama — i zgadza się z wariantem dark, gdzie znak też
leży na ciemnym tle.

`eksport-ikony/` trzyma komplet pięciu wariantów z projektu, w tym dwa
nieużywane w `AppIcon.appiconset`: `Scoffie-Icon-A-Light-1024.png` (wariant A)
i `Scoffie-Icon-Dark-Solid-1024.png` (znak na `#1A1411` bez alfy, do materiałów
poza App Store).

Pliki są renderowane skryptem z geometrii powyżej, nie eksportowane ręcznie —
jeśli trzeba je odtworzyć, wystarczy przeliczyć dysk minus kęs na siatce 1024.

## Znak w aplikacji

`Scoffie/Components/SCScoffieMark.swift` rysuje ten sam kształt ścieżkami
w `Canvas` (przestrzeń 100 × 100, czyli viewBox 1024 ÷ 10,24), więc znak
w aplikacji i ikona na ekranie startowym to ten sam rysunek. Komponent sam
rysuje sobie tło z promieniem 22% boku.

Używany w `StartupLoaderView`, `AuthFooterView`, `OnboardingHeroPattern`
(22 pt — najmniejszy rozmiar, na nim sprawdzaj czytelność kęsa) i
`TourIntroView`.

## Historia

`poprzednia-marka/` trzyma warianty sprzed zmiany nazwy (przedrostek `wm-`:
terakotowa miska, z której żółta para układa się w inicjały poprzedniej marki)
oraz `recraft-miska-*.svg` — miskę z Recrafta, która przez chwilę była
obowiązującym znakiem. Nic z tego katalogu nie jest już używane w kodzie
ani w zasobach; można go skasować.
