import SwiftUI

/// Ustawienia → „Pory posiłków".
///
/// Rozkład jazdy dnia. Odpowiada wyłącznie na pytanie „o której", a to,
/// **które** posiłki w ogóle jecie, ustawia sąsiedni arkusz „Posiłki
/// w planie". Rozdzielone, bo to dwie różne decyzje — ale obie obowiązują
/// całe gospodarstwo: plan tygodnia i lista zakupów są wspólne, więc pora
/// obiadu też musi być jedna dla domu.
///
/// Trzy decyzje projektowe:
///
/// 1. **Godzina jest pierwsza i przy lewej krawędzi.** To sedno tego ekranu:
///    kilka liczb w jednej pionowej kolumnie czyta się jednym ruchem oka,
///    a długość nazwy posiłku nie ma na co wpłynąć.
/// 2. **Koło godzin mieszka we własnym arkuszu, nie w rozwijanym wierszu.**
///    Wersja z akordeonem wstawiała `DatePicker(.wheel)` w środek
///    `ScrollView` — a koło z definicji przejmuje pionowe przeciągnięcia
///    w swoim obszarze. Skutek: przy próbie przewinięcia albo zamknięcia
///    arkusza przewijał się czas. Tego nie da się wyłączyć flagą, więc koło
///    musiało wyjść tam, gdzie nie ma z czym kolidować.
/// 3. **Listujemy to, co widać w Planie**, czyli `visibleSlots(planned:)`,
///    a nie same włączone sloty. Wyłączony posiłek, w którym zostały
///    zaplanowane dania, wraca do Planu z podpisem godziny — gdyby go tu
///    nie było, ta godzina byłaby widoczna i nieedytowalna.
struct MealTimesSheet: View {
    var onClose: () -> Void

    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.mealCalendarStore) private var mealStore
    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.colorScheme) private var scheme

    @State private var editing: MealSlot?
    @State private var errorMessage: String?
    /// Rozkład, którego nie udało się zapisać — zasila „Spróbuj ponownie".
    @State private var lastFailed: MealSlotSchedule?

    private var configuration: MealSlotConfiguration { sessionStore.mealSlots }
    private var schedule: MealSlotSchedule { sessionStore.mealSlotSchedule }

    /// Sloty, które Plan faktycznie rysuje w dniu.
    private var rows: [MealSlot] {
        let planned = MealSlot.allCases.filter { slot in
            datesViewModel.dates.contains { date in
                !mealStore.meals(for: date, slot: slot).isEmpty
            }
        }
        return configuration.visibleSlots(planned: planned)
    }

    var body: some View {
        let rows = self.rows

        return ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EditorialSheetHeader(
                        eyebrow: "Gospodarstwo",
                        title: "Pory posiłków",
                        onClose: onClose
                    )

                    Text("Godziny podpisują posiłki w planie i kalendarzu. Obowiązują wszystkich domowników — zmiana pojawi się od razu u każdego.")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)

                    EditorialSettingsCardGroup {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, slot in
                            timeRow(
                                slot,
                                isEnabledInPlan: configuration.isEnabled(slot),
                                isLast: index == rows.count - 1
                            )
                        }
                    }

                    outOfOrderNotice(rows)
                    saveStatus

                    if !schedule.isDefault {
                        Button("Przywróć domyślne godziny") {
                            save(.default)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SCPalette.terracotta)
                        .padding(.horizontal, 6)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(item: $editing) { slot in
            MealTimeEditorSheet(
                slot: slot,
                minutes: schedule.minutes(for: slot),
                onPick: { picked in
                    guard picked != schedule.minutes(for: slot) else { return }
                    save(schedule.setting(slot, toMinutes: picked))
                },
                onClearTime: {
                    editing = nil
                    save(schedule.setting(slot, toMinutes: nil))
                },
                onClose: { editing = nil }
            )
            .presentationDetents([.height(360)])
            .dashboardLiquidSheet(cornerRadius: 26)
        }
    }

    /// Bez stanu „Zapisuję…". Zapis jest optymistyczny — zegar pokazuje nową
    /// godzinę, zanim cokolwiek poleci po sieci — a napis migający przez
    /// kilkadziesiąt milisekund tylko podskakiwałby układem. Zostaje wyłącznie
    /// stan, który niesie informację: nieudany zapis.
    @ViewBuilder
    private var saveStatus: some View {
        if let errorMessage {
            VStack(alignment: .leading, spacing: 6) {
                Text(errorMessage)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                if let lastFailed {
                    Button("Spróbuj ponownie") { save(lastFailed) }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SCPalette.terracotta)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
        }
    }

    private func save(_ next: MealSlotSchedule) {
        errorMessage = nil
        lastFailed = nil
        Task { @MainActor in
            let saved = await sessionStore.saveMealSlotSchedule(next)
            if !saved {
                errorMessage = "Nie udało się zapisać godzin. Sprawdź połączenie i spróbuj ponownie."
                lastFailed = next
            }
        }
    }

    // MARK: - Wiersz rozkładu

    /// Jeden przystanek: godzina · kafel · nazwa · szewron. Wiersz nic nie
    /// rozwija — otwiera edytor. Dzięki temu w karcie nie ma animowanej
    /// wysokości ani niczego, co przechwytuje przewijanie.
    private func timeRow(_ slot: MealSlot, isEnabledInPlan: Bool, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            Button {
                editing = slot
            } label: {
                HStack(spacing: 0) {
                    // Stała kolumna 54pt: „08:00" w 16pt bold z cyframi
                    // o równej szerokości zajmuje ~44pt, więc wszystkie
                    // godziny stoją w jednej pionowej linii niezależnie od
                    // długości nazw.
                    Text(schedule.time(for: slot) ?? "—")
                        .font(.system(size: 16, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(timeColor(slot, isEnabledInPlan: isEnabledInPlan))
                        .frame(width: 54, alignment: .leading)

                    slotTile(slot, isEnabledInPlan: isEnabledInPlan)
                        .padding(.trailing, 10)

                    Text(slot.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isEnabledInPlan ? Color.scLabel(scheme) : Color.scMuted(scheme))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color.scFaint(scheme))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.scChipBg(scheme)))
                }
                .frame(height: 56)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(slot.title), \(schedule.time(for: slot) ?? "bez stałej pory")")
            .accessibilityHint("Stuknij, aby zmienić porę")

            if !isLast {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func timeColor(_ slot: MealSlot, isEnabledInPlan: Bool) -> Color {
        if schedule.minutes(for: slot) == nil { return Color.scFaint(scheme) }
        return isEnabledInPlan ? Color.scLabel(scheme) : Color.scMuted(scheme)
    }

    private func slotTile(_ slot: MealSlot, isEnabledInPlan: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(slot.cozyAccent.opacity(scheme == .dark ? 0.22 : 0.16))

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(slot.cozyAccent.opacity(0.4), lineWidth: 1)

            Image(systemName: slot.icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(slot.cozyAccent)
        }
        .frame(width: 22, height: 22)
        .opacity(isEnabledInPlan ? 1 : 0.5)
    }

    // MARK: - Ostrzeżenie o kolejności

    @ViewBuilder
    private func outOfOrderNotice(_ rows: [MealSlot]) -> some View {
        if let pair = schedule.outOfOrderPair(among: rows) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SCPalette.terracotta)

                Text(outOfOrderText(pair))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6)
        }
    }

    /// Kolejność slotów w planie jest stała — godziny jej nie przestawiają.
    /// Użytkownik ma się o tym dowiedzieć od nas, a nie ze zdziwienia nad
    /// ekranem Planu.
    private func outOfOrderText(_ pair: (earlier: MealSlot, later: MealSlot)) -> String {
        let earlierTime = schedule.time(for: pair.earlier) ?? ""
        let laterTime = schedule.time(for: pair.later) ?? ""
        let tail = "Plan i kalendarz i tak pokażą posiłki w stałej kolejności dnia."

        if earlierTime == laterTime {
            return "\(pair.earlier.title) i \(pair.later.title.lowercased()) mają tę samą porę (\(earlierTime)). \(tail)"
        }
        return "\(pair.later.title) (\(laterTime)) wypada nie później niż \(pair.earlier.title.lowercased()) (\(earlierTime)). \(tail)"
    }
}

