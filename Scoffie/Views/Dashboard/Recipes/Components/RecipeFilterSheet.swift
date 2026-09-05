import SwiftUI

// Arkusz „Filtry” otwierany z przycisku obok wyszukiwarki na Przepisach.
//
// Chassis jak w pozostałych arkuszach v2 (Ustawienia, Produkty): warstwa
// `SCPageBackground`, `EditorialSheetHeader` (eyebrow + tytuł + xmark),
// karty `scTileBg` z hairline'em `scTileStroke`, chipy w terakocie.
//
// Zmiany idą na kopię roboczą (`draft`) — dopiero „Pokaż przepisy” zapisuje
// je do bindingu widoku. Dzięki temu zamknięcie arkusza gestem nie zostawia
// listy w połowicznie przefiltrowanym stanie, a licznik w stopce może na
// żywo pokazywać, ile przepisów przetrwa wybór.
struct RecipeFilterSheet: View {
    @Binding var filters: RecipeFilterOptions

    /// Przepisy po zastosowaniu wyszukiwarki, ale PRZED filtrami — na nich
    /// liczony jest podgląd wyniku w stopce.
    let recipes: [Recipe]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var draft: RecipeFilterOptions

    init(filters: Binding<RecipeFilterOptions>, recipes: [Recipe]) {
        self._filters = filters
        self.recipes = recipes
        self._draft = State(initialValue: filters.wrappedValue)
    }

    private var matchCount: Int {
        draft.apply(to: recipes).count
    }

    var body: some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        EditorialSheetHeader(
                            eyebrow: "Filtry",
                            title: "Zawęź przepisy"
                        ) {
                            dismiss()
                        }

