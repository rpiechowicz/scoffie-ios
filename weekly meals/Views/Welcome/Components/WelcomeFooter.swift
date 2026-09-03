import SwiftUI

// Sticky footer for the welcome flow — pill stepper + back icon + primary
// action button, mirroring the tour footer so both flows feel alike. A two-band background (transparent → solid canvas)
// gives the scrolling step content a clean fade out before it reaches
// the button.
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
    /// „Wstecz" jako okrągła ikona po lewej od „Dalej" — ten sam układ, co
    /// w stopce przewodnika (`TourStepFooter`). Na pierwszym kroku nie ma
    /// dokąd wracać, więc przycisk znika.
    var showsBack: Bool = false
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

            // Wariant „soft" — ten sam przycisk, co w szczegółach przepisu
            // i w przewodniku. Pełny gradient z poświatą pod spodem był
            // jedynym takim akcentem w aplikacji: krzyczał na ekranie,
            // którego zadaniem jest spokojnie zebrać dane, i nie zgadzał
            // się z akcją, którą użytkownik zobaczy zaraz potem.
            HStack(spacing: 10) {
                if showsBack {
                    WMSoftIconButton(
                        systemName: "chevron.left",
                        accessibilityLabel: "Wstecz",
                        action: onBack
                    )
                }
                WMSoftButton(
                    title: nextLabel,
                    isEnabled: isNextEnabled,
                    isLoading: isLoading,
                    action: onNext
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        // 20 pt nad wskaźnikiem home, tyle samo co w stopce przewodnika
        // (`TourStepFooter`). Wcześniej było 48 i przycisk kreatora stał
        // wyraźnie wyżej niż ten sam przycisk na ekranie tuż przed nim.
        .padding(.bottom, 20)
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
    //      so the tinted capsule reads at its intended opacity instead of
    //      picking up whatever step content happens to sit behind it.
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
