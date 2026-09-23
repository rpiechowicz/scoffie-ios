import SwiftUI

// Arkusz „Twoje dane” otwierany kartą profilu na górze Ustawień.
//
// Zbiera to, co kreator powitalny zbierał raz i czego potem nie dało się już
// zmienić: imię, rok urodzenia, wzrost, wagę i liczbę treningów. Wszystkie te
// pola już jeżdżą do backendu (`users:profile:update` i
// `users:preferences:update`) — brakowało wyłącznie miejsca w UI.
//
// Świadomie NIE trafiają tu dieta, alergeny ani cel kaloryczny. Tam są
// preferencje jedzeniowe, tu fakty o użytkowniku; arkusz „Dieta i alergeny”
// ma już cztery sekcje i dołożenie do niego czterech pól zrobiłoby z niego
// ścianę kontrolek. Podział idzie za tym, który jest w kluczach
// `settings.profile.*` kontra `settings.diet.*`.
struct ProfileDetailsSheet: View {
    var onClose: () -> Void

    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.toasts) private var toasts
    @Environment(\.colorScheme) private var scheme

    @AppStorage("settings.user.displayName") private var displayName: String = ""
    @AppStorage("settings.user.email") private var email: String = ""
    @AppStorage("settings.user.avatarUrl") private var avatarUrl: String = ""
    @AppStorage("settings.user.avatarColor") private var avatarColor: Int = -1
    /// Ziarno awatara — to samo id, którym posługuje się `MemberAvatar`.
    @AppStorage("auth.userId") private var userId: String = ""
    @AppStorage("settings.profile.yearOfBirth") private var yearOfBirth: Int = Self.defaultYearOfBirth
    @AppStorage("settings.profile.heightCm") private var heightCm: Int = Self.defaultHeightCm
    @AppStorage("settings.profile.weightKg") private var weightKg: Double = Self.defaultWeightKg
    @AppStorage("settings.profile.sex") private var sexRaw: String = ""
    @AppStorage("settings.diet.activityLevel") private var activityLevelRaw: Int = ActivityLevel.light.rawValue

    @FocusState private var focusedField: Field?

    @State private var isConfirmingDeletion = false
    @State private var isDeleting = false
    @State private var deletionError: String?

    // Pola tekstowe NIE są związane wprost z `@AppStorage`. `SessionStore
    // .saveProfile` zapisuje z powrotem do tych samych kluczy
    // (SessionStore.swift:1177), więc debounce'owany zapis wstrzykiwał
    // przyciętą wartość w pole, w którym użytkownik właśnie pisze: po wpisaniu
    // „173” w polu z „178” robiło się „178173”, a 600 ms później clamp
    // zamieniał to na 230 i pole samo się przestawiało. Edycja idzie po
    // draftach, a do `@AppStorage` schodzi dopiero gotowa, przycięta liczba.
    @State private var nameDraft: String = ""
    @State private var heightDraft: String = ""
    @State private var weightDraft: String = ""
    @State private var didSeedDrafts = false
    /// Czy w tym otwarciu arkusza doszło do JAKIEJKOLWIEK edycji. Zapis do
    /// backendu (debounce i ten przy zamknięciu) wychodzi tylko wtedy —
    /// samo otwarcie i zamknięcie arkusza nie może nic wysłać. Wcześniej
    /// `task(id:)` odpalał się też przy pierwszym pokazaniu i po 600 ms
    /// wypychał aktualny stan — jeśli lokalne wartości były akurat domyślne
    /// (świeże logowanie, zanim `users:me` zdążył przywrócić prawdziwe),
    /// nadpisywały w bazie realną sylwetkę.
    @State private var didObserveInitialToken = false
    @State private var didEditThisSession = false

    private enum Field {
        case name
        case height
        case weight
    }

    // Te same wartości startowe co w kreatorze powitalnym — arkusz nie może
    // pokazać innych liczb niż ekran, który je pierwszy zapisał.
    private static let defaultYearOfBirth = 1992
    private static let defaultHeightCm = 178
    private static let defaultWeightKg: Double = 74

    private static let heightRange = 120...230
    private static let weightRange: ClosedRange<Double> = 30...250

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var yearRange: ClosedRange<Int> { 1900...currentYear }

    private var activityLevel: ActivityLevel {
        ActivityLevel(rawValue: activityLevelRaw) ?? .light
    }

    private var sex: Sex? { Sex(rawValue: sexRaw) }

    var body: some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EditorialSheetHeader(eyebrow: "Konto", title: "Twoje dane") {
                        commitAndClose()
                    }

                    Text("Na podstawie tych danych aplikacja podpowiada zapotrzebowanie kaloryczne. Zostają na Twoim koncie — nie trafiają nigdzie dalej.")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    identitySection
                    bodySection
                    activitySection
                    deleteAccountSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            normaliseStoredValues()
            seedDraftsIfNeeded()
        }
        .alert("Usunąć konto?", isPresented: $isConfirmingDeletion) {
            Button("Anuluj", role: .cancel) {}
            Button("Usuń konto", role: .destructive) { deleteAccount() }
        } message: {
            Text("Wypiszemy Cię z gospodarstwa i trwale usuniemy konto razem z Twoim profilem, preferencjami i odhaczonymi posiłkami. Tego nie da się cofnąć.")
        }
        // Pole liczbowe komituje się dopiero, gdy traci focus — dopiero wtedy
        // wpisana liczba jest kompletna i można ją bezpiecznie przyciąć.
        // Wejście w pole czyści draft, żeby pisanie zastępowało starą wartość
        // zamiast dopisywać się do niej.
        .onChange(of: focusedField) { previous, current in
            commit(field: previous)
            if current == .height { heightDraft = "" }
            if current == .weight { weightDraft = "" }
        }
        // Ten sam debounce co w arkuszu diety: każda zmiana kasuje poprzedni
        // zapis i planuje nowy 600 ms później, więc pisanie w polu imienia
        // nie generuje round-tripa na literę. Pierwsze odpalenie to samo
        // pokazanie arkusza (`task(id:)` startuje też bez zmiany id) — nic
        // wtedy nie wysyłamy; każde KOLEJNE to już realna edycja.
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

    // MARK: - Tożsamość

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Profil")

            // Imię jest nagłówkiem, e-mail podpisem — odwrotnie niż wcześniej,
            // gdzie e-mail siedział na górze pogrubiony i czytał się jak tytuł
            // karty, a imię lądowało pod nim w szerokim, pustym polu. Pole
            // zniknęło: imię jest edytowalne w miejscu, a że da się je
            // kliknąć, mówi ołówek i podkreślenie, które zapala się przy
            // wejściu w edycję.
            HStack(alignment: .center, spacing: 14) {
                ProfileAvatar(
                    avatarUrl: avatarUrl.isEmpty ? nil : avatarUrl,
                    displayName: displayName.isEmpty ? "Twoje konto" : displayName,
                    size: 56,
                    colorIndex: avatarColor >= 0 ? avatarColor : nil,
                    seed: userId.isEmpty ? displayName : userId
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        TextField("Twoje imię", text: $nameDraft)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .name)
                            .submitLabel(.done)
                            .font(.system(size: 19, weight: .bold))
                            .tracking(-0.3)
                            .foregroundStyle(Color.scLabel(scheme))
                            .onSubmit { focusedField = nil }
                            .onChange(of: nameDraft) { _, newValue in
                                // Limit serwera (`UpdateProfileDto`, 64) — przycinamy
                                // w polu, żeby stan lokalny = to, co przyjmie backend.
                                if newValue.count > SessionStore.displayNameMaxLength {
                                    nameDraft = String(newValue.prefix(SessionStore.displayNameMaxLength))
                                    return
                                }
                                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                displayName = trimmed
                            }
                            .fixedSize(horizontal: false, vertical: true)

                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(
                                focusedField == .name
                                    ? SCPalette.terracotta
                                    : Color.scFaint(scheme)
                            )
                    }

                    Rectangle()
                        .fill(
                            focusedField == .name
                                ? SCPalette.terracotta
                                : Color.scRule(scheme)
                        )
                        .frame(height: focusedField == .name ? 1.5 : 1)

                    Text(email.isEmpty ? "Brak e-maila" : email)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.middle)
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.smooth(duration: 0.18), value: focusedField == .name)
            }
            .padding(16)
            .background(card)
        }
    }

    // MARK: - Sylwetka

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Sylwetka")

            VStack(alignment: .leading, spacing: 16) {
                // Płeć jako pierwsza: to jedyne pole, które się nie zmienia,
                // a reszta sekcji (rok, wzrost, waga) to liczby aktualizowane
                // co jakiś czas. Naturalna kolejność czytania idzie od stałej
                // do zmiennych.
                sexPicker

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        fieldCaption("Rok urodzenia")
                        Spacer(minLength: 8)
                        Text(ageLabel)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(SCPalette.terracotta)
                    }

                    YearWheelPicker(
                        year: $yearOfBirth,
                        range: yearRange,
                        surface: Color.scChipBg(scheme)
                    )
                }

                HStack(spacing: 10) {
                    measureField(
                        caption: "Wzrost",
                        unit: "cm",
                        draft: $heightDraft,
                        placeholder: String(heightCm),
                        field: .height,
                        allowsDecimal: false
                    )

                    measureField(
                        caption: "Waga",
                        unit: "kg",
                        draft: $weightDraft,
                        placeholder: Self.weightText(weightKg),
                        field: .weight,
                        allowsDecimal: true
                    )
                }

                if let metrics {
                    bmiRow(metrics)
                }

            }
            .padding(18)
            .background(card)
        }
    }

    /// Sylwetka policzona z aktualnie ZAPISANYCH wartości, nie z draftów —
    /// BMI nie ma migać przy każdej wpisanej cyfrze.
    private var metrics: BodyMetrics? {
        BodyMetrics(
            heightCm: heightCm,
            weightKg: weightKg,
            yearOfBirth: yearOfBirth,
            activityRaw: activityLevelRaw,
            sexRaw: sexRaw
        )
    }

    /// BMI z kategorią i policzonym zapotrzebowaniem. Zapotrzebowanie ląduje
    /// tutaj, a nie tylko w arkuszu diety, bo to jedyne miejsce, gdzie widać
    /// wszystkie liczby, z których się bierze.
    private func bmiRow(_ metrics: BodyMetrics) -> some View {
        let category = metrics.bmiCategory

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Self.bmiFormatter.string(from: NSNumber(value: metrics.bmi)) ?? "—")
                        .font(.system(size: 20, weight: .heavy))
                        .tracking(-0.4)
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(scheme))

                    Text("BMI")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.scFaint(scheme))
                }

                Text(category.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(category.accent)
            }

            Rectangle()
                .fill(Color.scRule(scheme))
                .frame(width: 1, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(metrics.maintenanceCalories)")
                        .font(.system(size: 20, weight: .heavy))
                        .tracking(-0.4)
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(scheme))

                    Text("KCAL")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.scFaint(scheme))
                }

                Text("Na utrzymanie wagi")
                    .font(.system(size: 11.5, weight: .semibold))
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

    private static let bmiFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private var ageLabel: String {
        let age = max(currentYear - yearOfBirth, 0)
        return "\(age) \(Self.yearNoun(for: age))"
    }

    /// Polska odmiana „lat” po liczebniku: 1 → „rok”, 2–4 (poza 12–14) →
    /// „lata”, reszta → „lat”.
    private static func yearNoun(for count: Int) -> String {
        let lastTwo = count % 100
        let last = count % 10
        if count == 1 { return "rok" }
        if (2...4).contains(last), !(12...14).contains(lastTwo) { return "lata" }
        return "lat"
    }

    private func measureField(
        caption: String,
        unit: String,
        draft: Binding<String>,
        placeholder: String,
        field: Field,
        allowsDecimal: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldCaption(caption)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField(placeholder, text: draft)
                    .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
                    .focused($focusedField, equals: field)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color.scLabel(scheme))
                    .monospacedDigit()
                    .onChange(of: draft.wrappedValue) { _, newValue in
                        // Numberpad przepuszcza wklejenie — zostawiamy same
                        // cyfry, żeby parsowanie nie zależało od schowka.
                        let sanitised = Self.sanitise(newValue, allowsDecimal: allowsDecimal)
                        if sanitised != newValue {
                            draft.wrappedValue = sanitised
                            return
                        }
                        commitLive(field: field, text: sanitised)
                    }
                    // Wejście w pole czyści je przez `onChange(of: focusedField)`,
                    // ale ponowne stuknięcie w pole JUŻ aktywne nie zmienia
                    // focusu — bez tego limit trzech cyfr po cichu zjadał
                    // wpisywane cyfry i wyglądało to na zawieszone pole.
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            if focusedField == field { draft.wrappedValue = "" }
                        }
                    )

                Text(unit)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(insetField)
        }
    }

    // MARK: - Aktywność

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Aktywność")

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    EditorialSettingsTileIcon(icon: "figure.run", color: SCPalette.terracotta)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Treningi w tygodniu")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.scLabel(scheme))

                        Text("Im więcej ruchu, tym wyższe zapotrzebowanie.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.scMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    ForEach(ActivityLevel.allCases) { level in
                        activityChip(level)
                    }
                }
            }
            .padding(18)
            .background(card)
        }
    }

    private func activityChip(_ level: ActivityLevel) -> some View {
        let isSelected = level == activityLevel

        return Button {
            withAnimation(.smooth(duration: 0.20)) {
                activityLevelRaw = level.rawValue
            }
        } label: {
            VStack(spacing: 6) {
                Text(level.label)
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? .white : Color.scLabel(scheme))

                Text(level.subtitle)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : Color.scMuted(scheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .padding(.horizontal, 4)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [SCPalette.terracotta, SCPalette.terracotta.mix(black: 0.18)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            : AnyShapeStyle(Color.scChipBg(scheme))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.scTileStroke(scheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(level.label) treningów w tygodniu, \(level.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Usunięcie konta

    /// Świadomie na samym dole i świadomie bez ikony w kaflu — to jedyna
    /// nieodwracalna rzecz w tym arkuszu i ma wyglądać inaczej niż wszystko
    /// nad nią. Potwierdzenie w alercie wymienia z nazwy, co zniknie:
    /// „wszystkie dane" nie mówi nikomu nic.
    private var deleteAccountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                focusedField = nil
                isConfirmingDeletion = true
            } label: {
                HStack(spacing: 8) {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.red)
                    } else {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12, weight: .bold))
                    }

                    Text(isDeleting ? "Usuwam konto…" : "Usuń konto")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(-0.1)
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule().fill(Color.red.opacity(scheme == .dark ? 0.14 : 0.10)))
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)

            if let deletionError {
                Text(deletionError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 6)
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
                onClose()
            } else {
                deletionError = store.authError ?? "Nie udało się usunąć konta. Spróbuj ponownie."
                store.authError = nil
            }
        }
    }

    // MARK: - Zapis

    /// Token zmienia się przy każdej edycji pola — `task(id:)` anuluje
    /// zaplanowany zapis i planuje nowy.
    private var profileSyncToken: String {
        "\(displayName)|\(yearOfBirth)|\(heightCm)|\(weightKg)|\(activityLevelRaw)|\(sexRaw)"
    }

    /// Przepisuje zapisane wartości do draftów. Raz, przy pierwszym pokazaniu
    /// arkusza — późniejsze nadpisanie przestawiłoby pole pod palcami.
    private func seedDraftsIfNeeded() {
        guard !didSeedDrafts else { return }
        didSeedDrafts = true
        nameDraft = displayName
        heightDraft = String(heightCm)
        weightDraft = Self.weightText(weightKg)
    }

    /// Domyka edycję pola: parsuje draft, przycina do zakresu i dopiero wtedy
    /// zapisuje do `@AppStorage`. Pusty albo niesparsowalny draft wraca do
    /// ostatniej dobrej wartości, żeby wyjście z pustego pola nie kasowało
    /// wzrostu.
    private func commit(field: Field?) {
        switch field {
        case .name:
            let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                nameDraft = displayName
            } else {
                displayName = trimmed
                nameDraft = trimmed
            }

        // Wartość spoza zakresu jest ODRZUCANA, nie przycinana. „83174" to nie
        // jest waga 250 kg — to literówka, i jedyną uczciwą odpowiedzią jest
        // zostawić to, co było. Przycinanie zamieniało pomyłkę w prawdopodobnie
        // wyglądającą liczbę, którą łatwo przeoczyć.
        case .height:
            let resolved = Int(heightDraft).flatMap { Self.heightRange.contains($0) ? $0 : nil } ?? heightCm
            heightCm = resolved
            heightDraft = String(resolved)

        case .weight:
            let resolved = Self.weightValue(from: weightDraft)
                .flatMap { Self.weightRange.contains($0) ? $0 : nil } ?? weightKg
            weightKg = resolved
            weightDraft = Self.weightText(resolved)

        case .none:
            break
        }
    }

    /// Zapis w locie. Wartość schodzi do `@AppStorage` natychmiast, ale TYLKO
    /// wtedy, gdy wpisana liczba mieści się już w zakresie. Niedokończone „1"
    /// albo „17" nie jest ani zapisywane, ani przycinane — i właśnie dlatego
    /// nic nie przestawia się pod palcami. Wartości spoza zakresu domyka
    /// `commit(field:)` przy zejściu z pola.
    private func commitLive(field: Field, text: String) {
        switch field {
        case .height:
            guard let value = Int(text), Self.heightRange.contains(value) else { return }
            heightCm = value

        case .weight:
            // „83," w trakcie pisania nie parsuje się na liczbę i dobrze —
            // zapis czeka, aż użytkownik dopisze cyfrę po przecinku.
            guard let value = Self.weightValue(from: text),
                  Self.weightRange.contains(value) else { return }
            weightKg = value

        case .name:
            break
        }
    }

    /// Domknięcie wszystkich pól naraz — przed zapisem i przed zamknięciem.
    private func commitAllFields() {
        commit(field: .name)
        commit(field: .height)
        commit(field: .weight)
    }

    /// Dwa round-tripy, bo to dwa różne zasoby: sylwetka idzie przez
    /// `users:profile:update`, a liczba treningów przez
    /// `users:preferences:update` (tam mieszka `activityLevel`). Przenoszenie
    /// jednego pod drugi endpoint tylko po to, żeby mieć jedno wywołanie,
    /// zmieniłoby kontrakt backendu bez żadnego zysku.
    private func pushProfile() async {
        // Wartości są już przycięte przez `commit(field:)`, więc `saveProfile`
        // zapisze do `UserDefaults` dokładnie to, co widać w polu — i nic nie
        // podskoczy pod palcami.
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        await sessionStore.saveProfile(
            displayName: trimmedName.isEmpty ? nil : trimmedName,
            yearOfBirth: yearOfBirth,
            heightCm: heightCm,
            weightKg: weightKg,
            sex: sexRaw.isEmpty ? nil : sexRaw
        )

        await sessionStore.saveUserPreferences(activityLevel: activityLevelRaw)
    }

    /// Zamknięcie arkusza nie może zgubić zmiany wpisanej sekundę wcześniej —
    /// `task(id:)` zostaje anulowany razem z widokiem, więc zapis wychodzi tu
    /// jeszcze raz, bez debounce'u. Ale TYLKO gdy w tym otwarciu cokolwiek
    /// edytowano (`didEditThisSession`) albo domknięcie draftów właśnie coś
    /// zmieniło — otwarcie i zamknięcie arkusza bez edycji nie może wypchnąć
    /// lokalnego stanu do bazy (patrz komentarz przy `didEditThisSession`).
    private func commitAndClose() {
        focusedField = nil
        let tokenBeforeCommit = profileSyncToken
        commitAllFields()
        normaliseStoredValues()
        guard didEditThisSession || profileSyncToken != tokenBeforeCommit else {
            onClose()
            return
        }
        let store = sessionStore
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = yearOfBirth
        let height = heightCm
        let weight = weightKg
        let activity = activityLevelRaw
        let sexValue = sexRaw

        // Kolejka do stałej PRZED zadaniem: `onClose()` leci kilka linijek
        // niżej i środowisko tego arkusza już nie istnieje, gdy `await`
        // wracają.
        let toasts = toasts
        Task { @MainActor in
            let profileSaved = await store.saveProfile(
                displayName: name.isEmpty ? nil : name,
                yearOfBirth: year,
                heightCm: height,
                weightKg: weight,
                sex: sexValue.isEmpty ? nil : sexValue
            )
            let preferencesSaved = await store.saveUserPreferences(activityLevel: activity)

            // Najcichsza awaria w Ustawieniach. `saveProfile` zapisuje do
            // `UserDefaults` optymistycznie, zanim cokolwiek pójdzie w sieć,
            // więc karta profilu pokazuje nowe imię niezależnie od tego, czy
            // zapis doszedł — a następne `users:me` przywraca stare i wygląda
            // to, jakby aplikacja skasowała zmianę. Warstwa socketu nie melduje
            // się w `ConnectivityMonitor`, więc nie zapala się nawet pasek
            // braku sieci. Arkusza już nie ma, więc nie ma gdzie tego napisać
            // poza kapsułą.
            if !profileSaved || !preferencesSaved {
                toasts.error(
                    "Nie udało się zapisać profilu",
                    "Zmiany zostały tylko na tym telefonie."
                )
            }
        }

        onClose()
    }

    /// `@AppStorage` oddaje 0 dla klucza, którego nie ma albo który ktoś
    /// wyzerował — a 0 cm wzrostu i rok 0 to nie są wartości, które można
    /// pokazać w polu. Podmieniamy je na te same wartości startowe, których
    /// używa kreator powitalny.
    private func normaliseStoredValues() {
        if !yearRange.contains(yearOfBirth) { yearOfBirth = Self.defaultYearOfBirth }
        if !Self.heightRange.contains(heightCm) { heightCm = Self.defaultHeightCm }
        if !Self.weightRange.contains(weightKg) { weightKg = Self.defaultWeightKg }
        if !sexRaw.isEmpty, Sex(rawValue: sexRaw) == nil { sexRaw = "" }
        if ActivityLevel(rawValue: activityLevelRaw) == nil { activityLevelRaw = ActivityLevel.light.rawValue }
    }

    // MARK: - Płeć

    /// Płeć wchodzi wyłącznie do wzoru na przemianę materii — i tak to
    /// opisujemy. Trzeci stan („nie podano") nie jest osobnym przyciskiem:
    /// wychodzi się z niego stukając wybraną opcję, a ponowne stuknięcie
    /// w zaznaczoną odznacza ją z powrotem.
    private var sexPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldCaption("Płeć")

            HStack(spacing: 8) {
                ForEach(Sex.allCases) { candidate in
                    sexChip(candidate)
                }
            }

        }
    }

    private func sexChip(_ candidate: Sex) -> some View {
        let isSelected = sex == candidate

        return Button {
            withAnimation(.smooth(duration: 0.18)) {
                sexRaw = isSelected ? "" : candidate.rawValue
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: candidate.icon)
                    .font(.system(size: 12, weight: .semibold))

                Text(candidate.title)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.1)
            }
            .foregroundStyle(isSelected ? .white : Color.scLabel(scheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [SCPalette.terracotta, SCPalette.terracotta.mix(black: 0.18)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            : AnyShapeStyle(Color.scChipBg(scheme))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.scTileStroke(scheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(candidate.title)
        .accessibilityValue(isSelected ? "Wybrane" : "Niewybrane")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Liczby w polach

    /// Przepuszcza cyfry i jeden separator dziesiętny. Przecinek i kropka są
    /// wymienne, bo klawiatura `.decimalPad` podstawia separator zgodny
    /// z ustawieniami systemu, a użytkownik i tak może mieć nawyk drugiego.
    static func sanitise(_ raw: String, allowsDecimal: Bool) -> String {
        guard allowsDecimal else {
            return String(raw.filter(\.isNumber).prefix(3))
        }

        var whole = ""
        var fraction = ""
        var seenSeparator = false

        for character in raw {
            if character.isNumber {
                if seenSeparator {
                    if fraction.count < 1 { fraction.append(character) }
                } else if whole.count < 3 {
                    whole.append(character)
                }
            } else if character == "," || character == ".", !seenSeparator, !whole.isEmpty {
                seenSeparator = true
            }
        }

        if !seenSeparator { return whole }
        return whole + "," + fraction
    }

    static func weightValue(from text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    /// Bez zbędnego „,0" — 83 kg zostaje jako „83", 83,5 jako „83,5".
    static func weightText(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: - Chassis

    private func fieldCaption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Color.scFaint(scheme))
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.scTileBg(scheme))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
    }

    private var insetField: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.scChipBg(scheme))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
    }
}
