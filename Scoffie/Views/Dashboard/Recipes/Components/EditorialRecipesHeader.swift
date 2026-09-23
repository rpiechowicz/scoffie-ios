import SwiftUI

// Editorial top header on Przepisy v2 — W3 "Story carousel" variant.
// Source: design/Scoffie - Przepisy.html → recipes-v2.jsx RecipesV2_W3.
//   Outer block — `padding: '58px 20px 16px'` for the title row,
//   `0 20px 18px` for the search row.
//   Title — `EditorialPageHeader`, wspólny dla wszystkich zakładek.
//   Search — pill, `padding: 12px 14px 12px 16px`, rounded 99,
//   surface bg + line border + inset highlight. Magnifying glass icon
//   at 17pt with dim color; placeholder "Szukaj przepisów" at 16pt.
//
// Settings drops the "№ X · …" eyebrow because there's no week context to
// surface — same call here. The recipe list is a global library, not a
// per-week thing.
struct EditorialRecipesHeader: View {
    @Binding var searchText: String

    /// Liczba aktywnych grup filtrów — steruje plakietką na przycisku filtra.
    var activeFilterCount: Int = 0

    /// Stan dopasowania do preferencji — różdżka obok tytułu. Wszystkie
    /// domyślne, więc podglądy i inne wywołania zostają bez zmian.
    var isPersonalizationEnabled: Bool = true
    var isPersonalizationActive: Bool = false
    var hiddenRecipeCount: Int = 0

    var onSubmit: (() -> Void)? = nil
    var onOpenFilters: (() -> Void)? = nil
    var onOpenPersonalization: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @FocusState private var isSearchFocused: Bool

    private var hasActiveFilters: Bool { activeFilterCount > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            EditorialPageHeader(title: "Przepisy") {
                personalizationButton
            }

            HStack(spacing: 10) {
                searchPill

                filterButton
            }
        }
    }

    // Różdżka dopasowania — jedyna akcja w wierszu tytułu. Renderowana ZAWSZE,
    // również gdy nie ma żadnych preferencji: baner, który tu wcześniej był,
    // pojawiał się dopiero po ustawieniu czegoś w Ustawieniach, więc kto nic
    // nie ustawił, nigdy nie dowiadywał się, że funkcja istnieje — a kto
    // ustawił, dostawał kartę znikąd. Nagłówek nie może podskakiwać.
    private var personalizationButton: some View {
        EditorialIconButton(
            icon: "wand.and.stars",
            accent: SCPalette.sage,
            highlighted: isPersonalizationActive,
            // 43 pt, nie domyślne 38 — tyle mierzy pigułka filtra w rzędzie
            // niżej (19 pt treści + 2 × 12 pt paddingu). Przy 38 pt oba
            // przyciski wyglądały na dwa różne rozmiary tej samej rzeczy.
            size: 43,
            accessibilityTitle: isPersonalizationActive
                ? "Personalizacja przepisów, włączona"
                : "Personalizacja przepisów"
        ) {
            onOpenPersonalization?()
        }
        .overlay(alignment: .topTrailing) {
            if hiddenRecipeCount > 0 {
                Circle()
                    .fill(SCPalette.terracotta)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.scCanvas(scheme), lineWidth: 1.5))
                    .offset(x: 1, y: -1)
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.22), value: isPersonalizationActive)
        .animation(.smooth(duration: 0.22), value: hiddenRecipeCount > 0)
        // `EditorialIconButton` zaszywa `.accessibilityLabel(Text(icon))`,
        // czyli czyta „wand.and.stars”. Etykieta z zewnątrz wygrywa.
        .accessibilityLabel("Dopasowanie przepisów")
        .accessibilityValue(personalizationAccessibilityValue)
        .accessibilityHint("Otwiera wyjaśnienie i przełącznik")
    }

    private var personalizationAccessibilityValue: String {
        guard isPersonalizationEnabled else { return "Wyłączone" }
        guard isPersonalizationActive else { return "Włączone, brak preferencji" }
        guard hiddenRecipeCount > 0 else { return "Włączone" }
        return "Włączone, ukryto \(hiddenRecipeCount) \(RecipeCountNoun.label(for: hiddenRecipeCount))"
    }

    // Przycisk filtra dzieli z pigułką te same `padding(.vertical, 12)` i
    // wysokość linii 16pt fonta, więc oba elementy kończą się dokładnie na
    // tej samej wysokości bez wpisywania sztywnego `frame`.
    //
    // Włączone filtry to ten sam wariant „podświetlony”, co różdżka obok
    // (`SCCircleIconLabel(highlighted:)`): tint i obwódka akcentu, glif
    // w akcencie. Dawniej była tu pełna terakota z gradientem, białym glifem
    // i cieniem — jedyna taka plama koloru w nagłówkach aplikacji. Liczba
    // grup stoi w małej plakietce, jak liczniki w arkuszu filtrów.
    private var filterButton: some View {
        Button {
            onOpenFilters?()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 15, weight: .bold))

                if hasActiveFilters {
                    Text(verbatim: "\(activeFilterCount)")
                        .font(.system(size: 11.5, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(activeFilterCount)))
                        .frame(minWidth: 19, minHeight: 19)
                        .background(Capsule(style: .continuous).fill(SCPalette.terracotta))
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .foregroundStyle(hasActiveFilters ? SCPalette.terracotta : Color.scLabel(scheme))
            .frame(minWidth: 20)
            .frame(height: 19)
            .padding(.leading, hasActiveFilters ? 14 : 13)
            .padding(.trailing, hasActiveFilters ? 10 : 13)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(hasActiveFilters ? SCPalette.terracotta.opacity(0.20) : Color.scTileBg(scheme))
            )
            .overlay(
                Capsule(style: .continuous).stroke(
                    hasActiveFilters ? SCPalette.terracotta.opacity(0.40) : Color.scTileStroke(scheme),
                    lineWidth: 1
                )
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: hasActiveFilters)
        .animation(.easeOut(duration: 0.25), value: activeFilterCount)
        .accessibilityLabel(
            hasActiveFilters
                ? "Filtry, aktywne: \(activeFilterCount)"
                : "Filtry"
        )
    }

    private var searchPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.scMuted(scheme).opacity(0.7))

            TextField(text: $searchText) {
                Text("Szukaj przepisów")
                    .foregroundStyle(Color.scMuted(scheme).opacity(0.7))
            }
            .font(.system(size: 16))
            .tracking(-0.2)
            .foregroundStyle(Color.scLabel(scheme))
            .focused($isSearchFocused)
            .submitLabel(.search)
            .onSubmit { onSubmit?() }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.scMuted(scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wyczyść wyszukiwanie")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
        .contentShape(Capsule(style: .continuous))
        .onTapGesture { isSearchFocused = true }
    }
}
