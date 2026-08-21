import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.requestReview) private var requestReview

    @AppStorage("settings.theme") private var themeRawValue: String = AppTheme.system.rawValue
    @AppStorage("settings.notifications.enabled") private var notificationsEnabled: Bool = true
    @AppStorage("settings.notifications.planReminders") private var planRemindersEnabled: Bool = true
    @AppStorage("settings.notifications.shoppingReminders") private var shoppingRemindersEnabled: Bool = true
    @AppStorage("settings.user.displayName") private var userDisplayName: String = "user1"
    @AppStorage("settings.user.email") private var userEmail: String = "user1@example.com"
    @AppStorage("settings.user.avatarUrl") private var userAvatarUrl: String = ""
    @AppStorage("settings.household.name") private var persistedHouseholdName: String = ""
    @AppStorage("settings.diet.preference") private var dietPreferenceRaw: String = DietPreference.none.rawValue
    @AppStorage("settings.diet.allergens") private var allergensRaw: String = ""
    @AppStorage("settings.diet.calorieGoal") private var calorieGoal: Int = 2000
    @AppStorage("settings.diet.goal") private var goalRaw: String = UserGoal.healthy.rawValue

    @State private var showCreateHouseholdSheet = false
    @State private var showHouseholdSheet = false
    @State private var showNotificationsSheet = false
    @State private var showAppearanceSheet = false
    @State private var showDietSheet = false
    @State private var showHelpSheet = false
    @State private var createHouseholdName = ""
    @State private var householdNameError: String? = nil
    @State private var showLogoutAlert = false
    @State private var showLeaveHouseholdAlert = false
    @State private var invitationLink: URL?
    @State private var isCreatingInvitation = false
    @State private var expandedFAQ: String? = nil

    private static let householdNameMinLength = 2
    private static let householdNameMaxLength = 50

    // Calorie goal range — 1200 kcal is the lower medical safety bound for
    // adults; 3500 covers heavy training. 50 kcal step keeps the slider
    // tactile without snapping to silly precision.
    private static let calorieGoalMin: Int = 1200
    private static let calorieGoalMax: Int = 3500
    private static let calorieGoalStep: Int = 50
    private static let calorieGoalDefault: Int = 2000

    // Static FAQ content rendered by `helpSheet`. Grouped by topic so the
    // user can jump straight to the area they care about; only one row is
    // expanded at a time (`expandedFAQ` accordion state).
    fileprivate static let faqSections: [FAQSection] = [
        FAQSection(id: "plan", title: "Plan i kalendarz", items: [
            FAQItem(
                id: "plan-create",
                question: "Jak ułożyć plan posiłków na tydzień?",
                answer: "Wejdź w zakładkę Kalendarz, wybierz dzień i stuknij pusty slot — Śniadanie, Obiad lub Kolację. Otworzy się biblioteka przepisów, z której możesz wybrać danie. Powtórz dla pozostałych dni i posiłków."
            ),
            FAQItem(
                id: "plan-change",
                question: "Jak zmienić przepis dla danego dnia?",
                answer: "Stuknij kartę przepisu w kalendarzu — otworzą się szczegóły. Aby podmienić go na inny, wróć do dnia, usuń obecny przepis i przypisz nowy z biblioteki."
            ),
            FAQItem(
                id: "plan-past",
                question: "Czy mogę edytować przeszłe dni?",
                answer: "Nie. Plan z minionych dni jest archiwalny — możesz go tylko przeglądać. Dzisiejszy i przyszłe dni są w pełni edytowalne."
            ),
            FAQItem(
                id: "plan-favorites",
                question: "Co robi serduszko przy przepisie?",
                answer: "Oznacza ulubione przepisy — łatwiej je później znaleźć w bibliotece (zakładka Przepisy) i AI częściej będzie je proponować jako sugestie."
            )
        ]),

        FAQSection(id: "shopping", title: "Lista zakupów", items: [
            FAQItem(
                id: "shop-source",
                question: "Skąd biorą się produkty na liście?",
                answer: "Aplikacja zbiera składniki ze wszystkich przepisów przypisanych w kalendarzu na bieżący tydzień, sumuje powtarzające się produkty i grupuje je po działach sklepowych."
            ),
            FAQItem(
                id: "shop-close",
                question: "Co się dzieje, gdy odhaczę wszystko?",
                answer: "Przycisk „Kupione” zmieni się w „Zamknij” — stuknij go, żeby zarchiwizować listę. Trafi do historii w tej samej zakładce; w każdej chwili możesz ją podejrzeć lub usunąć."
            ),
            FAQItem(
                id: "shop-revision",
                question: "Dodałem nowy przepis po zamknięciu listy. Co teraz?",
                answer: "Aplikacja stworzy nową rewizję listy z brakującymi produktami. Zobaczysz ją jako „Lista 2” — działa identycznie jak pierwsza, ale zawiera tylko nowo wymagane składniki."
            ),
            FAQItem(
                id: "shop-manual",
                question: "Czy mogę dodawać produkty ręcznie?",
                answer: "Aktualnie nie — lista jest w pełni generowana z planu. Funkcja ręcznego dodawania jest na liście rzeczy do zrobienia."
            )
        ]),

        FAQSection(id: "household", title: "Gospodarstwo", items: [
            FAQItem(
                id: "house-create",
                question: "Po co tworzyć gospodarstwo?",
                answer: "Gospodarstwo to wspólna przestrzeń dla domowników — wszyscy widzą ten sam plan posiłków, listę zakupów i bibliotekę przepisów. Dzięki temu nie kupujecie tych samych rzeczy dwa razy."
            ),
            FAQItem(
                id: "house-invite",
                question: "Jak zaprosić domownika?",
                answer: "Otwórz Ustawienia → Gospodarstwo i naciśnij „+” obok listy domowników. Aplikacja wygeneruje link zaproszeniowy — wyślij go bliskiemu dowolnym komunikatorem."
            ),
            FAQItem(
                id: "house-shared",
                question: "Czy każdy domownik widzi mój plan?",
                answer: "Tak. Plan, lista zakupów i przepisy są wspólne dla wszystkich osób w gospodarstwie. Każdy może je edytować — zmiany pojawiają się u pozostałych w czasie rzeczywistym."
            ),
            FAQItem(
                id: "house-leave",
                question: "Jak opuścić gospodarstwo?",
                answer: "W oknie gospodarstwa stuknij czerwony przycisk „Opuść gospodarstwo”. Stracisz dostęp do wspólnych danych, ale Twoje konto pozostanie aktywne."
            )
        ]),

        FAQSection(id: "account", title: "Konto i dane", items: [
            FAQItem(
                id: "acc-sync",
                question: "Czy moje dane są synchronizowane?",
                answer: "Tak. Każda zmiana w planie, liście zakupów i przepisach jest zapisywana na serwerze i synchronizowana między urządzeniami w tym samym gospodarstwie."
            ),
            FAQItem(
                id: "acc-photo",
                question: "Skąd bierze się moje zdjęcie profilowe?",
                answer: "Logując się przez Google przejmujemy zdjęcie z Twojego konta Google. Logując się przez Apple — Apple nie udostępnia zdjęć, więc używamy Twojego inicjału na terakotowym tle."
            ),
            FAQItem(
                id: "acc-delete",
                question: "Jak usunąć konto?",
                answer: "Napisz na piechowicz.rafal98@gmail.com z prośbą o usunięcie konta. Potwierdzimy operację i wykasujemy wszystkie dane w ciągu 7 dni."
            )
        ]),

        FAQSection(id: "notifications", title: "Powiadomienia", items: [
            FAQItem(
                id: "notif-missing",
                question: "Dlaczego nie dostaję powiadomień?",
                answer: "Sprawdź dwie rzeczy: (1) główny przełącznik w Ustawienia → Powiadomienia w aplikacji, (2) uprawnienia w Ustawieniach iOS → Weekly Meals → Powiadomienia."
            ),
            FAQItem(
                id: "notif-when",
                question: "Kiedy wysyłane są przypomnienia?",
                answer: "Plan tygodniowy: w niedzielę wieczorem, jeśli nie masz jeszcze ułożonego planu na nadchodzący tydzień. Lista zakupów: w piątek rano, jeśli zostały niekupione produkty."
            )
        ]),

        FAQSection(id: "other", title: "Pozostałe", items: [
            FAQItem(
                id: "other-slow",
                question: "Aplikacja działa wolno",
                answer: "Spróbuj wymusić jej zamknięcie (przeciągnięcie w górę w przeglądzie aplikacji) i otworzyć ponownie. Twoje dane są bezpiecznie zapisane na serwerze, więc nic nie zginie."
            ),
            FAQItem(
                id: "other-idea",
                question: "Mam pomysł na nową funkcję",
                answer: "Świetnie! Napisz na piechowicz.rafal98@gmail.com — czytamy każdą wiadomość i wiele funkcji w aplikacji powstało właśnie z sugestii użytkowników."
            ),
            FAQItem(
                id: "other-bug",
                question: "Znalazłem błąd. Gdzie zgłosić?",
                answer: "Wyślij krótki opis na piechowicz.rafal98@gmail.com — najlepiej z screenem i nazwą urządzenia. Postaramy się odpowiedzieć i naprawić problem jak najszybciej."
            )
        ])
    ]

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

    /// Inline value next to "Wygląd" — uses the localized title from
    /// `AppTheme` so it reads "Auto" / "Jasny" / "Ciemny" in the row.
    private var appearanceRowValue: String {
        let theme = AppTheme(rawValue: themeRawValue) ?? .system
        switch theme {
        case .system: return "Auto"
        case .light: return "Jasny"
        case .dark: return "Ciemny"
        }
    }

    private var currentDiet: DietPreference {
        DietPreference(rawValue: dietPreferenceRaw) ?? .none
    }

    private var currentGoal: UserGoal {
        UserGoal(rawValue: goalRaw) ?? .healthy
    }

    private var selectedAllergens: Set<Allergen> {
        Set(allergensRaw
            .split(separator: ",")
            .compactMap { Allergen(rawValue: String($0)) })
    }

    /// Inline value next to "Dieta i alergeny" — kcal is always-on so it
    /// always shows up; diet name is prepended when set, allergen count
    /// is appended when at least one is picked. Capped at two pieces so
    /// the value column doesn't overflow on narrow rows.
    private var dietRowValue: String {
        var parts: [String] = []

        if currentDiet != .none {
            parts.append(currentDiet.title)
        } else if currentGoal != .healthy {
            // Bez diety wiersz pokazywał samo „2000 kcal” — cel jest wtedy
            // ciekawszą informacją niż nic.
            parts.append(currentGoal.shortTitle)
        }
        parts.append("\(calorieGoal) kcal")
        if !selectedAllergens.isEmpty {
            let count = selectedAllergens.count
            parts.append("\(count) \(allergenWord(for: count))")
        }

        return parts.prefix(2).joined(separator: " · ")
    }

    private func allergenWord(for count: Int) -> String {
        switch count {
        case 1:         return "alergen"
        case 2...4:     return "alergeny"
        default:        return "alergenów"
        }
    }

    private func toggleAllergen(_ allergen: Allergen) {
        var current = selectedAllergens
        if current.contains(allergen) {
            current.remove(allergen)
        } else {
            current.insert(allergen)
        }
        allergensRaw = current
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
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
    private var pageTopPadding: CGFloat { WMPageMetrics.top }
    private var pageHorizontalPadding: CGFloat { WMPageMetrics.horizontal }
    private var pageBottomPadding: CGFloat { WMPageMetrics.bottom }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                WMPageBackground(scheme: scheme)
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
                            infoSection

                            EditorialLogoutButton(isLoading: false) {
                                showLogoutAlert = true
                            }
                            .padding(.top, 20)
                            .padding(.bottom, 16)
                        }
                        .padding(.horizontal, pageHorizontalPadding)
                    }
                    .padding(.bottom, pageBottomPadding)
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(.container, edges: .top)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            .background(NavBarHitTestPassthrough())
            .sheet(isPresented: $showCreateHouseholdSheet) {
                createHouseholdSheet
                    .dashboardLiquidSheet()
            }
            .sheet(isPresented: $showHouseholdSheet) {
                householdManagementSheet
                    .dashboardLiquidSheet()
            }
            .sheet(isPresented: $showNotificationsSheet) {
                notificationsSheet
                    .dashboardLiquidSheet()
            }
            .sheet(isPresented: $showAppearanceSheet) {
                appearanceSheet
                    .dashboardLiquidSheet()
            }
            .sheet(isPresented: $showDietSheet) {
                dietSheet
                    .dashboardLiquidSheet()
            }
            .sheet(isPresented: $showHelpSheet) {
                helpSheet
                    .dashboardLiquidSheet()
            }
            .alert("Czy na pewno chcesz się wylogować?", isPresented: $showLogoutAlert) {
                Button("Anuluj", role: .cancel) {}
                Button("Wyloguj", role: .destructive) {
                    sessionStore.logout()
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
            avatarUrl: userAvatarUrl
        )
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSettingsSectionHeader(title: "Konto")

            EditorialSettingsCardGroup {
                EditorialSettingsRow(
                    icon: "house.fill",
                    iconColor: WMPalette.sage,
                    title: "Gospodarstwo",
                    value: householdRowValue,
                    action: openHousehold
                )

                EditorialSettingsRow(
                    icon: "leaf.fill",
                    iconColor: WMPalette.sage,
                    title: "Dieta i alergeny",
                    value: dietRowValue,
                    isLast: true,
                    action: { showDietSheet = true }
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
                    action: { showNotificationsSheet = true }
                )

                EditorialSettingsRow(
                    icon: "slider.horizontal.3",
                    iconColor: WMPalette.indigo,
                    title: "Wygląd",
                    value: appearanceRowValue,
                    isLast: true,
                    action: { showAppearanceSheet = true }
                )
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSettingsSectionHeader(title: "Informacje")

            EditorialSettingsCardGroup {
                EditorialSettingsRow(
                    icon: "book.fill",
                    iconColor: WMPalette.terracotta,
                    title: "Pomoc i FAQ",
                    action: { showHelpSheet = true }
                )

                EditorialSettingsRow(
                    icon: "heart.fill",
                    iconColor: SettingsAccent.coral,
                    title: "Oceń aplikację",
                    action: { requestReview() }
                )

                versionRow
            }
        }
    }

    /// "Wersja" row — uses the hollow "i" tile + the version pill on the
    /// right with no chevron / toggle. Manually composed because it doesn't
    /// fit the standard `EditorialSettingsRow` icon-tile shape.
    private var versionRow: some View {
        HStack(spacing: 14) {
            EditorialSettingsInfoTile()

            Text("Wersja")
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(Color.wmLabel(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(appVersionLabel)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.wmMuted(scheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Sheets
    //
    // Every sheet shares the same chassis as the main settings list — warm
    // `WMPageBackground` canvas, editorial header (eyebrow + title + xmark),
    // and `Color.wmTileBg` cards with `Color.wmTileStroke` hairlines. The
    // existing data wiring (createHousehold / leaveCurrentHousehold /
    // createInvitationLink, AppStorage flags) is preserved unchanged.

    private var createHouseholdSheet: some View {
        editorialSheet {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EditorialSheetHeader(
                        eyebrow: "Nowe gospodarstwo",
                        title: "Utwórz wspólną przestrzeń"
                    ) {
                        showCreateHouseholdSheet = false
                    }

                    Text("Nadaj nazwę miejscu, w którym domownicy planują posiłki i robią zakupy razem.")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    editorialNameInputCard

                    editorialPrimaryButton(
                        title: "Utwórz gospodarstwo",
                        icon: "house.badge.plus",
                        isEnabled: canSubmitCreateHousehold,
                        action: submitCreateHousehold
                    )

                    if let error = sessionStore.authError, !error.isEmpty {
                        Text(error)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.red)
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
        editorialSheet {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EditorialSheetHeader(
                        eyebrow: hasHousehold ? "Twoje gospodarstwo" : "Gospodarstwo",
                        title: hasHousehold ? persistedHouseholdName : "Brak gospodarstwa"
                    ) {
                        showHouseholdSheet = false
                    }

                    if hasHousehold {
                        householdOverviewCard
                        householdMembersCard
                    } else {
                        householdEmptyCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
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
        }
    }

    // ─── Powiadomienia ─────────────
    //
    // Big bell hero with the master toggle on the right; below it a card of
    // per-channel toggles (plan + lista zakupów) that visibly dim when the
    // master switch is off. Each channel row sits on a soft icon tile so the
    // category reads at a glance.
    private var notificationsSheet: some View {
        editorialSheet {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EditorialSheetHeader(
                        eyebrow: "Personalizacja",
                        title: "Powiadomienia"
                    ) {
                        showNotificationsSheet = false
                    }

                    notificationsHeroCard

                    notificationChannelsCard
                        .opacity(notificationsEnabled ? 1 : 0.55)
                        .animation(.smooth(duration: 0.2), value: notificationsEnabled)

                    Text(notificationsEnabled
                         ? "Możesz osobno wyciszyć każdy typ powiadomień. Zmiana zaczyna obowiązywać od następnego planowanego przypomnienia."
                         : "Wszystkie powiadomienia są wyciszone. Włącz główny przełącznik, aby zarządzać typami przypomnień."
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var notificationsHeroCard: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                SettingsAccent.coral.opacity(scheme == .dark ? 0.28 : 0.20),
                                SettingsAccent.coral.opacity(scheme == .dark ? 0.10 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: notificationsEnabled ? "bell.fill" : "bell.slash.fill")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(SettingsAccent.coral)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(notificationsEnabled ? "Włączone" : "Wyciszone")
                    .font(.system(size: 17, weight: .heavy))
                    .tracking(-0.3)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .contentTransition(.opacity)
                    .id(notificationsEnabled)

                Text("Główny przełącznik dla wszystkich przypomnień aplikacji.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: $notificationsEnabled)
                .labelsHidden()
                .tint(WMPalette.sage)
                .scaleEffect(0.95)
                .fixedSize()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
    }

    private var notificationChannelsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Kanały")

            VStack(spacing: 0) {
                channelToggleRow(
                    icon: "calendar.badge.clock",
                    accent: WMPalette.indigo,
                    title: "Plan tygodniowy",
                    subtitle: "Przypomnienia o ułożeniu posiłków na nadchodzące dni.",
                    isOn: $planRemindersEnabled,
                    isLast: false
                )

                channelToggleRow(
                    icon: "cart.fill",
                    accent: WMPalette.sage,
                    title: "Lista zakupów",
                    subtitle: "Powiadomienia o niekupionych produktach przed weekendem.",
                    isOn: $shoppingRemindersEnabled,
                    isLast: true
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.wmTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .disabled(!notificationsEnabled)
    }

    private func channelToggleRow(
        icon: String,
        accent: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            EditorialSettingsTileIcon(icon: icon, color: accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.wmLabel(scheme))

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(WMPalette.sage)
                .scaleEffect(0.85)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.wmRule(scheme))
                    .frame(height: 1)
                    .padding(.leading, 16 + 32 + 14)
            }
        }
    }

    // ─── Wygląd ─────────────────
    //
    // Visual theme picker — three full-bleed preview cards stacked vertically.
    // Each card paints an actual mini canvas for the theme (cream / dark /
    // split for Auto) and a chip showing the theme's terracotta accent so the
    // user picks by what they'll see, not by a label.
    private var appearanceSheet: some View {
        editorialSheet {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EditorialSheetHeader(
                        eyebrow: "Personalizacja",
                        title: "Wygląd"
                    ) {
                        showAppearanceSheet = false
                    }

                    Text("Wybierz motyw, którego aplikacja będzie używać domyślnie. Auto przełącza się razem z systemem.")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 12) {
                        ForEach(AppTheme.allCases) { theme in
                            themePreviewCard(theme)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func themePreviewCard(_ theme: AppTheme) -> some View {
        let selected = theme.rawValue == themeRawValue

        return Button {
            withAnimation(.smooth(duration: 0.25)) {
                themeRawValue = theme.rawValue
            }
        } label: {
            HStack(alignment: .center, spacing: 16) {
                themeCanvasPreview(theme)
                    .frame(width: 76, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(themeEyebrow(for: theme).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(WMPalette.terracotta)

                    Text(theme.title)
                        .font(.system(size: 20, weight: .heavy))
                        .tracking(-0.4)
                        .foregroundStyle(Color.wmLabel(scheme))

                    Text(themeDescription(for: theme))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                themeSelectionIndicator(selected: selected)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        selected
                            ? WMPalette.terracotta.opacity(scheme == .dark ? 0.10 : 0.07)
                            : Color.wmTileBg(scheme)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        selected
                            ? WMPalette.terracotta.opacity(scheme == .dark ? 0.45 : 0.36)
                            : Color.wmTileStroke(scheme),
                        lineWidth: selected ? 1.4 : 1
                    )
            )
            .shadow(
                color: WMPalette.terracotta.opacity(selected ? 0.18 : 0),
                radius: 14, x: 0, y: 8
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.title)\(selected ? ", wybrane" : "")")
    }

    /// Mini canvas — paints the actual base + glow stack used by
    /// `WMPageBackground` so the user sees what the live screen will look
    /// like. Auto splits left/right for light/dark.
    @ViewBuilder
    private func themeCanvasPreview(_ theme: AppTheme) -> some View {
        switch theme {
        case .light:
            themePreviewBlock(scheme: .light)
        case .dark:
            themePreviewBlock(scheme: .dark)
        case .system:
            HStack(spacing: 0) {
                themePreviewBlock(scheme: .light)
                themePreviewBlock(scheme: .dark)
            }
        }
    }

    private func themePreviewBlock(scheme: ColorScheme) -> some View {
        let base = scheme == .dark
            ? Color(red: 12 / 255, green: 8 / 255, blue: 6 / 255)
            : Color(red: 251 / 255, green: 245 / 255, blue: 234 / 255)
        let glow = WMPalette.terracotta.opacity(scheme == .dark ? 0.18 : 0.14)
        let label = scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255)

        return ZStack(alignment: .topLeading) {
            base
            RadialGradient(
                colors: [glow, .clear],
                center: UnitPoint(x: 0.5, y: 0),
                startRadius: 0,
                endRadius: 80
            )

            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(label.opacity(0.85))
                    .frame(width: 28, height: 5)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(label.opacity(0.45))
                    .frame(width: 18, height: 4)

                Spacer(minLength: 0)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(label.opacity(scheme == .dark ? 0.06 : 0.05))
                    .frame(height: 10)
                    .overlay(
                        Capsule()
                            .fill(WMPalette.terracotta)
                            .frame(width: 14, height: 4),
                        alignment: .leading
                    )
                    .padding(.top, 3)
            }
            .padding(8)
        }
    }

    private func themeSelectionIndicator(selected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(selected ? WMPalette.terracotta : Color.wmChipBg(scheme))
            Circle()
                .stroke(
                    selected
                        ? WMPalette.terracotta
                        : Color.wmFaint(scheme),
                    lineWidth: selected ? 0 : 1.4
                )

            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .animation(.smooth(duration: 0.2), value: selected)
    }

    private func themeEyebrow(for theme: AppTheme) -> String {
        switch theme {
        case .system: return "Synchronizacja z systemem"
        case .light:  return "Cozy daylight"
        case .dark:   return "Cozy night"
        }
    }

    private func themeDescription(for theme: AppTheme) -> String {
        // Aim for ~2 lines at 12pt in the ~190pt description column —
        // anything longer was getting tail-truncated on the preview card.
        switch theme {
        case .system: return "Aplikacja zmienia się razem z motywem iOS."
        case .light:  return "Kremowe tło z subtelnym terakotowym poblaskiem."
        case .dark:   return "Głęboki, brązowo-czarny canvas — łagodny dla oczu wieczorem."
        }
    }

    // ─── Dieta i alergeny ──────────
    //
    // Two-section sheet: pick one diet (single-select rows with icon tile +
    // radio dot), then toggle any allergens (multi-select chip cloud).
    // Both selections persist to `@AppStorage` instantly — the xmark
    // button is the only way out, no save / cancel needed.
    private var dietSheet: some View {
        editorialSheet {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EditorialSheetHeader(
                        eyebrow: "Personalizacja",
                        title: "Dieta i alergeny"
                    ) {
                        showDietSheet = false
                    }

                    Text("Aplikacja użyje tych ustawień na liście przepisów: dieta i alergeny odsiewają dania, a cel decyduje, które trafią na górę.")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    calorieGoalSection
                    goalPickerSection
                    dietPickerSection
                    allergensSection

                    if hasCustomisedPreferences {
                        resetPreferencesButton
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        // Debounced sync: every time any of the three preference fields
        // changes the previous task is cancelled and a new one is scheduled
        // 600ms later. Slider drags coalesce into a single backend write
        // instead of one per micro-step.
        .task(id: dietPreferencesSyncToken) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await sessionStore.saveUserPreferences(
                diet: currentDiet.rawValue,
                calorieGoal: calorieGoal,
                allergens: selectedAllergens.map(\.rawValue),
                goal: currentGoal.rawValue
            )
        }
    }

    /// Czy jest co czyścić — steruje widocznością „Wyczyść preferencje”.
    private var hasCustomisedPreferences: Bool {
        currentDiet != .none
            || currentGoal != .healthy
            || calorieGoal != Self.calorieGoalDefault
            || !selectedAllergens.isEmpty
    }

    /// Stable token that changes whenever the user touches any preference
    /// field — drives `task(id:)` so SwiftUI cancels the in-flight save and
    /// schedules a fresh one. Using a single concatenated string keeps the
    /// modifier signature simple.
    private var dietPreferencesSyncToken: String {
        "\(dietPreferenceRaw)|\(calorieGoal)|\(allergensRaw)|\(goalRaw)"
    }

    // ─── Twój cel ──────────
    //
    // Ten sam wybór, co w kroku 2 kreatora powitalnego — powtórzony tutaj,
    // bo po onboardingu nie było jak go zmienić. Cel nie odsiewa przepisów;
    // przestawia kolejność listy (patrz `RecipePersonalization.goalScore`).
    // Siedzi pod suwakiem kalorii, a podpowiedź „Ustaw” na dole tej karty
    // przestawia suwak nad nią.
    private var goalPickerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Twój cel")

            VStack(spacing: 0) {
                // Ostatni wiersz nigdy nie rysuje własnej kreski. Gdy pod nim
                // siedzi podpowiedź kaloryczna, kreskę stawia ona — i to na
                // pełnej szerokości. Wcześniej rysowały obie i pod ostatnim
                // celem wychodziła podwójna linia: wcięta i pełna.
                ForEach(Array(UserGoal.allCases.enumerated()), id: \.element.id) { idx, goal in
                    goalRow(goal, isLast: idx == UserGoal.allCases.count - 1)
                }

                if showsCalorieSuggestion {
                    calorieSuggestionRow
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.wmTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
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
            HStack(alignment: .center, spacing: 14) {
                EditorialSettingsTileIcon(icon: goal.icon, color: goal.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.wmLabel(scheme))

                    Text(goal.subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                radioIndicator(selected: isSelected)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.wmRule(scheme))
                    .frame(height: 1)
                    .padding(.leading, 16 + 32 + 14)
            }
        }
        .accessibilityLabel(goal.title)
        .accessibilityValue(isSelected ? "Wybrane" : "")
    }

    /// Cel niesie ze sobą sugerowaną kaloryczność, ale ustawiony wcześniej
    /// suwak jest decyzją użytkownika — więc podpowiadamy przyciskiem zamiast
    /// nadpisywać. Kreator powitalny robi to samo, tyle że tam suwak jeszcze
    /// nie był ruszany, więc może iść za celem sam.
    private var showsCalorieSuggestion: Bool {
        currentGoal != .plan && calorieGoal != currentGoal.suggestedCalories
    }

    private var calorieSuggestionRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WMPalette.butter)
                .frame(width: 22)

            Text("Dla tego celu zwykle wychodzi \(currentGoal.suggestedCalories) kcal.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.wmMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.smooth(duration: 0.22)) {
                    calorieGoal = snappedCalorieGoal(from: Double(currentGoal.suggestedCalories))
                }
            } label: {
                Text("Ustaw")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WMPalette.terracotta)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(WMPalette.terracotta.opacity(scheme == .dark ? 0.20 : 0.12)))
                    .overlay(Capsule().stroke(WMPalette.terracotta.opacity(0.30), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ustaw \(currentGoal.suggestedCalories) kcal")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.wmChipBg(scheme).opacity(scheme == .dark ? 0.5 : 0.7))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.wmRule(scheme))
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
                    .fill(Color.wmTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
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
            HStack(alignment: .center, spacing: 14) {
                EditorialSettingsTileIcon(icon: diet.icon, color: diet.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(diet.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.wmLabel(scheme))

                    Text(diet.subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                radioIndicator(selected: isSelected)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.wmRule(scheme))
                    .frame(height: 1)
                    .padding(.leading, 16 + 32 + 14)
            }
        }
        .accessibilityLabel(diet.title)
        .accessibilityValue(isSelected ? "Wybrane" : "")
    }

    /// Hollow ring → terracotta filled dot when selected. Same visual
    /// language as iOS group-pickers, just in our cozy palette.
    private func radioIndicator(selected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(
                    selected
                        ? WMPalette.terracotta
                        : Color.wmFaint(scheme),
                    lineWidth: 1.6
                )
                .frame(width: 22, height: 22)

            if selected {
                Circle()
                    .fill(WMPalette.terracotta)
                    .frame(width: 12, height: 12)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.18), value: selected)
    }

    private var calorieGoalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Cel kaloryczny")

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 14) {
                    EditorialSettingsTileIcon(icon: "flame.fill", color: WMPalette.terracotta)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dzienny cel")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.wmLabel(scheme))
                        Text("Aplikacja podpowie, jak rozłożyć posiłki w ciągu dnia.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.wmMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                calorieGoalEditor
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.wmTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
            )
        }
    }

    /// Big animated kcal readout above a 50-kcal-stepped slider — that's
    /// the whole picker. No quick-pick chips, no on/off toggle: the goal
    /// is always set, the slider is the only control.
    private var calorieGoalEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(calorieGoal, format: .number.grouping(.never))
                    .font(.system(size: 44, weight: .heavy))
                    .tracking(-1.4)
                    .foregroundStyle(WMPalette.terracotta)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(calorieGoal)))

                Text("kcal / dzień")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(Color.wmMuted(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.18), value: calorieGoal)

            VStack(spacing: 6) {
                Slider(
                    value: Binding(
                        get: { Double(calorieGoal) },
                        set: { calorieGoal = snappedCalorieGoal(from: $0) }
                    ),
                    in: Double(Self.calorieGoalMin)...Double(Self.calorieGoalMax),
                    step: Double(Self.calorieGoalStep)
                )
                .tint(WMPalette.terracotta)

                HStack {
                    Text("\(Self.calorieGoalMin)")
                    Spacer()
                    Text("\(Self.calorieGoalMax)")
                }
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.wmFaint(scheme))
            }
        }
    }

    /// Round an arbitrary slider value to the nearest 50-kcal step and
    /// clamp it to the [min, max] range. Defensive against the rare
    /// off-end value the UISlider can emit at the extremes.
    private func snappedCalorieGoal(from raw: Double) -> Int {
        let stepped = (raw / Double(Self.calorieGoalStep)).rounded() * Double(Self.calorieGoalStep)
        return min(max(Int(stepped), Self.calorieGoalMin), Self.calorieGoalMax)
    }

    private var allergensSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Alergeny i nietolerancje")

            VStack(alignment: .leading, spacing: 14) {
                Text("Stuknij, aby zaznaczyć produkty, których chcesz unikać. Możesz wybrać dowolną liczbę.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)

                allergenChipCloud
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.wmTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
            )
        }
    }

    /// Wrapping chip layout — uses the iOS 16+ `Layout`-backed flow from
    /// SwiftUI's native `HStack` when nested in a `ViewThatFits`. Falls
    /// back to a plain wrapping HStack via `LazyVGrid`-free chunking.
    private var allergenChipCloud: some View {
        AllergenChipFlow(spacing: 8) {
            ForEach(Allergen.allCases) { allergen in
                allergenChip(allergen)
            }
        }
    }

    private func allergenChip(_ allergen: Allergen) -> some View {
        let isSelected = selectedAllergens.contains(allergen)

        return Button {
            withAnimation(.smooth(duration: 0.18)) {
                toggleAllergen(allergen)
            }
        } label: {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .heavy))
                        .transition(.scale.combined(with: .opacity))
                }

                Text(allergen.title)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.1)
            }
            .foregroundStyle(
                isSelected
                    ? .white
                    : Color.wmLabel(scheme)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    isSelected
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [WMPalette.terracotta, WMPalette.terracotta.mix(black: 0.18)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        : AnyShapeStyle(Color.wmChipBg(scheme))
                )
            )
            .overlay(
                Capsule().stroke(
                    isSelected
                        ? WMPalette.terracotta.opacity(0.35)
                        : Color.wmTileStroke(scheme),
                    lineWidth: 1
                )
            )
            .shadow(
                color: WMPalette.terracotta.opacity(isSelected ? 0.20 : 0),
                radius: 5, x: 0, y: 2
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(allergen.title)
        .accessibilityValue(isSelected ? "Zaznaczone" : "Niezaznaczone")
    }

    /// Dim red pill that wipes the diet preference, calorie goal and all
    /// allergens in one tap — only shown when there's actually something
    /// to reset.
    private var resetPreferencesButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.22)) {
                dietPreferenceRaw = DietPreference.none.rawValue
                allergensRaw = ""
                calorieGoal = Self.calorieGoalDefault
                goalRaw = UserGoal.healthy.rawValue
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .heavy))
                Text("Wyczyść preferencje")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.1)
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.red.opacity(scheme == .dark ? 0.14 : 0.10)))
        }
        .buttonStyle(.plain)
    }

    private var helpSheet: some View {
        editorialSheet {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EditorialSheetHeader(
                        eyebrow: "Wsparcie",
                        title: "Pomoc i FAQ"
                    ) {
                        showHelpSheet = false
                        expandedFAQ = nil
                    }

                    Text("Najczęściej zadawane pytania o planowanie posiłków, listę zakupów i wspólne gospodarstwo. Nie znalazłeś odpowiedzi? Napisz do nas.")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(Self.faqSections) { section in
                        faqSectionCard(section)
                    }

                    contactCard
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func faqSectionCard(_ section: FAQSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: section.title)

            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { idx, item in
                    faqRow(item, isLast: idx == section.items.count - 1)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.wmTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func faqRow(_ item: FAQItem, isLast: Bool) -> some View {
        let isExpanded = expandedFAQ == item.id

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.smooth(duration: 0.28)) {
                    expandedFAQ = isExpanded ? nil : item.id
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(item.question)
                        .font(.system(size: 14.5, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(
                            isExpanded
                                ? WMPalette.terracotta
                                : Color.wmFaint(scheme)
                        )
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle().fill(
                                isExpanded
                                    ? WMPalette.terracotta.opacity(scheme == .dark ? 0.18 : 0.12)
                                    : Color.wmChipBg(scheme)
                            )
                        )
                        .padding(.top, 1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.question)
            .accessibilityHint(isExpanded ? "Stuknij, aby zwinąć odpowiedź" : "Stuknij, aby pokazać odpowiedź")

            if isExpanded {
                Text(item.answer)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.wmRule(scheme))
                    .frame(height: 1)
                    .padding(.leading, 16)
            }
        }
    }

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                EditorialSettingsTileIcon(icon: "envelope.fill", color: WMPalette.terracotta, size: 44, radius: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Nadal masz pytanie?")
                        .font(.system(size: 16, weight: .heavy))
                        .tracking(-0.3)
                        .foregroundStyle(Color.wmLabel(scheme))
                    Text("Czytamy każdą wiadomość. Odpowiadamy zwykle w ciągu kilku dni.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let url = URL(string: "mailto:piechowicz.rafal98@gmail.com?subject=Weekly%20Meals%20—%20Pytanie") {
                Link(destination: url) {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 12.5, weight: .heavy))
                        Text("Napisz do nas")
                            .font(.system(size: 14, weight: .bold))
                            .tracking(-0.1)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [WMPalette.terracotta, WMPalette.terracotta.mix(black: 0.18)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    )
                    .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
                    .shadow(color: WMPalette.terracotta.opacity(0.28), radius: 8, x: 0, y: 4)
                }
                .accessibilityLabel("Napisz do nas — piechowicz.rafal98@gmail.com")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
    }

    // MARK: - Sheet building blocks

    /// Wraps each sheet's content in the shared editorial chassis — warm
    /// `WMPageBackground` behind a transparent `presentationBackground`,
    /// so the sheet card itself adopts the cozy canvas instead of the
    /// system grey.
    @ViewBuilder
    private func editorialSheet<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            WMPageBackground(scheme: scheme)
                .ignoresSafeArea()

            content()
        }
    }

    private var editorialNameInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSheetSectionLabel(title: "Nazwa")

            TextField("Np. Dom", text: $createHouseholdName)
                .textInputAutocapitalization(.words)
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(Color.wmLabel(scheme))
                .tint(WMPalette.terracotta)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.wmChipBg(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            householdNameError != nil
                                ? Color.red.opacity(0.6)
                                : Color.wmTileStroke(scheme),
                            lineWidth: householdNameError != nil ? 1.5 : 1
                        )
                )
                .onChange(of: createHouseholdName) { _, _ in
                    if householdNameError != nil { householdNameError = nil }
                }

            if let error = householdNameError {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }

            HStack {
                Spacer()
                Text("\(trimmedCreateHouseholdName.count)/\(Self.householdNameMaxLength)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(
                        trimmedCreateHouseholdName.count > Self.householdNameMaxLength
                            ? .red
                            : Color.wmFaint(scheme)
                    )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
    }

    private var householdOverviewCard: some View {
        HStack(alignment: .center, spacing: 14) {
            EditorialSettingsTileIcon(icon: "house.fill", color: WMPalette.sage, size: 44, radius: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(persistedHouseholdName)
                    .font(.system(size: 17, weight: .heavy))
                    .tracking(-0.3)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .lineLimit(2)

                Text("\(householdMembers.count) \(membersLabel(for: householdMembers.count)) w gospodarstwie")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.wmMuted(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            leaveHouseholdIconButton
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
    }

    /// 36pt circular destructive icon button — sits on the right of the
    /// household name. Red wash background + red outline + door-arrow
    /// glyph; matches the visual weight of the xmark close button used
    /// in every sheet header so the row reads as compact + tidy.
    private var leaveHouseholdIconButton: some View {
        Button {
            showLeaveHouseholdAlert = true
        } label: {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.red)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.red.opacity(scheme == .dark ? 0.16 : 0.12)))
                .overlay(Circle().stroke(Color.red.opacity(scheme == .dark ? 0.30 : 0.24), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(sessionStore.isSigningIn)
        .opacity(sessionStore.isSigningIn ? 0.55 : 1)
        .accessibilityLabel("Opuść gospodarstwo")
    }

    private var householdMembersCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("Domownicy")
                    .font(.system(size: 18, weight: .heavy))
                    .tracking(-0.3)
                    .foregroundStyle(Color.wmLabel(scheme))

                Spacer(minLength: 0)

                if canCreateInvitations {
                    if let invitationLink {
                        ShareLink(item: invitationLink) {
                            inviteIcon
                        }
                        .accessibilityLabel("Udostępnij zaproszenie")
                    } else if isCreatingInvitation {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 32, height: 32)
                    } else {
                        Button {
                            Task { await createInvitationLink() }
                        } label: {
                            inviteIcon
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Przygotuj zaproszenie")
                    }
                }
            }

            if isLoadingMembers {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Ładowanie...")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.wmMuted(scheme))
                }
                .padding(.vertical, 4)
            } else if householdMembers.isEmpty {
                Text("Brak członków do wyświetlenia.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.wmMuted(scheme))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(householdMembers.enumerated()), id: \.element.id) { idx, member in
                        memberRow(member, isLast: idx == householdMembers.count - 1)
                    }
                }
            }

            if let error = sessionStore.authError, !error.isEmpty {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
    }

    /// 32pt circular "+" used by the invite affordance — same chip
    /// background + hairline stroke as the sheet's xmark button.
    private var inviteIcon: some View {
        Image(systemName: "plus")
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(WMPalette.terracotta)
            .frame(width: 32, height: 32)
            .background(Circle().fill(WMPalette.terracotta.opacity(scheme == .dark ? 0.18 : 0.12)))
            .overlay(Circle().stroke(WMPalette.terracotta.opacity(scheme == .dark ? 0.34 : 0.28), lineWidth: 1))
    }

    private var householdEmptyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                EditorialSettingsTileIcon(icon: "house.badge.plus", color: WMPalette.sage, size: 44, radius: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Brak gospodarstwa")
                        .font(.system(size: 17, weight: .heavy))
                        .tracking(-0.3)
                        .foregroundStyle(Color.wmLabel(scheme))
                    Text("Utwórz wspólne miejsce do planowania posiłków i listy zakupów.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            editorialPrimaryButton(
                title: "Utwórz gospodarstwo",
                icon: "house.badge.plus",
                isEnabled: true
            ) {
                createHouseholdName = ""
                showCreateHouseholdSheet = true
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
    }

    /// Primary action — terracotta gradient capsule with white label.
    /// Mirrors the editorial sage button on the Produkty hero, but tinted
    /// with the brand accent so it reads as the main affirmative CTA.
    private func editorialPrimaryButton(
        title: String,
        icon: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .heavy))
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: isEnabled
                                ? [WMPalette.terracotta, WMPalette.terracotta.mix(black: 0.18)]
                                : [Color.wmFaint(scheme), Color.wmFaint(scheme)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(Capsule().stroke(.white.opacity(isEnabled ? 0.22 : 0), lineWidth: 1))
            .shadow(color: WMPalette.terracotta.opacity(isEnabled ? 0.28 : 0), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.7)
    }

    // MARK: - Member row

    private func memberRow(_ member: HouseholdMemberSnapshot, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            ProfileAvatar(
                avatarUrl: member.avatarUrl,
                displayName: member.displayName,
                size: 38
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Color.wmLabel(scheme))
                        .lineLimit(1)

                    if member.id == sessionStore.currentUserId {
                        Text("TY")
                            .font(.system(size: 9.5, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(WMPalette.terracotta)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(WMPalette.terracotta.opacity(scheme == .dark ? 0.16 : 0.12), in: Capsule())
                    }
                }
                Text(member.email ?? "Brak e-maila")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.wmRule(scheme))
                    .frame(height: 1)
                    .padding(.leading, 50)
            }
        }
    }

    // MARK: - Actions / helpers

    private func openHousehold() {
        if hasHousehold {
            showHouseholdSheet = true
            Task { await preloadHouseholdContextIfNeeded(force: false) }
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

    private func membersLabel(for count: Int) -> String {
        switch count {
        case 1:
            return "osoba"
        case 2...4:
            return "osoby"
        default:
            return "osób"
        }
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
            sessionStore.authError = UserFacingErrorMapper.message(from: error)
            invitationLink = nil
        }
    }
}

