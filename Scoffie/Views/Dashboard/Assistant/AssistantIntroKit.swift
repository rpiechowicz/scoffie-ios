import SwiftUI

// Wspólne kawałki wprowadzenia Asystenta: flagi „widziane”, stan zgody
// w trakcie wypełniania i przejścia.
//
// Wprowadzenie v2 (24.09.2026, makieta Claude Design „Scoffie — Asystent ·
// Wprowadzenie v2”): Powitanie → Planowanie → Ty decydujesz → Zgoda. Strony
// są w `AssistantIntroPages.swift`, zgoda w `AssistantConsentGateView`,
// a przepływ i JEDNĄ stopkę (`SCStepFooter`, „Wstecz” obok „Dalej” — jak
// w onboardingu aplikacji) składa `AssistantView.introFlow`. Dawne klocki
// v1 — licznik kart „Poznaj”, wiersz „Pomiń” nad kartą, kafel znaku
// i nakładka na stopkę (`AssistantIntroFooter`) — zniknęły razem z kartami.

/// Flagi „widziane" wprowadzenia. Kasowane przy wylogowaniu i usunięciu
/// konta — nowy użytkownik na tym samym telefonie ma zobaczyć wprowadzenie
/// od nowa.
///
/// - `welcomeSeen`: ktoś doszedł do zgody (przez „Dalej” albo „Pomiń”) —
///   bez zgody wraca się prosto do niej, nie do powitania;
/// - `onboardingSeen`: wprowadzenie zakończone zgodą.
enum AssistantIntroState {
    static let welcomeSeenKey = "assistant.welcome.seen"
    static let onboardingSeenKey = "assistant.onboarding.seen"

    static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: welcomeSeenKey)
        defaults.removeObject(forKey: onboardingSeenKey)
    }
}

/// Stan zgody w trakcie wypełniania — POZA widokiem zgody, bo stopka
/// przepływu stoi poza animowaną treścią i musi wiedzieć, czy oba
/// potwierdzenia są zaznaczone, zanim odblokuje „Włącz Asystenta”. Arkusz
/// z menu trzyma własny egzemplarz.
struct AssistantConsentDraft: Equatable {
    var confirmsAge = false
    var confirmsData = false
    var errorMessage: String?
}

extension AnyTransition {
    /// Przejście wprowadzenie ↔ rozmowa: treść wymienia się pionowo
    /// (0,28 s, ease-out), tab bar stoi.
    static var assistantIntroStep: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 22).combined(with: .opacity),
            removal: .offset(y: -18).combined(with: .opacity)
        )
    }

    /// Przejście między krokami — jak w przewodniku i kreatorze: treść
    /// wjeżdża z krawędzi zgodnej z kierunkiem ruchu, poprzednia wyjeżdża
    /// w przeciwną.
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
