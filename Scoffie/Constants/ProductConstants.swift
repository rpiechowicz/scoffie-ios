import SwiftUI

/// Działy sklepu — nazwa, ikona i barwa.
///
/// Przypisanie PRODUKTU do działu robi backend: `toShoppingDepartment` liczy je
/// ze składnika przepisu i przysyła w `BackendShoppingItemDTO.department`.
/// Telefon zna tylko listę nazw, żeby wiedzieć, w jakiej kolejności ustawić
/// alejki i jaką barwą je podpisać.
///
/// Stała mapa produkt → dział (~190 wierszy: „Marchew” → Warzywa,
/// „Pierś z kurczaka” → Mięso, …) razem z `department(for:)` i `products(in:)`
/// zeszła stąd jako martwy kod. Nikt jej nie wołał od czasu, gdy lista zakupów
/// zaczęła przychodzić z serwera, a każdy nowy produkt w katalogu i tak
/// wchodził tam poza nią. Klasyfikacja po nazwie na telefonie miałaby sens
/// tylko jako druga, rozjeżdżająca się z serwerem prawda.
struct ProductConstants {
    struct Department {
        static let vegetables = "Warzywa"
        static let fruits = "Owoce"
        static let meat = "Mięso"
        static let fish = "Ryby"
        static let bakery = "Piekarnia"
        static let dairy = "Nabiał"
        static let grains = "Zboża i makarony"
        static let canned = "Konserwy"
        static let beverages = "Napoje"
        static let snacks = "Przekąski i słodycze"
        static let household = "Chemia i gospodarstwo"
        static let frozen = "Mrożonki"
        static let spices = "Przyprawy i sosy"
        static let oils = "Olej i tłuszcze"
        static let alcohols = "Alkohole"
        static let bakerySweets = "Cukiernia"
        static let other = "Inne"
    }

    // MARK: - Department Icon & Color

    static func departmentIcon(for department: String) -> String {
        let d = department.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch d {
        case Department.vegetables.lowercased():    return "leaf.fill"
        case Department.fruits.lowercased():        return "carrot.fill"
        case Department.meat.lowercased():          return "fork.knife"
        case Department.fish.lowercased():          return "fish.fill"
        case Department.bakery.lowercased():        return "storefront.fill"
        case Department.dairy.lowercased():         return "cup.and.saucer.fill"
        case Department.grains.lowercased():        return "takeoutbag.and.cup.and.straw.fill"
        case Department.canned.lowercased():        return "shippingbox.fill"
        case Department.beverages.lowercased():     return "waterbottle.fill"
        case Department.snacks.lowercased():        return "bag.fill"
        case Department.household.lowercased():     return "sparkles"
        case Department.frozen.lowercased():        return "snowflake"
        case Department.spices.lowercased():        return "flame.fill"
        case Department.oils.lowercased():          return "drop.fill"
        case Department.alcohols.lowercased():      return "wineglass.fill"
        case Department.bakerySweets.lowercased():  return "birthday.cake.fill"
        default:                       return "basket.fill"
        }
    }

    // Paleta „Cozy Kitchen" — dział bierze jeden z OŚMIU akcentów.
    //
    // Było pięć i szesnaście działów, więc samo indygo wracało pięć razy:
    // ryby, kasze, napoje, mrożonki i alkohole miały jedną barwę i kropka
    // przy nagłówku sekcji przestawała cokolwiek mówić. Odkąd pory dnia
    // dostały róż, morską i lawendę, jest z czego brać — szesnaście działów
    // dzieli osiem kolorów dokładnie po dwa.
    //
    // Gdzie się dało, kolor coś znaczy (warzywa zielone, mięso ceglaste,
    // ryby morskie, pieczywo złote, wino różowe, mrożonki zimne). Gdzie nie
    // — liczy się tylko to, żeby sąsiedzi na liście się różnili.
    static func departmentColor(for department: String) -> Color {
        let d = department.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch d {
        case Department.vegetables.lowercased():    return SCPalette.sage
        case Department.fruits.lowercased():        return SCPalette.rose
        case Department.meat.lowercased():          return SCPalette.terracottaDeep
        case Department.fish.lowercased():          return SCPalette.teal
        case Department.bakery.lowercased():        return SCPalette.butter
        case Department.dairy.lowercased():         return SCPalette.lavender
        case Department.grains.lowercased():        return SCPalette.terracotta
        case Department.canned.lowercased():        return SCPalette.indigo
        case Department.beverages.lowercased():     return SCPalette.teal
        // Ta sama lawenda, co pora „przekąska" w Planie i Kalendarzu.
        case Department.snacks.lowercased():        return SCPalette.lavender
        case Department.household.lowercased():     return SCPalette.sage
        case Department.frozen.lowercased():        return SCPalette.indigo
        case Department.spices.lowercased():        return SCPalette.terracottaDeep
        case Department.oils.lowercased():          return SCPalette.butter
        case Department.alcohols.lowercased():      return SCPalette.rose
        case Department.bakerySweets.lowercased():  return SCPalette.terracotta
        default:                                    return SCPalette.sage
        }
    }
}
