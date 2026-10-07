import SwiftUI

// Kreator, krok 3 — „Posiłki w planie”: które pory dom planuje i o której.
//
// 7.10.2026 (Rafał: „zrób na onboarding user te nowe widoki z ustawień…
// uspójnij to”): ta sama pionowa oś dnia co Ustawienia → „Posiłki w planie”
// (`MealDayAxisList`) — pora dodatkowa włącza się „Dodaj” w swoim miejscu,
// wyłącza przesunięciem, przytrzymaniem albo „Wyłącz” w okienku godziny.
// Dawne karty „Zawsze w planie” i „Dodatkowe posiłki” oraz pozioma oś
// (`MealDayTimesCard`) odpadły.
//
// Wybór i godziny czekają w `WelcomeView` na gospodarstwo z kroku 4 —
// `households:updateMealTypes` / `updateMealTimes` potrzebują `householdId`.
// Domu jeszcze nie ma, więc żadna pora nie ma dań (`plannedCount` = 0)
// i wyłączenie nie pyta o nic.
struct WelcomeMealsStep: View {
    @Binding var mealSlots: MealSlotConfiguration
    @Binding var mealSchedule: MealSlotSchedule

    var body: some View {
        MealDayAxisList(
            configuration: mealSlots,
            schedule: mealSchedule,
            plannedCount: { _ in 0 },
            onSetEnabled: { slot, isOn in
                guard mealSlots.isEnabled(slot) != isOn else { return }
                mealSlots = mealSlots.toggling(slot)
            },
            onSetTime: { slot, minutes in
                mealSchedule = mealSchedule.setting(slot, toMinutes: minutes)
            },
            onResetTimes: { mealSchedule = .default },
            topMargin: WelcomeLayout.topInset,
            top: {
                SCStepHeader(
                    icon: "fork.knife",
                    accent: SCPalette.butter,
                    eyebrow: "Posiłki w planie",
                    title: "Ile posiłków jecie?",
                    subtitle: MealCountText.inDay(mealSlots.enabled.count)
                )
                .padding(.bottom, 4)
            },
            status: { EmptyView() }
        )
    }
}
