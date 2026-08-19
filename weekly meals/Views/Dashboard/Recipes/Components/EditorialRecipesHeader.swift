import SwiftUI

// Editorial top header on Przepisy v2 — W3 "Story carousel" variant.
// Source: design/Weekly Meals - Przepisy.html → recipes-v2.jsx RecipesV2_W3.
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
    var onSubmit: (() -> Void)? = nil
    var onOpenFilters: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @FocusState private var isSearchFocused: Bool

    private var hasActiveFilters: Bool { activeFilterCount > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            EditorialPageHeader("Przepisy")

            HStack(spacing: 10) {
                searchPill

                filterButton
            }
        }
    }

    // Przycisk filtra dzieli z pigułką te same `padding(.vertical, 12)` i
    // wysokość linii 16pt fonta, więc oba elementy kończą się dokładnie na
    // tej samej wysokości bez wpisywania sztywnego `frame`.
    private var filterButton: some View {
        Button {
            onOpenFilters?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 15, weight: .bold))

                if hasActiveFilters {
                    Text("\(activeFilterCount)")
                        .font(.system(size: 13, weight: .heavy))
                        .monospacedDigit()
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .foregroundStyle(hasActiveFilters ? .white : Color.wmLabel(scheme))
            .frame(minWidth: 20)
            .frame(height: 19)
            .padding(.horizontal, hasActiveFilters ? 14 : 13)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous).fill(
                    hasActiveFilters
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [WMPalette.terracotta, WMPalette.terracotta.mix(black: 0.18)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        : AnyShapeStyle(Color.wmTileBg(scheme))
                )
            )
            .overlay(
                Capsule(style: .continuous).stroke(
                    hasActiveFilters ? WMPalette.terracotta.opacity(0.35) : Color.wmTileStroke(scheme),
                    lineWidth: 1
                )
            )
            .shadow(color: WMPalette.terracotta.opacity(hasActiveFilters ? 0.24 : 0), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.2), value: hasActiveFilters)
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
                .foregroundStyle(Color.wmMuted(scheme).opacity(0.7))

            TextField(text: $searchText) {
                Text("Szukaj przepisów")
                    .foregroundStyle(Color.wmMuted(scheme).opacity(0.7))
            }
            .font(.system(size: 16))
            .tracking(-0.2)
            .foregroundStyle(Color.wmLabel(scheme))
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
                        .foregroundStyle(Color.wmMuted(scheme))
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
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
        .contentShape(Capsule(style: .continuous))
        .onTapGesture { isSearchFocused = true }
    }
}
