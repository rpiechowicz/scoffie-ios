import SwiftUI

// First-login welcome flow. Od 24.09.2026 JEDEN przepływ z przewodnikiem
// „Poznaj aplikację” na początku (Rafał: „daj to wszystko w jednym wielkim
// stepperze, aby nie przełączać”): powitanie → 5 kroków przewodnika →
// „Teraz my poznajmy Ciebie” → 5 kroków kreatora, jedna stopka, jeden pasek
// kroków (11 odcinków), strony jadą na bok bez przenikania między dwoma
// ekranami. Dawniej `WelcomeFlowView` przenikał `FeatureTourView` w ten widok
// i pasek „1/5” zaczynał się od nowa.
//
// Kreator: five sequential pages — profile → goal →
// preferences → meals → household — gated by the shared step footer
// (`SCStepFooter`: pasek kroków, „Wstecz”, akcja główna na płycie
// `SCSheetFooter` z cieniem krawędzi). Each step persists optimistically (AppStorage) and
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

    /// Faza przewodnika przed kreatorem: 0 = powitanie, 1…5 = kroki,
    /// 6 = „Teraz my poznajmy Ciebie”. `nil` = jesteśmy w kreatorze (`step`).
    @State private var tourPhase: Int?
    @AppStorage(TourCompletion.storageKey) private var tourCompleted: Bool = false
    /// Wysokość płyty stopki — strony przewodnika kończą się nad nią
    /// (`TourPage` mierzy widoczną stronę pod sufit zdjęcia), a kroki
    /// kreatora mają własny zapas (`WelcomeLayout.bottomInset`).
    @State private var footerHeight: CGFloat = 150

    private let tourSteps = TourStep.all
    private var tourDonePhase: Int { tourSteps.count + 1 }

    // Step state — kept locally so the user can move back and tweak
    // without touching the backend until they advance.
    @State private var step: Int
    @State private var direction: Int = 1
    @State private var name: String
    // Odpowiedzi wymagane (7.10.2026, Rafał: „wymuszanie, aby user podał dane
    // wszystkie”): to, czego użytkownik jeszcze nie podał, jest `nil`, a nie
    // wartością domyślną — „Dalej” czeka (`isNextEnabled`), a zapis niczego
    // nie wysyła za niego. Rok to wyjątek: koło zawsze stoi na jakimś roku,
    // więc „brak” = bieżący rok (wiek 0) poza `ageRange`.
    @State private var yearOfBirth: Int
    @State private var heightCm: Int?
    @State private var weightKg: Double?
    @State private var sex: Sex?
    /// „Nie podaję” — płeć to wymagana ODPOWIEDŹ, nie wymagana płeć.
    @State private var sexDeclined: Bool
    /// „Nie podaję” stuknięte w tym kreatorze — dopiero wtedy zapis kasuje
    /// płeć na serwerze (`saveProfile(clearSex:)`), jak `clearsSex`
    /// w „Twoich danych”. Odtworzone przy wznowieniu niczego nie kasuje.
    @State private var clearsSex = false
    @State private var goal: UserGoal?
    @State private var activity: ActivityLevel?
    @State private var diet: DietPreference?
    /// Ostatni krok zaliczony „Dalej” (`WelcomeDraft.answeredStep`). Cel,
    /// aktywność i dieta są w magazynie zawsze — start sesji wpisuje tam
    /// domyślny wiersz serwera — więc „podane” znaczy tu „zaliczone w kreatorze”.
    @State private var answeredStep: Int
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
    /// Godziny posiłków z kroku 4 — tak jak `mealSlots` jadą na serwer
    /// dopiero razem z gospodarstwem (`households:updateMealTimes`).
    @State private var mealSchedule: MealSlotSchedule
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
    /// Stała, a nie „4" wpisane w `ScoffieApp` — przy dokładaniu kroku
    /// posiłków ta liczba już raz się przesunęła, a rozjazd nie objawia się
    /// błędem kompilacji, tylko kreatorem, który pyta o rytm dnia kogoś,
    /// kto przyszedł tu wyłącznie założyć nowy dom.
    static let householdOnlyStep = 5

    private let totalSteps = WelcomeView.householdOnlyStep

    init(
        initialDisplayName: String,
        isCreatingHousehold: Bool,
        errorMessage: String?,
        initialStep: Int = 1,
        showsTour: Bool = false,
        /// Tylko do zrzutów (`SCOFFIE_DEBUG_OPTIONS=tour-N`): faza, od której
        /// startuje przewodnik.
        startTourPhase: Int = 0
    ) {
        self.initialDisplayName = initialDisplayName
        self.isCreatingHousehold = isCreatingHousehold
        self.errorMessage = errorMessage
        self.initialStep = initialStep
        _step = State(initialValue: initialStep)
        // Przewodnik tylko na pełnej ścieżce — kto wraca po nowe
        // gospodarstwo, aplikację zna.
        _tourPhase = State(initialValue: showsTour && initialStep == 1 ? startTourPhase : nil)

        let defaults = UserDefaults.standard
        // Profil, cel i dieta z chronionego magazynu (7.10.2026); `defaults`
        // zostaje dla `auth.userId` i pór posiłków niżej.
        let protectedStore = SCProtectedSettings.shared

        // Szkic kreatora (7.10.2026, Codex): odpowiedzi z kroków zaliczonych
        // „Dalej”, zapisane synchronicznie RAZEM z numerem kroku. Wznowienie
        // czyta szkic, nie kopię profilu i preferencji — zapis na serwer idzie
        // w tle przez kolejkę i po zabiciu aplikacji kopia mogła zostać starsza
        // niż to, co użytkownik zatwierdził (a cel, aktywność i dieta są
        // w kopii zawsze — start sesji wpisuje tam domyślny wiersz serwera).
        let draft = WelcomeDraft.load(forUserId: defaults.string(forKey: "auth.userId"))
        let answered = draft?.answeredStep ?? 0
        _answeredStep = State(initialValue: answered)

        let storedName = protectedStore.string(forKey: "settings.user.displayName") ?? initialDisplayName
        let resolvedName = draft.map(\.name) ?? storedName
        _name = State(initialValue: resolvedName.isEmpty ? initialDisplayName : resolvedName)

        // Sylwetka: ze szkicu, a bez niego z kopii — tam leży tylko to, co
        // konto naprawdę ma (nowe konto: pusto, serwer trzyma `null`).
        let currentYear = Calendar.current.component(.year, from: Date())
        let resolvedYear: Int
        let resolvedHeight: Int?
        let resolvedWeight: Double?
        let resolvedSex: Sex?
        let resolvedSexDeclined: Bool
        if let draft {
            resolvedYear = draft.yearOfBirth ?? currentYear
            resolvedHeight = draft.heightCm
            resolvedWeight = draft.weightKg
            resolvedSex = draft.sex.flatMap { Sex(rawValue: $0) }
            resolvedSexDeclined = resolvedSex == nil && draft.sexDeclined
        } else {
            let storedYear = protectedStore.integer(forKey: "settings.profile.yearOfBirth")
            let storedHeight = protectedStore.integer(forKey: "settings.profile.heightCm")
            let storedWeight = protectedStore.double(forKey: "settings.profile.weightKg")
            resolvedYear = storedYear > 0 ? storedYear : currentYear
            resolvedHeight = storedHeight > 0 ? storedHeight : nil
            resolvedWeight = storedWeight > 0 ? storedWeight : nil
            resolvedSex = Sex(rawValue: protectedStore.string(forKey: "settings.profile.sex") ?? "")
            resolvedSexDeclined = false
        }
        _yearOfBirth = State(initialValue: resolvedYear)
        _heightCm = State(initialValue: resolvedHeight)
        _weightKg = State(initialValue: resolvedWeight)
        _sex = State(initialValue: resolvedSex)
        _sexDeclined = State(initialValue: resolvedSexDeclined)

        // Cel, aktywność i dieta — wyłącznie z zaliczonego kroku w szkicu.
        let resolvedGoal: UserGoal? = answered >= 2
            ? draft?.goal.flatMap { UserGoal(rawValue: $0) }
            : nil
        _goal = State(initialValue: resolvedGoal)

        let resolvedActivity: ActivityLevel? = answered >= 2
            ? draft?.activityLevel.flatMap { ActivityLevel(rawValue: $0) }
            : nil
        _activity = State(initialValue: resolvedActivity)

        let resolvedDiet: DietPreference? = answered >= 3
            ? draft?.diet.flatMap { DietPreference(rawValue: $0) }
            : nil
        _diet = State(initialValue: resolvedDiet)

        // Kalorie: ręcznie przesunięte są w szkicu; inaczej podpowiedź z tych
        // samych danych, z których liczy ją `bodyMetrics` w trakcie — bez celu
        // nie ma podpowiedzi, a kalorie ustawią się same przy wyborze celu
        // (`calorieSuggestionToken`).
        let draftKcal: Int? = answered >= 2 ? draft?.calorieGoal : nil
        let seedMetrics: BodyMetrics? = {
            guard let resolvedHeight, let resolvedWeight, let resolvedActivity else { return nil }
            return BodyMetrics(
                heightCm: resolvedHeight,
                weightKg: resolvedWeight,
                yearOfBirth: resolvedYear,
                activityRaw: resolvedActivity.rawValue,
                sexRaw: resolvedSex?.rawValue ?? ""
            )
        }()
        let seedSuggestion: Int? = resolvedGoal?.suggestedCalories(for: seedMetrics)
        _calorieGoal = State(
            initialValue: draftKcal ?? seedSuggestion ?? UserGoal.healthy.suggestedCalories
        )
        _calorieAdjustedManually = State(initialValue: draftKcal != nil)

        // Alergeny: z zaliczonego kroku 3 w szkicu; wcześniej z kopii (to, co
        // konto już ma, zaznaczone na start — jak dotąd).
        let storedTokens: [String]
        if answered >= 3, let draftAllergens = draft?.allergens {
            storedTokens = draftAllergens
        } else {
            storedTokens = (protectedStore.string(forKey: "settings.diet.allergens") ?? "")
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
        }
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
        // Godziny — ten sam klucz co `SessionStore.mealSlotSchedule`; pusty
        // daje rozkład domyślny (braki uzupełnia `MealSlotSchedule`).
        _mealSchedule = State(
            initialValue: MealSlotSchedule(
                storageValue: defaults.string(forKey: MealSlotSchedule.Keys.times) ?? ""
            )
        )
    }

    var body: some View {
        // Bez `NavigationStack` i paska nawigacji (24.09.2026, Rafał: „button
        // wyloguj wywal”, „header od samej góry tak jak wszystkie”): pasek
        // trzymał tylko „Wyloguj” i spychał treść 132 pt w dół. Krok zaczyna
        // się tam, gdzie strona przewodnika, a górny brzeg treści gaśnie pod
        // paskiem statusu (`scScrollEdgeFade` w każdym kroku).
        ZStack {
            // To samo tło, co przewodnik przed kreatorem i każdy ekran
            // aplikacji — przejście przewodnik → kreator nie zmienia koloru,
            // a płyta stopki (`scPageBase`) zlewa się z dołem strony.
            SCPageBackground(scheme: colorScheme)
                .ignoresSafeArea()

            ZStack {
                pageContent
                    .id(pageKey)
                    .transition(asymmetricSlide())
            }
            .animation(.easeInOut(duration: 0.34), value: pageKey)

            // Stopka jako nakładka, nie ostatnie dziecko `VStack`: stoi pod
            // klawiaturą (`ignoresSafeArea(.keyboard)`), a kroki z polami
            // dalej przewijają się nad klawiaturą. Zapas pod treścią to
            // `WelcomeLayout.bottomInset` (stopka + jej cień).
            VStack {
                Spacer()
                SCStepFooter(
                    slot: footerSlot,
                    onSlotTap: { skipTour() },
                    notice: tourPhase == nil ? saveWarning : nil,
                    showsBack: canGoBack,
                    onBack: { handleBack() },
                    // Jak w przewodniku: „Wstecz” w jednej linii z „Dalej”.
                    backPlacement: .besidePrimary,
                    primaryTitle: primaryTitle,
                    primaryIcon: tourPhase == nil && step == totalSteps ? "checkmark" : "arrow.right",
                    isPrimaryEnabled: tourPhase != nil || isNextEnabled,
                    isPrimaryLoading: tourPhase == nil && isCreatingHousehold && step == totalSteps,
                    onPrimary: { handlePrimary() }
                )
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    footerHeight = height
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: pageKey)
        // Suwak kalorii podąża za podpowiedzią, dopóki użytkownik sam go nie
        // przeciągnie. Podpowiedź zależy nie tylko od celu, ale i od sylwetki
        // z kroku 1 oraz treningów z kroku 2 — stąd wspólny token zamiast
        // samego `goal`.
        .onChange(of: calorieSuggestionToken) { _, _ in
            guard !calorieAdjustedManually, let suggestedCalories else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                calorieGoal = suggestedCalories
            }
        }
        .onChange(of: calorieGoal) { _, newValue in
            // Bez celu nie ma podpowiedzi, od której dałoby się odejść.
            if let suggestedCalories, newValue != suggestedCalories {
                calorieAdjustedManually = true
            }
        }
        // Tylko stuknięcie „Nie podaję” (zmiana), nie stan odtworzony w `init`.
        .onChange(of: sexDeclined) { _, declined in
            clearsSex = declined
        }
    }

    /// Sylwetka z kroków 1 i 2. `nil`, dopóki użytkownik ich nie wypełni —
    /// wtedy podpowiedź schodzi do płaskiej wartości przypisanej do celu.
    private var bodyMetrics: BodyMetrics? {
        guard let heightCm, let weightKg, let activity else { return nil }
        return BodyMetrics(
            heightCm: heightCm,
            weightKg: weightKg,
            yearOfBirth: yearOfBirth,
            activityRaw: activity.rawValue,
            sexRaw: sex?.rawValue ?? ""
        )
    }

    /// `nil` bez wybranego celu (7.10.2026) — kalorie liczą się od wyboru.
    private var suggestedCalories: Int? {
        goal?.suggestedCalories(for: bodyMetrics)
    }

    /// Rozbicie celu na makro do podglądu w kroku 3. Ten sam rachunek, co
    /// w Ustawieniach → „Dieta i alergeny" — bez nadpisań, bo w kreatorze
    /// nie ma czym ich zrobić.
    private var macroTargets: MacroTargets? {
        guard let goal else { return nil }
        return bodyMetrics?.macroTargets(for: goal, calories: calorieGoal)
    }

    /// Zmienia się przy każdej danej, która wpływa na podpowiedź.
    private var calorieSuggestionToken: String {
        "\(goal?.rawValue ?? "")|\(heightCm ?? 0)|\(weightKg ?? 0)|\(yearOfBirth)|\(activity?.rawValue ?? 0)|\(sex?.rawValue ?? "")"
    }

    // MARK: - Jeden przepływ: przewodnik + kreator

    /// Tożsamość strony — przejście na bok przy każdej zmianie, także na
    /// styku przewodnika z kreatorem.
    private var pageKey: String {
        if let tourPhase { return "tour-\(tourPhase)" }
        return "step-\(step)"
    }

    @ViewBuilder
    private var pageContent: some View {
        if let tourPhase {
            Group {
                if tourPhase <= 0 {
                    TourIntroView()
                } else if tourPhase >= tourDonePhase {
                    TourDoneView()
                } else {
                    TourStepView(step: tourSteps[tourPhase - 1])
                }
            }
            // Stopka jest nakładką (kroki kreatora przewijają się pod nią nad
            // klawiaturą), a strona przewodnika liczy wysokość zdjęcia
            // z widocznej części — kończy się więc nad płytą stopki.
            .padding(.bottom, footerHeight)
            .ignoresSafeArea(.keyboard)
        } else {
            stepContent(for: step)
        }
    }

    /// Pasek kroków na całość: 5 kroków przewodnika, ekran „Teraz my
    /// poznajmy Ciebie” i 5 kroków kreatora. Powitanie ma zamiast paska
    /// „Pomiń…”, a powrót po nowe gospodarstwo — nic („5 z 5” nie ma sensu
    /// dla kogoś, kto innych kroków nie widział).
    private var footerSlot: SCStepFooter.Slot {
        if let tourPhase, tourPhase <= 0 {
            return .link("Pomiń i przejdź do konfiguracji")
        }
        guard initialStep == 1 else { return .empty }
        let total = tourDonePhase + totalSteps
        if let tourPhase { return .progress(step: tourPhase, total: total) }
        return .progress(step: tourDonePhase + step, total: total)
    }

    private var primaryTitle: String {
        guard let tourPhase else { return nextLabel }
        if tourPhase <= 0 { return "Poznaj aplikację" }
        if tourPhase >= tourDonePhase { return "Opowiedz nam o sobie" }
        return tourPhase == tourSteps.count ? "Poznajmy się" : "Dalej"
    }

    private var canGoBack: Bool {
        if let tourPhase { return tourPhase > 0 }
        // Z pierwszego kroku kreatora wraca się do przewodnika.
        return step > initialStep || initialStep == 1
    }

    private func handlePrimary() {
        guard let tourPhase else {
            handleNext()
            return
        }
        if tourPhase >= tourDonePhase {
            enterWizard()
        } else {
            moveTour(to: tourPhase + 1, direction: 1)
        }
    }

    /// „Pomiń…” z powitania — prosto do pierwszego kroku kreatora.
    private func skipTour() {
        enterWizard()
    }

    /// Przewodnik zaliczony: po wznowieniu aplikacja zaczyna od kreatora.
    private func enterWizard() {
        tourCompleted = true
        direction = 1
        DispatchQueue.main.async {
            tourPhase = nil
            step = 1
        }
    }

    private func moveTour(to phase: Int, direction newDirection: Int) {
        direction = newDirection
        DispatchQueue.main.async {
            tourPhase = phase
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
                weightKg: $weightKg,
                sex: $sex,
                sexDeclined: $sexDeclined,
                activity: activity ?? .light
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
            WelcomeStep4MealsView(mealSlots: $mealSlots, mealSchedule: $mealSchedule)
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
                && isYearAnswered
                && isHeightAnswered
                && isWeightAnswered
                && (sex != nil || sexDeclined)
        case 2:
            return goal != nil && activity != nil
        case 3:
            // Alergeny opcjonalne — brak wyboru = brak alergii.
            return diet != nil
        case 4:
            return true
        case 5:
            // Te same granice, co w Ustawieniach (2…50, `SessionStore.householdNameLengthRange`;
            // serwer — `CreateHouseholdDto` — wpuszcza do 64). Od Fazy 0 backend egzekwuje je także na WebSockecie —
            // 1-znakowa nazwa wracałaby jako VALIDATION_ERROR z generycznym
            // komunikatem i kreator nie dałby się dokończyć.
            return SessionStore.isValidHouseholdName(householdName)
        default:
            return true
        }
    }

    private var isYearAnswered: Bool { WelcomeProgress.isYearAnswered(yearOfBirth) }

    private var isHeightAnswered: Bool {
        heightCm.map { WelcomeProgress.heightRange.contains($0) } ?? false
    }

    private var isWeightAnswered: Bool {
        weightKg.map { WelcomeProgress.weightRange.contains($0) } ?? false
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var avatarInitial: String {
        guard let first = trimmedName.first else { return "?" }
        return String(first).uppercased()
    }

    private func handleBack() {
        if let tourPhase {
            guard tourPhase > 0 else { return }
            moveTour(to: tourPhase - 1, direction: -1)
            return
        }
        if step > initialStep {
            move(to: step - 1)
        } else if initialStep == 1 {
            // Pierwszy krok kreatora → ekran „Teraz my poznajmy Ciebie”.
            moveTour(to: tourDonePhase, direction: -1)
        }
    }

    /// Kierunek trafia do drzewa widoków PRZED zmianą kroku, w osobnym
    /// obiegu pętli zdarzeń. Przejście wyjścia SwiftUI bierze z ostatniego
    /// renderu widoku, który znika — gdyby oba pola zmieniły się w jednej
    /// transakcji, strona schodząca wyjeżdżałaby jeszcze w POPRZEDNIM
    /// kierunku i przy pierwszym „Wstecz" po serii „Dalej" obie strony
    /// zjeżdżały się na tej samej krawędzi. To samo przy przejściach przewodnika (`moveTour`).
    private func move(to target: Int) {
        direction = target > step ? 1 : -1
        DispatchQueue.main.async {
            step = target
        }
    }

    private func handleNext() {
        guard isNextEnabled else { return }
        // Call SessionStore methods directly (it's a @MainActor reference
        // type pulled from Environment). Going via Sendable closure
        // arguments tripped a Swift 6 / iOS 26 ABI miscompile that
        // delivered shifted / corrupted parameter values to the closure
        // body — using the store reference avoids the indirection.
        let store = sessionStore
        // Krok zaliczony — PRZED zapisem, bo `savePreferencesStep` czyta
        // z `answeredStep`, co już padło (alergeny dopiero po kroku 3).
        // Szkic z odpowiedziami i numerem kroku idzie do pliku od razu,
        // synchronicznie i przed `advance()` — niezależnie od kolejki zapisów
        // na serwer (7.10.2026, Codex).
        if (1...3).contains(step) {
            answeredStep = max(answeredStep, step)
            saveDraft(userId: store.currentUserId)
        }
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
            UserDefaults.standard.set(mealSchedule.storageValue, forKey: MealSlotSchedule.Keys.times)
            advance()
        case 5:
            let trimmedHousehold = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
            let slots = mealSlots
            let schedule = mealSchedule
            Task { @MainActor in
                await store.createHousehold(name: trimmedHousehold)
                if store.currentHouseholdId != nil {
                    // Sloty PRZED domknięciem onboardingu: `completeOnboarding`
                    // przepuszcza aplikację do pulpitu, a Plan czyta wtedy
                    // konfigurację posiłków. Zapis po tej linii dorzucałby
                    // podwieczorek do już narysowanego tygodnia.
                    await store.saveMealSlotConfiguration(slots)
                    // Godziny tak samo: nowe gospodarstwo startuje z domyślnymi,
                    // więc jedzie tylko rozkład zmieniony w kroku 4.
                    if !schedule.isDefault {
                        await store.saveMealSlotSchedule(schedule)
                    }
                    await store.completeOnboarding()
                }
            }
        default:
            break
        }
    }

    /// Stan kroków 1–3 jako szkic (`WelcomeDraft`). Kalorie tylko ręcznie
    /// przesunięte — inaczej przy wznowieniu liczą się z podpowiedzi.
    private func saveDraft(userId: String?) {
        guard let userId, !userId.isEmpty else { return }
        WelcomeDraft(
            userId: userId,
            answeredStep: answeredStep,
            name: trimmedName,
            yearOfBirth: isYearAnswered ? yearOfBirth : nil,
            heightCm: heightCm,
            weightKg: weightKg,
            sex: sex?.rawValue,
            sexDeclined: sex == nil && sexDeclined,
            goal: goal?.rawValue,
            activityLevel: activity?.rawValue,
            diet: diet?.rawValue,
            allergens: Array(Set(allergens.map(\.rawValue)).union(unknownAllergens)).sorted(),
            calorieGoal: calorieAdjustedManually ? calorieGoal : nil
        ).save()
    }

    private func advance() {
        guard step < totalSteps else { return }
        move(to: step + 1)
    }

    // MARK: - Zapisy w tle z ponowieniem

    @MainActor
    private func saveProfileStep(_ store: SessionStore) async {
        // Tylko to, co podane (7.10.2026): `nil` = pole pominięte w zapisie.
        // Po „Dalej” z kroku 1 wszystko jest podane; strażniki chronią
        // ponowienie, gdy ktoś wrócił i wyczyścił pole.
        let ok = await store.saveProfile(
            displayName: trimmedName,
            yearOfBirth: isYearAnswered ? yearOfBirth : nil,
            heightCm: isHeightAnswered ? heightCm : nil,
            weightKg: isWeightAnswered ? weightKg : nil,
            sex: sex?.rawValue,
            clearSex: sex == nil && sexDeclined && clearsSex,
            // Formularz kreatora, nie lokalna kopia — bez czekania na `users:me`
            // (7.10.2026, `ensureProfileBaseline`).
            confirmBaselineFirst: false
        )
        pendingProfileRetry = !ok
        refreshSaveWarning()
    }

    @MainActor
    private func savePreferencesStep(_ store: SessionStore) async {
        // Unia z nieznanymi — kreator nie kasuje alergenu z nowszego buildu.
        let allergenRaws = Array(Set(allergens.map(\.rawValue)).union(unknownAllergens)).sorted()
        // Tylko odpowiedzi (7.10.2026): po kroku 2 cel, aktywność i kalorie
        // z nich policzone; dieta i alergeny dopiero po kroku 3 — wcześniej
        // pusta lista alergenów byłaby odpowiedzią udzieloną za użytkownika.
        let ok = await store.saveUserPreferences(
            diet: diet?.rawValue,
            calorieGoal: goal != nil ? calorieGoal : nil,
            allergens: answeredStep >= 3 ? allergenRaws : nil,
            goal: goal?.rawValue,
            activityLevel: activity?.rawValue,
            // Formularz kreatora to świadoma decyzja użytkownika, nie lokalna
            // kopia — nie czeka na odczyt z serwera (nowe konto i tak ma tam
            // domyślny wiersz). 7.10.2026, patrz `ensurePreferencesBaseline`.
            confirmBaselineFirst: false
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
                ? "Nie zapisaliśmy tego na serwerze — dane są w telefonie, ponowimy przy następnym kroku."
                : nil
        }
    }
}

