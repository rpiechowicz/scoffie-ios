import SwiftUI

/// Slot posiłku w ciągu dnia.
///
/// Kolejność `allCases` jest kolejnością dnia — na niej opiera się plan
/// tygodnia i kalendarz, więc nowe przypadki dopisuje się w miejscu, w którym
/// posiłek faktycznie wypada, a nie na końcu.
///
/// Podział na `core` i `optional` jest tu, a nie w widoku, bo to reguła
/// domenowa: śniadania, obiadu i kolacji nie da się wyłączyć (bez nich plan
/// przestaje być planem posiłków), a resztę gospodarstwo włącza sobie samo
/// w Ustawieniach → „Posiłki w planie". Backend pilnuje tego samego
/// (`normalizeEnabledMealTypes`), więc klient nie jest jedyną obroną.
///
/// `rawValue` jedzie do zapisanego na dysku planu (`DayMealPlan`,
/// `meal_plans.json`) — nie wolno go zmieniać bez migracji cache'u.
enum MealSlot: String, CaseIterable, Identifiable, Codable, Comparable {
    case breakfast
    case secondBreakfast
    case lunch
    case afternoonSnack
    case dinner
    case snack

    var id: String { rawValue }

    /// Kategoria, pod którą ten slot podpada na widoku Przepisów.
    ///
    /// Odwrotność `RecipesCategory.toMealSlot`. Sekcji jest cztery, nie sześć —
    /// sześć rozbiłoby ekran Przepisów. Trzy główne posiłki mają swoje, a trzy
    /// sloty „pomiędzy" (II śniadanie, podwieczorek, przekąska) schodzą do
    /// wspólnej sekcji `.snacks`: z punktu widzenia katalogu to ten sam rodzaj
    /// dania — coś małego, na słodko albo pod rękę — a nie trzy osobne kuchnie.
    ///
    /// Kolor idzie tu inną drogą niż `accentColor`: akcent grupuje sloty porą
    /// dnia, bo w planie podwieczorek stoi obok obiadu, a katalogu pora dnia
    /// nie obchodzi. Dlatego podwieczorek jest tu przy przekąsce, a tam przy
    /// obiedzie — i to jest zamierzone, nie przeoczenie.
    ///
    /// Bez tego przepis, którego `mealType` z backendu to `SNACK`,
    /// `SECOND_BREAKFAST` albo `AFTERNOON_SNACK`, nie miał kategorii — a brak
    /// kategorii wywalał CAŁY przepis przy mapowaniu DTO (`toAppRecipe`).
    /// Dziesięć dań (koktajle, pudding chia, hummus, wrap z indykiem) nie
    /// istniało wtedy w aplikacji: ani na Przepisach, ani przy dodawaniu
    /// podwieczorku, który przez to wyglądał na pusty.
    var baseCategory: RecipesCategory {
        switch self {
        case .breakfast:                                  return .breakfast
        case .lunch:                                      return .lunch
        case .dinner:                                     return .dinner
        case .secondBreakfast, .afternoonSnack, .snack:   return .snacks
        }
    }

    /// Posiłki, których nie da się wyłączyć.
    static let core: [MealSlot] = [.breakfast, .lunch, .dinner]

    /// Posiłki dodatkowe — to je użytkownik dokłada i zdejmuje.
    static let optionalSlots: [MealSlot] = [.secondBreakfast, .afternoonSnack, .snack]

    var isCore: Bool { Self.core.contains(self) }

    /// Pozycja w dniu. `allCases` jest już posortowane, ale jawny indeks
    /// przydaje się przy scalaniu list z backendu, gdzie kolejność bywa inna.
    var dayOrder: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    static func < (lhs: MealSlot, rhs: MealSlot) -> Bool {
        lhs.dayOrder < rhs.dayOrder
    }

    // MARK: - Prezentacja

    var title: String {
        switch self {
        case .breakfast:       return "Śniadanie"
        case .secondBreakfast: return "II śniadanie"
        case .lunch:           return "Obiad"
        case .afternoonSnack:  return "Podwieczorek"
        case .dinner:          return "Kolacja"
        case .snack:           return "Przekąska"
        }
    }

