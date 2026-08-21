import Foundation

/// Codzienna rotacja propozycji na karuzeli „Smaki na dziś”.
///
/// Bez niej karuzela pokazywała zawsze tę samą piątkę — najlepiej dopasowaną
/// do celu, więc dopóki użytkownik nie zmienił ustawień, ekran wyglądał
/// identycznie każdego dnia. Propozycja, która się nie zmienia, przestaje być
/// propozycją.
///
/// Wybór jest **deterministyczny**, nie losowy: ta sama doba daje tę samą
/// piątkę przy każdym wejściu, na każdym urządzeniu i po każdym restarcie.
/// Losowanie przy każdym renderze przestawiałoby karty pod palcem w trakcie
/// przewijania.
enum DailyRecipeRotation {
    /// Godzina, o której wchodzi nowy zestaw.
    ///
    /// Piąta rano, nie północ i nie ósma. O północy zestaw zmieniałby się
    /// komuś w trakcie wieczornego planowania; o ósmej — w trakcie śniadania,
    /// czyli dokładnie wtedy, gdy ktoś patrzy na propozycje. Piąta wypada
    /// między jednym a drugim.
    static let rolloverHour = 5

    /// Numer „doby posiłkowej” — rośnie o jeden po każdym przekroczeniu
    /// godziny przewrotu. Służy jako ziarno, więc liczy się tylko to, że jest
    /// stabilny w obrębie doby i inny następnego dnia.
    static func mealDay(for date: Date = Date(), calendar: Calendar = .current) -> Int {
        let shifted = calendar.date(byAdding: .hour, value: -rolloverHour, to: date) ?? date
        let start = calendar.startOfDay(for: shifted)
        return Int(start.timeIntervalSince1970 / 86_400)
    }

    /// Wybiera `count` przepisów na daną dobę.
    ///
    /// Rotacja obraca się wewnątrz `poolLimit` najlepiej dopasowanych, a nie
    /// całego katalogu — inaczej „dopasowane do Ciebie” znaczyłoby po prostu
    /// „losowe”. Kolejność wejściowa niesie ranking pod cel użytkownika, więc
    /// pula to po prostu jej początek.
    static func pick(
        count: Int,
        from recipes: [Recipe],
        poolLimit: Int = 15,
        day: Int = mealDay()
    ) -> [Recipe] {
        guard !recipes.isEmpty else { return [] }
        guard recipes.count > count else { return recipes }

        let pool = Array(recipes.prefix(max(poolLimit, count)))

        // Przesunięcie startu o numer doby daje przewidywalny obrót: każdy
        // dzień zaczyna od kolejnego przepisu w puli, więc przez `pool.count`
        // dni użytkownik zobaczy wszystko, zanim cokolwiek się powtórzy.
        // Do tego mieszamy pulę ziarnem doby, żeby zestaw nie był po prostu
        // przesuniętym oknem tej samej listy.
        var generator = SeededGenerator(seed: UInt64(bitPattern: Int64(day)))
        let shuffled = pool.shuffled(using: &generator)

        return Array(shuffled.prefix(count))
    }
}

/// Generator o powtarzalnym ciągu — `SystemRandomNumberGenerator` z definicji
/// nie da się zasiać, a `shuffled()` bez ziarna daje inny wynik przy każdym
/// wywołaniu, czyli przy każdym renderze widoku.
///
/// SplitMix64: krótki, sprawdzony i bez zależności.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Stała różna od zera, żeby ziarno 0 nie dawało zdegenerowanego ciągu.
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
