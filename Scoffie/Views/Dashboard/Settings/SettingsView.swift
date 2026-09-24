import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.requestReview) private var requestReview
    /// Katalog — tylko do liczby „ukrywa N przepisów” przy alergenach.
    @Environment(\.recipeCatalogStore) private var recipeCatalogStore

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
    @State private var showNotificationsSheet = false
    @State private var showAppearanceSheet = false
    @State private var showDietSheet = false
    @State private var showAllergenPicker = false
    @State private var showMealSlotsSheet = false
    @State private var showProfileSheet = false
    @State private var showHelpSheet = false
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
                answer: "W Ustawieniach, w sekcji profilu, stuknij „Usuń konto”. Konto i Twoje dane znikają od razu; wspólne przepisy i plan zostają domownikom. Możesz też napisać na support@scoffie.app z adresu przypisanego do konta."
            ),
            FAQItem(
                id: "acc-export",
                question: "Czy mogę pobrać swoje dane?",
                answer: "Tak. Napisz na support@scoffie.app z adresu przypisanego do konta — odeślemy paczkę JSON z profilem, preferencjami, przepisami, posiłkami, krokami i rozmowami z asystentem. Szybciej: Ustawienia → Informacje → „Prywatność i regulamin” → „Pobierz moje dane” — paczka od razu trafia do arkusza udostępniania."
            ),
            FAQItem(
                id: "acc-allergens",
                question: "Jakie alergeny zna aplikacja?",
                answer: "Wszystkie 14 alergenów z listy unijnej (gluten, mleko, jajka, orzechy, orzeszki ziemne, ryby, skorupiaki, mięczaki, soja, seler, gorczyca, sezam, łubin, siarczyny) oraz laktozę jako osobną nietolerancję. Ustawiasz je w profilu — od tej chwili ani asystent, ani ręczne wstawianie posiłku nie przepuści dania z takim składnikiem dla osoby, która go unika."
            )
        ]),

        FAQSection(id: "assistant", title: "Asystent", items: [
            FAQItem(
                id: "ai-what",
                question: "Co potrafi asystent?",
                answer: "Układa cały tydzień albo jeden dzień pod Wasze cele, podmienia pojedyncze danie, dzieli jedno danie na porcje dla domowników o różnych celach, sprawdza, czego brakuje do białka, i składa listę zakupów. Zna Wasz katalog, alergeny i preferencje z profili."
            ),
            FAQItem(
                id: "ai-approve",
                question: "Czy asystent sam zmienia mój plan?",
                answer: "Nie. Asystent proponuje, a Ty zatwierdzasz jednym przyciskiem w karcie. Po zapisie masz godzinę na „Cofnij”. Jeśli w międzyczasie ktoś w domu zmienił plan ręcznie, karta powie o tym i zapyta, czy zapisać mimo to."
            ),
            FAQItem(
                id: "ai-limits",
                question: "Skąd biorą się limity?",
                answer: "Każda odpowiedź kosztuje. Limit wiadomości i limit zapisanych planów liczą się na gospodarstwo i odnawiają się w dniu odnowienia planu — kupiony 15 września wraca 15 października, a nie pierwszego. Ile zostało i kiedy wraca, widzisz w menu asystenta → Limity. Wyczerpany limit zapisów nie blokuje rozmowy."
            ),
            FAQItem(
                id: "ai-data",
                question: "Jakie dane trafiają do modelu?",
                answer: "Plan tygodnia, przepisy, imiona domowników, ich preferencje, alergeny i cele kaloryczne — ale tylko osób, które wyraziły zgodę na asystenta. Wzrost, waga i płeć nigdy nie wychodzą poza aplikację. Rozmowy kasujemy po 90 dniach albo od razu, gdy usuniesz historię."
            ),
            FAQItem(
                id: "ai-memory",
                question: "Co asystent o nas pamięta?",
                answer: "Krótkie notatki z rozmów — zwyczaje, niechęci, sprzęt w kuchni — do 30 naraz. Zobaczysz je i skasujesz w menu asystenta → „Co o Was pamięta”. Nie zapisuje niczego o wadze ani zdrowiu."
            ),
            FAQItem(
                id: "ai-wrong",
                question: "Asystent się pomylił. Co zrobić?",
                answer: "Przytrzymaj odpowiedź i wybierz „Zgłoś odpowiedź” albo napisz na support@scoffie.app z datą i treścią. Asystent to program oparty na modelu językowym — może się mylić i nie zastępuje dietetyka ani lekarza."
            )
        ]),

        FAQSection(id: "notifications", title: "Powiadomienia", items: [
            FAQItem(
                id: "notif-missing",
                question: "Dlaczego nie dostaję powiadomień?",
                answer: "Sprawdź dwie rzeczy: (1) główny przełącznik w Ustawienia → Powiadomienia w aplikacji, (2) uprawnienia w Ustawieniach iOS → Scoffie → Powiadomienia."
            ),
            FAQItem(
                id: "notif-when",
                question: "Kiedy wysyłane są przypomnienia?",
                answer: "Doba ma trzy stałe miejsca i w każdym mieści się najwyżej jedno powiadomienie. Rano — przegląd dnia. Po południu — przekąska, jeśli jest w planie. Wieczorem jedno z czterech: niedokończone odhaczanie, zakupy przed jutrzejszym gotowaniem, jutro bez planu albo seria domkniętych dni. Do tego przypomnienia przy samych posiłkach: o gotowaniu tyle wcześniej, ile zajmuje danie, a przy daniach bez gotowania — o samej porze. Plan tygodniowy i lista zakupów odzywają się wtedy, gdy domownik skończy wprowadzać zmiany."
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
                answer: "Świetnie! Napisz na support@scoffie.app — czytamy każdą wiadomość i wiele funkcji w aplikacji powstało właśnie z sugestii użytkowników."
            ),
            FAQItem(
                id: "other-bug",
                question: "Znalazłem błąd. Gdzie zgłosić?",
                answer: "Wyślij krótki opis na support@scoffie.app — najlepiej z screenem i nazwą urządzenia. Postaramy się odpowiedzieć i naprawić problem jak najszybciej."
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
                            integrationsSection
                            infoSection

                            SCDestructiveButton(
                                title: "Wyloguj się",
                                icon: "rectangle.portrait.and.arrow.right"
                            ) {
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
                // Kierunek przewijania steruje zwijaniem dolnego menu.
                .scTracksTabBarCompaction()
                .ignoresSafeArea(.container, edges: .top)
            }
            // Miejsce pod własnym paskiem zakładek — musi być WEWNĄTRZ
            // `NavigationStack`, patrz `scReservesTabBarSpace`.
            .scReservesTabBarSpace()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            .background(NavBarHitTestPassthrough())
            .sheet(isPresented: $showLegalDocumentsSheet) {
                LegalDocumentsSheet(dataExportClient: sessionStore.dataExportClient)
            }
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
            .sheet(isPresented: $showDietSheet) {
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
            .sheet(isPresented: $showHelpSheet) {
                helpSheet
                    .dashboardLiquidSheet()
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
                EditorialSettingsRow(
                    icon: "house.fill",
                    iconColor: SCPalette.sage,
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
                    iconColor: SCPalette.terracotta,
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
                    action: { showNotificationsSheet = true }
                )

                EditorialSettingsRow(
                    icon: "slider.horizontal.3",
                    iconColor: SCPalette.indigo,
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
                        isLast: false,
                        action: { showCookidooSheet = true }
                    )
                }

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
        if case .disabled = sessionStore.cookidooIntegrationStore?.status { return false }
        return true
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSettingsSectionHeader(title: "Informacje")

            EditorialSettingsCardGroup {
                EditorialSettingsRow(
                    icon: "book.fill",
                    iconColor: SCPalette.terracotta,
                    title: "Pomoc i FAQ",
                    action: { showHelpSheet = true }
                )

                EditorialSettingsRow(
                    icon: "heart.fill",
                    iconColor: SettingsAccent.coral,
                    title: "Oceń aplikację",
                    action: { requestReview() }
                )

                // Jedno wejście do dokumentów i eksportu danych — polityka
                // obiecuje wgląd „w Aplikacji”, a stopka logowania to za mało.
                EditorialSettingsRow(
                    icon: "hand.raised.fill",
                    iconColor: SCPalette.indigo,
                    title: "Prywatność i regulamin",
                    value: "v\(LegalDocMeta.version)",
                    action: { showLegalDocumentsSheet = true }
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
                .foregroundStyle(Color.scLabel(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(appVersionLabel)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.scMuted(scheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Sheets
    //
    // Every sheet shares the same chassis as the main settings list — warm
    // `SCPageBackground` canvas, editorial header (eyebrow + title + xmark),
    // and `Color.scTileBg` cards with `Color.scTileStroke` hairlines. The
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
        // Dwie gałęzie, bo stopka z wyjściem ma sens tylko w gospodarstwie —
        // pusta płyta na dole arkusza bez domu byłaby kreską donikąd.
        Group {
            if hasHousehold {
                pinnedEditorialSheet {
                    householdHeader
                } content: {
                    householdSheetContent
                } footer: {
                    householdFooter
                }
            } else {
                pinnedEditorialSheet {
                    householdHeader
                } content: {
                    householdSheetContent
                }
            }
        }
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
            Text("Widzą ją wszyscy domownicy. Od 2 do 64 znaków.")
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

                    // Bez podpisu przy włączonych powiadomieniach — zachowanie
                    // gospodarstwa i ciszy nocnej (22–7) jest wbudowane i nie
                    // wymaga tłumaczenia na ekranie. Zostaje tylko wyjaśnienie
                    // przygaszonej karty, gdy główny przełącznik jest wyłączony.
                    if !notificationsEnabled {
                        Text("Wszystkie powiadomienia są wyciszone. Włącz główny przełącznik, aby zarządzać typami przypomnień.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.scMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 6)
                            .padding(.top, 4)
                    }
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
                    .foregroundStyle(Color.scLabel(scheme))
                    .contentTransition(.opacity)
                    .id(notificationsEnabled)

                Text("Główny przełącznik dla wszystkich przypomnień aplikacji.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: $notificationsEnabled)
                .labelsHidden()
                .tint(SCPalette.sage)
                .scaleEffect(0.95)
                .fixedSize()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
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

    private var notificationChannelsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Kanały")

            VStack(spacing: 0) {
                channelToggleRow(
                    icon: "sun.horizon.fill",
                    accent: SCPalette.butter,
                    title: "Poranny przegląd",
                    subtitle: "Jedno spojrzenie na dzień, zanim się zacznie: ile posiłków, ile kalorii, czym zaczynasz.",
                    isOn: $morningBriefingEnabled,
                    isLast: false
                )

                channelToggleRow(
                    icon: "flame.fill",
                    accent: SCPalette.terracotta,
                    title: "Pory posiłków",
                    subtitle: "Przypomnienie o gotowaniu tyle przed posiłkiem, ile zajmuje danie. Przy daniach bez gotowania — sama pora.",
                    isOn: $mealRemindersEnabled,
                    isLast: false
                )

                channelToggleRow(
                    icon: "moon.stars.fill",
                    accent: SCPalette.lavender,
                    title: "Podsumowanie dnia",
                    subtitle: "Wieczorem: niedokończone odhaczanie, zakupy przed jutrzejszym gotowaniem albo seria domkniętych dni.",
                    isOn: $dayWrapUpEnabled,
                    isLast: false
                )

                channelToggleRow(
                    icon: "calendar.badge.clock",
                    accent: SCPalette.indigo,
                    title: "Plan tygodniowy",
                    subtitle: "Jedno podsumowanie, gdy domownik skończy zmieniać plan.",
                    isOn: $planRemindersEnabled,
                    isLast: false
                )

                channelToggleRow(
                    icon: "cart.fill",
                    accent: SCPalette.sage,
                    title: "Lista zakupów",
                    subtitle: "Jedno podsumowanie, gdy domownik odhaczy zakupy.",
                    isOn: $shoppingRemindersEnabled,
                    isLast: true
                )
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
                    .foregroundStyle(Color.scLabel(scheme))

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(SCPalette.sage)
                .scaleEffect(0.85)
                .fixedSize()
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
                        .foregroundStyle(Color.scMuted(scheme))
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
                            .stroke(Color.scTileStroke(scheme), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(themeEyebrow(for: theme).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(SCPalette.terracotta)

                    Text(theme.title)
                        .font(.system(size: 20, weight: .heavy))
                        .tracking(-0.4)
                        .foregroundStyle(Color.scLabel(scheme))

                    Text(themeDescription(for: theme))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SCRadioMark(isOn: selected)
            }
            .padding(14)
            // Zaznaczenie jak zaznaczony `SCChoiceTile`: tint i obwódka
            // akcentu, bez cienia. Terakotowa poświata pod wybraną kartą była
            // jedynym cieniem na kartach Ustawień.
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

    /// Mini canvas — paints the actual base + glow stack used by
    /// `SCPageBackground` so the user sees what the live screen will look
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
        let glow = SCPalette.terracotta.opacity(scheme == .dark ? 0.18 : 0.14)
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
                            .fill(SCPalette.terracotta)
                            .frame(width: 14, height: 4),
                        alignment: .leading
                    )
                    .padding(.top, 3)
            }
            .padding(8)
        }
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
        pinnedEditorialSheet {
            EditorialSheetHeader(
                eyebrow: "Personalizacja",
                title: "Dieta i alergeny"
            ) {
                showDietSheet = false
            }
        } content: {
            VStack(alignment: .leading, spacing: 18) {
                Text("Aplikacja użyje tych ustawień na liście przepisów: dieta i alergeny odsiewają dania, a cel decyduje, które trafią na górę.")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)

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
        .sheet(isPresented: $showAllergenPicker) {
            AllergenPickerSheet(
                selected: selectedAllergens,
                hiddenRecipes: allergenHiddenRecipes,
                onToggle: { toggleAllergen($0) },
                onClear: { clearAllergens() }
            )
            .presentationDetents([.large])
            .dashboardLiquidSheet()
        }
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
            HStack(alignment: .center, spacing: 14) {
                EditorialSettingsTileIcon(icon: goal.icon, color: goal.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.scLabel(scheme))

                    Text(goal.subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SCRadioMark(isOn: isSelected)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.scRule(scheme))
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
        currentGoal != .plan && calorieGoal != suggestedCalories
    }

    /// Dwa warianty: policzony z sylwetki (wtedy mówimy skąd) i awaryjny,
    /// gdy w profilu brakuje danych. Drugi zachęca do ich uzupełnienia,
    /// zamiast udawać, że liczba jest szyta na miarę.
    private var calorieSuggestionText: String {
        guard bodyMetrics != nil else {
            return "Dla tego celu zwykle wychodzi \(suggestedCalories) kcal. Uzupełnij sylwetkę w „Twoje dane”, a policzymy dokładniej."
        }
        return "Dla Twojej sylwetki i tego celu wychodzi \(suggestedCalories) kcal."
    }

    private var calorieSuggestionRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SCPalette.butter)
                .frame(width: 22)

            Text(calorieSuggestionText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.scMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.smooth(duration: 0.22)) {
                    calorieGoal = snappedCalorieGoal(from: Double(suggestedCalories))
                }
            } label: {
                Text("Ustaw")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SCPalette.terracotta)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.20 : 0.12)))
                    .overlay(Capsule().stroke(SCPalette.terracotta.opacity(0.30), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ustaw \(suggestedCalories) kcal")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.scChipBg(scheme).opacity(scheme == .dark ? 0.5 : 0.7))
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
            HStack(alignment: .center, spacing: 14) {
                EditorialSettingsTileIcon(icon: diet.icon, color: diet.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(diet.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.scLabel(scheme))

                    Text(diet.subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SCRadioMark(isOn: isSelected)
            }
            // Dokładnie ta sama geometria co `goalRow` — obie sekcje to ta
            // sama lista wyboru i mają wyglądać identycznie. Wcześniej dieta
            // miała własną `minHeight` i inny padding pionowy, przez co jej
            // wiersze były wyraźnie wyższe od wierszy celu.
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    .padding(.leading, 16 + 32 + 14)
            }
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
                    Text("Uzupełnij sylwetkę w „Twoje dane”, a rozbijemy dzienny cel na białko, węglowodany i tłuszcze.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
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
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Color.scLabel(scheme))

                Text(isOverridden ? "Twoja wartość" : "Wyliczone")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOverridden ? macro.accent : Color.scFaint(scheme))
            }

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(.system(size: 17, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))
                    .contentTransition(.numericText(value: Double(value)))

                Text("g")
                    .font(.system(size: 11.5, weight: .semibold))
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
                .font(.system(size: 12, weight: .bold))
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
                Text("Z makr wychodzi \(macros.totalKcal) kcal")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.scLabel(scheme))

                Text(macroFooterNote(diff: diff))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(abs(diff) > 60 ? SCPalette.terracotta : Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hasMacroOverride {
                Button {
                    withAnimation(.smooth(duration: 0.22)) { resetMacroOverrides() }
                } label: {
                    Text("Policz")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(SCPalette.terracotta)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.20 : 0.12)))
                        .overlay(Capsule().stroke(SCPalette.terracotta.opacity(0.30), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Policz makra od nowa")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.scChipBg(scheme).opacity(scheme == .dark ? 0.5 : 0.7))
    }

    private func macroFooterNote(diff: Int) -> String {
        if abs(diff) <= 20 { return "Spina się z dziennym celem." }
        if diff > 0 { return "To \(diff) kcal ponad Twój cel \(calorieGoal) kcal." }
        return "To \(abs(diff)) kcal poniżej Twojego celu \(calorieGoal) kcal."
    }

    private func resetMacroOverrides() {
        proteinOverride = -1
        fatOverride = -1
        carbsOverride = -1
    }

    private var calorieGoalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Cel kaloryczny")

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 14) {
                    EditorialSettingsTileIcon(icon: "flame.fill", color: SCPalette.terracotta)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dzienny cel")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.scLabel(scheme))
                        Text("Aplikacja podpowie, jak rozłożyć posiłki w ciągu dnia.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.scMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                calorieGoalEditor
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

    /// Duża liczba nad suwakiem co 50 kcal — cały wybór. Suwak ma własny
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
    /// przepisów przez to znika. Wybór ma własny arkusz
    /// (`AllergenPickerSheet`), patrz opis w `AllergenPickerSheet.swift`.
    private var allergensSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Alergeny i nietolerancje")

            AllergenSummaryCard(
                selected: selectedAllergens,
                hiddenRecipes: allergenHiddenRecipes,
                onEdit: { showAllergenPicker = true }
            )
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

    private var helpSheet: some View {
        pinnedEditorialSheet {
            EditorialSheetHeader(
                eyebrow: "Wsparcie",
                title: "Pomoc i FAQ"
            ) {
                showHelpSheet = false
                expandedFAQ = nil
            }
        } content: {
            VStack(alignment: .leading, spacing: 18) {
                Text("Najczęściej zadawane pytania o planowanie posiłków, listę zakupów i wspólne gospodarstwo. Nie znalazłeś odpowiedzi? Napisz do nas.")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Self.faqSections) { section in
                    faqSectionCard(section)
                }

                contactCard
                    .padding(.top, 4)
            }
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
                    .fill(Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
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
                        .foregroundStyle(Color.scLabel(scheme))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(
                            isExpanded
                                ? SCPalette.terracotta
                                : Color.scFaint(scheme)
                        )
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle().fill(
                                isExpanded
                                    ? SCPalette.terracotta.opacity(scheme == .dark ? 0.18 : 0.12)
                                    : Color.scChipBg(scheme)
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
                    .foregroundStyle(Color.scMuted(scheme))
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
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    .padding(.leading, 16)
            }
        }
    }

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                EditorialSettingsTileIcon(icon: "envelope.fill", color: SCPalette.terracotta, size: 44, radius: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Nadal masz pytanie?")
                        .font(.system(size: 16, weight: .heavy))
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(scheme))
                    Text("Czytamy każdą wiadomość. Odpowiadamy zwykle w ciągu kilku dni.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let url = URL(string: "mailto:support@scoffie.app?subject=Scoffie%20—%20Pytanie") {
                Link(destination: url) {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 12.5, weight: .heavy))
                        Text("Napisz do nas")
                            .font(.system(size: 14, weight: .bold))
                            .tracking(-0.1)
                    }
                    .foregroundStyle(SCPalette.terracotta)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .scSoftCapsule()
                }
                .accessibilityLabel("Napisz do nas — support@scoffie.app")
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

    /// Treść arkusza gospodarstwa — domownicy, a bez domu karta zakładania.
    /// Zaproszenie i wyjście nie stoją tu, tylko w stopce arkusza.
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
    /// dłuższych niż ekran (dieta, pomoc, gospodarstwo). Nagłówek wewnątrz
    /// `ScrollView` odjeżdżał razem z krzyżykiem; tu stoi, a treść gaśnie pod
    /// nim (`scScrollEdgeFade`), bez kreski — jak w szczegółach posiłku
    /// i w filtrach przepisów.
    private func pinnedEditorialSheet<Header: View, Content: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) -> some View {
        editorialSheet {
            VStack(spacing: 0) {
                header()
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                ScrollView {
                    content()
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scScrollEdgeFade()
            }
        }
    }

    /// To samo z akcją przypiętą na dole (`scSheetFooter`, wspólna stopka
    /// arkuszy) — gospodarstwo trzyma tam wyjście, pod ręką zamiast na końcu
    /// listy. Stopka rezerwuje miejsce na swój cień sama, więc pod treścią
    /// wystarczy krótki oddech.
    private func pinnedEditorialSheet<Header: View, Content: View, Footer: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        // Wartość, nie domknięcie: `scSheetFooter` przechowuje swoje
        // domknięcie, a parametr `footer` nie może uciec z tej funkcji.
        let footerView = footer()

        return editorialSheet {
            VStack(spacing: 0) {
                header()
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                ScrollView {
                    content()
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
                .scScrollEdgeFade()
                .scSheetFooter { footerView }
            }
        }
    }

    private var editorialNameInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSheetSectionLabel(title: "Nazwa")

            TextField("Np. Dom", text: $createHouseholdName)
                .textInputAutocapitalization(.words)
                .font(.system(size: 15.5, weight: .medium))
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
                    .font(.system(size: 11, weight: .medium))
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
    // i jedną linijką „3 osoby · wspólny plan i lista zakupów”, ołówek do
    // nazwy — obok krzyżyka, wyjście — w stopce na dole arkusza.
    //
    // Trzy rundy uwag Rafała (23.09.2026): najpierw „za dużo zbędnego tekstu”
    // (karta z powtórzoną nazwą, liczby osób w trzech miejscach, sekcja
    // o tym, co domownicy dzielą), potem „znów pusto i smutno” (zaproszenie
    // jako osobna karta z jednym przyciskiem), a w końcu „usuń info
    // o diecie czy czymkolwiek innym, to tu nie ma sensu”. Wiersz domownika
    // to dziś sama tożsamość: awatar, imię i plakietki „TY” / „WŁAŚCICIEL”.

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
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Color.scMuted(scheme))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                } else if householdMembers.isEmpty {
                    Text("Nie udało się wczytać domowników.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.scMuted(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    ForEach(Array(householdMembers.enumerated()), id: \.element.id) { index, member in
                        memberRow(member, showsRule: index > 0)
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
                    .font(.system(size: 12, weight: .medium))
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
            accent: SCPalette.sage,
            subtitle: hasHousehold && !householdMembers.isEmpty ? householdSummary : nil,
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

    /// „3 osoby · wspólny plan i lista zakupów” — jedyne miejsce z liczbą osób.
    private var householdSummary: String {
        let count = householdMembers.count
        return "\(count) \(membersLabel(for: count)) · wspólny plan i lista zakupów"
    }

    /// Stopka arkusza: zaproszenie nad wyjściem (Rafał, 23.09.2026: „button
    /// do zapraszania daj na dole nad opuść”). Zaprasza tylko właściciel —
    /// reszta widzi pod domownikami, kogo o to poprosić.
    private var householdFooter: some View {
        VStack(spacing: 10) {
            if canCreateInvitations {
                inviteButton
            }
            leaveHouseholdButton
        }
    }

    /// Link tworzy się sam przy otwarciu arkusza (`preloadHouseholdContextIfNeeded`),
    /// więc zwykle od razu jest czym się podzielić; przycisk „Przygotuj” zostaje
    /// na wypadek, gdyby serwer za pierwszym razem odmówił.
    ///
    /// Dwie linijki zamiast samej kapsuły: nad czerwonym „Opuść” dwie
    /// kapsuły w podobnych barwach czytały się jak para równorzędnych akcji.
    /// Ikona, co robi, i warunki linku w jednym miejscu; glif po prawej mówi,
    /// że stuknięcie otwiera udostępnianie.
    @ViewBuilder
    private var inviteButton: some View {
        let isReady = invitationLink != nil
        let label = HStack(spacing: 12) {
            Circle()
                .fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.22 : 0.16))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SCPalette.terracotta)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(isReady ? "Zaproś domownika" : "Przygotuj zaproszenie")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scLabel(scheme))
                Text("Link dla jednej osoby · ważny 7 dni")
                    .font(.system(size: 12, weight: .medium))
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
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SCPalette.terracotta)
                }
            }
            .frame(width: 24)
            .accessibilityHidden(true)
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .scSoftSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

        if let invitationLink {
            ShareLink(
                item: invitationLink,
                message: Text("Dołącz do naszego domu w Scoffie — wspólny plan posiłków i lista zakupów.")
            ) {
                label
            }
            .buttonStyle(PlanPressStyle(scale: 0.97))
            .accessibilityHint("Udostępnia link zaproszenia ważny 7 dni")
        } else {
            Button {
                Task { await createInvitationLink() }
            } label: {
                label
            }
            .buttonStyle(PlanPressStyle(scale: 0.97))
            .disabled(isCreatingInvitation)
        }
    }

    /// Wyjście w stopce arkusza (Rafał, 23.09.2026: „daj to wychodzenie jako
    /// button na dole”), w tym samym stroju co każda akcja nieodwracalna
    /// (`SCDestructiveButton`) i z pytaniem w alercie — nie stoi obok nazwy
    /// domu ani na końcu przewijanej listy.
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.scLabel(scheme))

                    Text(invitation.subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.scMuted(scheme))

                    if let expiry = invitation.expiresAtText {
                        Text("Ważne do: \(expiry)")
                            .font(.system(size: 11, weight: .medium))
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.scLabel(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule(style: .continuous).fill(Color.scChipBg(scheme)))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.scTileStroke(scheme), lineWidth: 1.2)
                        )
                }
                .buttonStyle(.plain)

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
                        .font(.system(size: 13, weight: .bold))
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
                EditorialSettingsTileIcon(icon: "house.badge.plus", color: SCPalette.sage, size: 44, radius: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Brak gospodarstwa")
                        .font(.system(size: 17, weight: .heavy))
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(scheme))
                    Text("Utwórz wspólne miejsce do planowania posiłków i listy zakupów.")
                        .font(.system(size: 12.5, weight: .medium))
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
                createHouseholdName = ""
                showCreateHouseholdSheet = true
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
                    .font(.system(size: 13, weight: .heavy))
                Text(title)
                    .font(.system(size: 14, weight: .bold))
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
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)

                if isMe {
                    memberBadge("TY", color: SCPalette.terracotta)
                }

                if isOwner {
                    memberBadge("WŁAŚCICIEL", color: SCPalette.butter)
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
                // usunąć stąd; od tego jest „Opuść gospodarstwo” w stopce.
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

    /// Mała plakietka przy imieniu — „TY” w terakocie, „WŁAŚCICIEL” w maśle.
    /// Stały rozmiar (`fixedSize`): przy długim imieniu skraca się imię,
    /// a nie plakietka.
    private func memberBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
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
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color.scMuted(scheme))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.scChipBg(scheme)))
                .overlay(Circle().stroke(Color.scTileStroke(scheme), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(removingMemberId != nil)
        .accessibilityLabel("Opcje domownika: \(member.displayName)")
    }

    // MARK: - Actions / helpers

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
// Defined here (not in SCPalette) because it's only used by Settings v2.
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
                .font(.system(size: size * 0.40, weight: .semibold))
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

/// Suwak „Dzienny cel” z liczbą nad nim.
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(shown, format: .number.grouping(.never))
                    .font(.system(size: 44, weight: .heavy))
                    .tracking(-1.4)
                    .foregroundStyle(SCPalette.terracotta)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(shown)))

                Text("kcal / dzień")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Pod palcem liczba zmienia się od razu — rolowanie co krok
            // nie nadążało za ruchem. Roluje, gdy wartość przychodzi
            // z zewnątrz („Ustaw”, „Wyczyść preferencje”).
            .animation(isEditing ? nil : .smooth(duration: 0.18), value: shown)

            VStack(spacing: 6) {
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

                HStack {
                    Text("\(range.lowerBound)")
                    Spacer()
                    Text("\(range.upperBound)")
                }
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.scFaint(scheme))
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
