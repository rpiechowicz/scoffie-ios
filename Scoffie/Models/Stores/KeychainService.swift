import Foundation
import Security

/// Bezpieczne przechowywanie wrażliwych danych (tokeny auth) w iOS Keychain.
/// Keychain jest szyfrowany przez system i chroniony przez Secure Enclave.
enum KeychainService {

    private static let service = "app.scoffie.ios"

    // MARK: - Public API

    /// Zapisuje wartość w Keychain. Nadpisuje istniejącą, jeśli istnieje.
    ///
    /// **Nadpisanie idzie `SecItemUpdate`, nie „usuń i dodaj".** Poprzednia
    /// wersja kasowała wpis, a potem dodawała nowy — i jeśli `SecItemAdd`
    /// odmówił (Keychain chwilowo niedostępny, brak uprawnienia, pełny
    /// pęcherz), zostawało PUSTE MIEJSCE zamiast starej wartości. Dla tokenów
    /// to nie jest nieudany zapis, to koniec sesji: `SessionStore` czyta
    /// refresh token z Keychaina, brak wpisu znaczy „sesji nie da się
    /// uratować" i telefon wylogowuje się sam, bez udziału serwera i bez
    /// jednego żądania w logach. `SecItemUpdate` albo podmienia wartość, albo
    /// nie robi nic — nigdy nie zostawia dziury.
    ///
    /// `kSecAttrAccessible` ustawiamy tylko przy DODAWANIU: przy nadpisaniu
    /// wpis zachowuje atrybut, z którym powstał, a podmienianie go przy okazji
    /// zapisu tokenu zmieniałoby po cichu warunki dostępu do już istniejącego
    /// wpisu.
    @discardableResult
    static func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let update = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }

        var insert = query
        insert[kSecValueData as String] = data
        // Dostępne po pierwszym odblokowaniu urządzenia, nie migrowane
        // do innych urządzeń ani do kopii zapasowej.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    /// Odczytuje wartość z Keychain. Zwraca nil jeśli klucz nie istnieje.
    static func get(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }

        return value
    }

    /// Status wpisu bez czytania wartości. `get` zwraca `nil` zarówno dla
    /// braku wpisu (`errSecItemNotFound`), jak i dla wpisu chwilowo
    /// niedostępnego (`errSecInteractionNotAllowed` przed pierwszym
    /// odblokowaniem po restarcie) — a tylko ten pierwszy oznacza, że sesji
    /// naprawdę nie ma.
    static func status(forKey key: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        return SecItemCopyMatching(query as CFDictionary, nil)
    }

    /// Usuwa wartość z Keychain.
    @discardableResult
    static func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Usuwa wszystkie wpisy aplikacji z Keychain (używać przy logout).
    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}
