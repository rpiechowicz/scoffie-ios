import SwiftUI

// Krótkie nazwy i dopowiedzenia alergenów — wspólne dla karty i arkusza
// wyboru (`AllergenPickerSheet.swift`). Siatka 3 × 5 (`AllergenPicker`), która
// tu mieszkała, zniknęła 24.09.2026: kreator stoi teraz na tym samym arkuszu
// co Ustawienia (`AllergenSelectionField`).

extension Allergen {
    /// Krótka nazwa na etykietę i wiersz arkusza. Nawias z `title`
    /// („Laktoza (nietolerancja)”) schodzi do zdania pod listą.
    var pickerTitle: String {
        switch self {
        case .gluten:       return "Gluten"
        case .lactose:      return "Laktoza"
        case .eggs:         return "Jaja"
        case .nuts:         return "Orzechy"
        case .peanuts:      return "Orzeszki ziemne"
        case .fish:         return "Ryby"
        case .soy:          return "Soja"
        case .celery:       return "Seler"
        case .mustard:      return "Gorczyca"
        case .sesame:       return "Sezam"
        case .milk:         return "Mleko"
        case .crustaceans:  return "Skorupiaki"
        case .molluscs:     return "Mięczaki"
        case .lupin:        return "Łubin"
        case .sulphites:    return "Siarczyny"
        }
    }

    /// Co alergen obejmuje albo gdzie się chowa — podpowiedź VoiceOver przy
    /// pigułce. Ten sam zakres, który egzekwuje serwer
    /// (`src/common/allergens.ts`) — patrz komentarz przy `enum Allergen`.
    var pickerDetail: String {
        switch self {
        case .gluten:       return "pszenica, żyto, jęczmień, owies"
        case .lactose:      return "nietolerancja laktozy"
        case .eggs:         return "też w majonezie"
        case .nuts:         return "włoskie, laskowe, migdały"
        case .peanuts:      return "też masło orzechowe"
        case .fish:         return "razem z owocami morza"
        case .soy:          return "tofu, sos sojowy, edamame"
        case .celery:       return "też w bulionach"
        case .mustard:      return "musztarda, też majonez"
        case .sesame:       return "też tahini i hummus"
        case .milk:         return "alergia na białko mleka"
        case .crustaceans:  return "krewetki, kraby"
        case .molluscs:     return "małże, kalmary"
        case .lupin:        return "mąka z łubinu"
        case .sulphites:    return "wino, suszone owoce"
        }
    }
}
