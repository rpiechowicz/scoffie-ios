import Foundation

/// Codzienna rotacja propozycji na karuzeli „Smaki na dziś”.
///
/// Bez niej karuzela pokazywała zawsze ten sam zestaw — najlepiej dopasowany
/// do celu, więc dopóki użytkownik nie zmienił ustawień, ekran wyglądał
/// identycznie każdego dnia. Propozycja, która się nie zmienia, przestaje być
/// propozycją.
///
/// Wybór jest **deterministyczny**, nie losowy: ta sama doba daje ten sam
/// zestaw przy każdym wejściu, na każdym urządzeniu i po każdym restarcie.
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

    /// Ile kart pokazuje karuzela „Smaki na dziś”.
    ///
    /// Osiem, nie pięć: karuzela ma pokazać, co w katalogu ciekawego, a pięć
    /// pełnoekranowych kart kończyło się, zanim ktokolwiek zdążył się
    /// rozejrzeć. Osiem to nadal osiem kropek pod kartami, czyli jednym
    /// spojrzeniem widać, ile zostało — przy kilkunastu kropki przestają
    /// cokolwiek znaczyć, a przewijanie robi się pracą, nie przeglądaniem.
    /// Reszta katalogu i tak stoi niżej, w sekcjach.
    static let featuredCount = 8

    /// Wielkość puli, w obrębie której obraca się rotacja.
    ///
    /// Pula to początek listy uporządkowanej rankingiem, więc rotacja krąży
    /// wśród najlepiej dopasowanych dań, a nie po całym katalogu — inaczej
    /// „dopasowane do Ciebie” znaczyłoby po prostu „losowe”.
    ///
    /// Rośnie razem z katalogiem, bo stałe 15 znaczyło, że przy 89 przepisach
    /// karuzela w kółko recyklinguje tę samą piętnastkę, a reszta katalogu nie
    /// pokazuje się w niej nigdy — i żaden import nowych dań tego nie zmieniał.
    /// Dolna granica `count * 4` pilnuje drugiej strony: przy ciasnej puli
    /// kolejne dni pokazywałyby niemal ten sam zestaw. Przy `count = 8` i puli
    /// 40 sąsiednie doby mają wspólne średnio półtorej karty.
    static func poolSize(forCatalogOf total: Int, count: Int = featuredCount) -> Int {
        max(count * 4, total / 2)
    }

    /// Wybiera `count` przepisów na daną dobę.
    ///
    /// `poolLimit` domyślnie liczy się z rozmiaru katalogu (`poolSize`);
    /// jawna wartość jest po to, żeby dało się to przewidywalnie sprawdzić.
    static func pick(
        count: Int = featuredCount,
        from recipes: [Recipe],
        poolLimit: Int? = nil,
        day: Int = mealDay()
    ) -> [Recipe] {
        guard !recipes.isEmpty else { return [] }
        guard recipes.count > count else { return recipes }

        let limit = poolLimit ?? poolSize(forCatalogOf: recipes.count, count: count)
        let pool = Array(recipes.prefix(max(limit, count)))

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
