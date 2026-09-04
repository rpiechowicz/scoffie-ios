import SwiftUI

/// Onboarding asystenta — 6 kart po włączeniu zgody, pokazywane raz w
/// zakładce; te same karty jako arkusz z menu ⋯ → „Jak działa asystent".
/// Podział po tym, co user ROBI: planuje → poprawia → dzieli na dom →
/// decyduje → kupuje i zapisuje przepisy → wie, ile ma.
struct AssistantHowItWorksView: View {
    enum Presentation { case inline, sheet }

    var presentation: Presentation = .inline
    /// Krok „Poznaj" przepływu startowego — wskaźnik liczy karty jako
    /// kroki 2–7 całego przepływu; jako arkusz z menu liczy tylko karty.
    var showsStepBar = false
    /// Karta, od której zacząć — powrót z „Co potrafi" ląduje na ostatniej.
    var startCard = 0
    /// Ostatnia karta → dalej („Zobacz, co potrafi") / zamknięcie arkusza.
    let onFinish: () -> Void
    /// „Pomiń" — kończy cały przepływ (domyślnie to samo, co `onFinish`).
    var onSkip: (() -> Void)? = nil
    /// „Wstecz" z pierwszej karty — do kroku „Zgoda".
    var onBack: (() -> Void)? = nil
    var onCardChange: ((Int) -> Void)? = nil
    /// Stuknięty przykład z karty — wysyłany jako wiadomość (arkusz sam
    /// się zamyka, w przepływie kończy onboarding).
    var onAsk: ((String) -> Void)? = nil
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
                    .background(SCPageBackground(scheme: scheme).ignoresSafeArea())
            }
            .presentationDragIndicator(.visible)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if presentation == .sheet {
                HStack {
                    Text("Jak działa asystent")
                        .font(.system(size: 17, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(Color.scLabel(scheme))
                    Spacer()
                    Button("Zamknij") { finish() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.scMuted(scheme))
                }
                .padding(.horizontal, SCPageMetrics.horizontal)
                .padding(.top, 18)
                .padding(.bottom, 6)
            } else {
                AssistantIntroNavRow(
                    trailingTitle: "Pomiń",
                    onTrailing: { (onSkip ?? onFinish)() }
                )
            }

            // Karta wypełnia całą wolną wysokość (a przewija się dopiero, gdy
            // treść jest wyższa) — mała karta na środku pustej sekcji
            // wyglądała jak dymek, nie jak ekran wprowadzenia.
            GeometryReader { proxy in
                TabView(selection: $step) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        ScrollView {
                            onboardingCard(card, minHeight: max(0, proxy.size.height - 18))
                                .padding(.horizontal, SCPageMetrics.horizontal)
                                .padding(.top, 6)
                                .padding(.bottom, 12)
                        }
                        .scrollIndicators(.hidden)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            AssistantStickyFooter {
                WelcomeStepper(
                    step: showsStepBar ? AssistantIntroSteps.card(step) : step + 1,
                    total: showsStepBar ? AssistantIntroSteps.total : cards.count
                )
                .padding(.bottom, 8)

                HStack(spacing: 10) {
                    // Jak w przewodniku: okrągła strzałka po lewej od „Dalej".
                    // W arkuszu z menu — tylko między kartami.
                    if presentation == .inline || step > 0 {
                        SCSoftIconButton(systemName: "chevron.left", accessibilityLabel: "Wstecz") { back() }
                    }
                    SCSoftButton(
                        title: isLast ? (presentation == .sheet ? "Zamknij" : "Zaczynajmy") : "Dalej",
                        trailingIcon: isLast ? nil : "chevron.right"
                    ) {
                        if isLast { finish() } else { withAnimation { step += 1 } }
                    }
                }
            }
        }
        .onAppear { step = min(max(0, startCard), cards.count - 1) }
        .onChange(of: step) { _, value in onCardChange?(value) }
    }

    /// Dymek jest przyciskiem tylko wtedy, gdy ktoś odbiera wysłane zdanie.
    private func sendAction(for example: String) -> (() -> Void)? {
        guard let onAsk else { return nil }
        return {
            if presentation == .sheet { dismiss() }
            onAsk(example)
        }
    }

    /// Karta wstecz; z pierwszej — do poprzedniego kroku przepływu.
    private func back() {
        if step > 0 {
            withAnimation { step -= 1 }
        } else {
            onBack?()
        }
    }

    private func onboardingCard(_ card: AssistantCapabilities.OnboardingCard, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            AssistantIconTile(icon: card.icon, accent: card.accent, size: 64, radius: 18)

            VStack(alignment: .leading, spacing: 8) {
                Text(card.title)
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Color.scLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.body)
                    .font(.system(size: 16))
                    .lineSpacing(4)
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let example = card.example {
                AssistantExchangePreview(
                    example: example,
                    reply: card.reply,
                    thumb: card.thumb,
                    weekDays: 5,
                    onSend: sendAction(for: example)
                )
            } else if let thumb = card.thumb {
                AssistantThumb(kind: thumb, weekDays: 5)
            }

            if card.showsPrivacy {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SCPalette.sage)
                    Text("Nic nie zapisuje się samo — każda zmiana to karta z „Dodaj do planu”, a zapis cofniesz w ciągu doby. Wzrost, waga, kroki i e-mail nie są wysyłane do modelu AI.")
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .foregroundStyle(Color.scLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.scSageTint(scheme)))
            }

            if card.showsCapabilitiesLink, let onShowCapabilities {
                Button(action: onShowCapabilities) {
                    HStack(spacing: 4) {
                        Text("Zobacz wszystko, co potrafi")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SCPalette.terracotta)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.scTileBg(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.scTileStroke(scheme), lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.06), radius: 12, y: 8)
    }

    private func finish() {
        onFinish()
        if presentation == .sheet { dismiss() }
    }
}
