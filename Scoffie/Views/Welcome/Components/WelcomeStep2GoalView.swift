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
            VStack(alignment: .leading, spacing: 18) {
                WelcomeStepHeader(
                    icon: "target",
                    accent: WMPalette.terracotta,
                    eyebrow: "Twój cel",
                    title: "Co chcesz osiągnąć?",
                    subtitle: "Wybierz to, co najbardziej do Ciebie pasuje. Pomoże nam dobrać propozycje i kalorie."
                )

                VStack(alignment: .leading, spacing: 8) {
                    WelcomeFieldCaption(text: "Główny cel")
                    VStack(spacing: 0) {
                        ForEach(Array(UserGoal.allCases.enumerated()), id: \.element.id) { index, candidate in
                            GoalRow(
                                candidate: candidate,
                                isSelected: candidate == goal,
                                onTap: {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                        goal = candidate
                                    }
                                }
                            )
                            if index < UserGoal.allCases.count - 1 {
                                Divider()
                                    .background(Color.wmRule(colorScheme).opacity(0.5))
                                    .padding(.leading, 56)
                            }
                        }
                    }
                    .background(welcomeCardBackground)
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
                                                WMPalette.terracotta,
                                                WMPalette.terracottaDeep,
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
                                .foregroundStyle(Color.wmLabel(colorScheme))
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
                    .background(welcomeCardBackground)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 140)
            .padding(.bottom, 200)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var welcomeCardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.wmTileBg(colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.wmTileStroke(colorScheme), lineWidth: 1)
            )
    }
}

private struct GoalRow: View {
    let candidate: UserGoal
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
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
                        .frame(width: 30, height: 30)
                    Image(systemName: candidate.icon)
                        .font(.system(size: 14, weight: .semibold))
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
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .foregroundStyle(isSelected ? Color.white : Color.wmLabel(colorScheme))
                Text(level.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.wmMuted(colorScheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.horizontal, 4)
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
            .shadow(color: WMPalette.terracotta.opacity(isSelected ? 0.18 : 0), radius: 8, x: 0, y: 4)
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
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(.white)
                    .frame(width: 7, height: 7)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle()
                    .stroke(Color.wmFaint(colorScheme), lineWidth: 1.8)
                    .frame(width: 20, height: 20)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isSelected)
    }
}

#Preview("Dark") {
    StatefulPreviewContainer(initialGoal: .healthy, initialActivity: .active) { goal, activity in
        ZStack {
            WMPalette.canvasDark.ignoresSafeArea()
            WelcomeStep2GoalView(goal: goal, activity: activity)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Light") {
    StatefulPreviewContainer(initialGoal: .lose, initialActivity: .light) { goal, activity in
        ZStack {
            WMPalette.canvasLight.ignoresSafeArea()
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
