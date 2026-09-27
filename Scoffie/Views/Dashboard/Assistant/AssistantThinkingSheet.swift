import SwiftUI

/// „Jak pracowałem” — przebieg tury krok po kroku, otwierany z podpisu
/// „✦ Myślałem 42 s” pod odpowiedzią (27.09.2026, Rafał: „historia, jak
/// asystent myślał, w połowicznym sheecie, step by step, co zrobił”).
///
/// Kroki przychodzą z serwera gotowymi zdaniami (`AgentThinkingSummary.steps`,
/// także w historii) — bez kroków przejściowych, bo po turze mówiłyby to samo
/// co sąsiedni wiersz. Nazwa narzędzia NIE wychodzi na ekran; służy tylko do
/// wyboru glifu. Krok, który zmienił dane domu (`writes`), jest w szałwii.
/// Na końcu „Odpowiedź gotowa” — ten sam czas, co w podpisie.
struct AssistantThinkingSheet: View {
    let thinking: AgentThinkingSummary

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private var title: String {
        thinking.duration.map { "Myślałem \(AssistantThoughtLine.clock($0))" } ?? "Myślałem chwilę"
    }

    var body: some View {
        AssistantSheetScaffold(
            eyebrow: "Jak pracowałem",
            title: title,
            icon: "sparkles",
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(thinking.steps.enumerated()), id: \.offset) { index, step in
                    ThinkingStepRow(
                        icon: Self.icon(for: step),
                        text: step.label,
                        tone: step.writes == true ? .sage : .terra,
                        isFirst: index == 0,
                        isLast: false
                    )
                }
                ThinkingStepRow(
                    icon: "checkmark",
                    text: "Odpowiedź gotowa",
                    tone: .sage,
                    isFirst: thinking.steps.isEmpty,
                    isLast: true
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AssistantCardMetrics.listRadius, style: .continuous)
                    .fill(AssistantLook.card(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AssistantCardMetrics.listRadius, style: .continuous)
                    .strokeBorder(AssistantLook.cardStroke(scheme), lineWidth: 1)
            )
            .padding(.top, 4)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(40)
        .presentationBackground(Color.scPageBase(scheme))
    }

    /// Glif rodzaju pracy — z nazwy narzędzia, której nie pokazujemy.
    static func icon(for step: AgentProgressStepDTO) -> String {
        if step.isHandoff { return "wand.and.stars" }
        switch step.tool {
        case "get_household_context": return "house"
        case "get_week_plan": return "calendar"
        case "get_week_balance", "show_macro_gap": return "chart.bar"
        case "get_recipe_details": return "book"
        case "find_recipes": return "magnifyingglass"
        case "search_ingredients": return "carrot"
        case "ask_clarifying_question": return "questionmark.bubble"
        case "propose_week_plan", "build_meal_plan": return "calendar.badge.plus"
        case "propose_day_plan": return "sun.max"
        case "propose_swap", "replace_plan_item", "revise_proposal": return "arrow.triangle.2.circlepath"
        case "propose_remove_meal": return "minus.circle"
        case "propose_household_split": return "person.2"
        case "offer_options", "suggest_meals": return "fork.knife"
        case "check_plan_conflicts": return "checkmark.shield"
        case "show_shopping_list", "check_shopping_items": return "cart"
        case "remember_note": return "brain.head.profile"
        case "mark_meal_eaten": return "checkmark.circle"
        case "apply_week_plan": return "square.and.arrow.down"
        case "create_recipe", "update_recipe": return "square.and.pencil"
        case "delete_recipe": return "trash"
        default: return "sparkle"
        }
    }
}

/// Wiersz osi: krążek z glifem, kreska łącząca z sąsiadami, zdanie.
private struct ThinkingStepRow: View {
    enum Tone { case terra, sage }

    let icon: String
    let text: String
    let tone: Tone
    let isFirst: Bool
    let isLast: Bool

    @Environment(\.colorScheme) private var scheme

    private static let disc: CGFloat = 30

    private var tint: Color {
        tone == .sage ? AssistantLook.sage(scheme) : AssistantLook.terra(scheme)
    }

    private var fill: Color {
        tone == .sage ? AssistantLook.sageTint(scheme) : AssistantLook.terraTint(scheme)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle().fill(fill)
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: Self.disc, height: Self.disc)
            .accessibilityHidden(true)

            Text(text)
                .font(.system(size: 15, weight: isLast ? .semibold : .regular))
                .foregroundStyle(isLast ? AssistantLook.sage(scheme) : AssistantLook.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
        // Oś: kreska przez środek krążków, od sąsiada do sąsiada — nad
        // pierwszym i pod ostatnim jej nie ma.
        .background(alignment: .leading) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : AssistantLook.hair(scheme))
                    .frame(width: 1.5)
                Color.clear.frame(width: 1.5, height: Self.disc)
                Rectangle()
                    .fill(isLast ? Color.clear : AssistantLook.hair(scheme))
                    .frame(width: 1.5)
            }
            .padding(.leading, Self.disc / 2 - 0.75)
        }
        .accessibilityElement(children: .combine)
    }
}
