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

    /// Wiersz, którego wybór stoi teraz w małym arkuszu (`nil` = zamknięty).
    @State private var picking: ProfileField?
    /// Co pokazuje mały arkusz. Zostaje przy ostatnim wierszu, gdy `picking`
    /// wraca do `nil` — inaczej arkusz zjeżdżałby w dół pusty.
    @State private var pickerField: ProfileField = .year
    /// Mały arkusz jest na ekranie — od otwarcia do KOŃCA zjazdu (`onDismiss`),
    /// dłużej niż `picking`, które gaśnie już na początku zjazdu.
    @State private var pickerOnScreen = false
    /// Okno („Imię”, „Usunąć konto?”) czekające, aż mały arkusz zjedzie —
    /// alert z widoku, który właśnie prezentuje arkusz, system odrzuca, a ołówek
    /// i „Usuń konto” da się stuknąć przy otwartym wyborze.
    @State private var pendingAlert: PendingAlert?

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
    @State private var didEditThisSession = false
    /// W tym otwarciu wybrano „Nie podaję” — zapis kasuje płeć na serwerze
    /// (`saveProfile(clearSex:)`), zamiast ją pomijać.
    @State private var clearsSex = false

    // Te same wartości startowe co w kreatorze powitalnym — arkusz nie może
    // pokazać innych liczb niż ekran, który je pierwszy zapisał.
    private static let defaultYearOfBirth = BodyMetrics.defaultYearOfBirth
    private static let defaultHeightCm = BodyMetrics.defaultHeightCm
    private static let defaultWeightKg = BodyMetrics.defaultWeightKg

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var yearRange: ClosedRange<Int> { 1900...currentYear }

    private var sex: Sex? { Sex(rawValue: sexRaw) }

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
        .sheet(isPresented: pickerPresented, onDismiss: { pickerDidDismiss() }) {
            ProfileFieldPickerSheet(
                field: pickerField,
                sexRaw: $sexRaw,
                yearOfBirth: $yearOfBirth,
                heightCm: $heightCm,
                weightKg: $weightKg,
                yearRange: yearRange,
                onClose: { picking = nil }
            )
            // Jedna trzecia ekranu, jak koło godzin w „Posiłkach w planie”.
            .presentationDetents([.fraction(1.0 / 3.0)])
            // Bez przyciemnienia i z dotykiem pod spodem: wynik na górze
            // zmienia się na oczach, a stuknięcie w inny wiersz podmienia
            // wybór w tym samym arkuszu.
            .presentationBackgroundInteraction(.enabled(upThrough: .fraction(1.0 / 3.0)))
            .dashboardLiquidSheet(cornerRadius: 26)
        }
        .alert("Imię", isPresented: $isEditingName) {
            TextField("Twoje imię", text: $nameDraft)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            Button("Anuluj", role: .cancel) {}
            Button("Zapisz") { saveName() }
                .disabled(trimmedNameDraft.isEmpty)
        } message: {
            Text("Widzą je domownicy.")
        }
        // Limit serwera (`UpdateProfileDto`, 64 punkty kodowe) — przycinamy
        // w polu, żeby stan lokalny = to, co przyjmie backend.
        .onChange(of: nameDraft) { _, newValue in
            let limited = SessionStore.limitedDisplayName(newValue)
            if limited != newValue {
                nameDraft = limited
            }
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
            guard didObserveInitialToken else {
                didObserveInitialToken = true
                return
            }
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

                resultCard

                EditorialSheetSectionLabel(title: "Sylwetka")
                    .padding(.top, 22)
                bodyCard

                EditorialSheetSectionLabel(title: "Treningi w tygodniu")
                    .padding(.top, 22)
                activityCard

                Text("Z tych danych liczymy zapotrzebowanie. Zostają na Twoim koncie.")
                    .font(.sc(size: 12.5))
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .padding(.top, 10)

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
        HStack(spacing: 12) {
            avatar(size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(nameTitle)
                    .font(.sc(size: 17, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)

                if let emailText {
                    Text(emailText)
                        .font(.sc(size: 13))
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            renameButton
        }
    }

    private var trimmedNameDraft: String {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startEditingName() {
        nameDraft = displayName
        present(.rename)
    }

    /// Okno od razu — albo, gdy na ekranie stoi mały arkusz z wyborem, dopiero
    /// po jego zjeździe (`pickerDidDismiss`).
    private func present(_ alert: PendingAlert) {
        guard pickerOnScreen else {
            show(alert)
            return
        }
        pendingAlert = alert
        picking = nil
    }

    private func show(_ alert: PendingAlert) {
        switch alert {
        case .rename:        isEditingName = true
        case .deleteAccount: isConfirmingDeletion = true
        }
    }

    private func pickerDidDismiss() {
        // Wiersz stuknięty w trakcie zjazdu otwiera arkusz od nowa — wtedy
        // dalej jest na ekranie.
        pickerOnScreen = picking != nil
        guard !pickerOnScreen, let alert = pendingAlert else { return }
        pendingAlert = nil
        show(alert)
    }

    /// Puste imię się nie zapisuje — „Zapisz” jest wtedy wyłączone.
    private func saveName() {
        let trimmed = trimmedNameDraft
        guard !trimmed.isEmpty else { return }
        displayName = trimmed
    }

    // MARK: - Wynik

    /// Sylwetka policzona z zapisanych wartości. Zawsze jest (`BodyMetrics.preview`).
    private var metrics: BodyMetrics {
        BodyMetrics.preview(
            heightCm: heightCm,
            weightKg: weightKg,
            yearOfBirth: yearOfBirth,
            activityRaw: activityLevelRaw,
            sexRaw: sexRaw
        )
    }

    /// Kcal na utrzymanie i BMI na skali ocen — pierwsza rzecz w arkuszu, bo
    /// po to są te dane. Zmiana wartości poniżej roluje cyfry (`numericText`,
    /// krzywa `SCMotion.textRoll`), a znacznik BMI jedzie po skali.
    private var resultCard: some View {
        let metrics = self.metrics
        let kcal = metrics.maintenanceCalories
        let bmi = metrics.bmi
        let category = metrics.bmiCategory
        let bmiText = BodyMetricsSummaryRow.bmiFormatter.string(from: NSNumber(value: bmi)) ?? "—"

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.sc(size: 11, weight: .bold))
                    .foregroundStyle(SCMacroPalette.calories)

                Text("NA UTRZYMANIE WAGI")
                    .font(.sc(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.scFaint(scheme))
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(kcal)")
                    .font(.sc(size: 38, weight: .heavy))
                    .tracking(-1.2)
                    .foregroundStyle(Color.scLabel(scheme))
                    .contentTransition(.numericText(value: Double(kcal)))

                Text("kcal")
                    .font(.sc(size: 15, weight: .bold))
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .padding(.top, 2)

            Rectangle()
                .fill(Color.scRule(scheme))
                .frame(height: 1)
                .padding(.top, 10)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("BMI")
                    .font(.sc(size: 14))
                    .foregroundStyle(Color.scMuted(scheme))

                Text(bmiText)
                    .font(.sc(size: 16, weight: .bold))
                    .foregroundStyle(Color.scLabel(scheme))
                    .contentTransition(.numericText(value: bmi))

                Spacer(minLength: 8)

                Text(category.title)
                    .font(.sc(size: 13.5, weight: .bold))
                    .foregroundStyle(category.accent)
                    .contentTransition(.opacity)
            }
            .padding(.top, 11)

            BMIScale(bmi: bmi, accent: category.accent)
                .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
        .animation(SCMotion.textRoll, value: kcal)
        .animation(SCMotion.textRoll, value: bmiText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Na utrzymanie wagi \(kcal) kilokalorii dziennie. BMI \(bmiText), \(category.title).")
    }

    // MARK: - Sylwetka

    private var bodyCard: some View {
        VStack(spacing: 0) {
            ForEach(ProfileField.allCases) { field in
                EditorialSettingsRow(
                    icon: field.icon,
                    iconColor: field.color,
                    title: field.title,
                    isLast: field == .weight,
                    action: { pick(field) }
                ) {
                    rowValue(field)
                }
                .accessibilityValue(value(for: field))
                .accessibilityHint("Otwiera wybór")
            }
        }
        .background(card)
    }

    /// Wartość wiersza w terakocie, dopóki jej wybór stoi w małym arkuszu.
    private func rowValue(_ field: ProfileField) -> some View {
        let isActive = picking == field
        let text = value(for: field)

        return HStack(spacing: 6) {
            Text(text)
                .font(.sc(size: 15))
                .monospacedDigit()
                .foregroundStyle(isActive ? SCPalette.terracotta : Color.scMuted(scheme))
                .lineLimit(1)
                .contentTransition(.numericText())

            Image(systemName: "chevron.up.chevron.down")
                .font(.sc(size: 11, weight: .bold))
                .foregroundStyle(isActive ? SCPalette.terracotta : Color.scFaint(scheme))
        }
        .animation(SCMotion.textRoll, value: text)
        .animation(.smooth(duration: 0.2), value: isActive)
    }

    private func value(for field: ProfileField) -> String {
        switch field {
        case .sex:
            return sex?.title ?? "Nie podaję"
        case .year:
            return "\(yearOfBirth) · \(BodyMetricsSummaryRow.ageLabel(max(currentYear - yearOfBirth, 0)))"
        case .height:
            return "\(heightCm) cm"
        case .weight:
            return "\(Self.weightText(weightKg)) kg"
        }
    }

    /// Ten sam wiersz zamyka arkusz, inny podmienia jego wybór.
    private func pick(_ field: ProfileField) {
        if picking == field {
            picking = nil
        } else {
            pickerField = field
            picking = field
            pickerOnScreen = true
            // Nowy wybór odwołuje okno czekające na zjazd poprzedniego.
            pendingAlert = nil
        }
    }

    private var pickerPresented: Binding<Bool> {
        Binding(
            get: { picking != nil },
            set: { isPresented in
                if !isPresented { picking = nil }
            }
        )
    }

    // MARK: - Treningi

    private var activityCard: some View {
        SCIconTilePicker(choices: Self.activityChoices, selection: activityLevel)
            .padding(10)
            .background(card)
    }

    private var activityLevel: Binding<ActivityLevel> {
        Binding(
            get: { ActivityLevel(rawValue: activityLevelRaw) ?? .light },
            set: { activityLevelRaw = $0.rawValue }
        )
    }

    private static let activityChoices: [SCIconTileChoice<ActivityLevel>] = ActivityLevel.allCases.map { level in
        SCIconTileChoice(
            value: level,
            icon: level.tileIcon,
            title: level.label,
            color: level.effortColor,
            accessibilityLabel: "\(level.label) treningów w tygodniu, \(level.subtitle)"
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
    private func normaliseStoredValues() {
        if !yearRange.contains(yearOfBirth) { yearOfBirth = Self.defaultYearOfBirth }
        if !ProfileField.heights.contains(heightCm) { heightCm = Self.defaultHeightCm }
        if !ProfileField.weights.contains(weightKg) { weightKg = Self.defaultWeightKg }
        if !sexRaw.isEmpty, Sex(rawValue: sexRaw) == nil { sexRaw = "" }
        if ActivityLevel(rawValue: activityLevelRaw) == nil { activityLevelRaw = ActivityLevel.light.rawValue }
    }

    /// Bez zbędnego „,0" — 83 kg zostaje jako „83", 83,5 jako „83,5".
    static func weightText(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.scTileBg(scheme))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
    }
}

// MARK: - Wiersze Sylwetki

/// Wiersz Sylwetki — jego wybór otwiera mały arkusz (`ProfileFieldPickerSheet`).
private enum ProfileField: String, CaseIterable, Identifiable {
    case sex
    case year
    case height
    case weight

    var id: String { rawValue }

    /// Zakresy kół — te same, które `BodyMetrics` uznaje za sensowne.
    static let heights = 120...230
    static let kilograms = 30...250
    static let weights: ClosedRange<Double> = 30...250

    var title: String {
        switch self {
        case .sex:    return "Płeć"
        case .year:   return "Rok urodzenia"
        case .height: return "Wzrost"
        case .weight: return "Waga"
        }
    }

    var icon: String {
        switch self {
        case .sex:    return "figure.dress.line.vertical.figure"
        case .year:   return "calendar"
        case .height: return "ruler.fill"
        case .weight: return "scalemass.fill"
        }
    }

    /// Każdy wiersz w SWOIM kolorze, jak lista Ustawień.
    var color: Color {
        switch self {
        case .sex:    return SCPalette.indigo
        case .year:   return SCPalette.teal
        case .height: return SCPalette.sage
        case .weight: return SCPalette.rose
        }
    }
}

// MARK: - Mały arkusz z wyborem

/// Wybór jednej wartości „Twoich danych” na 1/3 ekranu — jak koło godzin
/// w „Posiłkach w planie” (`MealTimeEditorSheet`). Wartość zapisuje się od
/// razu (koło — gdy stanie), więc nie ma czego zatwierdzać: zamyka krzyżyk,
/// przeciągnięcie w dół albo ponowne stuknięcie w wiersz. Koło stoi we własnym
/// arkuszu, nie w liście: przejmuje pionowe przeciągnięcia i w przewijanej
/// treści zjadałoby przewijanie.
private struct ProfileFieldPickerSheet: View {
    let field: ProfileField
    @Binding var sexRaw: String
    @Binding var yearOfBirth: Int
    @Binding var heightCm: Int
    @Binding var weightKg: Double
    let yearRange: ClosedRange<Int>
    let onClose: () -> Void

    @Environment(\.colorScheme) private var scheme

    /// Płeć jako kafle — z trzecią opcją „Nie podaję” (wcześniej jedyną drogą
    /// było ponowne stuknięcie wybranej płci). Wszystkie w terakocie: płeć
    /// nie ma skali, którą mógłby nieść kolor.
    private static let sexChoices: [SCIconTileChoice<String>] = [
        SCIconTileChoice(value: Sex.female.rawValue, icon: Sex.female.icon, title: Sex.female.title, color: SCPalette.terracotta),
        SCIconTileChoice(value: Sex.male.rawValue, icon: Sex.male.icon, title: Sex.male.title, color: SCPalette.terracotta),
        SCIconTileChoice(value: "", icon: "eye.slash", title: "Nie podaję", color: SCPalette.terracotta)
    ]

    var body: some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                EditorialSheetHeader(
                    eyebrow: "Sylwetka",
                    title: field.title,
                    icon: field.icon,
                    accent: field.color,
                    compact: true,
                    onClose: onClose
                )
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 2)

                // Inny wiersz = inny wybór w tym samym arkuszu: stary gaśnie,
                // nowy wchodzi w JEGO miejsce (`ZStack` — w `VStack` przez chwilę
                // stałyby oba jeden pod drugim).
                ZStack {
                    picker
                        .id(field)
                        .transition(.opacity)
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .animation(.smooth(duration: 0.22), value: field)
    }

    @ViewBuilder
    private var picker: some View {
        switch field {
        case .sex:
            SCIconTilePicker(choices: Self.sexChoices, selection: $sexRaw)

        case .year:
            wheel([
                SCWheelColumn(
                    titles: yearRange.map { String($0) },
                    selection: Binding(
                        get: { yearOfBirth - yearRange.lowerBound },
                        set: { yearOfBirth = yearRange.lowerBound + $0 }
                    ),
                    width: 120,
                    accessibilityLabel: "Rok urodzenia"
                )
            ])

        case .height:
            wheel([
                SCWheelColumn(
                    titles: ProfileField.heights.map { String($0) },
                    selection: Binding(
                        get: { heightCm - ProfileField.heights.lowerBound },
                        set: { heightCm = ProfileField.heights.lowerBound + $0 }
                    ),
                    width: 84,
                    alignment: .right,
                    accessibilityLabel: "Wzrost w centymetrach"
                ),
                SCWheelColumn(titles: ["cm"], selection: nil, width: 52, alignment: .left, accessibilityLabel: "centymetry")
            ])

        case .weight:
            wheel([
                SCWheelColumn(
                    titles: ProfileField.kilograms.map { String($0) },
                    selection: kilogramsIndex,
                    width: 76,
                    alignment: .right,
                    accessibilityLabel: "Waga, kilogramy"
                ),
                SCWheelColumn(
                    titles: (0...9).map { ",\($0)" },
                    selection: tenthsIndex,
                    width: 52,
                    alignment: .left,
                    accessibilityLabel: "Waga, dziesiąte części kilograma"
                ),
                SCWheelColumn(titles: ["kg"], selection: nil, width: 48, alignment: .left, accessibilityLabel: "kilogramy")
            ])
        }
    }

    private func wheel(_ columns: [SCWheelColumn]) -> some View {
        SCWheelPicker(columns: columns, textColor: UIColor(Color.scLabel(scheme)))
            .frame(maxWidth: .infinity)
            // Niższe niż naturalne 216 pt, żeby zmieścić się w trzeciej
            // części ekranu — jak koło godzin; na małych telefonach 100.
            .frame(minHeight: 100, maxHeight: 160)
    }

    /// Waga w dziesiątych częściach kilograma — jedna liczba całkowita,
    /// bez szumu `Double` przy dzieleniu na dwa koła.
    private var weightTenths: Int {
        Int((weightKg * 10).rounded())
    }

    private var kilogramsIndex: Binding<Int> {
        Binding(
            get: { weightTenths / 10 - ProfileField.kilograms.lowerBound },
            set: { setWeight(kilograms: ProfileField.kilograms.lowerBound + $0, tenths: weightTenths % 10) }
        )
    }

    private var tenthsIndex: Binding<Int> {
        Binding(
            get: { weightTenths % 10 },
            set: { setWeight(kilograms: weightTenths / 10, tenths: $0) }
        )
    }

    /// 250 kg to górna granica — dziesiąte wracają wtedy do zera, a ich koło
    /// dojeżdża za nimi (`SCWheelPicker.updateUIView`).
    private func setWeight(kilograms: Int, tenths: Int) {
        let total = min(kilograms * 10 + tenths, ProfileField.kilograms.upperBound * 10)
        weightKg = Double(total) / 10
    }
}

// MARK: - Skala BMI

/// Skala BMI pod wynikiem: cztery odcinki w kolorach ocen (progi WHO 18,5 · 25
/// · 30 na skali 15–35) i znacznik, który przy zmianie jedzie sprężyną.
private struct BMIScale: View {
    let bmi: Double
    let accent: Color

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let lower = 15.0
    private static let upper = 35.0
    private static let gap: CGFloat = 3
    private static let marker: CGFloat = 16
    /// Górna granica odcinka i kolor oceny — te same co `BMICategory.accent`.
    private static let bands: [(upper: Double, color: Color)] = [
        (18.5, SCPalette.butter),
        (25, SCPalette.sage),
        (30, SCPalette.butter),
        (35, SCPalette.terracotta)
    ]
    private static let ticks: [Double] = [18.5, 25, 30]

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let width = proxy.size.width

                ZStack(alignment: .leading) {
                    HStack(spacing: Self.gap) {
                        ForEach(Array(Self.bands.enumerated()), id: \.offset) { index, band in
                            Capsule()
                                .fill(band.color.opacity(scheme == .dark ? 0.36 : 0.3))
                                .frame(width: segmentWidth(index, total: width), height: 8)
                        }
                    }

                    Circle()
                        .fill(Color.scPageBase(scheme))
                        .overlay(Circle().strokeBorder(accent, lineWidth: 3.5))
                        .frame(width: Self.marker, height: Self.marker)
                        .shadow(color: .black.opacity(0.16), radius: 3, x: 0, y: 1)
                        .offset(x: Self.fraction(bmi) * width - Self.marker / 2)
                }
                .frame(width: width, height: Self.marker)
            }
            .frame(height: Self.marker)

            GeometryReader { proxy in
                ForEach(Self.ticks, id: \.self) { tick in
                    Text(Self.tickLabel(tick))
                        .font(.sc(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(Color.scFaint(scheme))
                        .fixedSize()
                        .position(x: Self.fraction(tick) * proxy.size.width, y: 7)
                }
            }
            .frame(height: 14)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.72),
            value: bmi
        )
        .accessibilityHidden(true)
    }

    private func segmentWidth(_ index: Int, total: CGFloat) -> CGFloat {
        let start = index == 0 ? Self.lower : Self.bands[index - 1].upper
        let share = (Self.bands[index].upper - start) / (Self.upper - Self.lower)
        let available = max(0, total - Self.gap * CGFloat(Self.bands.count - 1))
        return available * CGFloat(share)
    }

    private static func fraction(_ value: Double) -> CGFloat {
        CGFloat(min(max((value - lower) / (upper - lower), 0), 1))
    }

    private static func tickLabel(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Poziomy treningów

private extension ActivityLevel {
    var tileIcon: String {
        switch self {
        case .sedentary:  return "sofa.fill"
        case .light:      return "figure.walk"
        case .active:     return "figure.run"
        case .veryActive: return "figure.highintensity.intervaltraining"
        }
    }

    /// Kolor wysiłku — „cieplej” z każdym poziomem: indygo, szałwia,
    /// terakota, czerwień (ember z palety toastów — jedyna czerwień palety).
    var effortColor: Color {
        switch self {
        case .sedentary:  return SCPalette.indigo
        case .light:      return SCPalette.sage
        case .active:     return SCPalette.terracotta
        case .veryActive: return SCPalette.Toast.ember
        }
    }
}

/// BMI z kategorią i zapotrzebowaniem na utrzymanie wagi — Ustawienia →
/// „Twoje dane” i pierwszy krok kreatora (od 24.09.2026 wspólny: kreator
/// pyta o te same liczby i pokazuje od razu, do czego posłużą).
struct BodyMetricsSummaryRow: View {
    let metrics: BodyMetrics

    @Environment(\.colorScheme) private var scheme

    /// BMI z kategorią i policzonym zapotrzebowaniem. Zapotrzebowanie ląduje
    /// tutaj, a nie tylko w arkuszu diety, bo to jedyne miejsce, gdzie widać
    /// wszystkie liczby, z których się bierze.
    var body: some View {
        let category = metrics.bmiCategory

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Self.bmiFormatter.string(from: NSNumber(value: metrics.bmi)) ?? "—")
                        .font(.sc(size: 20, weight: .heavy))
                        .tracking(-0.4)
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(scheme))

                    Text("BMI")
                        .font(.sc(size: 10.5, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.scFaint(scheme))
                }

                Text(category.title)
                    .font(.sc(size: 11.5, weight: .semibold))
                    .foregroundStyle(category.accent)
            }

            Rectangle()
                .fill(Color.scRule(scheme))
                .frame(width: 1, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(metrics.maintenanceCalories)")
                        .font(.sc(size: 20, weight: .heavy))
                        .tracking(-0.4)
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(scheme))

                    Text("KCAL")
                        .font(.sc(size: 10.5, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.scFaint(scheme))
                }

                Text("Na utrzymanie wagi")
                    .font(.sc(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.scMuted(scheme))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.scChipBg(scheme))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("BMI \(Self.bmiFormatter.string(from: NSNumber(value: metrics.bmi)) ?? ""), \(category.title). Na utrzymanie wagi \(metrics.maintenanceCalories) kilokalorii dziennie.")
    }

    static let bmiFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()


    /// „34 lata” — wiek z polską odmianą „lat” po liczebniku: 1 → „rok”,
    /// 2–4 (poza 12–14) → „lata”, reszta → „lat”.
    static func ageLabel(_ age: Int) -> String {
        let lastTwo = age % 100
        let last = age % 10
        if age == 1 { return "1 rok" }
        if (2...4).contains(last), !(12...14).contains(lastTwo) { return "\(age) lata" }
        return "\(age) lat"
    }
}
