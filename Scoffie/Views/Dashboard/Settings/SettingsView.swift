import SwiftUI

struct SettingsView: View {
    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.colorScheme) private var scheme
    /// Katalog — tylko do liczby „ukrywa N przepisów” przy alergenach.
    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @AppStorage("settings.theme") private var themeRawValue: String = AppTheme.system.rawValue
    @AppStorage("settings.notifications.enabled") private var notificationsEnabled: Bool = true
    @AppStorage("settings.notifications.planReminders") private var planRemindersEnabled: Bool = true
    @AppStorage("settings.notifications.shoppingReminders") private var shoppingRemindersEnabled: Bool = true
    // Dwa kanały czysto LOKALNE — planuje je telefon (`MealReminderService`),
    // więc nie jadą na backend razem z pozostałymi preferencjami.
    @AppStorage(MealReminderService.Keys.mealReminders) private var mealRemindersEnabled: Bool = true
    @AppStorage(MealReminderService.Keys.morningBriefing) private var morningBriefingEnabled: Bool = true
    @AppStorage(MealReminderService.Keys.dayWrapUp) private var dayWrapUpEnabled: Bool = true
    @AppStorage("settings.user.displayName") private var userDisplayName: String = "user1"
    @AppStorage("settings.user.email") private var userEmail: String = "user1@example.com"
    @AppStorage("settings.user.avatarUrl") private var userAvatarUrl: String = ""
    // −1 = backend jeszcze nie przydzielił koloru (konto sprzed tej zmiany).
    @AppStorage("settings.user.avatarColor") private var userAvatarColor: Int = -1
    // Ziarno awatara musi być tym samym identyfikatorem, którego używa
    // `MemberAvatar` (id użytkownika). Przy koncie bez przydzielonego
    // `avatarColor` e-mail i id dawały dwa różne kolory tej samej osobie —
    // jeden w Ustawieniach, drugi w Planie.
    @AppStorage("auth.userId") private var userId: String = ""
    @AppStorage("settings.household.name") private var persistedHouseholdName: String = ""
    @AppStorage("settings.diet.preference") private var dietPreferenceRaw: String = DietPreference.none.rawValue
    @AppStorage("settings.diet.allergens") private var allergensRaw: String = ""
    @AppStorage("settings.diet.calorieGoal") private var calorieGoal: Int = 2000
    @AppStorage("settings.diet.goal") private var goalRaw: String = UserGoal.healthy.rawValue
    // Sylwetka z arkusza „Twoje dane" — tylko do odczytu, żeby podpowiedź
    // kaloryczna liczyła się z realnych danych zamiast z płaskiej stałej.
    @AppStorage(BodyMetrics.Keys.heightCm) private var profileHeightCm: Int = 0
    @AppStorage(BodyMetrics.Keys.weightKg) private var profileWeightKg: Double = 0
    @AppStorage(BodyMetrics.Keys.sex) private var profileSexRaw: String = ""
    // −1 znaczy „nie nadpisane, licz za mnie". `@AppStorage` nie umie
    // opcjonalnego `Int`, a 0 g białka jest legalną (choć głupią) wartością,
    // więc potrzebny jest sentinel spoza dziedziny.
    @AppStorage("settings.diet.proteinG") private var proteinOverride: Int = -1
    @AppStorage("settings.diet.fatG") private var fatOverride: Int = -1
    @AppStorage("settings.diet.carbsG") private var carbsOverride: Int = -1
    @AppStorage(BodyMetrics.Keys.yearOfBirth) private var profileYearOfBirth: Int = 0
    @AppStorage(BodyMetrics.Keys.activityLevel) private var profileActivityRaw: Int = ActivityLevel.light.rawValue

    @State private var showCreateHouseholdSheet = false
    @State private var showHouseholdSheet = false
    /// „Utwórz gospodarstwo” z pustej karty arkusza gospodarstwa: arkusz
    /// tworzenia wchodzi PO zamknięciu tamtego, a nie na nim.
    @State private var opensCreateAfterHousehold = false
    @State private var showNotificationsSheet = false
    /// Zgoda systemu na powiadomienia — `nil`, dopóki system nie odpowiedział.
    /// Czytana przy wejściu, po powrocie aplikacji na wierzch i przy otwarciu
    /// arkusza (ktoś mógł ją zmienić w Ustawieniach iOS).
    @State private var notificationPermission: NotificationPermission?
    @State private var isRequestingNotifications = false
    /// Kanał, którego przykład stoi na górze arkusza powiadomień.
    @State private var notificationPreview: NotificationPreviewCard.Kind = .meals
    @State private var showAppearanceSheet = false
    @State private var showDietSheet = false
    /// Ekrany wpychane w arkusz „Dieta i alergeny” — wybór alergenów i „Twoje
    /// dane” (z odsyłacza „Uzupełnij sylwetkę”), zamiast arkuszy na arkuszu.
    @State private var showsAllergenPicker = false
    @State private var showsProfileFromDiet = false
    @State private var showMealSlotsSheet = false
    @State private var showProfileSheet = false
    /// „Pomoc” — strona wsparcia scoffie.app w Safari w aplikacji.
    @State private var showSupportPage = false
    @State private var showCookidooSheet = false
    @State private var showLegalDocumentsSheet = false
    @State private var showHealthSheet = false
    @State private var showPlanAccessSheet = false
    /// Stan dostępu do asystenta, pokazywany jako wartość wiersza. Bierzemy
    /// go z pamięci sklepu asystenta i odświeżamy przy wejściu w Ustawienia —
    /// wiersz bez wartości wyglądałby jak niedokończony, ale dokładanie
    /// osobnego żądania przy każdym otwarciu byłoby marnotrawstwem.
    @State private var planAccess: AgentUsageDTO?

    // Stan integracji „Zdrowie" przez @AppStorage — to arkusz zmienia te
    // klucze (via HealthStepsStore) i tylko @AppStorage odświeży wiersz.
    @AppStorage(HealthStepsStore.Keys.enabled) private var healthStepsEnabled: Bool = false
    @AppStorage(HealthStepsStore.Keys.source) private var healthStepsSource: String = StepsSource.appleHealth.rawValue
    @State private var createHouseholdName = ""
    @State private var householdNameError: String? = nil
    @State private var showLogoutAlert = false
    @State private var showLeaveHouseholdAlert = false
    @State private var showResetPreferencesAlert = false
    /// `task(id:)` odpala się także przy pierwszym pokazaniu widoku, nie
    /// tylko przy zmianie tokenu — a pierwsze odpalenie to żadna edycja.
    /// Bez tych strażników samo OTWARCIE arkusza diety / powiadomień
    /// wypychało bieżący lokalny stan do backendu; zaraz po świeżym
    /// zalogowaniu (zanim bootstrap przywróci preferencje z serwera)
    /// potrafiło to nadpisać w bazie prawdziwe ustawienia domyślnymi.
    /// Flagi zeruje `onAppear` arkusza, więc każde otwarcie ma swój
    /// „pierwszy strzał" do pominięcia.
    @State private var didObserveDietPreferencesToken = false
    @State private var didObserveNotificationToken = false
    /// Domownik wskazany do usunięcia — nie-nil otwiera alert potwierdzenia.
    @State private var memberToRemove: HouseholdMemberSnapshot?
    /// Id domownika w trakcie usuwania — wiersz pokazuje spinner zamiast menu.
    @State private var removingMemberId: String?
    @State private var invitationLink: URL?
    @State private var isCreatingInvitation = false
    @State private var showRenameHouseholdAlert = false
    @State private var renameDraft = ""

    /// Jedne granice nazwy domu w całej aplikacji (2…50) — zakładanie,
    /// zmiana nazwy i kreator (`SessionStore.householdNameLengthRange`).
    private static let householdNameMinLength = SessionStore.householdNameLengthRange.lowerBound
    private static let householdNameMaxLength = SessionStore.householdNameLengthRange.upperBound

    // Calorie goal range — 1200 kcal is the lower medical safety bound for
    // adults; 3500 covers heavy training. 50 kcal step keeps the slider
    // tactile without snapping to silly precision.
    private static let calorieGoalMin: Int = 1200
    private static let calorieGoalMax: Int = 3500
    private static let calorieGoalStep: Int = 50
    private static let calorieGoalDefault: Int = 2000

    /// Strona wsparcia — scoffie-web `src/pages/support/index.astro`
    /// (w menu strony „Pomoc”, `/support/`).
    private static let supportPageURL = URL(string: "https://scoffie.app/support/")!

    private var hasHousehold: Bool {
        !persistedHouseholdName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var trimmedCreateHouseholdName: String {
        createHouseholdName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var householdNameValidationError: String? {
        let name = trimmedCreateHouseholdName
        if name.isEmpty { return "Nazwa jest wymagana." }
        if name.count < Self.householdNameMinLength {
            return "Nazwa musi mieć co najmniej \(Self.householdNameMinLength) znaki."
        }
        if name.count > Self.householdNameMaxLength {
            return "Nazwa może mieć maksymalnie \(Self.householdNameMaxLength) znaków."
        }
        return nil
    }

    private var canSubmitCreateHousehold: Bool {
        householdNameValidationError == nil && !trimmedCreateHouseholdName.isEmpty
    }

    private var householdMembers: [HouseholdMemberSnapshot] {
        sessionStore.householdMembers
    }

    private var isLoadingMembers: Bool {
        sessionStore.isLoadingHouseholdMembers && householdMembers.isEmpty
    }

    private var canCreateInvitations: Bool {
        guard let currentUserId = sessionStore.currentUserId else { return false }
        guard let me = householdMembers.first(where: { $0.id == currentUserId }) else { return false }
        return me.role.uppercased() == "OWNER"
    }

    /// Inline value next to "Gospodarstwo" — "X osób" once the household has
    /// been preloaded; falls back to "Brak" when there's no household yet.
    private var householdRowValue: String {
        guard hasHousehold else { return "Brak" }
        let count = householdMembers.count
        if count == 0 { return "—" }
        return "\(count) \(membersLabel(for: count))"
    }

    /// Wartość przy „Powiadomieniach” — PRAWDZIWY stan, a nie sam przełącznik
    /// w aplikacji: bez zgody systemu (odmowa albo jeszcze nie pytaliśmy)
    /// żadne powiadomienie nie wyjdzie, choćby przełącznik stał na „Włączone”.
    /// Pusto, dopóki system nie odpowiedział — lepiej nic niż zgadywanie.
    private var notificationsRowValue: String? {
        guard let notificationPermission else { return nil }
        switch notificationPermission {
        case .notAsked, .denied:
            return "Wyłączone"
        case .allowed:
            return notificationsEnabled ? "Włączone" : "Wyciszone"
        }
    }

    /// Wartość przy „Wyglądzie” — ta sama nazwa co na karcie w arkuszu
    /// („Automatycznie” / „Jasny” / „Ciemny”); dawne „Auto” w wierszu
    /// i „Systemowy” w arkuszu to były dwie nazwy jednej rzeczy.
    private var appearanceRowValue: String {
        (AppTheme(rawValue: themeRawValue) ?? .system).title
    }

    private var currentDiet: DietPreference {
        DietPreference(rawValue: dietPreferenceRaw) ?? .none
    }

    private var currentGoal: UserGoal {
        UserGoal(rawValue: goalRaw) ?? .healthy
    }

    /// `nil`, gdy w profilu brakuje którejś danej — wtedy podpowiedź schodzi
    /// do płaskiej wartości przypisanej do celu.
    private var bodyMetrics: BodyMetrics? {
        BodyMetrics(
            heightCm: profileHeightCm,
            weightKg: profileWeightKg,
            yearOfBirth: profileYearOfBirth,
            activityRaw: profileActivityRaw,
            sexRaw: profileSexRaw
        )
    }

    private var suggestedCalories: Int {
        currentGoal.suggestedCalories(for: bodyMetrics)
    }

    /// To, co realnie obowiązuje: ręczne nadpisanie, a w jego braku wyliczenie
    /// z celu kalorycznego, sylwetki i liczby treningów. `nil`, gdy w profilu
    /// brakuje danych.
    ///
    /// Sama reguła siedzi w `DailyNutritionTargets`, bo pokazuje ją teraz
    /// także Plan tygodnia (pigułka nad menu i arkusz „Cel dnia").
    private var effectiveMacros: MacroTargets? {
        DailyNutritionTargets.resolve(
            calorieGoal: calorieGoal,
            goal: currentGoal,
            metrics: bodyMetrics,
            proteinOverride: proteinOverride,
            fatOverride: fatOverride,
            carbsOverride: carbsOverride
        ).macros
    }

    private var hasMacroOverride: Bool {
        proteinOverride >= 0 || fatOverride >= 0 || carbsOverride >= 0
    }

    /// Surowe tokeny z `@AppStorage` — CSV jest trwałym nadzbiorem tego, co
    /// ten build umie narysować. `Allergen` to tylko filtr do renderowania.
    private var allergenTokens: [String] {
        allergensRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    private var selectedAllergens: Set<Allergen> {
        Set(allergenTokens.compactMap { Allergen(rawValue: $0) })
    }

    /// Wartości, których ta wersja aplikacji nie zna — nowszy build dopisał
    /// je do konta i nie wolno ich skasować przy zwykłym stuknięciu w chip.
    /// Renderować ich nie ma jak (brak tytułu), więc tylko je przenosimy.
    /// Serwer i tak odrzuca id spoza swojej listy całym zapisem, więc nowa
    /// wartość enuma musi najpierw wyjść na backend.
    private var unknownAllergens: [String] {
        Array(Set(allergenTokens.filter { Allergen(rawValue: $0) == nil })).sorted()
    }

    /// Pełny zestaw do wysyłki: znane ∪ nieznane, posortowany.
    private var allergensPayload: [String] {
        Array(Set(selectedAllergens.map(\.rawValue)).union(unknownAllergens)).sorted()
    }

    /// Inline value next to "Dieta i alergeny" — kcal is always-on so it
    /// always shows up; diet name is prepended when set, allergen count
    /// is appended when at least one is picked. Capped at two pieces so
    /// the value column doesn't overflow on narrow rows.
    /// Kolumna wartości mieści około piętnastu znaków, więc pokazujemy
    /// JEDNĄ informację, nie sklejkę. „Schudnąć · 2100 kcal" ucinało się do
    /// „Schudnąć · 210…", czyli do liczby, której i tak nie dało się
    /// odczytać. Kolejność: dieta (najbardziej konkretna), potem cel,
    /// a na końcu kalorie — czyli to, co użytkownik faktycznie ustawił.
    private var dietRowValue: String {
        if currentDiet != .none {
            return currentDiet.title
        }
        if currentGoal != .healthy {
            return currentGoal.shortTitle
        }
        return "\(calorieGoal) kcal"
    }

    /// Wartość przy „Posiłkach w planie".
    ///
    /// Liczba, nie wyliczanka nazw: sześć slotów nie zmieści się w kolumnie
    /// wartości, a „Śniadanie · II śnia…" mówi mniej niż „5 posiłków dziennie".
    /// Przy samej trójce podstawowej dopisek jest zbędny — to stan domyślny,
    /// więc mówimy „Klasyczne 3", żeby nie sugerować, że coś jest ustawione.
    private var mealSlotsRowValue: String {
        let count = sessionStore.mealSlots.enabled.count
        return count == MealSlot.core.count ? "Klasyczne 3" : "\(count) dziennie"
    }

    /// Rozpiętość dnia — od pierwszej do ostatniej pory wśród planowanych
    /// posiłków. Mówi to, po co użytkownik wchodzi w ten ekran, i mieści się
    /// w wierszu. Trójka obowiązkowa ma porę zawsze, więc oba końce istnieją.
    /// Wartość wiersza „Asystent i plan": nazwa kupionego planu albo stan
    /// próbny. Pusto, dopóki nie wiemy — zgadywanie „Dostęp próbny" u kogoś,
    /// kto płaci, byłoby gorsze niż brak wartości.
    private var planAccessRowValue: String {
        guard let planAccess else { return "" }
        if planAccess.isTrial { return "Dostęp próbny" }
        return planAccess.product.map { "Plan \($0)" } ?? "Plan domu"
    }

    private func toggleAllergen(_ allergen: Allergen) {
        var current = selectedAllergens
        if current.contains(allergen) {
            current.remove(allergen)
        } else {
            current.insert(allergen)
        }
        // Unia z nieznanymi: stuknięcie w chip nie ma prawa skasować
        // alergenu ustawionego na nowszej wersji aplikacji.
        allergensRaw = Array(Set(current.map(\.rawValue)).union(unknownAllergens))
            .sorted()
            .joined(separator: ",")
    }

    /// „Wyczyść” w arkuszu alergenów — zdejmuje wszystkie ZNANE alergeny.
    /// Nieznane (dopisane przez nowszą wersję aplikacji) zostają, tak jak
    /// przy każdym stuknięciu w pojedynczy alergen.
    private func clearAllergens() {
        allergensRaw = unknownAllergens.joined(separator: ",")
    }

    private var appVersionLabel: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, buildNumber) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty:
            return "\(version) (\(build))"
        case let (version?, _) where !version.isEmpty:
            return version
        case let (_, build?) where !build.isEmpty:
            return "Build \(build)"
        default:
            return "Niedostępna"
        }
    }

    // Marginesy strony wspólne dla wszystkich zakładek v2.
    private var pageTopPadding: CGFloat { SCPageMetrics.top }
    private var pageHorizontalPadding: CGFloat { SCPageMetrics.horizontal }
    private var pageBottomPadding: CGFloat { SCPageMetrics.bottom }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                SCPageBackground(scheme: scheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        EditorialPageHeader("Ustawienia")
                            .padding(.horizontal, pageHorizontalPadding)
                            .padding(.top, pageTopPadding)
                            .padding(.bottom, 16)

                        VStack(alignment: .leading, spacing: 0) {
                            profileGroup
                            accountSection
                            appSection
                            if showsIntegrationsSection {
                                integrationsSection
                            }
                            infoSection

                            SCDestructiveButton(
                                title: "Wyloguj się",
                                icon: "rectangle.portrait.and.arrow.right"
                            ) {
                                showLogoutAlert = true
                            }
                            .padding(.top, 20)

                            versionCaption
                                .padding(.top, 14)
                                .padding(.bottom, 16)
                        }
                        .padding(.horizontal, pageHorizontalPadding)
                    }
                    .padding(.bottom, pageBottomPadding)
                }
                .scrollIndicators(.hidden)
                // Duży tytuł zjechał — pod paskiem stanu staje szklana kapsuła.
                .scReportsCompactTitle("Ustawienia", for: .settings)
                .ignoresSafeArea(.container, edges: .top)
            }
            // Pasek nawigacji SCHOWANY, jak na Planie i Dziś — pusty, żywy pasek
            // łapał stuknięcia w górne wiersze, a hak `NavBarHitTestPassthrough`
            // pod systemowym `TabView` przestał działać (6.10.2026).
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showLegalDocumentsSheet) {
                LegalDocumentsSheet(dataExportClient: sessionStore.dataExportClient)
            }
            .sheet(isPresented: $showCreateHouseholdSheet) {
                createHouseholdSheet
                    .dashboardLiquidSheet()
            }
            .sheet(isPresented: $showHouseholdSheet, onDismiss: {
                guard opensCreateAfterHousehold else { return }
                opensCreateAfterHousehold = false
                showCreateHouseholdSheet = true
            }) {
                householdManagementSheet
                    .dashboardLiquidSheet()
            }
            .sheet(isPresented: $showNotificationsSheet) {
                notificationsSheet
                    .dashboardLiquidSheet()
                    // Zgoda mogła się zmienić w Ustawieniach iOS, zanim ktoś
                    // tu wszedł — arkusz pokazuje stan z tej chwili.
                    .task { await refreshNotificationPermission() }
                    // Przełączniki muszą dojechać na serwer, bo to on decyduje
                    // o wysłaniu pusha. Trzymane tylko lokalnie wyciszały
                    // wyłącznie powiadomienia rysowane przez aplikację.
                    // Pierwsze odpalenie (samo otwarcie arkusza) jest
                    // pomijane — patrz `didObserveNotificationToken`.
                    .onAppear { didObserveNotificationToken = false }
                    .task(id: notificationPreferencesToken) {
                        guard didObserveNotificationToken else {
                            didObserveNotificationToken = true
                            return
                        }
                        await sessionStore.syncNotificationPreferences()
                    }
                    // Kanały lokalne nie mają czego wysyłać na serwer, ale
                    // mają co przeliczyć na telefonie: wyłączony przełącznik
                    // musi zdjąć rozkład od razu, a nie przy najbliższym
                    // wyjściu z aplikacji.
                    .onChange(of: localReminderToken) { _, _ in
                        sessionStore.rescheduleMealReminders()
                    }
            }
            .task {
                await refreshNotificationPermission()
            }
            // Powrót z Ustawień iOS („Otwórz ustawienia”) — wiersz i arkusz
            // mają od razu mówić to, co użytkownik właśnie przestawił.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await refreshNotificationPermission() }
            }
            .task {
                planAccess = sessionStore.agentStore?.usage
                if let refreshed = await sessionStore.agentStore?.loadUsage() {
                    planAccess = refreshed
                }
            }
            .sheet(isPresented: $showPlanAccessSheet) {
                PlanAccessSheet()
            }
            .sheet(isPresented: $showAppearanceSheet) {
                appearanceSheet
                    .dashboardLiquidSheet()
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileDetailsSheet {
                    showProfileSheet = false
                }
                .presentationDetents([.large])
                .dashboardLiquidSheet()
            }
            .sheet(isPresented: $showDietSheet, onDismiss: {
                // Arkusz zamknięty z wepchniętym ekranem — następne otwarcie
                // ma zacząć od diety, nie od alergenów czy „Twoich danych”.
                showsAllergenPicker = false
                showsProfileFromDiet = false
            }) {
                dietSheet
                    .dashboardLiquidSheet()
            }
            .sheet(isPresented: $showMealSlotsSheet) {
                MealSlotsSheet {
                    showMealSlotsSheet = false
                }
                .presentationDetents([.large])
                .dashboardLiquidSheet()
            }
            // Pomoc to strona wsparcia na scoffie.app (te same „Najczęstsze
            // sprawy”, kontakt, zgłaszanie błędów i RODO) w Safari W APLIKACJI,
            // w jednym arkuszu: zostaje się w Ustawieniach, „Zamknij” wraca na
            // listę, a odnośniki „mailto:” otwierają Pocztę. Dawny arkusz
            // z 28 pytaniami wpisanymi w kod starzał się szybciej niż aplikacja
            // (planowanie przez Kalendarz, „nie da się dopisać produktów”,
            // logowanie przez Google) — strona zmienia się bez wydania.
            .sheet(isPresented: $showSupportPage) {
                SCSafariView(url: Self.supportPageURL) {
                    showSupportPage = false
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showCookidooSheet) {
                CookidooIntegrationSheet {
                    showCookidooSheet = false
                }
                .presentationDetents([.large])
                .dashboardLiquidSheet()
            }
            .sheet(isPresented: $showHealthSheet) {
                HealthIntegrationSheet {
                    showHealthSheet = false
                }
                .presentationDetents([.large])
                .dashboardLiquidSheet()
            }
            .alert("Czy na pewno chcesz się wylogować?", isPresented: $showLogoutAlert) {
                Button("Anuluj", role: .cancel) {}
                Button("Wyloguj", role: .destructive) {
                    Task { await sessionStore.signOut() }
                }
            } message: {
                Text("Sesja zostanie zakończona na tym urządzeniu.")
            }
            .task(id: sessionStore.householdRealtimeVersion) {
                guard sessionStore.householdRealtimeVersion > 0 else { return }
                await handleHouseholdRealtimeUpdate()
            }
            .task {
                await preloadHouseholdContextIfNeeded(force: false)
            }
        }
    }

    // MARK: - Sections

    private var profileGroup: some View {
        EditorialProfileCard(
            displayName: userDisplayName,
            email: userEmail,
            avatarUrl: userAvatarUrl,
            avatarSeed: userId.isEmpty ? userDisplayName : userId,
            avatarColorIndex: userAvatarColor >= 0 ? userAvatarColor : nil,
            action: { showProfileSheet = true }
        )
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSettingsSectionHeader(title: "Konto")

            EditorialSettingsCardGroup {
                // Każdy wiersz w swoim kolorze, jak Ustawienia iOS
                // (6.10.2026) — dotąd szałwia dwa razy, terakota trzy razy.
                EditorialSettingsRow(
                    icon: "house.fill",
                    iconColor: SCPalette.indigo,
                    title: "Gospodarstwo",
                    value: householdRowValue,
                    action: openHousehold
                )

                EditorialSettingsRow(
                    icon: "leaf.fill",
                    iconColor: SCPalette.sage,
                    title: "Dieta i alergeny",
                    value: dietRowValue,
                    action: { showDietSheet = true }
                )

                // Jeden wiersz na wszystko o posiłkach: które dom planuje
                // i o której je. Pory otwierają się z tego arkusza, bo nikt
                // nie szuka ich osobno — a Ustawienia nie muszą tłumaczyć
                // różnicy między dwiema decyzjami, zanim ktokolwiek w nie wejdzie.
                EditorialSettingsRow(
                    icon: "fork.knife",
                    iconColor: SCPalette.butter,
                    title: "Posiłki w planie",
                    value: mealSlotsRowValue,
                    action: { showMealSlotsSheet = true }
                )

                // Spokojny dom sprawy z planem: stan, zużycie i oferta leżą
                // tutaj i czekają, aż ktoś sam po nie przyjdzie. Wartość po
                // prawej jest szara jak każda inna — wiersz nie zaczepia.
                EditorialSettingsRow(
                    icon: "sparkles",
                    iconColor: SCPalette.terracotta,
                    title: "Asystent i plan",
                    value: planAccessRowValue,
                    isLast: true,
                    action: { showPlanAccessSheet = true }
                )
            }
        }
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSettingsSectionHeader(title: "Aplikacja")

            EditorialSettingsCardGroup {
                EditorialSettingsRow(
                    icon: "bell.fill",
                    iconColor: SettingsAccent.coral,
                    title: "Powiadomienia",
                    value: notificationsRowValue,
                    action: { showNotificationsSheet = true }
                )

                EditorialSettingsRow(
                    icon: "circle.lefthalf.filled",
                    iconColor: SCPalette.lavender,
                    title: "Wygląd",
                    value: appearanceRowValue,
                    isLast: true,
                    action: { showAppearanceSheet = true }
                )
            }
        }
    }

    private var integrationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSettingsSectionHeader(title: "Integracje")

            EditorialSettingsCardGroup {
                if showsCookidooRow {
                    EditorialSettingsRow(
                        icon: "app.connected.to.app.below.fill",
                        iconColor: SCPalette.sage,
                        title: "Cookidoo (Thermomix)",
                        value: cookidooRowValue,
                        isLast: !FeatureFlags.health,
                        action: { showCookidooSheet = true }
                    )
                }

                if FeatureFlags.health {
                    EditorialSettingsRow(
                        icon: "figure.walk",
                        iconColor: SCPalette.terracotta,
                        title: "Zdrowie",
                        value: healthRowValue,
                        isLast: true,
                        action: { showHealthSheet = true }
                    )
                }
            }
        }
    }

    /// Sekcja „Integracje” znika, gdy nie ma w niej ani jednego wiersza
    /// (obie funkcje schowane w `FeatureFlags`).
    private var showsIntegrationsSection: Bool {
        showsCookidooRow || FeatureFlags.health
    }

    /// Prawa kolumna wiersza „Zdrowie": nazwa wybranego źródła kroków, gdy
    /// integracja działa — od razu widać, czy kroki idą z Apple, czy z Garmina.
    private var healthRowValue: String {
        guard healthStepsEnabled else { return "Nie połączono" }
        return healthStepsSource == StepsSource.garmin.rawValue ? "Garmin" : "Apple Zdrowie"
    }

    /// Prawa kolumna wiersza Cookidoo. Pusta przy `.unknown` — lepiej nie
    /// pisać nic, niż zgadywać, zanim serwer odpowie po zimnym starcie.
    private var cookidooRowValue: String? {
        switch sessionStore.cookidooIntegrationStore?.status {
        case .connected:
            return "Połączono"
        case .authFailed:
            return "Błąd logowania"
        case .notConnected:
            return "Nie połączono"
        case .disabled:
            return "Wyłączone"
        case .unknown, nil:
            return nil
        }
    }

    /// Wiersz Cookidoo znika, gdy serwer ma integrację wyłączoną — każde
    /// dotknięcie kończyło się alertem „na razie wyłączone".
    private var showsCookidooRow: Bool {
        guard FeatureFlags.thermomix else { return false }
        if case .disabled = sessionStore.cookidooIntegrationStore?.status { return false }
        return true
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSettingsSectionHeader(title: "Informacje")

            EditorialSettingsCardGroup {
                EditorialSettingsRow(
                    icon: "questionmark",
                    iconColor: SCPalette.teal,
                    title: "Pomoc i FAQ",
                    action: { showSupportPage = true }
                )

                // Strona recenzji w App Store, nie `requestReview()`: systemowa
                // prośba o ocenę ma limit (najwyżej 3 razy w roku) i po jego
                // wyczerpaniu stuknięcie nie robiło NIC. Wiersz to jawna prośba
                // użytkownika, więc dostaje pewną drogę.
                EditorialSettingsRow(
                    icon: "star.fill",
                    iconColor: SCPalette.rose,
                    title: "Oceń aplikację",
                    action: openWriteReview
                )

                // Jedno wejście do dokumentów i eksportu danych — polityka
                // obiecuje wgląd „w Aplikacji”, a stopka logowania to za mało.
                EditorialSettingsRow(
                    icon: "hand.raised.fill",
                    iconColor: SettingsAccent.slate,
                    title: "Prywatność i regulamin",
                    value: "v\(LegalDocMeta.version)",
                    isLast: true,
                    action: { showLegalDocumentsSheet = true }
                )
            }
        }
    }

    /// Wersja aplikacji jako cichy podpis pod „Wyloguj się” (6.10.2026) —
    /// dawny wiersz „Wersja” z kafelkiem „i” wyglądał na stuknięty, a nic
    /// nie robił.
    private var versionCaption: some View {
        Text("Scoffie \(appVersionLabel)")
            .font(.sc(size: 12.5))
            .monospacedDigit()
            .foregroundStyle(Color.scFaint(scheme))
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Wersja aplikacji \(appVersionLabel)")
    }

    // MARK: - Sheets
    //
    // Every sheet shares the same chassis as the main settings list — warm
    // `SCPageBackground` canvas, editorial header (kafelek + eyebrow + title +
    // xmark; kafelek i kolor z wiersza listy, który otwiera arkusz),
    // and `Color.scTileBg` cards with `Color.scTileStroke` hairlines. The
    // existing data wiring (createHousehold / leaveCurrentHousehold /
    // createInvitationLink, AppStorage flags) is preserved unchanged.

    private var createHouseholdSheet: some View {
        editorialSheet {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Kafelek domu w indygo — jak wiersz „Gospodarstwo”
                    // i arkusz istniejącego gospodarstwa.
                    EditorialSheetHeader(
                        eyebrow: "Nowe gospodarstwo",
                        title: "Utwórz wspólną przestrzeń",
                        icon: "house.fill",
                        accent: SCPalette.indigo
                    ) {
                        showCreateHouseholdSheet = false
                    }

                    Text("Nadaj nazwę miejscu, w którym domownicy planują posiłki i robią zakupy razem.")
                        .font(.sc(size: 13.5, weight: .regular))
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    editorialNameInputCard

                    editorialPrimaryButton(
                        title: "Utwórz gospodarstwo",
                        icon: "house.badge.plus",
                        isEnabled: canSubmitCreateHousehold,
                        action: submitCreateHousehold
                    )

                    if let error = sessionStore.authError, !error.isEmpty {
                        SCInlineErrorText(error)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var householdManagementSheet: some View {
        // „Opuść gospodarstwo” przypięte na samym dole arkusza (Rafał
        // 7.10.2026: „daj na samym dole”). Od 6.10 stało na końcu treści,
        // czyli przy krótkiej liście domowników — w połowie arkusza.
        pinnedEditorialSheet(
            header: { householdHeader },
            content: { householdSheetContent },
            showsFooter: hasHousehold,
            footer: { leaveHouseholdButton }
        )
        .alert("Opuścić gospodarstwo?", isPresented: $showLeaveHouseholdAlert) {
            Button("Anuluj", role: .cancel) {}
            Button("Opuść", role: .destructive) {
                Task {
                    await sessionStore.leaveCurrentHousehold()
                    if sessionStore.currentHouseholdId == nil {
                        persistedHouseholdName = ""
                        showHouseholdSheet = false
                    }
                }
            }
        } message: {
            Text("Stracisz dostęp do wspólnego planu i listy zakupów.")
        }
        .alert(
            "Usunąć domownika?",
            isPresented: Binding(
                get: { memberToRemove != nil },
                set: { if !$0 { memberToRemove = nil } }
            ),
            presenting: memberToRemove
        ) { member in
            Button("Anuluj", role: .cancel) {}
            Button("Usuń", role: .destructive) {
                Task { await removeMember(member) }
            }
        } message: { member in
            Text("\(member.displayName) straci dostęp do wspólnego planu i listy zakupów tego gospodarstwa.")
        }
        .alert("Nazwa gospodarstwa", isPresented: $showRenameHouseholdAlert) {
            TextField("Np. Dom", text: $renameDraft)
                .textInputAutocapitalization(.words)
            Button("Anuluj", role: .cancel) {}
            Button("Zapisz") {
                let name = renameDraft
                Task { await sessionStore.renameHousehold(to: name) }
            }
            .disabled(!SessionStore.isValidHouseholdName(
                renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        } message: {
            Text("Widzą ją wszyscy domownicy. Od \(Self.householdNameMinLength) do \(Self.householdNameMaxLength) znaków.")
        }
    }

    // ─── Powiadomienia ─────────────
    //
    // 6.10.2026 (artefakt „Arkusze Ustawień”, sekcja 6): główny przełącznik to
    // zwykły wiersz listy z systemowym `Toggle` — dawna karta z dzwonkiem 64 pt
    // i akapitem odpadła. Bez zgody iOS ten sam pierwszy wiersz prosi o zgodę
    // („Włącz powiadomienia”) albo prowadzi do Ustawień iOS („Otwórz”). Kanały
    // w dwóch grupach, tak jak naprawdę działają: „Dla Ciebie” planuje telefon
    // (`MealReminderService`), „Od domowników” wysyła serwer, gdy ktoś inny
    // coś zmieni. Opis każdego kanału w jednej linii.
    private var notificationsSheet: some View {
        pinnedEditorialSheet {
            EditorialSheetHeader(
                eyebrow: "Personalizacja",
                title: "Powiadomienia",
                icon: "bell.fill",
                accent: SettingsAccent.coral
            ) {
                showNotificationsSheet = false
            }
        } content: {
            VStack(alignment: .leading, spacing: 18) {
                // Podgląd zamiast opisu: tak przyjdzie wybrany kanał.
                // Stuknięcie albo włączenie kanału niżej podmienia przykład.
                NotificationPreviewCard(
                    kind: notificationPreview,
                    isActive: notificationChannelsActive && isPreviewChannelOn
                )

                EditorialSettingsCardGroup {
                    notificationsMasterRow
                }

                VStack(alignment: .leading, spacing: 18) {
                    notificationChannelGroup(title: "Dla Ciebie") {
                        channelToggleRow(
                            icon: "sun.horizon.fill",
                            accent: SCPalette.butter,
                            kind: .morning,
                            title: "Poranny przegląd",
                            subtitle: "Posiłki i kalorie na dziś",
                            isOn: $morningBriefingEnabled,
                            isLast: false
                        )

                        channelToggleRow(
                            icon: "clock.fill",
                            accent: SCPalette.sage,
                            kind: .meals,
                            title: "Pory posiłków",
                            subtitle: "Kiedy zacząć gotować",
                            isOn: $mealRemindersEnabled,
                            isLast: false
                        )

                        channelToggleRow(
                            icon: "moon.stars.fill",
                            accent: SCPalette.indigo,
                            kind: .dayWrapUp,
                            title: "Podsumowanie dnia",
                            subtitle: "Wieczorem, przed jutrem",
                            isOn: $dayWrapUpEnabled,
                            isLast: true
                        )
                    }

                    notificationChannelGroup(title: "Od domowników") {
                        channelToggleRow(
                            icon: "calendar.badge.clock",
                            accent: SCPalette.terracotta,
                            kind: .plan,
                            title: "Zmiany planu",
                            subtitle: "Gdy ktoś skończy zmieniać plan",
                            isOn: $planRemindersEnabled,
                            isLast: false
                        )

                        channelToggleRow(
                            icon: "cart.fill",
                            accent: SCPalette.teal,
                            kind: .shopping,
                            title: "Lista zakupów",
                            subtitle: "Gdy ktoś odhaczy zakupy",
                            isOn: $shoppingRemindersEnabled,
                            isLast: true
                        )
                    }
                }
                // Bez zgody systemu albo przy wyciszonym głównym przełączniku
                // kanały stoją przygaszone i nieruchome.
                .disabled(!notificationChannelsActive)
                .opacity(notificationChannelsActive ? 1 : 0.5)
                .animation(.smooth(duration: 0.2), value: notificationChannelsActive)
            }
        }
    }

    /// Czy system wyświetli powiadomienia. Zanim odpowie (`nil`), arkusz
    /// stoi w układzie „zgoda jest” — tak jest u większości i nic nie mignie.
    private var systemAllowsNotifications: Bool {
        notificationPermission == nil || notificationPermission == .allowed
    }

    /// Przełączniki kanałów coś zmieniają tylko przy zgodzie systemu
    /// i włączonym głównym przełączniku — inaczej stoją przygaszone.
    private var notificationChannelsActive: Bool {
        systemAllowsNotifications && notificationsEnabled
    }

    /// Pierwszy wiersz arkusza: przy zgodzie — główny przełącznik; bez niej —
    /// prośba o zgodę albo droga do Ustawień iOS. Ten sam wiersz listy co
    /// w Ustawieniach (`EditorialSettingsRow`), zmienia się tylko jego treść.
    @ViewBuilder
    private var notificationsMasterRow: some View {
        switch notificationPermission {
        case .notAsked?:
            EditorialSettingsRow(
                icon: "bell.badge.fill",
                iconColor: SettingsAccent.coral,
                title: "Włącz powiadomienia",
                isLast: true,
                action: { requestNotificationPermission() }
            ) {
                if isRequestingNotifications {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    EditorialSettingsChevron()
                }
            }
            .disabled(isRequestingNotifications)
        case .denied?:
            EditorialSettingsRow(
                icon: "bell.slash.fill",
                iconColor: SettingsAccent.coral,
                title: "Wyłączone w ustawieniach iOS",
                isLast: true,
                action: { openSystemNotificationSettings() }
            ) {
                Text("Otwórz")
                    .font(.sc(size: 15, weight: .semibold))
                    .foregroundStyle(SCPalette.terracotta)
                    .fixedSize()
            }
            .accessibilityHint("Otwiera ustawienia powiadomień Scoffie w iOS")
        case .allowed?, nil:
            EditorialSettingsRow(
                icon: notificationsEnabled ? "bell.fill" : "bell.slash.fill",
                iconColor: SettingsAccent.coral,
                title: "Powiadomienia",
                isLast: true
            ) {
                // Systemowy `Toggle` w naturalnym rozmiarze.
                Toggle("Powiadomienia", isOn: $notificationsEnabled)
                    .labelsHidden()
                    .tint(SCPalette.sage)
                    .fixedSize()
            }
        }
    }

    /// Zmiana któregokolwiek przełącznika powiadomień. Steruje `task(id:)`,
    /// więc SwiftUI anuluje poprzednią wysyłkę i planuje nową — bez ręcznego
    /// debounce'u przy szybkim przeklikiwaniu.
    private var notificationPreferencesToken: String {
        [
            notificationsEnabled,
            planRemindersEnabled,
            shoppingRemindersEnabled
        ]
        .map { $0 ? "1" : "0" }
        .joined()
    }

    /// Przełączniki, które zmieniają WYŁĄCZNIE rozkład na telefonie.
    /// Główny wyłącznik jest w obu tokenach: gasi i pushe z serwera,
    /// i przypomnienia planowane lokalnie.
    private var localReminderToken: String {
        [
            notificationsEnabled,
            morningBriefingEnabled,
            mealRemindersEnabled,
            dayWrapUpEnabled
        ]
        .map { $0 ? "1" : "0" }
        .joined()
    }

    /// Grupa kanałów: etykieta sekcji + karta listy jak w Ustawieniach.
    private func notificationChannelGroup<Rows: View>(
        title: String,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: title)
            EditorialSettingsCardGroup {
                rows()
            }
        }
    }

    /// Wiersz kanału — wymiary `EditorialSettingsRow` (kafelek 30, tytuł 15,
    /// wiersz 52, kreska od tytułu), z jednym wierszem opisu pod tytułem
    /// i systemowym `Toggle` po prawej.
    private func channelToggleRow(
        icon: String,
        accent: Color,
        kind: NotificationPreviewCard.Kind,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            EditorialSettingsTileIcon(icon: icon, color: accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.sc(size: 15, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.sc(size: 12.5, weight: .regular))
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(SCPalette.sage)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        // Stuknięcie w wiersz (poza przełącznikiem) pokazuje jego przykład
        // na górze; włączenie kanału — też.
        .contentShape(Rectangle())
        .onTapGesture { notificationPreview = kind }
        .onChange(of: isOn.wrappedValue) { _, isNowOn in
            if isNowOn { notificationPreview = kind }
        }
        .background(accent.opacity(notificationPreview == kind ? (scheme == .dark ? 0.10 : 0.06) : 0))
        .animation(.smooth(duration: 0.2), value: notificationPreview == kind)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    .padding(.leading, 12 + 30 + 12)
            }
        }
    }

    /// Czy kanał z podglądu jest włączony — wyłączony pokazuje się wygaszony.
    private var isPreviewChannelOn: Bool {
        switch notificationPreview {
        case .morning:   return morningBriefingEnabled
        case .meals:     return mealRemindersEnabled
        case .dayWrapUp: return dayWrapUpEnabled
        case .plan:      return planRemindersEnabled
        case .shopping:  return shoppingRemindersEnabled
        }
    }

    // ─── Wygląd ─────────────────
    //
    // Trzy karty z podglądem ekranu — wybiera się to, co się zobaczy
    // (6.10.2026, artefakt „Arkusze Ustawień”, sekcja 7): „Automatycznie” na
    // górze, bo to domyślne, nazwa + jeden podpis po polsku (bez „Cozy
    // daylight / Cozy night” i akapitu nad kartami), kółko wyboru po prawej,
    // wybrana w tincie jak każda karta wyboru (`scChoiceSurface(.tile)`).
    private static let themeOrder: [AppTheme] = [.system, .light, .dark]

    private var appearanceSheet: some View {
        pinnedEditorialSheet {
            EditorialSheetHeader(
                eyebrow: "Personalizacja",
                title: "Wygląd",
                icon: "circle.lefthalf.filled",
                accent: SCPalette.lavender
            ) {
                showAppearanceSheet = false
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Self.themeOrder) { theme in
                    themePreviewCard(theme)
                }

                Text("Zmienia się od razu, na tym ekranie też.")
                    .font(.sc(size: 12.5))
                    .foregroundStyle(Color.scFaint(scheme))
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
            }
        }
    }

    private func themePreviewCard(_ theme: AppTheme) -> some View {
        let selected = theme.rawValue == themeRawValue

        return Button {
            withAnimation(.smooth(duration: 0.25)) {
                themeRawValue = theme.rawValue
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                themeCanvasPreview(theme)
                    .frame(width: 58, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.scTileStroke(scheme), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(theme.title)
                        .font(.sc(size: 17, weight: .heavy))
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(1)

                    Text(themeDescription(for: theme))
                        .font(.sc(size: 13, weight: .regular))
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SCRadioMark(isOn: selected)
            }
            .padding(14)
            // Zaznaczenie jak zaznaczony `SCChoiceTile`: tint i obwódka
            // akcentu, bez cienia.
            .scChoiceSurface(
                RoundedRectangle(cornerRadius: 18, style: .continuous),
                isOn: selected,
                offFill: Color.scTileBg(scheme),
                style: .tile
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.title)\(selected ? ", wybrane" : "")")
    }

    /// Mini ekran — tło `SCPageBackground` z poświatą u góry, nagłówek,
    /// karta i terakotowy akcent; „Automatycznie” pół na pół.
    @ViewBuilder
    private func themeCanvasPreview(_ theme: AppTheme) -> some View {
        switch theme {
        case .light:
            themePreviewBlock(scheme: .light, width: 58, horizontalInset: 6)
        case .dark:
            themePreviewBlock(scheme: .dark, width: 58, horizontalInset: 6)
        case .system:
            HStack(spacing: 0) {
                themePreviewBlock(scheme: .light, width: 29, horizontalInset: 4)
                themePreviewBlock(scheme: .dark, width: 29, horizontalInset: 4)
            }
        }
    }

    private func themePreviewBlock(scheme: ColorScheme, width: CGFloat, horizontalInset: CGFloat) -> some View {
        let base = scheme == .dark
            ? Color(red: 12 / 255, green: 8 / 255, blue: 6 / 255)
            : Color(red: 251 / 255, green: 245 / 255, blue: 234 / 255)
        let glow = SCPalette.terracotta.opacity(scheme == .dark ? 0.18 : 0.14)
        let label = scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255)
        let accent = scheme == .dark
            ? Color(red: 219 / 255, green: 132 / 255, blue: 82 / 255)
            : Color(red: 182 / 255, green: 100 / 255, blue: 60 / 255)
        let inner = max(width - horizontalInset * 2, 1)

        return ZStack(alignment: .topLeading) {
            base
            RadialGradient(
                colors: [glow, .clear],
                center: UnitPoint(x: 0.5, y: 0),
                startRadius: 0,
                endRadius: 50
            )

            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(label.opacity(0.85))
                    .frame(width: inner * 0.7, height: 5)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(label.opacity(0.4))
                    .frame(width: inner, height: 4)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(label.opacity(0.08))
                    .frame(width: inner, height: 14)

                Spacer(minLength: 0)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: inner * 0.45, height: 6)
            }
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, 8)
        }
        .frame(width: width)
    }

    private func themeDescription(for theme: AppTheme) -> String {
        switch theme {
        case .system: return "Razem z motywem iOS"
        case .light:  return "Kremowe tło, ciepłe akcenty"
        case .dark:   return "Ciepła czerń, łagodna wieczorem"
        }
    }

    // ─── Dieta i alergeny ──────────
    //
    // Two-section sheet: pick one diet (single-select rows with icon tile +
    // radio dot), then toggle any allergens (multi-select chip cloud).
    // Both selections persist to `@AppStorage` instantly — the xmark
    // button is the only way out, no save / cancel needed.
    private var dietSheet: some View {
        // Własny stos nawigacji: wybór alergenów i „Twoje dane” wjeżdżają jako
        // kolejne ekrany TEGO arkusza, nie arkusze na nim. Pierwszy ekran
        // zostaje przy swoim nagłówku (pasek systemu schowany).
        NavigationStack {
            pinnedEditorialSheet {
                EditorialSheetHeader(
                    eyebrow: "Personalizacja",
                    title: "Dieta i alergeny",
                    icon: "leaf.fill",
                    accent: SCPalette.sage,
                    detail: dietHeaderDetail
                ) {
                    showDietSheet = false
                }
            } content: {
                // Od liczby do skutku (6.10.2026, artefakt „Arkusze Ustawień”,
                // sekcja 3): kalorie, zaraz pod nimi makro, które się z nich
                // liczy, potem cel (jego „Ustaw” siedzi w karcie kalorii),
                // dieta i alergeny, które odsiewają przepisy. Akapit wstępu odpadł.
                VStack(alignment: .leading, spacing: 18) {
                    calorieGoalSection
                    macroSection
                    goalPickerSection
                    dietPickerSection
                    allergensSection

                    if hasCustomisedPreferences {
                        resetPreferencesButton
                            .padding(.top, 4)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showsAllergenPicker) {
                AllergenPickerSheet(
                    selected: selectedAllergens,
                    hiddenRecipes: allergenHiddenRecipes,
                    onToggle: { toggleAllergen($0) },
                    onClear: { clearAllergens() },
                    isPushed: true
                )
            }
            .navigationDestination(isPresented: $showsProfileFromDiet) {
                // Usunięcie konta stamtąd zamyka cały arkusz.
                ProfileDetailsSheet(onClose: { showDietSheet = false }, isPushed: true)
            }
        }
        // Alert, zapis i jego licznik na STOSIE, nie na pierwszym ekranie:
        // ekran przykryty wepchniętym znika z widoku (`onDisappear`), a `task`
        // związany z nim anulowałby się razem z nim — zmiana alergenów na
        // ekranie wyboru nie doszłaby wtedy na serwer.
        //
        // Na arkuszu diety, a nie na ekranie Ustawień — alert podpięty pod
        // widok przykryty arkuszem się nie pokaże.
        .alert("Wyczyścić preferencje?", isPresented: $showResetPreferencesAlert) {
            Button("Anuluj", role: .cancel) {}
            Button("Wyczyść", role: .destructive) { resetPreferences() }
        } message: {
            Text("Dieta, cel, makroskładniki i alergeny wrócą do ustawień domyślnych. Przepisy ukryte przez alergeny znów się pokażą.")
        }
        // Debounced sync: every time any of the three preference fields
        // changes the previous task is cancelled and a new one is scheduled
        // 600ms later. Slider drags coalesce into a single backend write
        // instead of one per micro-step. Pierwsze odpalenie (samo otwarcie
        // arkusza) jest pomijane — patrz `didObserveDietPreferencesToken`.
        .onAppear { didObserveDietPreferencesToken = false }
        .task(id: dietPreferencesSyncToken) {
            guard didObserveDietPreferencesToken else {
                didObserveDietPreferencesToken = true
                return
            }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await sessionStore.saveUserPreferences(
                diet: currentDiet.rawValue,
                calorieGoal: calorieGoal,
                allergens: allergensPayload,
                goal: currentGoal.rawValue,
                proteinG: proteinOverride >= 0 ? proteinOverride : nil,
                fatG: fatOverride >= 0 ? fatOverride : nil,
                carbsG: carbsOverride >= 0 ? carbsOverride : nil,
                // „Czego nie jem” zniknęło z aplikacji (23.09.2026), ale kolumny
                // na serwerze zostały i walidator planu dalej je czyta. Każdy
                // zapis preferencji jawnie je zeruje, żeby nikt nie został
                // z blokadą, której nie widzi i nie ma jak zdjąć — patrz też
                // sprzątanie w `SessionStore.loadUserPreferences`.
                excludedIngredientIds: [],
                clearMaxPrepTime: true,
                clearMacroOverrides: !hasMacroOverride
            )
        }
    }

    /// Linijka pod tytułem arkusza: dieta i liczba omijanych alergenów
    /// („Wegetariańska · 3 alergeny”); bez alergenów — sama dieta.
    private var dietHeaderDetail: String {
        let count = selectedAllergens.count
        guard count > 0 else { return currentDiet.title }
        let noun = PolishPlural.form(count, one: "alergen", few: "alergeny", many: "alergenów")
        return "\(currentDiet.title) · \(count) \(noun)"
    }

    /// Czy jest co czyścić — steruje widocznością „Wyczyść preferencje”.
    private var hasCustomisedPreferences: Bool {
        currentDiet != .none
            || currentGoal != .healthy
            || calorieGoal != Self.calorieGoalDefault
            // Po tokenach, nie po rozpoznanych chipach: użytkownik, którego
            // jedyne alergeny pochodzą z nowszego buildu, też ma co czyścić.
            || !allergenTokens.isEmpty
            || hasMacroOverride
    }

    /// Stable token that changes whenever the user touches any preference
    /// field — drives `task(id:)` so SwiftUI cancels the in-flight save and
    /// schedules a fresh one. Using a single concatenated string keeps the
    /// modifier signature simple.
    private var dietPreferencesSyncToken: String {
        "\(dietPreferenceRaw)|\(calorieGoal)|\(allergensRaw)|\(goalRaw)|\(proteinOverride)|\(fatOverride)|\(carbsOverride)"
    }

    // ─── Twój cel ──────────
    //
    // Ten sam wybór, co w kroku 2 kreatora powitalnego — powtórzony tutaj,
    // bo po onboardingu nie było jak go zmienić. Cel nie odsiewa przepisów;
    // przestawia kolejność listy (patrz `RecipePersonalization.goalScore`).
    // Jego podpowiedź kaloryczna („Ustaw”) siedzi w karcie kalorii wyżej.
    private var goalPickerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Twój cel")

            VStack(spacing: 0) {
                ForEach(Array(UserGoal.allCases.enumerated()), id: \.element.id) { idx, goal in
                    goalRow(goal, isLast: idx == UserGoal.allCases.count - 1)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func goalRow(_ goal: UserGoal, isLast: Bool) -> some View {
        let isSelected = goal == currentGoal

        return Button {
            withAnimation(.smooth(duration: 0.20)) {
                goalRaw = goal.rawValue
            }
        } label: {
            choiceRowLabel(
                icon: goal.icon,
                accent: goal.accent,
                title: goal.title,
                subtitle: Self.goalShortSubtitle(goal),
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !isLast { choiceRowRule }
        }
        .accessibilityLabel(goal.title)
        .accessibilityValue(isSelected ? "Wybrane" : "")
    }

    /// Wiersz wyboru celu i diety — wymiary wiersza Ustawień
    /// (`EditorialSettingsRow`: kafelek 30, tytuł 15, wiersz 52, kreska od
    /// tytułu), podpis w JEDNEJ linii, kółko wyboru po prawej.
    private func choiceRowLabel(
        icon: String,
        accent: Color,
        title: String,
        subtitle: String,
        isSelected: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            EditorialSettingsTileIcon(icon: icon, color: accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.sc(size: 15, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.sc(size: 12.5, weight: .regular))
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SCRadioMark(isOn: isSelected)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private var choiceRowRule: some View {
        Rectangle()
            .fill(Color.scRule(scheme))
            .frame(height: 1)
            .padding(.leading, 12 + 30 + 12)
    }

    /// Podpisy celów w jednej linii — krótsze niż `UserGoal.subtitle`, którego
    /// dłuższe zdania zostają w kreatorze.
    private static func goalShortSubtitle(_ goal: UserGoal) -> String {
        switch goal {
        case .healthy:  return "Zbilansowane, mniej przetworzonych"
        case .lose:     return "Lekki deficyt kaloryczny"
        case .gain:     return "Nadwyżka kaloryczna z białkiem"
        case .maintain: return "Kalorie na utrzymanie"
        case .plan:     return "Bez celu kalorycznego"
        }
    }

    /// Podpisy diet w jednej linii — krótsze niż `DietPreference.subtitle`
    /// (kreator zostaje przy swoich).
    private static func dietShortSubtitle(_ diet: DietPreference) -> String {
        switch diet {
        case .none:        return "Wszystkie przepisy"
        case .vegetarian:  return "Bez mięsa i ryb"
        case .vegan:       return "Bez produktów odzwierzęcych"
        case .pescatarian: return "Bez mięsa, z rybami"
        case .keto:        return "Bardzo mało węglowodanów"
        case .paleo:       return "Bez zbóż, nabiału i przetworzonych"
        case .highProtein: return "Min. 20 % kalorii z białka"
        }
    }

    /// Cel niesie ze sobą sugerowaną kaloryczność, ale ustawiony wcześniej
    /// suwak jest decyzją użytkownika — więc podpowiadamy przyciskiem zamiast
    /// nadpisywać. Kreator powitalny robi to samo, tyle że tam suwak jeszcze
    /// nie był ruszany, więc może iść za celem sam.
    private var showsCalorieSuggestion: Bool {
        currentGoal != .plan && calorieGoal != suggestedCalories
    }

    /// Dwa warianty: policzony z sylwetki (wtedy mówimy skąd) i awaryjny,
    /// gdy w profilu brakuje danych. Drugi zachęca do ich uzupełnienia,
    /// zamiast udawać, że liczba jest szyta na miarę.
    private var calorieSuggestionText: String {
        guard bodyMetrics != nil else {
            return "Dla tego celu zwykle wychodzi \(suggestedCalories) kcal"
        }
        return "Dla celu „\(currentGoal.title)” wychodzi \(suggestedCalories) kcal"
    }

    /// Podpowiedź na dole karty kalorii: żarówka, zdanie i „Ustaw”. Bez
    /// sylwetki pod zdaniem odsyłacz „Twoje dane ›”.
    private var calorieSuggestionRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.sc(size: 15, weight: .semibold))
                .foregroundStyle(SCPalette.butter)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(calorieSuggestionText)
                    .font(.sc(size: 13, weight: .regular))
                    .foregroundStyle(Color.scMuted(scheme))
                    .contentTransition(.numericText())
                    .fixedSize(horizontal: false, vertical: true)

                // Odsyłacz do sylwetki prowadzi TAM, w tym samym arkuszu —
                // zamiast kazać zamknąć dietę i szukać karty profilu.
                if bodyMetrics == nil {
                    openProfileFromDietLink
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.smooth(duration: 0.22)) {
                    calorieGoal = snappedCalorieGoal(from: Double(suggestedCalories))
                }
            } label: {
                Text("Ustaw")
                    .font(.sc(size: 12, weight: .bold))
                    .foregroundStyle(SCPalette.terracotta)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    // Wariant „soft” = szkło w tincie terakoty.
                    .scSoftCapsule()
            }
            .buttonStyle(PlanPressStyle(scale: 0.94))
            .accessibilityLabel("Ustaw \(suggestedCalories) kcal")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(SCPalette.butter.opacity(scheme == .dark ? 0.10 : 0.07))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.scRule(scheme))
                .frame(height: 1)
        }
    }

    private var dietPickerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Sposób odżywiania")

            VStack(spacing: 0) {
                ForEach(Array(DietPreference.allCases.enumerated()), id: \.element.id) { idx, diet in
                    dietRow(diet, isLast: idx == DietPreference.allCases.count - 1)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func dietRow(_ diet: DietPreference, isLast: Bool) -> some View {
        let isSelected = diet == currentDiet

        return Button {
            withAnimation(.smooth(duration: 0.20)) {
                dietPreferenceRaw = diet.rawValue
            }
        } label: {
            // Dokładnie ta sama geometria co `goalRow` — obie sekcje to ta
            // sama lista wyboru i mają wyglądać identycznie.
            choiceRowLabel(
                icon: diet.icon,
                accent: diet.accent,
                title: diet.title,
                subtitle: Self.dietShortSubtitle(diet),
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !isLast { choiceRowRule }
        }
        .accessibilityLabel(diet.title)
        .accessibilityValue(isSelected ? "Wybrane" : "")
    }

    // ─── Makroskładniki ──────────
    //
    // Domyślnie liczone z celu, sylwetki i liczby treningów — użytkownik nie
    // musi nic robić i wartości same podążają, gdy zmieni cel albo dołoży
    // treningów. Każde makro da się jednak nadpisać: „max 2200 kcal, ale
    // 160 g białka" to normalny sposób prowadzenia redukcji i aplikacja nie
    // ma prawa go blokować.
    @ViewBuilder
    private var macroSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Makroskładniki")

            VStack(alignment: .leading, spacing: 0) {
                if let macros = effectiveMacros {
                    macroRow(.protein, value: macros.proteinG, override: $proteinOverride)
                    macroDivider
                    macroRow(.carbs, value: macros.carbsG, override: $carbsOverride)
                    macroDivider
                    macroRow(.fat, value: macros.fatG, override: $fatOverride)
                    // Kreska nad stopką idzie na pełną szerokość, bo stopka
                    // ma własne tło rozciągnięte od krawędzi do krawędzi —
                    // wcięta kreska kończyła się w innym miejscu niż kolor
                    // pod nią i wyglądało to na niedoróbkę.
                    Rectangle()
                        .fill(Color.scRule(scheme))
                        .frame(height: 1)
                    macroFooter(macros)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Uzupełnij sylwetkę w „Twoje dane”, a rozbijemy dzienny cel na białko, węglowodany i tłuszcze.")
                            .font(.sc(size: 12.5, weight: .medium))
                            .foregroundStyle(Color.scMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)

                        openProfileFromDietLink
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    /// „Twoje dane ›” — odsyłacz z arkusza diety do sylwetki. Wpycha ekran
    /// „Twoje dane” w ten arkusz (`showsProfileFromDiet`); „wstecz” wraca do
    /// diety z policzonymi już kaloriami i makro.
    private var openProfileFromDietLink: some View {
        Button {
            showsProfileFromDiet = true
        } label: {
            HStack(spacing: 3) {
                Text("Twoje dane")
                    .font(.sc(size: 13, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.sc(size: 11, weight: .bold))
            }
            .foregroundStyle(SCPalette.terracotta)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.96))
        .accessibilityHint("Otwiera wzrost, wagę i rok urodzenia")
    }

    private var macroDivider: some View {
        Rectangle()
            .fill(Color.scRule(scheme))
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private enum Macro {
        case protein, carbs, fat

        var title: String {
            switch self {
            case .protein: return "Białko"
            case .carbs:   return "Węglowodany"
            case .fat:     return "Tłuszcze"
            }
        }

        var accent: Color {
            switch self {
            case .protein: return SCPalette.indigo
            case .carbs:   return SCPalette.sage
            case .fat:     return SCPalette.butter
            }
        }

        /// Ten sam krok, do którego zaokrąglane są wyliczenia — inaczej
        /// stepper wyprowadzałby wartość z siatki („193 g") i pół karty
        /// pokazywałoby okrągłe liczby, a pół nie.
        var step: Int { MacroTargets.gramStep }

        var upperBound: Int {
            switch self {
            case .protein: return 400
            case .carbs:   return 800
            case .fat:     return 300
            }
        }
    }

    private func macroRow(_ macro: Macro, value: Int, override: Binding<Int>) -> some View {
        let isOverridden = override.wrappedValue >= 0

        return HStack(spacing: 12) {
            Circle()
                .fill(macro.accent)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(macro.title)
                    .font(.sc(size: 14.5, weight: .semibold))
                    .foregroundStyle(Color.scLabel(scheme))

                Text(isOverridden ? "Twoja wartość" : "Wyliczone")
                    .font(.sc(size: 11, weight: .medium))
                    .foregroundStyle(isOverridden ? macro.accent : Color.scFaint(scheme))
            }

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(.sc(size: 17, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))
                    .contentTransition(.numericText(value: Double(value)))

                Text("g")
                    .font(.sc(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .frame(minWidth: 58, alignment: .trailing)

            macroStepper(macro, value: value, override: override)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.smooth(duration: 0.18), value: value)
    }

    /// Minus / plus zamiast pola tekstowego. Makra reguluje się o kilka
    /// gramów w jedną albo drugą stronę, a nie wpisuje od zera — a przy okazji
    /// nie ma tu żadnego stanu pośredniego do zepsucia.
    private func macroStepper(_ macro: Macro, value: Int, override: Binding<Int>) -> some View {
        HStack(spacing: 0) {
            macroStepButton(systemName: "minus", accent: macro.accent) {
                override.wrappedValue = MacroTargets.snappedGrams(Double(value - macro.step))
            }

            Rectangle()
                .fill(Color.scTileStroke(scheme))
                .frame(width: 1, height: 18)

            macroStepButton(systemName: "plus", accent: macro.accent) {
                let next = MacroTargets.snappedGrams(Double(value + macro.step))
                override.wrappedValue = min(next, macro.upperBound)
            }
        }
        .background(Capsule().fill(Color.scChipBg(scheme)))
        .overlay(Capsule().stroke(Color.scTileStroke(scheme), lineWidth: 1))
        .accessibilityLabel(macro.title)
        .accessibilityValue("\(value) gramów")
    }

    private func macroStepButton(
        systemName: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.18)) { action() }
        } label: {
            Image(systemName: systemName)
                .font(.sc(size: 12, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Suma makr rzadko trafia w cel co do kilokalorii — i nie musi. Pokazujemy
    /// ją wprost, żeby po ręcznym podkręceniu białka było widać, że dzienna
    /// pula przestała się spinać, zamiast zostawiać użytkownika z trzema
    /// liczbami bez kontekstu.
    private func macroFooter(_ macros: MacroTargets) -> some View {
        let diff = macros.totalKcal - calorieGoal

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Z makr: \(macros.totalKcal) kcal")
                    .font(.sc(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.scLabel(scheme))

                Text(macroFooterNote(diff: diff))
                    .font(.sc(size: 11.5, weight: .medium))
                    .foregroundStyle(abs(diff) > 60 ? SCPalette.terracotta : Color.scMuted(scheme))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hasMacroOverride {
                Button {
                    withAnimation(.smooth(duration: 0.22)) { resetMacroOverrides() }
                } label: {
                    Text("Policz od nowa")
                        .font(.sc(size: 12, weight: .bold))
                        .foregroundStyle(SCPalette.terracotta)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .scSoftCapsule()
                }
                .buttonStyle(PlanPressStyle(scale: 0.94))
                .accessibilityLabel("Policz makra od nowa")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.scChipBg(scheme).opacity(scheme == .dark ? 0.5 : 0.7))
    }

    private func macroFooterNote(diff: Int) -> String {
        if abs(diff) <= 20 { return "Spina się z dziennym celem" }
        if diff > 0 { return "\(diff) kcal ponad cel" }
        return "\(abs(diff)) kcal poniżej celu"
    }

    private func resetMacroOverrides() {
        proteinOverride = -1
        fatOverride = -1
        carbsOverride = -1
    }

    /// Karta „Kalorie”: wiersz „Dzienny cel” z dużą liczbą po prawej, suwak
    /// co 50 kcal z podpisami skrajnych wartości (`CalorieGoalEditor`), a na
    /// dole podpowiedź celu z „Ustaw” (6.10.2026 — dawniej pod listą celów).
    /// Akapit „Aplikacja podpowie, jak rozłożyć…” odpadł.
    private var calorieGoalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Kalorie")

            VStack(spacing: 0) {
                calorieGoalEditor
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 12)

                if showsCalorieSuggestion {
                    calorieSuggestionRow
                        .transition(.opacity)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    /// Wiersz z dużą liczbą i suwak co 50 kcal — cały wybór. Suwak ma własny
    /// stan na czas przeciągania (`CalorieGoalEditor`), patrz niżej.
    private var calorieGoalEditor: some View {
        CalorieGoalEditor(
            calorieGoal: $calorieGoal,
            range: Self.calorieGoalMin...Self.calorieGoalMax,
            step: Self.calorieGoalStep
        )
    }

    /// Round an arbitrary slider value to the nearest 50-kcal step and
    /// clamp it to the [min, max] range. Defensive against the rare
    /// off-end value the UISlider can emit at the extremes.
    private func snappedCalorieGoal(from raw: Double) -> Int {
        let stepped = (raw / Double(Self.calorieGoalStep)).rounded() * Double(Self.calorieGoalStep)
        return min(max(Int(stepped), Self.calorieGoalMin), Self.calorieGoalMax)
    }

    /// Alergeny w arkuszu diety to sam wynik — co jest wykluczone i ile
    /// przepisów przez to znika. Wybór (`AllergenPickerSheet(isPushed:)`)
    /// wjeżdża jako kolejny ekran tego arkusza, patrz `dietSheet`.
    private var allergensSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Alergeny i nietolerancje")

            AllergenSelectionField(
                selected: selectedAllergens,
                hiddenRecipes: allergenHiddenRecipes,
                onToggle: { toggleAllergen($0) },
                onClear: { clearAllergens() },
                onEdit: { showsAllergenPicker = true }
            )

            Text("Dieta i alergeny odsiewają przepisy, cel ustawia je na liście.")
                .font(.sc(size: 12.5))
                .foregroundStyle(Color.scFaint(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
                .padding(.top, 8)
        }
    }

    /// Ile przepisów katalogu ukrywają same alergeny (bez diety) — `nil`,
    /// dopóki katalog się nie wczytał.
    private var allergenHiddenRecipes: Int? {
        let recipes = recipeCatalogStore.recipes
        guard !recipes.isEmpty else { return nil }
        return RecipePersonalization(avoidedAllergens: selectedAllergens).hiddenCount(in: recipes)
    }

    /// Czyści dietę, cel kaloryczny, makro i wszystkie alergeny — widoczne
    /// tylko wtedy, gdy jest co czyścić, i dopiero po potwierdzeniu
    /// (`showResetPreferencesAlert`), jak każda akcja w `SCDestructiveButton`.
    /// Jedno stuknięcie zdejmowało też alergeny, a przepisy, które ukrywały,
    /// wracały na listę bez słowa.
    private var resetPreferencesButton: some View {
        SCDestructiveButton(title: "Wyczyść preferencje", icon: "arrow.counterclockwise") {
            showResetPreferencesAlert = true
        }
    }

    private func resetPreferences() {
        withAnimation(.smooth(duration: 0.22)) {
            dietPreferenceRaw = DietPreference.none.rawValue
            // Jedyne miejsce, gdzie unia „znane ∪ nieznane" celowo NIE
            // obowiązuje: „Wyczyść" to jawna decyzja i kasuje też wartości,
            // których ten build nie umie narysować.
            allergensRaw = ""
            calorieGoal = Self.calorieGoalDefault
            goalRaw = UserGoal.healthy.rawValue
            resetMacroOverrides()
        }
    }

    /// Treść arkusza gospodarstwa — domownicy (z zaproszeniem jako ostatnim
    /// wierszem), a bez domu karta zakładania. „Opuść gospodarstwo” stoi
    /// w stopce arkusza (`householdManagementSheet`).
    private var householdSheetContent: some View {
        let hasInvitations = !sessionStore.pendingInvitations.isEmpty

        return VStack(alignment: .leading, spacing: 0) {
            // Skrzynka zaproszeń nad resztą i w OBU gałęziach: dla
            // kogoś bez gospodarstwa to jedyna alternatywa dla
            // zakładania własnego, a dla kogoś, kto już gdzieś jest —
            // jedyne miejsce, w którym w ogóle zobaczy, że ktoś go
            // zaprosił.
            if hasInvitations {
                householdInvitationsCard
            }

            if hasHousehold {
                householdMembersSection
                    .padding(.top, hasInvitations ? 20 : 0)
            } else {
                householdEmptyCard
                    .padding(.top, hasInvitations ? 18 : 0)
            }
        }
    }

    // MARK: - Sheet building blocks

    /// Wraps each sheet's content in the shared editorial chassis — warm
    /// `SCPageBackground` behind a transparent `presentationBackground`,
    /// so the sheet card itself adopts the cozy canvas instead of the
    /// system grey.
    @ViewBuilder
    private func editorialSheet<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            content()
        }
    }

    /// Arkusz z nagłówkiem przypiętym NAD przewijaną treścią — dla arkuszy
    /// dłuższych niż ekran (dieta, gospodarstwo). Nagłówek wewnątrz
    /// `ScrollView` odjeżdżał razem z krzyżykiem; tu stoi, a treść gaśnie pod
    /// nim (`scScrollEdgeFade`), bez kreski — jak w szczegółach posiłku
    /// i w filtrach przepisów.
    private func pinnedEditorialSheet<Header: View, Content: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) -> some View {
        pinnedEditorialSheet(header: header, content: content, showsFooter: false) { EmptyView() }
    }

    /// To samo z przyciskiem przypiętym na samym dole arkusza (`scSheetFooter`)
    /// — `showsFooter: false` = bez stopki (gospodarstwo bez domu).
    private func pinnedEditorialSheet<Header: View, Content: View, Footer: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        showsFooter: Bool,
        @ViewBuilder footer: @escaping () -> Footer
    ) -> some View {
        editorialSheet {
            VStack(spacing: 0) {
                header()
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                let scroll = ScrollView {
                    content()
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scScrollEdgeFade()

                if showsFooter {
                    scroll.scSheetFooter(footer)
                } else {
                    scroll
                }
            }
        }
    }

    private var editorialNameInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSheetSectionLabel(title: "Nazwa")

            TextField("Np. Dom", text: $createHouseholdName)
                .textInputAutocapitalization(.words)
                .font(.sc(size: 15.5, weight: .medium))
                .foregroundStyle(Color.scLabel(scheme))
                .tint(SCPalette.terracotta)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.scChipBg(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            householdNameError != nil
                                ? SCInlineErrorText.tint.opacity(0.6)
                                : Color.scTileStroke(scheme),
                            lineWidth: householdNameError != nil ? 1.5 : 1
                        )
                )
                .onChange(of: createHouseholdName) { _, _ in
                    if householdNameError != nil { householdNameError = nil }
                }

            if let error = householdNameError {
                SCInlineErrorText(error)
                    .padding(.horizontal, 4)
            }

            HStack {
                Spacer()
                Text("\(trimmedCreateHouseholdName.count)/\(Self.householdNameMaxLength)")
                    .font(.sc(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(
                        trimmedCreateHouseholdName.count > Self.householdNameMaxLength
                            ? SCInlineErrorText.tint
                            : Color.scFaint(scheme)
                    )
            }
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

    // ─── Gospodarstwo ─────────────
    //
    // Tylko to, po co się tu wchodzi: kto mieszka w domu, jak zaprosić
    // kolejną osobę i jak wyjść. Nazwa domu stoi w nagłówku z ikoną domu
    // i samym „3 osoby” pod nazwą, ołówek do nazwy — obok krzyżyka,
    // wyjście — na końcu przewijanej treści (6.10.2026).
    //
    // Trzy rundy uwag Rafała (23.09.2026): najpierw „za dużo zbędnego tekstu”
    // (karta z powtórzoną nazwą, liczby osób w trzech miejscach, sekcja
    // o tym, co domownicy dzielą), potem „znów pusto i smutno” (zaproszenie
    // jako osobna karta z jednym przyciskiem), a w końcu „usuń info
    // o diecie czy czymkolwiek innym, to tu nie ma sensu”. Wiersz domownika
    // to dziś sama tożsamość: awatar, imię i plakietki „Ty” / „Właściciel”.

    private var householdOwner: HouseholdMemberSnapshot? {
        householdMembers.first { $0.role.uppercased() == "OWNER" }
    }

    private var householdMembersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Domownicy")

            VStack(spacing: 0) {
                if isLoadingMembers {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Wczytuję domowników…")
                            .font(.sc(size: 12.5, weight: .medium))
                            .foregroundStyle(Color.scMuted(scheme))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                } else if householdMembers.isEmpty {
                    Text("Nie udało się wczytać domowników.")
                        .font(.sc(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.scMuted(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    ForEach(Array(householdMembers.enumerated()), id: \.element.id) { index, member in
                        memberRow(member, showsRule: index > 0)
                    }

                    // Zaproszenie to OSTATNI wiersz listy domowników — jak
                    // „dodaj” w listach systemu (Rafał 4.10.2026: „pod
                    // domownikami albo nad, ładniej i czytelniej”). Dawniej
                    // dwuwierszowy kafel w stopce nad „Opuść”.
                    if canCreateInvitations {
                        inviteRow
                    }
                }

            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if !canCreateInvitations, let owner = householdOwner {
                Text("Zaprasza właściciel: \(HouseholdMemberStyle.shortName(owner.displayName))")
                    .font(.sc(size: 12, weight: .medium))
                    .foregroundStyle(Color.scFaint(scheme))
                    .padding(.horizontal, 6)
                    .padding(.top, 10)
            }

            if let error = sessionStore.authError, !error.isEmpty {
                SCInlineErrorText(error)
                    .padding(.horizontal, 6)
                    .padding(.top, 10)
            }
        }
    }

    /// Nagłówek arkusza gospodarstwa: wspólny `EditorialSheetHeader` z ikoną
    /// domu w szałwii (ta sama co w wierszu „Gospodarstwo” w Ustawieniach),
    /// nazwą domu i jedną linijką o nim. Ołówek do nazwy stoi obok krzyżyka.
    private var householdHeader: some View {
        EditorialSheetHeader(
            eyebrow: hasHousehold ? "Twoje gospodarstwo" : "Gospodarstwo",
            title: hasHousehold ? persistedHouseholdName : "Brak gospodarstwa",
            icon: "house.fill",
            accent: SCPalette.indigo,
            // Pod nazwą, obok kafelka — samo „3 osoby” (6.10.2026).
            detail: hasHousehold && !householdMembers.isEmpty ? householdSummary : nil,
            onClose: { showHouseholdSheet = false }
        ) {
            // Nazwę zmienia tylko właściciel — ta sama brama co na
            // serwerze (`ensureOwner` w `households:updateName`).
            if hasHousehold && canCreateInvitations {
                SCSheetIconButton(systemName: "pencil", accessibilityLabel: "Zmień nazwę gospodarstwa") {
                    renameDraft = persistedHouseholdName
                    showRenameHouseholdAlert = true
                }
            }
        }
    }

    /// „3 osoby” — jedyne miejsce z liczbą osób. Dopisek „· wspólny plan
    /// i lista zakupów” odpadł 6.10.2026 (objaśnienie, nie informacja).
    private var householdSummary: String {
        let count = householdMembers.count
        return "\(count) \(membersLabel(for: count))"
    }

    /// Wiersz „Zaproś domownika” na końcu listy domowników, w układzie wiersza
    /// osoby: w miejscu awatara przerywane kółko z plusem (miejsce na kolejną
    /// osobę), tytuł i warunki linku, z prawej szklany krążek udostępniania.
    /// Link tworzy się sam przy otwarciu arkusza
    /// (`preloadHouseholdContextIfNeeded`), więc zwykle od razu jest czym się
    /// podzielić; bez linku krążek ma strzałkę „przygotuj ponownie”.
    @ViewBuilder
    private var inviteRow: some View {
        let isReady = invitationLink != nil
        let label = HStack(spacing: 12) {
            Circle()
                .strokeBorder(
                    SCPalette.terracotta.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
                .background(Circle().fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.12 : 0.08)))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "plus")
                        .font(.sc(size: 16, weight: .bold))
                        .foregroundStyle(SCPalette.terracotta)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(isReady ? "Zaproś domownika" : "Przygotuj zaproszenie")
                    .font(.sc(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(SCPalette.terracotta)
                Text("Link dla jednej osoby · 7 dni")
                    .font(.sc(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if isCreatingInvitation {
                    ProgressView()
                        .controlSize(.small)
                        .tint(SCPalette.terracotta)
                } else {
                    Image(systemName: isReady ? "square.and.arrow.up" : "arrow.clockwise")
                        .font(.sc(size: 14, weight: .semibold))
                        .foregroundStyle(SCPalette.terracotta)
                }
            }
            .frame(width: 34, height: 34)
            .scChromeGlass(in: Circle(), tint: SCPalette.terracotta.opacity(scheme == .dark ? 0.3 : 0.22))
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.scRule(scheme))
                .frame(height: 1)
                .padding(.leading, 14 + 40 + 12)
        }

        if let invitationLink {
            // Systemowy arkusz udostępniania przez `SCShareSheet`, nie
            // `ShareLink`: tylko on mówi, że link naprawdę wyszedł
            // (`completed`) — a dopiero wtedy pytamy o zgodę na powiadomienia.
            Button {
                shareInvitation(invitationLink)
            } label: {
                label
            }
            .buttonStyle(PlanPressStyle(scale: 0.98))
            .accessibilityLabel("Zaproś domownika")
            .accessibilityHint("Udostępnia link zaproszenia ważny 7 dni")
        } else {
            Button {
                Task { await createInvitationLink() }
            } label: {
                label
            }
            .buttonStyle(PlanPressStyle(scale: 0.98))
            .disabled(isCreatingInvitation)
            .accessibilityLabel("Przygotuj zaproszenie")
        }
    }

    /// Link zaproszenia do systemowego arkusza udostępniania. Po WYSŁANIU
    /// (nie po samym otwarciu arkusza) prosimy o zgodę na powiadomienia,
    /// jeśli system jeszcze nie pytał: zaproszony domownik będzie zmieniał
    /// plan i listę, a o tym właśnie mówią powiadomienia. To jest pierwsze
    /// miejsce, w którym prośba ma oczywisty powód — przy starcie aplikacji
    /// nie miała żadnego.
    private func shareInvitation(_ link: URL) {
        SCShareSheet.present(
            url: link,
            title: "Zaproszenie do domu w Scoffie",
            image: nil,
            message: "Dołącz do naszego domu w Scoffie — wspólny plan posiłków i lista zakupów."
        ) {
            Task { @MainActor in
                guard notificationPermission != .allowed,
                      await NotificationPermission.current() == .notAsked else { return }
                // Arkusz udostępniania jeszcze zjeżdża — systemowe okno zgody
                // wchodzi po nim, a nie w trakcie.
                try? await Task.sleep(for: .milliseconds(450))
                await askForNotificationPermission()
            }
        }
    }

    /// Wyjście przypięte na dole arkusza gospodarstwa (7.10.2026; 6.10 na
    /// chwilę na końcu treści), w tym samym stroju co każda akcja
    /// nieodwracalna (`SCDestructiveButton`) i z pytaniem w alercie.
    private var leaveHouseholdButton: some View {
        SCDestructiveButton(title: "Opuść gospodarstwo", icon: "rectangle.portrait.and.arrow.right") {
            showLeaveHouseholdAlert = true
        }
        .disabled(sessionStore.isSigningIn)
        .opacity(sessionStore.isSigningIn ? 0.55 : 1)
    }

    /// Zaproszenia czekające na użytkownika.
    ///
    /// Powód istnienia jest prosty: zaproszenie było wyłącznie linkiem
    /// w komunikatorze. Kto otworzył je w złym momencie — bo należał już do
    /// innego gospodarstwa albo zamknął alert — nie miał w aplikacji ŻADNEGO
    /// śladu, że coś do niego przyszło.
    private var householdInvitationsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Zaproszenia")

            VStack(spacing: 0) {
                ForEach(Array(sessionStore.pendingInvitations.enumerated()), id: \.element.id) { index, invitation in
                    invitationRow(
                        invitation,
                        isLast: index == sessionStore.pendingInvitations.count - 1
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func invitationRow(
        _ invitation: HouseholdInvitationSnapshot,
        isLast: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                EditorialSettingsTileIcon(icon: "envelope.open.fill", color: SCPalette.butter)

                VStack(alignment: .leading, spacing: 2) {
                    Text(invitation.householdName)
                        .font(.sc(size: 15, weight: .semibold))
                        .foregroundStyle(Color.scLabel(scheme))

                    Text(invitation.subtitle)
                        .font(.sc(size: 12, weight: .regular))
                        .foregroundStyle(Color.scMuted(scheme))

                    if let expiry = invitation.expiresAtText {
                        Text("Ważne do: \(expiry)")
                            .font(.sc(size: 11, weight: .medium))
                            .foregroundStyle(Color.scMuted(scheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Dołączenie z gospodarstwa oznacza jego opuszczenie, więc etykieta
            // mówi to wprost zamiast obiecywać samo „Dołącz".
            HStack(spacing: 10) {
                // Neutralna obok terakotowej — jak `AssistantGhostButton`:
                // tło o ton od karty i cienka obwódka. Wcześniej kapsuła
                // wypełniona kolorem tekstu (`scFaint`) czytała się jak ciężka
                // szara płyta, mocniejsza niż akcja główna obok.
                Button {
                    Task { await sessionStore.declineInvitation(token: invitation.token) }
                } label: {
                    Text("Odrzuć")
                        .font(.sc(size: 13, weight: .semibold))
                        .foregroundStyle(Color.scLabel(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        // Neutralne szkło obok „Dołącz” (szkło w tincie).
                        .scChromeGlass(in: Capsule(style: .continuous))
                }
                .buttonStyle(PlanPressStyle(scale: 0.96))

                Button {
                    Task {
                        await sessionStore.acceptPendingInvitation(
                            token: invitation.token,
                            leaveOtherHouseholds: hasHousehold
                        )
                        if sessionStore.currentHouseholdId != nil {
                            persistedHouseholdName = sessionStore.currentHouseholdName ?? persistedHouseholdName
                        }
                    }
                } label: {
                    Text(hasHousehold ? "Przenieś się" : "Dołącz")
                        .font(.sc(size: 13, weight: .bold))
                        .foregroundStyle(SCPalette.terracotta)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .scSoftCapsule()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    .padding(.leading, 16 + 32 + 14)
            }
        }
    }

    private var householdEmptyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                EditorialSettingsTileIcon(icon: "house.badge.plus", color: SCPalette.indigo, size: 44, radius: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Brak gospodarstwa")
                        .font(.sc(size: 17, weight: .heavy))
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(scheme))
                    Text("Utwórz wspólne miejsce do planowania posiłków i listy zakupów.")
                        .font(.sc(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            editorialPrimaryButton(
                title: "Utwórz gospodarstwo",
                icon: "house.badge.plus",
                isEnabled: true
            ) {
                // Karta stoi W arkuszu gospodarstwa (dom zniknął, gdy był
                // otwarty) — arkusz tworzenia zastępuje go zamiast wjeżdżać
                // na niego; dwa arkusze z jednego ekranu SwiftUI i tak by nie
                // pokazał.
                createHouseholdName = ""
                opensCreateAfterHousehold = true
                showHouseholdSheet = false
            }
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

    /// Primary action — terracotta „soft" capsule (tint + hairline in the
    /// accent), the same treatment as `SCSoftButton` and the recipe bar,
    /// sized for a sheet. The filled gradient is gone app-wide: one saturated
    /// slab per screen kept winning over the content it was meant to serve.
    private func editorialPrimaryButton(
        title: String,
        icon: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.sc(size: 13, weight: .heavy))
                Text(title)
                    .font(.sc(size: 14, weight: .bold))
                    .tracking(-0.1)
            }
            .foregroundStyle(SCPalette.terracotta)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .scSoftCapsule()
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.smooth(duration: 0.18), value: isEnabled)
    }

    // MARK: - Member row

    /// Rola dla VoiceOver — to samo, co plakietki przy imieniu.
    private func memberRoleDescription(_ member: HouseholdMemberSnapshot) -> String {
        let role = member.role.uppercased() == "OWNER" ? "Właściciel" : "Domownik"
        return member.id == sessionStore.currentUserId ? "\(role), to Ty" : role
    }

    /// Awatar, imię i plakietki — nic więcej. Dieta, alergeny i opis roli
    /// wyszły z wiersza (Rafał, 23.09.2026: „to tu nie ma sensu”): czego kto
    /// nie je, pilnuje plan i asystent, a nie lista domowników. Jedna linijka
    /// zamiast dwóch, więc każdy wiersz ma tę samą wysokość — wyznacza ją
    /// awatar, a nie liczba etykiet.
    private func memberRow(_ member: HouseholdMemberSnapshot, showsRule: Bool) -> some View {
        let isOwner = member.role.uppercased() == "OWNER"
        let isMe = member.id == sessionStore.currentUserId

        return HStack(spacing: 12) {
            // Kolor z backendu + ziarno z id — dokładnie to, czym ten sam
            // domownik świeci na Planie. Bez tych parametrów kolor liczył
            // się z IMIENIA i ta sama osoba miała tu inny odcień niż wszędzie
            // indziej.
            ProfileAvatar(
                avatarUrl: member.avatarUrl,
                displayName: member.displayName,
                size: 40,
                colorIndex: member.avatarColor,
                seed: member.id
            )

            HStack(spacing: 6) {
                Text(member.displayName)
                    .font(.sc(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)

                if isMe {
                    memberBadge("Ty", color: SCPalette.terracotta)
                }

                if isOwner {
                    memberBadge("Właściciel", color: SCPalette.butter)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(member.displayName)
            .accessibilityValue(memberRoleDescription(member))

            if removingMemberId == member.id {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 32, height: 32)
            } else if canCreateInvitations, !isMe {
                // `canCreateInvitations` == „jestem właścicielem" — ta sama
                // brama co przy zapraszaniu. Własnego wiersza nie da się
                // usunąć stąd; od tego jest „Opuść gospodarstwo” pod listą.
                memberActionsMenu(for: member)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            if showsRule {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    .padding(.leading, 14 + 40 + 12)
            }
        }
    }

    /// Mała plakietka przy imieniu — „Ty” w terakocie, „Właściciel” w maśle,
    /// zwykłymi literami w tincie (6.10.2026; wersaliki 9,5 pt odstawały od
    /// reszty aplikacji). Stały rozmiar (`fixedSize`): przy długim imieniu
    /// skraca się imię, a nie plakietka.
    private func memberBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.sc(size: 11.5, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(scheme == .dark ? 0.16 : 0.12), in: Capsule())
            .fixedSize()
    }

    /// Trzy kropki przy domowniku — 32pt kółko w stylistyce krzyżyka arkusza,
    /// tylko w neutralnych barwach: akcja destrukcyjna mieszka w menu
    /// i alertach, a nie w samym przycisku.
    private func memberActionsMenu(for member: HouseholdMemberSnapshot) -> some View {
        Menu {
            Button(role: .destructive) {
                memberToRemove = member
            } label: {
                Label("Usuń z gospodarstwa", systemImage: "person.badge.minus")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.sc(size: 13, weight: .heavy))
                .foregroundStyle(Color.scMuted(scheme))
                .frame(width: 32, height: 32)
                .scChromeGlass(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(removingMemberId != nil)
        .accessibilityLabel("Opcje domownika: \(member.displayName)")
    }

    // MARK: - Actions / helpers

    /// Stan zgody z systemu. Gdy zgoda właśnie się POJAWIŁA (prośba albo
    /// Ustawienia iOS), przypomnienia o posiłkach układają się od nowa —
    /// rozkład planowany bez zgody nie miałby kiedy wyjść.
    @MainActor
    private func refreshNotificationPermission() async {
        let previous = notificationPermission
        let current = await NotificationPermission.current()
        notificationPermission = current
        if current == .allowed, let previous, previous != .allowed {
            sessionStore.rescheduleMealReminders()
        }
    }

    /// „Włącz powiadomienia” — systemowa prośba, tylko gdy jeszcze nie pytaliśmy.
    private func requestNotificationPermission() {
        guard !isRequestingNotifications else { return }
        isRequestingNotifications = true
        Task { @MainActor in
            await askForNotificationPermission()
            isRequestingNotifications = false
        }
    }

    @MainActor
    private func askForNotificationPermission() async {
        let previous = notificationPermission
        let result = await NotificationPermission.requestIfNotAsked()
        notificationPermission = result
        if result == .allowed, previous != .allowed {
            sessionStore.rescheduleMealReminders()
        }
    }

    /// Formularz recenzji Scoffie w App Store. Id aplikacji z jednego miejsca
    /// (`SCAppUpdateGate.defaultStoreURL`), z `?action=write-review`.
    private func openWriteReview() {
        var components = URLComponents(url: SCAppUpdateGate.defaultStoreURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "action", value: "write-review")]
        guard let url = components?.url else { return }
        openURL(url)
    }

    /// Po odmowie system nie zapyta drugi raz — zostają Ustawienia iOS,
    /// prosto na stronę powiadomień Scoffie.
    private func openSystemNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        openURL(url)
    }

    @MainActor
    private func removeMember(_ member: HouseholdMemberSnapshot) async {
        removingMemberId = member.id
        defer { removingMemberId = nil }
        await sessionStore.removeHouseholdMember(memberUserId: member.id)
    }

    private func openHousehold() {
        if hasHousehold {
            showHouseholdSheet = true
            // `force: true`, bo to jest jawna intencja użytkownika: otwiera
            // ekran, żeby zobaczyć AKTUALNY skład domu. `force: false`
            // odbijało się od pamięci podręcznej i pokazywało listę sprzed
            // dołączenia nowej osoby — aż do wylogowania.
            Task {
                await preloadHouseholdContextIfNeeded(force: true)
            }
        } else {
            createHouseholdName = ""
            showCreateHouseholdSheet = true
        }
    }

    @MainActor
    private func preloadHouseholdContextIfNeeded(force: Bool = false) async {
        guard hasHousehold else {
            invitationLink = nil
            return
        }

        await sessionStore.refreshHouseholdMembers(force: force)
        await sessionStore.refreshPendingInvitations()

        guard canCreateInvitations else {
            invitationLink = nil
            return
        }

        if force || invitationLink == nil {
            await createInvitationLink()
        }
    }

    @MainActor
    private func handleHouseholdRealtimeUpdate() async {
        guard hasHousehold else {
            invitationLink = nil
            return
        }

        guard canCreateInvitations else {
            invitationLink = nil
            return
        }

        if invitationLink == nil {
            await createInvitationLink()
        }
    }

    /// „osoba / osoby / osób” — z nastkami i „22 osoby”, nie „22 osób”.
    private func membersLabel(for count: Int) -> String {
        PolishPlural.form(count, one: "osoba", few: "osoby", many: "osób")
    }

    private func submitCreateHousehold() {
        if let error = householdNameValidationError {
            householdNameError = error
            return
        }
        let value = trimmedCreateHouseholdName
        Task {
            await sessionStore.createHousehold(name: value)
            if sessionStore.currentHouseholdId != nil {
                persistedHouseholdName = value
                showCreateHouseholdSheet = false
                createHouseholdName = ""
                householdNameError = nil
            }
        }
    }

    private func createInvitationLink() async {
        guard hasHousehold else {
            invitationLink = nil
            return
        }

        isCreatingInvitation = true
        defer { isCreatingInvitation = false }

        do {
            invitationLink = try await sessionStore.createInvitationLink()
        } catch is CancellationError {
            return
        } catch {
            sessionStore.authError = UserFacingErrorMapper.inlineMessage(from: error)
            invitationLink = nil
        }
    }
}

// Bell + heart rows in the design use `oklch(0.70 0.14 22)` — a warm coral
// that's distinct from the brand terracotta but still in the same family.
// Defined here (not in SCPalette) because it's only used by Settings v2.
/// Akcenty wierszy Ustawień spoza `SCPalette` — wspólne z arkuszami, które
/// te wiersze otwierają (kafelek i eyebrow w kolorze wiersza).
enum SettingsAccent {
    /// Ciepły szary kafelek „Prywatność i regulamin” — jak szare kafle
    /// w Ustawieniach iOS. Jeden w obu motywach (kafelek bierze głęboki kolor).
    static let slate = Color(red: 133 / 255, green: 123 / 255, blue: 115 / 255)

    static let coral = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 219 / 255, green: 119 / 255, blue: 96 / 255, alpha: 1)   // oklch(0.70 0.14 22)
            : UIColor(red: 192 / 255, green: 92 / 255, blue: 72 / 255, alpha: 1)    // darkened for cream bg legibility
    })
}

/// Shared profile avatar used by the Settings current-user card and the
/// Household member rows. Renders the remote photo when `avatarUrl` is present
/// (e.g. Google users). Falls back to a tinted circle with up-to-two
/// initials derived from the display name — Apple Sign in doesn't expose a
/// profile photo, so Apple users always hit this branch.
struct ProfileAvatar: View {
    let avatarUrl: String?
    let displayName: String
    let size: CGFloat

    /// Indeks gradientu przydzielony przez backend przy kończeniu onboardingu.
    /// Ma pierwszeństwo, bo tylko serwer widzi, jakie kolory zajęli już
    /// pozostali domownicy.
    var colorIndex: Int? = nil

    /// Zapasowe ziarno dla kont sprzed wprowadzenia `avatarColor` — kolor
    /// liczy się wtedy z hasza e-maila. Ta sama osoba dostaje zawsze ten sam
    /// odcień, ale bez gwarancji, że różny od domownika.
    var seed: String = ""

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if let url = resolvedURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty, .failure:
                        initialsFallback
                    @unknown default:
                        initialsFallback
                    }
                }
            } else {
                initialsFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(.white.opacity(scheme == .dark ? 0.12 : 0.18), lineWidth: 1)
        )
        .accessibilityElement()
        .accessibilityLabel(Text(displayName))
    }

    private var resolvedURL: URL? {
        guard let avatarUrl, !avatarUrl.isEmpty else { return nil }
        return URL(string: avatarUrl)
    }

    private var initialsFallback: some View {
        // Gradient dobierany deterministycznie z ziarna — nie losowany przy
        // każdym renderze, bo avatar zmieniający kolor po scrollu wyglądałby
        // na usterkę. Paleta jest zamknięta i wzięta z `SCPalette`, więc
        // każdy wariant siedzi w tej samej rodzinie kolorów co reszta
        // aplikacji, zamiast wpadać w przypadkowy odcień z całego koła barw.
        Self.gradient(index: colorIndex, seed: seed.isEmpty ? displayName : seed)
        .overlay(
            Text(Self.initials(for: displayName))
                .font(.sc(size: size * 0.40, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(.white)
                .monospacedDigit()
        )
    }

    /// Dwanaście gradientów: cztery jednobarwne z palety aplikacji i osiem
    /// przejść między nimi. Liczba musi zgadzać się z `AVATAR_COLOR_COUNT`
    /// w `users.service.ts` — to serwer wybiera indeks, klient tylko go
    /// odczytuje.
    ///
    /// Wszystkie warianty siedzą w rodzinie kolorów aplikacji zamiast być
    /// losowane z całego koła barw: awatar ma odróżniać domowników, a nie
    /// wyskakiwać z interfejsu.
    static let gradientPairs: [(Color, Color)] = [
        // Każda para przechodzi między DWOMA różnymi barwami palety, nie
        // między odcieniami jednej. Warianty tonalne (terakota → ciemniejsza
        // terakota) na kółku 48 pt wyglądały po prostu na jednolitą plamę
        // z cieniem — dopiero zmiana barwy widać jako gradient.
        (SCPalette.terracotta,               SCPalette.butter.mix(black: 0.06)),
        (SCPalette.sage,                     SCPalette.indigo.mix(black: 0.10)),
        (SCPalette.indigo,                   SCPalette.terracottaDeep),
        (SCPalette.butter,                   SCPalette.terracottaDeep.mix(black: 0.10)),
        (SCPalette.sage,                     SCPalette.butter.mix(black: 0.04)),
        (SCPalette.terracotta,               SCPalette.indigo.mix(black: 0.22)),
        (SCPalette.indigo,                   SCPalette.sage.mix(black: 0.04)),
        (SCPalette.butter,                   SCPalette.sage.mix(black: 0.40)),
        (SCPalette.terracottaDeep,           SCPalette.butter.mix(black: 0.02)),
        (SCPalette.indigo.mix(black: 0.40),  SCPalette.indigo.mix(black: 0.02)),
        (SCPalette.sage.mix(black: 0.44),    SCPalette.butter.mix(black: 0.08)),
        (SCPalette.terracotta.mix(black: 0.34), SCPalette.terracotta.mix(black: 0.02)),
    ]

    /// Przejście po przekątnej, od krawędzi do krawędzi. Bez punktu
    /// pośredniego — zagęszczał gradient w środku i spłaszczał różnicę
    /// między barwami zamiast ją uwypuklić.
    /// Pierwszy przystanek gradientu — dominujący odcień. Używany tam, gdzie
    /// potrzebny jest jeden kolor osoby zamiast całego przejścia: tinty chipów
    /// i obwódki na Planie.
    static func baseColor(index: Int?, seed: String) -> Color {
        let resolved = index.map { abs($0) % gradientPairs.count }
            ?? stableIndex(for: seed, upperBound: gradientPairs.count)
        return gradientPairs[resolved].0
    }

    static func gradient(index: Int?, seed: String) -> LinearGradient {
        let resolved = index.map { abs($0) % gradientPairs.count }
            ?? stableIndex(for: seed, upperBound: gradientPairs.count)
        let pair = gradientPairs[resolved]
        return LinearGradient(
            colors: [pair.0, pair.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Własny FNV-1a zamiast `hashValue`. `Hasher` Swifta jest zasolony na
    /// każde uruchomienie procesu, więc kolor avatara zmieniałby się po
    /// każdym restarcie aplikacji — a to ma być cecha użytkownika, nie sesji.
    private static func stableIndex(for seed: String, upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Int(hash % UInt64(upperBound))
    }

    static func initials(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }

        let tokens = trimmed
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "." || $0 == "_" })
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }

        let letters = tokens.prefix(2).compactMap { token -> String? in
            guard let first = token.first else { return nil }
            return String(first).uppercased()
        }

        if let joined = letters.isEmpty ? nil : letters.joined(), !joined.isEmpty {
            return joined
        }

        if let first = trimmed.first {
            return String(first).uppercased()
        }
        return "?"
    }
}

#Preview {
    SettingsView()
}

/// Wiersz „Dzienny cel” z dużą liczbą po prawej i suwak pod nim
/// (6.10.2026 — dawniej liczba 44 pt NAD suwakiem). Liczba stoi w tym samym
/// widoku co suwak, bo pod palcem pokazuje wartość z `draft`.
///
/// W trakcie przeciągania wartość żyje TYLKO tutaj, a do `@AppStorage`
/// trafia po puszczeniu. Wcześniej każdy krok suwaka (co 50 kcal, kilkanaście
/// razy na sekundę) zapisywał `UserDefaults` — a na ten klucz patrzy cały
/// arkusz diety (makro, podpowiedź celu, liczenie ukrytych przepisów), całe
/// Ustawienia i zakładki pod arkuszem (ranking Przepisów, cel dnia w Planie
/// i Kalendarzu). Każdy krok przebudowywał je wszystkie, a liczba dodatkowo
/// rolowała się animacją, której następny krok nie dawał dojechać — suwak
/// szedł za palcem z opóźnieniem. Zapis na serwer i tak czekał na koniec
/// (`dietPreferencesSyncToken`), więc nic się nie traci.
private struct CalorieGoalEditor: View {
    @Binding var calorieGoal: Int
    let range: ClosedRange<Int>
    let step: Int

    @Environment(\.colorScheme) private var scheme
    /// Wartość pod palcem; `nil`, gdy nikt nie przeciąga.
    @State private var draft: Int?
    @State private var isEditing = false

    private var shown: Int { draft ?? calorieGoal }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                EditorialSettingsTileIcon(icon: "flame.fill", color: SettingsAccent.coral)

                Text("Dzienny cel")
                    .font(.sc(size: 15, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(shown, format: .number.grouping(.never))
                        .font(.sc(size: 28, weight: .heavy))
                        .tracking(-0.8)
                        .foregroundStyle(SCPalette.terracotta)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(shown)))
                        // Roluje też pod palcem. Animacja siedzi na SAMEJ liczbie
                        // i jest krótka, więc kolejny krok przejmuje ją w locie
                        // zamiast czekać na koniec; zapis do @AppStorage i tak idzie
                        // dopiero po puszczeniu (to on dławił suwak, nie rolowanie).
                        .animation(
                            isEditing ? .snappy(duration: 0.14) : .smooth(duration: 0.22),
                            value: shown
                        )

                    Text("kcal")
                        .font(.sc(size: 13, weight: .bold))
                        .foregroundStyle(Color.scMuted(scheme))
                }
                .fixedSize()
                .accessibilityElement(children: .combine)
            }
            .frame(minHeight: 40)

            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { Double(shown) },
                        set: { raw in
                            let value = snapped(raw)
                            if isEditing {
                                if value != draft { draft = value }
                            } else if value != calorieGoal {
                                // VoiceOver (przesunięcie w górę / w dół) nie
                                // przeciąga — zapisuje od razu.
                                calorieGoal = value
                            }
                        }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: Double(step),
                    onEditingChanged: { editing in
                        isEditing = editing
                        guard !editing else { return }
                        if let draft, draft != calorieGoal {
                            calorieGoal = draft
                        }
                        draft = nil
                    }
                )
                .tint(SCPalette.terracotta)
                .accessibilityLabel("Dzienny cel w kcal")

                HStack {
                    Text("\(range.lowerBound)")
                    Spacer()
                    Text("\(range.upperBound)")
                }
                .font(.sc(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.scFaint(scheme))
                .accessibilityHidden(true)
            }
        }
    }

    /// Najbliższy krok co 50 kcal, w granicach skali — UISlider potrafi
    /// oddać wartość tuż za końcem.
    private func snapped(_ raw: Double) -> Int {
        let stepped = (raw / Double(step)).rounded() * Double(step)
        return min(max(Int(stepped), range.lowerBound), range.upperBound)
    }
}
