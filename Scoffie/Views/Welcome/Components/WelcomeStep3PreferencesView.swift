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
                WelcomeHeader(
                    icon: "flame.fill",
                    eyebrow: "Dieta i kalorie",
                    title: "Ile i co jesz?",
                    subtitle: "Cel policzyliśmy z Twoich danych. Jeśli czujesz, że to za dużo albo za mało, przesuń suwak — i powiedz nam, czego nie jesz."
                )

                // Cel i jego rozkład na makro w JEDNEJ karcie (24.09.2026),
                // jak liczby dania w szczegółach i w wyborze posiłku: najpierw
                // kcal, pod nimi pasek proporcji z legendą. Dawniej osobna
                // sekcja z trzema paskami, każdy na swoim torze.
                WelcomeSection(
                    title: "Dzienny cel",
                    hint: "Suma ze wszystkich posiłków w ciągu dnia — i jak rozłożymy ją na białko, węglowodany i tłuszcze."
                ) {
                    calorieCard
                }

                WelcomeSection(title: "Sposób odżywiania", hint: "Przepisy i propozycje asystenta będą trzymać się tej diety.") {
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

                // Powód pada tu jeszcze raz, choć był na ostatnim ekranie
                // przewodnika — kto go pominął, dopiero tu dowiaduje się, co
                // zaznaczenie zmienia (24.09.2026, „więcej opisu”).
                WelcomeSection(
                    title: "Alergeny i nietolerancje",
                    hint: "Przepisy z tymi składnikami schowamy — nie trafią do planu ani na listę zakupów."
                ) {
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

            if let macros {
                Rectangle()
                    .fill(Color.scRule(colorScheme))
                    .frame(height: 1)
                    .padding(.vertical, 4)
                macroSplit(macros)
            }
        }
        .padding(16)
        .welcomeCard()
    }

    /// Rozkład celu na makro: jeden pasek podzielony w proporcji kalorii
    /// z każdego makro i legenda z gramami — ten sam idiom, co liczby dania
    /// w wyborze posiłku i w szczegółach, w kolorach `SCMacroPalette`
    /// (Ustawienia, „Cel dnia”).
    ///
    /// Ta część karty niczego nie pyta — jest odpowiedzią na to, o co
    /// pytaliśmy wcześniej. Bez niej krok 3 wyglądał tak, jakby wzrost i waga
    /// z kroku 1 nigdzie nie poszły. Gramy rolują się razem z suwakiem celu,
    /// a odcinki zmieniają proporcje w miejscu.
    private func macroSplit(_ macros: MacroTargets) -> some View {
        let parts: [(title: String, grams: Int, kcal: Int, color: Color)] = [
            ("białko", macros.proteinG, macros.proteinKcal, SCMacroPalette.protein),
            ("węglowodany", macros.carbsG, macros.carbsKcal, SCMacroPalette.carbs),
            ("tłuszcze", macros.fatG, macros.fatKcal, SCMacroPalette.fat),
        ]
        let total = max(1, parts.reduce(0) { $0 + $1.kcal })

        return VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let gap: CGFloat = 3
                let free = max(0, proxy.size.width - gap * CGFloat(parts.count - 1))
                HStack(spacing: gap) {
                    ForEach(parts, id: \.title) { part in
                        Capsule(style: .continuous)
                            .fill(part.color)
                            .frame(width: max(6, free * CGFloat(part.kcal) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 8)

            HStack(spacing: 0) {
                ForEach(parts, id: \.title) { part in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(part.grams)")
                                .font(.system(size: 17, weight: .heavy))
                                .monospacedDigit()
                                .foregroundStyle(Color.scLabel(colorScheme))
                                .contentTransition(.numericText(value: Double(part.grams)))
                            Text("g")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Color.scMuted(colorScheme))
                        }
                        HStack(spacing: 5) {
                            Circle()
                                .fill(part.color)
                                .frame(width: 7, height: 7)
                            Text(part.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.scMuted(colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(part.title): \(part.grams) gramów")
                }
            }
        }
        .animation(.smooth(duration: 0.22), value: macros)
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
