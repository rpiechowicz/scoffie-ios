import SwiftUI

struct AuthView: View {
    let isLoading: Bool
    let errorMessage: String?
    let onSignInWithAppleTap: () -> Void

    var body: some View {
        // Layout zgodny z designem (B2 Cozy Kitchen). Hero 280pt sięga pod
        // status bar (ignoresSafeArea w hero). Content zajmuje resztę i spacerem
        // wypycha Apple+footer na dół — tak jak `marginBottom: auto` w designie.
        // ScrollView z `basedOnSize`: przy zwykłej czcionce nic się nie rusza,
        // a przy dużej Dynamic Type albo w poziomie przycisk logowania nie
        // ucieka poza ekran bez możliwości dotarcia.
        ZStack(alignment: .top) {
            AuthBackgroundView()

            ScrollView {
            VStack(spacing: 0) {
                OnboardingHeroPattern()

                VStack(alignment: .leading, spacing: 0) {
                    AuthHeaderView()

                    AuthFeaturesView()
                        .padding(.top, 24)

                    Spacer(minLength: 20)

                    AuthActionsView(
                        isLoading: isLoading,
                        errorMessage: errorMessage,
                        onSignInWithAppleTap: onSignInWithAppleTap
                    )
                        .padding(.top, 20)

                    AuthFooterView()
                        .padding(.top, 14)
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 36)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(minHeight: UIScreen.main.bounds.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
        }
    }
}

#Preview("Dark") {
    AuthView(isLoading: false, errorMessage: nil, onSignInWithAppleTap: {})
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    AuthView(isLoading: false, errorMessage: nil, onSignInWithAppleTap: {})
        .preferredColorScheme(.light)
}

#Preview("Loading") {
    AuthView(isLoading: true, errorMessage: nil, onSignInWithAppleTap: {})
        .preferredColorScheme(.dark)
}

#Preview("Error") {
    AuthView(
        isLoading: false,
        errorMessage: "Nie udało się zalogować. Spróbuj ponownie.",
        onSignInWithAppleTap: {}
    )
    .preferredColorScheme(.dark)
}
