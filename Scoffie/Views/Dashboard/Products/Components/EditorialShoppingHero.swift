import SwiftUI

// Hero "arc" variant for Produkty v2 — eyebrow + Kupione CTA + half-circle
// gauge with centered fraction + inline stats centered below.
//
// Source: products.jsx → HeroArc.
//   Outer wrap — `padding: '16px 16px 10px'`.
//   Card — `padding: '18px 16px 14px'`, `borderRadius: 22`. Background:
//          radial sage glow at top-center + flat warm tile below + 1px
//          inner highlight + drop shadow.
//   Header row (`marginBottom: 4`):
//     Eyebrow "LISTA ZAKUPÓW" — 10.5pt 700 tracking 1.4 sage uppercase.
//     `BuyAllButton` — gradient sage capsule (top sage@70%, bottom sage·#000@14%),
//                      icon `check` 13pt, "Kupione" 12.5pt 700.
//   Arc gauge — 200×100 svg, stroke 12, sage with `drop-shadow(0 0 6px sage@60%)`.
//     Centered overlay (top: 32, full width, column):
//       `X / Y` — 36pt heavy, tracking -1, faint "/" between numbers.
//       `Z% KUPIONE` — 10.5pt 700 tracking 1.4 muted uppercase, marginTop 4.
//   Footer — centered dots+counts (gap 18, marginTop 4): terracotta/sage bullets.
struct EditorialShoppingHero: View {
    let bought: Int
    let total: Int
    var subtitleOverride: String? = nil
    var primaryActionTitle: String = "Kupione"
    var primaryActionSystemImage: String = "checkmark"
    var isPrimaryActionDisabled: Bool = false
    var isPrimaryActionLoading: Bool = false
    var onPrimaryAction: () -> Void = {}

    @Environment(\.colorScheme) private var scheme

    // Geometry — design uses `size: 200, stroke: 12`. We make the
    // container slightly taller (130 vs design's 118) so the centered
    // fraction can sit lower without clipping the bottom percentage row.
    private let arcSize: CGFloat = 200
    private let arcStroke: CGFloat = 12
    private let arcContainerHeight: CGFloat = 130

    private var percent: Int {
        guard total > 0 else { return 0 }
        return Int((Double(bought) / Double(total) * 100).rounded())
    }

    private var remaining: Int { max(0, total - bought) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.bottom, 4)

            arcGauge
                .padding(.top, 8)

