import SwiftUI

/// Co zrobić z daniem, które ktoś z wybranego „Dla kogo” już ma w tej porze.
enum PlanSlotConflictChoice: Hashable {
    /// Nowe danie zastępuje tamto — tym osobom, które je dostają.
    case replace
    /// Oba dania zostają obok siebie w porze.
    case addBeside
}

/// Karta w stopce „Wybierz przepis”, gdy wybrane danie trafi do pory,
/// w której ktoś z „Dla kogo” ma już INNE danie (27.09.2026, Rafał: „wybieram
/// posiłek1 dla user1, potem posiłek2 dla całego domu — to powinno być dla
/// obu to samo, czy tylko dla user2?” → wariant „karta z wyborem”).
///
/// Strój karty „ZAMIENISZ” z „Dodaj do planu” (`AddToPlanSheet`): zdjęcie
/// dania, które już stoi, eyebrow w kolorze pory („OBIAD · ANIA MA JUŻ”),
/// nazwa — a pod spodem przełącznik „Zamień dla wszystkich / Dodaj obok”.
/// Domyślnie zamiana: „Wspólne” znaczy, że wszyscy jedzą to samo. Tytuł
/// przycisku pod kartą idzie za wyborem („Zamień w planie” / „Dodaj do
/// planu”), więc przed stuknięciem widać, co się stanie.
struct PlanSlotConflictCard: View {
    let slot: MealSlot
    /// Dania, które już stoją w porze dla kogoś z wybranych — pierwsze
    /// pokazujemy, resztę liczymy („+1”).
    let meals: [PlanMeal]
    /// „ANIA MA JUŻ”, „CAŁY DOM MA JUŻ”, „MASZ JUŻ”.
    let whoHasIt: String
    /// Wybrany cały dom — „Zamień dla wszystkich”, inaczej samo „Zamień”.
    let replacesForEveryone: Bool
    @Binding var choice: PlanSlotConflictChoice

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let accent = slot.cozyAccent

        VStack(alignment: .leading, spacing: 10) {
            if let first = meals.first {
                HStack(spacing: 10) {
                    EditorialRecipeCover(recipe: first.recipe, size: 36, cornerRadius: 10)
                        .id(first.recipe.id)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(slot.title.uppercased()) · \(whoHasIt)")
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text(meals.count > 1 ? "\(first.recipe.name) +\(meals.count - 1)" : first.recipe.name)
                            .font(.system(size: 14, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(Color.scLabel(scheme))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: 4) {
                segment(
                    .replace,
                    title: replacesForEveryone ? "Zamień dla wszystkich" : "Zamień",
                    icon: "arrow.triangle.2.circlepath",
                    accent: accent
                )
                segment(.addBeside, title: "Dodaj obok", icon: "plus", accent: accent)
            }
            .padding(3)
            .background(Capsule(style: .continuous).fill(Color.scChipBg(scheme)))
        }
        .padding(10)
        .background(shape.fill(Color.scTileBg(scheme)))
        .overlay(shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
        .animation(.smooth(duration: 0.22), value: choice)
        .accessibilityElement(children: .contain)
    }

    private func segment(
        _ value: PlanSlotConflictChoice,
        title: String,
        icon: String,
        accent: Color
    ) -> some View {
        let isOn = choice == value
        return Button {
            choice = value
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isOn ? accent : Color.scMuted(scheme))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background {
                if isOn {
                    Capsule(style: .continuous)
                        .fill(Color.clear)
                        .scSoftCapsule(accent)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