                        categorySection
                        difficultySection
                        prepTimeSection
                        caloriesSection
                        nutritionSection
                        favouritesSection
                        thermomixSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)

                footer
            }
        }
    }

    // MARK: - Sekcje

    private var categorySection: some View {
        section("Kategoria") {
            RecipeFilterChipFlow {
                ForEach(RecipeFilterOptions.selectableCategories) { category in
                    RecipeFilterChip(
                        title: RecipesConstants.displayName(for: category),
                        icon: RecipesConstants.icon(for: category),
                        accent: RecipeAccent.accent(for: category),
                        isSelected: draft.categories.contains(category)
                    ) {
                        withAnimation(.smooth(duration: 0.18)) {
                            draft.toggle(category: category)
                        }
                    }
                }
            }
        }
    }

    private var difficultySection: some View {
        section("Trudność") {
            RecipeFilterChipFlow {
                ForEach(Difficulty.allCases) { difficulty in
                    RecipeFilterChip(
                        title: difficulty.rawValue,
                        icon: RecipesConstants.icon(for: difficulty),
                        accent: RecipeAccent.accent(for: difficulty),
                        isSelected: draft.difficulties.contains(difficulty)
                    ) {
                        withAnimation(.smooth(duration: 0.18)) {
                            draft.toggle(difficulty: difficulty)
                        }
                    }
                }
            }
        }
    }

    private var prepTimeSection: some View {
        section("Czas przygotowania") {
            RecipeFilterChipFlow {
                ForEach(RecipeFilterOptions.prepTimeChoices, id: \.self) { minutes in
                    RecipeFilterChip(
                        title: "do \(minutes) min",
                        icon: "clock",
                        isSelected: draft.maxPrepTimeMinutes == minutes
                    ) {
                        withAnimation(.smooth(duration: 0.18)) {
                            draft.toggle(maxPrepTime: minutes)
                        }
                    }
                }

                RecipeFilterChip(
                    title: "Bez limitu",
                    isSelected: draft.maxPrepTimeMinutes == nil
                ) {
                    withAnimation(.smooth(duration: 0.18)) {
                        draft.maxPrepTimeMinutes = nil
                    }
                }
            }
        }
    }

    private var caloriesSection: some View {
        section("Kalorie na porcję") {
            VStack(alignment: .leading, spacing: 10) {
                RecipeFilterChipFlow {
                    ForEach(RecipeFilterOptions.calorieChoices, id: \.self) { kcal in
                        RecipeFilterChip(
                            title: "do \(kcal) kcal",
                            icon: "flame",
                            isSelected: draft.maxCaloriesPerServing == kcal
                        ) {
                            withAnimation(.smooth(duration: 0.18)) {
                                draft.toggle(maxCalories: kcal)
                            }
                        }
                    }

                    RecipeFilterChip(
                        title: "Bez limitu",
                        isSelected: draft.maxCaloriesPerServing == nil
                    ) {
                        withAnimation(.smooth(duration: 0.18)) {
                            draft.maxCaloriesPerServing = nil
                        }
                    }
                }

                if draft.maxCaloriesPerServing != nil {
                    Text("Przepisy bez policzonych makr zostają na liście.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.scFaint(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var nutritionSection: some View {
        section("Profil odżywczy") {
            VStack(alignment: .leading, spacing: 10) {
                RecipeFilterChipFlow {
                    ForEach(RecipeNutritionTag.allCases) { tag in
                        RecipeFilterChip(
                            title: tag.title,
                            icon: tag.icon,
                            accent: RecipeAccent.accent(for: tag),
                            isSelected: draft.nutritionTags.contains(tag)
                        ) {
                            withAnimation(.smooth(duration: 0.18)) {
                                draft.toggle(nutritionTag: tag)
                            }
                        }
                    }
                }

                if !draft.nutritionTags.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Na porcję: " + draft.orderedNutritionTags
                            .map(\.thresholdDescription)
                            .joined(separator: " · "))

                        Text("Przepisy bez policzonych makr nie wchodzą.")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.scFaint(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var favouritesSection: some View {
        section("Ulubione") {
            Button {
                withAnimation(.smooth(duration: 0.18)) {
                    draft.favouritesOnly.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: draft.favouritesOnly ? "heart.fill" : "heart")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SCPalette.terracotta)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.20 : 0.12)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tylko ulubione")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(Color.scLabel(scheme))

                        Text("Pokaż wyłącznie przepisy z serduszkiem")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.scMuted(scheme))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    RecipeFilterToggleIndicator(isOn: draft.favouritesOnly)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(draft.favouritesOnly ? [.isSelected, .isButton] : .isButton)
        }
    }

    private var thermomixSection: some View {
        section("Thermomix") {
            Button {
                withAnimation(.smooth(duration: 0.18)) {
                    draft.thermomixOnly.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "cooktop.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SCPalette.sage)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(SCPalette.sage.opacity(scheme == .dark ? 0.20 : 0.12)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tylko przepisy na Thermomix")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(Color.scLabel(scheme))

                        Text("Przepisy z odpowiednikiem w Cookidoo")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.scMuted(scheme))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    RecipeFilterToggleIndicator(isOn: draft.thermomixOnly)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(draft.thermomixOnly ? [.isSelected, .isButton] : .isButton)
        }
    }

    // MARK: - Stopka

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.smooth(duration: 0.18)) {
                    draft.reset()
                }
            } label: {
                Text("Wyczyść")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.1)
                    .foregroundStyle(draft.isActive ? Color.scLabel(scheme) : Color.scFaint(scheme))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.scChipBg(scheme)))
                    .overlay(Capsule().stroke(Color.scTileStroke(scheme), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!draft.isActive)

            Button {
                filters = draft
                dismiss()
            } label: {
                Text(applyTitle)
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.1)
                    .foregroundStyle(SCPalette.terracotta)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .scSoftCapsule()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(
            Rectangle()
                .fill(Color.scCanvas(scheme).opacity(0.94))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.scRule(scheme))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var applyTitle: String {
        switch matchCount {
        case 0:  return "Brak wyników"
        case 1:  return "Pokaż 1 przepis"
        default: return "Pokaż \(matchCount) \(Self.recipeNoun(for: matchCount))"
        }
    }

    /// Polska odmiana rzeczownika po liczebniku: 2–4 → „przepisy”,
    /// 12–14 i reszta → „przepisów”.
    private static func recipeNoun(for count: Int) -> String {
        let lastTwo = count % 100
        let last = count % 10
        if (2...4).contains(last), !(12...14).contains(lastTwo) { return "przepisy" }
        return "przepisów"
    }

    // MARK: - Chassis sekcji

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: title)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.scTileBg(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.scTileStroke(scheme), lineWidth: 1)
                )
        }
    }
}

// MARK: - Chip

// Zaznaczony chip dostaje pełny akcent (gradient + biały tekst), niezaznaczony
// siedzi na `scChipBg` — ten sam język co chipy alergenów w Ustawieniach.
struct RecipeFilterChip: View {
    let title: String
    var icon: String? = nil
    var accent: Color = SCPalette.terracotta
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.1)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : Color.scLabel(scheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    isSelected
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [accent, accent.mix(black: 0.18)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        : AnyShapeStyle(Color.scChipBg(scheme))
                )
            )
            .overlay(
                Capsule().stroke(
                    isSelected ? accent.opacity(0.35) : Color.scTileStroke(scheme),
                    lineWidth: 1
                )
            )
            .shadow(color: accent.opacity(isSelected ? 0.20 : 0), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Zawijający rząd chipów — ten sam `Layout` co chmura alergenów.
struct RecipeFilterChipFlow<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        AllergenChipFlow(spacing: spacing) {
            content()
        }
    }
}

/// Mały switch-look bez `Toggle` — cały wiersz jest przyciskiem, więc
/// natywny toggle łapałby gest jako drugi target.
struct RecipeFilterToggleIndicator: View {
    let isOn: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Capsule()
            .fill(isOn ? AnyShapeStyle(SCPalette.terracotta) : AnyShapeStyle(Color.scBarTrack(scheme)))
            .frame(width: 44, height: 26)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                    .padding(.horizontal, 3)
            }
            .animation(.smooth(duration: 0.18), value: isOn)
    }
}
