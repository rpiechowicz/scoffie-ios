import SwiftUI

// Klocki przepływu startowego asystenta (projekt „Asystent Powitanie",
// 3.09.2026): pasek kroków, duża ikona AI z poświatą, wiersz i pigułka
// zaufania. Hero (krok 0) nie ma paska — pasek pojawia się dopiero, gdy
// użytkownik faktycznie wszedł w proces: Zgoda → Poznaj → Start.

/// Trzy segmenty z numerem i etykietą kapitalikami. Aktywny jest szerszy
/// (1,35×) i pełny terracotta, zrobiony — przygaszony z ptaszkiem.
struct AssistantStepBar: View {
    let step: Int

    @Environment(\.colorScheme) private var scheme

    private static let steps = ["Zgoda", "Poznaj", "Start"]
    private static let activeWeight: CGFloat = 1.35
    private static let spacing: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let count = CGFloat(Self.steps.count)
            let free = proxy.size.width - Self.spacing * (count - 1)
            let unit = free / (count - 1 + Self.activeWeight)
            HStack(alignment: .top, spacing: Self.spacing) {
                ForEach(Self.steps.indices, id: \.self) { index in
                    segment(index)
                        .frame(width: unit * (index == step ? Self.activeWeight : 1))
                }
            }
        }
        .frame(height: 24)
        .padding(.horizontal, WMPageMetrics.horizontal)
        .padding(.top, 2)
        .padding(.bottom, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Krok \(step + 1) z \(Self.steps.count): \(Self.steps[min(step, Self.steps.count - 1)])")
    }

    private func segment(_ index: Int) -> some View {
        let done = index < step
        let on = index == step
        return VStack(alignment: .leading, spacing: 6) {
            Capsule()
                .fill(done || on ? WMPalette.terracotta : Color.wmBarTrack(scheme))
                .opacity(done ? 0.5 : 1)
                .frame(height: 3)
            HStack(spacing: 5) {
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(WMPalette.terracotta)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 10.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(on ? WMPalette.terracotta : Color.wmFaint(scheme))
                }
                Text(Self.steps[index])
                    .font(.system(size: 11, weight: on ? .bold : .semibold))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(on ? Color.wmLabel(scheme) : Color.wmFaint(scheme))
                    .lineLimit(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: step)
    }
}

/// Duża ikona AI: kafelek z gradientem terracotta, obrysem, cieniem
/// i poświatą pod spodem. Jedyny element w aplikacji, który wygląda jak
/// zaproszenie — dlatego tylko na hero.
struct AssistantAIMark: View {
    var size: CGFloat = 118

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [WMPalette.terracotta.opacity(0.30), WMPalette.terracotta.opacity(0.10), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.92
                    )
                )
                .frame(width: size * 1.84, height: size * 1.84)

            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: WMPalette.terracotta.opacity(0.30), location: 0),
                            .init(color: WMPalette.terracotta.opacity(0.10), location: 0.52),
                            .init(color: Color.wmLabel(scheme).opacity(0.04), location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .stroke(WMPalette.terracotta.opacity(0.34), lineWidth: 1)
                )
                .overlay(alignment: .top) {
                    // Cienki jasny „highlight" u góry, jak na przyciskach soft.
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .fill(.white.opacity(0.16))
                        .frame(height: 1.5)
                        .padding(.horizontal, size * 0.22)
                        .padding(.top, 1)
                }
                .shadow(color: WMPalette.terracotta.opacity(0.22), radius: 23, y: 20)
                .frame(width: size, height: size)

            Image(systemName: "sparkles")
                .font(.system(size: size * 0.5, weight: .light))
                .foregroundStyle(WMPalette.terracotta)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Mały ptaszek w zielonym kółku + jedno zdanie. Cztery takie na hero.
struct AssistantTickRow: View {
    let text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(Color.wmSageTint(scheme))
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(WMPalette.sage)
            }
            .frame(width: 17, height: 17)
            Text(text)
                .font(.system(size: 13.5))
                .tracking(-0.15)
                .foregroundStyle(Color.wmLabel(scheme))
        }
    }
}

/// Kapsuła zaufania pod haczykami hero.
struct AssistantTrustPill: View {
    let text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WMPalette.sage)
            Text(text)
                .font(.system(size: 12))
                .tracking(-0.1)
                .foregroundStyle(Color.wmLabel(scheme))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.wmSageTint(scheme)))
    }
}

/// Wiersz zaufania w tincie sage — na ekranie „Asystent gotowy".
struct AssistantTrustRow: View {
    var text = "Wzrost, waga, kroki i e-mail zostają w telefonie. Zgodę cofniesz w każdej chwili."

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WMPalette.sage)
            Text(text)
                .font(.system(size: 12.5))
                .tracking(-0.1)
                .lineSpacing(2)
                .foregroundStyle(Color.wmLabel(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.wmSageTint(scheme)))
    }
}

extension AnyTransition {
    /// Przejście między krokami przepływu startowego: nagłówek zakładki
    /// i tab bar stoją, wymienia się tylko treść (0,28 s, ease-out).
    static var assistantIntroStep: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 22).combined(with: .opacity),
            removal: .offset(y: -18).combined(with: .opacity)
        )
    }
}
