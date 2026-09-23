import SwiftUI

// Welcome step 2 — Goal & activity. The user picks one of five goals and
// declares their training frequency (1–4). Tapping a row updates state
// optimistically; the WelcomeView pushes the result to the backend on
// "Dalej". Selection markers animate with a spring so the radio dot pops
// in instead of snapping.
struct WelcomeStep2GoalView: View {
    @Binding var goal: UserGoal
    @Binding var activity: ActivityLevel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: WelcomeLayout.sectionSpacing) {
                WelcomeStepHeader(
                    icon: "target",
                    accent: SCPalette.terracotta,
                    eyebrow: "Twój cel",
                    title: "Co chcesz osiągnąć?",
                    subtitle: "Wybierz to, co najbardziej do Ciebie pasuje. Pomoże nam dobrać propozycje i kalorie."
                )

                VStack(alignment: .leading, spacing: 8) {
                    WelcomeFieldCaption(text: "Główny cel")
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

                VStack(alignment: .leading, spacing: 8) {
                    WelcomeFieldCaption(text: "Treningi w tygodniu")
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
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
                                    .frame(width: 30, height: 30)
                                Image(systemName: "figure.run")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            Text("Ile razy w tygodniu trenujesz?")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.scLabel(colorScheme))
                        }

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
                    .padding(16)
                    .welcomeCard()
                }
            }
            .padding(.horizontal, WelcomeLayout.horizontal)
            .padding(.top, WelcomeLayout.topInset)
            .padding(.bottom, WelcomeLayout.bottomInset)
        }
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
            VStack(spacing: 6) {
                Text(level.label)
                    .font(.system(size: 18, weight: .bold))
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
            // w wariancie „soft”, bez gradientu i bez cienia.
            .scChoiceSurface(RoundedRectangle(cornerRadius: 12, style: .continuous), isOn: isSelected)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Dark") {
    StatefulPreviewContainer(initialGoal: .healthy, initialActivity: .active) { goal, activity in
        ZStack {
            SCPalette.canvasDark.ignoresSafeArea()
            WelcomeStep2GoalView(goal: goal, activity: activity)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Light") {
    StatefulPreviewContainer(initialGoal: .lose, initialActivity: .light) { goal, activity in
        ZStack {
            SCPalette.canvasLight.ignoresSafeArea()
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
