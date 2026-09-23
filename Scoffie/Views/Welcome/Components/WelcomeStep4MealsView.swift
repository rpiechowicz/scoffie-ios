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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: WelcomeLayout.sectionSpacing) {
                SCStepHeader(
                    icon: "clock.fill",
                    eyebrow: "Rytm dnia",
                    title: "Ile posiłków jecie?",
                    subtitle: "Tyle miejsc dostanie każdy dzień w planie."
                )

                WelcomeSection(title: "Zawsze w planie") {
                    coreRuleCard
                }

                WelcomeSection(title: "Dodatkowe posiłki") {
                    VStack(spacing: 10) {
                        ForEach(MealSlot.optionalSlots) { slot in
                            optionalCard(slot)
                        }
                    }
                }

                WelcomeSection(title: "Pory posiłków") {
                    dayCard
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

    // MARK: - Dzień w pigułce

    /// Włączone posiłki na osi dnia — ikona w kolorze pory, godzina i nazwa.
    /// Włączenie podwieczorku wstawia go w jego miejsce dnia, a nie tylko
    /// dopisuje nazwę do zdania: dom widzi, jak będzie wyglądał każdy dzień
    /// w planie.
    ///
    /// Godziny są tu do przeczytania, nie do ustawienia. Pięć pickerów
    /// w kreatorze to pięć decyzji, których nikt na tym etapie nie umie
    /// podjąć — a domyślne pory i tak trafiają w większość domów. Zmienia
    /// się je w Ustawieniach → „Posiłki w planie”.
    private var dayCard: some View {
        let schedule = MealSlotSchedule.default

        return HStack(alignment: .top, spacing: 4) {
            ForEach(mealSlots.enabled) { slot in
                VStack(spacing: 6) {
                    Image(systemName: slot.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(slot.cozyAccent)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(slot.cozyAccent.opacity(colorScheme == .dark ? 0.16 : 0.12)))

                    Text(schedule.time(for: slot) ?? "—")
                        .font(.system(size: 13.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(colorScheme))

                    Text(slot.shortTitle)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.scFaint(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .welcomeCard()
    }
}

#Preview("Dark") {
    MealsStepPreview(configuration: .default) { slots in
        ZStack {
            SCPageBackground(scheme: .dark).ignoresSafeArea()
            WelcomeStep4MealsView(mealSlots: slots)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Light") {
    MealsStepPreview(configuration: MealSlotConfiguration(enabled: MealSlot.allCases)) { slots in
        ZStack {
            SCPageBackground(scheme: .light).ignoresSafeArea()
            WelcomeStep4MealsView(mealSlots: slots)
        }
        .preferredColorScheme(.light)
    }
}

private struct MealsStepPreview<Content: View>: View {
    @State private var configuration: MealSlotConfiguration
    let content: (Binding<MealSlotConfiguration>) -> Content

    init(
        configuration: MealSlotConfiguration,
        @ViewBuilder content: @escaping (Binding<MealSlotConfiguration>) -> Content
    ) {
        _configuration = State(initialValue: configuration)
        self.content = content
    }

    var body: some View {
        content($configuration)
    }
}
