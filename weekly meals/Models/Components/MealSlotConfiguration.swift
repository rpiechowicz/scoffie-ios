import Foundation

/// Które posiłki gospodarstwo planuje.
///
/// Ustawienie jest **wspólne dla gospodarstwa**, nie osobiste. Plan tygodnia
/// i lista zakupów są jedne dla całego domu — gdyby jedna osoba miała
/// podwieczorek, a druga nie, ta druga widziałaby plan z dziurą i listę
/// zakupów, która się z nim nie zgadza. Backend trzyma to w
/// `Household.enabledMealTypes`; tutaj mamy lokalne lustro na czas offline
/// i na pierwszą klatkę po starcie.
struct MealSlotConfiguration: Equatable {
    /// Sloty włączone przez gospodarstwo — zawsze zawiera trójkę obowiązkową.
    let enabled: [MealSlot]

    static let `default` = MealSlotConfiguration(enabled: MealSlot.core)

    init(enabled: [MealSlot]) {
        // Trójka obowiązkowa dokładana bezwarunkowo. Ta sama reguła stoi
        // w backendzie (`normalizeEnabledMealTypes`) — klient nie jest tu
        // jedyną obroną, ale ma nie pokazać stanu, którego serwer nie zapisze.
        var set = Set(enabled)
        MealSlot.core.forEach { set.insert($0) }
        self.enabled = MealSlot.allCases.filter { set.contains($0) }
    }

    func isEnabled(_ slot: MealSlot) -> Bool {
        enabled.contains(slot)
    }

    /// Posiłki dodatkowe, które są aktualnie włączone.
    var enabledOptional: [MealSlot] {
        enabled.filter { !$0.isCore }
    }

    func enabling(_ slot: MealSlot) -> MealSlotConfiguration {
        MealSlotConfiguration(enabled: enabled + [slot])
    }

    func disabling(_ slot: MealSlot) -> MealSlotConfiguration {
        MealSlotConfiguration(enabled: enabled.filter { $0 != slot })
    }

    func toggling(_ slot: MealSlot) -> MealSlotConfiguration {
        isEnabled(slot) ? disabling(slot) : enabling(slot)
    }

    // MARK: - Persystencja

    enum Keys {
        /// Przechowywane jako CSV `rawValue`, bo `@AppStorage` nie umie tablic.
        static let enabledSlots = "settings.mealSlots.enabled"
    }

    init(storageValue: String) {
        let slots = storageValue
            .split(separator: ",")
            .compactMap { MealSlot(rawValue: String($0).trimmingCharacters(in: .whitespaces)) }
        self.init(enabled: slots)
    }

    var storageValue: String {
        enabled.map(\.rawValue).joined(separator: ",")
    }

    /// Wartości `MealType` do wysyłki na backend.
    var backendMealTypes: [String] {
        enabled.map(\.backendMealType)
    }

    init(backendMealTypes: [String]) {
        self.init(enabled: backendMealTypes.compactMap { MealSlot(backendMealType: $0) })
    }
}

extension MealSlotConfiguration {
    /// Sloty, które widok planu ma pokazać dla konkretnego dnia.
    ///
    /// Do włączonych dokładamy te, w których mimo wyłączenia coś stoi.
    /// Wyłączenie posiłku ukrywa slot, ale nie kasuje jedzenia — a ukryty
    /// posiłek, o którym nikt się nie dowie, jest gorszy niż jeden wiersz
    /// więcej na ekranie.
    func visibleSlots(planned: [MealSlot]) -> [MealSlot] {
        (enabled + planned).sortedByDay
    }
}
