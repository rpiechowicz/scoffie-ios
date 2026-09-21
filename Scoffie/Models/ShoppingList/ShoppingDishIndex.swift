import Foundation

// Wiąże produkty listy zakupów z daniami, z których się wzięły.
//
// Backend tego powiązania NIE dowozi: `BackendShoppingItemDTO` to sama nazwa,
// ilość, jednostka i dział. Ale dowozi coś, co wystarczy — `productKey`
// liczone przez `normalizeProductKey(name, unit)`, czyli dosłownie
// `"<nazwa składnika>::<jednostka>"`. Ta sama nazwa stoi w składnikach
// przepisu, który telefon ma już wczytany razem z planem tygodnia
// (`weeklyPlans:getByWeek` oddaje pełne wiersze składników), więc dania
// stojące za produktem da się złożyć lokalnie, bez jednej dodatkowej rundy
// do serwera.

/// Danie tygodnia, z którego wziął się produkt na liście zakupów.
struct ShoppingDish: Identifiable, Hashable {
    let id: String
    let title: String
    /// Skrócony tytuł do jednej linijki pod nazwą produktu — patrz
    /// `ShoppingDishIndex.shortTitle`.
    let shortTitle: String
    let date: Date
    let slot: MealSlot
    let imageURL: URL?
    let participantIds: [String]
    let isToday: Bool
    /// Indeks dnia w widocznym tygodniu — po nim idzie kolejność dań.
    let dayOrder: Int
}

/// Produkty listy zakupów ↔ dania widocznego tygodnia.
struct ShoppingDishIndex {
    static let empty = ShoppingDishIndex(dishes: [], dishesByIngredient: [:])

    /// Wszystkie dania tygodnia w kolejności dzień → pora dnia.
    let dishes: [ShoppingDish]

    /// Nazwa składnika (małymi literami) → dania, które go potrzebują.
    private let dishesByIngredient: [String: [ShoppingDish]]

    var isEmpty: Bool { dishes.isEmpty }

    /// Dania zaplanowane na dziś — z nich bierze się wiersz „Na dziś”.
    var todayDishes: [ShoppingDish] { dishes.filter(\.isToday) }

    // MARK: - Budowanie

    /// Składa indeks z planu widocznego tygodnia.
    ///
    /// `mealsProvider` i `isToday` przychodzą z zewnątrz zamiast referencji do
    /// `MealCalendarStore`, żeby indeks dał się zbudować także z danych
    /// z podglądu albo z mocka — sam nic nie wie o sieci ani o magazynach.
    static func build(
        dates: [Date],
        isToday: (Date) -> Bool,
        mealsProvider: (Date, MealSlot) -> [PlanMeal]
    ) -> ShoppingDishIndex {
        var dishes: [ShoppingDish] = []
        var dishesByIngredient: [String: [ShoppingDish]] = [:]

        for (dayOrder, date) in dates.enumerated() {
            let dayIsToday = isToday(date)
            let dayKey = MealCalendarStore.dateKey(for: date)

            for slot in MealSlot.allCases {
                for meal in mealsProvider(date, slot) {
                    let dish = ShoppingDish(
                        // Sam `meal.id` nie wystarczy: posiłek dodany lokalnie
                        // dostaje syntetyczne id do czasu odświeżenia tygodnia,
                        // a dzień i pora domykają tożsamość wiersza planu.
                        id: "\(dayKey).\(slot.rawValue).\(meal.id)",
                        title: meal.recipe.name,
                        shortTitle: shortTitle(meal.recipe.name),
                        date: date,
                        slot: slot,
                        imageURL: meal.recipe.imageURL,
                        participantIds: meal.participantIds,
                        isToday: dayIsToday,
                        dayOrder: dayOrder
                    )
                    dishes.append(dish)

                    // Ten sam składnik potrafi stać w przepisie dwa razy
                    // (np. oliwa do smażenia i do polania) — danie ma się
                    // pojawić pod produktem raz.
                    var seen = Set<String>()
                    for ingredient in meal.recipe.ingredients {
                        let key = normalizedKey(ingredient.name)
                        guard !key.isEmpty, seen.insert(key).inserted else { continue }
                        dishesByIngredient[key, default: []].append(dish)
                    }
                }
            }
        }

        return ShoppingDishIndex(dishes: dishes, dishesByIngredient: dishesByIngredient)
    }

    // MARK: - Odpytywanie

