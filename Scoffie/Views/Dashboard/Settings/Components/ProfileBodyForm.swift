import Observation
import SwiftUI

// Treść „Twoich danych” — JEDNA dla arkusza Ustawień (`ProfileDetailsSheet`)
// i pierwszego kroku kreatora (`WelcomeProfileStep`).
//
// 7.10.2026 (Rafał: „zrób na onboarding user te nowe widoki z ustawień…
// uspójnij to”): kreator miał własną kopię sylwetki — pola tekstowe wzrostu
// i wagi, poziome koło lat, chipy płci i treningów — a Ustawienia od 6.10.2026
// stały na wyniku, wierszach z wyborem w arkuszu na 1/3 i kaflach treningów.
// Teraz oba miejsca stoją na tych samych klockach i różnią się tylko tym, kto
// trzyma wartości i kiedy je zapisuje: arkusz — `@ProtectedSetting` i zapis
// z debounce, kreator — `@State` i zapis przy „Dalej”.

// MARK: - Wiersze Sylwetki

/// Wiersz Sylwetki — jego wybór otwiera mały arkusz (`ProfileFieldPickerSheet`).
enum ProfileField: String, CaseIterable, Identifiable {
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

// MARK: - Mały arkusz i okna

/// Stan małego arkusza z wyborem — JEDEN mechanizm dla „Twoich danych”
/// w Ustawieniach i kroku 1 kreatora (7.10.2026, przegląd: kreator sprawdzał
/// tylko `picking`, a ono gaśnie już na POCZĄTKU zjazdu — ołówek stuknięty
/// w ciągu ~0,3 s po krzyżyku chciał pokazać okno nad zjeżdżającym arkuszem,
/// system go nie pokazywał, a `isPresented` mogło zostać `true` i okno nie
/// otwierało się już wcale).
///
/// Okno („Imię”, „Usunąć konto?”) idzie przez `present(_:)`: od razu, gdy
/// arkusza nie ma, a gdy jest na ekranie (od otwarcia do KOŃCA zjazdu) —
/// arkusz zjeżdża, a okno pokazuje się w `onDismiss`. Nowy wybór odwołuje
/// okno czekające na zjazd poprzedniego. Alertu z widoku, który prezentuje
/// arkusz, system nie pokaże.
@Observable
final class ProfilePickerGate {
    /// Wiersz, którego wybór stoi teraz w małym arkuszu (`nil` = zamknięty).
    var picking: ProfileField?
    /// Co pokazuje arkusz, gdy `picking` już zgasło (zjazd) — inaczej
    /// zjeżdżałby pusty.
    private(set) var shownField: ProfileField = .year
    /// Arkusz jest na ekranie — od otwarcia do końca zjazdu, dłużej niż
    /// `picking`, które gaśnie na początku zjazdu.
    private(set) var isOnScreen = false
    @ObservationIgnored private var pending: (() -> Void)?

    /// Ten sam wiersz zamyka arkusz, inny podmienia jego wybór.
    func pick(_ field: ProfileField) {
        if picking == field {
            picking = nil
        } else {
            shownField = field
            picking = field
            isOnScreen = true
            pending = nil
        }
    }

    /// Okno od razu — albo po zjeździe małego arkusza.
    func present(_ action: @escaping () -> Void) {
        guard isOnScreen else {
            action()
            return
        }
        pending = action
        picking = nil
    }

    /// `onDismiss` arkusza. Wiersz stuknięty w trakcie zjazdu otwiera arkusz
    /// od nowa — wtedy dalej jest na ekranie i okno czeka.
    func didDismiss() {
        isOnScreen = picking != nil
        guard !isOnScreen, let action = pending else { return }
        pending = nil
        action()
    }
}

// MARK: - Wynik, Sylwetka, Treningi

/// Wynik (kcal na utrzymanie i BMI na skali ocen), Sylwetka (cztery wiersze
/// z wyborem w małym arkuszu na 1/3 ekranu) i treningi w tygodniu (kafle
/// z ikoną w kolorze wysiłku).
///
/// Mały arkusz NIE przyciemnia reszty i przepuszcza dotyk
/// (`presentationBackgroundInteraction`): wynik zmienia się na oczach,
/// a stuknięcie w inny wiersz podmienia wybór bez zamykania; zamyka krzyżyk,
/// przeciągnięcie albo ten sam wiersz. Wartość wchodzi od razu (koło — gdy
/// stanie), więc nie ma czego zatwierdzać.
struct ProfileBodyForm: View {
    @Binding var sexRaw: String
    @Binding var yearOfBirth: Int
    @Binding var heightCm: Int
    @Binding var weightKg: Double
    @Binding var activity: ActivityLevel
    /// Stan małego arkusza — trzyma go rodzic, bo jego okna („Imię”, „Usuń
    /// konto”) idą przez `gate.present(_:)`.
    let gate: ProfilePickerGate

    @Environment(\.colorScheme) private var scheme

    init(
        sexRaw: Binding<String>,
        yearOfBirth: Binding<Int>,
        heightCm: Binding<Int>,
        weightKg: Binding<Double>,
        activity: Binding<ActivityLevel>,
        gate: ProfilePickerGate
    ) {
        _sexRaw = sexRaw
        _yearOfBirth = yearOfBirth
        _heightCm = heightCm
        _weightKg = weightKg
        _activity = activity
        self.gate = gate
    }

    static var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    static var yearRange: ClosedRange<Int> { 1900...currentYear }

