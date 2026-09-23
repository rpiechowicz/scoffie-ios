import SwiftUI

/// Onboarding asystenta — karty po włączeniu zgody, pokazywane raz w
/// zakładce; te same karty jako arkusz z menu ⋯ → „Jak działa asystent".
/// Podział po tym, co user ROBI: planuje → poprawia → dzieli na dom →
/// kupuje i zapisuje przepisy.
///
/// Karta ma układ kroku przewodnika „Poznaj aplikację": ikona, tytuł,
/// opis, a pod nimi „zdjęcie" — tu podgląd prawdziwej wymiany z asystentem
/// (dymek, odpowiedź, karta). Bez pudełka wokół całości: ramka w ramce
/// (karta w karcie w kafelku) zjadała 44 pt szerokości i sprawiała, że
/// wszystko wyglądało na ściśnięte.
///
/// W zakładce stepper i przyciski są w `AssistantIntroFooter`, którą składa
/// `AssistantView` poza animowaną treścią; numer karty trzyma rodzic
/// (`step`), bo to on obsługuje „Dalej" i „Wstecz". Arkusz z menu ma
/// własną stopkę i własny licznik.
struct AssistantHowItWorksView: View {
    enum Presentation { case inline, sheet }

    var presentation: Presentation = .inline
    /// Numer karty od rodzica (w zakładce). `nil` = własny (arkusz).
    var step: Binding<Int>? = nil
    /// Ostatnia karta → dalej / zamknięcie arkusza.
    let onFinish: () -> Void
    /// „Pomiń" — kończy cały przepływ (domyślnie to samo, co `onFinish`).
    var onSkip: (() -> Void)? = nil
    /// Stuknięty przykład z karty — wysyłany jako wiadomość (arkusz sam
    /// się zamyka, w przepływie kończy onboarding).
    var onAsk: ((String) -> Void)? = nil
    var onShowCapabilities: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var localStep = 0

    private let cards = AssistantCapabilities.onboarding
    private var stepBinding: Binding<Int> { step ?? $localStep }
    private var currentStep: Int { stepBinding.wrappedValue }
    private var isLast: Bool { currentStep == cards.count - 1 }

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
                // Ten sam nagłówek, co w pozostałych arkuszach asystenta
                // (eyebrow · tytuł · podtytuł · X) — własny pasek z tekstowym
                // „Zamknij” wyglądał jak z innej aplikacji.
                AssistantSheetHeader(
                    title: "Jak działa asystent",
                    subtitle: "Cztery karty: co potrafi, jak wygląda odpowiedź i co zostaje w Twoich rękach.",
                    onClose: { finish() }
                )
                .padding(.bottom, 10)
            } else {
                AssistantIntroNavRow(
                    trailingTitle: "Pomiń",
                    onTrailing: { (onSkip ?? onFinish)() }
                )
            }

            TabView(selection: stepBinding) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    ScrollView {
                        onboardingCard(card)
                            .padding(.horizontal, SCPageMetrics.horizontal)
                            .padding(.top, 8)
                            // Zapas na cień stopki (`SCEdgeShade`): bez niego
                            // dolny przycisk miniatury albo odnośnik „Zobacz
                            // wszystko" siadały pod nim, gdy treść mieściła
                            // się w sam raz.
                            .padding(.bottom, SCEdgeShade.bottomHeight + 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if presentation == .sheet {
                AssistantIntroFooter(
                    slot: .stepper(step: currentStep + 1, total: cards.count),
                    // Jak w przewodniku: okrągła strzałka po lewej od „Dalej";
                    // w arkuszu tylko między kartami.
                    showsBack: currentStep > 0,
                    onBack: { withAnimation(.easeInOut(duration: 0.3)) { stepBinding.wrappedValue -= 1 } },
                    primaryTitle: isLast ? "Zamknij" : "Dalej",
                    primaryTrailingIcon: isLast ? nil : "chevron.right",
                    onPrimary: {
                        if isLast {
                            finish()
                        } else {
                            withAnimation(.easeInOut(duration: 0.3)) { stepBinding.wrappedValue += 1 }
                        }
                    }
                )
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: currentStep)
    }

    /// Dymek jest przyciskiem tylko wtedy, gdy ktoś odbiera wysłane zdanie.
    private func sendAction(for example: String) -> (() -> Void)? {
        guard let onAsk else { return nil }
        return {
            if presentation == .sheet { dismiss() }
            onAsk(example)
        }
    }

    private func onboardingCard(_ card: AssistantCapabilities.OnboardingCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AssistantIconTile(icon: card.icon, accent: card.accent, size: 48, radius: 14)
                .padding(.bottom, 16)

            Text(card.title)
                .font(.system(size: 27, weight: .bold))
                .tracking(-0.4)
                .lineSpacing(2)
                .foregroundStyle(Color.scLabel(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

            Text(card.body)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(Color.scMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)

            // „Zdjęcie" kroku: podgląd rozmowy wprost na stronie, tak jak
            // wygląda prawdziwa rozmowa. Dodatkowa powierzchnia pod spodem
            // zabierała miniaturze 28 pt szerokości i łamała jej nagłówek.
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
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SCPalette.sage)
                        .padding(.top, 1)
                    Text("Nic nie zapisuje się samo — każda zmiana to karta z „Dodaj do planu”, a zapis cofniesz w ciągu doby. Wzrost, waga, kroki i e-mail nie są wysyłane do modelu AI.")
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .foregroundStyle(Color.scLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.scSageTint(scheme)))
                .padding(.top, 16)
            }

            if card.showsCapabilitiesLink, let onShowCapabilities {
                Button(action: onShowCapabilities) {
                    HStack(spacing: 5) {
                        Text("Zobacz wszystko, co potrafi")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SCPalette.terracotta)
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func finish() {
        onFinish()
        if presentation == .sheet { dismiss() }
    }
}
