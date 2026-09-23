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

// MARK: - Notka nad listą

/// Jedna linijka nad listą, gdy coś ją zawęża poza tym arkuszem — dieta
/// i alergeny (szałwia) albo filtry wszystkich przepisów (terakota,
/// z krzyżykiem, który je zdejmuje). Bez niej krótsza lista wygląda na brak
/// przepisów, a nie na skutek ustawienia z innego ekranu.
struct RecipeListNote: View {
    let icon: String
    let text: String
    var tint: Color = SCPalette.sage
    var onClear: (() -> Void)? = nil
    var clearLabel: String = "Wyczyść filtry"

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .accessibilityHidden(true)

            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .heavy))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(tint.opacity(scheme == .dark ? 0.22 : 0.14)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearLabel)
            }
        }
        .foregroundStyle(tint)
        .padding(.leading, 12)
        .padding(.trailing, onClear == nil ? 12 : 8)
        .padding(.vertical, onClear == nil ? 9 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(scheme == .dark ? 0.16 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
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
