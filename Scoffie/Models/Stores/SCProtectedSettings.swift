import Foundation
import Observation
import SwiftUI

// MARK: - Chronione ustawienia (7.10.2026)
//
// Audyt bezpieczeństwa 5.09.2026, pkt 2.5: profil (rok urodzenia, waga, wzrost,
// płeć), dieta (alergeny, preferencja, cel, kcal, makra, aktywność) i dane konta
// (e-mail, imię, adres zdjęcia) leżały w `UserDefaults` przez `@AppStorage` —
// czyli w jawnym plistcie, który jedzie z każdą kopią zapasową telefonu (iTunes /
// Finder bez szyfrowania, iCloud). Własny `UserDefaults(suiteName:)` niczego nie
// zmienia — to dalej plist w kopii.
//
// Dlatego te klucze mieszkają w JEDNYM pliku JSON w
// `Application Support/ProtectedSettings/`:
// - ochrona pliku `.completeUntilFirstUserAuthentication` (zaszyfrowany do
//   pierwszego odblokowania po restarcie; potem czytelny także w tle —
//   powiadomienia, intencje Live Activity),
// - `isExcludedFromBackup` na katalogu i pliku (nie jedzie w kopii zapasowej;
//   po odtworzeniu telefonu wartości wracają z serwera — `users:me`
//   i `users:preferences:get` — tak jak po świeżej instalacji),
// - zapis atomowy (plik tymczasowy + podmiana), więc przerwany zapis nie zostawia
//   połowy pliku.
//
// Widoki czytają je przez `@ProtectedSetting` (niżej) — zamiennik `@AppStorage`
// o tych samych nazwach, typach i wartościach domyślnych. Kod poza widokami —
// przez `SCProtectedSettings.shared` z API jak `UserDefaults`
// (`set`, `string`, `integer`, `double`, `removeObject`).
//
// NOWY wrażliwy klucz: dopisz go do `registeredKeys` (migracja ze starego
// `UserDefaults` i czyszczenie przy wylogowaniu) i czytaj przez
// `@ProtectedSetting` / `SCProtectedSettings.shared` — nigdy przez
// `@AppStorage` ani `UserDefaults.standard`.

/// Jedna zapisana wartość. Tylko typy, które naprawdę stoją pod tymi kluczami.
nonisolated enum SCProtectedValue: Codable, Equatable {
    case int(Int)
    case double(Double)
    case string(String)

    // Odczyty ŚCISŁE — tak, jak czyta `@AppStorage` (`object(forKey:) as? T`):
    // liczba nie udaje tekstu, tekst nie udaje liczby, a ułamek nie staje się
    // liczbą całkowitą. Brak dopasowania = wartość domyślna z deklaracji.

    var strictInt: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(exactly: value)
        case .string: return nil
        }
    }

    var strictDouble: Double? {
        switch self {
        case .int(let value): return Double(value)
        case .double(let value): return value
        case .string: return nil
        }
    }

    var strictString: String? {
        switch self {
        case .string(let value): return value
        case .int, .double: return nil
        }
    }
}

/// Wartość jednego klucza w pamięci. Osobny obiekt `@Observable` na klucz,
/// żeby widok przebudowywał się tylko przy zmianie klucza, który przeczytał —
/// tak samo ziarniście jak `@AppStorage`.
@MainActor
@Observable
final class SCProtectedSettingSlot {
    var value: SCProtectedValue?

    init(value: SCProtectedValue?) {
        self.value = value
    }
}

/// Magazyn wrażliwych ustawień — patrz komentarz na górze pliku.
///
/// Wszystko na głównym aktorze (jak `SessionStore` i widoki), więc nie ma
/// wyścigów. `shared` powstaje leniwie przy pierwszym dostępie i W `init`
/// czyta plik oraz przenosi stare wartości z `UserDefaults` — każdy odczyt
/// (widok, store) widzi więc dane już po migracji.
@MainActor
final class SCProtectedSettings {
    static let shared = SCProtectedSettings()

    /// Wersja formatu pliku, zapisywana w nim samym.
    static let formatVersion = 1

    enum Kind {
        case int
        case double
        case string
    }