    private var sex: Sex? { Sex(rawValue: sexRaw) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        }
        .sheet(isPresented: pickerPresented, onDismiss: { gate.didDismiss() }) {
            ProfileFieldPickerSheet(
                field: gate.picking ?? gate.shownField,
                sexRaw: $sexRaw,
                yearOfBirth: $yearOfBirth,
                heightCm: $heightCm,
                weightKg: $weightKg,
                yearRange: Self.yearRange,
                onClose: { gate.picking = nil }
            )
            // Jedna trzecia ekranu, jak koło godzin w „Posiłkach w planie”.
            .presentationDetents([.fraction(1.0 / 3.0)])
            // Bez przyciemnienia i z dotykiem pod spodem: wynik na górze
            // zmienia się na oczach, a stuknięcie w inny wiersz podmienia
            // wybór w tym samym arkuszu.
            .presentationBackgroundInteraction(.enabled(upThrough: .fraction(1.0 / 3.0)))
            .dashboardLiquidSheet(cornerRadius: 26)
        }
    }

    // MARK: - Wynik

    /// Sylwetka policzona z bieżących wartości. Zawsze jest (`BodyMetrics.preview`).
    private var metrics: BodyMetrics {
        BodyMetrics.preview(
            heightCm: heightCm,
            weightKg: weightKg,
            yearOfBirth: yearOfBirth,
            activityRaw: activity.rawValue,
            sexRaw: sexRaw
        )
    }

    /// Kcal na utrzymanie i BMI na skali ocen — pierwsza rzecz, bo po to są
    /// te dane. Zmiana wartości poniżej roluje cyfry (`numericText`, krzywa
    /// `SCMotion.textRoll`), a znacznik BMI jedzie po skali.
    private var resultCard: some View {
        let metrics = self.metrics
        let kcal = metrics.maintenanceCalories
        let bmi = metrics.bmi
        let category = metrics.bmiCategory
        let bmiText = Self.bmiFormatter.string(from: NSNumber(value: bmi)) ?? "—"

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
                    action: { gate.pick(field) }
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
        let isActive = gate.picking == field
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
            return "\(yearOfBirth) · \(Self.ageLabel(max(Self.currentYear - yearOfBirth, 0)))"
        case .height:
            return "\(heightCm) cm"
        case .weight:
            return "\(Self.weightText(weightKg)) kg"
        }
    }

    private var pickerPresented: Binding<Bool> {
        Binding(
            get: { gate.picking != nil },
            set: { isPresented in
                if !isPresented { gate.picking = nil }
            }
        )
    }

    // MARK: - Treningi

    private var activityCard: some View {
        SCIconTilePicker(choices: Self.activityChoices, selection: $activity)
            .padding(10)
            .background(card)
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

    private var card: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.scTileBg(scheme))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
    }

    // MARK: - Teksty

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

    /// Bez zbędnego „,0" — 83 kg zostaje jako „83", 83,5 jako „83,5".
    static func weightText(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Profil nad treścią

/// Profil nad „Twoimi danymi” tam, gdzie nie ma nagłówka arkusza z krzyżykiem:
/// ekran wepchnięty w arkusz diety i krok 1 kreatora. Imię zmienia okno
/// „Imię” (`profileNameAlert`) — ołówkiem albo stuknięciem w imię.
struct ProfileIdentityRow: View {
    let title: String
    /// Imienia jeszcze nie ma (kreator) — tytuł w terakocie prosi o nie.
    var isPlaceholder: Bool = false
    var detail: String? = nil
    let avatarUrl: String?
    var colorIndex: Int? = nil
    let seed: String
    let onRename: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onRename) {
                HStack(spacing: 12) {
                    ProfileAvatar(
                        avatarUrl: avatarUrl,
                        displayName: isPlaceholder ? "?" : title,
                        size: 44,
                        colorIndex: colorIndex,
                        seed: seed
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.sc(size: 17, weight: .bold))
                            .tracking(-0.3)
                            .foregroundStyle(isPlaceholder ? SCPalette.terracotta : Color.scLabel(scheme))
                            .lineLimit(1)

                        if let detail {
                            Text(detail)
                                .font(.sc(size: 13))
                                .foregroundStyle(Color.scMuted(scheme))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Zmienia imię")

            SCSheetIconButton(systemName: "pencil", accessibilityLabel: "Zmień imię", action: onRename)
        }
    }
}

// MARK: - Okno „Imię”

extension View {
    /// Okno „Imię” — Ustawienia → „Twoje dane” i krok 1 kreatora. Pole tnie
    /// `SessionStore.limitedDisplayName` (punkty kodowe, jak `@MaxLength`
    /// serwera), „Zapisz” bez imienia jest wyłączone.
    func profileNameAlert(
        isPresented: Binding<Bool>,
        draft: Binding<String>,
        onSave: @escaping () -> Void
    ) -> some View {
        modifier(ProfileNameAlert(isPresented: isPresented, draft: draft, onSave: onSave))
    }
}

private struct ProfileNameAlert: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var draft: String
    let onSave: () -> Void

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func body(content: Content) -> some View {
        content
            .alert("Imię", isPresented: $isPresented) {
                TextField("Twoje imię", text: $draft)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                Button("Anuluj", role: .cancel) {}
                Button("Zapisz", action: onSave)
                    .disabled(trimmed.isEmpty)
            } message: {
                Text("Widzą je domownicy.")
            }
            // Limit serwera (`UpdateProfileDto`, 64 punkty kodowe) — przycinamy
            // w polu, żeby stan lokalny = to, co przyjmie backend.
            .onChange(of: draft) { _, newValue in
                let limited = SessionStore.limitedDisplayName(newValue)
                if limited != newValue {
                    draft = limited
                }
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
