import SwiftUI

// Welcome step 3 — Diet + daily kcal target. The slider sits between the
// design's 1200…3500 bounds with a 50 kcal step so the value lands on a
// recognisable number. The diet rows reuse the radio + accent-icon
// pattern from step 2 so the flow feels visually consistent.
struct WelcomeStep3PreferencesView: View {
    @Binding var diet: DietPreference
    @Binding var calorieGoal: Int
    @Binding var allergens: Set<Allergen>
    /// Rozbicie dziennego celu na makro — policzone z sylwetki i celu
    /// z kroków 1–2. `nil`, dopóki sylwetki nie da się złożyć (te same
    /// warunki, co w Ustawieniach → „Dieta i alergeny").
    ///
    /// Do odczytu, nie do edycji: w kreatorze ma pokazać, że liczby
    /// z poprzednich kroków do czegoś posłużyły. Stepperami przestawia się
    /// je w Ustawieniach, gdzie jest miejsce na trzy wiersze z kontrolkami
    /// i na przycisk powrotu do automatu.
    var macros: MacroTargets?

    @Environment(\.colorScheme) private var colorScheme

    private let calorieRange: ClosedRange<Double> = 1200...3500
    private let calorieStep: Double = 50

    private func toggleAllergen(_ allergen: Allergen) {
        if allergens.contains(allergen) {
            allergens.remove(allergen)
        } else {
            allergens.insert(allergen)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: WelcomeLayout.sectionSpacing) {
                WelcomeStepHeader(
                    icon: "leaf.fill",
                    accent: SCPalette.terracotta,
                    eyebrow: "Dieta i kalorie",
                    title: "Co najczęściej jadasz?",
                    subtitle: "Na podstawie Twojego celu zaproponowaliśmy dzienną liczbę kalorii — możesz ją dostosować."
                )

                VStack(alignment: .leading, spacing: 8) {
                    WelcomeFieldCaption(text: "Cel kaloryczny")

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                SCPalette.terracotta,
                                                SCPalette.terracottaDeep,
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 36, height: 36)
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dzienny cel")
                                    .font(.system(size: 15.5, weight: .semibold))
                                    .foregroundStyle(Color.scLabel(colorScheme))
                                Text("Aplikacja podpowie, jak rozłożyć posiłki w ciągu dnia.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.scMuted(colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(calorieGoal)")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundStyle(SCPalette.terracotta)
                                .monospacedDigit()
                                .contentTransition(.numericText(value: Double(calorieGoal)))
                                .animation(
                                    .spring(response: 0.28, dampingFraction: 0.86),
                                    value: calorieGoal
                                )
                            Text("kcal / dzień")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.scMuted(colorScheme))
                        }

                        Slider(
                            value: Binding(
                                get: { Double(calorieGoal) },
                                set: { calorieGoal = Int($0.rounded()) }
                            ),
                            in: calorieRange,
                            step: calorieStep
                        )
                        .tint(SCPalette.terracotta)

