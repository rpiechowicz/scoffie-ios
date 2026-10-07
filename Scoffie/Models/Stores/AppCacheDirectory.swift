import Foundation

/// Katalog plików offline aplikacji: `Application Support/ScoffieCache`.
///
/// 7.10.2026 (audyt bezpieczeństwa 5.09.2026, pkt 2.5): plan, lista zakupów,
/// domownicy i katalog przepisów (z przepisami domu) leżały w `Documents`,
/// a ten trafia do kopii zapasowej iCloud i komputera — prywatne dane domu
/// wychodziły z telefonu. Paczki i sesja Gotuj leżały w `Application Support`
/// bez wykluczenia z kopii. Teraz wszystko to idzie przez ten jeden katalog:
/// - wykluczony z kopii zapasowej (`isExcludedFromBackup` na KATALOGU obejmuje
///   całą zawartość, także pliki przeniesione do niego później);
/// - z ochroną `completeUntilFirstUserAuthentication` (nowe pliki dziedziczą
///   ją po katalogu) — czytelny w tle po pierwszym odblokowaniu, bo intencje
///   Live Activity wstają z pliku sesji Gotuj na ekranie blokady;
/// - NIE `Caches`: system czyści go przy braku miejsca, a katalog z rewizją
///   (delta zamiast pełnego pobrania) i plan offline mają przetrwać.
///
/// Katalogu nie kasujemy w całości — każdy store sprząta własne pliki.
/// Nowy plik offline = `AppCacheDirectory.url(for:)`, nigdy `Documents`.
///
/// `nonisolated`, bo czytają go też kolejki w tle (`CatalogCacheGate`).
nonisolated enum AppCacheDirectory {
    static let folderName = "ScoffieCache"

    /// Katalog — tworzony, zabezpieczany i zasilany starymi plikami raz na
    /// proces, przy pierwszym użyciu (`static let` inicjuje się leniwie
    /// i bezpiecznie wątkowo). Każdy odczyt i każde sprzątanie idzie przez
    /// tę właściwość, więc żaden store nie zobaczy katalogu przed migracją.
    static let directory: URL = prepare()

    /// Plik (albo podkatalog) w katalogu offline.
    static func url(for name: String, isDirectory: Bool = false) -> URL {
        directory.appendingPathComponent(name, isDirectory: isDirectory)
    }

    // MARK: - Przygotowanie

    private static func prepare() -> URL {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var directory = support.appendingPathComponent(folderName, isDirectory: true)
        // Błędy nie przerywają: bez katalogu zapis pliku się nie uda, a store
        // i tak żyje bez cache do końca procesu (jak przy każdym błędzie zapisu).
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        migrateLegacyItems(into: directory, applicationSupport: support)
        return directory
    }

    // MARK: - Migracja (7.10.2026)

    /// Pliki, które do 7.10.2026 leżały w `Documents`.
    private static func isLegacyDocumentsFile(_ name: String) -> Bool {
        guard name.hasSuffix(".json") else { return false }
        return name.hasPrefix("meal_plans")                // MealCalendarStore (też stary wspólny meal_plans.json)
            || name.hasPrefix("shopping_list_cache_")      // ShoppingListStore
            || name == "household_members_cache_v1.json"   // SessionStore
            || name == "recipe_catalog.json"               // CatalogCacheFiles
            || name == "recipe_catalog_household.json"     // CatalogCacheFiles
            || name.hasPrefix("recipes_catalog_cache_v")   // katalog sprzed synchronizacji (v8…v12)
    }

    /// Paczki i sesja Gotuj — do 7.10.2026 w samym `Application Support`.
    private static let legacyApplicationSupportItems = ["cook-scenarios-v1", "cook-session-v1.json"]

    /// Przenosi stare pliki, żeby po aktualizacji nie zniknął plan offline
    /// ani katalog (pełne pobranie od nowa). Przeniesienie w obrębie jednego
    /// woluminu to zmiana nazwy — natychmiastowe także dla dużego katalogu.
    /// Idempotentne: co się nie przeniosło, przejdzie przy następnym starcie.
    private static func migrateLegacyItems(into directory: URL, applicationSupport: URL) {
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let documentNames = (try? fileManager.contentsOfDirectory(atPath: documents.path)) ?? []
        for name in documentNames where isLegacyDocumentsFile(name) {
            move(name, from: documents, into: directory)
        }
        for name in legacyApplicationSupportItems {
            move(name, from: applicationSupport, into: directory)
        }
    }

    private static func move(_ name: String, from source: URL, into directory: URL) {
        let fileManager = FileManager.default
        let old = source.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: old.path) else { return }
        let new = directory.appendingPathComponent(name)
        if fileManager.fileExists(atPath: new.path) {
            // Nowy plik powstał po starym (poprzednie przeniesienie się nie
            // udało, a store zdążył zapisać) — stary jest nieaktualny.
            try? fileManager.removeItem(at: old)
        } else {
            // Nieudane przeniesienie zostawia stary plik do następnego startu;
            // każdy z tych plików niesie w nazwie albo w środku konto lub dom
            // (katalog publiczny jest wspólny), więc cudzy nie zostanie odczytany.
            try? fileManager.moveItem(at: old, to: new)
        }
    }
}
