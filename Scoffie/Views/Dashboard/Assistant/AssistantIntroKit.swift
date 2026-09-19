import SwiftUI

// Klocki przepływu startowego asystenta (projekt „Asystent Powitanie",
// 3.09.2026): numeracja kroków pod wspólny `WelcomeStepper`, duża ikona AI
// z poświatą, wiersz z haczykiem i JEDNA stopka na cały przepływ.
//
// Od 5.09.2026 przepływ ma tę samą mechanikę, co przewodnik „Poznaj
// aplikację" (`FeatureTourView`) i kreator „Poznajmy się": treść jeździ
// na bok zgodnie z kierunkiem ruchu, a stopka ze stepperem i przyciskami
// stoi w miejscu poza animowanym obszarem. Wcześniej każdy krok miał
// własną stopkę i całość przenikała się pionowo — przycisk główny
// mrugał i przesuwał się przy każdym „Dalej".

/// Numeracja kroków przepływu startowego pod wspólny `WelcomeStepper`
/// (ten sam pigułkowy wskaźnik, co w kreatorze „Poznajmy się" i w
/// przewodniku). Pięć kroków: Zgoda → 4 karty „Poznaj". Hero (krok 0)
/// wskaźnika nie ma — pojawia się, gdy user wszedł w proces.
enum AssistantIntroSteps {
    static let consent = 1
    static func card(_ index: Int) -> Int { 2 + index }
    static var total: Int { 1 + AssistantCapabilities.onboarding.count }
}

/// Flagi „widziane" przepływu startowego. Kasowane przy wylogowaniu
/// i usunięciu konta — nowy użytkownik na tym samym telefonie ma zobaczyć
/// hero i onboarding od nowa.
enum AssistantIntroState {
    static let welcomeSeenKey = "assistant.welcome.seen"
    static let onboardingSeenKey = "assistant.onboarding.seen"

    static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: welcomeSeenKey)
        defaults.removeObject(forKey: onboardingSeenKey)
    }
}

/// Stan zgody w trakcie wypełniania — POZA widokiem bramki, bo stopka
/// przepływu (`AssistantIntroFooter`) stoi poza animowaną treścią i musi
/// wiedzieć, czy oba potwierdzenia są zaznaczone, zanim odblokuje „Włącz
/// asystenta". Arkusz z menu trzyma własny egzemplarz.
struct AssistantConsentDraft: Equatable {
    var confirmsAge = false
    var confirmsData = false
    var errorMessage: String?
}

/// Wiersz nawigacji kroku: „Wstecz" po lewej, opcjonalnie „Pomiń" po
/// prawej. Kreator „Poznajmy się" ma „Wstecz" w pasku nawigacji; tu paska
/// nie ma (nagłówek zakładki), więc wiersz siedzi tuż pod nim.
struct AssistantIntroNavRow: View {
    var onBack: (() -> Void)? = nil
    var trailingTitle: String? = nil
    var onTrailing: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("Wstecz")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.scMuted(scheme))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if let trailingTitle, let onTrailing {
                Button(trailingTitle, action: onTrailing)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.scMuted(scheme))
            }
        }
        .frame(minHeight: 22)
        .padding(.horizontal, SCPageMetrics.horizontal)
        .padding(.bottom, 6)
    }
}

/// Duża ikona AI: kafelek z gradientem terracotta, obrysem, cieniem
/// i poświatą pod spodem. Jedyny element w aplikacji, który wygląda jak
/// zaproszenie — dlatego tylko na hero.
struct AssistantAIMark: View {
    var size: CGFloat = 118

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [SCPalette.terracotta.opacity(0.30), SCPalette.terracotta.opacity(0.10), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.92
                    )
                )
                .frame(width: size * 1.84, height: size * 1.84)

            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: SCPalette.terracotta.opacity(0.30), location: 0),
                            .init(color: SCPalette.terracotta.opacity(0.10), location: 0.52),
                            .init(color: Color.scLabel(scheme).opacity(0.04), location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .stroke(SCPalette.terracotta.opacity(0.34), lineWidth: 1)
                )
                // Bez jasnego „highlightu" pod górną krawędzią: 1,5-punktowa
                // kreska tuż pod obrysem czytała się jak podwójna ramka.
                .shadow(color: SCPalette.terracotta.opacity(0.22), radius: 23, y: 20)
                .frame(width: size, height: size)

            // Znak Scoffie, nie systemowe „sparkles": to ten sam glif, który
            // oddycha w wierszu tury i stoi nad briefingiem — asystent ma
            // jedną twarz na wszystkich ekranach.
            SCMarkShape()
                .fill(SCPalette.terracotta)
                .frame(width: size * 0.44, height: size * 0.44)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Ptaszek w zielonym kółku + jedno zdanie. Cztery takie na hero.
