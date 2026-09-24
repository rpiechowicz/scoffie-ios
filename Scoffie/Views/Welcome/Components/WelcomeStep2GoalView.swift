import SwiftUI

// Kreator, krok 2 — cel i aktywność. Jeden z pięciu celów (te same wiersze,
// co w Ustawieniach → „Dieta i alergeny”) i liczba treningów w tygodniu.
// Wybór zmienia stan od razu; `WelcomeView` wysyła go na serwer przy „Dalej”.
struct WelcomeStep2GoalView: View {
    @Binding var goal: UserGoal
    @Binding var activity: ActivityLevel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: WelcomeLayout.sectionSpacing) {
                WelcomeHeader(
                    icon: "target",
                    eyebrow: "Twój cel",
                    title: "Co chcesz osiągnąć?",
                    subtitle: "Od tego zależy Twój dzienny cel kalorii i przepisy, które podsuniemy jako pierwsze. Cel zmienisz w każdej chwili w Ustawieniach."
                )

                WelcomeSection(title: "Główny cel", hint: "Wybierz to, co jest dla Ciebie teraz najważniejsze.") {
                    VStack(spacing: 0) {
                        ForEach(Array(UserGoal.allCases.enumerated()), id: \.element.id) { index, candidate in
                            WelcomeOptionRow(
                                icon: candidate.icon,
                                accent: candidate.accent,
                                title: candidate.title,
                                subtitle: candidate.subtitle,
                                isSelected: candidate == goal,
                                onTap: {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                        goal = candidate
                                    }
                                }
                            )
                            if index < UserGoal.allCases.count - 1 {
                                WelcomeOptionDivider()
                            }
                        }
                    }
                    .welcomeCard()
                }

                // Same chipy, bez karty z ikoną i pytaniem „Ile razy
                // w tygodniu trenujesz?” — etykieta sekcji mówi to samo.
                WelcomeSection(title: "Treningi w tygodniu", hint: "Siłownia, bieganie, rower, basen — liczy się każdy. Więcej ruchu to wyższy cel.") {
                    HStack(spacing: 8) {
                        ForEach(ActivityLevel.allCases) { candidate in
                            ActivityChip(
                                level: candidate,
                                isSelected: candidate == activity,
                                onTap: {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                        activity = candidate
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, WelcomeLayout.horizontal)
            .padding(.top, WelcomeLayout.topInset)
            .padding(.bottom, WelcomeLayout.bottomInset)
        }
        .scScrollEdgeFade()
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct ActivityChip: View {
    let level: ActivityLevel
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                Text(level.label)
                    .font(.system(size: 18, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? SCPalette.terracotta : Color.scLabel(colorScheme))
                Text(level.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? SCPalette.terracotta.opacity(0.85) : Color.scMuted(colorScheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.horizontal, 4)
            .padding(.vertical, 12)
            // Ten sam chip co w „Twoich danych” w Ustawieniach: wybór
            // w wariancie „soft”, bez gradientu i bez cienia. Niewybrany na
            // tle karty (`scTileBg`), bo stoi wprost na stronie.
            .scChoiceSurface(
                RoundedRectangle(cornerRadius: 14, style: .continuous),
                isOn: isSelected,
                offFill: Color.scTileBg(colorScheme)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(level.label) treningów w tygodniu, \(level.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Dark") {
    StatefulPreviewContainer(initialGoal: .healthy, initialActivity: .active) { goal, activity in
        ZStack {
            SCPageBackground(scheme: .dark).ignoresSafeArea()
            WelcomeStep2GoalView(goal: goal, activity: activity)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Light") {
    StatefulPreviewContainer(initialGoal: .lose, initialActivity: .light) { goal, activity in
        ZStack {
            SCPageBackground(scheme: .light).ignoresSafeArea()
            WelcomeStep2GoalView(goal: goal, activity: activity)
        }
        .preferredColorScheme(.light)
    }
}

private struct StatefulPreviewContainer<Content: View>: View {
    @State private var goal: UserGoal
    @State private var activity: ActivityLevel
    let content: (Binding<UserGoal>, Binding<ActivityLevel>) -> Content

    init(
        initialGoal: UserGoal,
        initialActivity: ActivityLevel,
        @ViewBuilder content: @escaping (Binding<UserGoal>, Binding<ActivityLevel>) -> Content
    ) {
        _goal = State(initialValue: initialGoal)
        _activity = State(initialValue: initialActivity)
        self.content = content
    }

    var body: some View {
        content($goal, $activity)
    }
}
