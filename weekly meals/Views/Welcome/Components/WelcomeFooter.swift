import SwiftUI

// Sticky footer for the welcome flow — pill stepper + primary action
// button. The "Wstecz" affordance lives in the navigation toolbar
// (`topBarLeading`) so the footer stays visually focused on the single
// forward action and the terracotta button's shadow has nothing to bleed
// into. A two-band background (transparent → solid canvas) gives the
// scrolling step content a clean fade out before it reaches the button.
struct WelcomeFooter: View {
    let step: Int
    let total: Int
    let nextLabel: String
    let isNextEnabled: Bool
    let isLoading: Bool
    /// Hide the pill stepper for single-step modes (e.g. an already
    /// onboarded user landing only on the household-creation screen) —
    /// "4 of 4" doesn't make sense if the user never saw the others.
    var showsStepper: Bool = true
    let onBack: () -> Void
    let onNext: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var canvas: Color {
        Color.wmCanvas(colorScheme)
    }

    var body: some View {
        VStack(spacing: 18) {
            if showsStepper {
                WelcomeStepper(step: step, total: total)
            }

            ZStack(alignment: .bottom) {
                // Custom drop-glow — a blurred terracotta band positioned
                // BELOW the button. Replaces SwiftUI's `.shadow()` which
                // spreads in every direction (including up/sideways into
                // the diet rows above). Keeping it inside its own frame
                // means the glow can't escape past the button bounds.
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(WMPalette.terracotta.opacity(isNextEnabled ? 0.45 : 0))
                    .frame(height: 22)
                    .blur(radius: 14)
                    .padding(.horizontal, 18)
                    .offset(y: 14)
                    .allowsHitTesting(false)

                Button(action: onNext) {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text(nextLabel)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        WMPalette.terracotta.opacity(0.94),
                                        WMPalette.terracotta,
                                        WMPalette.terracottaDeep,
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
                    .opacity(isNextEnabled ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .disabled(!isNextEnabled || isLoading)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 22)
        // The inner `.ignoresSafeArea(edges: .bottom)` extends the canvas
        // band down through the home-indicator safe area, so scroll
        // content can't peek into that zone underneath the button.
        .background {
            footerBackground
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // Two-stack scrim:
    //   1. A 64pt fade (clear → canvas) sits ABOVE the footer's content
    //      so step rows fully fade out before they reach the stepper
    //      dots — no half-transparent text behind the indicator.
    //   2. A solid canvas slab covers the area under the stepper + button
    //      so the terracotta glow patch lands on opaque ground.
    private var footerBackground: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    canvas.opacity(0),
                    canvas.opacity(0.55),
                    canvas,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 64)
            canvas
        }
        .allowsHitTesting(false)
    }
}

#Preview("Step 1") {
    ZStack(alignment: .bottom) {
        WMPalette.canvasDark.ignoresSafeArea()
        WelcomeFooter(
            step: 1,
            total: 4,
            nextLabel: "Dalej",
            isNextEnabled: true,
            isLoading: false,
            onBack: {},
            onNext: {}
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Step 4 light") {
    ZStack(alignment: .bottom) {
        WMPalette.canvasLight.ignoresSafeArea()
        WelcomeFooter(
            step: 4,
            total: 4,
            nextLabel: "Utwórz gospodarstwo",
            isNextEnabled: true,
            isLoading: false,
            onBack: {},
            onNext: {}
        )
    }
    .preferredColorScheme(.light)
}