            footerStats
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(heroBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.12),
                radius: 18, x: 0, y: 12)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(subtitleOverride ?? "LISTA ZAKUPÓW")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(WMPalette.sage)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            buyAllButton
        }
    }

    private var buyAllButton: some View {
        // Resolved icon — kept as a single value so SwiftUI can hand the
        // change to `contentTransition(.symbolEffect(.replace))`, which
        // smoothly cross-fades SF Symbols rather than swapping in place.
        let iconName = isPrimaryActionLoading ? "hourglass" : primaryActionSystemImage

        return Button(action: onPrimaryAction) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))

                Text(primaryActionTitle)
                    .font(.system(size: 12.5, weight: .bold))
                    .tracking(-0.1)
                    .foregroundStyle(.white)
                    // Cross-fades title text on change ("Kupione" →
                    // "Zaznaczanie…" → "Zamknij") instead of an instant
                    // swap that would jolt the button width.
                    .contentTransition(.opacity)
                    .id(primaryActionTitle)
                    .transition(.opacity)
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                // Design: `color-mix(in oklch, sage, transparent 30%)` — sage @ 70% opacity.
                                WMPalette.sage.opacity(0.70),
                                // Design: `color-mix(in oklch, sage, #000 14%)` — sage darkened 14%.
                                WMPalette.sage.mix(black: 0.14)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            )
            .shadow(color: WMPalette.sage.opacity(0.28), radius: 6, x: 0, y: 4)
            .opacity(isPrimaryActionDisabled ? 0.45 : 1)
            // The HStack width animates with the title swap so the capsule
            // grows / shrinks smoothly between "Kupione" and "Zamknij"
            // instead of snapping to a new width mid-transition.
            .animation(.smooth(duration: 0.28), value: primaryActionTitle)
            .animation(.smooth(duration: 0.20), value: isPrimaryActionDisabled)
        }
        .buttonStyle(.plain)
        .disabled(isPrimaryActionDisabled)
    }

    // MARK: - Arc gauge (half-circle)

    private var arcGauge: some View {
        // ZStack(.top) anchors the arc to the container top; the centered
        // overlay is then pinned below the topmost point of the arc with
        // explicit `.padding(.top, …)`. Bumping that padding gives more
        // breathing room between the gauge and the fraction.
        ZStack(alignment: .top) {
            ArcShape(percent: 100)
                .stroke(Color.wmFaint(scheme).opacity(0.35),
                        style: StrokeStyle(lineWidth: arcStroke, lineCap: .round))

            ArcShape(percent: percent)
                .stroke(WMPalette.sage,
                        style: StrokeStyle(lineWidth: arcStroke, lineCap: .round))
                .shadow(color: WMPalette.sage.opacity(0.60), radius: 6, x: 0, y: 0)
                .animation(.easeInOut(duration: 0.32), value: percent)

            // Centered overlay — distance from the top of the gauge to the
            // top of the fraction. Numbers animate via `CountingNumber`
            // (same ramp as the kcal counter on Kalendarz v2).
            VStack(spacing: 6) {
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    CountingNumber(target: bought)
                        .font(.system(size: 36, weight: .heavy))
                        .tracking(-1.0)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .lineLimit(1)
                        .fixedSize()

                    Text("/")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(Color.wmFaint(scheme))

                    CountingNumber(target: total)
                        .font(.system(size: 36, weight: .heavy))
                        .tracking(-1.0)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .lineLimit(1)
                        .fixedSize()
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)

                HStack(spacing: 0) {
                    CountingNumber(target: percent)
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Color.wmMuted(scheme))

                    Text("% KUPIONE")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Color.wmMuted(scheme))
                }
            }
            .padding(.top, 50)
        }
        .frame(width: arcSize, height: arcContainerHeight)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footerStats: some View {
        HStack(spacing: 18) {
            statBullet(value: remaining, label: "do kupienia", color: WMPalette.terracotta)
            statBullet(value: bought, label: "kupione", color: WMPalette.sage)
        }
        .frame(maxWidth: .infinity)
    }

    private func statBullet(value: Int, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            CountingNumber(target: value)
                .font(.system(size: 13, weight: .bold))
                .tracking(-0.1)
                .foregroundStyle(Color.wmLabel(scheme))

            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.wmMuted(scheme))
                .lineLimit(1)
        }
    }

    // MARK: - Background

    private var heroBackground: some View {
        ZStack {
            // Base: warm tile gradient — same body as the bar variant.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.wmTileBg(scheme).opacity(scheme == .dark ? 1.4 : 1.0),
                            Color.wmTileBg(scheme).opacity(scheme == .dark ? 0.55 : 0.4)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Sage radial glow centered at the top — design's
            // `radial-gradient(100% 80% at 50% 0%, sage@20%, transparent 65%)`.
            RadialGradient(
                colors: [WMPalette.sage.opacity(scheme == .dark ? 0.18 : 0.12), .clear],
                center: UnitPoint(x: 0.5, y: 0.0),
                startRadius: 0,
                endRadius: 260
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            // 1px inner highlight at the top edge.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(scheme == .dark ? 0.06 : 0.20), lineWidth: 1)
                .blur(radius: 0.5)
                .mask(
                    LinearGradient(
                        colors: [.white, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}

// MARK: - Half-circle arc

/// Open arc that draws from the left baseline up and over to the right
/// baseline. `percent` is clamped to 0…100.
private struct ArcShape: Shape {
    var percent: Int

    var animatableData: Double {
        get { Double(percent) }
        set { percent = Int(newValue.rounded()) }
    }

    func path(in rect: CGRect) -> Path {
        let stroke: CGFloat = 12
        // Radius based on width — the half-circle's diameter spans the
        // full width of the rect, minus the stroke so the caps don't get
        // clipped.
        let radius = (rect.width - stroke) / 2
        // Anchor the arc to the TOP of the rect (the "baseline" of the
        // half-circle is at y = stroke/2 + radius). This leaves any
        // extra vertical room below the arc for centered text overlay.
        let center = CGPoint(x: rect.midX, y: stroke / 2 + radius)
        // SwiftUI 0° points right; the design's path starts at left
        // (180°) and sweeps clockwise to 0°. We map `percent` onto a
        // 0…180° travel along that sweep.
        let pct = max(0, min(100, percent))
        let startAngle = Angle.degrees(180)
        let endAngle = Angle.degrees(180 + Double(pct) / 100.0 * 180.0)

        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}

// MARK: - Color helpers (mix in linear sRGB)

extension Color {
    /// Interpolate against another color in linear sRGB. Mirrors the
    /// `color-mix(in oklch, …)` blends used in the design tokens.
    func mix(with other: Color, by fraction: CGFloat) -> Color {
        let f = max(0, min(1, fraction))

        let a = UIColor(self).cgColor.components ?? [0, 0, 0, 1]
        let b = UIColor(other).cgColor.components ?? [0, 0, 0, 1]

        let aR = a.count >= 3 ? a[0] : a[0]
        let aG = a.count >= 3 ? a[1] : a[0]
        let aB = a.count >= 3 ? a[2] : a[0]
        let bR = b.count >= 3 ? b[0] : b[0]
        let bG = b.count >= 3 ? b[1] : b[0]
        let bB = b.count >= 3 ? b[2] : b[0]

        return Color(
            red:   Double(aR + (bR - aR) * f),
            green: Double(aG + (bG - aG) * f),
            blue:  Double(aB + (bB - aB) * f)
        )
    }

    /// Convenience: blend toward black by `fraction`.
    func mix(black fraction: CGFloat) -> Color {
        self.mix(with: .black, by: fraction)
    }

    /// Convenience: blend toward white by `fraction`.
    func mix(white fraction: CGFloat) -> Color {
        self.mix(with: .white, by: fraction)
    }
}
