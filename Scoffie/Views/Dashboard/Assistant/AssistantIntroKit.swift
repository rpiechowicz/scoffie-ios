import SwiftUI

// Klocki przepływu startowego asystenta (projekt „Asystent Powitanie",
// 3.09.2026): numeracja kroków, znak asystenta, wiersz „Pomiń” i JEDNA
// stopka na cały przepływ.
//
// Od 5.09.2026 przepływ ma tę samą mechanikę, co przewodnik „Poznaj
// aplikację" (`FeatureTourView`) i kreator „Poznajmy się": treść jeździ
// na bok zgodnie z kierunkiem ruchu, a stopka z paskiem kroków i przyciskami
// stoi w miejscu poza animowanym obszarem. Od 23.09.2026 także te same
// KLOCKI (`Components/SCStepFlow.swift`): pasek kroków, stopka na
// `SCSheetFooter` z cieniem krawędzi, nagłówek i karta funkcji — Rafał:
// „użyj steppera z naszym shadow, aby było wszystko zgodne ze sobą”.

/// Numeracja kroków przepływu startowego pod wspólny pasek kroków
/// (`SCStepProgress`, ten sam co w kreatorze „Poznajmy się" i w
/// przewodniku). Pięć kroków: Zgoda → 4 karty „Poznaj". Hero (krok 0)
/// paska nie ma — pojawia się, gdy user wszedł w proces.
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

/// Wiersz nad kartami „Poznaj”: opcjonalnie „Wstecz” po lewej, „Pomiń” po
/// prawej. Oba jako kontrolki aplikacji — krążek jak krzyżyk arkusza
/// (`SCSheetIconButton`) i neutralna kapsuła tej samej wysokości — a nie
/// goły szary tekst, który czytał się jak podpis, a nie przycisk.
struct AssistantIntroNavRow: View {
    var onBack: (() -> Void)? = nil
    var trailingTitle: String? = nil
    var onTrailing: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack {
            if let onBack {
                SCSheetIconButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Wstecz",
                    action: onBack
                )
            }
            Spacer()
            if let trailingTitle, let onTrailing {
                Button(action: onTrailing) {
                    Text(trailingTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Color.scMuted(scheme))
                        .padding(.horizontal, 14)
                        .frame(height: SCStepFooter.rowHeight)
                        .background(Capsule(style: .continuous).fill(Color.scChipBg(scheme)))
                        .overlay(Capsule(style: .continuous).stroke(Color.scTileStroke(scheme), lineWidth: 1))
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(PlanPressStyle(scale: 0.94))
            }
        }
        .frame(minHeight: SCStepFooter.rowHeight)
        .padding(.horizontal, SCPageMetrics.horizontal)
        .padding(.bottom, 6)
    }
}

/// Znak asystenta na powitaniu: znak Scoffie w kafelku w tincie terakoty —
/// ten sam rozmiar i miejsce, co logo na powitaniu przewodnika.
///
/// Do 23.09.2026 był to kafel 100 pt z gradientem, cieniem i poświatą
/// 1,84× — jedyny taki akcent w przepływie, który teraz stoi na wspólnych
/// klockach i kartach bez cienia.
struct AssistantAIMark: View {
    var size: CGFloat = 56

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.16 : 0.12))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(SCPalette.terracotta.opacity(0.34), lineWidth: 1)
            )
            // Znak Scoffie, nie systemowe „sparkles": to ten sam glif, który
            // oddycha w wierszu tury i stoi nad briefingiem — asystent ma
            // jedną twarz na wszystkich ekranach.
            .overlay(
                SCMarkShape()
                    .fill(SCPalette.terracotta)
                    .frame(width: size * 0.46, height: size * 0.46)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Jedna stopka na cały przepływ startowy — nakładka na wspólną stopkę
/// kroków (`SCStepFooter`): płyta `SCSheetFooter` z cieniem krawędzi, wiersz
/// z „Wstecz”, paskiem kroków i licznikiem, pod nim akcja główna na całą
/// szerokość. Wysokość nie zmienia się między krokami, więc przycisk
/// główny stoi w miejscu.
///
/// API zostaje po staremu (`AssistantView` składa stopkę dla każdego kroku),
/// zmienia się tylko rysunek. Przycisk główny ma glif PO LEWEJ
/// (`EditorialPrimaryActionButton`), więc strzałka „po prawej” z dawnego
/// `SCSoftButton` zamienia się w strzałkę przed tytułem, a akcja bez strzałki
/// („Zaczynajmy”, „Zamknij”) dostaje ptaszek.
struct AssistantIntroFooter: View {
    enum Slot: Equatable {
        case link(String)
        case stepper(step: Int, total: Int)
        case empty
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

    var body: some View {
        SCStepFooter(
            slot: stepSlot,
            onSlotTap: onSlotTap,
            notice: notice,
            showsBack: showsBack,
            onBack: onBack,
            primaryTitle: primaryTitle,
            primaryIcon: primaryIcon,
            isPrimaryEnabled: isPrimaryEnabled,
            isPrimaryLoading: isPrimaryLoading,
            primaryHint: primaryHint,
            onPrimary: onPrimary
        )
    }

    private var stepSlot: SCStepFooter.Slot {
        switch slot {
        case let .link(title): return .link(title)
        case let .stepper(step, total): return .progress(step: step, total: total)
        case .empty: return .empty
        }
    }

    private var primaryIcon: String {
        if let primaryLeadingIcon { return primaryLeadingIcon }
        return primaryTrailingIcon == nil ? "checkmark" : "arrow.right"
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
