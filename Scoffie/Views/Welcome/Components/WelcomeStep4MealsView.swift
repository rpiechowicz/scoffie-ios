import SwiftUI

/// Kreator, krok 4 — które posiłki gospodarstwo planuje.
///
/// Ustawienie żyło dotąd wyłącznie w Ustawieniach → „Posiłki w planie",
/// więc każdy nowy dom zaczynał od trójki domyślnej i dowiadywał się
/// o podwieczorku dopiero wtedy, gdy zaczął go szukać w planie. Tutaj
/// pytanie pada raz, w miejscu, w którym i tak zbieramy resztę.
///
/// Wybór jedzie na serwer dopiero po utworzeniu gospodarstwa w kroku 5 —
/// `households:updateMealTypes` potrzebuje `householdId`, którego na tym
/// ekranie jeszcze nie ma.
struct WelcomeStep4MealsView: View {
    @Binding var mealSlots: MealSlotConfiguration
    /// Godziny posiłków — jak `mealSlots` czekają na gospodarstwo z kroku 5.
    @Binding var mealSchedule: MealSlotSchedule

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: WelcomeLayout.sectionSpacing) {
                SCStepHeader(
                    icon: "clock.fill",
                    eyebrow: "Rytm dnia",
                    title: "Ile posiłków jecie?",
                    subtitle: "Każdy dzień w planie dostanie tyle miejsc na dania, ile tu zaznaczysz. Godziny przydadzą się w Kalendarzu i przy przypomnieniach."
                )

                WelcomeSection(title: "Zawsze w planie", hint: "Te trzy są podstawą każdego dnia.") {
                    coreRuleCard
                }

                WelcomeSection(title: "Dodatkowe posiłki", hint: "Zaznacz, jeśli zdarza Ci się jeść coś między głównymi posiłkami.") {
                    VStack(spacing: 10) {
                        ForEach(MealSlot.optionalSlots) { slot in
                            optionalCard(slot)
                        }
                    }
                }

                // Ta sama oś co w Ustawieniach → „Posiłki w planie”:
                // stuknięcie w posiłek otwiera koło godzin do połowy ekranu.
                WelcomeSection(title: "Pory posiłków", hint: "Stuknij w posiłek, żeby zmienić godzinę.") {
                    MealDayTimesCard(
                        slots: mealSlots.enabled,
                        schedule: mealSchedule,
                        onSetTime: { slot, minutes in
                            mealSchedule = mealSchedule.setting(slot, toMinutes: minutes)
                        }
                    )
                }
            }
            .padding(.horizontal, WelcomeLayout.horizontal)
            .padding(.top, WelcomeLayout.topInset)
            .padding(.bottom, WelcomeLayout.bottomInset)
        }
    }

    // MARK: - Trójka obowiązkowa

    /// Śniadania, obiadu i kolacji nie da się wyłączyć — ta sama reguła stoi
    /// w backendzie (`normalizeEnabledMealTypes`). Trzy karty, w które nic
    /// się nie klika, byłyby zaproszeniem do stukania, więc schodzą do
    /// jednego wiersza. Identycznie jak w Ustawieniach.
    private var coreRuleCard: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                ForEach(MealSlot.core) { slot in
                    EditorialSettingsTileIcon(
                        icon: slot.icon,
                        color: slot.cozyAccent,
                        size: 28,
                        radius: 8
                    )
                }
            }

            Text(MealSlot.core.map(\.title).joined(separator: " · "))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.scLabel(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .welcomeCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Posiłki dodatkowe

    private func optionalCard(_ slot: MealSlot) -> some View {
        let isEnabled = mealSlots.isEnabled(slot)

        return Button {
            withAnimation(.smooth(duration: 0.24)) {
                mealSlots = mealSlots.toggling(slot)
            }
        } label: {
            HStack(spacing: 14) {
                EditorialSettingsTileIcon(
                    icon: slot.icon,
                    color: slot.cozyAccent,
                    size: 40,
                    radius: 11
                )
                .opacity(isEnabled ? 1 : 0.45)

                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isEnabled ? Color.scLabel(colorScheme) : Color.scMuted(colorScheme))

                    Text(slot.settingsSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.scMuted(colorScheme))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Pole wyboru, jak w Ustawieniach → „Posiłki w planie”:
                // posiłków włącza się dowolnie wiele, a „wiele z wielu” to
                // w aplikacji `SCCheckbox`. Świadomie nie `Toggle` —
                // przełącznik w klikalnej karcie zjadałby stuknięcia raz
                // sobie, raz karcie.
                SCCheckbox(on: isEnabled, accent: SCPalette.terracotta)
            }
            .padding(14)
            .frame(minHeight: 76)
            // Włączona karta jak zaznaczony `SCChoiceTile`: tint i obwódka
            // akcentu.
            .scChoiceSurface(
                RoundedRectangle(cornerRadius: WelcomeLayout.cardRadius, style: .continuous),
                isOn: isEnabled,
                offFill: Color.scTileBg(colorScheme),
                style: .tile
            )
            .contentShape(RoundedRectangle(cornerRadius: WelcomeLayout.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(slot.title). \(slot.settingsSubtitle)")
        .accessibilityAddTraits(isEnabled ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isEnabled ? "Stuknij, aby wyłączyć" : "Stuknij, aby włączyć")
    }
}

#Preview("Dark") {
    MealsStepPreview(configuration: .default) { slots, schedule in
        ZStack {
            SCPageBackground(scheme: .dark).ignoresSafeArea()
            WelcomeStep4MealsView(mealSlots: slots, mealSchedule: schedule)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Light") {
    MealsStepPreview(configuration: MealSlotConfiguration(enabled: MealSlot.allCases)) { slots, schedule in
        ZStack {
            SCPageBackground(scheme: .light).ignoresSafeArea()
            WelcomeStep4MealsView(mealSlots: slots, mealSchedule: schedule)
        }
        .preferredColorScheme(.light)
    }
}

private struct MealsStepPreview<Content: View>: View {
    @State private var configuration: MealSlotConfiguration
    @State private var schedule: MealSlotSchedule = .default
    let content: (Binding<MealSlotConfiguration>, Binding<MealSlotSchedule>) -> Content

    init(
        configuration: MealSlotConfiguration,
        @ViewBuilder content: @escaping (Binding<MealSlotConfiguration>, Binding<MealSlotSchedule>) -> Content
    ) {
        _configuration = State(initialValue: configuration)
        self.content = content
    }

    var body: some View {
        content($configuration, $schedule)
    }
}
