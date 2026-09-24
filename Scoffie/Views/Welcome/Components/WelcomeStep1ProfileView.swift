import SwiftUI

// Kreator, krok 1 — profil: imię, rok urodzenia, wzrost, waga, płeć.
//
// Od 24.09.2026 (Rafał: „tak smutno wygląda… żeby wyglądało jak reszta”)
// w układzie Ustawień → „Twoje dane” (`ProfileDetailsSheet`), które pytają
// o dokładnie to samo: karta „Profil” z awatarem i imieniem edytowanym
// w miejscu, karta „Sylwetka” z płcią, rokiem (wiek w terakocie), wzrostem
// i wagą w jednym miejscu, a pod nimi na żywo BMI i kalorie na utrzymanie
// wagi (`BodyMetricsSummaryRow`) — widać od razu, do czego te liczby służą.
// Dawniej pięć osobnych pól luzem na tle.
//
// Pola trzymają lokalny `@State` rodzica, więc wpisuje się swobodnie; zapis
// na serwer robi `WelcomeView` przy „Dalej”. Rok urodzenia to poziome koło
// (`YearWheelPicker`), to samo co w Ustawieniach → „Twoje dane”.
struct WelcomeStep1ProfileView: View {
    @Binding var name: String
    @Binding var yearOfBirth: Int
    @Binding var heightCm: Int
    @Binding var weightKg: Double
    @Binding var sex: Sex?
    /// Treningi z kroku 2 (do tej chwili wartość domyślna) — tylko do
    /// podglądu kalorii na utrzymanie wagi.
    var activity: ActivityLevel = .light

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sessionStore) private var sessionStore
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case height
        case weight
    }

    private let yearRange: ClosedRange<Int> = 1900...Calendar.current.component(.year, from: Date())

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    private var metrics: BodyMetrics? {
        BodyMetrics(
            heightCm: heightCm,
            weightKg: weightKg,
            yearOfBirth: yearOfBirth,
            activityRaw: activity.rawValue,
            sexRaw: sex?.rawValue ?? ""
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            // Ciaśniej niż inne kroki (16 zamiast 22): ten krok ma się
            // zmieścić bez przewijania razem z podglądem BMI (Rafał 24.09.2026).
            VStack(alignment: .leading, spacing: 16) {
                SCStepHeader(
                    icon: "person.fill",
                    eyebrow: "Witaj w Scoffie",
                    title: "Zacznijmy od Ciebie",
                    subtitle: "Z tych danych policzymy Twój dzienny cel."
                )

                // Bez etykiety „Profil” — awatar z imieniem mówi sam za siebie,
                // a ten krok ma się zmieścić bez przewijania.
                profileCard

                VStack(alignment: .leading, spacing: 2) {
                    // Zdanie o prywatności w wierszu etykiety, po prawej — pada,
                    // zanim poda się wagę, i nie kosztuje osobnej linijki.
                    HStack(alignment: .firstTextBaseline) {
                        EditorialSheetSectionLabel(title: "Sylwetka")
                            .fixedSize()
                        Spacer(minLength: 8)
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("Tylko do obliczeń")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundStyle(Color.scFaint(colorScheme))
                        .padding(.trailing, 6)
                    }
                    bodyCard
                }
            }
            .padding(.horizontal, WelcomeLayout.horizontal)
            .padding(.top, WelcomeLayout.topInset)
            .padding(.bottom, WelcomeLayout.bottomInset)
        }
        .scScrollEdgeFade()
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Profil

    /// Awatar i imię jak w „Twoich danych”: imię jest nagłówkiem karty,
    /// edytowalnym w miejscu — ołówek i kreska zapalają się w terakocie przy
    /// edycji.
    private var profileCard: some View {
        let isEditing = focusedField == .name
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        return HStack(alignment: .center, spacing: 14) {
            ProfileAvatar(
                avatarUrl: nil,
                displayName: trimmed.isEmpty ? "?" : trimmed,
                size: 44,
                seed: sessionStore.currentUserId ?? trimmed
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    TextField("Jak masz na imię?", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onChange(of: name) { _, newValue in
                            // Limit serwera (`UpdateProfileDto`, 64).
                            if newValue.count > SessionStore.displayNameMaxLength {
                                name = String(newValue.prefix(SessionStore.displayNameMaxLength))
                            }
                        }
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .font(.system(size: 18, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(colorScheme))
                        .onSubmit { focusedField = .height }

                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isEditing ? SCPalette.terracotta : Color.scFaint(colorScheme))
                }

                Rectangle()
                    .fill(isEditing ? SCPalette.terracotta : Color.scRule(colorScheme))
                    .frame(height: isEditing ? 1.5 : 1)

                Text("Tak zobaczą Cię domownicy w planie")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.scMuted(colorScheme))
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.18), value: isEditing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .welcomeCard()
        .contentShape(Rectangle())
        .onTapGesture { focusedField = .name }
    }

    // MARK: - Sylwetka

    /// Jedna karta jak „Sylwetka” w Ustawieniach: płeć, rok, wzrost i waga,
    /// a pod nimi wynik — BMI i kalorie na utrzymanie wagi.
    private var bodyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                fieldCaption("Płeć")
                HStack(spacing: 8) {
                    ForEach(Sex.allCases) { candidate in
                        SexChip(
                            candidate: candidate,
                            isSelected: sex == candidate,
                            onTap: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    sex = (sex == candidate) ? nil : candidate
                                }
                            }
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    fieldCaption("Rok urodzenia")
                    Spacer(minLength: 8)
                    Text(BodyMetricsSummaryRow.ageLabel(max(currentYear - yearOfBirth, 0)))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(SCPalette.terracotta)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.2), value: yearOfBirth)
                }
                YearWheelPicker(year: $yearOfBirth, range: yearRange, surface: Color.scChipBg(colorScheme))
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldCaption("Wzrost")
                    measureField(unit: "cm") {
                        TextField("178", value: $heightCm, format: .number)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .height)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    fieldCaption("Waga")
                    measureField(unit: "kg") {
                        // Jedno miejsce po przecinku — 83,5 kg to
                        // normalny odczyt z wagi łazienkowej.
                        TextField("74", value: $weightKg, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .weight)
                    }
                }
            }

            if let metrics {
                BodyMetricsSummaryRow(metrics: metrics)
                    .animation(.smooth(duration: 0.2), value: metrics.maintenanceCalories)
            }
        }
        .padding(14)
        .welcomeCard()
    }

    /// Podpis pola w karcie — krój etykiety sekcji bez jej marginesów, jak
    /// w „Twoich danych”.
    private func fieldCaption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(Color.scFaint(colorScheme))
    }

    /// Pole liczby z jednostką — wzrost i waga w jednym kroju, na wklęsłej
    /// powierzchni wewnątrz karty (`scChipBg`), jak w Ustawieniach.
    private func measureField<Input: View>(unit: String, @ViewBuilder input: () -> Input) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            input()
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color.scLabel(colorScheme))
                .monospacedDigit()
            Text(unit)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.scMuted(colorScheme))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.scChipBg(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.scTileStroke(colorScheme), lineWidth: 1)
                )
        )
    }
}

