import SwiftUI

/// Jeden krok przewodnika „Poznaj aplikację”.
///
/// Od 24.09.2026 (wieczór) krok to PLAKAT z R2 — pionowa grafika z własnym
/// nagłówkiem, opisem i kartami aplikacji (te same, co zrzuty w App Store).
/// Rafał: „podmień przewodnik”. Wcześniej: pozioma ilustracja + nagłówek
/// kroku + karta czterech funkcji rysowane w aplikacji. Tekst plakatu żyje
/// tu jeszcze raz wyłącznie dla VoiceOver — obrazka czytnik nie przeczyta.
struct TourStep: Identifiable {
    let id: String
    /// Kolor tła pod plakatem, zanim dojdzie z sieci.
    let accent: Color
    /// Nagłówek plakatu, słowo w słowo.
    let title: String
    /// Opis pod nagłówkiem plakatu, słowo w słowo.
    let lead: String
    /// Plakat na R2 (`TourStep.image(_:version:)`).
    let imageURL: URL
}

extension TourStep {
    /// Plakaty przewodnika leżą na R2 (bucket zdjęć, `onboarding/`), nie
    /// w paczce aplikacji — Rafał 24.09.2026. WebP 1080 × 2344, ~150–210 KB.
    /// CDN trzyma je z `immutable` na rok, więc NOWA grafika = NOWA wersja
    /// w nazwie (`-v3`), nigdy nadpisanie pod tą samą. `-v1` to dawne poziome
    /// ilustracje — zostają na R2 dla starszych wersji aplikacji.
    private static let imageBase = URL(string: "https://img.scoffie.app/onboarding/")!

    private static func image(_ name: String, version: Int = 2) -> URL {
        imageBase.appendingPathComponent("tour-\(name)-v\(version).webp")
    }

    /// Ściąga plakaty do pamięci i na dysk, zanim przewodnik je pokaże —
    /// woła ją ekran logowania i sam przepływ. Powtórne wołanie nic nie
    /// kosztuje (trafienie w pamięć podręczną).
    static func prefetchImages() {
        ImagePrefetcher.prefetch(all.map(\.imageURL), variant: .poster)
    }

    /// Kolejność jak w aplikacji: Plan, Przepisy, Zakupy, Asystent,
    /// Ustawienia — ostatni krok prowadzi wprost do kreatora, który te
    /// ustawienia wypełnia. Plakaty „Mniej planowania…” (powitanie) i „Każdy
    /// posiłek…” (Kalendarz) są tylko w App Store — przewodnik ma własne
    /// powitanie, a Kalendarza nie pokazuje.
    static let all: [TourStep] = [
        TourStep(
            id: "plan",
            accent: SCPalette.terracotta,
            title: "Wasz tydzień. Wspólny plan.",
            lead: "Zaplanuj posiłki dla całego domu. Śledź kalorie i makra każdej osoby.",
            imageURL: image("plan")
        ),
        TourStep(
            id: "recipes",
            accent: SCPalette.sage,
            title: "Przepisy dopasowane do Ciebie.",
            lead: "Kalorie, makra i składniki w jednym miejscu. Wybieraj dania zgodne z dietą i wykluczaj wybrane alergeny.",
            imageURL: image("recipes")
        ),
        TourStep(
            id: "shopping",
            accent: SCPalette.indigo,
            title: "Wasze posiłki. Gotowe zakupy.",
            lead: "Lista zakupów powstaje z Waszego planu. Sprawdź składniki według dań i zobacz, czego brakuje na dziś.",
            imageURL: image("shopping")
        ),
        TourStep(
            id: "assistant",
            accent: SCPalette.butter,
            title: "Twój asystent AI. Mniej główkowania.",
            lead: "Zaplanuj posiłki w rozmowie. Scoffie uwzględni dietę i alergeny, a wybrane dania łatwo zamienisz.",
            imageURL: image("assistant")
        ),
        TourStep(
            id: "settings",
            accent: SCPalette.terracottaDeep,
            title: "Twoje potrzeby. Twoje ustawienia.",
            lead: "Dopasuj kalorie, makra i dietę do siebie. Ustaw godziny posiłków w rytmie swojego dnia.",
            imageURL: image("settings")
        ),
    ]
}

/// Klucz „przewodnik obejrzany".
///
/// Trzymany w `UserDefaults`, a nie na serwerze, bo dotyczy urządzenia, nie
/// konta — i celowo kasowany w `SessionStore.clearPersistedSession()`.
/// Bez tego kasowania wylogowanie i ponowne zalogowanie (także na cudze
/// konto) omijałoby przewodnik, bo flaga przeżywa w `UserDefaults` sesję,
/// po której została ustawiona.
enum TourCompletion {
    static let storageKey = "onboarding.tourCompleted"
}
