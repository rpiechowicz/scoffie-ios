import SwiftUI

/// Opcja kafla z ikoną (`SCIconTilePicker`).
struct SCIconTileChoice<Value: Hashable> {
    let value: Value
    let icon: String
    let title: String
    /// Kolor opcji: w spoczynku kółko w tincie, po wyborze pełne.
    let color: Color
    var accessibilityLabel: String? = nil
}

/// Wybór jednej z kilku opcji jako kafle z ikoną w kółku i krótkim podpisem —
/// treningi w tygodniu i płeć w „Twoich danych” (6.10.2026, artefakt „Arkusze
/// Ustawień”, wariant A „Kafle”). Każda opcja ma swój kolor: w spoczynku
/// kółko w tincie z glifem w tym kolorze, po wyborze pełne (głęboki wariant)
/// z białym glifem, podpis w kolorze opcji. Pod wybranym kaflem leży JEDNA
/// szklana soczewka w kolorze wyboru — jak w `RecipeFilterSegment` przepływa
/// sprężyną z „rozciągnięciem” (`LensSquish`), a ikona nowo wybranego podskakuje.
/// Bez podpisu z nazwą poziomu pod spodem (Rafał: „to lekko aktywny usuń”) —
/// ikona i kolor mówią wystarczająco.
///
/// Wybór, którego nie ma wśród opcji (kreator, 7.10.2026: `Value` opcjonalne
/// i `nil` = „jeszcze bez odpowiedzi”), nie zapala żadnego kafla ani soczewki.
struct SCIconTilePicker<Value: Hashable>: View {
    let choices: [SCIconTileChoice<Value>]
    @Binding var selection: Value

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Szerokość rzędu — z niej szerokość i miejsce soczewki.
    @State private var width: CGFloat = 0
    /// Licznik przeskoków soczewki — każdy gra jedno „rozciągnięcie”.
    @State private var squish = 0
    /// Podskoki ikon, licznik na kafel — podskakuje tylko nowo wybrany.
    @State private var hops: [Int: Int] = [:]

    private static var spacing: CGFloat { 6 }

    private var slide: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.74)
    }

    var body: some View {
        let count = max(choices.count, 1)
        // `nil` = wyboru nie ma wśród opcji — żaden kafel nie świeci.
        let matched = choices.firstIndex { $0.value == selection }
        let index = matched ?? 0
        let tileWidth = max(0, (width - Self.spacing * CGFloat(count - 1)) / CGFloat(count))
        let accent = choices.indices.contains(index) ? choices[index].color : SCPalette.terracotta

        HStack(spacing: Self.spacing) {
            ForEach(Array(choices.enumerated()), id: \.offset) { offset, choice in
                tile(choice, at: offset, isOn: offset == matched)
            }
        }
        .background(alignment: .leading) {
            // Soczewka — JEDNA, przesuwana, pod przyciskami i bez dotyku
            // (szkło w etykiecie przycisku łapało stuknięcia, patrz `scChromeGlass`).
            Color.clear
                .frame(width: tileWidth)
                .frame(maxHeight: .infinity)
                .scChromeGlass(
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                    tint: accent.opacity(scheme == .dark ? 0.32 : 0.2)
                )
                .keyframeAnimator(initialValue: LensSquish(), trigger: squish) { lens, frame in
                    lens.scaleEffect(x: frame.x, y: frame.y)
                } keyframes: { _ in
                    KeyframeTrack(\.x) {
                        MoveKeyframe(1)
                        CubicKeyframe(1.1, duration: 0.12)
                        CubicKeyframe(0.98, duration: 0.15)
                        CubicKeyframe(1, duration: 0.16)
                    }
                    KeyframeTrack(\.y) {
                        MoveKeyframe(1)
                        CubicKeyframe(0.9, duration: 0.12)
                        CubicKeyframe(1.03, duration: 0.15)
                        CubicKeyframe(1, duration: 0.16)
                    }
                }
                .offset(x: (tileWidth + Self.spacing) * CGFloat(index))
                .opacity(width > 0 && matched != nil ? 1 : 0)
                .allowsHitTesting(false)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .animation(slide, value: index)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func tile(_ choice: SCIconTileChoice<Value>, at offset: Int, isOn: Bool) -> some View {
        Button {
            guard choice.value != selection else { return }
            if !reduceMotion {
                squish += 1
                hops[offset, default: 0] += 1
            }
            selection = choice.value
        } label: {
            VStack(spacing: 8) {
                Image(systemName: choice.icon)
                    .font(.sc(size: 19, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : choice.color.opacity(0.85))
                    .frame(width: 44, height: 44)
                    .background {
                        Circle()
                            .fill(isOn ? choice.color : choice.color.opacity(scheme == .dark ? 0.16 : 0.12))
                            // Pełne kółko w GŁĘBOKIM wariancie, jak kafle wierszy
                            // (`EditorialSettingsTileIcon`) — na jasnym wariancie
                            // ciemnego motywu biały glif ginął.
                            .environment(\.colorScheme, isOn ? .light : scheme)
                    }
                    .symbolEffect(.bounce, value: hops[offset] ?? 0)

                Text(choice.title)
                    .font(.sc(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isOn ? choice.color : Color.scMuted(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .animation(.smooth(duration: 0.25), value: isOn)
        .accessibilityLabel(choice.accessibilityLabel ?? choice.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
