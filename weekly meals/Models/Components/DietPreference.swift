import SwiftUI

// User's primary eating-style preference. Stored in `@AppStorage` as the
// raw value, so adding cases later is non-breaking — unknown ids fall
// back to `.none`. Used by Settings → Dieta i alergeny and (eventually)
// by the recipe-suggestions backend.
enum DietPreference: String, CaseIterable, Identifiable {
    case none
    case vegetarian
    case vegan
    case pescatarian
    case keto
    case paleo
    case highProtein

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:         return "Bez ograniczeń"
        case .vegetarian:   return "Wegetariańska"
        case .vegan:        return "Wegańska"
        case .pescatarian:  return "Pescetariańska"
        case .keto:         return "Ketogeniczna"
        case .paleo:        return "Paleo"
        case .highProtein:  return "Wysokobiałkowa"
        }
    }

    var subtitle: String {
        switch self {
        case .none:         return "Aplikacja proponuje wszystkie przepisy."
        case .vegetarian:   return "Bez mięsa i ryb."
        case .vegan:        return "Bez produktów odzwierzęcych."
        case .pescatarian:  return "Bez mięsa, z rybami i owocami morza."
        case .keto:         return "Bardzo niska zawartość węglowodanów."
        case .paleo:        return "Bez zbóż, nabiału i przetworzonych."
        case .highProtein:  return "Min. 20 % kalorii z białka."
        }
    }

    var icon: String {
        switch self {
        case .none:         return "fork.knife"
        case .vegetarian:   return "leaf.fill"
        case .vegan:        return "carrot.fill"
        case .pescatarian:  return "fish.fill"
        case .keto:         return "flame.fill"
        case .paleo:        return "hare.fill"
        case .highProtein:  return "figure.strengthtraining.traditional"
        }
    }

    /// Wartość, którą rozumie backend (`DietPreferenceValue` w Prismie).
    ///
    /// Nie da się jej wyprowadzić przez `rawValue.uppercased()`: `highProtein`
    /// dałoby `HIGHPROTEIN`, a kolumna trzyma `HIGH_PROTEIN`. Przez to zapis
    /// leciał w kosz na walidacji, a przy następnym odczycie `high_protein`
    /// nie parsowało się z powrotem i wybór wracał do „Bez ograniczeń”.
    /// Mapowanie jest wypisane wprost, żeby dokładanie kolejnej
    /// wieloczłonowej diety nie odtworzyło tego błędu.
    var backendValue: String {
        switch self {
        case .none:         return "NONE"
        case .vegetarian:   return "VEGETARIAN"
        case .vegan:        return "VEGAN"
        case .pescatarian:  return "PESCATARIAN"
        case .keto:         return "KETO"
        case .paleo:        return "PALEO"
        case .highProtein:  return "HIGH_PROTEIN"
        }
    }

    init?(backendValue: String) {
        let normalised = backendValue.uppercased()
        guard let match = DietPreference.allCases.first(where: { $0.backendValue == normalised }) else {
            return nil
        }
        self = match
    }

    var accent: Color {
        switch self {
        case .none:         return WMPalette.terracotta
        case .vegetarian:   return WMPalette.sage
        case .vegan:        return WMPalette.sage
        case .pescatarian:  return WMPalette.indigo
        case .keto:         return WMPalette.terracotta
        case .paleo:        return WMPalette.butter
        case .highProtein:  return WMPalette.indigo
        }
    }
}

// Alergeny i nietolerancje, których realnie da się uniknąć w tym katalogu.
//
// `rawValue` to kontrakt z backendem: dokładnie te id trzyma
// `UserPreference.allergens` i `Recipe.allergens` (`src/common/allergens.ts`).
// Nowa wartość wchodzi NAJPIERW na serwer — inaczej odrzuci cały zapis
// preferencji. Od plastra D przepis niesie alergeny policzone na serwerze
// z kuratorowanych tagów składników, więc chip nie obiecuje więcej, niż
// katalog dowozi:
//
//   laktoza = nabiał ZAWIERAJĄCY laktozę (nietolerancja), nie alergia na
//             białko mleka — produkty „bez laktozy" i ghee jej nie mają;
//   ryby    = ryby i owoce morza (krewetka też);
//   seler   — także w bulionach i przyprawie uniwersalnej;
//   gorczyca — także w majonezie; sezam — także w hummusie i tahini.
//
// Lista celowo krótsza niż „14 alergenów UE": chip, którego katalog nie
// potrafi wypełnić, obiecuje ochronę, której nie dowozimy. Nieznane id z
// serwera zostają w zapisie (unia w `SettingsView`), ale nie renderują chipa.
//
// Multi-select; persisted in `@AppStorage` as a sorted comma-separated
// raw-value string (`"eggs,gluten,nuts"`).
enum Allergen: String, CaseIterable, Identifiable {
    case gluten
    case lactose
    case eggs
    case nuts
    case peanuts
    case fish
    case soy
    case celery
    case mustard
    case sesame

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gluten:       return "Gluten"
        case .lactose:      return "Laktoza"
        case .eggs:         return "Jaja"
        case .nuts:         return "Orzechy"
        case .peanuts:      return "Orzeszki ziemne"
        case .fish:         return "Ryby i owoce morza"
        case .soy:          return "Soja"
        case .celery:       return "Seler"
        case .mustard:      return "Gorczyca"
        case .sesame:       return "Sezam"
        }
    }
}
