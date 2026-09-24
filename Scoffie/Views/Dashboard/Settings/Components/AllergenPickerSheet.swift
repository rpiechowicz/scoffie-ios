import SwiftUI

// Alergeny w Ustawieniach → „Dieta i alergeny”: karta z tym, czego unikasz,
// i osobny arkusz wyboru.
//
// Trzy wcześniejsze układy w samym arkuszu diety nie działały: chmura pigułek
// rozjeżdżała się długością nazw, piętnaście kafli z opisami zajmowało półtora
// ekranu, a siatka 3 × 5 krótkich pigułek czytała się jak klawiatura bez
// objaśnień („dalej nie jest ładne UX” — Rafał, 23.09.2026). Teraz arkusz
// diety pokazuje tylko wynik — co jest wykluczone i ile przepisów przez to
// znika — a wybór ma własny arkusz, w którym jest miejsce na ikonę i jedno
// zdanie przy każdym alergenie (gdzie się chowa: jaja w majonezie, seler
// w bulionie). Od 24.09.2026 kreator powitalny stoi na tym samym mechanizmie
// (`AllergenSelectionField`) — siatka 3 × 5 z kreatora zniknęła, bo Rafał
// chciał w obu miejscach tego samego arkusza, a nie dwóch wyborów.

// MARK: - Karta + arkusz (Ustawienia i kreator)

/// Alergeny tam, gdzie się je ustawia: Ustawienia → „Dieta i alergeny”
/// i krok 3 kreatora. Karta z wynikiem otwiera arkusz wyboru — jeden
/// mechanizm w obu miejscach.
///
/// Widok niczego nie zapisuje: dostaje zaznaczone i oddaje stuknięcia.
/// Unię „znane ∪ nieznane” (alergeny z nowszego buildu) trzyma właściciel,
/// patrz `SettingsView.toggleAllergen`.
struct AllergenSelectionField: View {
    let selected: Set<Allergen>
    /// Ile przepisów znika przez zaznaczone alergeny (`nil` = nie wiadomo,
    /// np. w kreatorze, zanim wczyta się katalog).
    let hiddenRecipes: Int?
    let onToggle: (Allergen) -> Void
    let onClear: () -> Void

    @State private var showsPicker = false

    var body: some View {
        AllergenSummaryCard(
            selected: selected,
            hiddenRecipes: hiddenRecipes,
            onEdit: { showsPicker = true }
        )
        .sheet(isPresented: $showsPicker) {
            AllergenPickerSheet(
                selected: selected,
                hiddenRecipes: hiddenRecipes,
                onToggle: onToggle,
                onClear: onClear
            )
            .presentationDetents([.large])
            .dashboardLiquidSheet()
        }
    }
}

// MARK: - Karta w arkuszu diety

struct AllergenSummaryCard: View {
    let selected: Set<Allergen>
    /// Ile przepisów znika przez zaznaczone alergeny. `nil` = katalog się
    /// jeszcze nie wczytał — wtedy lepiej nic nie mówić niż „zero”.
    let hiddenRecipes: Int?
    let onEdit: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var ordered: [Allergen] { AllergenPickerGroup.ordered.filter { selected.contains($0) } }

    private var title: String {
        guard !selected.isEmpty else { return "Jesz wszystko" }
        let noun = PolishPlural.form(selected.count, one: "alergen", few: "alergeny", many: "alergenów")
        return "Omijamy \(selected.count) \(noun)"
    }

