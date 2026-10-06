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
/// Wyłączenie pory dodatkowej: „Wyłącz” obok krzyżyka w okienku godziny albo
/// przesunięcie wiersza w lewo (jak usuwanie w Mailu). Dlatego oś to `List` —
/// `swipeActions` działa tylko w liście; lista nie przewija się sama
/// (`scrollDisabled`) i ma wysokość wszystkich wierszy, więc w karcie
/// zachowuje się jak zwykły `VStack`.
///
/// Wyłączenie nie kasuje jedzenia: jeśli w porze coś stoi, pytamy
/// o potwierdzenie, a Plan pokazuje ją dalej (`visibleSlots(planned:)`) —
/// tu taka pora stoi jak włączona, tylko przygaszona.
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
    /// Pora do przełączenia, gdy okienko godziny ZEJDZIE — alert potwierdzenia
    /// nie pokaże się, dopóki stoi nad nim inny arkusz.
    @State private var toggleAfterEditor: MealSlot?
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
        let pair = schedule.outOfOrderPair(among: shown)
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

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        EditorialSheetSectionLabel(title: "Twój dzień")

                        dayCard(shown: shown, pair: pair)

                        Text("Wspólne dla całego domu. Śniadanie, obiad i kolacja są zawsze.")
                            .font(.sc(size: 12.5, weight: .regular))
                            .foregroundStyle(Color.scFaint(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 6)

                        if !schedule.isDefault {
                            Button("Przywróć domyślne godziny") {
                                saveTimes(.default)
                            }
                            .font(.sc(size: 12.5, weight: .semibold))
                            .foregroundStyle(SCPalette.terracotta)
                            .padding(.horizontal, 6)
                            .padding(.top, 2)
                        }

                        saveStatus
                        timesStatus
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 40)
                    .animation(.smooth(duration: 0.22), value: schedule.isDefault)
                }
                .scrollIndicators(.hidden)
                .scScrollEdgeFade()
            }
        }
        // Koło godzin we własnym arkuszu, nie w karcie: `DatePicker(.wheel)`
        // przejmuje pionowe przeciągnięcia i w przewijanej treści zjadał
        // przewijanie oraz gest zamknięcia arkusza.
        .sheet(item: $editing, onDismiss: { runToggleAfterEditor() }) { slot in
            editorSheet(slot)
                // Jedna trzecia ekranu — nad nią dalej widać oś dnia.
                .presentationDetents([.fraction(1.0 / 3.0)])
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

    private func dayCard(
        shown: [MealSlot],
        pair: (earlier: MealSlot, later: MealSlot)?
    ) -> some View {
        let slots = MealSlot.allCases

        return VStack(alignment: .leading, spacing: 0) {
            // `List`, bo tylko w niej działa `swipeActions` („Wyłącz” gestem).
            // Nie przewija się: stała wysokość = wszystkie wiersze.
            List {
                ForEach(Array(slots.enumerated()), id: \.element) { index, slot in
                    axisRow(
                        slot,
                        isFirst: index == 0,
                        isLast: index == slots.count - 1,
                        isShown: shown.contains(slot),
                        warning: pair?.later == slot ? pair?.earlier : nil
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
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
            }
            .listStyle(.plain)
            .listRowSpacing(0)
            .environment(\.defaultMinListRowHeight, 0)
            .contentMargins(.vertical, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: rowHeight * CGFloat(slots.count))
            .animation(.smooth(duration: 0.22), value: configuration.enabled)

            if pair != nil {
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
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.scTileStroke(scheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.smooth(duration: 0.22), value: pair == nil)
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
                offRow(slot, isFirst: isFirst, isLast: isLast)
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
    private func offRow(_ slot: MealSlot, isFirst: Bool, isLast: Bool) -> some View {
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

            Text(slot.title)
                .font(.sc(size: 16, weight: .medium))
                .tracking(-0.2)
                .foregroundStyle(Color.scMuted(scheme))
                .lineLimit(1)
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
            action: editorAction(for: slot)
        )
    }

    /// „Wyłącz” przy włączonej porze dodatkowej, „Dodaj” przy wyłączonej,
    /// w której zostały dania. Obowiązkowe — bez akcji.
    private func editorAction(for slot: MealSlot) -> MealTimeEditorSheet.Action? {
        guard MealSlot.optionalSlots.contains(slot) else { return nil }
        let isEnabled = configuration.isEnabled(slot)
        return MealTimeEditorSheet.Action(
            title: isEnabled ? "Wyłącz" : "Dodaj",
            accessibilityLabel: isEnabled
                ? "Wyłącz \(slot.accusativeName)"
                : "Dodaj \(slot.accusativeName)",
            run: {
                toggleAfterEditor = slot
                editing = nil
            }
        )
    }

    private func runToggleAfterEditor() {
        guard let slot = toggleAfterEditor else { return }
        toggleAfterEditor = nil
        toggle(slot, to: !configuration.isEnabled(slot))
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
    private static func mealsPlural(_ count: Int) -> String {
        if count == 1 { return "posiłek" }
        let lastTwo = count % 100
        if (12...14).contains(lastTwo) { return "posiłków" }
        return (2...4).contains(count % 10) ? "posiłki" : "posiłków"
    }
}