    /// Klucze, które NIE mogą leżeć w `UserDefaults`, z typem, pod którym
    /// stara wersja aplikacji je tam zapisywała (potrzebny przy migracji).
    /// Te same stringi co dawniej w `@AppStorage` — nazwy się nie zmieniły.
    ///
    /// ŚWIADOMIE poza listą (zostają w `UserDefaults`): `auth.userId`
    /// (identyfikator, `restoreSession` czyta go przed Keychainem),
    /// `settings.user.avatarColor`, `settings.household.name`, przełączniki
    /// powiadomień, motyw, flagi „pokazano”, `settings.profile.sexClearPending`
    /// (znacznik nieudanego zapisu, nie dana) i wygaszone
    /// `settings.diet.excludedIngredients` / `maxPrepTimeMinutes` (zawsze puste
    /// od 23.09.2026, `loadUserPreferences` je kasuje).
    static let registeredKeys: [String: Kind] = [
        // Konto
        "settings.user.email": .string,
        "settings.user.displayName": .string,
        "settings.user.avatarUrl": .string,
        // Sylwetka
        "settings.profile.yearOfBirth": .int,
        "settings.profile.heightCm": .int,
        "settings.profile.weightKg": .double,
        "settings.profile.sex": .string,
        // Dieta i cel
        "settings.diet.preference": .string,
        "settings.diet.allergens": .string,
        "settings.diet.goal": .string,
        "settings.diet.calorieGoal": .int,
        "settings.diet.activityLevel": .int,
        "settings.diet.proteinG": .int,
        "settings.diet.fatG": .int,
        "settings.diet.carbsG": .int,
    ]

    private nonisolated struct StoredFile: Codable {
        var version: Int
        var values: [String: SCProtectedValue]
    }

    private let fileURL: URL
    private var slots: [String: SCProtectedSettingSlot] = [:]
    /// `false`, dopóki pliku nie udało się przeczytać. Plik istnieje, ale jest
    /// nieczytelny = proces obudzony w tle PRZED pierwszym odblokowaniem po
    /// restarcie (ochrona pliku). Wtedy nie wolno go nadpisać tym, co jest
    /// w pamięci (prawie nic) — czekamy, aż da się go przeczytać.
    private var isLoaded = false
    /// Klucze zmienione, zanim plik dał się przeczytać — przy wczytaniu
    /// wygrywają z plikiem, bo są nowsze.
    private var keysChangedBeforeLoad: Set<String> = []
    /// Klucze przeniesione do pamięci, ale jeszcze nie skasowane z
    /// `UserDefaults`, bo plik nie zapisał się ani razu. Kasujemy je dopiero
    /// po udanym zapisie — inaczej nieudany zapis zgubiłby dane.
    private var userDefaultsLeftovers: Set<String> = []

    private init() {
        fileURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProtectedSettings", isDirectory: true)
            .appendingPathComponent("settings.json")
        loadIfNeeded()
    }

    // MARK: - Odczyt (jak `UserDefaults`)

    /// Surowa wartość. Odczyt w `body` rejestruje zależność widoku od klucza.
    func value(forKey key: String) -> SCProtectedValue? {
        slot(forKey: key).value
    }

    /// Jak `UserDefaults.string(forKey:)`: liczba wraca jako tekst, brak = `nil`.
    func string(forKey key: String) -> String? {
        switch value(forKey: key) {
        case .string(let text)?: return text
        case .int(let number)?: return String(number)
        case .double(let number)?: return String(number)
        case nil: return nil
        }
    }

    /// Jak `UserDefaults.integer(forKey:)`: brak albo nie-liczba = 0, ułamek
    /// obcięty.
    func integer(forKey key: String) -> Int {
        switch value(forKey: key) {
        case .int(let number)?: return number
        case .double(let number)?: return Int(exactly: number.rounded(.towardZero)) ?? 0
        case .string(let text)?: return Int(text) ?? 0
        case nil: return 0
        }
    }

    /// Jak `UserDefaults.double(forKey:)`: brak albo nie-liczba = 0.
    func double(forKey key: String) -> Double {
        switch value(forKey: key) {
        case .int(let number)?: return Double(number)
        case .double(let number)?: return number
        case .string(let text)?: return Double(text) ?? 0
        case nil: return 0
        }
    }

    // MARK: - Zapis (jak `UserDefaults`)

    func set(_ value: Int, forKey key: String) {
        setValue(.int(value), forKey: key)
    }

    func set(_ value: Double, forKey key: String) {
        setValue(.double(value), forKey: key)
    }

    func set(_ value: String, forKey key: String) {
        setValue(.string(value), forKey: key)
    }

    func removeObject(forKey key: String) {
        // Stara kopia z `UserDefaults` (jeśli jakimś cudem jeszcze jest) też
        // znika — usunięcie ma usuwać wszędzie.
        UserDefaults.standard.removeObject(forKey: key)
        setValue(nil, forKey: key)
    }

