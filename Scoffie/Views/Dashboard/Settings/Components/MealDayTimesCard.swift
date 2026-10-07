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
            // Jedna trzecia ekranu (Rafał 4.10.2026: „lepiej będzie wyglądać”) —
            // kompaktowy nagłówek i niższe koło godzin mieszczą się w niej.
            .presentationDetents([.fraction(1.0 / 3.0)])
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
                    .font(.sc(size: 14, weight: .semibold))
                    .foregroundStyle(slot.cozyAccent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(slot.cozyAccent.opacity(scheme == .dark ? 0.16 : 0.12)))

                // Godzina na kapsułce pola — jedyny znak, że w oś da się
                // stuknąć, bez szewronów i podpisów.
                Text(time ?? "—")
                    .font(.sc(size: 13.5, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(time == nil ? Color.scFaint(scheme) : Color.scLabel(scheme))
                    .contentTransition(.numericText())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule(style: .continuous).fill(Color.scChipBg(scheme)))

                Text(slot.shortTitle)
                    .font(.sc(size: 10.5, weight: .semibold))
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
