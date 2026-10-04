import SwiftUI

/// Nagłówek wyników na Przepisach — JEDEN dla wyszukiwania i filtrów
/// (Rafał 4.10.2026: „stan filtrów oraz search byłby podobny, a może nawet
/// taki sam”). Zamiast karuzeli i sekcji: etykieta, duża liczba przepisów,
/// czego szukasz („makaron” · do 30 min · łatwe) i szklane „Wyczyść”, które
/// wraca do zwykłego widoku. Pod nim jedna płaska lista.
struct RecipeResultsHeader: View {
    let count: Int
    let query: String
    let filterLabels: [String]
    /// Wybrana zakładka kategorii („Obiady”) — staje w miejscu etykiety.
    var scopeTitle: String? = nil
    let onClear: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var eyebrow: String {
        if let scopeTitle { return scopeTitle }
        switch (query.isEmpty, filterLabels.isEmpty) {
        case (false, false): return "Wyniki z filtrami"
        case (false, true):  return "Wyniki wyszukiwania"
        default:             return "Twoje filtry"
        }
    }

    private var detail: String {
        var parts: [String] = []
        if !query.isEmpty { parts.append("„\(query)”") }
        parts.append(contentsOf: filterLabels)
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(SCPalette.terracotta)
                .lineLimit(1)
                .contentTransition(.opacity)

            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(verbatim: "\(count)")
                        .font(.system(size: 30, weight: .heavy))
                        .tracking(-0.6)
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(scheme))
                        .contentTransition(.numericText(value: Double(count)))

                    Text(PolishPlural.recipesNoun(count))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.scMuted(scheme))
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onClear) {
                    Text("Wyczyść")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.scLabel(scheme))
                        .padding(.horizontal, 15)
                        .frame(height: 34)
                        .scChromeGlass(in: Capsule(style: .continuous))
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(PlanPressStyle(scale: 0.94))
                .accessibilityHint("Wraca do wszystkich przepisów")
            }

            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(2)
                    .contentTransition(.opacity)
            }
        }
        .animation(SCMotion.textRoll, value: count)
        .animation(SCMotion.textRoll, value: detail)
        .accessibilityElement(children: .contain)
    }
}
