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
    @Environment(\.colorScheme) private var scheme

    @AppStorage("settings.user.displayName") private var displayName: String = ""
    @AppStorage("settings.user.email") private var email: String = ""
    @AppStorage("settings.user.avatarUrl") private var avatarUrl: String = ""
    @AppStorage("settings.profile.yearOfBirth") private var yearOfBirth: Int = Self.defaultYearOfBirth
    @AppStorage("settings.profile.heightCm") private var heightCm: Int = Self.defaultHeightCm
    @AppStorage("settings.profile.weightKg") private var weightKg: Int = Self.defaultWeightKg
    @AppStorage("settings.diet.activityLevel") private var activityLevelRaw: Int = ActivityLevel.light.rawValue

    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case height
        case weight
    }

    // Te same wartości startowe co w kreatorze powitalnym — arkusz nie może
    // pokazać innych liczb niż ekran, który je pierwszy zapisał.
    private static let defaultYearOfBirth = 1992
    private static let defaultHeightCm = 178
    private static let defaultWeightKg = 74

    private static let heightRange = 120...230
    private static let weightRange = 30...250

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var yearRange: ClosedRange<Int> { 1900...currentYear }

    private var activityLevel: ActivityLevel {
        ActivityLevel(rawValue: activityLevelRaw) ?? .light
    }

    var body: some View {
        ZStack {
            WMPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EditorialSheetHeader(eyebrow: "Konto", title: "Twoje dane") {
                        commitAndClose()
                    }

                    Text("Na podstawie tych danych aplikacja podpowiada zapotrzebowanie kaloryczne. Zostają na Twoim koncie — nie trafiają nigdzie dalej.")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    identitySection
                    bodySection
                    activitySection
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear(perform: normaliseStoredValues)
        // Ten sam debounce co w arkuszu diety: każda zmiana kasuje poprzedni
        // zapis i planuje nowy 600 ms później, więc pisanie w polu imienia
        // nie generuje round-tripa na literę.
        .task(id: profileSyncToken) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await pushProfile()
        }
    }

    // MARK: - Tożsamość

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Profil")

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ProfileAvatar(
                        avatarUrl: avatarUrl.isEmpty ? nil : avatarUrl,
                        displayName: displayName.isEmpty ? "Twoje konto" : displayName,
                        size: 64
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(email.isEmpty ? "Brak e-maila" : email)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Color.wmLabel(scheme))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(avatarHint)
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundStyle(Color.wmFaint(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    fieldCaption("Imię")

                    HStack(spacing: 12) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.wmMuted(scheme))

                        TextField("Np. Rafał", text: $displayName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .name)
                            .submitLabel(.done)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.wmLabel(scheme))
                            .onSubmit { focusedField = nil }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(insetField)
                }
            }
            .padding(18)
            .background(card)
        }
    }

    /// E-mail i zdjęcie przychodzą od dostawcy logowania i nie da się ich tu
    /// zmienić. Apple w ogóle nie oddaje zdjęcia profilowego, więc dla kont
    /// Apple zawsze zostają inicjały — mówimy o tym wprost, zamiast dawać
    /// przycisk „zmień”, który nie miałby czego zrobić.
    private var avatarHint: String {
        avatarUrl.isEmpty
            ? "Zdjęcie i e-mail pochodzą z konta, którym się logujesz."
            : "Zdjęcie i e-mail pochodzą z konta Google."
    }

    // MARK: - Sylwetka

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Sylwetka")

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        fieldCaption("Rok urodzenia")
                        Spacer(minLength: 8)
                        Text(ageLabel)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(WMPalette.terracotta)
                    }

                    YearWheelPicker(
                        year: $yearOfBirth,
                        range: yearRange,
                        surface: Color.wmInsetSurface(scheme)
                    )
                }

                HStack(spacing: 10) {
                    measureField(
                        caption: "Wzrost",
                        unit: "cm",
                        value: $heightCm,
                        placeholder: "178",
                        field: .height
                    )

                    measureField(
                        caption: "Waga",
                        unit: "kg",
                        value: $weightKg,
                        placeholder: "74",
                        field: .weight
                    )
                }
            }
            .padding(18)
            .background(card)
        }
    }

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
        value: Binding<Int>,
        placeholder: String,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldCaption(caption)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField(placeholder, value: value, format: .number)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: field)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color.wmLabel(scheme))
                    .monospacedDigit()

                Text(unit)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.wmMuted(scheme))
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
                    EditorialSettingsTileIcon(icon: "figure.run", color: WMPalette.terracotta)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Treningi w tygodniu")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.wmLabel(scheme))

                        Text("Im więcej ruchu, tym wyższe zapotrzebowanie.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.wmMuted(scheme))
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
                    .foregroundStyle(isSelected ? .white : Color.wmLabel(scheme))

                Text(level.subtitle)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : Color.wmMuted(scheme))
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
                                    colors: [WMPalette.terracotta, WMPalette.terracotta.mix(black: 0.18)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            : AnyShapeStyle(Color.wmChipBg(scheme))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.wmTileStroke(scheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(level.label) treningów w tygodniu, \(level.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Zapis

    /// Token zmienia się przy każdej edycji pola — `task(id:)` anuluje
    /// zaplanowany zapis i planuje nowy.
    private var profileSyncToken: String {
        "\(displayName)|\(yearOfBirth)|\(heightCm)|\(weightKg)|\(activityLevelRaw)"
    }

    /// Dwa round-tripy, bo to dwa różne zasoby: sylwetka idzie przez
    /// `users:profile:update`, a liczba treningów przez
    /// `users:preferences:update` (tam mieszka `activityLevel`). Przenoszenie
    /// jednego pod drugi endpoint tylko po to, żeby mieć jedno wywołanie,
    /// zmieniłoby kontrakt backendu bez żadnego zysku.
    private func pushProfile() async {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        await sessionStore.saveProfile(
            displayName: trimmedName.isEmpty ? nil : trimmedName,
            yearOfBirth: clamped(yearOfBirth, to: yearRange),
            heightCm: clamped(heightCm, to: Self.heightRange),
            weightKg: clamped(weightKg, to: Self.weightRange)
        )

        await sessionStore.saveUserPreferences(activityLevel: activityLevelRaw)
    }

    /// Zamknięcie arkusza nie może zgubić zmiany wpisanej sekundę wcześniej —
    /// `task(id:)` zostaje anulowany razem z widokiem, więc zapis wychodzi tu
    /// jeszcze raz, bez debounce'u.
    private func commitAndClose() {
        normaliseStoredValues()
        let store = sessionStore
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = clamped(yearOfBirth, to: yearRange)
        let height = clamped(heightCm, to: Self.heightRange)
        let weight = clamped(weightKg, to: Self.weightRange)
        let activity = activityLevelRaw

        Task { @MainActor in
            await store.saveProfile(
                displayName: name.isEmpty ? nil : name,
                yearOfBirth: year,
                heightCm: height,
                weightKg: weight
            )
            await store.saveUserPreferences(activityLevel: activity)
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
        if ActivityLevel(rawValue: activityLevelRaw) == nil { activityLevelRaw = ActivityLevel.light.rawValue }
    }

    private func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: - Chassis

    private func fieldCaption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Color.wmFaint(scheme))
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.wmTileBg(scheme))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
            )
    }

    private var insetField: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.wmInsetSurface(scheme))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
            )
    }
}
