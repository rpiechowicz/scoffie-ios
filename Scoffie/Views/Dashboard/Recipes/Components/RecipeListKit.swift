import SwiftUI

// Klocki arkuszy z listą przepisów: lista kategorii (chevron przy sekcji na
// Przepisach) i wybór przepisu do planu („Wybierz przepis” w Planie).
//
// Oba arkusze stoją na tym samym (runda 8, 23.09.2026 — Rafał: „żeby
// wszystko trzymało się kupy, nie było nic, co jest odrębnie nowe”):
// `EditorialSheetHeader` z kafelkiem i podtytułem, `SCSearchField`, karta
// kontekstu, wiersze `EditorialRecipeRow`, pusty stan. Różni je tylko to, co
// robi wiersz — otwiera przepis albo go zaznacza — i stopka wyboru.
//
// Pigułek z opcjami filtrów pod szukaniem już nie ma (runda 10, Rafał:
// „usuń to szybkie wybieranie z chips — od tego mamy filtry”): zawężanie
// żyje w jednym miejscu, w arkuszu pod przyciskiem filtrów w nagłówku.

// MARK: - Góra arkusza

/// Przypięta góra arkusza z listą: nagłówek i szukanie. Jedne odstępy dla
/// obu arkuszy — lista kategorii i wybór do planu mają się zaczynać w tym
/// samym miejscu.
struct RecipeListSheetTop<Header: View>: View {
    let searchPrompt: String
    @Binding var searchText: String
    @ViewBuilder var header: () -> Header

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
                .padding(.horizontal, 20)

            SCSearchField(prompt: searchPrompt, text: $searchText)
                .padding(.horizontal, 20)
                .padding(.top, 16)
        }
        .padding(.top, 18)
        .padding(.bottom, 8)
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

/// Pusty stan listy w arkuszu — karta aplikacji: kafelek z ikoną powodu
/// w tincie akcentu, tytuł, jedno zdanie i akcja, która ten powód zdejmuje,
/// jako przycisk „soft” na całą szerokość; druga akcja — tekstem pod nim.
///
/// Ten sam układ, co karta pustego tygodnia w Planie i zaproszenie
/// w gospodarstwie (runda 10 — Rafał: „popraw to zgodnie z naszymi
/// standardami”). Wcześniej szara lupa nad tytułem i stos terakotowych
/// kapsułek, bez względu na to, co opróżniło listę.
struct RecipeListEmptyState: View {
    struct Action {
        let title: String
        var icon: String = "arrow.counterclockwise"
        let run: () -> Void
    }

    var icon: String = "magnifyingglass"
    var accent: Color = SCPalette.terracotta
    /// Etykieta nad tytułem w kolorze akcentu („LISTA ZAKUPÓW”) — tam, gdzie
    /// karta stoi na ekranie sama, bez nagłówka, który mówiłby, czego dotyczy.
    var eyebrow: String? = nil
    let title: String
    let message: String
    var actions: [Action] = []

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            SCHeaderIconWell(icon: icon, accent: accent, size: 52)

            if let eyebrow {
                Text(eyebrow)
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .padding(.top, 14)
            }

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(Color.scLabel(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, eyebrow == nil ? 14 : 4)

            Text(message)
                .font(.system(size: 13.5))
                .foregroundStyle(Color.scMuted(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            if let primary = actions.first {
                EditorialPrimaryActionButton(
                    title: primary.title,
                    icon: primary.icon,
                    action: primary.run
                )
                .padding(.top, 18)
            }

            ForEach(actions.dropFirst(), id: \.title) { action in
                Button(action: action.run) {
                    Text(action.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(SCPalette.terracotta)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlanPressStyle(scale: 0.97))
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .padding(.bottom, actions.isEmpty ? 26 : 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}
