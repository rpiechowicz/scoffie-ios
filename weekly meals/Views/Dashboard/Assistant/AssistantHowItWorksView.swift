import SwiftUI

/// Onboarding asystenta — 6 kart po włączeniu zgody, pokazywane raz w
/// zakładce; te same karty jako arkusz z menu ⋯ → „Jak działa asystent".
/// Podział po tym, co user ROBI: planuje → poprawia → dzieli na dom →
/// decyduje → kupuje i zapisuje przepisy → wie, ile ma.
struct AssistantHowItWorksView: View {
    enum Presentation { case inline, sheet }

    var presentation: Presentation = .inline
    /// „Zaczynajmy" / zamknięcie arkusza.
    let onFinish: () -> Void
    var onShowCapabilities: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var step = 0

    private let cards = AssistantCapabilities.onboarding
    private var isLast: Bool { step == cards.count - 1 }

    var body: some View {
        switch presentation {
        case .inline:
            content
        case .sheet:
            NavigationStack {
                content
                    .toolbar(.hidden, for: .navigationBar)
                    .background(WMPageBackground(scheme: scheme).ignoresSafeArea())
            }
            .presentationDragIndicator(.visible)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                if presentation == .sheet {
                    Text("Jak działa asystent")
                        .font(.system(size: 17, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(Color.wmLabel(scheme))
                }
                Spacer()
                Button(presentation == .sheet ? "Zamknij" : "Pomiń") {
                    finish()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.wmMuted(scheme))
            }
            .padding(.horizontal, WMPageMetrics.horizontal)
            .padding(.top, presentation == .sheet ? 18 : 0)
            .padding(.bottom, 6)

            TabView(selection: $step) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    ScrollView {
                        onboardingCard(card)
                            .padding(.horizontal, WMPageMetrics.horizontal)
                            .padding(.top, 6)
                            .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            AssistantStickyFooter {
                HStack(spacing: 6) {
                    ForEach(cards.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == step ? WMPalette.terracotta : Color.wmFaint(scheme))
                            .frame(width: index == step ? 18 : 6, height: 6)
                            .animation(.easeInOut(duration: 0.2), value: step)
                    }
                }
                .accessibilityLabel("Karta \(step + 1) z \(cards.count)")

                WMSoftButton(
                    title: isLast ? (presentation == .sheet ? "Zamknij" : "Zaczynajmy") : "Dalej",
                    trailingIcon: isLast ? nil : "chevron.right"
                ) {
                    if isLast { finish() } else { withAnimation { step += 1 } }
                }
            }
            .padding(.bottom, presentation == .sheet ? 12 : 0)
        }
    }

    private func onboardingCard(_ card: AssistantCapabilities.OnboardingCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AssistantIconTile(icon: card.icon, accent: card.accent, size: 52, radius: 15)

            VStack(alignment: .leading, spacing: 6) {
                Text(card.title)
                    .font(.system(size: 21, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.body)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundStyle(Color.wmMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let example = card.example {
                AssistantExampleBubble(text: example)
            }

            if let thumb = card.thumb {
                AssistantThumb(kind: thumb, weekDays: 3)
            }

            if card.showsPrivacy {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WMPalette.sage)
                    Text("Wzrost, waga, kroki i e-mail zostają w telefonie. Zgodę cofniesz w każdej chwili w menu.")
                        .font(.system(size: 12.5))
                        .lineSpacing(2)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.wmSageTint(scheme)))
            }

            if card.showsCapabilitiesLink, let onShowCapabilities {
                Button(action: onShowCapabilities) {
                    HStack(spacing: 4) {
                        Text("Zobacz wszystko, co potrafi")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(WMPalette.terracotta)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.wmTileBg(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.wmTileStroke(scheme), lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.06), radius: 12, y: 8)
    }

    private func finish() {
        onFinish()
        if presentation == .sheet { dismiss() }
    }
}
