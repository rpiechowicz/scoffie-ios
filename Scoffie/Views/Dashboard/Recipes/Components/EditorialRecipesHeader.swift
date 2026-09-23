import SwiftUI

// Editorial top header on Przepisy v2 — W3 "Story carousel" variant.
// Source: design/Scoffie - Przepisy.html → recipes-v2.jsx RecipesV2_W3.
//   Outer block — `padding: '58px 20px 16px'` for the title row,
//   `0 20px 18px` for the search row.
//   Title — `EditorialPageHeader`, wspólny dla wszystkich zakładek.
//   Search — wspólne pole `SCSearchField` (kapsuła 44 pt, lupa, krzyżyk),
//   to samo, co w liście kategorii i w wyborze przepisu do planu.
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

    private var hasActiveFilters: Bool { activeFilterCount > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Bez różdżki dopasowania obok tytułu: przełącznik „Dopasowane
            // do Ciebie” stoi w Filtrach, a dwa wejścia do tej samej rzeczy
            // w odległości kciuka mówiły co innego (23.09.2026).
            EditorialPageHeader("Przepisy")

            HStack(spacing: 10) {
                // To samo pole, co w liście kategorii, w wyborze przepisu do
                // planu i w wykluczaniu składników (`SCSearchField`).
                SCSearchField(
                    prompt: "Szukaj przepisów",
                    text: $searchText,
                    onSubmit: { onSubmit?() }
                )

                filterButton
            }
        }
    }

    // Przycisk filtra ma wysokość pola szukania (`SCSearchField`, 44 pt),
    // więc oba elementy kończą się dokładnie na tej samej wysokości.
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
            .padding(.leading, hasActiveFilters ? 14 : 13)
            .padding(.trailing, hasActiveFilters ? 10 : 13)
            .frame(height: 44)
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
}
