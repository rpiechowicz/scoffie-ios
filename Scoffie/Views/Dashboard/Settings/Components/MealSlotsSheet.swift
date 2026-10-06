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
    /// Pora, której godzinę zmienia teraz okienko z kołem (wiersz podświetlony).
    @State private var editing: MealSlot?
    /// Liczniki „pop” świeżo dodanych pór — wyzwalacz `keyframeAnimator`.
    @State private var popCounts: [MealSlot: Int] = [:]

    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 56

    private var configuration: MealSlotConfiguration { sessionStore.mealSlots }
    private var schedule: MealSlotSchedule { sessionStore.mealSlotSchedule }

    /// Posiłki, które Plan faktycznie rysuje w dniu — włączone i te wyłączone,
    /// w których zostały dania. Gdyby tych drugich nie było na osi jako
    /// zwykłych wierszy, ich godzina byłaby widoczna w Planie i nieedytowalna.
    private var timeSlots: [MealSlot] {
        let planned = MealSlot.allCases.filter { slot in
            datesViewModel.dates.contains { date in
                !mealStore.meals(for: date, slot: slot).isEmpty
            }
        }
        return configuration.visibleSlots(planned: planned)
    }

    var body: some View {
        let shown = timeSlots
        // Kolejność liczona po porach, które są w dniu (wiersze z godziną).
        let pair = schedule.outOfOrderPair(among: shown.filter { configuration.isEnabled($0) })
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
                    subtitle: "\(count) \(Self.mealsPlural(count)) w dniu",
                    onClose: onClose
                )
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

                // Cała treść to `List`, bo tylko lista daje systemowe
                // `swipeActions` („Wyłącz” przesunięciem). Lista MUSI się
                // przewijać — `scrollDisabled` wyłącza też gest przesunięcia
                // (tak nie działało „Wyłącz” w pierwszej wersji, 6.10.2026).
                // `insetGrouped` rysuje kartę z zaokrąglonymi rogami sam.
                List {
                    Section {
                        ForEach(Array(MealSlot.allCases.enumerated()), id: \.element) { index, slot in
                            axisRow(
                                slot,
                                isFirst: index == 0,
                                isLast: index == MealSlot.allCases.count - 1,
                                isShown: configuration.isEnabled(slot),
                                warning: pair?.later == slot ? pair?.earlier : nil
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.scTileBg(scheme))
                            // To samo pod przytrzymaniem — gest przesunięcia nie każdy zna.
                            .contextMenu {
                                if configuration.isEnabled(slot), MealSlot.optionalSlots.contains(slot) {
                                    Button(role: .destructive) {
                                        toggle(slot, to: false)
                                    } label: {
                                        Label("Wyłącz \(slot.accusativeName)", systemImage: "minus.circle")
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if configuration.isEnabled(slot), MealSlot.optionalSlots.contains(slot) {
                                    Button(role: .destructive) {
                                        toggle(slot, to: false)
                                    } label: {
                                        Label("Wyłącz", systemImage: "minus.circle")
                                    }
                                    .tint(.red)
                                }
                            }
                        }

                        if pair != nil {
                            orderNotice
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.scTileBg(scheme))
                        }
                    } header: {
                        EditorialSheetSectionLabel(title: "Twój dzień")
                            .textCase(nil)
                    } footer: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Wspólne dla całego domu. Śniadanie, obiad i kolacja są zawsze. Dodatkową porę wyłączysz, przesuwając ją w lewo.")
                                .font(.sc(size: 12.5, weight: .regular))
                                .foregroundStyle(Color.scFaint(scheme))
                                .fixedSize(horizontal: false, vertical: true)

                            if !schedule.isDefault {
                                Button("Przywróć domyślne godziny") {
                                    saveTimes(.default)
                                }
                                .font(.sc(size: 12.5, weight: .semibold))
                                .foregroundStyle(SCPalette.terracotta)
                                .buttonStyle(.plain)
                            }

                            saveStatus
                            timesStatus
                        }
                        .textCase(nil)
                        .padding(.top, 4)
                    }
                }
                .listStyle(.insetGrouped)
                .listRowSpacing(0)
                .environment(\.defaultMinListRowHeight, 0)
                .scrollContentBackground(.hidden)
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .contentMargins(.top, 0, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scScrollEdgeFade()
                .animation(.smooth(duration: 0.22), value: configuration.enabled)
                .animation(.smooth(duration: 0.22), value: pair == nil)
                .animation(.smooth(duration: 0.22), value: schedule.isDefault)
            }
        }
        // Koło godzin we własnym arkuszu, nie w karcie: `DatePicker(.wheel)`
        // przejmuje pionowe przeciągnięcia i w przewijanej treści zjadał
        // przewijanie oraz gest zamknięcia arkusza.
        .sheet(item: $editing) { slot in
            editorSheet(slot)
                // Jedna trzecia ekranu — nad nią dalej widać oś dnia.
                // Pory dodatkowe mają nad kołem wiersz „W planie dnia” — wyżej niż 1/3.
                .presentationDetents([MealSlot.optionalSlots.contains(slot) ? .height(390) : .fraction(1.0 / 3.0)])
                .dashboardLiquidSheet(cornerRadius: 26)
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

    // MARK: - Oś dnia

    /// Ostatni wiersz karty, gdy godziny nie idą po kolei.
    private var orderNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.sc(size: 11.5, weight: .semibold))
                .foregroundStyle(SCPalette.terracotta)

            Text("Plan i tak pokaże posiłki w stałej kolejności dnia.")
                .font(.sc(size: 12.5, weight: .regular))
                .foregroundStyle(Color.scMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    /// Wiersz osi. `isShown` — pora jest w dniu Planu (włączona albo
    /// wyłączona z daniami); inaczej stoi przygaszona z „Dodaj”.
    ///
    /// „Pop” siedzi na kontenerze, nie na wierszu włączonej pory: licznik
    /// rośnie przy stuknięciu w „Dodaj”, zanim konfiguracja przestawi wiersz,
    /// a animator wstawiony razem z nowym wierszem nie zagrałby wcale.
    private func axisRow(
        _ slot: MealSlot,
        isFirst: Bool,
        isLast: Bool,
        isShown: Bool,
        warning: MealSlot?
    ) -> some View {
        ZStack {
            if isShown {
                onRow(
                    slot,
                    isFirst: isFirst,
                    isLast: isLast,
                    isDimmed: !configuration.isEnabled(slot),
                    warning: warning
                )
            } else {
                offRow(slot, isFirst: isFirst, isLast: isLast, planned: plannedCount(for: slot))
            }
        }
        .keyframeAnimator(initialValue: 1.0, trigger: popCounts[slot] ?? 0) { row, scale in
            row.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(1.04, duration: 0.12, spring: .snappy)
                SpringKeyframe(1, duration: 0.3, spring: .bouncy)
            }
        }
    }

    private func onRow(
        _ slot: MealSlot,
        isFirst: Bool,
        isLast: Bool,
        isDimmed: Bool,
        warning: MealSlot?
    ) -> some View {
        let time = schedule.time(for: slot)
        let isEditing = editing == slot
        let timeColor: Color = (warning != nil || isEditing)
            ? SCPalette.terracotta
            : Color.scLabel(scheme)

        return Button {
            editing = slot
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let time {
                        Text(time)
                            .font(.sc(size: 18, weight: .bold))
                            .tracking(-0.3)
                            .monospacedDigit()
                            .foregroundStyle(timeColor)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("kiedy\nchcesz")
                            .font(.sc(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color.scMuted(scheme))
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                    }
                }
                .frame(width: 62, alignment: .trailing)

                axisMark(isFirst: isFirst, isLast: isLast, gap: 30 + 8) {
                    Image(systemName: slot.icon)
                        .font(.sc(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(slot.cozyAccent))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(slot.title)
                        .font(.sc(size: 16, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(1)

                    if let warning {
                        Text(warningText(earlier: warning))
                            .font(.sc(size: 12.5, weight: .medium))
                            .foregroundStyle(SCPalette.terracotta)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.sc(size: 13, weight: .semibold))
                    .foregroundStyle(Color.scFaint(scheme))
            }
            .padding(.leading, 14)
            .padding(.trailing, 14)
            .frame(height: rowHeight)
            .opacity(isDimmed ? 0.5 : 1)
            .background(SCPalette.terracotta.opacity(isEditing ? 0.08 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle())
        .animation(.smooth(duration: 0.22), value: time)
        .animation(.smooth(duration: 0.2), value: isEditing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(slot.title), \(time ?? "bez stałej pory")")
        .accessibilityHint("Stuknij, aby zmienić porę")
        .accessibilityAddTraits(.isButton)
    }

    /// Pora, której dom nie je: na swoim miejscu, przygaszona, z „Dodaj”.
    private func offRow(_ slot: MealSlot, isFirst: Bool, isLast: Bool, planned: Int) -> some View {
        HStack(spacing: 10) {
            Text(schedule.time(for: slot) ?? "—")
                .font(.sc(size: 18, weight: .medium))
                .tracking(-0.3)
                .monospacedDigit()
                .foregroundStyle(Color.scFaint(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 62, alignment: .trailing)

            axisMark(isFirst: isFirst, isLast: isLast, gap: 14 + 12) {
                Circle()
                    .strokeBorder(
                        slot.cozyAccent.opacity(0.6),
                        style: StrokeStyle(lineWidth: 2, dash: [3, 2.5])
                    )
                    .frame(width: 14, height: 14)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(slot.title)
                    .font(.sc(size: 16, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)

                // Wyłączona, ale w tym tygodniu zostały w niej dania — Plan
                // dalej ją pokazuje, więc mówimy, dlaczego.
                if planned > 0 {
                    Text("W tym tygodniu: \(planned) \(Self.dishesPlural(planned))")
                        .font(.sc(size: 12.5, weight: .regular))
                        .foregroundStyle(Color.scFaint(scheme))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                popCounts[slot, default: 0] += 1
                toggle(slot, to: true)
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "plus")
                        .font(.sc(size: 13, weight: .semibold))
                    Text("Dodaj")
                        .font(.sc(size: 13.5, weight: .semibold))
                }
                .foregroundStyle(Color.scLabel(scheme))
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .frame(height: 32)
                .scChromeGlass(in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(PlanPressStyle(scale: 0.94))
            .accessibilityLabel("Dodaj \(slot.accusativeName)")
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(height: rowHeight)
    }

    /// Znak pory na linii dnia. Linia to dwa odcinki — nad i pod znakiem —
    /// z przerwą `gap`, a nie jedna kreska pod kółkami: tło karty jest
    /// półprzezroczyste, więc „obwódka w kolorze tła” nie zakryłaby kreski.
    /// Pierwszy wiersz nie ma odcinka u góry, ostatni u dołu.
    private func axisMark<Mark: View>(
        isFirst: Bool,
        isLast: Bool,
        gap: CGFloat,
        @ViewBuilder mark: () -> Mark
    ) -> some View {
        let rule = Color.scRule(scheme)

        return ZStack {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : rule)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                Color.clear
                    .frame(width: 2, height: gap)
                Rectangle()
                    .fill(isLast ? Color.clear : rule)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            mark()
        }
        .frame(width: 30)
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    private func warningText(earlier: MealSlot) -> String {
        let time = schedule.time(for: earlier).map { " (\($0))" } ?? ""
        return "Nie później niż \(earlier.lowercaseName)\(time)"
    }

    // MARK: - Okienko godziny

    private func editorSheet(_ slot: MealSlot) -> some View {
        MealTimeEditorSheet(
            slot: slot,
            minutes: schedule.minutes(for: slot),
            onPick: { picked in
                guard picked != schedule.minutes(for: slot) else { return }
                saveTimes(schedule.setting(slot, toMinutes: picked))
            },
            onClearTime: {
                editing = nil
                saveTimes(schedule.setting(slot, toMinutes: nil))
            },
            onClose: { editing = nil },
            inPlan: inPlanToggle(for: slot)
        )
    }

    /// Wiersz „W planie dnia” z przełącznikiem — tylko przy porach
    /// dodatkowych (obowiązkowych nie da się wyłączyć). Wyłączenie zamyka
    /// okienko, gdy kciuk przejedzie (oś pod spodem pokazuje skutek);
    /// włączenie zostawia je otwarte, bo zwykle chce się od razu ustawić godzinę.
    private func inPlanToggle(for slot: MealSlot) -> MealTimeEditorSheet.InPlan? {
        guard MealSlot.optionalSlots.contains(slot) else { return nil }
        return MealTimeEditorSheet.InPlan(
            isOn: configuration.isEnabled(slot),
            set: { isOn in
                if isOn {
                    popCounts[slot, default: 0] += 1
                    toggle(slot, to: true)
                } else {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        editing = nil
                        disableFromEditor(slot)
                    }
                }
            }
        )
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

    /// Polska liczba mnoga: 1 posiłek, 2–4 posiłki, 5–21 posiłków,
    /// 22 posiłki… Reguła idzie po ostatniej cyfrze z wyjątkiem nastek.
    private static func dishesPlural(_ count: Int) -> String {
        if count == 1 { return "danie" }
        let lastTwo = count % 100
        if (12...14).contains(lastTwo) { return "dań" }
        return (2...4).contains(count % 10) ? "dania" : "dań"
    }

    private static func mealsPlural(_ count: Int) -> String {
        if count == 1 { return "posiłek" }
        let lastTwo = count % 100
        if (12...14).contains(lastTwo) { return "posiłków" }
        return (2...4).contains(count % 10) ? "posiłki" : "posiłków"
    }
}
