import Foundation

/// O której gospodarstwo je poszczególne posiłki.
///
/// Godziny były wcześniej zaszyte w `MealSlot.time` jako stała. To działa,
/// dopóki wszyscy jedzą obiad o 14:00 — a nie jedzą. Ten typ przenosi je
/// do ustawień, zachowując dotychczasowe wartości jako domyślne, więc nikt,
/// kto nie wejdzie w ekran godzin, nie zobaczy żadnej zmiany.
///
/// Trzy decyzje, które warto znać:
///
/// 1. **Minuty od północy, nie `Date`.** Pora posiłku to punkt w dobie, a nie
///    moment w czasie — `Date` wciągnąłby tu strefę czasową i datę, których
///    ten typ nie ma prawa znać. Konwersja na `Date` żyje tylko na granicy
///    z `DatePicker`.
/// 2. **Przekąska nadal może nie mieć pory.** To slot „kiedykolwiek w ciągu
///    dnia" i wpisanie mu godziny na siłę byłoby kłamstwem wobec
///    użytkownika — ale jeśli ktoś *chce* mieć przekąskę o stałej porze,
///    może ją ustawić. Domyślnie jej nie ma.
/// 3. **Kolejność slotów nie zależy od godzin.** `MealSlot.allCases` zostaje
///    jedynym źródłem kolejności dnia (opiera się na niej plan, kalendarz
///    i cache), więc ustawienie kolacji na 06:00 nie przestawi jej przed
///    śniadanie. Arkusz ustawień mówi o tym wprost, zamiast po cichu
///    sortować — patrz `hasOutOfOrderTimes`.
struct MealSlotSchedule: Equatable {
    /// Minuty od północy. Brak klucza = slot bez stałej pory.
    private let minutesBySlot: [MealSlot: Int]

    /// Wartości, z którymi aplikacja żyła, zanim godziny stały się edytowalne.
    static let defaultMinutes: [MealSlot: Int] = [
        .breakfast:       8 * 60,
        .secondBreakfast: 10 * 60 + 30,
        .lunch:           14 * 60,
        .afternoonSnack:  17 * 60,
        .dinner:          20 * 60,
        // .snack celowo bez wpisu — patrz punkt 2 w opisie typu.
    ]

    /// Sloty, którym nie wolno odebrać pory. Pusty wiersz „Śniadanie —"
    /// w planie nic nie wnosi, a przekąska jest jedynym slotem, dla którego
    /// „bez pory" jest sensownym stanem.
    static let slotsRequiringTime: [MealSlot] = [
        .breakfast, .secondBreakfast, .lunch, .afternoonSnack, .dinner
    ]

    static let `default` = MealSlotSchedule(minutesBySlot: defaultMinutes)

    /// Pora podpowiadana, kiedy użytkownik pierwszy raz nadaje przekąsce
    /// godzinę — między obiadem a podwieczorkiem, czyli tam, gdzie
    /// przekąska naturalnie wypada.
    static let snackSuggestedMinutes = 15 * 60 + 30

    init(minutesBySlot: [MealSlot: Int]) {
        var normalized = minutesBySlot.compactMapValues(Self.clamp)
        // Braki uzupełniamy domyślnymi, żeby częściowo zapisana albo starsza
        // wartość z dysku nie zostawiła posiłku bez godziny.
        for slot in Self.slotsRequiringTime where normalized[slot] == nil {
            normalized[slot] = Self.defaultMinutes[slot]
        }
        self.minutesBySlot = normalized
    }

    // MARK: - Odczyt

    func minutes(for slot: MealSlot) -> Int? { minutesBySlot[slot] }

    /// Sformatowana pora („08:00") albo `nil`, gdy slot jej nie ma.
    /// Zastępuje dawne `MealSlot.time`.
    func time(for slot: MealSlot) -> String? {
        minutesBySlot[slot].map(Self.format)
    }

    var isDefault: Bool { self == .default }

    /// Pierwsza para slotów, w której godziny nie idą po kolei dnia — liczona
    /// wyłącznie po slotach podanych przez wywołującego.
    ///
    /// Widok ma podać to, co faktycznie pokazuje na ekranie: wyłączony
    /// podwieczorek z domyślną 17:00 nie może wywołać ostrzeżenia o wierszu,
    /// którego nie widać.
    func outOfOrderPair(among slots: [MealSlot]) -> (earlier: MealSlot, later: MealSlot)? {
        let timed = slots.sortedByDay.compactMap { slot in
            minutesBySlot[slot].map { (slot: slot, minutes: $0) }
        }
        for (first, second) in zip(timed, timed.dropFirst()) where second.minutes <= first.minutes {
            return (first.slot, second.slot)
        }
        return nil
    }

    /// Czy godziny nie idą po kolei dnia. **Nie używać w widokach** — liczy po
    /// wszystkich slotach, także wyłączonych, więc potrafi ostrzec o wierszu,
    /// którego użytkownik nie ma na ekranie. Widoki wołają
    /// `outOfOrderPair(among:)` z listą, którą rysują.
    var hasOutOfOrderTimes: Bool {
        outOfOrderPair(among: MealSlot.allCases) != nil
    }

    // MARK: - Zmiany

    func setting(_ slot: MealSlot, toMinutes minutes: Int?) -> MealSlotSchedule {
        var next = minutesBySlot
        if let minutes {
            next[slot] = Self.clamp(minutes)
        } else {
            // Slot obowiązkowy zignoruje próbę wyczyszczenia — `init`
            // i tak dołożyłby mu domyślną porę, więc lepiej nie udawać,
            // że zmiana przeszła.
            guard !Self.slotsRequiringTime.contains(slot) else { return self }
            next.removeValue(forKey: slot)
        }
        return MealSlotSchedule(minutesBySlot: next)
    }

    // MARK: - Granica z DatePicker

    /// `DatePicker` operuje na `Date`, więc porę osadzamy w dowolnym dniu —
    /// liczą się wyłącznie godzina i minuta.
    func date(for slot: MealSlot, calendar: Calendar = .current) -> Date {
        Self.date(fromMinutes: minutesBySlot[slot] ?? Self.snackSuggestedMinutes, calendar: calendar)
    }

    static func date(fromMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        let total = clamp(minutes)
        return calendar.date(
            from: DateComponents(year: 2000, month: 1, day: 1, hour: total / 60, minute: total % 60)
        ) ?? Date()
    }

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return clamp((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    // MARK: - Formatowanie

    static func format(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private static func clamp(_ minutes: Int) -> Int {
        min(max(minutes, 0), 24 * 60 - 1)
    }

    // MARK: - Persystencja

    enum Keys {
        /// CSV `slot:minuty`, bo `@AppStorage` nie umie słowników.
        static let times = "settings.mealSlots.times"
    }

    init(storageValue: String) {
        let pairs = storageValue
            .split(separator: ",")
            .compactMap { entry -> (MealSlot, Int)? in
                let parts = entry.split(separator: ":")
                guard parts.count == 2,
                      let slot = MealSlot(rawValue: String(parts[0]).trimmingCharacters(in: .whitespaces)),
                      let minutes = Int(String(parts[1]).trimmingCharacters(in: .whitespaces))
                else { return nil }
                return (slot, minutes)
            }
        self.init(minutesBySlot: Dictionary(pairs, uniquingKeysWith: { _, last in last }))
    }

    var storageValue: String {
        MealSlot.allCases
            .compactMap { slot in
                minutesBySlot[slot].map { "\(slot.rawValue):\($0)" }
            }
            .joined(separator: ",")
    }
}
