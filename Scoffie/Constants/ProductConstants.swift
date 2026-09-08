import SwiftUI

struct ProductConstants {
    // Działy w sklepie (kategorie wysokiego poziomu)
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

    // Mapowanie produktu -> dział sklepu
    static let productToDepartment: [String: String] = [
        // Warzywa
        "Marchew": Department.vegetables,
        "Ziemniaki": Department.vegetables,
        "Cebula": Department.vegetables,
        "Cebula czerwona": Department.vegetables,
        "Czosnek": Department.vegetables,
        "Papryka": Department.vegetables,
        "Ogórek": Department.vegetables,
        "Pomidory": Department.vegetables,
        "Pomidory krojone": Department.vegetables,
        "Sałata": Department.vegetables,
        "Sałata rzymska": Department.vegetables,
        "Szpinak": Department.vegetables,
        "Brokuł": Department.vegetables,
        "Kalafior": Department.vegetables,
        "Cukinia": Department.vegetables,
        "Bakłażan": Department.vegetables,
        "Buraki": Department.vegetables,
        "Pieczarki": Department.vegetables,
        "Seler": Department.vegetables,
        "Pietruszka (korzeń)": Department.vegetables,
        "Natka pietruszki": Department.vegetables,
        "Szczypiorek": Department.vegetables,
        "Awokado": Department.vegetables,
        "Warzywa mieszane": Department.vegetables,
        "Warzywa świeże": Department.vegetables,

        // Owoce
        "Jabłka": Department.fruits,
        "Banany": Department.fruits,
        "Banan": Department.fruits,
        "Pomarańcze": Department.fruits,
        "Cytryny": Department.fruits,
        "Cytryna": Department.fruits,
        "Truskawki": Department.fruits,
        "Winogrona": Department.fruits,
        "Borówki": Department.fruits,
        "Maliny": Department.fruits,
        "Jagody": Department.fruits,
        "Gruszki": Department.fruits,
        "Ananas": Department.fruits,
        "Sok z cytryny": Department.fruits,

        // Mięso
        "Pierś z kurczaka": Department.meat,
        "Udko z kurczaka": Department.meat,
        "Kurczak grillowany": Department.meat,
        "Kurczak (skrzydła/udo)": Department.meat,
        "Wołowina": Department.meat,
        "Mięso mielone wołowe": Department.meat,
        "Wieprzowina": Department.meat,
        "Indyk": Department.meat,
        "Mięso mielone z indyka": Department.meat,
        "Kiełbasa": Department.meat,
        "Szynka": Department.meat,
        "Boczek": Department.meat,

        // Ryby
        "Łosoś": Department.fish,
        "Dorsz": Department.fish,
        "Tuńczyk (świeży)": Department.fish,
        "Tuńczyk w sosie własnym": Department.fish,
        "Krewetki": Department.fish,

        // Nabiał
        "Mleko": Department.dairy,
        "Jogurt": Department.dairy,
        "Jogurt naturalny": Department.dairy,
        "Masło": Department.dairy,
        "Śmietana": Department.dairy,
        "Śmietanka": Department.dairy,
        "Ser żółty": Department.dairy,
        "Ser feta": Department.dairy,
        "Twaróg": Department.dairy,
        "Twaróg półtłusty": Department.dairy,
        "Mozzarella": Department.dairy,
        "Parmezan": Department.dairy,
        "Jajka": Department.dairy,
        "Jajko": Department.dairy,

        // Piekarnia
        "Chleb": Department.bakery,
        "Bułki": Department.bakery,
        "Bułka pełnoziarnista": Department.bakery,
        "Tortilla": Department.bakery,
        "Pieczywo tostowe": Department.bakery,
        "Chleb pita": Department.bakery,

        // Zboża i makarony
        "Makaron": Department.grains,
        "Makaron spaghetti": Department.grains,
        "Makaron ryżowy (suchy)": Department.grains,
        "Ryż": Department.grains,
        "Ryż basmati (suchy)": Department.grains,
        "Ryż biały (suchy)": Department.grains,
        "Ryż (suchy)": Department.grains,
        "Ryż arborio": Department.grains,
        "Komosa ryżowa": Department.grains,
        "Kasza": Department.grains,
        "Płatki owsiane": Department.grains,
        "Granola": Department.grains,
        "Mąka": Department.grains,
        "Soczewica czerwona": Department.grains,
        "Ciecierzyca": Department.grains,
        "Fasola czarna (ugotowana)": Department.grains,
        "Nasiona chia": Department.grains,

        // Konserwy i słoiki
        "Fasola konserwowa": Department.canned,
        "Ciecierzyca konserwowa": Department.canned,
        "Pomidory krojone (puszka)": Department.canned,
        "Tuńczyk (puszka)": Department.canned,
        "Kukurydza (puszka)": Department.canned,
        "Kukurydza": Department.canned,
        "Ogórki kiszone": Department.canned,
        "Oliwki": Department.canned,
        "Passata pomidorowa": Department.canned,
        "Hummus": Department.canned,
        "Bulion warzywny": Department.canned,
        "Mleko kokosowe": Department.canned,

        // Napoje
        "Woda": Department.beverages,
        "Sok": Department.beverages,
        "Kawa": Department.beverages,
        "Herbata": Department.beverages,
        "Białe wino": Department.alcohols,
        "Wino": Department.alcohols,
        "Riesling": Department.alcohols,

        // Przekąski i słodycze
        "Czekolada": Department.snacks,
        "Ciastka": Department.snacks,
        "Chipsy": Department.snacks,
        "Orzechy": Department.snacks,
        "Orzechy włoskie": Department.snacks,
        "Pestki dyni": Department.snacks,
        "Sezam": Department.snacks,
        "Masło orzechowe": Department.snacks,
        "Miód": Department.snacks,
        "Baton": Department.snacks,

        // Przyprawy i sosy
        "Sól": Department.spices,
        "Pieprz": Department.spices,
        "Papryka słodka": Department.spices,
        "Curry": Department.spices,
        "Pasta curry": Department.spices,
        "Oregano": Department.spices,
        "Bazylia": Department.spices,
        "Cynamon": Department.spices,
        "Przyprawy": Department.spices,
        "Ketchup": Department.spices,
        "Musztarda": Department.spices,
        "Majonez": Department.spices,
        "Sos sojowy": Department.spices,
        "Sos Caesar": Department.spices,
        "Sos teriyaki": Department.spices,
        "Ocet": Department.spices,

        // Oleje i tłuszcze
        "Oliwa z oliwek": Department.oils,
        "Oliwa": Department.oils,
        "Olej": Department.oils,
        "Olej rzepakowy": Department.oils,
        "Masło klarowane": Department.oils,

        // Mrożonki
        "Warzywa mrożone": Department.frozen,
        "Owoce mrożone": Department.frozen,
        "Mrożone owoce": Department.frozen,
        "Lody": Department.frozen,

        // Inne specjalne
        "Tofu": Department.other,

        // Chemia i gospodarstwo
        "Papier toaletowy": Department.household,
        "Ręczniki papierowe": Department.household,
        "Płyn do naczyń": Department.household,
        "Proszek do prania": Department.household,
        "Worki na śmieci": Department.household,
    ]

    // Pomocnicze API
    static func department(for productName: String) -> String {
        // Dokładne dopasowanie
        if let dept = productToDepartment[productName] { return dept }
        // Częściowe dopasowanie (np. "Ryż basmati" pasuje do "Ryż")
        for (key, dept) in productToDepartment {
            if productName.localizedCaseInsensitiveContains(key)
                || key.localizedCaseInsensitiveContains(productName) {
                return dept
            }
        }
        return Department.other
    }

    static func products(in department: String) -> [String] {
        return productToDepartment
            .filter { $0.value == department }
            .map { $0.key }
            .sorted()
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
