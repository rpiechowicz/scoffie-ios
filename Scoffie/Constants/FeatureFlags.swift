/// Funkcje schowane do odwołania: kod zostaje, interfejs i ruch sieciowy nie.
///
/// Stałe aplikacji, nie flagi z serwera — schowanie ma działać także na
/// starszym serwerze i bez sieci. Powrót = `true` i nowy build.
enum FeatureFlags {
    /// Thermomix / Cookidoo: plakietka i filtr „Thermomix”, przycisk
    /// „Gotuj w Thermomixie”, wiersz Cookidoo w Ustawieniach. Schowane
    /// 3.10.2026 do czasu rozmowy z Vorwerk. Do tego czasu przepis
    /// z Cookidoo jest zwykłym przepisem — z trybem Gotuj, jeśli ma scenariusz.
    static let thermomix = false

    /// Zdrowie (kroki z Apple Zdrowie / Garmina): wiersz w Ustawieniach,
    /// pasek kroków w Kalendarzu, odczyt i wysyłka kroków. Schowane 3.10.2026.
    static let health = false
}
