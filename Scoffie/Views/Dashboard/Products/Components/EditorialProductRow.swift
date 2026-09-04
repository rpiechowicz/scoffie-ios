import SwiftUI

// One product row inside an aisle card. Source: products.jsx → ProductRow.
//   Container — `padding: '11px 14px'`, hairline rule below (except last).
//   Check — circular 24pt, gradient sage when bought, ghost border otherwise.
//   Name  — 15pt 500 label color when active. Bought rows drop the
//           strikethrough (which combined with dim text destroyed
//           legibility) in favour of a quieter "read-only" look: muted
//           label color (60% opacity) at the same weight.
//   Amount pill — 4pt/10pt, 11.5pt 700 tracking 0.1, fontFeature `tnum`.
//                 colored bg/text when not bought, neutral when bought.
struct EditorialProductRow: View {
    let title: String
    let amount: String
    let bought: Bool
    let accent: Color
    let isLast: Bool
    var isDisabled: Bool = false
    var onToggle: () -> Void = {}

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: 12) {
                EditorialCheckCircle(on: bought, accent: accent)

                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .tracking(-0.2)
                    // Read-only "done" look — muted (60%) instead of faint
                    // (32%) + no strikethrough, so the product name stays
                    // readable on the cream canvas.
                    .foregroundStyle(bought ? Color.wmMuted(scheme) : Color.wmLabel(scheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                amountPill
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.72 : 1)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.wmRule(scheme))
                    .frame(height: 1)
                    .padding(.leading, 50)
            }
        }
    }

    private var amountPill: some View {
        Text(amount)
            .font(.system(size: 11.5, weight: .bold))
            .tracking(0.1)
            .monospacedDigit()
            .foregroundStyle(bought ? Color.wmMuted(scheme) : accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    bought
                    ? Color.wmTileBg(scheme)
                    : accent.opacity(scheme == .dark ? 0.20 : 0.12)
                )
            )
            .overlay(
                Capsule().stroke(
                    bought
                    ? Color.wmTileStroke(scheme)
                    : accent.opacity(scheme == .dark ? 0.42 : 0.32),
                    lineWidth: 1
                )
            )
            .fixedSize()
    }
}

// 24pt circle with a soft top-down accent fill + check glyph when on, hollow
// border when off. Mirrors `ProdCheck` from the design.
struct EditorialCheckCircle: View {
    let on: Bool
    var accent: Color = WMPalette.sage
    var size: CGFloat = 24

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if on {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.mix(black: 0.14)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Circle()
                    .stroke(accent.mix(black: 0.10), lineWidth: 1)

                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.42, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
            } else {
                Circle()
                    .stroke(Color.wmFaint(scheme), lineWidth: 1.6)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: on ? accent.opacity(0.40) : .clear, radius: 4, x: 0, y: 3)
        .animation(.easeInOut(duration: 0.16), value: on)
    }
}
