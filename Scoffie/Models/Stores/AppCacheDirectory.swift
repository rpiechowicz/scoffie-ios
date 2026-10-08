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
/// Katalogu nie kasujemy w całości — każdy store sprząta własne pliki, i to
/// przez `removeFiles(where:)` / `removeEverywhere(_:)`, które sprzątają
/// TAKŻE stare miejsca (plik, którego migracja nie przeniosła, nie może
/// przeżyć wylogowania w kopii zapasowej).
/// Nowy plik offline = `AppCacheDirectory.url(for:)`, nigdy `Documents`.
///
/// `nonisolated`, bo czytają go też kolejki w tle (`CatalogCacheGate`).
nonisolated enum AppCacheDirectory {
    static let folderName = "ScoffieCache"

    /// Katalog — przy pierwszym użyciu tworzony, zabezpieczany i zasilany
    /// starymi plikami. Gdy coś z tego się nie udało (np. start w tle przed
    /// pierwszym odblokowaniem), następny DOSTĘP próbuje jeszcze raz; po
    /// pełnym sukcesie to już tylko odczyt pod zamkiem. Każdy odczyt i każde
    /// sprzątanie idzie przez tę właściwość, więc żaden store nie zobaczy
    /// katalogu przed migracją.
    static var directory: URL {
        state.lock.lock()
        defer { state.lock.unlock() }
        if let url = state.url, state.isComplete { return url }
        let result = prepare()
        state.url = result.url
        state.isComplete = result.isComplete
        return result.url
    }

    /// Plik (albo podkatalog) w katalogu offline.
    static func url(for name: String, isDirectory: Bool = false) -> URL {
        directory.appendingPathComponent(name, isDirectory: isDirectory)
    }

    // MARK: - Sprzątanie (wylogowanie, zmiana domu, usunięcie konta)

    /// Usuwa pliki (i podkatalogi) o pasującej nazwie z katalogu offline ORAZ
    /// ze starych miejsc — tam tylko to, co należy do aplikacji (ta sama lista,
    /// której używa migracja), nigdy nic innego z `Documents`.
    static func removeFiles(where matches: (String) -> Bool) {
        removeFiles(where: matches, in: [(directory: directory, contains: { _ in true })])
        removeLegacyCopies(where: matches)
    }

    /// `removeFiles(where:)` dla jednej nazwy.
    static func removeEverywhere(_ name: String) {
        removeFiles(where: { $0 == name })
    }

    /// Tylko stare miejsca — dla plików, które w katalogu offline kasuje ktoś
    /// inny we własnym porządku (katalog: kolejka `CatalogCacheGate`).
    static func removeLegacyCopies(where matches: (String) -> Bool) {
        removeFiles(where: matches, in: legacyLocations())
    }

    private static func removeFiles(where matches: (String) -> Bool, in places: [LegacyLocation]) {
        let fileManager = FileManager.default
        for place in places {
            let names = (try? fileManager.contentsOfDirectory(atPath: place.directory.path)) ?? []
            for name in names where place.contains(name) && matches(name) {
                try? fileManager.removeItem(at: place.directory.appendingPathComponent(name))
            }
        }
    }

    // MARK: - Przygotowanie

    /// Stan przygotowania katalogu, chroniony zamkiem.
    private nonisolated final class State: @unchecked Sendable {
        let lock = NSLock()
        var url: URL?
        var isComplete = false
    }

    private static let state = State()

    /// Tworzy katalog, ustawia ochronę i wykluczenie z kopii, przenosi stare
    /// pliki. `isComplete == false` = przy następnym dostępie jeszcze raz.
    private static func prepare() -> (url: URL, isComplete: Bool) {
        let fileManager = FileManager.default
        var directory = applicationSupport.appendingPathComponent(folderName, isDirectory: true)
        // Błędy nie przerywają: bez katalogu zapis pliku się nie uda, a store
        // i tak żyje bez cache do końca procesu (jak przy każdym błędzie zapisu).
        var isComplete = true
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            isComplete = false
        }
        #if os(iOS)
        do {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: directory.path
            )
        } catch {
            isComplete = false
        }
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try directory.setResourceValues(values)
        } catch {
            isComplete = false
        }
        if !migrateLegacyItems(into: directory) {
            isComplete = false
        }
        return (directory, isComplete)
    }

    // MARK: - Stare miejsca (do 7.10.2026) — jedno źródło dla migracji i sprzątania

    private typealias LegacyLocation = (directory: URL, contains: (String) -> Bool)

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static func legacyLocations() -> [LegacyLocation] {
        [
            (directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
             contains: { AppCacheDirectory.isLegacyDocumentsFile($0) }),
            (directory: applicationSupport,
             contains: { AppCacheDirectory.legacyApplicationSupportItems.contains($0) }),
        ]
    }

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
    private static let legacyApplicationSupportItems: Set<String> = ["cook-scenarios-v1", "cook-session-v1.json"]

    /// Przenosi stare pliki, żeby po aktualizacji nie zniknął plan offline
    /// ani katalog (pełne pobranie od nowa). Przeniesienie w obrębie jednego
    /// woluminu to zmiana nazwy — natychmiastowe także dla dużego katalogu.
    /// `false` = coś zostało w starym miejscu (ponowienie przy następnym dostępie).
    private static func migrateLegacyItems(into directory: URL) -> Bool {
        let fileManager = FileManager.default
        var isComplete = true
        for place in legacyLocations() {
            let names: [String]
            do {
                names = try fileManager.contentsOfDirectory(atPath: place.directory.path)
            } catch {
                // Brak katalogu (świeża instalacja) = nie ma czego przenosić.
                if fileManager.fileExists(atPath: place.directory.path) { isComplete = false }
                continue
            }
            for name in names where place.contains(name) {
                if !move(name, from: place.directory, into: directory) { isComplete = false }
            }
        }
        return isComplete
    }

    private static func move(_ name: String, from source: URL, into directory: URL) -> Bool {
        let fileManager = FileManager.default
        let old = source.appendingPathComponent(name)
        let new = directory.appendingPathComponent(name)
        do {
            if fileManager.fileExists(atPath: new.path) {
                // Nowy plik powstał po starym (poprzednie przeniesienie się nie
                // udało, a store zdążył zapisać) — stary jest nieaktualny.
                try fileManager.removeItem(at: old)
            } else {
                try fileManager.moveItem(at: old, to: new)
            }
            return true
        } catch {
            // Stary plik zostaje do ponowienia; sprzątanie sesji i tak go
            // usuwa (`removeFiles` sięga też do starych miejsc).
            return false
        }
    }
}
