import SwiftUI

// One aisle on Produkty v2 — editorial folio + label + tiny progress rod above
// a stacked card of `EditorialProductRow`s. Source: products.jsx → AisleSection.
//
// Header row (`marginBottom: 12`, gap 12, alignItems: 'flex-end'):
//   Folio number — 44pt heavy italic, color = aisle accent w/ 35% transparent.
//                  Tracking -1.5, lineHeight 42pt, fontFeature 'tnum'.
//   Label column:
//     Icon + UPPERCASE label — 13pt icon, 10.5pt 700 tracking 1.4, accent.
//     "X/Y kupione · Z%" sub-line — 14pt 600 tracking -0.2, label / muted.
//   Tiny progress rod — 52×5 capsule, accent → accent+10% white.
//
// Body — rounded 18pt card with `WARM.card`/border + inner top hairline.
struct EditorialAisleSection: View {
    let index: Int
    let title: String
    let icon: String
    let accent: Color
    let bought: Int
    let total: Int
    let items: [Item]
    var disableTaps: Bool = false
    var onToggle: ((Item) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    struct Item: Identifiable, Hashable {
        let id: String
        let name: String
        let amount: String
        let bought: Bool
    }

    private var percent: Int {
        guard total > 0 else { return 0 }
        return Int((Double(bought) / Double(total) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    EditorialProductRow(
                        title: item.name,
                        amount: item.amount,
                        bought: item.bought,
                        accent: accent,
                        isLast: idx == items.count - 1,
                        isDisabled: disableTaps,
                        onToggle: { onToggle?(item) }
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.wmTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: - Header
    //
    // Three columns:
    //   1. Big italic folio number ("07") — accent at 65% opacity.
    //   2. Icon + UPPERCASE label only (no count line below) — flexible width.
    //   3. Stacked stat — "X/Y · Z%" caption sitting ABOVE the progress rod.
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(folioNumber)
                .font(.system(size: 44, weight: .heavy))
                .italic()
                .tracking(-1.5)
                .foregroundStyle(accent.opacity(scheme == .dark ? 0.65 : 0.55))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()

            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(accent)

                Text(title.uppercased())
                    .font(.system(size: 15, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Stat column — count line on top, progress rod below it.
            // `fixedSize` keeps the column tight (no horizontal stretching);
            // numbers animate via `CountingNumber` (same load-ramp + smooth
            // recount on change as Kalendarz's kcal counter).
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 0) {
                    CountingNumber(target: bought)
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(-0.2)
                        .foregroundStyle(Color.wmLabel(scheme))

                    Text("/")
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(-0.2)
                        .foregroundStyle(Color.wmLabel(scheme))

                    CountingNumber(target: total)
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(-0.2)
                        .foregroundStyle(Color.wmLabel(scheme))

                    Text(verbatim: " · ")
                        .font(.system(size: 12, weight: .medium))
                        .tracking(-0.2)
                        .foregroundStyle(Color.wmMuted(scheme))

                    CountingNumber(target: percent)
                        .font(.system(size: 12, weight: .medium))
                        .tracking(-0.2)
                        .foregroundStyle(Color.wmMuted(scheme))

                    Text("%")
                        .font(.system(size: 12, weight: .medium))
                        .tracking(-0.2)
                        .foregroundStyle(Color.wmMuted(scheme))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.wmBarTrack(scheme))
                        .frame(width: 64, height: 5)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.mix(white: 0.10)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 64 * CGFloat(percent) / 100, height: 5)
                        .animation(.easeInOut(duration: 0.32), value: bought)
                }
            }
            .fixedSize()
        }
    }

    private var folioNumber: String {
        index < 10 ? String(format: "0%d", index) : "\(index)"
    }
}
