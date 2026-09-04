# Logo Scoffie

## Źródło

`scoffie-logo.svg` — 1024×1024, trzy ścieżki wektorowe, kolory `#D2452D`,
`#ECB936` i `#F1F1EC`. To jedyny obowiązujący plik. Wszystko inne w tym
katalogu jest historią.

## CO JESZCZE NIE JEST ZROBIONE

**Aplikacja nadal rysuje logo poprzedniej marki, a ono układa parę w jej
inicjały.** To najbardziej widoczny ślad po starej nazwie: pokazuje się na
ekranie startowym, przy logowaniu, w nagłówku dokumentów prawnych i w ikonie
aplikacji. Nazwy typów i plików są już poprawione, ale rysunek nie.

Dwa kroki, oba wymagają Maca, bo na Windowsie nie ma czym zamienić wektora
na piksele:

1. **Ikona aplikacji.** `Assets.xcassets/AppIcon.appiconset` trzyma trzy pliki
   PNG: `app-icon-primary`, `app-icon-dark`, `app-icon-tinted`. Xcode nie
   przyjmuje SVG jako ikony. Wyeksportuj `scoffie-logo.svg` do PNG 1024×1024
   w trzech wariantach (podstawowy bez przezroczystości, ciemny, oraz
   jednokolorowy) i podmień pliki pod tymi samymi nazwami.
2. **Logo w aplikacji.** `Scoffie/Components/SCSteamingBowlLogo.swift` rysuje
   miskę ścieżkami wprost w SwiftUI. Trzeba przenieść ścieżki z nowego SVG
   (viewBox 1024, więc dzielnik 10,24 do układu 100×100, tak jak przy
   poprzednim logo) albo wstawić SVG do katalogu zasobów jako obrazek
   wektorowy i zastąpić nim rysowanie.

Po tych dwóch krokach zniknie ostatni widoczny ślad po poprzedniej nazwie.

## Historia

Katalog `poprzednia-marka/` trzyma komplet wariantów logo sprzed zmiany nazwy:
terakotowa miska, z której żółta para układa się w inicjały poprzedniej marki.
Pliki mają przedrostek `wm-`, żeby nikt nie wziął ich za aktualny znak — przez
chwilę leżały tu pod nazwami `scoffie-*`, mimo że rysunek był stary.

Zostają, dopóki nowe logo nie doczeka się kompletu postaci: znaku
monochromatycznego, wariantu na przezroczystym tle i wariantu do ikony.
Wtedy można je skasować.
