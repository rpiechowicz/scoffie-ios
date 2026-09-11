import Foundation

// Kalendarz — kilka sposobów powiedzenia tego samego.
//
// Ekran, który na każde odhaczenie odpowiada dokładnie tym samym słowem,
// brzmi jak automat. Kilka wariantów tego samego zdania, dobieranych
// STABILNIE dla pary (dzień, danie), sprawia, że aplikacja brzmi jak ktoś,
// kto mówi — a jednocześnie nie zmienia zdania co minutę ani przy każdym
// wejściu na ekran: wtorek mówi do tego samego obiadu zawsze tak samo,
// a środa inaczej.
//
// Dwie rzeczy są tu celowe:
//
//  1. **Ziarno, nie losowanie.** Wariant bierze się z dnia, dania i rodzaju
//     zdania. Losowanie z zegara dawałoby migotanie słów przy każdym
//     tyknięciu odliczania, a `Hasher` Swifta jest celowo losowany przy
//     starcie procesu — to samo zdanie brzmiałoby inaczej po każdym
//     uruchomieniu.
//  2. **Warianty mówią DOKŁADNIE to samo.** Różnią się tonem, nie treścią:
//     „Pora jeść” i „Smacznego!” niosą tę samą informację. Wariant, który
//     dodawałby albo gubił fakt, nie jest wariantem, tylko innym zdaniem.
enum CalendarVoice {
    /// Wariant dla ziarna. Jeden wariant = brak wyboru; puste = pusty tekst.
    static func pick(_ variants: [String], seed: String) -> String {
        guard let first = variants.first else { return "" }
        guard variants.count > 1 else { return first }
        return variants[Int(hash(seed) % UInt64(variants.count))]
    }

    /// FNV-1a, 64-bitowe — deterministyczne między uruchomieniami.
    private static func hash(_ text: String) -> UInt64 {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01b3
        }
        return value
    }
}
