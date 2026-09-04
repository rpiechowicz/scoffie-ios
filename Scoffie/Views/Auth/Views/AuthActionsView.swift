import SwiftUI

struct AuthActionsView: View {
    let isLoading: Bool
    let errorMessage: String?
    let onSignInWithAppleTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            // Custom polski przycisk Apple — native SignInWithAppleButton
            // lokalizuje się wg języka systemu, a chcemy zawsze „Zaloguj się
            // przez Apple". Spinner siedzi w środku przycisku zamiast tekstu
            // pod spodem, dzięki czemu layout nie podskakuje przy loading.
            Button(action: onSignInWithAppleTap) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(fgColor)
                            .controlSize(.small)
                    } else {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 18, weight: .medium))
                    }

                    Text(isLoading ? "Logowanie…" : "Zaloguj się przez Apple")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(fgColor)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(bgColor)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .opacity(isLoading ? 0.85 : 1)

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.85, green: 0.35, blue: 0.35))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // HIG: dark → biały przycisk z czarnym tekstem, light → odwrotnie.
    private var bgColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var fgColor: Color {
        colorScheme == .dark ? .black : .white
    }
}

#Preview("Dark") {
    AuthActionsView(isLoading: false, errorMessage: nil, onSignInWithAppleTap: {})
        .padding()
        .background(Color.wmCanvas(.dark))
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    AuthActionsView(isLoading: false, errorMessage: nil, onSignInWithAppleTap: {})
        .padding()
        .background(Color.wmCanvas(.light))
        .preferredColorScheme(.light)
}

#Preview("Loading") {
    AuthActionsView(isLoading: true, errorMessage: nil, onSignInWithAppleTap: {})
        .padding()
        .background(Color.wmCanvas(.dark))
        .preferredColorScheme(.dark)
}

#Preview("Error") {
    AuthActionsView(
        isLoading: false,
        errorMessage: "Nie udało się zalogować. Spróbuj ponownie.",
        onSignInWithAppleTap: {}
    )
    .padding()
    .background(Color.wmCanvas(.dark))
    .preferredColorScheme(.dark)
}
