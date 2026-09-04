import SwiftUI

// Wrapping chip layout used by Ustawienia → Dieta i alergeny. Each child
// is placed left-to-right; when the next chip won't fit on the current
// line, it wraps to a new one. Both axes use the same `spacing` value
// (matches the design's even gap).
//
// Built on the iOS 16+ `Layout` protocol so the whole flow is laid out
// in a single pass without intermediate `GeometryReader`s.
struct AllergenChipFlow: Layout {
    var spacing: CGFloat = 8
    /// `.trailing` dosuwa każdy wiersz do prawej krawędzi (podpowiedzi
    /// asystenta nad polem — jak dymki użytkownika).
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)

        let height = rows.reduce(into: CGFloat(0)) { acc, row in
            acc += row.height
        } + spacing * CGFloat(max(0, rows.count - 1))

        let width = rows
            .map(\.width)
            .max() ?? 0

        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x = alignment == .trailing ? bounds.maxX - row.width : bounds.minX
            for item in row.items {
                let size = item.size
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    // MARK: - Row computation

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]

        for (idx, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)

            // Width occupied if we append this chip to the current row
            // (existing width + spacing if it isn't the first chip + chip width).
            let appendedWidth = rows[rows.count - 1].items.isEmpty
                ? size.width
                : rows[rows.count - 1].width + spacing + size.width

            if appendedWidth > maxWidth, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }

            var current = rows[rows.count - 1]
            current.items.append((index: idx, size: size))
            current.width = current.items.isEmpty
                ? size.width
                : current.items.reduce(into: CGFloat(0)) { $0 += $1.size.width }
                    + spacing * CGFloat(max(0, current.items.count - 1))
            current.height = max(current.height, size.height)
            rows[rows.count - 1] = current
        }

        return rows
    }
}