///
/// Kółko 22 pt i tekst 15 pt — wcześniej 17 pt i 13,5 pt, czyli drobniej
/// niż podpisy w przewodniku, choć to ten sam rodzaj listy. Nie większe:
/// cztery wiersze muszą się zmieścić nad stopką bez przewijania.
struct AssistantTickRow: View {
    let text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.scSageTint(scheme))
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(SCPalette.sage)
            }
            .frame(width: 22, height: 22)
            Text(text)
                .font(.system(size: 15))
                .tracking(-0.15)
                .foregroundStyle(Color.scLabel(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Jedna stopka na cały przepływ startowy — ten sam szkielet, co
/// `TourFooter` w przewodniku i `WelcomeFooter` w kreatorze: górne gniazdo
/// o stałej wysokości (stepper, odnośnik albo nic), pod nim rząd
/// przycisków. Wysokość nie zmienia się między krokami, więc przycisk
/// główny stoi w miejscu; zmienia się zawartość gniazda, tytuł
/// i obecność „Wstecz" — każde z własnym, cichym przejściem.
struct AssistantIntroFooter: View {
    enum Slot: Equatable {
        case link(String)
        case stepper(step: Int, total: Int)
        case empty

        /// Klucz przejścia gniazda: wszystkie kroki ze stepperem dzielą jedną
        /// instancję, więc pigułka przesuwa się sprężyście, zamiast wjeżdżać
        /// od nowa z każdą stroną.
        var key: Int {
            switch self {
            case .link: return 0
            case .stepper: return 1
            case .empty: return 2
            }
        }
    }

    let slot: Slot
    var onSlotTap: (() -> Void)? = nil
    /// Komunikat nad przyciskami — np. błąd zapisu zgody. Przy przyciskach,
    /// które go wywołały, a nie w treści, którą trzeba by przewinąć.
    var notice: String? = nil
    var showsBack = false
    var onBack: (() -> Void)? = nil
    let primaryTitle: String
    var primaryLeadingIcon: String? = nil
    var primaryTrailingIcon: String? = nil
    var isPrimaryEnabled = true
    var isPrimaryLoading = false
    var primaryHint: String? = nil
    let onPrimary: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AssistantStickyFooter {
            VStack(spacing: 18) {
                if let notice {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(notice)
                            .font(.system(size: 12.5, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(SCPalette.terracotta)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SCPalette.terracotta.opacity(0.12)))
                    .transition(.opacity)
                }

                ZStack {
                    slotContent
                        .id(slot.key)
                        .transition(.opacity)
                }
                .frame(maxWidth: .infinity)
                .frame(height: TourFooter.slotHeight)
                .animation(.easeInOut(duration: 0.34), value: slot.key)

                HStack(spacing: 10) {
                    if showsBack, let onBack {
                        SCSoftIconButton(
                            systemName: "chevron.left",
                            accessibilityLabel: "Wstecz",
                            action: onBack
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                    SCSoftButton(
                        title: primaryTitle,
                        leadingIcon: primaryLeadingIcon,
                        trailingIcon: primaryTrailingIcon,
                        isEnabled: isPrimaryEnabled,
                        isLoading: isPrimaryLoading,
                        action: onPrimary
                    )
                    .accessibilityHint(primaryHint ?? "")
                }
                .animation(.spring(response: 0.36, dampingFraction: 0.86), value: showsBack)
                .animation(.easeInOut(duration: 0.22), value: primaryTitle)
            }
            .animation(.easeInOut(duration: 0.2), value: notice)
        }
    }

    @ViewBuilder
    private var slotContent: some View {
        switch slot {
        case let .link(title):
            Button(action: { onSlotTap?() }) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .buttonStyle(.plain)
        case let .stepper(step, total):
            WelcomeStepper(step: step, total: total)
        case .empty:
            Color.clear
        }
    }
}

extension AnyTransition {
    /// Przejście przepływ startowy ↔ rozmowa: nagłówek zakładki i tab bar
    /// stoją, treść wymienia się pionowo (0,28 s, ease-out).
    static var assistantIntroStep: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 22).combined(with: .opacity),
            removal: .offset(y: -18).combined(with: .opacity)
        )
    }

    /// Przejście między krokami przepływu — jak w przewodniku i kreatorze:
    /// treść wjeżdża z krawędzi zgodnej z kierunkiem ruchu, poprzednia
    /// wyjeżdża w przeciwną.
    static func horizontalStep(direction: Int) -> AnyTransition {
        let slideIn: AnyTransition = direction >= 0
            ? .move(edge: .trailing).combined(with: .opacity)
            : .move(edge: .leading).combined(with: .opacity)
        let slideOut: AnyTransition = direction >= 0
            ? .move(edge: .leading).combined(with: .opacity)
            : .move(edge: .trailing).combined(with: .opacity)
        return .asymmetric(insertion: slideIn, removal: slideOut)
    }
}
