import SwiftUI

/// Ustawienia → „Posiłki w planie” (wersja 4 · czytelnie, 6.10.2026).
///
/// JEDNA karta „Twój dzień”: pionowa oś dnia ze wszystkimi sześcioma porami
/// w kolejności doby. Włączona pora = godzina dużą cyfrą, kółko w kolorze pory
/// na linii dnia, pełna nazwa i szewron — stuknięcie otwiera koło godzin
/// w arkuszu na 1/3 ekranu (`MealTimeEditorSheet`). Pora, której dom nie je,
/// stoi przygaszona W SWOIM miejscu z pigułką „Dodaj” — od razu widać, co da
/// się dołożyć i gdzie wypadnie. Dawne karty „Dodatkowe posiłki”, wiersz
/// „Zawsze w planie” i akapity odpadły.
///
/// Wyłączenie pory dodatkowej: przesunięcie wiersza w lewo (jak usuwanie
/// w Mailu) albo „Wyłącz” obok krzyżyka w okienku godziny. Dlatego treść to
/// `List(.insetGrouped)` — `swipeActions` działa tylko w liście, i to tylko
/// w PRZEWIJANEJ (`scrollDisabled` wyłącza też przesunięcie).
///
/// Wyłączenie nie kasuje jedzenia: jeśli w porze coś stoi, pytamy
/// o potwierdzenie, a Plan pokazuje ją dalej (`visibleSlots(planned:)`).
/// Tu taka pora stoi jak każda wyłączona — z „Dodaj” i dopiskiem
/// „W tym tygodniu: 2 dania” (wcześniej stała jak włączona, tylko
/// przygaszona, i wyglądało, jakby „Wyłącz” nie zadziałało).
///
/// Od 7.10.2026 sama oś (wiersze, okienko godziny, przesunięcie) to wspólny
/// `MealDayAxisList` — stoi na nim też krok „Posiłki” kreatora. Tu zostaje
/// zapis od razu, pytanie przy porze z daniami i stan zapisu.
struct MealSlotsSheet: View {
    var onClose: () -> Void

    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.mealCalendarStore) private var mealStore
    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.colorScheme) private var scheme

    @State private var pendingDisable: MealSlot?
    @State private var errorMessage: String?
    /// Konfiguracja, której nie udało się zapisać — zasila „Spróbuj ponownie".
    /// Bez tego użytkownik musi się domyślić, że ma przestawić kartę drugi raz.
    @State private var lastFailed: MealSlotConfiguration?
    @State private var timesErrorMessage: String?
    /// Rozkład godzin, którego nie udało się zapisać — zasila „Spróbuj ponownie".
    @State private var lastFailedTimes: MealSlotSchedule?

    private var configuration: MealSlotConfiguration { sessionStore.mealSlots }
    private var schedule: MealSlotSchedule { sessionStore.mealSlotSchedule }

    var body: some View {
        let count = configuration.enabled.count

        return ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Masło — kolor wiersza „Posiłki w planie” w Ustawieniach.
                EditorialSheetHeader(
                    eyebrow: "Gospodarstwo",
                    title: "Posiłki w planie",
                    icon: "fork.knife",
                    accent: SCPalette.butter,
                    subtitle: MealCountText.inDay(count),
                    onClose: onClose
                )
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

                MealDayAxisList(
                    configuration: configuration,
                    schedule: schedule,
                    plannedCount: { plannedCount(for: $0) },
                    onSetEnabled: { slot, isOn in toggle(slot, to: isOn) },
                    onDisableFromEditor: { disableFromEditor($0) },
                    onSetTime: { slot, minutes in
                        saveTimes(schedule.setting(slot, toMinutes: minutes))
                    },
                    onResetTimes: { saveTimes(.default) }
                ) {
                    saveStatus
                    timesStatus
                }
            }
        }
        .alert(
            disableAlertTitle,
            isPresented: Binding(
                get: { pendingDisable != nil },
                set: { if !$0 { pendingDisable = nil } }
            ),
            presenting: pendingDisable
        ) { slot in
            Button("Anuluj", role: .cancel) { pendingDisable = nil }
            Button("Wyłącz") {
                pendingDisable = nil
                apply(configuration.disabling(slot))
            }
        } message: { slot in
            Text(
                "W tym tygodniu masz tu zaplanowane posiłki (\(plannedCount(for: slot))). "
                + "Zostaną w planie — slot będzie widoczny, dopóki coś w nim stoi."
            )
        }
    }

    /// Tytuł potwierdzenia. Składany osobno, bo nazwa slotu wchodzi
    /// w polskie cudzysłowy i interpolacja w literale zjadałaby zamykający.
    private var disableAlertTitle: String {
        "Wyłączyć \u{201E}\(pendingDisable?.title ?? "")\u{201D}?"
    }

    /// „Wyłącz” z okienka godziny. Bez dań — od razu, oś zmienia się, gdy
    /// okienko jeszcze schodzi. Z daniami — potwierdzenie, ale dopiero po
    /// zejściu okienka: alert nie pokaże się nad schodzącym arkuszem (wcześniej
    /// czekało to na `onDismiss`, który nie zawsze przychodził, i „Wyłącz”
    /// nic nie robiło).
    private func disableFromEditor(_ slot: MealSlot) {
        guard plannedCount(for: slot) > 0 else {
            apply(configuration.disabling(slot))
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            pendingDisable = slot
        }
    }

    // MARK: - Zapis godzin

    /// Bez stanu „Zapisuję…" — zapis jest optymistyczny, oś pokazuje nową
    /// godzinę, zanim cokolwiek poleci po sieci. Zostaje tylko nieudany zapis.
    private func saveTimes(_ next: MealSlotSchedule) {
        timesErrorMessage = nil
        lastFailedTimes = nil
        Task { @MainActor in
            let saved = await sessionStore.saveMealSlotSchedule(next)
            if !saved {
                timesErrorMessage = "Nie udało się zapisać godzin."
                lastFailedTimes = next
            }
        }
    }

    // MARK: - Stan zapisu

    @ViewBuilder
    private var timesStatus: some View {
        if let timesErrorMessage {
            VStack(alignment: .leading, spacing: 6) {
                SCInlineErrorText(timesErrorMessage)

                if let lastFailedTimes {
                    SCRetryButton { saveTimes(lastFailedTimes) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
        }
    }

    /// Świadomie **bez** stanu „Zapisuję…".
    ///
    /// Zapis jest optymistyczny — `saveMealSlotConfiguration` przestawia
    /// `mealSlots` od razu, a przy błędzie cofa. Karta pokazuje więc nową
    /// wartość zanim cokolwiek poleci po sieci, a napis, który zapala się
    /// i gaśnie w kilkadziesiąt milisekund, tylko podskakiwał układem.
    /// Zostaje wyłącznie stan, który niesie informację: nieudany zapis.
    @ViewBuilder
    private var saveStatus: some View {
        if let errorMessage {
            VStack(alignment: .leading, spacing: 6) {
                SCInlineErrorText(errorMessage)

                if let lastFailed {
                    SCRetryButton { apply(lastFailed) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
        }
    }

    // MARK: - Akcje

    /// Ile posiłków stoi w tym slocie w oglądanym tygodniu. Zasila ostrzeżenie
    /// przy wyłączaniu i podpis „w tym tygodniu".
    private func plannedCount(for slot: MealSlot) -> Int {
        datesViewModel.dates.reduce(0) { total, date in
            total + mealStore.meals(for: date, slot: slot).count
        }
    }

    private func toggle(_ slot: MealSlot, to isOn: Bool) {
        guard isOn || plannedCount(for: slot) == 0 else {
            // Wyłączenie slotu, w którym coś stoi, przechodzi przez alert.
            pendingDisable = slot
            return
        }
        apply(configuration.toggling(slot))
    }

    private func apply(_ next: MealSlotConfiguration) {
        errorMessage = nil
        lastFailed = nil
        Task { @MainActor in
            let saved = await sessionStore.saveMealSlotConfiguration(next)
            if !saved {
                // Sam skutek, bez diagnozy łączności: brak sieci ma w aplikacji
                // jedno miejsce (pasek u góry), a „Spróbuj ponownie” stoi obok.
                errorMessage = "Nie udało się zapisać zmiany."
                lastFailed = next
            }
        }
    }
}