/// Płeć różnicuje wzór na przemianę materii wyłącznie stałą (+5 / −161),
/// więc pytanie jest opcjonalne: ponowne stuknięcie w zaznaczoną opcję ją
/// odznacza, a bez niej liczymy ze średniej.
private struct SexChip: View {
    let candidate: Sex
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                Image(systemName: candidate.icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(candidate.title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(isSelected ? SCPalette.terracotta : Color.scLabel(colorScheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            // Ten sam chip co w „Twoich danych” w Ustawieniach — wybór
            // w wariancie „soft”, nie pełna terakota z białym napisem.
            // Niewybrany na tle karty (`scTileBg`), bo stoi wprost na stronie.
            // Wewnątrz karty „Sylwetka”, więc niewybrany na wklęsłej
            // powierzchni (`scChipBg`), jak pola wzrostu i wagi obok.
            .scChoiceSurface(
                RoundedRectangle(cornerRadius: 12, style: .continuous),
                isOn: isSelected,
                offFill: Color.scChipBg(colorScheme)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(candidate.title)
        .accessibilityValue(isSelected ? "Wybrane" : "Niewybrane")
    }
}

// Nie `private` — korzysta z niego również arkusz „Twoje dane” w Ustawieniach,
// żeby rok urodzenia wybierało się tam dokładnie tak samo jak w kreatorze.
//
// Pod spodem jest poziomy `ScrollView` po CAŁYM zakresie lat, a nie pięć
// przycisków przerysowywanych przy każdej zmianie. Poprzednia wersja liczyła
// widoczne lata jako `year-2…year+2`, więc każdy krok podmieniał wszystkie
// pięć etykiet naraz: gest zatrzymywał się po jednym roku, a zamiast
// przewijania było mruganie. Tu przewija system — z rozpędem, z odbiciem na
// końcach zakresu i ze snapowaniem do komórki (`viewAligned`), a rok bierze
// się z tego, co stoi na środku.
struct YearWheelPicker: View {
    @Binding var year: Int
    let range: ClosedRange<Int>

    /// Tło pigułki. Domyślnie `scTileBg`, czyli to, czego używa kreator na
    /// tle kanwy. W arkuszu Ustawień picker siedzi WEWNĄTRZ karty `scTileBg`
    /// i przy domyślnym tle zlałby się z nią w jedną plamę — tam wchodzi
    /// `scChipBg`.
    var surface: Color? = nil

    @Environment(\.colorScheme) private var colorScheme

    /// Rok pod środkiem kontrolki. Osobny od `year`, bo w trakcie
    /// przewijania jest `nil` przez chwilę między komórkami — i dlatego
    /// nie może BYĆ źródłem prawdy, tylko ją aktualizować.
    @State private var centeredYear: Int?

    /// Ile lat mieści się w kontrolce. Pięć, jak dotąd: środkowa komórka
    /// plus po dwie z każdej strony jako zapowiedź kierunku.
    private static let visibleCells: CGFloat = 5
    private static let contentPadding: CGFloat = 6
    private static let rowHeight: CGFloat = 44

    private var years: [Int] { Array(range) }

    var body: some View {
        GeometryReader { proxy in
            let cellWidth = max(
                44,
                (proxy.size.width - Self.contentPadding * 2) / Self.visibleCells
            )
            // Marginesy treści równe dwóm komórkom z każdej strony —
            // pierwszy i ostatni rok zakresu też muszą dać się ustawić
            // na środku, a nie tylko przy krawędzi.
            let sideInset = max(0, (proxy.size.width - cellWidth) / 2)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(years, id: \.self) { y in
                        Text(String(y))
                            .font(font(for: y))
                            .foregroundStyle(color(for: y))
                            .monospacedDigit()
                            .frame(width: cellWidth, height: Self.rowHeight)
                            .contentShape(Rectangle())
                            // Skala i przezroczystość prowadzone przez sam
                            // scroll — dzięki temu sąsiedzi gasną PŁYNNIE
                            // w trakcie ruchu, a nie skokiem po dojechaniu.
                            .scrollTransition(
                                .interactive,
                                axis: .horizontal
                            ) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.86)
                                    .opacity(phase.isIdentity ? 1 : 0.55)
                            }
                            // Stuknięcie w sąsiada zostaje jako druga droga —
                            // ustawienie `centeredYear` przewija tam scroll,
                            // więc wynik jest ten sam co przy geście.
                            .onTapGesture {
                                guard y != year else { return }
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                    centeredYear = y
                                }
                                year = y
                            }
                            .id(y)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centeredYear, anchor: .center)
            .contentMargins(.horizontal, sideInset, for: .scrollContent)
            .frame(height: Self.rowHeight)
            .padding(.vertical, Self.contentPadding)
            .background(background(cellWidth: cellWidth))
            // Snap ustawił nowy rok na środku — to jedyne miejsce, w którym
            // gest zmienia wartość.
            .onChange(of: centeredYear) { _, newValue in
                guard let newValue, newValue != year else { return }
                year = newValue
            }
            // Wartość zmieniona z zewnątrz (wczytanie profilu, korekta
            // zakresu w `clampToRange`) dojeżdża do środka sama.
            .onChange(of: year) { _, newValue in
                guard centeredYear != newValue else { return }
                centeredYear = newValue
            }
            .onAppear { centeredYear = clamp(year) }
        }
        .frame(height: Self.rowHeight + Self.contentPadding * 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rok urodzenia: \(year)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                year = clamp(year + 1)
            case .decrement:
                year = clamp(year - 1)
            @unknown default:
                break
            }
        }
    }

