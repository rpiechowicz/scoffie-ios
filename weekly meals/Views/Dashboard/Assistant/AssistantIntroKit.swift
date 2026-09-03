import SwiftUI

// Klocki przepływu startowego asystenta (projekt „Asystent Powitanie",
// 3.09.2026): numeracja kroków pod wspólny `WelcomeStepper`, duża ikona AI
// z poświatą, wiersz i pigułka zaufania.

/// Numeracja kroków przepływu startowego pod wspólny `WelcomeStepper`
/// (ten sam pigułkowy wskaźnik, co w kreatorze „Poznajmy się" i w
/// przewodniku). Jeden ciąg: Zgoda → 6 kart „Poznaj" → „Co potrafi".
/// Hero (krok 0) wskaźnika nie ma — pojawia się, gdy user wszedł w proces.
enum AssistantIntroSteps {
    static let consent = 1
    static func card(_ index: Int) -> Int { 2 + index }
    static var capabilities: Int { total }
    static var total: Int { 2 + AssistantCapabilities.onboarding.count }
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
                    .foregroundStyle(Color.wmMuted(scheme))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if let trailingTitle, let onTrailing {
                Button(trailingTitle, action: onTrailing)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.wmMuted(scheme))
            }
        }
        .frame(minHeight: 22)
        .padding(.horizontal, WMPageMetrics.horizontal)
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
                        colors: [WMPalette.terracotta.opacity(0.30), WMPalette.terracotta.opacity(0.10), .clear],
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
                            .init(color: WMPalette.terracotta.opacity(0.30), location: 0),
                            .init(color: WMPalette.terracotta.opacity(0.10), location: 0.52),
                            .init(color: Color.wmLabel(scheme).opacity(0.04), location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .stroke(WMPalette.terracotta.opacity(0.34), lineWidth: 1)
                )
                .overlay(alignment: .top) {
                    // Cienki jasny „highlight" u góry, jak na przyciskach soft.
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .fill(.white.opacity(0.16))
                        .frame(height: 1.5)
                        .padding(.horizontal, size * 0.22)
                        .padding(.top, 1)
                }
                .shadow(color: WMPalette.terracotta.opacity(0.22), radius: 23, y: 20)
                .frame(width: size, height: size)

            Image(systemName: "sparkles")
                .font(.system(size: size * 0.5, weight: .light))
                .foregroundStyle(WMPalette.terracotta)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Mały ptaszek w zielonym kółku + jedno zdanie. Cztery takie na hero.
struct AssistantTickRow: View {
    let text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(Color.wmSageTint(scheme))
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(WMPalette.sage)
            }
            .frame(width: 17, height: 17)
            Text(text)
                .font(.system(size: 13.5))
                .tracking(-0.15)
                .foregroundStyle(Color.wmLabel(scheme))
        }
    }
}

/// Kapsuła zaufania pod haczykami hero.
struct AssistantTrustPill: View {
    let text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WMPalette.sage)
            Text(text)
                .font(.system(size: 12))
                .tracking(-0.1)
                .foregroundStyle(Color.wmLabel(scheme))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.wmSageTint(scheme)))
    }
}

/// Wiersz zaufania w tincie sage — na ekranie „Asystent gotowy".
struct AssistantTrustRow: View {
    var text = "Wzrost, waga, kroki i e-mail zostają w telefonie. Zgodę cofniesz w każdej chwili."

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WMPalette.sage)
            Text(text)
                .font(.system(size: 12.5))
                .tracking(-0.1)
                .lineSpacing(2)
                .foregroundStyle(Color.wmLabel(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.wmSageTint(scheme)))
    }
}

extension AnyTransition {
    /// Przejście między krokami przepływu startowego: nagłówek zakładki
    /// i tab bar stoją, wymienia się tylko treść (0,28 s, ease-out).
    static var assistantIntroStep: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 22).combined(with: .opacity),
            removal: .offset(y: -18).combined(with: .opacity)
        )
    }
}
