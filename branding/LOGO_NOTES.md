# Scoffie Logo

## Aktualne źródło

`scoffie-logo.svg` — 1024×1024, trzy ścieżki wektorowe, kolory `#D2452D`
(czerwień), `#ECB936` (żółć) i `#F1F1EC` (tło). To jest logo Scoffie i to ono
obowiązuje.

## CO JESZCZE NIE JEST ZROBIONE

**Aplikacja nadal rysuje stare logo, a ono układa parę w litery „WM".** To są
inicjały Weekly Meals, czyli najbardziej widoczny ślad po starej nazwie —
widzi go każdy przy pierwszym uruchomieniu i na ekranie logowania.

Do zrobienia, w tej kolejności:

1. **Ikona aplikacji.** `Assets.xcassets/AppIcon.appiconset` trzyma trzy pliki
   PNG (`app-icon-primary`, `app-icon-dark`, `app-icon-tinted`). Xcode nie
   przyjmuje SVG jako ikony, więc trzeba wyeksportować `scoffie-logo.svg` do
   PNG 1024×1024 i podmienić. Tego kroku nie da się zrobić bez narzędzia
   rasteryzującego — na Macu wystarczy podgląd albo dowolny edytor.
2. **Logo w aplikacji.** `WMSteamingBowlLogo.swift` rysuje starą miskę
   ścieżkami wprost w SwiftUI, razem z parą w kształcie „WM". Trzeba albo
   przerysować nowe logo na ścieżki, albo wstawić `scoffie-logo.svg` do
   katalogu zasobów jako obrazek wektorowy i zastąpić nim rysowanie.
   Nazwa typu też jest do zmiany — pójdzie razem z etapem 2 rebrandingu.
3. **Stare pliki źródłowe.** Reszta plików w tym katalogu to warianty logo
   „WM Steam" z poprzedniej marki. Mają już nazwy `scoffie-*`, ale rysunek
   w środku jest stary. Do skasowania, gdy nowe warianty będą gotowe.

## Historia

Poprzednie logo (v3 „WM Steam", Recraft): terakotowa miska (#BE4834),
z której żółta para (#ECD034) układa się w litery `WM`. Zastąpione przy
zmianie nazwy na Scoffie 4.09.2026.