    private func background(cellWidth: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: WelcomeLayout.cardRadius, style: .continuous)
                .fill(surface ?? Color.scTileBg(colorScheme))
            RoundedRectangle(cornerRadius: WelcomeLayout.cardRadius, style: .continuous)
                .stroke(Color.scTileStroke(colorScheme), lineWidth: 1)

            // Ramka wyboru stoi NIERUCHOMO na środku — to lata jadą pod nią.
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(SCPalette.terracotta.opacity(colorScheme == .dark ? 0.16 : 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(SCPalette.terracotta.opacity(0.32), lineWidth: 1)
                )
                .frame(width: cellWidth, height: Self.rowHeight)
                .allowsHitTesting(false)
        }
    }

    private func clamp(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func font(for y: Int) -> Font {
        y == year
            ? .system(size: 20, weight: .bold)
            : .system(size: 16, weight: .medium)
    }

    private func color(for y: Int) -> Color {
        y == year ? Color.scLabel(colorScheme) : Color.scMuted(colorScheme)
    }
}

#Preview("Dark") {
    StepPreviewWrapper {
        WelcomeStep1ProfileView(
            name: .constant("Rafał"),
            yearOfBirth: .constant(1992),
            heightCm: .constant(178),
            weightKg: .constant(74),
            sex: .constant(.male)
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Light") {
    StepPreviewWrapper {
        WelcomeStep1ProfileView(
            name: .constant("Rafał"),
            yearOfBirth: .constant(1992),
            heightCm: .constant(178),
            weightKg: .constant(74),
            sex: .constant(.male)
        )
    }
    .preferredColorScheme(.light)
}

private struct StepPreviewWrapper<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            SCPageBackground(scheme: colorScheme).ignoresSafeArea()
            content()
        }
    }
}
