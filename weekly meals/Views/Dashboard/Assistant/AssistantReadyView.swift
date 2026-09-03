import SwiftUI

/// Krok 3 przepływu startowego — „Asystent gotowy". Zamyka pętlę: zamiast
/// pustego pola użytkownik dostaje jedno gotowe zdanie do wysłania i link
/// do limitów domu na wypadek pytania „ile mam wiadomości".
struct AssistantReadyView: View {
    /// „Napisz pierwszą wiadomość" — przejście do rozmowy z fokusem na polu.
    let onCompose: () -> Void
    /// Stuknięcie w gotowe zdanie — wysyła je jako pierwszą wiadomość.
    let onAsk: (String) -> Void
    var onShowLimits: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    private let firstStep = AssistantCapabilities.onboarding.first?.example
        ?? "Zaplanuj mi obiady i kolacje na ten tydzień, w tygodniu do 30 minut"

    var body: some View {
        VStack(spacing: 0) {
            AssistantStepBar(step: 2)

            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 0) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(Color.wmSageTint(scheme))
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(WMPalette.sage.opacity(0.3), lineWidth: 1)
                            Image(systemName: "checkmark")
                                .font(.system(size: 40, weight: .semibold))
                                .foregroundStyle(WMPalette.sage)
                        }
                        .frame(width: 84, height: 84)
                        .accessibilityHidden(true)

                        Text("Asystent gotowy")
                            .font(.system(size: 27, weight: .bold))
                            .tracking(-0.65)
                            .foregroundStyle(Color.wmLabel(scheme))
                            .padding(.top, 22)

                        Text("Zgoda zapisana. Zacznij od jednego zdania — resztę asystent dopyta.")
                            .font(.system(size: 14.5))
                            .tracking(-0.15)
                            .lineSpacing(3)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.wmMuted(scheme))
                            .frame(maxWidth: 290)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)

                    AssistantSurfaceCard {
                        AssistantSectionLabel(text: "Dobry pierwszy krok")
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                        AssistantExampleBubble(text: firstStep) {
                            onAsk(firstStep)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 9)
                        .padding(.bottom, 13)
                    }

                    AssistantTrustRow()
                }
                .padding(.horizontal, WMPageMetrics.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            AssistantStickyFooter {
                WMSoftButton(title: "Napisz pierwszą wiadomość", leadingIcon: "sparkles", action: onCompose)
                if let onShowLimits {
                    AssistantTextButton(title: "Zobacz limity domu", action: onShowLimits)
                }
            }
        }
    }
}
