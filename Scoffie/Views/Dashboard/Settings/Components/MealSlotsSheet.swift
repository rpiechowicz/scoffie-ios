import SwiftUI

/// Ustawienia → „Posiłki w planie".
///
/// Odpowiada na dwa pytania po kolei: **które** posiłki gospodarstwo planuje
/// i **o której** się je. Drugie ma własny ekran, otwierany stąd — obie
/// decyzje obowiązują cały dom, ale to osobne decyzje i osobne zapisy, więc
/// mieszanie ich w jednej liście kończyło się stopką prostującą samą siebie.
/// W Ustawieniach jest jeden wiersz, bo nikt nie szuka „pór posiłków" gdzie
/// indziej niż przy „posiłkach w planie".
///
/// Trzy decyzje projektowe:
///
/// 1. **Ekran listuje trzy pozycje, nie sześć.** Śniadania, obiadu i kolacji
///    nie da się wyłączyć, więc ich wiersze były wierszami bez decyzji —
///    trzy kłódki i przypis tłumaczący, czemu nic się nie klika. Zeszły do
///    jednej karty reguły, w którą nikt nie próbuje stuknąć, bo nie wygląda
///    jak wiersz.
/// 2. **Wybór to karta, nie przełącznik przy krawędzi.** Celem dotyku jest
///    cały prostokąt, a stan niesie tło, obwódka i znacznik — nie ma
///    kontrolki o stałej szerokości, którą długość nazwy mogłaby przesunąć.
///    `Toggle` wewnątrz `Button` to zresztą loteria hit-testingu.
/// 3. **Wyłączenie nie kasuje jedzenia.** Jeśli w slocie coś stoi, pytamy
///    o potwierdzenie i mówimy wprost, że posiłki zostają. Plan pokazuje taki
///    slot mimo wyłączenia — dane nie znikają po cichu.
struct MealSlotsSheet: View {
    var onClose: () -> Void

    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.weeklyMealStore) private var mealStore
    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.colorScheme) private var scheme

    @State private var showTimes = false
    @State private var pendingDisable: MealSlot?
    @State private var errorMessage: String?
    /// Konfiguracja, której nie udało się zapisać — zasila „Spróbuj ponownie".
    /// Bez tego użytkownik musi się domyślić, że ma przestawić kartę drugi raz.
    @State private var lastFailed: MealSlotConfiguration?

    private var configuration: MealSlotConfiguration { sessionStore.mealSlots }
    private var mealTimesRowValue: String {
        let schedule = sessionStore.mealSlotSchedule
        guard !schedule.isDefault else { return "Domyślne" }

        let times = sessionStore.mealSlots.enabled.compactMap { schedule.minutes(for: $0) }
        guard let first = times.min(), let last = times.max(), first != last else {
            return "Własne"
        }
        return "\(MealSlotSchedule.format(first)) – \(MealSlotSchedule.format(last))"
    }


    var body: some View {
        // Liczone raz na przemalowanie: `plannedCount` przechodzi po całym
        // tygodniu razy liczba slotów, a wołane z każdej karty osobno robiłoby
        // tę samą robotę trzy razy.
        let counts = plannedCounts()

        return ZStack {
            WMPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EditorialSheetHeader(
                        eyebrow: "Gospodarstwo",
                        title: "Posiłki w planie",
                        onClose: onClose
                    )

                    leadSentence
                    coreRuleCard

                    VStack(alignment: .leading, spacing: 10) {
                        EditorialSheetSectionLabel(title: "Dodatkowe posiłki")

                        ForEach(MealSlot.optionalSlots) { slot in
                            optionalCard(slot, planned: counts[slot] ?? 0)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        EditorialSheetSectionLabel(title: "Rozkład dnia")

                        EditorialSettingsCardGroup {
                            EditorialSettingsRow(
                                icon: "clock.fill",
                                iconColor: WMPalette.indigo,
                                title: "Pory posiłków",
                                value: mealTimesRowValue,
                                isLast: true,
                                action: { showTimes = true }
                            )
                        }
                    }

                    introCard
                    saveStatus

                    Text("Wyłączony posiłek znika z planu, ale zaplanowane dania w nim zostają.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.wmFaint(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showTimes) {
            MealTimesSheet { showTimes = false }
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

    // MARK: - Zdanie wiodące

    /// Skład dnia jednym zdaniem z liczbą. Zastępuje dawny pasek chipów:
    /// niesie tę samą informację, a nie ma stanu, nie da się w nie stuknąć
    /// i nie ma czego zgnieść na wąskim ekranie.
    private var leadSentence: some View {
        let count = configuration.enabled.count

        return (
            Text("Dzień w planie ma teraz ")
                .foregroundStyle(Color.wmMuted(scheme))
            + Text("\(count) \(Self.mealsPlural(count))")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color.wmLabel(scheme))
            + Text(". Śniadanie, obiad i kolację jecie zawsze — resztę dokładacie tutaj.")
                .foregroundStyle(Color.wmMuted(scheme))
        )
        .font(.system(size: 13.5, weight: .regular))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    // MARK: - Reguła: trójka obowiązkowa

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
                    .foregroundStyle(Color.wmLabel(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text("Zawsze w planie — na nich stoi lista zakupów.")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(Color.wmFaint(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Posiłki dodatkowe

    private func optionalCard(_ slot: MealSlot, planned: Int) -> some View {
        let isEnabled = configuration.isEnabled(slot)

        return Button {
            toggle(slot, to: !isEnabled)
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
                        .foregroundStyle(isEnabled ? Color.wmLabel(scheme) : Color.wmMuted(scheme))

                    Text(slot.settingsSubtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.wmMuted(scheme))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Widoczne tylko wtedy, gdy jest co stracić z oczu:
                    // wyłączony slot, w którym zostało jedzenie.
                    if !isEnabled, planned > 0 {
                        Text("W tym tygodniu stoją tu \(planned) \(Self.mealsPlural(planned))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.wmFaint(scheme))
                    }
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
                            ? WMPalette.terracotta.opacity(scheme == .dark ? 0.10 : 0.07)
                            : Color.wmTileBg(scheme)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isEnabled
                            ? WMPalette.terracotta.opacity(scheme == .dark ? 0.45 : 0.36)
                            : Color.wmTileStroke(scheme),
                        lineWidth: isEnabled ? 1.4 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.20), value: isEnabled)
        .accessibilityLabel("\(slot.title). \(slot.settingsSubtitle)")
        .accessibilityAddTraits(isEnabled ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isEnabled ? "Stuknij, aby wyłączyć" : "Stuknij, aby włączyć")
    }

    /// Znacznik wyboru o stałej średnicy — świadomie **nie** `Toggle`.
    /// Przełącznik w klikalnej karcie zjadałby stuknięcia raz sobie, raz
    /// karcie, a wyjęty poza kartę odebrałby jej cel dotyku i wrócił do
    /// wiersza z kontrolką przy krawędzi.
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
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .stroke(Color.wmRule(scheme), lineWidth: 1.5)
            }
        }
        .frame(width: 26, height: 26)
    }

    // MARK: - Zasięg i stan zapisu

    private var introCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WMPalette.sage)
                .frame(width: 28, height: 28)
                .background(Circle().fill(WMPalette.sage.opacity(scheme == .dark ? 0.18 : 0.12)))

            Text("Lista posiłków jest wspólna dla całego gospodarstwa — plan tygodnia i lista zakupów są jedne dla wszystkich domowników.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.wmMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
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
                Text(errorMessage)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                if let lastFailed {
                    Button("Spróbuj ponownie") { apply(lastFailed) }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WMPalette.terracotta)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
        }
    }

    // MARK: - Akcje

    private func plannedCounts() -> [MealSlot: Int] {
        var counts: [MealSlot: Int] = [:]
        for slot in MealSlot.optionalSlots {
            counts[slot] = plannedCount(for: slot)
        }
        return counts
    }

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
                errorMessage = "Nie udało się zapisać zmiany. Sprawdź połączenie i spróbuj ponownie."
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
