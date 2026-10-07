import SwiftUI

// First-login welcome flow. Od 24.09.2026 JEDEN przepływ z przewodnikiem
// „Poznaj aplikację” na początku (Rafał: „daj to wszystko w jednym wielkim
// stepperze, aby nie przełączać”): powitanie → 5 kroków przewodnika →
// „Teraz my poznajmy Ciebie” → 4 kroki kreatora, jedna stopka, jeden pasek
// kroków (10 odcinków), strony jadą na bok bez przenikania między dwoma
// ekranami. Dawniej `WelcomeFlowView` przenikał `FeatureTourView` w ten widok
// i pasek „1/5” zaczynał się od nowa.
//
// Kreator: od 7.10.2026 CZTERY kroki, każdy to ten sam widok co wiersz
// Ustawień (Rafał: „zrób na onboarding user te nowe widoki z ustawień…
// uspójnij to i popraw maksymalnie pod nowy widok”):
// 1. „Twoje dane” (`ProfileBodyForm`: imię, sylwetka, treningi),
// 2. „Dieta i alergeny” (`DietPreferencesForm`: kalorie, makro, cel, dieta,
//    alergeny — dawne kroki „Cel” i „Dieta i kalorie” w jednym, bo cel
//    stoi w Ustawieniach w arkuszu diety),
// 3. „Posiłki w planie” (`MealDayAxisList`),
// 4. „Gospodarstwo” (`HouseholdKit`).
// Stopka (`SCStepFooter`: pasek kroków, „Wstecz” obok „Dalej”) stoi
// w systemowym `safeAreaBar` — pod przyciskami nic poza natywnym miękkim
// brzegiem przewijania. Zapisy bez zmian: profil przy „Dalej” z kroku 1,
// preferencje z kroku 2 (`confirmBaselineFirst: false`), pory i godziny
// lokalnie do utworzenia gospodarstwa w kroku 4, który domyka onboarding
// na serwerze i przepuszcza aplikację do pulpitu (`RootScreen`).
//
// Odpowiedzi WYMAGANE (7.10.2026, Rafał: „wymuszanie, aby user podał dane
// wszystkie, bo inaczej button będzie dalej wyłączony”; reguły z #360
// przeniesione na ten kreator): krok 1 — imię, rok (wiek 16…110), wzrost,
// waga, płeć albo „Nie podaję” i treningi; krok 2 — cel i dieta (alergeny
// opcjonalne). Czego nie podano, jest `nil`, a nie wartością domyślną —
// „Dalej” czeka (`isNextEnabled`), a zapis niczego nie wysyła za użytkownika.
// Wznowienie czyta szkic (`WelcomeDraft`), nie kopię profilu i preferencji.
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
    /// the last step (household creation) — they can't backtrack into the
    /// profile / preference steps that they already completed.
    let initialStep: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sessionStore) private var sessionStore

    /// Faza przewodnika przed kreatorem: 0 = powitanie, 1…5 = kroki,
    /// 6 = „Teraz my poznajmy Ciebie”. `nil` = jesteśmy w kreatorze (`step`).
    @State private var tourPhase: Int?
    @AppStorage(TourCompletion.storageKey) private var tourCompleted: Bool = false
    private let tourSteps = TourStep.all
    private var tourDonePhase: Int { tourSteps.count + 1 }

    // Step state — kept locally so the user can move back and tweak
    // without touching the backend until they advance.
    @State private var step: Int
    @State private var direction: Int = 1
    @State private var name: String
    /// Rok to wyjątek wśród odpowiedzi: koło zawsze stoi na jakimś roku, więc
    /// „brak” = bieżący rok (wiek 0) poza `ProfileField.acceptedAges`.
    @State private var yearOfBirth: Int
    /// `nil` = jeszcze bez odpowiedzi (7.10.2026).
    @State private var heightCm: Int?
    @State private var weightKg: Double?
    /// Surowa wartość płci jak w „Twoich danych” — „” = „Nie podaję”,
    /// `nil` = jeszcze bez odpowiedzi (płeć to wymagana ODPOWIEDŹ, nie
    /// wymagana płeć).
    @State private var sexRaw: String?
    /// „Nie podaję” stuknięte w tym kreatorze — dopiero wtedy zapis kasuje
    /// płeć na serwerze (`saveProfile(clearSex:)`), jak w „Twoich danych”.
    /// Odtworzone przy wznowieniu samo niczego nie kasuje — zatwierdzone
    /// wcześniej skasowanie niesie `sexClearPending`
    /// (`SessionStore.markSexClearPending`, ustawiany przy „Dalej”).
    @State private var clearsSex = false
    @State private var goal: UserGoal?
    @State private var activity: ActivityLevel?
    @State private var diet: DietPreference?
    /// Ostatni krok zaliczony „Dalej” (`WelcomeDraft.answeredStep`). Cel,
    /// aktywność i dieta są w magazynie zawsze — start sesji wpisuje tam
    /// domyślny wiersz serwera (HEALTHY / 2 / NONE) — więc „podane” znaczy
    /// tu „zaliczone w kreatorze”.
    @State private var answeredStep: Int
    @State private var calorieGoal: Int
    @State private var allergens: Set<Allergen>
    /// Wartości alergenów zapisane na koncie, których ten build nie rozumie.
    /// Trzymamy je, żeby zapis z kreatora nie skasował ustawienia zrobionego
    /// na nowszej wersji aplikacji (patrz `SettingsView.unknownAllergens`).
    @State private var unknownAllergens: [String]
    /// Posiłki, które gospodarstwo planuje. Zbierane w kroku 3, wysyłane
    /// dopiero w kroku 4 — `households:updateMealTypes` potrzebuje
    /// `householdId`, który powstaje razem z gospodarstwem.
    @State private var mealSlots: MealSlotConfiguration
    /// Godziny posiłków z kroku 3 — tak jak `mealSlots` jadą na serwer
    /// dopiero razem z gospodarstwem (`households:updateMealTimes`).
    @State private var mealSchedule: MealSlotSchedule
    @State private var householdName: String = ""
    /// Zdjęcie konta (Google) z chronionego magazynu — awatar w „Twoich
    /// danych” i na liście domowników, jak w Ustawieniach.
    private let storedAvatarUrl: String?

    // Whether the user has manually moved the kcal slider away from the
    // suggested value for the current goal. Until they do, the slider
    // tracks the goal so a user picking "schudnąć" sees the lower
    // baseline appear without having to drag it down. „Ustaw” w karcie
    // kalorii (podpowiedź celu) wraca do śledzenia (7.10.2026).
    @State private var calorieAdjustedManually: Bool = false

    /// Zapisy z kroków 1–2 idą w tle. Gdy któryś padnie, kreator nie
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
    static let householdOnlyStep = 4

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

        // Szkic kreatora (7.10.2026, z #360): odpowiedzi z kroków zaliczonych
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

        // Sylwetka i treningi: ze szkicu, a bez niego sylwetka z kopii — tam
        // leży tylko to, co konto naprawdę ma (nowe konto: pusto, serwer
        // trzyma `null`). Treningi bez szkicu — brak odpowiedzi: kopia ma
        // zawsze domyślny wiersz serwera.
        let currentYear = Calendar.current.component(.year, from: Date())
        let resolvedYear: Int
        let resolvedHeight: Int?
        let resolvedWeight: Double?
        let resolvedSexRaw: String?
        let resolvedActivity: ActivityLevel?
        if let draft {
            resolvedYear = draft.yearOfBirth ?? currentYear
            resolvedHeight = draft.heightCm
            resolvedWeight = draft.weightKg
            if let sex = draft.sex.flatMap({ Sex(rawValue: $0) }) {
                resolvedSexRaw = sex.rawValue
            } else {
                resolvedSexRaw = draft.sexDeclined ? "" : nil
            }
            resolvedActivity = draft.activityLevel.flatMap { ActivityLevel(rawValue: $0) }
        } else {
            let storedYear = protectedStore.integer(forKey: "settings.profile.yearOfBirth")
            let storedHeight = protectedStore.integer(forKey: "settings.profile.heightCm")
            let storedWeight = protectedStore.double(forKey: "settings.profile.weightKg")
            resolvedYear = ProfileBodyForm.yearRange.contains(storedYear) ? storedYear : currentYear
            // Wzrost i waga w zakresie kół „Twoich danych” (`ProfileField`) —
            // koło poza swoim zakresem nie ma czego pokazać.
            resolvedHeight = storedHeight > 0
                ? min(max(storedHeight, ProfileField.heights.lowerBound), ProfileField.heights.upperBound)
                : nil
            resolvedWeight = storedWeight > 0
                ? min(max(storedWeight, ProfileField.weights.lowerBound), ProfileField.weights.upperBound)
                : nil
            // Pusta płeć w kopii to NIE „Nie podaję” — konto jej po prostu
            // nie ma, więc pytanie czeka na odpowiedź.
            resolvedSexRaw = Sex(rawValue: protectedStore.string(forKey: "settings.profile.sex") ?? "")?.rawValue
            resolvedActivity = nil
        }
        _yearOfBirth = State(initialValue: resolvedYear)
        _heightCm = State(initialValue: resolvedHeight)
        _weightKg = State(initialValue: resolvedWeight)
        _sexRaw = State(initialValue: resolvedSexRaw)
        _activity = State(initialValue: resolvedActivity)

        storedAvatarUrl = protectedStore.string(forKey: "settings.user.avatarUrl").flatMap { $0.isEmpty ? nil : $0 }

        // Cel i dieta — wyłącznie z zaliczonego kroku 2 w szkicu.
        let resolvedGoal: UserGoal? = answered >= 2
            ? draft?.goal.flatMap { UserGoal(rawValue: $0) }
            : nil
        _goal = State(initialValue: resolvedGoal)

        let resolvedDiet: DietPreference? = answered >= 2
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
                sexRaw: resolvedSexRaw ?? ""
            )
        }()
        let seedSuggestion: Int? = resolvedGoal?.suggestedCalories(for: seedMetrics)
        _calorieGoal = State(
            initialValue: draftKcal ?? seedSuggestion ?? UserGoal.healthy.suggestedCalories
        )
        _calorieAdjustedManually = State(initialValue: draftKcal != nil)

        // Alergeny: z zaliczonego kroku 2 w szkicu; wcześniej z kopii (to, co
        // konto już ma, zaznaczone na start).
        let storedTokens: [String]
        if answered >= 2, let draftAllergens = draft?.allergens {
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
        // wyloguj wywal”, „header od samej góry tak jak wszystkie”): krok
        // zaczyna się tam, gdzie strona przewodnika, a górny brzeg treści gaśnie
        // pod paskiem statusu (`scScrollEdgeFade` w każdym kroku).
        ZStack {
            // To samo tło, co przewodnik przed kreatorem i każdy ekran
            // aplikacji — przejście przewodnik → kreator nie zmienia koloru.
            SCPageBackground(scheme: colorScheme)
                .ignoresSafeArea()

            ZStack {
                pageContent
                    .id(pageKey)
                    .transition(asymmetricSlide())
            }
            .animation(.easeInOut(duration: 0.34), value: pageKey)
        }
        // Stopka w systemowym `safeAreaBar` (7.10.2026; dawniej nakładka
        // z zapasem pod treścią): przewijana treść kończy się nad przyciskami,
        // a pod nimi jest tylko natywny miękki brzeg (`scSheetFooterEdge`) —
        // bez płyty, pasa i cienia. Przy klawiaturze (nazwa domu) stopka
        // jedzie nad nią, jak każda stopka arkusza.
        .safeAreaBar(edge: .bottom, spacing: 0) {
            SCStepFooter(
                slot: footerSlot,
                onSlotTap: { skipTour() },
                notice: tourPhase == nil ? saveWarning : nil,
                showsBack: canGoBack,
                onBack: { handleBack() },
                // Jak w przewodniku i wprowadzeniu Asystenta: „Wstecz” w jednej
                // linii z „Dalej”.
                backPlacement: .besidePrimary,
                primaryTitle: primaryTitle,
                primaryIcon: tourPhase == nil && step == totalSteps ? "checkmark" : "arrow.right",
                isPrimaryEnabled: tourPhase != nil || isNextEnabled,
                isPrimaryLoading: tourPhase == nil && isCreatingHousehold && step == totalSteps,
                onPrimary: { handlePrimary() }
            )
        }
        .scSheetFooterEdge()
        .sensoryFeedback(.impact(flexibility: .soft), trigger: pageKey)
        // Kalorie idą za podpowiedzią, dopóki użytkownik sam nie ruszy suwaka.
        // Podpowiedź zależy nie tylko od celu, ale i od sylwetki oraz treningów
        // z kroku 1 — stąd wspólny token zamiast samego `goal`.
        .onChange(of: calorieSuggestionToken) { _, _ in
            guard !calorieAdjustedManually, let suggestedCalories else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                calorieGoal = suggestedCalories
            }
        }
        // Ręczna zmiana odpina kalorie od podpowiedzi, a „Ustaw” (albo suwak
        // na tej samej wartości) przypina je z powrotem. Bez celu nie ma
        // podpowiedzi, od której dałoby się odejść (kalorie są wtedy zakryte).
        .onChange(of: calorieGoal) { _, newValue in
            if let suggestedCalories {
                calorieAdjustedManually = newValue != suggestedCalories
            }
        }
        // Tylko stuknięcie „Nie podaję” (zmiana), nie stan odtworzony w `init`
        // — jak w #360. Wybór płci zdejmuje zamiar skasowania.
        .onChange(of: sexRaw) { _, current in
            clearsSex = current == ""
        }
    }

    /// Sylwetka z kroku 1. `nil`, dopóki jej nie podano albo gdy któraś dana
    /// jest bez sensu — wtedy podpowiedź schodzi do płaskiej wartości
    /// przypisanej do celu.
    private var bodyMetrics: BodyMetrics? {
        guard let heightCm, let weightKg, let activity else { return nil }
        return BodyMetrics(
            heightCm: heightCm,
            weightKg: weightKg,
            yearOfBirth: yearOfBirth,
            activityRaw: activity.rawValue,
            sexRaw: sexRaw ?? ""
        )
    }

    /// `nil` bez wybranego celu (7.10.2026) — kalorie liczą się od wyboru.
    private var suggestedCalories: Int? {
        goal?.suggestedCalories(for: bodyMetrics)
    }

    /// Zmienia się przy każdej danej, która wpływa na podpowiedź.
    private var calorieSuggestionToken: String {
        "\(goal?.rawValue ?? "")|\(heightCm ?? 0)|\(weightKg ?? 0)|\(yearOfBirth)|\(activity?.rawValue ?? 0)|\(sexRaw ?? "-")"
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
            // Stopka stoi w `safeAreaBar`, więc strona przewodnika liczy
            // wysokość zdjęcia kroku już z części NAD nią (dawniej nakładka
            // i `padding(.bottom, footerHeight)`).
            .ignoresSafeArea(.keyboard)
        } else {
            stepContent(for: step)
        }
    }

    /// Pasek kroków na całość: 5 kroków przewodnika, ekran „Teraz my
    /// poznajmy Ciebie” i 4 kroki kreatora. Powitanie ma zamiast paska
    /// „Pomiń…”, a powrót po nowe gospodarstwo — nic („4 z 4” nie ma sensu
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
            WelcomeProfileStep(
                name: $name,
                sexRaw: $sexRaw,
                yearOfBirth: $yearOfBirth,
                heightCm: $heightCm,
                weightKg: $weightKg,
                activity: $activity,
                avatarUrl: storedAvatarUrl,
                seed: avatarSeed
            )
        case 2:
            WelcomeDietStep(
                calorieGoal: $calorieGoal,
                goal: $goal,
                diet: $diet,
                allergens: $allergens,
                metrics: bodyMetrics
            )
        case 3:
            WelcomeMealsStep(mealSlots: $mealSlots, mealSchedule: $mealSchedule)
        default:
            WelcomeHouseholdStep(
                householdName: $householdName,
                firstName: trimmedName,
                avatarUrl: storedAvatarUrl,
                seed: avatarSeed,
                errorMessage: errorMessage,
                // Ktoś, kogo zaproszono, nie ma po co zakładać własnego
                // gospodarstwa — a bez tej listy był to jedyny widoczny sposób
                // wyjścia z tego ekranu.
                pendingInvitations: sessionStore.pendingInvitations,
                onAcceptInvitation: { token in
                    Task { await sessionStore.acceptPendingInvitation(token: token) }
                },
                onDeclineInvitation: { token in
                    Task { await sessionStore.declineInvitation(token: token) }
                }
            )
        }
    }

    /// Ziarno awatara — id konta, jak w Ustawieniach (`MemberAvatar`).
    private var avatarSeed: String {
        sessionStore.currentUserId ?? trimmedName
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
                && sexRaw != nil
                && activity != nil
        case 2:
            // Alergeny opcjonalne — brak wyboru = brak alergii.
            return goal != nil && diet != nil
        case 3:
            return true
        case 4:
            // Te same granice, co w Ustawieniach (2…50, `SessionStore.householdNameLengthRange`;
            // serwer — `CreateHouseholdDto` — wpuszcza do 64). Od Fazy 0 backend egzekwuje je także na WebSockecie —
            // 1-znakowa nazwa wracałaby jako VALIDATION_ERROR z generycznym
            // komunikatem i kreator nie dałby się dokończyć.
            return SessionStore.isValidHouseholdName(householdName)
        default:
            return true
        }
    }

    private var isYearAnswered: Bool { ProfileField.isYearAccepted(yearOfBirth) }

    private var isHeightAnswered: Bool {
        heightCm.map { ProfileField.heights.contains($0) } ?? false
    }

    private var isWeightAnswered: Bool {
        weightKg.map { ProfileField.weights.contains($0) } ?? false
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
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
        // z `answeredStep`, co już padło (alergeny dopiero po kroku 2).
        // Szkic z odpowiedziami i numerem kroku idzie do pliku od razu,
        // synchronicznie i przed `advance()` — niezależnie od kolejki zapisów
        // na serwer (7.10.2026, z #360).
        if (1...2).contains(step) {
            answeredStep = max(answeredStep, step)
            saveDraft(userId: store.currentUserId)
        }
        // „Nie podaję” stuknięte w tym kreatorze: zamiar skasowania płci też
        // synchronicznie, wspólnym znacznikiem z „Twoich danych”
        // (`sexClearPending`) — zapis w tle czeka w kolejce i zabicie aplikacji
        // gubiło żądanie. Po wznowieniu `clearsSex` jest `false`, ale znacznik
        // sam dokłada `null` do następnego zapisu profilu.
        if step == 1, sexRaw == "", clearsSex {
            store.markSexClearPending()
        }
        retryPendingSaves(store)
        switch step {
        case 1:
            Task { @MainActor in await saveProfileStep(store) }
            advance()
        case 2:
            Task { @MainActor in await savePreferencesStep(store) }
            advance()
        case 3:
            // Posiłki nie mają dokąd pójść na serwerze, dopóki nie ma
            // gospodarstwa — wybór czeka w `mealSlots` na krok 4. Lokalnie
            // zapisany od razu: zabicie aplikacji na kroku 4 nie cofa go
            // do domyślnych.
            UserDefaults.standard.set(mealSlots.storageValue, forKey: MealSlotConfiguration.Keys.enabledSlots)
            UserDefaults.standard.set(mealSchedule.storageValue, forKey: MealSlotSchedule.Keys.times)
            advance()
        case 4:
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
                    // więc jedzie tylko rozkład zmieniony w kroku 3.
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

    /// Stan kroków 1–2 jako szkic (`WelcomeDraft`). Kalorie tylko ręcznie
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
            sex: (sexRaw?.isEmpty ?? true) ? nil : sexRaw,
            sexDeclined: sexRaw == "",
            activityLevel: activity?.rawValue,
            goal: goal?.rawValue,
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
        // ponowienie.
        let ok = await store.saveProfile(
            displayName: trimmedName,
            yearOfBirth: isYearAnswered ? yearOfBirth : nil,
            heightCm: isHeightAnswered ? heightCm : nil,
            weightKg: isWeightAnswered ? weightKg : nil,
            sex: (sexRaw?.isEmpty ?? true) ? nil : sexRaw,
            clearSex: sexRaw == "" && clearsSex,
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
        // Tylko odpowiedzi (7.10.2026): kalorie dopiero z celem, alergeny
        // dopiero po zaliczonym kroku 2 — wcześniej pusta lista byłaby
        // odpowiedzią udzieloną za użytkownika.
        let ok = await store.saveUserPreferences(
            diet: diet?.rawValue,
            calorieGoal: goal != nil ? calorieGoal : nil,
            allergens: answeredStep >= 2 ? allergenRaws : nil,
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

/// Szkic kreatora (7.10.2026, z #360): odpowiedzi kroków 1–2 i numer
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
    /// `ActivityLevel.rawValue` — treningi są w kroku 1 („Twoje dane”).
    var activityLevel: Int?
    /// `UserGoal.rawValue`.
    var goal: String?
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