                        HStack {
                            Text("1 200")
                            Spacer()
                            Text("3 500")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Color.scMuted(colorScheme))
                        .monospacedDigit()
                    }
                    .padding(16)
                    .welcomeCard()
                }

                if let macros {
                    VStack(alignment: .leading, spacing: 8) {
                        WelcomeFieldCaption(text: "Makroskładniki")
                        macroCard(macros)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    WelcomeFieldCaption(text: "Sposób odżywiania")
                    VStack(spacing: 0) {
                        ForEach(Array(DietPreference.allCases.enumerated()), id: \.element.id) { index, candidate in
                            WelcomeOptionRow(
                                icon: candidate.icon,
                                accent: candidate.accent,
                                title: candidate.title,
                                subtitle: candidate.subtitle,
                                isSelected: candidate == diet,
                                onTap: {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                        diet = candidate
                                    }
                                }
                            )
                            if index < DietPreference.allCases.count - 1 {
                                WelcomeOptionDivider()
                            }
                        }
                    }
                    .welcomeCard()
                }

                VStack(alignment: .leading, spacing: 8) {
                    WelcomeFieldCaption(text: "Alergeny i nietolerancje")
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Stuknij, aby zaznaczyć produkty, których chcesz unikać. Możesz wybrać dowolną liczbę.")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Color.scMuted(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)

                        AllergenChipFlow(spacing: 8) {
                            ForEach(Allergen.allCases) { candidate in
                                AllergenChip(
                                    allergen: candidate,
                                    isSelected: allergens.contains(candidate),
                                    onTap: {
                                        withAnimation(.smooth(duration: 0.18)) {
                                            toggleAllergen(candidate)
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .padding(18)
                    .welcomeCard()
                }
            }
            .padding(.horizontal, WelcomeLayout.horizontal)
            .padding(.top, WelcomeLayout.topInset)
            .padding(.bottom, WelcomeLayout.bottomInset)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Trzy paski w proporcji kalorii z każdego makro plus gramy.
    ///
    /// Ta karta niczego nie pyta — jest odpowiedzią na to, o co pytaliśmy
    /// wcześniej. Bez niej krok 3 wyglądał tak, jakby wzrost i waga z kroku 1
    /// nigdzie nie poszły.
    private func macroCard(_ macros: MacroTargets) -> some View {
        let total = max(macros.totalKcal, 1)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Tak rozkładamy \(calorieGoal) kcal na dzień. Dokładne wartości ustawisz w Ustawieniach.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.scMuted(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            macroRow(
                title: "Białko",
                grams: macros.proteinG,
                kcal: macros.proteinKcal,
                total: total,
                accent: SCPalette.indigo
            )
            macroRow(
                title: "Węglowodany",
                grams: macros.carbsG,
                kcal: macros.carbsKcal,
                total: total,
                accent: SCPalette.sage
            )
            macroRow(
                title: "Tłuszcze",
                grams: macros.fatG,
                kcal: macros.fatKcal,
                total: total,
                accent: SCPalette.butter
            )
        }
        .padding(16)
        .welcomeCard()
        .animation(.smooth(duration: 0.22), value: macros)
    }

    private func macroRow(
        title: String,
        grams: Int,
        kcal: Int,
        total: Int,
        accent: Color
    ) -> some View {
        let share = min(max(Double(kcal) / Double(total), 0), 1)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.scLabel(colorScheme))
                Spacer(minLength: 8)
                Text("\(grams) g")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                Text("· \(Int((share * 100).rounded()))%")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.scFaint(colorScheme))
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.scBarTrack(colorScheme))
                    Capsule()
                        .fill(accent)
                        .frame(width: proxy.size.width * share)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(grams) gramów")
    }

}

// Multi-select chip used by the allergens section. Mirrors Settings →
// Dieta i alergeny so the visual + tap feel are identical between the
// welcome flow and Settings.
private struct AllergenChip: View {
    let allergen: Allergen
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
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
            .foregroundStyle(isSelected ? .white : Color.scLabel(colorScheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    isSelected
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [SCPalette.terracotta, SCPalette.terracotta.mix(black: 0.18)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        : AnyShapeStyle(Color.scChipBg(colorScheme))
                )
            )
            .overlay(
                Capsule().stroke(
                    isSelected
                        ? SCPalette.terracotta.opacity(0.35)
                        : Color.scTileStroke(colorScheme),
                    lineWidth: 1
                )
            )
            .shadow(
                color: SCPalette.terracotta.opacity(isSelected ? 0.20 : 0),
                radius: 5, x: 0, y: 2
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(allergen.title)
        .accessibilityValue(isSelected ? "Zaznaczone" : "Niezaznaczone")
    }
}

#Preview("Dark") {
    StatefulPreviewContainer(diet: .none, kcal: 2300, allergens: []) { diet, kcal, allergens in
        ZStack {
            SCPalette.canvasDark.ignoresSafeArea()
            WelcomeStep3PreferencesView(diet: diet, calorieGoal: kcal, allergens: allergens)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Light") {
    StatefulPreviewContainer(diet: .vegetarian, kcal: 1900, allergens: [.gluten, .nuts]) { diet, kcal, allergens in
        ZStack {
            SCPalette.canvasLight.ignoresSafeArea()
            WelcomeStep3PreferencesView(diet: diet, calorieGoal: kcal, allergens: allergens)
        }
        .preferredColorScheme(.light)
    }
}

private struct StatefulPreviewContainer<Content: View>: View {
    @State private var diet: DietPreference
    @State private var kcal: Int
    @State private var allergens: Set<Allergen>
    let content: (Binding<DietPreference>, Binding<Int>, Binding<Set<Allergen>>) -> Content

    init(
        diet: DietPreference,
        kcal: Int,
        allergens: Set<Allergen>,
        @ViewBuilder content: @escaping (Binding<DietPreference>, Binding<Int>, Binding<Set<Allergen>>) -> Content
    ) {
        _diet = State(initialValue: diet)
        _kcal = State(initialValue: kcal)
        _allergens = State(initialValue: allergens)
        self.content = content
    }

    var body: some View {
        content($diet, $kcal, $allergens)
    }
}