// Static FAQ data model — lives at file scope so the `static let` lookup
// table on `SettingsView` can reference it without ordering headaches.
fileprivate struct FAQSection: Identifiable {
    let id: String
    let title: String
    let items: [FAQItem]
}

fileprivate struct FAQItem: Identifiable, Equatable {
    let id: String
    let question: String
    let answer: String
}

// Bell + heart rows in the design use `oklch(0.70 0.14 22)` — a warm coral
// that's distinct from the brand terracotta but still in the same family.
// Defined here (not in WMPalette) because it's only used by Settings v2.
private enum SettingsAccent {
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
        // Cozy Kitchen avatar — terracotta gradient with the user's
        // initial in white. Mirrors the design's `Avatar` component.
        LinearGradient(
            colors: [WMPalette.terracotta, WMPalette.terracotta.mix(black: 0.20)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Text(Self.initials(for: displayName))
                .font(.system(size: size * 0.40, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(.white)
                .monospacedDigit()
        )
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

// MARK: - Nav bar hit-test pass-through (shared with Calendar / Produkty)
//
// SwiftUI's `NavigationStack` keeps the toolbar layer "live" so the auto-blur
// material can fade in on scroll, but that layer also captures touches across
// its full ~44pt height — even when the toolbar is visually empty. That blocks
// taps on the top-most rows once the layout extends under it via
// `.ignoresSafeArea(.container, edges: .top)`. There are no real toolbar
// items here, so disabling user interaction on the underlying
// `UINavigationBar` lets touches fall through while the auto-blur stays live.
private struct NavBarHitTestPassthrough: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        BarUnlocker()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class BarUnlocker: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.findNavigationBar()?.isUserInteractionEnabled = false
            }
        }

        private func findNavigationBar() -> UINavigationBar? {
            var responder: UIResponder? = self
            while let r = responder {
                if let vc = r as? UIViewController,
                   let bar = vc.navigationController?.navigationBar {
                    return bar
                }
                responder = r.next
            }
            return nil
        }
    }
}

#Preview {
    SettingsView()
}
