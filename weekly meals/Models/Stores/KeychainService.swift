import Foundation
import Security

/// Bezpieczne przechowywanie wrażliwych danych (tokeny auth) w iOS Keychain.
/// Keychain jest szyfrowany przez system i chroniony przez Secure Enclave.
enum KeychainService {

    private static let service = "rpiechowicz.weekly-meals"

    // MARK: - Public API

    /// Zapisuje wartość w Keychain. Nadpisuje istniejącą wartość jeśli istnieje.
    @discardableResult
    static func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Usuń stary wpis przed zapisem (update = delete + add)
        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String:   data,
            // Dostępne po odblokowania urządzenia, nie migrowane do innych urządzeń
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
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
