import SwiftUI

struct AuthView: View {
    let isLoading: Bool
    let errorMessage: String?
    let onSignInWithAppleTap: () -> Void

    var body: some View {
        // Ekran NIE przewija się — wszystko ma się zmieścić na jednym widoku.
        // Elastyczne są tylko dwie rzeczy: hero z kaflami (150–280 pt; dostaje
        // miejsce pierwszy, stąd `layoutPriority`) i odstęp nad przyciskiem.
        // Reszta ma stałą wysokość, więc na niskim ekranie kurczy się hero,
        // a nie treść; poniżej 700 pt kafle funkcji tracą jeszcze podpisy.
        GeometryReader { proxy in
            let compact = proxy.size.height < 700
            ZStack(alignment: .top) {
                AuthBackgroundView()

                VStack(spacing: 0) {
                    OnboardingHeroPattern()
                        .frame(minHeight: 150, maxHeight: 280)
                        .layoutPriority(1)

                    VStack(alignment: .leading, spacing: 0) {
                        AuthHeaderView()

                        AuthFeaturesView(compact: compact)
                            .padding(.top, compact ? 18 : 22)

                        Spacer(minLength: 14)

                        AuthActionsView(
                            isLoading: isLoading,
                            errorMessage: errorMessage,
                            onSignInWithAppleTap: onSignInWithAppleTap
                        )

                        AuthFooterView()
                            .padding(.top, 14)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .ignoresSafeArea(edges: .top)
            }
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