/// Wymagane odpowiedzi kreatora (7.10.2026, Rafał: „wymuszanie, aby user
/// podał dane wszystkie, bo inaczej button będzie dalej wyłączony”).
///
/// Zakresy = te, z których aplikacja i serwer liczą zapotrzebowanie
/// (`BodyMetrics.init?`, backend `body-metrics.util.ts`) i które ustawia
/// „Twoje dane” (`ProfileField.heights` / `weights`) — podany wzrost zawsze
/// daje wynik. Wiek od 16, bo od tylu lat jest aplikacja (regulamin
/// i polityka, `AuthFooterView`; zgoda Asystenta też pyta o 16). Rok liczony
/// jak wszędzie w aplikacji: bieżący rok minus rok urodzenia.
enum WelcomeProgress {
    static let ageRange = 16...110
    static let heightRange = 120...230
    static let weightRange: ClosedRange<Double> = 30...250

    static func isYearAnswered(_ yearOfBirth: Int, now: Date = Date()) -> Bool {
        let currentYear = Calendar.current.component(.year, from: now)
        return ageRange.contains(currentYear - yearOfBirth)
    }
}

/// Szkic kreatora (7.10.2026, Codex): odpowiedzi kroków 1–3 i numer
/// ostatniego kroku zaliczonego „Dalej”, zapisane RAZEM i synchronicznie.
///
/// Po co: zapisy na serwer (i do kopii profilu/preferencji) idą w tle przez
/// kolejki `SessionStore` — zabicie aplikacji tuż po „Dalej” mogło zostawić
/// zaliczony krok przy starej kopii (np. serwerowe „Bez diety” zamiast
/// wybranej diety). Wznowienie czyta więc szkic, nie kopię.
///
/// W chronionym magazynie (dane zdrowotne — nie `UserDefaults`), jako JSON
/// pod jednym kluczem, zwykłym `set` (bez znacznika edycji z ręki — nie
/// miesza się z licznikami strażnika). Kasowany po zakończeniu onboardingu
/// (`SessionStore.persistOnboardingCompletedAt`) i przy wylogowaniu /
/// usunięciu konta (`SCProtectedSettings.removeAll`). Szkic innego konta
/// (`userId`) jest pomijany.
nonisolated struct WelcomeDraft: Codable, Equatable {
    static let storageKey = "onboarding.draft"

    var userId: String
    var answeredStep: Int
    var name: String
    /// `nil` = rok jeszcze niepodany (koło na bieżącym roku).
    var yearOfBirth: Int?
    var heightCm: Int?
    var weightKg: Double?
    /// `Sex.rawValue`.
    var sex: String?
    var sexDeclined: Bool
    /// `UserGoal.rawValue`.
    var goal: String?
    /// `ActivityLevel.rawValue`.
    var activityLevel: Int?
    /// `DietPreference.rawValue`.
    var diet: String?
    /// Surowe wartości, także nieznane temu buildowi.
    var allergens: [String]
    /// Tylko ręcznie przesunięty suwak; `nil` = podpowiedź z danych.
    var calorieGoal: Int?
}

extension WelcomeDraft {
    /// Szkic tego konta albo `nil` (brak, uszkodzony, cudzy).
    @MainActor
    static func load(forUserId userId: String?) -> WelcomeDraft? {
        guard let userId, !userId.isEmpty,
              let json = SCProtectedSettings.shared.string(forKey: storageKey),
              let data = json.data(using: .utf8),
              let draft = try? JSONDecoder().decode(WelcomeDraft.self, from: data),
              draft.userId == userId
        else { return nil }
        return draft
    }

    /// Zapis synchroniczny (plik atomowy w `SCProtectedSettings`).
    @MainActor
    func save() {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8)
        else { return }
        SCProtectedSettings.shared.set(json, forKey: Self.storageKey)
    }

    @MainActor
    static func clear() {
        SCProtectedSettings.shared.removeObject(forKey: storageKey)
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

