import SwiftUI

// Kreator, krok 1 — „Twoje dane”: imię, sylwetka i treningi.
//
// 7.10.2026 (Rafał: „zrób na onboarding user te nowe widoki z ustawień…
// uspójnij to i popraw maksymalnie pod nowy widok”): ten sam widok co
// Ustawienia → „Twoje dane” — profil z ołówkiem i oknem „Imię”, na górze
// wynik (kcal na utrzymanie, BMI na skali), Sylwetka jako wiersze z wyborem
// w arkuszu na 1/3 i kafle treningów (`ProfileBodyForm`). Treningi przeszły
// tu z dawnego kroku „Cel”, bo w Ustawieniach są częścią „Twoich danych”.
// Dawne pola tekstowe wzrostu i wagi, poziome koło lat i chipy odpadły.
//
// Wartości trzyma `WelcomeView` (`@State`); zapis na serwer idzie przy „Dalej”.
struct WelcomeProfileStep: View {
    @Binding var name: String
    @Binding var sexRaw: String
    @Binding var yearOfBirth: Int
    @Binding var heightCm: Int
    @Binding var weightKg: Double
    @Binding var activity: ActivityLevel
    let avatarUrl: String?
    /// Ziarno awatara — id konta, jak w Ustawieniach.
    let seed: String

    /// Wiersz Sylwetki, którego wybór stoi w małym arkuszu.
    @State private var picking: ProfileField? = nil
    @State private var nameDraft = ""
    @State private var isEditingName = false
    /// Okno „Imię” czeka, aż mały arkusz zjedzie — alertu z widoku, który
    /// prezentuje arkusz, system nie pokaże (jak w `ProfileDetailsSheet`).
    @State private var renamesAfterPicker = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        WelcomeStepPage {
            SCStepHeader(
                icon: "person.fill",
                eyebrow: "Twoje dane",
                title: "Zacznijmy od Ciebie",
                subtitle: "Z tych danych policzymy Twój dzienny cel."
            )
            .padding(.bottom, WelcomeLayout.headerSpacing)

            // Bez imienia „Dalej” stoi wyłączone, a tytuł w terakocie prosi
            // o nie — stuknięcie w wiersz albo ołówek otwiera okno „Imię”.
            ProfileIdentityRow(
                title: trimmedName.isEmpty ? "Jak masz na imię?" : trimmedName,
                isPlaceholder: trimmedName.isEmpty,
                avatarUrl: avatarUrl,
                seed: seed,
                onRename: { startEditingName() }
            )
            .padding(.bottom, 18)

            ProfileBodyForm(
                sexRaw: $sexRaw,
                yearOfBirth: $yearOfBirth,
                heightCm: $heightCm,
                weightKg: $weightKg,
                activity: $activity,
                picking: $picking,
                onPickerDismiss: { pickerDidDismiss() }
            )
        }
        .onChange(of: picking) { _, current in
            // Nowy wybór odwołuje okno czekające na zjazd poprzedniego.
            if current != nil { renamesAfterPicker = false }
        }
        .profileNameAlert(isPresented: $isEditingName, draft: $nameDraft) {
            saveName()
        }
    }

    private func startEditingName() {
        nameDraft = trimmedName
        guard picking != nil else {
            isEditingName = true
            return
        }
        renamesAfterPicker = true
        picking = nil
    }

    private func pickerDidDismiss() {
        guard picking == nil, renamesAfterPicker else { return }
        renamesAfterPicker = false
        isEditingName = true
    }

    /// Puste imię się nie zapisuje — „Zapisz” jest wtedy wyłączone.
    private func saveName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        name = trimmed
    }
}