    /// Wszystko naraz — przy wylogowaniu i usunięciu konta
    /// (`SessionStore.clearPersistedSession`). Kasuje plik, pamięć i ewentualne
    /// resztki tych kluczy w `UserDefaults`.
    func removeAll() {
        let defaults = UserDefaults.standard
        for key in Self.registeredKeys.keys {
            defaults.removeObject(forKey: key)
        }
        for slot in slots.values where slot.value != nil {
            slot.value = nil
        }
        keysChangedBeforeLoad.removeAll()
        userDefaultsLeftovers.removeAll()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                debugLog("[SCProtectedSettings] removeAll — nie udało się skasować pliku: \(error.localizedDescription)")
                // Plik zostaje, ale pusty stan w pamięci go nadpisze przy
                // najbliższym zapisie.
                save()
            }
        }
        // Stan w pamięci (pusty) jest teraz prawdą — nie wczytujemy już
        // starego pliku poprzedniego konta.
        isLoaded = true
    }

    /// Ponowna próba wczytania pliku, gdy start w tle trafił na telefon przed
    /// pierwszym odblokowaniem. Woła ją `SessionStore` przy wejściu na pierwszy
    /// plan — poza `body`, więc zmiana wartości bezpiecznie przebudowuje widoki.
    /// Przy wczytanym pliku tylko dobiera resztki z `UserDefaults` (start przed
    /// pierwszym odblokowaniem nie widział `UserDefaults`, więc migracja mogła
    /// nic nie znaleźć) — kilkanaście odczytów, zwykle bez skutku.
    func reloadIfNeeded() {
        guard isLoaded else {
            loadIfNeeded()
            return
        }
        let migrated = migrateFromUserDefaults(skipping: [])
        guard !migrated.isEmpty else { return }
        userDefaultsLeftovers.formUnion(migrated)
        save()
    }

    /// Zapis wspólny dla `set`/`removeObject` i `@ProtectedSetting`.
    func setValue(_ newValue: SCProtectedValue?, forKey key: String) {
        loadIfNeeded()
        let entry = self.slot(forKey: key)
        // Ta sama wartość — bez przebudowy widoków i bez zapisu pliku.
        guard entry.value != newValue else { return }
        entry.value = newValue
        if isLoaded {
            save()
        } else {
            keysChangedBeforeLoad.insert(key)
        }
    }

    // MARK: - Wnętrze

    private func slot(forKey key: String) -> SCProtectedSettingSlot {
        if let existing = slots[key] { return existing }
        let created = SCProtectedSettingSlot(value: nil)
        slots[key] = created
        return created
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }

        var stored: [String: SCProtectedValue] = [:]
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch {
                // Plik jest, ale zamknięty (przed pierwszym odblokowaniem) —
                // spróbujemy przy zapisie albo przy wejściu na pierwszy plan.
                debugLog("[SCProtectedSettings] plik nieczytelny, odkładam wczytanie: \(error.localizedDescription)")
                return
            }
            if let file = try? JSONDecoder().decode(StoredFile.self, from: data) {
                stored = file.values
            } else {
                // Uszkodzony plik: zaczynamy od pustego (serwer i tak oddaje
                // profil i preferencje przy starcie sesji).
                debugLog("[SCProtectedSettings] plik uszkodzony — start od pustego")
            }
        }

        isLoaded = true
        let changedBeforeLoad = keysChangedBeforeLoad
        keysChangedBeforeLoad.removeAll()
        for (key, value) in stored where !changedBeforeLoad.contains(key) {
            slot(forKey: key).value = value
        }

        let migrated = migrateFromUserDefaults(skipping: changedBeforeLoad)
        userDefaultsLeftovers.formUnion(migrated)
        if !changedBeforeLoad.isEmpty || !migrated.isEmpty {
            save()
        }
    }

    /// Jednorazowe w skutkach przeniesienie starych wartości z `UserDefaults`.
    ///
    /// Idzie przy KAŻDYM wczytaniu (raz na proces, kilkanaście odczytów
    /// `object(forKey:)`), a nie raz na zawsze za flagą: jeśli jakakolwiek
    /// stara ścieżka zapisze jeszcze klucz do `UserDefaults`, następny start go
    /// stamtąd zabierze. Wartość już obecna w pliku wygrywa — jest nowsza niż
    /// to, co zostało w `UserDefaults`. Zwraca klucze znalezione w
    /// `UserDefaults` (do skasowania po udanym zapisie).
    private func migrateFromUserDefaults(skipping skipped: Set<String>) -> Set<String> {
        let defaults = UserDefaults.standard
        var found: Set<String> = []
        for (key, kind) in Self.registeredKeys where defaults.object(forKey: key) != nil {
            found.insert(key)
            let entry = self.slot(forKey: key)
            guard entry.value == nil, !skipped.contains(key) else { continue }
            switch kind {
            case .int:
                entry.value = .int(defaults.integer(forKey: key))
            case .double:
                entry.value = .double(defaults.double(forKey: key))
            case .string:
                if let text = defaults.string(forKey: key) {
                    entry.value = .string(text)
                }
            }
        }
        return found
    }

    private func save() {
        var values: [String: SCProtectedValue] = [:]
        for (key, slot) in slots {
            if let value = slot.value { values[key] = value }
        }

        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true

        do {
            var directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            // Wykluczenie katalogu obejmuje wszystko w nim; plik dostaje je
            // jeszcze raz niżej, bo zapis atomowy podmienia plik i gubi jego
            // atrybuty.
            try? directory.setResourceValues(excluded)

            let data = try JSONEncoder().encode(StoredFile(version: Self.formatVersion, values: values))
            try data.write(
                to: fileURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            var file = fileURL
            try? file.setResourceValues(excluded)
        } catch {
            // Wartość żyje w pamięci do końca procesu; następny zapis spróbuje
            // jeszcze raz (zapisuje zawsze cały stan).
            debugLog("[SCProtectedSettings] zapis nieudany: \(error.localizedDescription)")
            return
        }

        if !userDefaultsLeftovers.isEmpty {
            let defaults = UserDefaults.standard
            for key in userDefaultsLeftovers {
                defaults.removeObject(forKey: key)
            }
            userDefaultsLeftovers.removeAll()
        }
    }
}

