import SwiftUI

/// Ustawienia → Integracje → „Zdrowie".
///
/// Jeden arkusz na cały flow kroków: wybór źródła (Apple Zdrowie ALBO Garmin —
/// nigdy oba, bo Garmin Connect dopisuje kroki do Zdrowia obok próbek iPhone'a
/// i suma liczyłaby je podwójnie), połączenie z HealthKit, cel kroków
/// i wyłączenie. Garmin też idzie przez HealthKit — systemowa zgoda na odczyt
/// jest potrzebna dla obu opcji.
struct HealthIntegrationSheet: View {
    var onClose: () -> Void

    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.colorScheme) private var scheme

    @AppStorage(HealthStepsStore.Keys.enabled) private var stepsEnabled: Bool = false
    @AppStorage(HealthStepsStore.Keys.stepsGoal) private var stepsGoal: Int = HealthStepsStore.defaultStepsGoal

    @State private var selectedSource: StepsSource = .appleHealth
    @State private var errorMessage: String?
    @State private var showDisableAlert = false

    // Zakres celu kroków: 2000 to dolna sensowna granica aktywności, 40 000
    // mieści maratończyków; krok 500 trzyma suwak namacalnym jak przy kcal.
    private static let stepsGoalMin = 2_000
    private static let stepsGoalMax = 40_000
    private static let stepsGoalStep = 500

    private var store: HealthStepsStore? { sessionStore.healthStepsStore }

    var body: some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    EditorialSheetHeader(
                        eyebrow: "Integracje",
                        title: "Zdrowie",
                        onClose: onClose
                    )

                    if !HealthKitService.isAvailable {
                        unavailableCard
                    } else if stepsEnabled {
                        connectedCard
                        sourcePicker
                        emptyWindowHintCard
                        goalSection
                        disableButton
                    } else {
                        introCard
                        sourcePicker
                        connectSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .task {
            selectedSource = store?.source ?? .appleHealth
            await store?.refreshAndSync()
        }
        .onDisappear {
            // Zmiana celu suwakiem nie wysyła nic na bieżąco (PUT przy każdym
            // ticku suwaka to spam) — domykamy ją jednym syncem przy zamknięciu.
            if let store {
                Task { @MainActor in
                    await store.syncNow()
                }
            }
        }
        .alert("Wyłączyć integrację?", isPresented: $showDisableAlert) {
            Button("Anuluj", role: .cancel) {}
            Button("Wyłącz", role: .destructive) {
                store?.disable()
            }
        } message: {
            Text("Pasek kroków zniknie z Kalendarza, a synchronizacja się zatrzyma. Zapisane dni zostają w statystykach, a uprawnienia w Zdrowiu możesz cofnąć w Ustawieniach systemu.")
        }
    }

    // MARK: - Stan: niepołączono

    private var introCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "figure.walk")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SCPalette.terracotta)
                .frame(width: 28, height: 28)
                .background(Circle().fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.18 : 0.12)))

            Text("Połącz aplikację ze Zdrowiem, aby widzieć dzienne kroki w Kalendarzu pod kaloriami i zbierać statystyki aktywności. Kroki są tylko odczytywane — aplikacja niczego nie zapisuje do Zdrowia.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.scMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }

    private var connectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage {
                SCInlineErrorText(errorMessage)
                    .padding(.horizontal, 6)
            }

            EditorialPrimaryActionButton(
                title: "Połącz ze Zdrowiem",
                icon: "heart.fill",
                isEnabled: true,
                isLoading: store?.isBusy ?? false
            ) {
                submitEnable()
            }
            .padding(.top, 4)

            Text("iOS zapyta o zgodę na odczyt kroków. Zgodą zarządzasz potem w Ustawienia → Prywatność i bezpieczeństwo → Zdrowie.")
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(Color.scFaint(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
        }
    }

    private func submitEnable() {
        errorMessage = nil
        Task { @MainActor in
            errorMessage = await store?.enable(source: selectedSource)
        }
    }

    // MARK: - Wybór źródła

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSheetSectionLabel(title: "Źródło kroków")

            HStack(spacing: 10) {
                sourceCard(
                    .appleHealth,
                    icon: "heart.fill",
                    title: "Apple Zdrowie",
                    subtitle: "iPhone i Apple Watch"
                )
                sourceCard(
                    .garmin,
                    icon: "applewatch",
                    title: "Garmin",
                    subtitle: "Przez Garmin Connect"
                )
            }

            if selectedSource == .garmin {
                garminHowToCard
            }
        }
    }

    private func sourceCard(
        _ source: StepsSource,
        icon: String,
        title: String,
        subtitle: String
    ) -> some View {
        let isSelected = selectedSource == source
        return Button {
            selectSource(source)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Źródło jest jedno („nigdy oba” — patrz opis arkusza),
                // więc wybór pokazuje kółko `SCRadioMark`, jak kafle planów.
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? SCPalette.terracotta : Color.scMuted(scheme))

                    Spacer(minLength: 0)

                    SCRadioMark(isOn: isSelected, size: 18)
                }

                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .scChoiceSurface(
                RoundedRectangle(cornerRadius: 14, style: .continuous),
                isOn: isSelected,
                offFill: Color.scTileBg(scheme),
                style: .tile
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectSource(_ source: StepsSource) {
        guard selectedSource != source else { return }
        selectedSource = source
        // Przy działającej integracji przełączenie od razu czyta okno na nowo
        // i re-syncuje — backend nadpisze wiersze nowym źródłem.
        if stepsEnabled {
            Task { @MainActor in
                await store?.setSource(source)
            }
        }
    }

    private var garminHowToCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SCPalette.sage)

            Text("Kroki z Garmina czytamy przez Zdrowie. W aplikacji Garmin Connect włącz zapisywanie kroków do Apple Health: Więcej → Ustawienia → Zdrowie użytkownika → Apple Health.")
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(Color.scMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SCPalette.sage.opacity(scheme == .dark ? 0.10 : 0.07))
        )
    }

    // MARK: - Stan: połączono

    private var connectedCard: some View {
        HStack(spacing: 14) {
            EditorialSettingsTileIcon(
                icon: "checkmark",
                color: SCPalette.sage,
                size: 44,
                radius: 12
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("Połączono ze Zdrowiem")
                    .font(.system(size: 15.5, weight: .heavy))
                    .foregroundStyle(Color.scLabel(scheme))

                if let todaySteps = store?.todaySteps {
                    Text("Dzisiaj: \(todaySteps) kroków")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.scMuted(scheme))
                } else if let since = store?.enabledAtKey {
                    Text("Synchronizacja od \(since)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.scMuted(scheme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SCPalette.sage.opacity(scheme == .dark ? 0.10 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SCPalette.sage.opacity(scheme == .dark ? 0.45 : 0.36), lineWidth: 1.4)
        )
        .accessibilityElement(children: .combine)
    }

    /// Odmowy odczytu w Zdrowiu nie da się sprawdzić programowo — jedyny
    /// sygnał to puste okno mimo włączonej integracji. Treść podpowiedzi
    /// zależy od źródła: przy Garminie częstszym winowajcą jest brak syncu
    /// w Garmin Connect niż uprawnienia.
    @ViewBuilder
    private var emptyWindowHintCard: some View {
        if store?.lastWindowWasEmpty == true {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SCPalette.butter)

                Text(selectedSource == .garmin
                    ? "Zdrowie nie zwraca żadnych kroków z Garmina. Upewnij się, że Garmin Connect zapisuje kroki do Apple Health i że zegarek się zsynchronizował."
                    : "Zdrowie nie zwraca żadnych kroków. Jeśli licznik stoi pusty, sprawdź Ustawienia → Prywatność i bezpieczeństwo → Zdrowie → Scoffie i włącz odczyt Kroków.")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(SCPalette.butter.opacity(scheme == .dark ? 0.12 : 0.10))
            )
        }
    }

    // MARK: - Cel kroków

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Cel kroków")

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 14) {
                    EditorialSettingsTileIcon(icon: "figure.walk", color: SCPalette.terracotta)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dzienny cel")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.scLabel(scheme))
                        Text("Pasek w Kalendarzu pokazuje postęp względem tej liczby.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.scMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                goalEditor
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
        }
    }

    /// Duży animowany odczyt nad suwakiem z krokiem 500 — ten sam idiom, co
    /// edytor celu kalorycznego w Ustawieniach.
    private var goalEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(stepsGoal, format: .number.grouping(.never))
                    .font(.system(size: 44, weight: .heavy))
                    .tracking(-1.4)
                    .foregroundStyle(SCPalette.terracotta)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(stepsGoal)))

                Text("kroków / dzień")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.18), value: stepsGoal)

            VStack(spacing: 6) {
                Slider(
                    value: Binding(
                        get: { Double(stepsGoal) },
                        set: { stepsGoal = Self.snappedStepsGoal(from: $0) }
                    ),
                    in: Double(Self.stepsGoalMin)...Double(Self.stepsGoalMax),
                    step: Double(Self.stepsGoalStep)
                )
                .tint(SCPalette.terracotta)

                HStack {
                    Text("\(Self.stepsGoalMin)")
                    Spacer()
                    Text("\(Self.stepsGoalMax)")
                }
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.scFaint(scheme))
            }
        }
    }

    private static func snappedStepsGoal(from raw: Double) -> Int {
        let stepped = (raw / Double(stepsGoalStep)).rounded() * Double(stepsGoalStep)
        return min(max(Int(stepped), stepsGoalMin), stepsGoalMax)
    }

    // MARK: - Wyłączenie

    private var disableButton: some View {
        SCDestructiveButton(
            title: "Wyłącz integrację",
            icon: "link.badge.plus",
            iconRotation: .degrees(45)
        ) {
            showDisableAlert = true
        }
        .padding(.top, 8)
    }

    // MARK: - Brak Zdrowia (iPad)

    private var unavailableCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "heart.slash.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.scFaint(scheme))

            Text("Zdrowie nie jest dostępne na tym urządzeniu.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.scMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }
}
