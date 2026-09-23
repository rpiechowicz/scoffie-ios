import SwiftUI

/// Wybór alergenów — Ustawienia → „Dieta i alergeny” i krok 3 kreatora.
///
/// Piętnaście krótkich pigułek w siatce 3 × 5 w jednej karcie. Kolejność
/// układa rzędy w trójki tematyczne: gluten i mleko, jaja i orzechy, ryby
/// i owoce morza, nasiona i warzywa, dodatki — więc siatka czyta się jak
/// lista w grupach, choć nie ma nagłówków.
///
/// Dwa poprzednie układy nie działały. Chmura pigułek układała się według
/// długości nazw („Laktoza (nietolerancja)” rozpychała rząd, „Siarczyny”
/// zostawały same w ostatnim). Kafelki z dopowiedzeniem były czytelne, ale
/// piętnaście kafelków w trzech grupach zajmowało półtora ekranu. Teraz
/// nazwa jest krótka, a dopowiedzenie (gdzie alergen się chowa) czyta
/// VoiceOver jako podpowiedź; pod siatką jedno zdanie o tym, co najczęściej
/// myli: laktoza to nie mleko.
///
/// Widok niczego nie zapisuje: dostaje zaznaczone i oddaje stuknięcia.
/// Unię „znane ∪ nieznane” (alergeny z nowszego buildu) trzyma właściciel,
/// patrz `SettingsView.toggleAllergen`.
struct AllergenPicker: View {
    let selected: Set<Allergen>
    let onToggle: (Allergen) -> Void

    @Environment(\.colorScheme) private var scheme

    /// Rzędy po trzy: gluten · laktoza · mleko / jaja · orzechy · orzeszki /
    /// ryby · skorupiaki · mięczaki / soja · sezam · seler / gorczyca · łubin
    /// · siarczyny. Alergen spoza listy (nowa wartość enuma) dochodzi na
    /// końcu — lepiej ostatni rząd niż cicho zniknięta pigułka.
    private static let order: [Allergen] = {
        let listed: [Allergen] = [
            .gluten, .lactose, .milk,
            .eggs, .nuts, .peanuts,
            .fish, .crustaceans, .molluscs,
            .soy, .sesame, .celery,
            .mustard, .lupin, .sulphites
        ]
        return listed + Allergen.allCases.filter { !listed.contains($0) }
    }()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Self.order) { allergen in
                    AllergenPill(
                        allergen: allergen,
                        isOn: selected.contains(allergen),
                        action: { onToggle(allergen) }
                    )
                }
            }

            Text("Laktoza to nietolerancja, mleko — alergia na jego białko. Liczymy też ukryte źródła, np. jaja i gorczycę w majonezie.")
                .font(.system(size: 12))
                .foregroundStyle(Color.scFaint(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// Pigułka alergenu w siatce — zaznaczona w wariancie „soft” (tint i obwódka
/// terakoty, ptaszek), niezaznaczona na tle pola.
private struct AllergenPill: View {
    let allergen: Allergen
    let isOn: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    private static let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
                Text(allergen.pickerTitle)
                    .font(.system(size: 13, weight: isOn ? .semibold : .medium))
                    .tracking(-0.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isOn ? SCPalette.terracotta : Color.scLabel(scheme))
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(Self.shape.fill(isOn ? SCPalette.terracotta.opacity(scheme == .dark ? 0.16 : 0.12) : Color.scChipBg(scheme)))
            .overlay(Self.shape.strokeBorder(isOn ? SCPalette.terracotta.opacity(0.45) : Color.scTileStroke(scheme), lineWidth: 1))
            .contentShape(Self.shape)
        }
        .buttonStyle(PlanPressStyle(scale: 0.95))
        .animation(.spring(response: 0.26, dampingFraction: 0.75), value: isOn)
        .accessibilityLabel(allergen.title)
        .accessibilityValue(isOn ? "Zaznaczone" : "Niezaznaczone")
        .accessibilityHint(allergen.pickerDetail)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

extension Allergen {
    /// Krótka nazwa na pigułkę. Nawias z `title` („Laktoza (nietolerancja)”)
    /// schodzi do zdania pod siatką.
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
