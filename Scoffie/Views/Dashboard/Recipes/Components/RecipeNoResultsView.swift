import SwiftUI

/// Pusto w wynikach Przepisów (Rafał 4.10.2026: „pusty stan w niepasujących
/// przepisach popraw, nie podoba mi się”). Bez karty — jak „Brak wyników”
/// w aplikacjach Apple: szklany krążek z ikoną powodu, który delikatnie
/// podskakuje przy wejściu, krótki tytuł z frazą, jedno zdanie i akcje
/// w szkle. Pierwsza akcja (najbardziej pomocna — np. „Pokaż 4 w innych
/// kategoriach”) w tincie terakoty, reszta neutralna.
struct RecipeNoResultsView: View {
    struct Action: Identifiable {
        let title: String
        let icon: String
        let run: () -> Void
        var id: String { title }
    }

    let icon: String
    var accent: Color = SCPalette.terracotta
    let title: String
    let message: String
    var actions: [Action] = []

    @Environment(\.colorScheme) private var scheme
    @State private var bounce = 0

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(accent)
                .symbolEffect(.bounce, value: bounce)
                .frame(width: 76, height: 76)
                .scChromeGlass(in: Circle(), tint: accent.opacity(scheme == .dark ? 0.22 : 0.14))
                .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.06), radius: 10, x: 0, y: 4)

            Text(title)
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(Color.scLabel(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            Text(message)
                .font(.system(size: 14.5))
                .foregroundStyle(Color.scMuted(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 290)
                .padding(.top, 6)

            if !actions.isEmpty {
                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 10) {
                        ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                            actionButton(action, isPrimary: index == 0)
                        }
                    }
                }
                .padding(.top, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
        .padding(.horizontal, 20)
        .task {
            try? await Task.sleep(for: .milliseconds(180))
            bounce += 1
        }
    }

    private func actionButton(_ action: Action, isPrimary: Bool) -> some View {
        Button(action: action.run) {
            HStack(spacing: 7) {
                Image(systemName: action.icon)
                    .font(.system(size: 13, weight: .bold))
                Text(action.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isPrimary ? SCPalette.terracotta : Color.scLabel(scheme))
            .padding(.horizontal, 18)
            .frame(height: 44)
            .scChromeGlass(
                in: Capsule(style: .continuous),
                tint: isPrimary ? SCPalette.terracotta.opacity(scheme == .dark ? 0.3 : 0.22) : nil
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.95))
    }
}
