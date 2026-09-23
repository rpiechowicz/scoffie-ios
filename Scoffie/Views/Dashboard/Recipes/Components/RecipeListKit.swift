import SwiftUI

// Klocki arkuszy z listą przepisów: lista kategorii (chevron przy sekcji na
// Przepisach) i wybór przepisu do planu („Wybierz przepis” w Planie).
//
// Oba arkusze stoją na tym samym (runda 8, 23.09.2026 — Rafał: „żeby
// wszystko trzymało się kupy, nie było nic, co jest odrębnie nowe”):
// `EditorialSheetHeader` z kafelkiem i podtytułem, `SCSearchField`, pasek
// pigułek z filtrami kategorii, notka o zawężeniu, wiersze
// `EditorialRecipeRow`, pusty stan. Różni je tylko to, co robi wiersz —
// otwiera przepis albo go zaznacza — i stopka wyboru.

// MARK: - Góra arkusza

/// Przypięta góra arkusza z listą: nagłówek, szukanie i pasek pigułek.
/// Jedne odstępy dla obu arkuszy — lista kategorii i wybór do planu mają się
/// zaczynać w tym samym miejscu.
struct RecipeListSheetTop<Header: View, Pills: View>: View {
    let searchPrompt: String
    @Binding var searchText: String
    @ViewBuilder var header: () -> Header
    @ViewBuilder var pills: () -> Pills

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
                .padding(.horizontal, 20)

            SCSearchField(prompt: searchPrompt, text: $searchText)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            pills()
                .padding(.top, 10)
        }
        .padding(.top, 18)
        .padding(.bottom, 4)
    }
}

// MARK: - Przycisk filtrów w nagłówku

/// Krążek filtrów obok krzyżyka — glif jak na przycisku filtrów na
/// Przepisach. Zawężona lista świeci akcentem i nosi liczbę zaznaczonych opcji.
struct RecipeListFilterButton: View {
    let count: Int
    var accent: Color = SCPalette.terracotta
    let action: () -> Void

    var body: some View {
        SCSheetIconButton(
            systemName: "line.3.horizontal.decrease",
            tint: count > 0 ? accent : nil,
            accessibilityLabel: count > 0 ? "Filtry, zaznaczone: \(count)" : "Filtry",
            action: action
        )
        .scCountBadge(count, color: accent)
    }
}

// MARK: - Pigułki

