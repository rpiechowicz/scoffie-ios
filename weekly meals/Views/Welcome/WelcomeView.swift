import SwiftUI

// First-login welcome flow. Four sequential pages — profile → goal →
// preferences → household — gated by a sticky footer with a pill stepper
// and primary action. Each step persists optimistically (AppStorage) and
// pushes to the backend; the household creation in step 4 also marks
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
    /// step 4 (household creation) — they can't backtrack into the
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
    @State private var weightKg: Int
    @State private var goal: UserGoal
    @State private var activity: ActivityLevel
    @State private var diet: DietPreference
    @State private var calorieGoal: Int
    @State private var allergens: Set<Allergen>
    @State private var householdName: String = ""

    // Whether the user has manually moved the kcal slider away from the
    // suggested value for the current goal. Until they do, the slider
    // tracks the goal so a user picking "schudnąć" sees the lower
    // baseline appear in step 3 without having to drag it down.
    @State private var calorieAdjustedManually: Bool = false

    private let totalSteps = 4

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

        let storedWeight = defaults.integer(forKey: "settings.profile.weightKg")
        _weightKg = State(initialValue: storedWeight > 0 ? storedWeight : 74)

        let storedGoal = defaults.string(forKey: "settings.diet.goal") ?? UserGoal.healthy.rawValue
        let resolvedGoal = UserGoal(rawValue: storedGoal) ?? .healthy
        _goal = State(initialValue: resolvedGoal)

        let storedActivityRaw = defaults.integer(forKey: "settings.diet.activityLevel")
        let storedActivity = ActivityLevel(rawValue: storedActivityRaw) ?? .light
        _activity = State(initialValue: storedActivity)

        let storedDiet = defaults.string(forKey: "settings.diet.preference") ?? DietPreference.none.rawValue
        _diet = State(initialValue: DietPreference(rawValue: storedDiet) ?? .none)

        let storedCalorieGoal = defaults.integer(forKey: "settings.diet.calorieGoal")
        let initialKcal = storedCalorieGoal > 0 ? storedCalorieGoal : resolvedGoal.suggestedCalories
        _calorieGoal = State(initialValue: initialKcal)
        _calorieAdjustedManually = State(
            initialValue: storedCalorieGoal > 0 && storedCalorieGoal != resolvedGoal.suggestedCalories
        )

        let storedAllergensRaw = defaults.string(forKey: "settings.diet.allergens") ?? ""
        let initialAllergens: Set<Allergen> = Set(
            storedAllergensRaw
                .split(separator: ",")
                .compactMap { Allergen(rawValue: String($0)) }
        )
        _allergens = State(initialValue: initialAllergens)
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
                        onBack: handleBack,
                        onNext: handleNext
                    )
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .ignoresSafeArea(.container, edges: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step > initialStep {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: handleBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.wmLabel(colorScheme))
                        }
                        .accessibilityLabel("Wstecz")
                    }
                }
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
        .onChange(of: goal) { _, newValue in
            // Keep the kcal slider in sync with the suggested target until
            // the user explicitly drags it — once they do, leave it alone.
            if !calorieAdjustedManually {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    calorieGoal = newValue.suggestedCalories
                }
            }
        }
        .onChange(of: calorieGoal) { _, newValue in
            if newValue != goal.suggestedCalories {
                calorieAdjustedManually = true
            }
        }
    }

    @ViewBuilder
    private func stepContent(for step: Int) -> some View {
        switch step {
        case 1:
            WelcomeStep1ProfileView(
                name: $name,
                yearOfBirth: $yearOfBirth,
                heightCm: $heightCm,
                weightKg: $weightKg
            )
        case 2:
            WelcomeStep2GoalView(goal: $goal, activity: $activity)
        case 3:
            WelcomeStep3PreferencesView(
                diet: $diet,
                calorieGoal: $calorieGoal,
                allergens: $allergens
            )
        default:
            WelcomeStep4HouseholdView(
                householdName: $householdName,
                firstName: trimmedName,
                avatarInitial: avatarInitial,
                errorMessage: errorMessage
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
        case 2, 3:
            return true
        case 4:
            return !householdName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        switch step {
        case 1:
            let name = trimmedName
            let year = yearOfBirth
            let height = heightCm
            let weight = weightKg
            Task { @MainActor in
                await store.saveProfile(
                    displayName: name,
                    yearOfBirth: year,
                    heightCm: height,
                    weightKg: weight
                )
            }
            advance()
        case 2, 3:
            let goalRaw = goal.rawValue
            let activityRaw = activity.rawValue
            let dietRaw = diet.rawValue
            let kcal = calorieGoal
            let allergenRaws = allergens.map(\.rawValue).sorted()
            Task { @MainActor in
                await store.saveUserPreferences(
                    diet: dietRaw,
                    calorieGoal: kcal,
                    allergens: allergenRaws,
                    goal: goalRaw,
                    activityLevel: activityRaw
                )
            }
            advance()
        case 4:
            let trimmedHousehold = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                await store.createHousehold(name: trimmedHousehold)
                if store.currentHouseholdId != nil {
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

