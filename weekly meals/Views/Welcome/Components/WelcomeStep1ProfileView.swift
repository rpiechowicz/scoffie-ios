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
            VStack(alignment: .leading, spacing: 18) {
                WelcomeStepHeader(
                    icon: "person.fill",
                    accent: WMPalette.terracotta,
                    eyebrow: "Witaj w Weekly Meals",
                    title: "Zacznijmy od Ciebie",
                    subtitle: "Te dane pomogą nam dopasować propozycje. Zmienisz je później w ustawieniach."
                )

                VStack(alignment: .leading, spacing: 6) {
                    WelcomeFieldCaption(text: "Jak masz na imię?")
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.wmMuted(colorScheme))
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
                            .foregroundStyle(Color.wmLabel(colorScheme))
                            .onSubmit { focusedField = .height }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(welcomeCardBackground)
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
                                .foregroundStyle(Color.wmLabel(colorScheme))
                                .monospacedDigit()
                            Text("cm")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.wmMuted(colorScheme))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(welcomeCardBackground)
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
                                .foregroundStyle(Color.wmLabel(colorScheme))
                                .monospacedDigit()
                            Text("kg")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.wmMuted(colorScheme))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(welcomeCardBackground)
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
                    .foregroundStyle(Color.wmMuted(colorScheme))
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 140)
            .padding(.bottom, 200)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var welcomeCardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.wmTileBg(colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.wmTileStroke(colorScheme), lineWidth: 1)
            )
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
            .foregroundStyle(isSelected ? Color.white : Color.wmLabel(colorScheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [WMPalette.terracotta.opacity(0.95), WMPalette.terracotta],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            : AnyShapeStyle(Color.wmChipBg(colorScheme))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.wmTileStroke(colorScheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(candidate.title)
        .accessibilityValue(isSelected ? "Wybrane" : "Niewybrane")
    }
}

// Nie `private` — korzysta z niego również arkusz „Twoje dane” w Ustawieniach,
// żeby rok urodzenia wybierało się tam dokładnie tak samo jak w kreatorze.
struct YearWheelPicker: View {
    @Binding var year: Int
    let range: ClosedRange<Int>

    /// Tło pigułki. Domyślnie `wmTileBg`, czyli to, czego używa kreator na
    /// tle kanwy. W arkuszu Ustawień picker siedzi WEWNĄTRZ karty `wmTileBg`
    /// i przy domyślnym tle zlałby się z nią w jedną plamę — tam wchodzi
    /// `wmInsetSurface`.
    var surface: Color? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragAnchorYear: Int? = nil

    private static let snapAnimation = Animation.spring(response: 0.22, dampingFraction: 0.78)
    private static let dragAnimation = Animation.interactiveSpring(response: 0.18, dampingFraction: 0.86)

    var body: some View {
        let years = visibleYears()
        return HStack(spacing: 4) {
            ForEach(years, id: \.self) { y in
                Button {
                    guard range.contains(y), y != year else { return }
                    withAnimation(Self.snapAnimation) {
                        year = y
                    }
                } label: {
                    Text(String(y))
                        .font(yearFont(for: y))
                        .foregroundStyle(yearColor(for: y))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!range.contains(y))
            }
        }
        .padding(6)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(surface ?? Color.wmTileBg(colorScheme))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.wmTileStroke(colorScheme), lineWidth: 1)

                GeometryReader { proxy in
                    let w = (proxy.size.width - 12) / 5
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(WMPalette.terracotta.opacity(colorScheme == .dark ? 0.16 : 0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(WMPalette.terracotta.opacity(0.32), lineWidth: 1)
                        )
                        .frame(width: w, height: proxy.size.height - 12)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .allowsHitTesting(false)
                }
            }
        )
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    let anchor = dragAnchorYear ?? year
                    if dragAnchorYear == nil { dragAnchorYear = anchor }
                    // ~52pt per logical cell on a 360pt-wide picker — feels
                    // like a wheel without overshooting on small flicks.
                    let cellWidth: CGFloat = 52
                    let steps = Int((-value.translation.width / cellWidth).rounded())
                    let target = clamp(anchor + steps)
                    if target != year {
                        withAnimation(Self.dragAnimation) {
                            year = target
                        }
                    }
                }
                .onEnded { _ in
                    dragAnchorYear = nil
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rok urodzenia: \(year)")
        .accessibilityAdjustableAction { direction in
            withAnimation(Self.snapAnimation) {
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
    }

    private func clamp(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func visibleYears() -> [Int] {
        (-2...2).map { year + $0 }
    }

    private func yearFont(for y: Int) -> Font {
        if y == year { return .system(size: 20, weight: .bold) }
        if abs(y - year) == 1 { return .system(size: 16, weight: .medium) }
        return .system(size: 15, weight: .medium)
    }

    private func yearColor(for y: Int) -> Color {
        if !range.contains(y) {
            return Color.wmFaint(colorScheme).opacity(0.4)
        }
        if y == year {
            return Color.wmLabel(colorScheme)
        }
        if abs(y - year) == 1 {
            return Color.wmMuted(colorScheme)
        }
        return Color.wmFaint(colorScheme)
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
            Color.wmCanvas(colorScheme).ignoresSafeArea()
            content()
        }
    }
}
