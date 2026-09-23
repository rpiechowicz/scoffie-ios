import SwiftUI

// Welcome step 1 — Profile: imię, rok urodzenia, wzrost, waga.
//
// All fields are bound to local @State so users can type freely; the
// commit + backend save happens at the WelcomeView level when the user
// taps "Dalej". Year of birth uses a horizontal wheel-style picker that
// echoes the design canvas (5 visible values, center-highlighted).
struct WelcomeStep1ProfileView: View {
    @Binding var name: String
    @Binding var yearOfBirth: Int
    @Binding var heightCm: Int
    @Binding var weightKg: Double
    @Binding var sex: Sex?

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case height
        case weight
    }

    private let yearRange: ClosedRange<Int> = 1900...Calendar.current.component(.year, from: Date())

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: WelcomeLayout.sectionSpacing) {
                WelcomeStepHeader(
                    icon: "person.fill",
                    accent: SCPalette.terracotta,
                    eyebrow: "Witaj w Scoffie",
                    title: "Zacznijmy od Ciebie",
                    subtitle: "Te dane pomogą nam dopasować propozycje. Zmienisz je później w ustawieniach."
                )

                VStack(alignment: .leading, spacing: 6) {
                    WelcomeFieldCaption(text: "Jak masz na imię?")
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.scMuted(colorScheme))
                        TextField("Np. Rafał", text: $name)
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
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.scLabel(colorScheme))
                            .onSubmit { focusedField = .height }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .welcomeCard()
                }

                VStack(alignment: .leading, spacing: 6) {
                    WelcomeFieldCaption(text: "Rok urodzenia")
                    YearWheelPicker(year: $yearOfBirth, range: yearRange)
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        WelcomeFieldCaption(text: "Wzrost")
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            TextField("178", value: $heightCm, format: .number)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .height)
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(Color.scLabel(colorScheme))
                                .monospacedDigit()
                            Text("cm")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.scMuted(colorScheme))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .welcomeCard()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        WelcomeFieldCaption(text: "Waga")
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            // Jedno miejsce po przecinku — 83,5 kg to
                            // normalny odczyt z wagi łazienkowej.
                            TextField("74", value: $weightKg, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .weight)
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(Color.scLabel(colorScheme))
                                .monospacedDigit()
                            Text("kg")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.scMuted(colorScheme))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .welcomeCard()
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    WelcomeFieldCaption(text: "Płeć")
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

                Text("Te dane przetwarzamy lokalnie wyłącznie do obliczeń kalorycznych — nie udostępniamy ich nikomu, ani nie wykorzystujemy do reklam.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.scMuted(colorScheme))
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
            }
            .padding(.horizontal, WelcomeLayout.horizontal)
            .padding(.top, WelcomeLayout.topInset)
            .padding(.bottom, WelcomeLayout.bottomInset)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// Year-of-birth picker. Shows 5 years horizontally with the selected one
// scaled and highlighted. Tapping a side value advances the wheel; the
// terracotta highlight band animates with a spring so the interaction
// feels tactile. Drag updates live (every cell-width of horizontal travel
// changes the year by one) so the picker reads as a real wheel and not a
// commit-on-release control.
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
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.scLabel(colorScheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [SCPalette.terracotta.opacity(0.95), SCPalette.terracotta],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            : AnyShapeStyle(Color.scChipBg(colorScheme))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.scTileStroke(colorScheme), lineWidth: 1)
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
            Color.scCanvas(colorScheme).ignoresSafeArea()
            content()
        }
    }
}
