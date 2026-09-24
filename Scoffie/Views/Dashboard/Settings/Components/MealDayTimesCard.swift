import SwiftUI

/// „Pory posiłków” — dzień w pigułce: posiłki na osi dnia, każdy z ikoną
/// w kolorze pory, godziną i krótką nazwą. Stuknięcie w posiłek otwiera
/// koło godzin w małym arkuszu do połowy ekranu.
///
/// Jeden widok w dwóch miejscach: krok 4 kreatora i Ustawienia → „Posiłki
/// w planie”. Dawniej kreator pokazywał godziny tylko do przeczytania,
/// a Ustawienia miały osobny arkusz z listą wierszy (`MealTimesSheet`) —
/// Rafałowi (24.09.2026) podobała się oś z kreatora, ale nie dało się na niej
/// nic ustawić. Teraz oś jest jedna i w obu miejscach działa tak samo.
///
/// Widok niczego nie zapisuje: dostaje rozkład i oddaje zmianę pory
/// (`onSetTime`). Kreator trzyma ją lokalnie do utworzenia gospodarstwa,
/// Ustawienia zapisują od razu (`SessionStore.saveMealSlotSchedule`).
struct MealDayTimesCard: View {
    /// Posiłki na osi, w kolejności dnia.
    let slots: [MealSlot]
    let schedule: MealSlotSchedule
    /// Posiłki widoczne w planie, choć wyłączone (zostały w nich dania) —
    /// rysowane przygaszone, ale dalej do ustawienia.
    var dimmed: Set<MealSlot> = []
    /// Nowa pora posiłku w minutach od północy; `nil` = bez stałej pory
    /// (tylko tam, gdzie pozwala `MealSlotSchedule.slotsRequiringTime`).
    let onSetTime: (MealSlot, Int?) -> Void

    @Environment(\.colorScheme) private var scheme

    @State private var editing: MealSlot?

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            ForEach(slots) { slot in
                column(slot)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.scTileStroke(scheme), lineWidth: 1)
        )
        // Koło godzin we własnym arkuszu, nie w karcie: `DatePicker(.wheel)`
        // przejmuje pionowe przeciągnięcia i w przewijanej treści zjadał
        // przewijanie oraz gest zamknięcia arkusza.
        .sheet(item: $editing) { slot in
            MealTimeEditorSheet(
                slot: slot,
                minutes: schedule.minutes(for: slot),
                onPick: { picked in
                    guard picked != schedule.minutes(for: slot) else { return }
                    onSetTime(slot, picked)
                },
                onClearTime: {
                    editing = nil
                    onSetTime(slot, nil)
                },
                onClose: { editing = nil }
            )
            .presentationDetents([.medium])
            .dashboardLiquidSheet(cornerRadius: 26)
        }
    }

    private func column(_ slot: MealSlot) -> some View {
        let isDimmed = dimmed.contains(slot)
        let time = schedule.time(for: slot)

        return Button {
            editing = slot
        } label: {
            VStack(spacing: 6) {
                Image(systemName: slot.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(slot.cozyAccent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(slot.cozyAccent.opacity(scheme == .dark ? 0.16 : 0.12)))

                // Godzina na kapsułce pola — jedyny znak, że w oś da się
                // stuknąć, bez szewronów i podpisów.
                Text(time ?? "—")
                    .font(.system(size: 13.5, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(time == nil ? Color.scFaint(scheme) : Color.scLabel(scheme))
                    .contentTransition(.numericText())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule(style: .continuous).fill(Color.scChipBg(scheme)))

                Text(slot.shortTitle)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.scFaint(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .opacity(isDimmed ? 0.5 : 1)
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .animation(.smooth(duration: 0.22), value: time)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(slot.title), \(time ?? "bez stałej pory")")
        .accessibilityHint("Stuknij, aby zmienić porę")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Ostrzeżenie o kolejności

/// Kolejność posiłków w planie jest stała — godziny jej nie przestawiają.
/// Użytkownik ma się o tym dowiedzieć od nas, a nie ze zdziwienia nad
/// ekranem Planu.
struct MealTimesOrderNotice: View {
    let slots: [MealSlot]
    let schedule: MealSlotSchedule

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let pair = schedule.outOfOrderPair(among: slots) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SCPalette.terracotta)

                Text(text(pair))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
        }
    }

    private func text(_ pair: (earlier: MealSlot, later: MealSlot)) -> String {
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

/// Koło godzin dla jednego posiłku, we własnym arkuszu do połowy ekranu.
///
/// Powód istnienia tego widoku jako osobnego arkusza: `DatePicker(.wheel)`
/// przejmuje pionowe przeciągnięcia w swoim obszarze i **nie da się** tego
/// wyłączyć. Wstawione w `ScrollView` zjadało przewijanie listy i gest
/// zamknięcia arkusza. Tutaj nic nie przewija się pod spodem, więc koło może
/// sobie łapać wszystko, co chce — a arkusz zamyka się uchwytem, krzyżykiem
/// albo stuknięciem w tło.
///
/// Godzina zapisuje się sama przy każdym obrocie koła (`onPick`), więc nie
/// ma czego zatwierdzać: zamyka się krzyżykiem, jak każdy arkusz, a nie
/// przyciskiem „Gotowe”, który udawał zapis.
private struct MealTimeEditorSheet: View {
    let slot: MealSlot
    let minutes: Int?
    let onPick: (Int) -> Void
    let onClearTime: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var scheme

    /// Kopia lokalna: koło pisze tu na każdą klatkę przeciągnięcia,
    /// a dalej idzie dopiero wartość różna od zapisanej.
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
                EditorialSheetHeader(
                    eyebrow: "Pora posiłku",
                    title: slot.title,
                    icon: slot.icon,
                    accent: slot.cozyAccent,
                    onClose: onClose
                )
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 4)

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
}
