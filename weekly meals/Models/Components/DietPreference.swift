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
// Lista jest krótsza niż „14 alergenów UE" i to jest celowe: chip, którego
// nie ma czym wypełnić, obiecuje ochronę, której nie dowozimy. Zostały te,
// które mają w katalogu składników rzeczywiste źródła i występują w polskiej
// kuchni domowej:
//
//   laktoza  — 43 źródła   gluten   — 40 źródeł
//   ryby     —  9 źródeł   orzechy  —  3 źródła
//   jaja     —  2 źródła (ale 9 z 30 przepisów)
//   soja     —  1 źródło (sos sojowy — najczęstszy ukryty nośnik)
//   orzeszki —  1 źródło (osobno od orzechów: to inna alergia i częstsza)
//
// Wypadły `sezam` i `seler` (po jednym źródle, zero przepisów) oraz
// `shellfish` — jedyna pozycja katalogu to krewetka, siedząca i tak w dziale
// „Ryby", więc jest teraz obsługiwana przez „Ryby i owoce morza".
//
// Usunięte wartości nie wymagają migracji: `RecipePersonalization` czyta
// zapisane alergeny przez `compactMap(Allergen.init(rawValue:))`, więc stare
// wpisy po prostu przestają być rozpoznawane.
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
        }
    }
}