// MARK: - Edytor pory

/// Koło godzin dla jednego posiłku, we własnym arkuszu.
///
/// Powód istnienia tego pliku jako osobnego widoku: `DatePicker(.wheel)`
/// przejmuje pionowe przeciągnięcia w swoim obszarze i **nie da się** tego
/// wyłączyć. Wstawione w `ScrollView` zjadało przewijanie listy i gest
/// zamknięcia arkusza. Tutaj nic nie przewija się pod spodem, więc koło może
/// sobie łapać wszystko, co chce — a arkusz zamyka się uchwytem, przyciskiem
/// albo stuknięciem w tło.
private struct MealTimeEditorSheet: View {
    let slot: MealSlot
    let minutes: Int?
    let onPick: (Int) -> Void
    let onClearTime: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var scheme

    /// Kopia lokalna: koło pisze tu na każdą klatkę przeciągnięcia,
    /// a do `sessionStore` idzie dopiero wartość różna od zapisanej.
    @State private var selection: Date

    init(
        slot: MealSlot,
        minutes: Int?,
        onPick: @escaping (Int) -> Void,
        onClearTime: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.slot = slot
        self.minutes = minutes
        self.onPick = onPick
        self.onClearTime = onClearTime
        self.onClose = onClose
        let start = minutes ?? MealSlotSchedule.snackSuggestedMinutes
        _selection = State(initialValue: MealSlotSchedule.date(fromMinutes: start))
    }

    var body: some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                DatePicker(
                    "",
                    selection: $selection,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.wheel)
                // Bez wymuszonej lokalizacji telefon w en_US pokaże AM/PM,
                // a cała reszta aplikacji rysuje godziny jako „%02d:%02d".
                .environment(\.locale, Locale(identifier: "pl_PL"))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)

                // Zdjąć porę można wyłącznie tam, gdzie model na to pozwala.
                // Przy pozostałych slotach `setting(_:toMinutes: nil)` jest
                // no-opem i UI nie ma prawa udawać, że zmiana przeszła.
                if !MealSlotSchedule.slotsRequiringTime.contains(slot) {
                    Button("Bez stałej pory", action: onClearTime)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(SCPalette.terracotta)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.bottom, 6)
                }

                Spacer(minLength: 0)
            }
        }
        .onChange(of: selection) { _, newValue in
            onPick(MealSlotSchedule.minutes(from: newValue))
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(slot.cozyAccent.opacity(scheme == .dark ? 0.22 : 0.16))

                Image(systemName: slot.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(slot.cozyAccent)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("Pora posiłku")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(SCPalette.terracotta)

                Text(slot.title)
                    .font(.system(size: 19, weight: .heavy))
                    .tracking(-0.3)
                    .foregroundStyle(Color.scLabel(scheme))
            }

            Spacer(minLength: 8)

            Button("Gotowe", action: onClose)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SCPalette.terracotta)
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 4)
    }
}
