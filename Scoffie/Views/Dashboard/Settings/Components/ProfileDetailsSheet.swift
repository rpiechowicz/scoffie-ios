import SwiftUI

// Arkusz „Twoje dane” otwierany kartą profilu na górze Ustawień.
//
// Zbiera to, co kreator powitalny zbierał raz i czego potem nie dało się już
// zmienić: imię, płeć, rok urodzenia, wzrost, wagę i liczbę treningów.
// Wszystkie te pola jeżdżą do backendu (`users:profile:update`
// i `users:preferences:update`).
//
// Świadomie NIE trafiają tu dieta, alergeny ani cel kaloryczny. Tam są
// preferencje jedzeniowe, tu fakty o użytkowniku — podział idzie za kluczami
// `settings.profile.*` kontra `settings.diet.*`.
//
// Wygląd od 6.10.2026 (artefakt „Arkusze Ustawień”, sekcja 1, cztery rundy
// z Rafałem — „super, pasuje mi, koduj”):
// - nagłówek = profil: awatar, imię jako tytuł, e-mail pod nim, ołówek obok
//   krzyżyka otwiera okno „Imię” (jak nazwa gospodarstwa); osobna karta
//   profilu i pole imienia w miejscu odpadły;
// - na górze WYNIK, bo po to są te dane: kcal na utrzymanie wagi i BMI na
//   skali ocen — cyfry rolują, znacznik jedzie po skali w kolorze oceny;
// - Sylwetka = cztery wiersze listy. Stuknięcie otwiera mały arkusz na 1/3
//   ekranu z wyborem (Rafał: „wybory dałbym dalej w sheet na 1/3 ekranu”) —
//   płeć to kafle z „Nie podaję”, rok i wzrost systemowe koło, waga koło
//   kilogramów i dziesiątych jak w Zdrowiu. Arkusz NIE przyciemnia reszty
//   i przepuszcza dotyk (`presentationBackgroundInteraction`): wynik zmienia
//   się na oczach, a stuknięcie w inny wiersz podmienia wybór bez zamykania;
// - treningi = kafle z ikoną w kolorze wysiłku (`SCIconTilePicker`), bez
//   podpisu z nazwą poziomu.
// Pola liczbowe z klawiaturą (i ich drafty, które pilnowały, żeby zapis nie
// wstrzykiwał wartości pod palce) odeszły razem z polami.
//
// Od 7.10.2026 wynik, Sylwetka, treningi, profil nad treścią i okno „Imię” to
// wspólne klocki z `ProfileBodyForm.swift` — stoi na nich też krok 1 kreatora.
// Tu zostaje to, co należy do arkusza: wartości w `@ProtectedSetting`, zapis
// z debounce i przy zejściu, nagłówek z krzyżykiem i usunięcie konta.
struct ProfileDetailsSheet: View {
    var onClose: () -> Void
    /// Ekran wepchnięty w inny arkusz (odsyłacz „Uzupełnij sylwetkę w „Twoje
    /// dane”” w „Dieta i alergeny”): systemowy pasek z „wstecz” zamiast
    /// nagłówka z krzyżykiem, a zapis przy zejściu z ekranu — „wstecz” nie
    /// przechodzi przez `commitAndClose`.
    var isPushed: Bool = false

    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.toasts) private var toasts
    @Environment(\.colorScheme) private var scheme

    @ProtectedSetting("settings.user.displayName") private var displayName: String = ""
    @ProtectedSetting("settings.user.email") private var email: String = ""
    @ProtectedSetting("settings.user.avatarUrl") private var avatarUrl: String = ""
    @AppStorage("settings.user.avatarColor") private var avatarColor: Int = -1
    /// Ziarno awatara — to samo id, którym posługuje się `MemberAvatar`.
    @AppStorage("auth.userId") private var userId: String = ""
    @ProtectedSetting("settings.profile.yearOfBirth") private var yearOfBirth: Int = Self.defaultYearOfBirth
    @ProtectedSetting("settings.profile.heightCm") private var heightCm: Int = Self.defaultHeightCm
    @ProtectedSetting("settings.profile.weightKg") private var weightKg: Double = Self.defaultWeightKg
    @ProtectedSetting("settings.profile.sex") private var sexRaw: String = ""
    @ProtectedSetting("settings.diet.activityLevel") private var activityLevelRaw: Int = ActivityLevel.light.rawValue

    @State private var isConfirmingDeletion = false
    @State private var isDeleting = false
    /// Konto usunięte — ekran wepchnięty, który właśnie schodzi, nie ma już
    /// czego zapisywać.
    @State private var accountDeleted = false
    @State private var deletionError: String?

    /// Imię w oknie „Imię” — kopia, żeby „Anuluj” niczego nie zmieniało.
    @State private var nameDraft = ""
    @State private var isEditingName = false

    /// Mały arkusz z wyborem i okna czekające na jego zjazd — wspólny
    /// mechanizm z kreatorem (`ProfilePickerGate`): ołówek i „Usuń konto” da
    /// się stuknąć przy otwartym wyborze.
    @State private var pickerGate = ProfilePickerGate()

    private enum PendingAlert {
        case rename
        case deleteAccount
    }

    /// Czy w tym otwarciu arkusza doszło do JAKIEJKOLWIEK edycji. Zapis do
    /// backendu (debounce i ten przy zamknięciu) wychodzi tylko wtedy —
    /// samo otwarcie i zamknięcie arkusza nie może nic wysłać. Wcześniej
    /// `task(id:)` odpalał się też przy pierwszym pokazaniu i po 600 ms
    /// wypychał aktualny stan — jeśli lokalne wartości były akurat domyślne
    /// (świeże logowanie, zanim `users:me` zdążył przywrócić prawdziwe),
    /// nadpisywały w bazie realną sylwetkę.
    @State private var didObserveInitialToken = false
    /// Licznik edycji z ręki (sylwetka + aktywność) przy ostatniej obsłużonej
    /// zmianie — wartości wpisane przez `users:me` / odczyt preferencji nie są
    /// edycją i nie wysyłają niczego z powrotem (7.10.2026, Codex runda 2).
    @State private var observedEditGeneration = 0
    @State private var didEditThisSession = false
    /// W tym otwarciu wybrano „Nie podaję” — zapis kasuje płeć na serwerze
    /// (`saveProfile(clearSex:)`), zamiast ją pomijać.
    @State private var clearsSex = false

    // Te same wartości startowe co w kreatorze powitalnym — arkusz nie może
    // pokazać innych liczb niż ekran, który je pierwszy zapisał.
    private static let defaultYearOfBirth = BodyMetrics.defaultYearOfBirth
    private static let defaultHeightCm = BodyMetrics.defaultHeightCm
    private static let defaultWeightKg = BodyMetrics.defaultWeightKg

    private var yearRange: ClosedRange<Int> { ProfileBodyForm.yearRange }

    var body: some View {
        Group {
            if isPushed {
                scrollContent
                    .scPushedPage("Twoje dane")
            } else {
                ZStack {
                    SCPageBackground(scheme: scheme)
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        // Przypięty nad treścią: profil jest nagłówkiem arkusza.
                        EditorialSheetHeader(
                            eyebrow: "Twoje dane",
                            title: nameTitle,
                            detail: emailText,
                            leading: AnyView(avatar(size: 52)),
                            onClose: { commitAndClose() }
                        ) {
                            renameButton
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 12)

                        scrollContent
                            .scScrollEdgeFade()
                    }
                }
            }
        }
        .onAppear {
            normaliseStoredValues()
        }
        // Zejście z ekranu domyka zapis w obu trybach: „wstecz” w ekranie
        // wepchniętym i przeciągnięcie arkusza w dół nie przechodzą przez
        // `commitAndClose`, a anulują zaplanowany `task(id:)` — zmiana sprzed
        // 600 ms zostałaby tylko na telefonie. Nie w trakcie ani po usunięciu
        // konta: zasłona zdejmuje ekran, zanim `deleteAccount` wróci.
        .onDisappear {
            guard !isDeleting, !accountDeleted else { return }
            commitAndSave()
        }
        // „Nie podaję” wybrane w TYM otwarciu — dopiero wtedy zapis wysyła
        // jawny `null`. Puste pole z samego startu (konto bez płci, logowanie
        // przed `users:me`) nie może skasować płci zapisanej na serwerze.
        .onChange(of: sexRaw) { previous, current in
            if current.isEmpty, !previous.isEmpty {
                clearsSex = true
            } else if !current.isEmpty {
                clearsSex = false
            }
        }
        .profileNameAlert(isPresented: $isEditingName, draft: $nameDraft) {
            saveName()
        }
        .alert("Usunąć konto?", isPresented: $isConfirmingDeletion) {
            Button("Anuluj", role: .cancel) {}
            Button("Usuń konto", role: .destructive) { deleteAccount() }
        } message: {
            Text("Wypiszemy Cię z gospodarstwa i trwale usuniemy konto razem z Twoim profilem, preferencjami i odhaczonymi posiłkami. Tego nie da się cofnąć.")
        }
        // Każda zmiana kasuje poprzedni zapis i planuje nowy 600 ms później —
        // kręcenie kołem nie robi round-tripa na każdy rok. Pierwsze odpalenie
        // to samo pokazanie arkusza (`task(id:)` startuje też bez zmiany id) —
        // nic wtedy nie wysyłamy; każde KOLEJNE to już realna edycja.
        .task(id: profileSyncToken) {
            let editGeneration = Self.userEditGeneration
            guard didObserveInitialToken else {
                didObserveInitialToken = true
                observedEditGeneration = editGeneration
                return
            }
            // Wartości zmienił odczyt z serwera, nie użytkownik — nic nie wysyłamy.
            guard editGeneration != observedEditGeneration else { return }
            observedEditGeneration = editGeneration
            didEditThisSession = true
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await pushProfile()
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isPushed {
                    identityRow
                        .padding(.bottom, 18)
                }

                ProfileBodyForm(
                    sexRaw: $sexRaw,
                    yearOfBirth: $yearOfBirth,
                    heightCm: $heightCm,
                    weightKg: $weightKg,
                    activity: activityLevel,
                    gate: pickerGate
                )

                deleteAccountSection
                    .padding(.top, 22)
            }
            .padding(.horizontal, 20)
            .padding(.top, isPushed ? 8 : 6)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Profil

    private var nameTitle: String {
        displayName.isEmpty ? "Twoje konto" : displayName
    }

    private var emailText: String? {
        email.isEmpty ? nil : email
    }

    private func avatar(size: CGFloat) -> some View {
        ProfileAvatar(
            avatarUrl: avatarUrl.isEmpty ? nil : avatarUrl,
            displayName: nameTitle,
            size: size,
            colorIndex: avatarColor >= 0 ? avatarColor : nil,
            seed: userId.isEmpty ? displayName : userId
        )
    }

    private var renameButton: some View {
        SCSheetIconButton(systemName: "pencil", accessibilityLabel: "Zmień imię") {
            startEditingName()
        }
    }

    /// Profil w ekranie wepchniętym — tam nagłówek arkusza z krzyżykiem
    /// zastępuje systemowy pasek, więc imię i ołówek stoją na górze treści.
    private var identityRow: some View {
        ProfileIdentityRow(
            title: nameTitle,
            detail: emailText,
            avatarUrl: avatarUrl.isEmpty ? nil : avatarUrl,
            colorIndex: avatarColor >= 0 ? avatarColor : nil,
            seed: userId.isEmpty ? displayName : userId,
            onRename: { startEditingName() }
        )
    }

    private var trimmedNameDraft: String {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startEditingName() {
        nameDraft = displayName
        present(.rename)
    }

    /// Okno od razu — albo, gdy na ekranie stoi mały arkusz z wyborem, dopiero
    /// po jego zjeździe (`ProfilePickerGate.present`).
    private func present(_ alert: PendingAlert) {
        pickerGate.present { show(alert) }
    }

    private func show(_ alert: PendingAlert) {
        switch alert {
        case .rename:        isEditingName = true
        case .deleteAccount: isConfirmingDeletion = true
        }
    }

    /// Puste imię się nie zapisuje — „Zapisz” jest wtedy wyłączone.
    private func saveName() {
        let trimmed = trimmedNameDraft
        guard !trimmed.isEmpty else { return }
        displayName = trimmed
    }

    // MARK: - Treningi

    private var activityLevel: Binding<ActivityLevel> {
        Binding(
            get: { ActivityLevel(rawValue: activityLevelRaw) ?? .light },
            set: { activityLevelRaw = $0.rawValue }
        )
    }

    // MARK: - Usunięcie konta

    /// Świadomie na samym dole — to jedyna nieodwracalna rzecz w tym arkuszu
    /// i ma wyglądać inaczej niż wszystko nad nią (`SCDestructiveButton`).
    /// Potwierdzenie w alercie wymienia z nazwy, co zniknie.
    private var deleteAccountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SCDestructiveButton(
                title: isDeleting ? "Usuwam konto…" : "Usuń konto",
                icon: "trash.fill",
                isLoading: isDeleting
            ) {
                present(.deleteAccount)
            }

            if let deletionError {
                SCInlineErrorText(deletionError)
            }
        }
    }

    /// Arkusz zamyka się dopiero po potwierdzeniu z serwera. Gdyby zamykał
    /// się od razu, nieudane kasowanie zostawiłoby użytkownika na ekranie
    /// ustawień bez żadnej informacji, że konto nadal istnieje.
    private func deleteAccount() {
        guard !isDeleting else { return }
        isDeleting = true
        deletionError = nil

        let store = sessionStore
        Task { @MainActor in
            let succeeded = await store.deleteAccount()
            isDeleting = false

            if succeeded {
                accountDeleted = true
                onClose()
            } else {
                deletionError = store.authError ?? "Nie udało się usunąć konta. Spróbuj ponownie."
                store.authError = nil
            }
        }
    }

    // MARK: - Zapis

    /// Token zmienia się przy każdej edycji — `task(id:)` anuluje
    /// zaplanowany zapis i planuje nowy.
    private var profileSyncToken: String {
        "\(displayName)|\(yearOfBirth)|\(heightCm)|\(weightKg)|\(activityLevelRaw)|\(sexRaw)"
    }

    /// Dwa round-tripy, bo to dwa różne zasoby: sylwetka idzie przez
    /// `users:profile:update`, a liczba treningów przez
    /// `users:preferences:update` (tam mieszka `activityLevel`).
    private func pushProfile() async {
        guard await Self.serverCopiesReady(sessionStore, toasts: toasts) else { return }
        // Nowsza edycja w międzyczasie ma już własne zadanie zapisu.
        guard !Task.isCancelled else { return }
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        await sessionStore.saveProfile(
            displayName: trimmedName.isEmpty ? nil : trimmedName,
            yearOfBirth: yearOfBirth,
            heightCm: heightCm,
            weightKg: weightKg,
            sex: sexRaw.isEmpty ? nil : sexRaw,
            clearSex: sexRaw.isEmpty && clearsSex
        )

        await sessionStore.saveUserPreferences(activityLevel: activityLevelRaw)
    }

    /// Arkusz wysyła CAŁY zestaw (sylwetka + aktywność) z lokalnej kopii, więc
    /// najpierw upewnia się, że kopia przyszła z serwera (7.10.2026). Po
    /// odtworzeniu telefonu albo nieudanym odczycie przy starcie kopia to
    /// wartości domyślne — wysłane nadpisałyby prawdziwe dane konta. `false` =
    /// nic nie wysyłać (komunikat już pokazany).
    /// Edycje z ręki w obu domenach, które ten arkusz zapisuje.
    private static var userEditGeneration: Int {
        let store = SCProtectedSettings.shared
        return store.userEditGeneration(.profile) &+ store.userEditGeneration(.preferences)
    }

    @MainActor
    private static func serverCopiesReady(_ store: SessionStore, toasts: SCToastCenter) async -> Bool {
        let profile = await store.ensureProfileBaseline()
        let preferences = await store.ensurePreferencesBaseline()
        if profile == .unavailable || preferences == .unavailable {
            toasts.error("Nie udało się wczytać Twoich danych", "Spróbuj ponownie.")
            return false
        }
        if profile == .reloaded || preferences == .reloaded {
            toasts.info(
                "Wczytano Twoje dane",
                "Ostatnia zmiana nie została zapisana — wprowadź ją jeszcze raz."
            )
            return false
        }
        return true
    }

    /// Zamknięcie arkusza nie może zgubić zmiany zrobionej sekundę wcześniej —
    /// `task(id:)` zostaje anulowany razem z widokiem, więc zapis wychodzi tu
    /// jeszcze raz, bez debounce'u. Ale TYLKO gdy w tym otwarciu cokolwiek
    /// zmieniono (`didEditThisSession`) — otwarcie i zamknięcie arkusza bez
    /// edycji nie może wypchnąć lokalnego stanu do bazy.
    private func commitAndClose() {
        commitAndSave()
        onClose()
    }

    /// Zapis na serwer, jeśli w tym otwarciu coś się zmieniło — bez zamykania
    /// (ekran wepchnięty schodzi „wstecz” sam).
    private func commitAndSave() {
        let tokenBeforeCommit = profileSyncToken
        normaliseStoredValues()
        guard didEditThisSession || profileSyncToken != tokenBeforeCommit else {
            return
        }
        let store = sessionStore
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = yearOfBirth
        let height = heightCm
        let weight = weightKg
        let activity = activityLevelRaw
        let sexValue = sexRaw
        let clearSex = sexValue.isEmpty && clearsSex
        // Zapis już zaplanowany — krzyżyk woła tę funkcję, a zaraz po nim
        // `onDisappear` drugi raz; bez zdjęcia flagi poszłyby dwa zapisy.
        didEditThisSession = false

        // Kolejka do stałej PRZED zadaniem: zaraz po tej funkcji arkusz się
        // zamyka (`commitAndClose`) albo ekran schodzi „wstecz”, i środowisko
        // tego widoku już nie istnieje, gdy `await` wracają.
        let toasts = toasts
        Task { @MainActor in
            guard await Self.serverCopiesReady(store, toasts: toasts) else { return }
            let profileSaved = await store.saveProfile(
                displayName: name.isEmpty ? nil : name,
                yearOfBirth: year,
                heightCm: height,
                weightKg: weight,
                sex: sexValue.isEmpty ? nil : sexValue,
                clearSex: clearSex
            )
            let preferencesSaved = await store.saveUserPreferences(activityLevel: activity)

            // `saveProfile` zapisuje do `UserDefaults` optymistycznie, zanim
            // cokolwiek pójdzie w sieć, więc arkusz pokazuje nową wartość
            // niezależnie od tego, czy zapis doszedł — a następne `users:me`
            // przywraca starą. Arkusza już nie ma, więc nie ma gdzie tego
            // napisać poza kapsułą.
            if !profileSaved || !preferencesSaved {
                toasts.error(
                    "Nie udało się zapisać profilu",
                    "Zmiany zostały tylko na tym telefonie."
                )
            }
        }
    }

    /// `@AppStorage` oddaje 0 dla klucza, którego nie ma albo który ktoś
    /// wyzerował — a 0 cm wzrostu i rok 0 to nie są wartości, które da się
    /// postawić na kole. Podmieniamy je na te same wartości startowe, których
    /// używa kreator powitalny.
    ///
    /// Zapis przez magazyn, NIE przez `@ProtectedSetting` (7.10.2026, przegląd
    /// gałęzi): poprawka wartości spoza zakresu to nie edycja z ręki — nie
    /// podbija `userEditGeneration`, więc nie unieważnia `users:me` w drodze
    /// i sama nie odpala zapisu na serwer. Klucze = te z deklaracji wyżej.
    private func normaliseStoredValues() {
        let store = SCProtectedSettings.shared
        if !yearRange.contains(yearOfBirth) {
            store.set(Self.defaultYearOfBirth, forKey: "settings.profile.yearOfBirth")
        }
        if !ProfileField.heights.contains(heightCm) {
            store.set(Self.defaultHeightCm, forKey: "settings.profile.heightCm")
        }
        if !ProfileField.weights.contains(weightKg) {
            store.set(Self.defaultWeightKg, forKey: "settings.profile.weightKg")
        }
        if !sexRaw.isEmpty, Sex(rawValue: sexRaw) == nil {
            store.set("", forKey: "settings.profile.sex")
        }
        if ActivityLevel(rawValue: activityLevelRaw) == nil {
            store.set(ActivityLevel.light.rawValue, forKey: "settings.diet.activityLevel")
        }
    }
}
