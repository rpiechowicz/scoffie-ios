import Foundation

/// Taksonomia przepisu z serwera (katalog 1000, 28.09.2026): kuchnia, rodzaj
/// dania, pory roku, okazje, sprzęt i cechy. To pola, których NIE da się
/// wyliczyć ze składników — redakcja katalogu ustawia je ręcznie, a telefon
/// przestaje zgadywać rodzaj dania z nazwy (`RecipeCategoryFacets`).
///
/// Wartości to id z backendu (`src/recipes/recipe-taxonomy.ts`) — kontrakt jak
/// alergeny: nieznaną wartość telefon pomija, nie odrzuca przepisu.
///
/// `Recipe.taxonomy == nil` znaczy „serwer tego nie przysłał” (stary backend,
/// przepis z cache'u sprzed tej zmiany, mock) — wtedy filtry kategorii wracają
/// do heurystyki, a filtry kuchni i okazji przepisu nie łapią. Przepisy domu
/// przychodzą z `cuisine: OTHER` i `dishType: nil` — rodzaj też z heurystyki.
struct RecipeTaxonomy: Codable, Hashable {
    /// `POLISH`, `ITALIAN`… albo `OTHER` (międzynarodowa / spoza listy).
    var cuisine: String
    /// `SOUP`, `PASTA`, `CAKE`, `DRINK`… `nil` = redakcja nie przypisała.
    var dishType: String?
    /// Pory roku; pusta lista = cały rok.
    var seasons: [String]
    /// `CHRISTMAS_EVE`, `CHRISTMAS`, `EASTER`, `BARBECUE`, `PARTY`.
    var occasions: [String]
    /// `OVEN`, `AIRFRYER`, `BLENDER`, `GRILL`, `JUICER`, `WAFFLE_MAKER`.
    var equipment: [String]
    /// `LUNCHBOX`, `SIDE`, `OCCASIONAL`.
    var features: [String]

    init(
        cuisine: String = "OTHER",
        dishType: String? = nil,
        seasons: [String] = [],
        occasions: [String] = [],
        equipment: [String] = [],
        features: [String] = []
    ) {
        self.cuisine = cuisine
        self.dishType = dishType
        self.seasons = seasons
        self.occasions = occasions
        self.equipment = equipment
        self.features = features
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cuisine = try container.decodeIfPresent(String.self, forKey: .cuisine) ?? "OTHER"
        dishType = try container.decodeIfPresent(String.self, forKey: .dishType)
        seasons = try container.decodeIfPresent([String].self, forKey: .seasons) ?? []
        occasions = try container.decodeIfPresent([String].self, forKey: .occasions) ?? []
        equipment = try container.decodeIfPresent([String].self, forKey: .equipment) ?? []
        features = try container.decodeIfPresent([String].self, forKey: .features) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case cuisine, dishType, seasons, occasions, equipment, features
    }
}

// MARK: - Kuchnia

/// Kafelki „Kuchnia” w filtrach. `OTHER` nie ma kafelka — „kuchnia inna”
/// niczego nie mówi, a to ponad połowa katalogu.
enum RecipeCuisine: String, CaseIterable, Identifiable {
    case polish = "POLISH"
    case italian = "ITALIAN"
    case spanish = "SPANISH"
    case greek = "GREEK"
    case indian = "INDIAN"
    case thai = "THAI"
    case mexican = "MEXICAN"
    case american = "AMERICAN"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .polish:   return "Polska"
        case .italian:  return "Włoska"
        case .spanish:  return "Hiszpańska"
        case .greek:    return "Grecka"
        case .indian:   return "Indyjska"
        case .thai:     return "Tajska"
        case .mexican:  return "Meksykańska"
        case .american: return "Amerykańska"
        }
    }

    /// Glif, gdy żaden przepis tej kuchni nie ma zdjęcia.
    var tileIcon: String {
        self == .polish ? "fork.knife" : "globe.europe.africa.fill"
    }
}

// MARK: - Okazje i sezon

/// Kafelki „Okazje i sezon”: święta, grill, impreza i cztery pory roku. Jedna
/// sekcja, bo to jedno pytanie — „na kiedy gotuję” — a osobne sekcje po
/// cztery–pięć kafelków rozciągały arkusz. W obrębie sekcji LUB („Lato albo
/// Grill”).
///
/// Pora roku łapie tylko dania SEZONOWE (szparagi, truskawki, dynia) — przepis
/// bez pór jest całoroczny i nie wpada pod „Lato”, bo nic o lecie nie mówi.
enum RecipeMoment: String, CaseIterable, Identifiable {
    case christmasEve = "CHRISTMAS_EVE"
    case christmas = "CHRISTMAS"
    case easter = "EASTER"
    case barbecue = "BARBECUE"
    case party = "PARTY"
    case spring = "SPRING"
    case summer = "SUMMER"
    case autumn = "AUTUMN"
    case winter = "WINTER"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .christmasEve: return "Wigilia"
        case .christmas:    return "Boże Narodzenie"
        case .easter:       return "Wielkanoc"
        case .barbecue:     return "Grill"
        case .party:        return "Impreza"
        case .spring:       return "Wiosna"
        case .summer:       return "Lato"
        case .autumn:       return "Jesień"
        case .winter:       return "Zima"
        }
    }

    /// Nazwa w zdaniu podsumowania filtrów — święta z wielkiej litery.
    var summaryTitle: String {
        switch self {
        case .christmasEve, .christmas, .easter: return title
        default:                                 return title.lowercased()
        }
    }

    var tileIcon: String {
        switch self {
        case .christmasEve: return "moon.stars.fill"
        case .christmas:    return "gift.fill"
        case .easter:       return "hare.fill"
        case .barbecue:     return "flame"
        case .party:        return "party.popper.fill"
        case .spring:       return "camera.macro"
        case .summer:       return "sun.max.fill"
        case .autumn:       return "leaf.fill"
        case .winter:       return "snowflake"
        }
    }
}

// MARK: - Odczyt z przepisu

extension Recipe {
    /// Kuchnia z kafelka albo `nil` (inna, nieznana, brak danych).
    var cuisine: RecipeCuisine? {
        taxonomy.flatMap { RecipeCuisine(rawValue: $0.cuisine) }
    }

    /// Okazje i pory roku przepisu w jednym zbiorze — pod sekcję „Okazje i sezon”.
    var moments: Set<RecipeMoment> {
        guard let taxonomy else { return [] }
        return Set((taxonomy.occasions + taxonomy.seasons).compactMap(RecipeMoment.init(rawValue:)))
    }

    /// Przepis napisany pod airfryer (w krokach ma też wariant na piekarnik).
    var isAirfryer: Bool { taxonomy?.equipment.contains("AIRFRYER") ?? false }

    /// Znosi transport w pudełku — na zimno albo do odgrzania.
    var isLunchbox: Bool { taxonomy?.features.contains("LUNCHBOX") ?? false }
}