    private var subtitle: String {
        guard !selected.isEmpty else { return "Dodaj alergen, a przepisy z nim znikną" }
        guard let hiddenRecipes else { return "Znikają z przepisów i planu" }
        return hiddenRecipes == 0 ? "Żaden przepis ich nie zawiera" : "ukrywa \(PolishPlural.recipes(hiddenRecipes))"
    }

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    let accent = selected.isEmpty ? SCPalette.sage : SCPalette.terracotta
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(scheme == .dark ? 0.18 : 0.12))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: selected.isEmpty ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(accent)
                                .contentTransition(.symbolEffect(.replace))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 15.5, weight: .semibold))
                            .tracking(-0.25)
                            .foregroundStyle(Color.scLabel(scheme))
                            .contentTransition(.numericText())
                        Text(subtitle)
                            .font(.system(size: 12.5))
                            .monospacedDigit()
                            .foregroundStyle(Color.scMuted(scheme))
                            .contentTransition(.numericText())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 3) {
                        Text(selected.isEmpty ? "Dodaj" : "Zmień")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(SCPalette.terracotta)
                }

                if !selected.isEmpty {
                    AllergenChipFlow(spacing: 6) {
                        ForEach(ordered) { allergen in
                            AllergenTag(allergen: allergen)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.scTileStroke(scheme), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .animation(.smooth(duration: 0.22), value: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Alergeny")
        .accessibilityValue(selected.isEmpty ? "brak" : ordered.map(\.title).joined(separator: ", "))
        .accessibilityHint(selected.isEmpty ? "Dodaje alergeny" : "Zmienia alergeny")
        .accessibilityAddTraits(.isButton)
    }
}

/// Alergen na karcie: ikona i krótka nazwa w terakocie — wspólna etykieta
/// aplikacji (`SCTag`).
private struct AllergenTag: View {
    let allergen: Allergen

    var body: some View {
        SCTag(title: allergen.pickerTitle, icon: allergen.pickerIcon)
    }
}

// MARK: - Arkusz wyboru

struct AllergenPickerSheet: View {
    let selected: Set<Allergen>
    /// Ile przepisów znika przez zaznaczone alergeny (`nil` = nie wiadomo).
    let hiddenRecipes: Int?
    let onToggle: (Allergen) -> Void
    /// „Wyczyść” obok krzyżyka — zdejmuje wszystkie zaznaczone alergeny.
    let onClear: () -> Void

    /// Pytanie przed wyczyszczeniem wszystkich alergenów.
    @State private var confirmsClear = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // „Wyczyść” jak w filtrach i w wykluczaniu składników —
                // tylko wtedy, gdy coś jest zaznaczone.
                EditorialSheetHeader(
                    eyebrow: "Dieta",
                    title: "Alergeny",
                    onClose: { dismiss() }
                ) {
                    if !selected.isEmpty {
                        // Z pytaniem, w odróżnieniu od „Wyczyść” w filtrach:
                        // alergeny to bezpieczeństwo, a jedno stuknięcie
                        // przywracało na listy wszystko, co ukrywały — tak
                        // samo jak „Wyczyść preferencje”, które pyta.
                        RecipeFilterClearButton(accessibilityLabel: "Wyczyść alergeny") {
                            confirmsClear = true
                        }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
                .animation(.smooth(duration: 0.22), value: selected.isEmpty)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(AllergenPickerGroup.all.enumerated()), id: \.element.id) { index, group in
                            EditorialSheetSectionLabel(title: group.title)
                                .padding(.top, index == 0 ? 6 : 20)
                            groupCard(group)
                        }

                        Text("Laktoza to nietolerancja cukru mlecznego, mleko — alergia na jego białko.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.scFaint(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 6)
                            .padding(.top, 12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .containerRelativeFrame(.horizontal)
                }
                .scrollIndicators(.hidden)
                .scScrollEdgeFade()
                .scSheetFooter { footer }
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
        .alert("Wyczyścić alergeny?", isPresented: $confirmsClear) {
            Button("Anuluj", role: .cancel) {}
            Button("Wyczyść", role: .destructive) {
                withAnimation(.smooth(duration: 0.22)) { onClear() }
            }
        } message: {
            Text("Przepisy z tymi alergenami znów pokażą się na listach i w podpowiedziach.")
        }
    }

    private func groupCard(_ group: AllergenPickerGroup) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(group.allergens.enumerated()), id: \.element) { index, allergen in
                row(allergen, showsRule: index > 0)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.scTileStroke(scheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func row(_ allergen: Allergen, showsRule: Bool) -> some View {
        let isOn = selected.contains(allergen)
        let accent = allergen.pickerAccent

        return Button {
            withAnimation(.smooth(duration: 0.18)) { onToggle(allergen) }
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(scheme == .dark ? 0.18 : 0.12))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: allergen.pickerIcon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(accent)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(allergen.pickerTitle)
                        .font(.system(size: 15, weight: isOn ? .semibold : .medium))
                        .tracking(-0.25)
                        .foregroundStyle(Color.scLabel(scheme))
                    Text(allergen.pickerDetail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SCCheckbox(on: isOn, accent: SCPalette.terracotta, size: 22)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .overlay(alignment: .top) {
            if showsRule {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    .padding(.leading, 14 + 34 + 12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(allergen.title)
        .accessibilityValue(isOn ? "Zaznaczone" : "Niezaznaczone")
        .accessibilityHint(allergen.pickerDetail)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: selected.isEmpty
                     ? "Bez alergenów"
                     : "\(selected.count) \(PolishPlural.form(selected.count, one: "alergen", few: "alergeny", many: "alergenów"))")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.3)
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))
                    .contentTransition(.numericText(value: Double(selected.count)))

                if let hiddenRecipes, !selected.isEmpty {
                    Text(verbatim: hiddenRecipes == 0
                         ? "Żaden przepis ich nie zawiera"
                         : "ukrywa \(PolishPlural.recipes(hiddenRecipes))")
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                        .contentTransition(.numericText(value: Double(hiddenRecipes)))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.25), value: selected)
            .accessibilityElement(children: .combine)

            RecipeFilterFooterButton(title: "Gotowe", trailingIcon: nil) { dismiss() }
        }
        .padding(.leading, 4)
    }
}

// MARK: - Grupy i wygląd

/// Alergeny w trzech grupach, od najczęstszych. Wartość enuma, której tu
/// nie ma (nowszy serwer), trafia do „Pozostałe” — lepiej dodatkowa grupa
/// niż cicho zniknięty wiersz.
struct AllergenPickerGroup: Identifiable {
    let title: String
    let allergens: [Allergen]

    var id: String { title }

    static var all: [AllergenPickerGroup] {
        let known: [AllergenPickerGroup] = [
            AllergenPickerGroup(title: "Najczęstsze", allergens: [.gluten, .lactose, .milk, .eggs, .nuts, .peanuts]),
            AllergenPickerGroup(title: "Ryby i owoce morza", allergens: [.fish, .crustaceans, .molluscs]),
            AllergenPickerGroup(title: "Nasiona i dodatki", allergens: [.soy, .sesame, .celery, .mustard, .lupin, .sulphites])
        ]
        let listed = Set(known.flatMap(\.allergens))
        let rest = Allergen.allCases.filter { !listed.contains($0) }
        return rest.isEmpty ? known : known + [AllergenPickerGroup(title: "Pozostałe", allergens: rest)]
    }

    /// Kolejność z arkusza — tak samo stoją etykiety na karcie.
    static var ordered: [Allergen] { all.flatMap(\.allergens) }
}

extension Allergen {
    /// Glif przy alergenie. Tam, gdzie SF Symbols nie ma dosłownego rysunku,
    /// stoi skojarzenie: kłos (laur) przy glutenie, owal jajka, kapsuła
    /// orzeszka, kropki sezamu, kwiat łubinu.
    var pickerIcon: String {
        switch self {
        case .gluten:       return "laurel.leading"
        case .lactose:      return "drop.fill"
        case .milk:         return "cup.and.saucer.fill"
        case .eggs:         return "oval.portrait.fill"
        case .nuts:         return "tree.fill"
        case .peanuts:      return "capsule.portrait.fill"
        case .fish:         return "fish.fill"
        case .crustaceans:  return "fish"
        case .molluscs:     return "water.waves"
        case .soy:          return "leaf.circle.fill"
        case .sesame:       return "circle.grid.3x3.fill"
        case .celery:       return "carrot.fill"
        case .mustard:      return "flame.fill"
        case .lupin:        return "camera.macro"
        case .sulphites:    return "wineglass.fill"
        }
    }

    /// Barwa ikony — grupami: zboża i jaja masło, nabiał lawenda, orzechy
    /// ceglasta terakota, ryby morska, nasiona szałwia, dodatki róż.
    var pickerAccent: Color {
        switch self {
        case .gluten, .eggs, .mustard:        return SCPalette.butter
        case .lactose, .milk:                 return SCPalette.lavender
        case .nuts, .peanuts:                 return SCPalette.terracottaDeep
        case .fish, .crustaceans, .molluscs:  return SCPalette.teal
        case .soy, .sesame, .celery:          return SCPalette.sage
        case .lupin, .sulphites:              return SCPalette.rose
        }
    }
}
