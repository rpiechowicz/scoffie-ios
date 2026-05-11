import SwiftUI

// Welcome step 3 — Diet + daily kcal target. The slider sits between the
// design's 1200…3500 bounds with a 50 kcal step so the value lands on a
// recognisable number. The diet rows reuse the radio + accent-icon
// pattern from step 2 so the flow feels visually consistent.
struct WelcomeStep3PreferencesView: View {
    @Binding var diet: DietPreference
    @Binding var calorieGoal: Int
    @Binding var allergens: Set<Allergen>

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
            VStack(alignment: .leading, spacing: 18) {
                WelcomeStepHeader(
                    icon: "leaf.fill",
                    accent: WMPalette.terracotta,
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
                                                WMPalette.terracotta,
                                                WMPalette.terracottaDeep,
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
                                    .foregroundStyle(Color.wmLabel(colorScheme))
                                Text("Aplikacja podpowie, jak rozłożyć posiłki w ciągu dnia.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.wmMuted(colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(calorieGoal)")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundStyle(WMPalette.terracotta)
                                .monospacedDigit()
                                .contentTransition(.numericText(value: Double(calorieGoal)))
                                .animation(
                                    .spring(response: 0.28, dampingFraction: 0.86),
                                    value: calorieGoal
                                )
                            Text("kcal / dzień")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.wmMuted(colorScheme))
                        }

                        Slider(
                            value: Binding(
                                get: { Double(calorieGoal) },
                                set: { calorieGoal = Int($0.rounded()) }
                            ),
                            in: calorieRange,
                            step: calorieStep
                        )
                        .tint(WMPalette.terracotta)

                        HStack {
                            Text("1 200")
                            Spacer()
                            Text("3 500")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Color.wmMuted(colorScheme))
                        .monospacedDigit()
                    }
                    .padding(16)
                    .background(welcomeCardBackground)
                }

                VStack(alignment: .leading, spacing: 8) {
                    WelcomeFieldCaption(text: "Sposób odżywiania")
                    VStack(spacing: 0) {
                        ForEach(Array(DietPreference.allCases.enumerated()), id: \.element.id) { index, candidate in
                            DietRow(
                                candidate: candidate,
                                isSelected: candidate == diet,
                                onTap: {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                        diet = candidate
                                    }
                                }
                            )
                            if index < DietPreference.allCases.count - 1 {
                                Divider()
                                    .background(Color.wmRule(colorScheme).opacity(0.5))
                                    .padding(.leading, 60)
                            }
                        }
                    }
                    .background(welcomeCardBackground)
                }

                VStack(alignment: .leading, spacing: 8) {
                    WelcomeFieldCaption(text: "Alergeny i nietolerancje")
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Stuknij, aby zaznaczyć produkty, których chcesz unikać. Możesz wybrać dowolną liczbę.")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Color.wmMuted(colorScheme))
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
                    .background(welcomeCardBackground)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 140)
            .padding(.bottom, 170)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var welcomeCardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.wmTileBg(colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.wmTileStroke(colorScheme), lineWidth: 1)
            )
    }
}

private struct DietRow: View {
    let candidate: DietPreference
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    candidate.accent,
                                    candidate.accent.opacity(0.78),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    Image(systemName: candidate.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.wmLabel(colorScheme))
                    Text(candidate.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wmMuted(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                RadioDot(isSelected: isSelected)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct RadioDot: View {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(WMPalette.terracotta)
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(.white)
                    .frame(width: 8, height: 8)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle()
                    .stroke(Color.wmFaint(colorScheme), lineWidth: 1.8)
                    .frame(width: 22, height: 22)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isSelected)
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
            .foregroundStyle(isSelected ? .white : Color.wmLabel(colorScheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    isSelected
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [WMPalette.terracotta, WMPalette.terracotta.mix(black: 0.18)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        : AnyShapeStyle(Color.wmChipBg(colorScheme))
                )
            )
            .overlay(
                Capsule().stroke(
                    isSelected
                        ? WMPalette.terracotta.opacity(0.35)
                        : Color.wmTileStroke(colorScheme),
                    lineWidth: 1
                )
            )
            .shadow(
                color: WMPalette.terracotta.opacity(isSelected ? 0.20 : 0),
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
            WMPalette.canvasDark.ignoresSafeArea()
            WelcomeStep3PreferencesView(diet: diet, calorieGoal: kcal, allergens: allergens)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Light") {
    StatefulPreviewContainer(diet: .vegetarian, kcal: 1900, allergens: [.gluten, .nuts]) { diet, kcal, allergens in
        ZStack {
            WMPalette.canvasLight.ignoresSafeArea()
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
