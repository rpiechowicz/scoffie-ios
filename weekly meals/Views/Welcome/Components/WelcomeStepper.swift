import SwiftUI

// Pill-style step indicator. The current step's pill widens to 28pt while
// the others stay at 8pt; transitions are spring-eased so the indicator
// feels alive when the user moves between steps. Mirrors the
// design canvas (`components/welcome.jsx → WelcomeStepper`).
struct WelcomeStepper: View {
    let step: Int
    let total: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...total, id: \.self) { n in
                Capsule(style: .continuous)
                    .fill(fill(for: n))
                    .frame(width: width(for: n), height: 8)
                    .animation(
                        .spring(response: 0.42, dampingFraction: 0.82),
                        value: step
                    )
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Krok \(step) z \(total)")
    }

    private func width(for n: Int) -> CGFloat {
        n == step ? 28 : 8
    }

    private func fill(for n: Int) -> Color {
        let label = colorScheme == .dark
            ? WMPalette.labelDark
            : WMPalette.labelLight
        if n == step {
            return WMPalette.terracotta
        }
        if n < step {
            return label.opacity(0.5)
        }
        return label.opacity(colorScheme == .dark ? 0.14 : 0.12)
    }
}

#Preview("Dark") {
    VStack(spacing: 24) {
        WelcomeStepper(step: 1, total: 4)
        WelcomeStepper(step: 2, total: 4)
        WelcomeStepper(step: 3, total: 4)
        WelcomeStepper(step: 4, total: 4)
    }
    .padding()
    .background(WMPalette.canvasDark)
    .preferredColorScheme(.dark)
}

#Preview("Light") {
    VStack(spacing: 24) {
        WelcomeStepper(step: 1, total: 4)
        WelcomeStepper(step: 2, total: 4)
    }
    .padding()
    .background(WMPalette.canvasLight)
    .preferredColorScheme(.light)
}
