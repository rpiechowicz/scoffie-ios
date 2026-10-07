import SwiftUI

// Kreator, krok 2 — „Dieta i alergeny”: kalorie, makro, cel, sposób
// odżywiania i alergeny.
//
// 7.10.2026 (Rafał: „zrób na onboarding user te nowe widoki z ustawień…
// uspójnij to”): dawne kroki „Cel” i „Dieta i kalorie” to jeden krok, bo
// w Ustawieniach cel stoi w arkuszu „Dieta i alergeny” — i to ten sam widok
// (`DietPreferencesForm`). Różnice to tryby: makro bez stepperów (zapis
// z kreatora nie wysyła nadpisań), wybór alergenów w arkuszu, bez odsyłacza
// do „Twoich danych” (sylwetka jest z kroku 1).
//
// Kalorie idą za celem i sylwetką, dopóki nikt nie ruszył suwaka
// (`WelcomeView.calorieAdjustedManually`); „Ustaw” w karcie wraca do podpowiedzi.
//
// Cel i dieta wymagane (7.10.2026): startują bez wyboru (`nil`), a kalorie
// i makro są zakryte do wyboru celu (`DietPreferencesForm(answers:)`).
// Alergeny opcjonalne — brak wyboru = brak alergii.
struct WelcomeDietStep: View {
    @Binding var calorieGoal: Int
    @Binding var goal: UserGoal?
    @Binding var diet: DietPreference?
    @Binding var allergens: Set<Allergen>
    /// Sylwetka z kroku 1 — podpowiedź kaloryczna i makro.
    let metrics: BodyMetrics?

    var body: some View {
        WelcomeStepPage {
            SCStepHeader(
                icon: "leaf.fill",
                accent: SCPalette.sage,
                eyebrow: "Dieta i alergeny",
                title: "Ile i co jesz?",
                subtitle: "Cel policzyliśmy z Twoich danych."
            )
            .padding(.bottom, WelcomeLayout.headerSpacing)

            DietPreferencesForm(
                calorieGoal: $calorieGoal,
                answers: $goal,
                diet: $diet,
                metrics: metrics,
                allergens: allergens,
                onToggleAllergen: { toggle($0) },
                onClearAllergens: { allergens = [] }
            )
        }
    }

    private func toggle(_ allergen: Allergen) {
        if allergens.contains(allergen) {
            allergens.remove(allergen)
        } else {
            allergens.insert(allergen)
        }
    }
}
