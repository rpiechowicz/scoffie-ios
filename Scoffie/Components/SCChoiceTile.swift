import SwiftUI

/// Stan kafelka wyboru. Osobny typ, a nie zagnieżdżony w `SCChoiceTile`:
/// typ zagnieżdżony w typie generycznym jest sam generyczny, więc
/// `SCChoiceTile<Text>.Mark` i `SCChoiceTile<Group<…>>.Mark` byłyby dla
/// kompilatora dwoma różnymi wyliczeniami.
enum SCChoiceMark: Equatable {
    case off
    case on
    /// Przyszło z profilu — kłódka w szałwii, stuknięcie nic nie robi.
    case locked
}

/// Kafelek wyboru w siatce 2 × N: pole wyboru, nazwa, pod nią jedna linijka
/// dopowiedzenia. Zaznaczony — tint i obwódka akcentu; zablokowany —
/// szałwia z kłódką.
///
/// Jeden rysunek dla wszystkich siatek wyboru wielokrotnego: kafelki „Dieta”
/// i „Cechy” w filtrach przepisów, alergeny w Ustawieniach i w kreatorze.
/// Zaznaczanie ma wyglądać i reagować tak samo niezależnie od ekranu —
/// dawniej alergeny były chmurą pigułek z pełną terakotą i cieniem, a filtry
/// kafelkami, czyli ten sam gest w dwóch różnych językach.
struct SCChoiceTile<Detail: View>: View {
    let title: String
    let mark: SCChoiceMark
    var accent: Color = SCPalette.terracotta
    /// Kafelek, który nic by nie dał (np. zero wyników) — gaśnie, ale zostaje
    /// na miejscu, żeby siatka nie przeskakiwała przy stuknięciu obok.
    var isDimmed: Bool = false
    /// Co VoiceOver czyta po nazwie. Dopowiedzenie z ekranu tu nie trafia
    /// samo, bo kafelek jest jednym elementem (`children: .ignore`).
    var accessibilityValue: String? = nil
    let action: () -> Void
    @ViewBuilder var detail: () -> Detail

    @Environment(\.colorScheme) private var scheme

    private var isActive: Bool { mark != .off }
    private var tint: Color { mark == .locked ? SCPalette.sage : accent }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                markView

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: isActive ? .semibold : .medium))
                        .tracking(-0.25)
                        .foregroundStyle(isActive ? tint : Color.scLabel(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    detail()
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Color.scFaint(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive ? tint.opacity(scheme == .dark ? 0.12 : 0.09) : Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        mark == .on ? tint.opacity(0.4) : (mark == .locked ? .clear : Color.scTileStroke(scheme)),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.97))
        .disabled(mark == .locked || isDimmed)
        .opacity(isDimmed ? 0.4 : 1)
        .animation(.smooth(duration: 0.18), value: mark)
        .animation(.smooth(duration: 0.18), value: isDimmed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(accessibilityValue ?? ""))
        .accessibilityAddTraits(mark == .off ? .isButton : [.isButton, .isSelected])
    }

    @ViewBuilder
    private var markView: some View {
        if mark == .locked {
            RoundedRectangle(cornerRadius: 20 / 3, style: .continuous)
                .fill(SCPalette.sage.opacity(scheme == .dark ? 0.22 : 0.16))
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SCPalette.sage)
                )
        } else {
            SCCheckbox(on: mark == .on, accent: accent, size: 20)
        }
    }
}
