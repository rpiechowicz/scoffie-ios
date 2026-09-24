import SwiftUI

// Kreator, krok 3 — dzienny cel kalorii, makro, sposób odżywiania i alergeny.
// Suwak chodzi w granicach 1200…3500 co 50 kcal, żeby liczba lądowała na
// rozpoznawalnej wartości. Wiersze diety są tymi samymi wierszami, co cele
// w kroku 2 i dieta w Ustawieniach.
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
                SCStepHeader(
                    icon: "flame.fill",
                    eyebrow: "Dieta i kalorie",
                    title: "Ile i co jesz?",
                    subtitle: "Cel policzyliśmy z Twoich danych — możesz go przesunąć."
                )

                WelcomeSection(title: "Dzienny cel") {
                    calorieCard
                }

                if let macros {
                    WelcomeSection(title: "Makroskładniki") {
                        macroCard(macros)
                    }
                }

                WelcomeSection(title: "Sposób odżywiania") {
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

                // Bez zdania „Dania z nimi znikną z przepisów” — powód padł
                // na ostatnim ekranie przewodnika, a siatka mówi sama za siebie.
                WelcomeSection(title: "Alergeny i nietolerancje") {
                    // Ten sam mechanizm co w Ustawieniach: karta z wynikiem
                    // i arkusz wyboru. Katalogu w kreatorze jeszcze nie ma,
                    // więc bez liczby ukrytych przepisów.
                    AllergenSelectionField(
                        selected: allergens,
                        hiddenRecipes: nil,
                        onToggle: { toggleAllergen($0) },
                        onClear: { allergens = [] }
                    )
                }
            }
            .padding(.horizontal, WelcomeLayout.horizontal)
            .padding(.top, WelcomeLayout.topInset)
            .padding(.bottom, WelcomeLayout.bottomInset)
        }
        .scScrollEdgeFade()
        .scrollDismissesKeyboard(.interactively)
    }

    /// Duża liczba celu, suwak i granice. Bez kafelka z płomieniem i zdania
    /// „Aplikacja podpowie, jak rozłożyć posiłki” — płomień stoi w nagłówku
    /// kroku, a liczba w terakocie mówi, co tu się ustawia.
    private var calorieCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(calorieGoal)")
                    .font(.system(size: 38, weight: .heavy))
                    .tracking(-0.8)
                    .foregroundStyle(SCPalette.terracotta)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(calorieGoal)))
                    .animation(
                        .spring(response: 0.28, dampingFraction: 0.86),
                        value: calorieGoal
                    )
                Text("kcal / dzień")
                    .font(.system(size: 14, weight: .medium))
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
            .accessibilityLabel("Dzienny cel kalorii")
            .accessibilityValue("\(calorieGoal) kcal")

            HStack {
                Text("1 200")
                Spacer()
                Text("3 500")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.scFaint(colorScheme))
            .monospacedDigit()
        }
        .padding(16)
        .welcomeCard()
    }

    /// Trzy paski w proporcji kalorii z każdego makro plus gramy.
    ///
    /// Ta karta niczego nie pyta — jest odpowiedzią na to, o co pytaliśmy
    /// wcześniej. Bez niej krok 3 wyglądał tak, jakby wzrost i waga z kroku 1
    /// nigdzie nie poszły. Gramy rolują się razem z suwakiem celu, a paski
    /// zmieniają proporcje w miejscu.
    private func macroCard(_ macros: MacroTargets) -> some View {
        let total = max(macros.totalKcal, 1)

        return VStack(alignment: .leading, spacing: 14) {
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
        let percent = Int((share * 100).rounded())

        return VStack(alignment: .leading, spacing: 7) {
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
                    .foregroundStyle(Color.scLabel(colorScheme))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(grams)))
                Text("\(percent)%")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.scFaint(colorScheme))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(percent)))
                    .frame(minWidth: 30, alignment: .trailing)
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

#Preview("Dark") {
    StatefulPreviewContainer(diet: .none, kcal: 2300, allergens: []) { diet, kcal, allergens in
        ZStack {
            SCPageBackground(scheme: .dark).ignoresSafeArea()
            WelcomeStep3PreferencesView(diet: diet, calorieGoal: kcal, allergens: allergens)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Light") {
    StatefulPreviewContainer(diet: .vegetarian, kcal: 1900, allergens: [.gluten, .nuts]) { diet, kcal, allergens in
        ZStack {
            SCPageBackground(scheme: .light).ignoresSafeArea()
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
