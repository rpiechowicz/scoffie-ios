import SwiftUI

/// Asystent wyłączony na serwerze (503 `AI_DISABLED`, `AI_ENABLED=false`
/// na Railwayu) — przerwa techniczna, nie błąd.
///
/// Wersja A z 6.10.2026 („jak od Apple”, artefakt „Asystent na przerwie”):
/// pusty stan NA ŚRODKU wolnego miejsca, jak w aplikacjach Apple — znak
/// z kluczem w krążku, tytuł, jedno zdanie i szklany „Sprawdź ponownie”.
/// Pole wiadomości i licznik puli w nagłówku znikają na czas przerwy
/// (`AssistantView.showsMaintenance`); „…” zostaje (historia rozmów).
/// Dawna wersja (blok przy dolnej krawędzi, karta trzech kafli „Działa jak
/// zawsze”, które wyglądały na przyciski, a nic nie robiły) odpadła.
///
/// Ruch mówi tylko o zmianie — bez kaskady przy wejściu, ekran stoi od razu:
/// - znak oddycha, a klucz kiwa się co kilka sekund (tylko na otwartej
///   zakładce, przy „Ogranicz ruch” stoi);
/// - sprawdzanie = kręciołek w miejscu strzałki, przycisk nie zmienia szerokości;
/// - „jeszcze nie” = przycisk drgnie, haptyka ostrzeżenia i zdanie pod spodem;
/// - powrót (`isBack`) = klucz odpada, znak podskakuje, tytuł roluje się
///   na „Asystent wrócił”, a po chwili `AssistantView` przechodzi w powitanie
///   (`comebackHold`). Wyczerpana pula to INNY stan (`AssistantQuotaSpentCard`).
struct AssistantMaintenanceView: View {
    /// Trwa sprawdzanie — w przycisku kręciołek zamiast strzałki.
    let isChecking: Bool
    /// Asystent już wrócił: chwila „wrócił” przed powitaniem
    /// (`AssistantView.comebackHold`).
    var isBack: Bool = false
    /// `true` = asystent wrócił (ekran zniknie sam, bo `isUnavailable` spadło).
    let onRecheck: () async -> Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scTabIsActive) private var isActiveTab

    /// Ostatnie sprawdzenie nic nie dało — pod przyciskiem krótkie „jeszcze nie”.
    @State private var stillDown = false
    /// Nieudane sprawdzenia: haptyka ostrzeżenia i drgnięcie przycisku.
    @State private var checks = 0
    /// Podskok znaku przy powrocie (`SCLivingMark.cheer`).
    @State private var cheer = 0

    var body: some View {
        VStack(spacing: 0) {
            mark
                .padding(.bottom, 20)

            // Tytuł i zdanie ROLUJĄ się na powrót — ten sam ruch co każda
            // zmiana tekstu w aplikacji (`SCMotion.textRoll`).
            Text(isBack ? "Asystent wrócił" : "Asystent ma przerwę")
                .font(.sc(size: 24, weight: .heavy))
                .tracking(-0.6)
                .foregroundStyle(AssistantLook.ink(scheme))
                .multilineTextAlignment(.center)
                // „Ogranicz ruch”: samo przenikanie zamiast rolowania liter.
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .accessibilityAddTraits(.isHeader)

            Text(isBack ? "Możesz pisać." : "Wróci niedługo. Plan, przepisy i zakupy działają jak zawsze.")
                .font(.sc(size: 15.5))
                .tracking(-0.2)
                .lineSpacing(2)
                .foregroundStyle(AssistantLook.muted(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
                .contentTransition(.opacity)
                .padding(.top, 8)

            recheckButton
                .padding(.top, 22)
                .opacity(isBack ? 0 : 1)
                .disabled(isBack)
                .accessibilityHidden(isBack)

            Text("Jeszcze nie wrócił. Zajrzyj za kilka minut.")
                .font(.sc(size: 13.5))
                .foregroundStyle(AssistantLook.faint(scheme))
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .opacity(stillDown && !isBack ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: stillDown)
                .accessibilityHidden(!stillDown || isBack)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : SCMotion.textRoll, value: isBack)
        .sensoryFeedback(.warning, trigger: checks)
        .sensoryFeedback(trigger: isBack) { old, new in
            !old && new ? .success : nil
        }
        .onChange(of: isBack) { _, back in
            if back { cheer += 1 }
        }
    }

    // MARK: - Części

    /// Żywy znak w krążku w tincie terakoty, klucz w rogu — ta sama postać
    /// co w powitaniu, tylko „w warsztacie”. Krążek NIE jest szkłem: stoi
    /// w treści, a szkło jest tylko na tym, co pływa.
    private var mark: some View {
        SCLivingMark(
            mood: .idle,
            color: AssistantLook.terraFill(scheme),
            size: 44,
            cheer: cheer
        )
        .frame(width: 96, height: 96)
        .background(Circle().fill(AssistantLook.terraTint(scheme)))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.sc(size: 12, weight: .bold))
                .foregroundStyle(AssistantLook.terra(scheme))
                .symbolEffect(
                    .wiggle,
                    options: .repeat(.periodic(delay: 2.6)),
                    isActive: isActiveTab && !reduceMotion && !isBack
                )
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.scPageBase(scheme)))
                .overlay(Circle().stroke(AssistantLook.terraFill(scheme).opacity(0.35), lineWidth: 1))
                // Klucz odpada przy powrocie — skala z obrotem, potem krycie;
                // przy „Ogranicz ruch” samo krycie.
                .scaleEffect(isBack && !reduceMotion ? 0.01 : 1)
                .rotationEffect(.degrees(isBack && !reduceMotion ? -60 : 0))
                .opacity(isBack ? 0 : 1)
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeIn(duration: 0.25), value: isBack)
                .offset(x: -14, y: -14)
        }
        .accessibilityHidden(true)
    }

    /// Szklany przycisk w tincie terakoty („soft”), na szerokość treści.
    /// Drgnięcie po nieudanym sprawdzeniu gra keyframe'ami na liczniku
    /// `checks` — przy „Ogranicz ruch” zostaje sama haptyka i zdanie.
    private var recheckButton: some View {
        Button {
            Task {
                stillDown = false
                let back = await onRecheck()
                if !back {
                    stillDown = true
                    checks += 1
                }
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    if isChecking {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(AssistantLook.terra(scheme))
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.sc(size: 15, weight: .bold))
                    }
                }
                .frame(width: 20, height: 20)

                Text("Sprawdź ponownie")
                    .font(.sc(size: 16, weight: .semibold))
                    .tracking(-0.2)
                    .lineLimit(1)
            }
            .foregroundStyle(AssistantLook.terra(scheme))
            .padding(.leading, 18)
            .padding(.trailing, 22)
            .frame(height: 48)
            .scSoftCapsule(AssistantLook.terra(scheme))
            .contentShape(Capsule())
        }
        .buttonStyle(PlanPressStyle(scale: 0.97))
        .disabled(isChecking)
        .keyframeAnimator(initialValue: CGFloat.zero, trigger: reduceMotion ? 0 : checks) { content, offset in
            content.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(0)
                CubicKeyframe(-6, duration: 0.08)
                CubicKeyframe(5, duration: 0.1)
                CubicKeyframe(-3, duration: 0.1)
                CubicKeyframe(0, duration: 0.12)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isChecking)
    }
}

#Preview("Light") {
    ZStack {
        SCPageBackground(scheme: .light).ignoresSafeArea()
        AssistantMaintenanceView(isChecking: false, onRecheck: { false })
            .padding(.horizontal, SCPageMetrics.horizontal)
    }
    .preferredColorScheme(.light)
}

#Preview("Dark — wrócił") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()
        AssistantMaintenanceView(isChecking: false, isBack: true, onRecheck: { true })
            .padding(.horizontal, SCPageMetrics.horizontal)
    }
    .preferredColorScheme(.dark)
}