/// Pigułka filtra — kształt i miary pigułki składnika (`RecipeExclusionPill`):
/// 36 pt, kapsuła na `scTileBg`. Włączona ma tło zaznaczonego chipa
/// (`scChoiceSurface`) i ptaszek — albo własny glif pigułki (serce
/// „Ulubionych”), już w kolorze akcentu.
struct RecipeFilterPill: View {
    let title: String
    var icon: String? = nil
    let isOn: Bool
    var accent: Color = SCPalette.terracotta
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    /// Licznik stuknięć — haptyka tylko za dotyk, nie za zmianę z arkusza
    /// filtrów, który zapisuje ten sam stan pod spodem.
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isOn ? accent : Color.scMuted(scheme))
                } else if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }

                Text(title)
                    .font(.system(size: 14.5, weight: isOn ? .semibold : .medium))
                    .tracking(-0.2)
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? accent : Color.scLabel(scheme))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .scChoiceSurface(
                Capsule(style: .continuous),
                isOn: isOn,
                accent: accent,
                offFill: Color.scTileBg(scheme)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .sensoryFeedback(.selection, trigger: taps)
        .animation(.smooth(duration: 0.2), value: isOn)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// Pasek pigułek pod szukaniem — opcje filtrów kategorii (te same, co
/// kafelki w `RecipeCategoryFilterSheet`, ten sam stan), grupy aspektów
/// rozdzielone cienką kreską. Pigułki to szybka droga: jedno stuknięcie
/// zamiast arkusza; arkusz pod przyciskiem w nagłówku pokazuje te same
/// opcje ze zdjęciem dania i liczbą przepisów.
///
/// `leading` to pigułki przed aspektami (w wyborze do planu: „Ulubione”
/// i „Wszystkie pory”).
struct RecipeFacetPillBar<Leading: View>: View {
    let facets: [RecipeFacet]
    @Binding var filter: RecipeCategoryFilter
    var accent: Color = SCPalette.terracotta
    @ViewBuilder var leading: () -> Leading

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                leading()

                ForEach(Array(facets.enumerated()), id: \.element.id) { index, facet in
                    if index > 0 || Leading.self != EmptyView.self {
                        separator
                    }

                    ForEach(facet.options) { option in
                        RecipeFilterPill(
                            title: option.title,
                            isOn: filter.contains(option.id, in: facet.kind),
                            accent: accent
                        ) {
                            withAnimation(.smooth(duration: 0.2)) {
                                filter.toggle(option.id, in: facet.kind)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            // Obwódka pigułki nie może być przycięta przez przewijany pasek.
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.scRule(scheme))
            .frame(width: 1, height: 18)
            .accessibilityHidden(true)
    }
}

extension RecipeFacetPillBar where Leading == EmptyView {
    init(facets: [RecipeFacet], filter: Binding<RecipeCategoryFilter>, accent: Color = SCPalette.terracotta) {
        self.init(facets: facets, filter: filter, accent: accent, leading: { EmptyView() })
    }
}

// MARK: - Karta kontekstu nad listą

/// Co zawęża listę spoza tego arkusza — dieta i alergeny z Ustawień, filtry
/// wszystkich przepisów — jako karta aplikacji (`scTileBg`): jeden wiersz na
/// przyczynę, kafelek w jej kolorze, nazwa i jedno zdanie szczegółu; filtry
/// zdejmuje „Wyczyść”.
///
/// Zastąpiła kolorowe pudełko z jednym zdaniem („Lista zawężona Twoją
/// dietą”) — Rafał (23.09.2026): „zrób to inaczej, ładniej, czytelniej”.
/// Pudełko mówiło tylko, ŻE coś zawęża, na tincie terakoty jak ostrzeżenie.
/// Karta mówi CO (dieta wegetariańska, bez glutenu) i ile przez to znika.
struct RecipeListContextCard: View {
    struct Row: Identifiable {
        let id: String
        let icon: String
        let accent: Color
        let title: String
        let detail: String
        var onClear: (() -> Void)? = nil
    }

    let rows: [Row]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(Color.scRule(scheme))
                        .frame(height: 1)
                        .padding(.leading, 14 + 32 + 12)
                }
                rowView(row)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 12) {
            SCHeaderIconWell(icon: row.icon, accent: row.accent, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)

                Text(row.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if let onClear = row.onClear {
                // Ten sam „Wyczyść”, co obok krzyżyka w arkuszach filtrów.
                RecipeFilterClearButton(accessibilityLabel: "Wyczyść filtry", action: onClear)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

extension RecipeListContextCard.Row {
    /// Dieta i alergeny z Ustawień: nazwa diety w jej kolorze, czego nie ma
    /// i ile przez to znika. `nil`, gdy dopasowanie nic nie ukrywa.
    ///
    /// Alergeny idą po „bez:” w mianowniku — „omijamy laktoza” kaleczyłoby
    /// biernik, a lista po dwukropku to zwykły spis.
    static func personalization(_ personalization: RecipePersonalization, hidden: Int) -> Self? {
        guard personalization.isEnabled, personalization.restrictsCatalog, hidden > 0 else { return nil }

        let allergens = Allergen.allCases
            .filter { personalization.avoidedAllergens.contains($0) }
            .map { $0.pickerTitle.lowercased() }
        // Dwa pierwsze z nazwy, reszta liczbą — pięć alergenów zjadało obie
        // linijki szczegółu i ucinało „ukrywa N przepisów”.
        let shown = allergens.prefix(2).joined(separator: ", ")
            + (allergens.count > 2 ? " +\(allergens.count - 2)" : "")
        let hiddenText = "ukrywa \(PolishPlural.recipes(hidden))"
        let diet = personalization.diet

        if diet != .none {
            var parts: [String] = []
            if !allergens.isEmpty { parts.append("bez: " + shown) }
            parts.append(hiddenText)
            return Self(
                id: "personalization",
                icon: diet.icon,
                accent: diet.accent,
                title: "Dieta \(diet.title.lowercased())",
                detail: parts.joined(separator: " · ")
            )
        }

        let count = allergens.count
        let noun = PolishPlural.form(count, one: "alergen", few: "alergeny", many: "alergenów")
        return Self(
            id: "personalization",
            icon: "exclamationmark.shield.fill",
            accent: SCPalette.terracotta,
            title: "Omijamy \(count) \(noun)",
            detail: shown + " · " + hiddenText
        )
    }

    /// Filtry wszystkich przepisów (arkusz „Filtry”): co działa i „Wyczyść”.
    static func filters(_ labels: [String], onClear: @escaping () -> Void) -> Self? {
        guard !labels.isEmpty else { return nil }
        return Self(
            id: "filters",
            icon: "line.3.horizontal.decrease",
            accent: SCPalette.terracotta,
            title: "Filtry z Przepisów",
            detail: labels.joined(separator: " · "),
            onClear: onClear
        )
    }
}

// MARK: - Wiersze

/// Wiersze przepisów z kreskami między nimi. Tryb decyduje o końcówce
/// wiersza: przeglądanie (strzałka, stuknięcie otwiera przepis) albo wybór
/// (kółko, stuknięcie zaznacza). Przy zaznaczonym wierszu kreski znikają —
/// jego tło samo go odcina.
struct RecipeRowStack: View {
    enum Mode: Equatable {
        case browse
        case select(UUID?)
    }

    let recipes: [Recipe]
    var mode: Mode = .browse
    var accent: Color = SCPalette.terracotta
    let onTap: (Recipe) -> Void

    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(recipes.enumerated()), id: \.element.id) { index, recipe in
                EditorialRecipeRow(
                    recipe: recipe,
                    accessory: accessory(for: recipe),
                    accent: accent,
                    action: { onTap(recipe) }
                )
                .task {
                    await recipeCatalogStore.loadNextPageIfNeeded(
                        currentItemId: recipe.id,
                        threshold: 8
                    )
                }

                if index < recipes.count - 1 {
                    Rectangle()
                        .fill(Color.scRule(scheme))
                        .frame(height: 1)
                        .padding(.leading, 20 + 48 + 14)
                        .padding(.trailing, 20)
                        .opacity(isSelected(recipe) || isSelected(recipes[index + 1]) ? 0 : 1)
                }
            }
        }
    }

    private func accessory(for recipe: Recipe) -> EditorialRecipeRow.Accessory {
        switch mode {
        case .browse:
            return .chevron
        case .select(let selectedId):
            return .selection(isOn: recipe.id == selectedId)
        }
    }

    private func isSelected(_ recipe: Recipe) -> Bool {
        mode == .select(recipe.id)
    }
}

// MARK: - Pusty stan

/// Pusty stan listy w arkuszu — karta z lupą, tytułem, zdaniem i akcjami,
/// które zdejmują to, co listę opróżniło („Wyczyść filtry”, „Pokaż przepisy
/// z innych pór”). Wcześniej lista kategorii i wybór do planu miały dwa
/// różne puste stany (karta z tytułem 16 pt i goły stos z tytułem 17 pt).
struct RecipeListEmptyState: View {
    struct Action {
        let title: String
        var tint: Color = SCPalette.terracotta
        let run: () -> Void
    }

    var icon: String = "magnifyingglass"
    let title: String
    let message: String
    var actions: [Action] = []

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.scMuted(scheme))
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 16, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(Color.scLabel(scheme))
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.scMuted(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !actions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(actions, id: \.title) { action in
                        Button(action: action.run) {
                            Text(action.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(action.tint)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .scSoftCapsule(action.tint)
                        }
                        .buttonStyle(PlanPressStyle(scale: 0.96))
                    }
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }
}
