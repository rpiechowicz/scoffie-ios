import SwiftUI

// First-login welcome flow. Five sequential pages — profile → goal →
// preferences → meals → household — gated by a sticky footer with a pill stepper
// and primary action. Each step persists optimistically (AppStorage) and
// pushes to the backend; the household creation in step 5 also marks
// onboarding complete server-side, which routes the app into the
// dashboard via the standard `RootScreen` evaluator.
//
// Page transitions are driven by the step number — content slides in
// from the trailing edge while the previous page fades out, mirroring
// the asymmetric crossfade used at the app root level.
struct WelcomeView: View {
    let initialDisplayName: String
    let isCreatingHousehold: Bool
    let errorMessage: String?
    /// Step the flow opens at. New users start at 1 (full onboarding);
    /// already-onboarded users who lost their household land directly on
    /// step 5 (household creation) — they can't backtrack into the
    /// profile / preference steps that they already completed.
    let initialStep: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sessionStore) private var sessionStore

    // Step state — kept locally so the user can move back and tweak
    // without touching the backend until they advance.
    @State private var step: Int
    @State private var direction: Int = 1
    @State private var name: String
    @State private var yearOfBirth: Int
    @State private var heightCm: Int
    @State private var weightKg: Double
    @State private var sex: Sex?
    @State private var goal: UserGoal
    @State private var activity: ActivityLevel
    @State private var diet: DietPreference
    @State private var calorieGoal: Int
    @State private var allergens: Set<Allergen>
    /// Wartości alergenów zapisane na koncie, których ten build nie rozumie.
    /// Trzymamy je, żeby zapis z kreatora nie skasował ustawienia zrobionego
    /// na nowszej wersji aplikacji (patrz `SettingsView.unknownAllergens`).
    @State private var unknownAllergens: [String]
    /// Posiłki, które gospodarstwo planuje. Zbierane w kroku 4, wysyłane
    /// dopiero w kroku 5 — `households:updateMealTypes` potrzebuje
    /// `householdId`, który powstaje razem z gospodarstwem.
    @State private var mealSlots: MealSlotConfiguration
    @State private var householdName: String = ""

    // Whether the user has manually moved the kcal slider away from the
    // suggested value for the current goal. Until they do, the slider
    // tracks the goal so a user picking "schudnąć" sees the lower
    // baseline appear in step 3 without having to drag it down.
    @State private var calorieAdjustedManually: Bool = false

    /// Zapisy z kroków 1–3 idą w tle. Gdy któryś padnie, kreator nie
    /// zatrzymuje się (dane są w AppStorage), ale mówi o tym i ponawia
    /// przy następnym „Dalej" — wcześniej błąd wychodził dopiero w Ustawieniach.
    @State private var pendingProfileRetry = false
    @State private var pendingPreferencesRetry = false
    @State private var saveWarning: String?

    /// Krok, na którym ląduje ktoś po onboardingu bez gospodarstwa —
    /// zarazem ostatni krok pełnej ścieżki.
    ///
    /// Stała, a nie „4" wpisane w `weekly_mealsApp` — przy dokładaniu kroku
    /// posiłków ta liczba już raz się przesunęła, a rozjazd nie objawia się
    /// błędem kompilacji, tylko kreatorem, który pyta o rytm dnia kogoś,
    /// kto przyszedł tu wyłącznie założyć nowy dom.
    static let householdOnlyStep = 5

    private let totalSteps = WelcomeView.householdOnlyStep

    init(
        initialDisplayName: String,
        isCreatingHousehold: Bool,
        errorMessage: String?,
        initialStep: Int = 1
    ) {
        self.initialDisplayName = initialDisplayName
        self.isCreatingHousehold = isCreatingHousehold
        self.errorMessage = errorMessage
        self.initialStep = initialStep
        _step = State(initialValue: initialStep)

        let defaults = UserDefaults.standard

        let storedName = defaults.string(forKey: "settings.user.displayName") ?? initialDisplayName
        _name = State(initialValue: storedName.isEmpty ? initialDisplayName : storedName)

        let storedYear = defaults.integer(forKey: "settings.profile.yearOfBirth")
        _yearOfBirth = State(
            initialValue: storedYear > 0 ? storedYear : 1992
        )

        let storedHeight = defaults.integer(forKey: "settings.profile.heightCm")
        _heightCm = State(initialValue: storedHeight > 0 ? storedHeight : 178)

        let storedWeight = defaults.double(forKey: "settings.profile.weightKg")
        _weightKg = State(initialValue: storedWeight > 0 ? storedWeight : 74)

        let storedSex = defaults.string(forKey: "settings.profile.sex") ?? ""
        _sex = State(initialValue: Sex(rawValue: storedSex))

        let storedGoal = defaults.string(forKey: "settings.diet.goal") ?? UserGoal.healthy.rawValue
        let resolvedGoal = UserGoal(rawValue: storedGoal) ?? .healthy
        _goal = State(initialValue: resolvedGoal)

        let storedActivityRaw = defaults.integer(forKey: "settings.diet.activityLevel")
        let storedActivity = ActivityLevel(rawValue: storedActivityRaw) ?? .light
        _activity = State(initialValue: storedActivity)

        let storedDiet = defaults.string(forKey: "settings.diet.preference") ?? DietPreference.none.rawValue
        _diet = State(initialValue: DietPreference(rawValue: storedDiet) ?? .none)

        let storedCalorieGoal = defaults.integer(forKey: "settings.diet.calorieGoal")
        let seedMetrics = BodyMetrics(
            heightCm: storedHeight > 0 ? storedHeight : 178,
            weightKg: storedWeight > 0 ? storedWeight : 74,
            yearOfBirth: storedYear > 0 ? storedYear : 1992,
            activityRaw: storedActivity.rawValue,
            sexRaw: storedSex
        )
        let seedSuggestion = resolvedGoal.suggestedCalories(for: seedMetrics)
        let initialKcal = storedCalorieGoal > 0 ? storedCalorieGoal : seedSuggestion
        _calorieGoal = State(initialValue: initialKcal)
        _calorieAdjustedManually = State(
            initialValue: storedCalorieGoal > 0 && storedCalorieGoal != seedSuggestion
        )

        let storedAllergensRaw = defaults.string(forKey: "settings.diet.allergens") ?? ""
        let storedTokens = storedAllergensRaw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        _allergens = State(initialValue: Set(storedTokens.compactMap { Allergen(rawValue: $0) }))
        _unknownAllergens = State(
            initialValue: Array(Set(storedTokens.filter { Allergen(rawValue: $0) == nil })).sorted()
        )

        // Ten sam klucz, którym żyje `SessionStore.mealSlots` — kreator
        // przerwany w połowie i wznowiony po restarcie wraca do tego, co
        // użytkownik już zaznaczył.
        let storedSlots = defaults.string(forKey: MealSlotConfiguration.Keys.enabledSlots) ?? ""
        _mealSlots = State(
            initialValue: storedSlots.isEmpty
                ? MealSlotConfiguration.default
                : MealSlotConfiguration(storageValue: storedSlots)
        )
    }

    var body: some View {
        // NavigationStack + invisible toolbar item is the same recipe used
        // in CalendarView / ProductsView / SettingsView: SwiftUI keeps the
        // nav bar layer "live" and fades in its `.bar` blur material the
        // moment scroll content slides under the status bar. We don't have
        // a real title — `Wyloguj` lives as the only toolbar item.
        NavigationStack {
            ZStack {
                Color.wmCanvas(colorScheme)
                    .ignoresSafeArea()

                ZStack {
                    stepContent(for: step)
                        .id(step)
                        .transition(asymmetricSlide())
                }
                .animation(.easeInOut(duration: 0.34), value: step)

                VStack {
                    Spacer()
                    WelcomeFooter(
                        step: step,
                        total: totalSteps,
                        nextLabel: nextLabel,
                        isNextEnabled: isNextEnabled,
                        isLoading: isCreatingHousehold && step == totalSteps,
                        showsStepper: initialStep == 1,
                        showsBack: step > initialStep,
                        warning: saveWarning,
                        onBack: handleBack,
                        onNext: handleNext
                    )
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .ignoresSafeArea(.container, edges: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // „Wstecz" siedzi w stopce obok „Dalej" (`WelcomeFooter`),
                // tak jak w przewodniku — w pasku został tylko „Wyloguj".
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Wyloguj") {
                        sessionStore.logout()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.wmMuted(colorScheme))
                    .accessibilityHint("Powrót do ekranu logowania")
                }
            }
        }
        // Suwak kalorii podąża za podpowiedzią, dopóki użytkownik sam go nie
        // przeciągnie. Podpowiedź zależy nie tylko od celu, ale i od sylwetki
        // z kroku 1 oraz treningów z kroku 2 — stąd wspólny token zamiast
        // samego `goal`.
        .onChange(of: calorieSuggestionToken) { _, _ in
            guard !calorieAdjustedManually else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                calorieGoal = suggestedCalories
            }
        }
        .onChange(of: calorieGoal) { _, newValue in
            if newValue != suggestedCalories {
                calorieAdjustedManually = true
            }
        }
    }

    /// Sylwetka z kroków 1 i 2. `nil`, dopóki użytkownik ich nie wypełni —
    /// wtedy podpowiedź schodzi do płaskiej wartości przypisanej do celu.
    private var bodyMetrics: BodyMetrics? {
        BodyMetrics(
            heightCm: heightCm,
            weightKg: weightKg,
            yearOfBirth: yearOfBirth,
            activityRaw: activity.rawValue,
            sexRaw: sex?.rawValue ?? ""
        )
    }

    private var suggestedCalories: Int {
        goal.suggestedCalories(for: bodyMetrics)
    }

    /// Rozbicie celu na makro do podglądu w kroku 3. Ten sam rachunek, co
    /// w Ustawieniach → „Dieta i alergeny" — bez nadpisań, bo w kreatorze
    /// nie ma czym ich zrobić.
    private var macroTargets: MacroTargets? {
        bodyMetrics?.macroTargets(for: goal, calories: calorieGoal)
    }

    /// Zmienia się przy każdej danej, która wpływa na podpowiedź.
    private var calorieSuggestionToken: String {
        "\(goal.rawValue)|\(heightCm)|\(weightKg)|\(yearOfBirth)|\(activity.rawValue)|\(sex?.rawValue ?? "")"
    }

    @ViewBuilder
    private func stepContent(for step: Int) -> some View {
        switch step {
        case 1:
            WelcomeStep1ProfileView(
                name: $name,
                yearOfBirth: $yearOfBirth,
                heightCm: $heightCm,
                weightKg: $weightKg,
                sex: $sex
            )
        case 2:
            WelcomeStep2GoalView(goal: $goal, activity: $activity)
        case 3:
            WelcomeStep3PreferencesView(
                diet: $diet,
                calorieGoal: $calorieGoal,
                allergens: $allergens,
                macros: macroTargets
            )
        case 4:
            WelcomeStep4MealsView(mealSlots: $mealSlots)
        default:
            WelcomeStep4HouseholdView(
                householdName: $householdName,
                firstName: trimmedName,
                avatarInitial: avatarInitial,
                errorMessage: errorMessage,
                // Ktoś, kogo zaproszono, nie ma po co zakładać własnego
                // gospodarstwa — a bez tej listy był to jedyny widoczny sposób
                // wyjścia z tego ekranu.
                pendingInvitations: sessionStore.pendingInvitations,
                onAcceptInvitation: { token in
                    Task { await sessionStore.acceptPendingInvitation(token: token) }
                }
            )
        }
    }

    private func asymmetricSlide() -> AnyTransition {
        let slideIn: AnyTransition = direction >= 0
            ? .move(edge: .trailing).combined(with: .opacity)
            : .move(edge: .leading).combined(with: .opacity)
        let slideOut: AnyTransition = direction >= 0
            ? .move(edge: .leading).combined(with: .opacity)
            : .move(edge: .trailing).combined(with: .opacity)
        return .asymmetric(insertion: slideIn, removal: slideOut)
    }

    private var nextLabel: String {
        step == totalSteps ? "Utwórz gospodarstwo" : "Dalej"
    }

    private var isNextEnabled: Bool {
        switch step {
        case 1:
            return !trimmedName.isEmpty
                && (1900...Calendar.current.component(.year, from: Date())).contains(yearOfBirth)
                && (80...260).contains(heightCm)
                && (30...300).contains(weightKg)
        case 2, 3, 4:
            return true
        case 5:
            // Te same granice, co w Ustawieniach i na serwerze (`CreateHouseholdDto`
            // 2…64). Od Fazy 0 backend egzekwuje je także na WebSockecie —
            // 1-znakowa nazwa wracałaby jako VALIDATION_ERROR z generycznym
            // komunikatem i kreator nie dałby się dokończyć.
            return SessionStore.isValidHouseholdName(householdName)
        default:
            return true
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var avatarInitial: String {
        guard let first = trimmedName.first else { return "?" }
        return String(first).uppercased()
    }

    private func handleBack() {
        guard step > initialStep else { return }
        direction = -1
        step -= 1
    }

    private func handleNext() {
        guard isNextEnabled else { return }
        // Call SessionStore methods directly (it's a @MainActor reference
        // type pulled from Environment). Going via Sendable closure
        // arguments tripped a Swift 6 / iOS 26 ABI miscompile that
        // delivered shifted / corrupted parameter values to the closure
        // body — using the store reference avoids the indirection.
        let store = sessionStore
        retryPendingSaves(store)
        switch step {
        case 1:
            Task { @MainActor in await saveProfileStep(store) }
            advance()
        case 2, 3:
            Task { @MainActor in await savePreferencesStep(store) }
            advance()
        case 4:
            // Posiłki nie mają dokąd pójść na serwerze, dopóki nie ma
            // gospodarstwa — wybór czeka w `mealSlots` na krok 5. Lokalnie
            // zapisany od razu: zabicie aplikacji na kroku 5 nie cofa go
            // do domyślnych.
            UserDefaults.standard.set(mealSlots.storageValue, forKey: MealSlotConfiguration.Keys.enabledSlots)
            advance()
        case 5:
            let trimmedHousehold = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
            let slots = mealSlots
            Task { @MainActor in
                await store.createHousehold(name: trimmedHousehold)
                if store.currentHouseholdId != nil {
                    // Sloty PRZED domknięciem onboardingu: `completeOnboarding`
                    // przepuszcza aplikację do pulpitu, a Plan czyta wtedy
                    // konfigurację posiłków. Zapis po tej linii dorzucałby
                    // podwieczorek do już narysowanego tygodnia.
                    await store.saveMealSlotConfiguration(slots)
                    await store.completeOnboarding()
                }
            }
        default:
            break
        }
    }

    private func advance() {
        guard step < totalSteps else { return }
        direction = 1
        step += 1
    }

    // MARK: - Zapisy w tle z ponowieniem

    @MainActor
    private func saveProfileStep(_ store: SessionStore) async {
        let ok = await store.saveProfile(
            displayName: trimmedName,
            yearOfBirth: yearOfBirth,
            heightCm: heightCm,
            weightKg: weightKg,
            sex: sex?.rawValue
        )
        pendingProfileRetry = !ok
        refreshSaveWarning()
    }

    @MainActor
    private func savePreferencesStep(_ store: SessionStore) async {
        // Unia z nieznanymi — kreator nie kasuje alergenu z nowszego buildu.
        let allergenRaws = Array(Set(allergens.map(\.rawValue)).union(unknownAllergens)).sorted()
        let ok = await store.saveUserPreferences(
            diet: diet.rawValue,
            calorieGoal: calorieGoal,
            allergens: allergenRaws,
            goal: goal.rawValue,
            activityLevel: activity.rawValue
        )
        pendingPreferencesRetry = !ok
        refreshSaveWarning()
    }

    /// Nieudane zapisy wracają przy każdym kolejnym „Dalej" — bez osobnego
    /// przycisku, bo user i tak idzie do przodu.
    private func retryPendingSaves(_ store: SessionStore) {
        if pendingProfileRetry {
            Task { @MainActor in await saveProfileStep(store) }
        }
        if pendingPreferencesRetry {
            Task { @MainActor in await savePreferencesStep(store) }
        }
    }

    private func refreshSaveWarning() {
        withAnimation(.easeInOut(duration: 0.2)) {
            saveWarning = (pendingProfileRetry || pendingPreferencesRetry)
                ? "Nie udało się zapisać na serwerze — dane zostały w telefonie, spróbujemy przy następnym kroku."
                : nil
        }
    }
}

#Preview("Dark · Step 1") {
    WelcomeView(
        initialDisplayName: "Rafał",
        isCreatingHousehold: false,
        errorMessage: nil
    )
    .preferredColorScheme(.dark)
}

#Preview("Light · Step 1") {
    WelcomeView(
        initialDisplayName: "Rafał",
        isCreatingHousehold: false,
        errorMessage: nil
    )
    .preferredColorScheme(.light)
}

