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

    var onSubmit: (() -> Void)? = nil
    var onOpenFilters: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @FocusState private var isSearchFocused: Bool

    private var hasActiveFilters: Bool { activeFilterCount > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Bez różdżki dopasowania obok tytułu: przełącznik „Dopasowane
            // do Ciebie” stoi w Filtrach, a dwa wejścia do tej samej rzeczy
            // w odległości kciuka mówiły co innego (23.09.2026).
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