    /// Krótsza etykieta pod ciasne miejsca (chipy, legendy makro).
    var shortTitle: String {
        switch self {
        case .breakfast:       return "Śniadanie"
        case .secondBreakfast: return "II śn."
        case .lunch:           return "Obiad"
        case .afternoonSnack:  return "Podw."
        case .dinner:          return "Kolacja"
        case .snack:           return "Przekąska"
        }
    }

    // Pora posiłku **nie** jest już własnością slotu — ustawia ją gospodarstwo
    // w Ustawieniach → „Posiłki w planie". Czytaj ją z
    // `MealSlotSchedule.time(for:)` (`sessionStore.mealSlotSchedule`);
    // dotychczasowe godziny żyją tam jako `MealSlotSchedule.defaultMinutes`.

    var icon: String {
        switch self {
        case .breakfast:       return "sunrise.fill"
        case .secondBreakfast: return "cup.and.saucer.fill"
        case .lunch:           return "fork.knife"
        case .afternoonSnack:  return "birthday.cake.fill"
        case .dinner:          return "moon.stars.fill"
        case .snack:           return "carrot.fill"
        }
    }

    /// Jednozdaniowe wyjaśnienie do arkusza ustawień — użytkownik ma wiedzieć,
    /// co dokładnie włącza, zanim to włączy.
    var settingsSubtitle: String {
        switch self {
        case .breakfast:       return "Pierwszy posiłek dnia"
        case .secondBreakfast: return "Coś lekkiego między śniadaniem a obiadem"
        case .lunch:           return "Główny posiłek dnia"
        case .afternoonSnack:  return "Popołudniowa przerwa — owoc, jogurt, kanapka"
        case .dinner:          return "Ostatni pełny posiłek"
        case .snack:           return "Slot bez stałej pory — na przekąski w ciągu dnia"
        }
    }

    // MARK: - Kolory
    //
    // Posiłek dodatkowy dostaje akcent posiłku, obok którego stoi (II śniadanie
    // = rodzina śniadania), a odróżnia się ikoną i lżejszym wierszem. Sześć
    // niezależnych kolorów rozbiłoby paletę „Cozy Kitchen" na jarmark.

    var accentColor: Color {
        switch self {
        case .breakfast, .secondBreakfast: return .orange
        case .lunch, .afternoonSnack:      return .blue
        case .dinner, .snack:              return .purple
        }
    }

    var secondaryAccentColor: Color {
        switch self {
        case .breakfast, .secondBreakfast: return .yellow
        case .lunch, .afternoonSnack:      return .cyan
        case .dinner, .snack:              return .indigo
        }
    }

    // MARK: - Mapowanie na backend

    /// Wartość enuma `MealType` po stronie API.
    var backendMealType: String {
        switch self {
        case .breakfast:       return "BREAKFAST"
        case .secondBreakfast: return "SECOND_BREAKFAST"
        case .lunch:           return "LUNCH"
        case .afternoonSnack:  return "AFTERNOON_SNACK"
        case .dinner:          return "DINNER"
        case .snack:           return "SNACK"
        }
    }

    init?(backendMealType: String) {
        switch backendMealType.uppercased() {
        case "BREAKFAST":        self = .breakfast
        case "SECOND_BREAKFAST": self = .secondBreakfast
        case "LUNCH":            self = .lunch
        case "AFTERNOON_SNACK":  self = .afternoonSnack
        case "DINNER":           self = .dinner
        case "SNACK":            self = .snack
        default:                 return nil
        }
    }
}

extension Array where Element == MealSlot {
    /// Porządkuje sloty porą dnia i usuwa duplikaty. Używane wszędzie tam,
    /// gdzie lista przychodzi z zewnątrz (backend, cache) i nie ma gwarancji
    /// kolejności.
    var sortedByDay: [MealSlot] {
        MealSlot.allCases.filter { contains($0) }
    }
}