    /// Dania stojące za produktem.
    ///
    /// Dopasowujemy po SAMEJ NAZWIE, bez jednostki z `productKey`. Powód jest
    /// w danych: klucz serwera bierze `normalizedUnit ?? unit`, a lista
    /// przepisów potrafi przyjechać bez normalizacji — wtedy klucz złożony
    /// lokalnie z surowej jednostki („łyżka”) nie trafiłby w żaden produkt
    /// i wiersz zostałby bez dań. Nazwa jest kanoniczna po obu stronach:
    /// backend zapisuje ją na listę przez `toTitleCase`, a iOS przez
    /// `displayIngredientName` — obie robią dokładnie to samo.
    func dishes(for item: ShoppingItem) -> [ShoppingDish] {
        dishesByIngredient[Self.ingredientKey(of: item)] ?? []
    }

    /// Czy produkt jest potrzebny do któregoś z dzisiejszych dań.
    func isForToday(_ item: ShoppingItem) -> Bool {
        dishes(for: item).contains(where: \.isToday)
    }

    /// Nazwy dań pod nazwą produktu — „Omlet ze szpinakiem · Krem z pomidorów”.
    /// `nil`, gdy produktu nie da się przypiąć do żadnego dania (ręczna
    /// pozycja albo przepis wycofany z planu po zbudowaniu listy).
    func dishSummary(for item: ShoppingItem) -> String? {
        // Po daniach z planu idą przepisy, z których produkt DOPISANO ręcznie
        // („brakuje mi”) — inaczej taka pozycja stałaby na liście bez słowa
        // o tym, skąd się wzięła.
        let titles = dishes(for: item).map(\.shortTitle)
            + (item.addedFrom ?? []).map { Self.shortTitle($0) }
        guard !titles.isEmpty else { return nil }

        // Kolejność bierze się z planu, więc duplikaty („Omlet” na dwa dni)
        // stoją obok siebie i wystarczy odsiać powtórki, zachowując kolejność.
        var seen = Set<String>()
        let unique = titles.filter { seen.insert($0).inserted }
        return unique.joined(separator: " · ")
    }

    /// Produkty potrzebne do jednego dania, w kolejności podanej listy.
    func items(_ items: [ShoppingItem], for dish: ShoppingDish) -> [ShoppingItem] {
        items.filter { dishes(for: $0).contains(dish) }
    }

    // MARK: - Klucze

    private static func ingredientKey(of item: ShoppingItem) -> String {
        // `productKey` to `"<nazwa>::<jednostka>"`. Gdyby kiedyś przyjechał
        // klucz bez separatora, nazwa produktu mówi to samo — serwer pisze ją
        // z tego samego źródła.
        let namePart = item.productKey.components(separatedBy: "::").first ?? ""
        return normalizedKey(namePart.isEmpty ? item.name : namePart)
    }

    private static func normalizedKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Skracanie tytułów

    /// Łączniki, po których w tytule zaczyna się wyliczanie dodatków.
    private static let titleCutoffs = [", ", " – ", " — ", " - ", " (", " i ", " oraz "]

    /// Słowa, na których nazwa nie ma prawa się skończyć.
    private static let danglingWords: Set<String> = [
        "z", "ze", "w", "we", "na", "po", "i", "oraz", "do", "od", "bez", "pod"
    ]

    /// Ile znaków mieści się pod nazwą produktu, zanim wiersz zacznie ciąć
    /// tytuł wielokropkiem.
    private static let shortTitleLimit = 24

    /// Krótka nazwa dania.
    ///
    /// Pod nazwą produktu jest JEDNA linijka na wszystkie dania, a tytuły
    /// katalogowe mają po pięć–siedem słów („Kurczak pieczony z batatem
    /// i cukinią”). Bez skrócenia widać z nich pierwsze dwa słowa
    /// i wielokropek — czyli tyle samo, co po odcięciu, tylko brzydziej.
    ///
    /// Reguła jest w dwóch krokach: najpierw wyliczanie dodatków („… i …”,
    /// „…, …”), potem twardy limit długości na granicy słowa. Wiszący przyimek
    /// spada na końcu, bo „Kurczak pieczony z” czyta się jak urwane zdanie,
    /// a nie jak nazwa dania.
    static func shortTitle(_ title: String) -> String {
        var cut = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cut.isEmpty else { return cut }

        for separator in titleCutoffs {
            guard let range = cut.range(of: separator, options: [.caseInsensitive]) else { continue }
            let head = String(cut[cut.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !head.isEmpty { cut = head }
        }

        var words = cut.split(separator: " ").map(String.init)
        while words.count > 1, words.joined(separator: " ").count > shortTitleLimit {
            words.removeLast()
        }
        while words.count > 1, danglingWords.contains(words[words.count - 1].lowercased()) {
            words.removeLast()
        }

        let result = words.joined(separator: " ")
        return result.isEmpty ? cut : result
    }
}
