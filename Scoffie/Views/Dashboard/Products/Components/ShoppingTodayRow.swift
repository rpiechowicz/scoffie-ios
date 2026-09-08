import SwiftUI

// Wiersz „Na dziś” — jedyna rzecz między paskiem postępu a alejkami.
//
// Źródło: canvas claude.ai → „Weekly Meals - Zakupy v2.html”
// (`components/shop-v2-final.jsx` → `ShopTodayToggle`).
//
// Odpowiada na pytanie, które w sklepie pada pierwsze: „czy mam to, z czego
// dziś gotuję?”. Stuknięcie otwiera arkusz „Na dziś” — pełne dzisiejsze dania
// z ich składnikami. Arkusz umie potem przełączyć listę w tryb filtra i wtedy
// ten sam wiersz jest drogą powrotną.
struct ShoppingTodayRow: View {
    /// Ile dzisiejszych produktów zostało do kupienia.
    let missing: Int
    /// Ilu dzisiejszych dań dotyczą te braki.
    let dishes: Int
    /// Lista jest właśnie zawężona do dzisiejszych produktów.
    let isFiltered: Bool
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var hasEverything: Bool { missing == 0 }
    private var accent: Color { hasEverything ? SCPalette.sage : SCPalette.terracotta }

    private var title: String {
        hasEverything ? "Na dziś masz wszystko" : "Na dziś brakuje \(PolishPlural.products(missing))"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: hasEverything ? "checkmark.circle.fill" : "clock")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .contentTransition(.symbolEffect(.replace))

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)
                    // Jedno zdanie w jednej linijce. Skala schodzi tylko na
                    // wąskich telefonach z dużą czcionką systemową — złamane
                    // na dwie linijki rozpychało wiersz i odklejało go od
                    // paska postępu nad nim.
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                trailing
            }
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isFiltered ? "Stuknij, aby wrócić do całej listy" : "Stuknij, aby zobaczyć dzisiejsze dania")
    }

    @ViewBuilder
    private var trailing: some View {
        if isFiltered {
            HStack(spacing: 5) {
                Text("Cała lista")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SCPalette.terracotta)
                    .lineLimit(1)
                    .fixedSize()

                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SCPalette.terracotta)
            }
        } else {
            HStack(spacing: 8) {
                if dishes > 0 && !hasEverything {
                    Text(PolishPlural.dishes(dishes))
                        .font(.system(size: 13, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                        .fixedSize()
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)
            }
        }
    }

    private var accessibilityLabel: Text {
        if isFiltered {
            return Text("\(title). Lista zawężona do dzisiejszych produktów")
        }
        if hasEverything {
            return Text(title)
        }
        return Text("\(title), \(PolishPlural.dishes(dishes))")
    }
}
