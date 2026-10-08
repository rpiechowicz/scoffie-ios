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
    /// Od 7.10.2026 (przed premierą — App Review 2.5.1 odrzuca uprawnienie
    /// HealthKit bez widocznej funkcji Zdrowia) paczka nie ma też uprawnienia
    /// ani kodu HealthKit. Powrót = `true` + przywrócić uprawnienie
    /// `com.apple.developer.healthkit` w OBU `.entitlements` (Debug i Release),
    /// opisy `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription`
    /// w `Scoffie-Info.plist` i warunek `SCOFFIE_HEALTHKIT`
    /// w `SWIFT_ACTIVE_COMPILATION_CONDITIONS` (bez niego `HealthKitService`
    /// to zaślepka „niedostępne”).
    static let health = false
}
