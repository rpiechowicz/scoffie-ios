import SwiftUI

/// Wybór alergenów — Ustawienia → „Dieta i alergeny” i krok 3 kreatora.
///
/// Piętnaście pozycji w trzech grupach, w siatce 2 × N kafelków
/// (`SCChoiceTile`), zamiast jednej chmury pigułek. Chmura układała się
/// według długości nazw, więc „Laktoza (nietolerancja)” rozpychała rząd,
/// a „Siarczyny” zostawały same w ostatnim — trudno było ją przeczytać
/// i jeszcze trudniej sprawdzić, co jest zaznaczone. Kafelek ma stałe
/// miejsce, krótką nazwę i jedną linijkę o tym, gdzie alergen się chowa
/// (majonez, buliony, tahini) — to są te rzeczy, o które ludzie pytają.
///
/// Widok niczego nie zapisuje: dostaje zaznaczone i oddaje stuknięcia.
/// Unię „znane ∪ nieznane” (alergeny z nowszego buildu) trzyma właściciel,
/// patrz `SettingsView.toggleAllergen`.
struct AllergenPicker: View {
    let selected: Set<Allergen>
    let onToggle: (Allergen) -> Void

    private struct AllergenGroup: Identifiable {
        let title: String
        let allergens: [Allergen]
        var id: String { title }
    }

    /// Kolejność w grupach: od najczęściej zaznaczanych. Alergen, którego
    /// nie ma w żadnej grupie (nowa wartość enuma), ląduje w „Innych” —
    /// lepiej ostatnia grupa niż cicho zniknięty chip.
    private static let groups: [AllergenGroup] = {
        let named: [AllergenGroup] = [
            AllergenGroup(title: "Najczęstsze", allergens: [.gluten, .lactose, .milk, .eggs, .nuts, .peanuts]),
            AllergenGroup(title: "Ryby i owoce morza", allergens: [.fish, .crustaceans, .molluscs]),
            AllergenGroup(title: "Nasiona, warzywa i dodatki", allergens: [.soy, .sesame, .celery, .mustard, .lupin, .sulphites])
        ]
        let listed = Set(named.flatMap(\.allergens))
        let rest = Allergen.allCases.filter { !listed.contains($0) }
        return rest.isEmpty ? named : named + [AllergenGroup(title: "Inne", allergens: rest)]
    }()

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Self.groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(group.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color.scMuted(scheme))
                        Spacer(minLength: 8)
                        let picked = group.allergens.filter { selected.contains($0) }.count
                        if picked > 0 {
                            Text(verbatim: "\(picked) z \(group.allergens.count)")
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(SCPalette.terracotta)
                                .contentTransition(.numericText(value: Double(picked)))
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 6)

                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(group.allergens) { allergen in
                            SCChoiceTile(
                                title: allergen.pickerTitle,
                                mark: selected.contains(allergen) ? .on : .off,
                                accessibilityValue: allergen.pickerDetail,
                                action: { onToggle(allergen) }
                            ) {
                                Text(allergen.pickerDetail)
                            }
                        }
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.2), value: selected)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

extension Allergen {
    /// Krótka nazwa na kafelek. Nawias z `title` („Laktoza (nietolerancja)”)
    /// schodzi do dopowiedzenia pod spodem, gdzie jest miejsce.
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

    /// Jedna linijka pod nazwą: co to obejmuje albo gdzie się chowa. Ten sam
    /// zakres, który egzekwuje serwer (`src/common/allergens.ts`) — patrz
    /// komentarz przy `enum Allergen`.
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