// MARK: - @ProtectedSetting

/// Zamiennik `@AppStorage` dla kluczy z `SCProtectedSettings.registeredKeys`.
///
/// Podmiana w widoku jest mechaniczna: ta sama nazwa klucza, typ i wartość
/// domyślna, `$nazwa` daje `Binding` jak dotąd:
///
///     @ProtectedSetting("settings.profile.weightKg") private var weightKg: Double = 0
///
/// Widok odświeża się sam przy zmianie klucza (Observation: odczyt w `body`
/// rejestruje zależność od `SCProtectedSettingSlot` tego klucza), także gdy
/// wartość zapisze `SessionStore` przez `SCProtectedSettings.shared`.
/// Obsługiwane typy: `Int`, `Double`, `String` — tylko takie stoją pod tymi
/// kluczami. Nowy typ = nowy `init` niżej i nowy przypadek `SCProtectedValue`.
@MainActor
@propertyWrapper
struct ProtectedSetting<Value>: DynamicProperty {
    private let key: String
    private let defaultValue: Value
    private let decode: (SCProtectedValue) -> Value?
    private let encode: (Value) -> SCProtectedValue

    private init(
        key: String,
        defaultValue: Value,
        decode: @escaping (SCProtectedValue) -> Value?,
        encode: @escaping (Value) -> SCProtectedValue
    ) {
        self.key = key
        self.defaultValue = defaultValue
        self.decode = decode
        self.encode = encode
    }

    var wrappedValue: Value {
        get {
            guard let stored = SCProtectedSettings.shared.value(forKey: key) else {
                return defaultValue
            }
            return decode(stored) ?? defaultValue
        }
        nonmutating set {
            SCProtectedSettings.shared.setValue(encode(newValue), forKey: key)
        }
    }

    var projectedValue: Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { newValue in self.wrappedValue = newValue }
        )
    }
}

extension ProtectedSetting where Value == Int {
    init(wrappedValue: Int, _ key: String) {
        self.init(
            key: key,
            defaultValue: wrappedValue,
            decode: { stored in stored.strictInt },
            encode: { value in .int(value) }
        )
    }
}

extension ProtectedSetting where Value == Double {
    init(wrappedValue: Double, _ key: String) {
        self.init(
            key: key,
            defaultValue: wrappedValue,
            decode: { stored in stored.strictDouble },
            encode: { value in .double(value) }
        )
    }
}

extension ProtectedSetting where Value == String {
    init(wrappedValue: String, _ key: String) {
        self.init(
            key: key,
            defaultValue: wrappedValue,
            decode: { stored in stored.strictString },
            encode: { value in .string(value) }
        )
    }
}
