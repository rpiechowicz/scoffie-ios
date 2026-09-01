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
            VStack(alignment: .leading, spacing: 18) {
                WelcomeStepHeader(
                    icon: "clock.fill",
                    accent: WMPalette.terracotta,
                    eyebrow: "Rytm dnia",
                    title: "Ile posiłków jecie?",
                    subtitle: "Tyle miejsc dostanie każdy dzień w planie — i tyle dań policzymy do dziennego celu."
                )

                coreRuleCard

                VStack(alignment: .leading, spacing: 8) {
                    WelcomeFieldCaption(text: "Dodatkowe posiłki")

                    VStack(spacing: 10) {
                        ForEach(MealSlot.optionalSlots) { slot in
                            optionalCard(slot)
                        }
                    }
                }

                scheduleCard
            }
            .padding(.horizontal, 24)
            .padding(.top, 140)
            .padding(.bottom, 170)
        }
    }

    // MARK: - Trójka obowiązkowa

    /// Śniadania, obiadu i kolacji nie da się wyłączyć — ta sama reguła stoi
    /// w backendzie (`normalizeEnabledMealTypes`). Trzy karty, w które nic
    /// się nie klika, byłyby zaproszeniem do stukania, więc schodzą do
    /// jednego wiersza reguły. Identycznie jak w Ustawieniach.
    private var coreRuleCard: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                ForEach(MealSlot.core) { slot in
                    EditorialSettingsTileIcon(
                        icon: slot.icon,
                        color: slot.cozyAccent,
                        size: 26,
                        radius: 8
                    )
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(MealSlot.core.map(\.title).joined(separator: " · "))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.wmLabel(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text("Zawsze w planie — na nich stoi lista zakupów.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.wmFaint(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.wmTileBg(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.wmTileStroke(colorScheme), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Posiłki dodatkowe

    private func optionalCard(_ slot: MealSlot) -> some View {
        let isEnabled = mealSlots.isEnabled(slot)

        return Button {
            withAnimation(.smooth(duration: 0.20)) {
                mealSlots = mealSlots.toggling(slot)
            }
        } label: {
            HStack(spacing: 14) {
                EditorialSettingsTileIcon(
                    icon: slot.icon,
                    color: slot.cozyAccent,
                    size: 44,
                    radius: 12
                )
                .opacity(isEnabled ? 1 : 0.45)

                VStack(alignment: .leading, spacing: 3) {
                    Text(slot.title)
                        .font(.system(size: 17, weight: .heavy))
                        .tracking(-0.3)
                        .foregroundStyle(isEnabled ? Color.wmLabel(colorScheme) : Color.wmMuted(colorScheme))

                    Text(slot.settingsSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wmMuted(colorScheme))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                selectionMark(isEnabled: isEnabled)
            }
            .padding(14)
            .frame(minHeight: 84)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isEnabled
                            ? WMPalette.terracotta.opacity(colorScheme == .dark ? 0.10 : 0.07)
                            : Color.wmTileBg(colorScheme)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isEnabled
                            ? WMPalette.terracotta.opacity(colorScheme == .dark ? 0.45 : 0.36)
                            : Color.wmTileStroke(colorScheme),
                        lineWidth: isEnabled ? 1.4 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(slot.title). \(slot.settingsSubtitle)")
        .accessibilityAddTraits(isEnabled ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isEnabled ? "Stuknij, aby wyłączyć" : "Stuknij, aby włączyć")
    }

    /// Znacznik o stałej średnicy zamiast `Toggle` — przełącznik wewnątrz
    /// klikalnej karty zjadałby stuknięcia raz sobie, raz karcie.
    private func selectionMark(isEnabled: Bool) -> some View {
        ZStack {
            if isEnabled {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [WMPalette.terracotta, WMPalette.terracotta.mix(black: 0.18)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .stroke(Color.wmFaint(colorScheme), lineWidth: 1.8)
            }
        }
        .frame(width: 24, height: 24)
    }

    // MARK: - Podgląd godzin

    /// Godziny są tu do przeczytania, nie do ustawienia. Pięć pickerów
    /// w kreatorze to pięć decyzji, których nikt na tym etapie nie umie
    /// podjąć — a domyślne pory i tak trafiają w większość domów. Wiersz
    /// mówi wprost, gdzie się je zmienia.
    private var scheduleCard: some View {
        let schedule = MealSlotSchedule.default
        let summary = mealSlots.enabled
            .compactMap { slot -> String? in
                guard let time = schedule.time(for: slot) else { return nil }
                return "\(slot.shortTitle) \(time)"
            }
            .joined(separator: " · ")

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WMPalette.indigo)
                Text("Domyślne pory")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.wmLabel(colorScheme))
            }

            Text(summary)
                .font(.system(size: 12))
                .foregroundStyle(Color.wmMuted(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            Text("Zmienisz je w Ustawieniach → Pory posiłków.")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.wmFaint(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.wmTileBg(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.wmTileStroke(colorScheme), lineWidth: 1)
        )
    }
}

#Preview("Dark") {
    MealsStepPreview(configuration: .default) { slots in
        ZStack {
            WMPalette.canvasDark.ignoresSafeArea()
            WelcomeStep4MealsView(mealSlots: slots)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Light") {
    MealsStepPreview(configuration: MealSlotConfiguration(enabled: MealSlot.allCases)) { slots in
        ZStack {
            WMPalette.canvasLight.ignoresSafeArea()
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
