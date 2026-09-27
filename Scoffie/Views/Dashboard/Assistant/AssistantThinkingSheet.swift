import SwiftUI

/// „Jak pracowałem” — przebieg tury krok po kroku, otwierany z podpisu
/// „✦ Myślałem 42 s ›” pod odpowiedzią (27.09.2026, Rafał: „historia, jak
/// asystent myślał, w połowicznym sheecie, step by step, co zrobił”).
///
/// Runda 2 tego samego dnia („header jest zbyt duży, i całą resztę też
/// dopracuj”): nagłówek kompaktowy (`EditorialSheetHeader(compact:)`), pod nim
/// dwie etykiety z faktami (kroki · zapisy), oś bez karty wokół — w półarkuszu
/// karta w karcie ściskała. Kolor mówi RODZAJ pracy: sprawdzanie (plan,
/// dom, bilans) — neutralny, dobieranie dań — terakota, przejście na
/// dokładne planowanie — indygo, zapis — szałwia. Kroki wchodzą kaskadą.
///
/// Kroki przychodzą z serwera gotowymi zdaniami (`AgentThinkingSummary.steps`,
/// także w historii) — bez kroków przejściowych. Nazwa narzędzia NIE wychodzi
/// na ekran; służy tylko do wyboru glifu i koloru.
struct AssistantThinkingSheet: View {
    let thinking: AgentThinkingSummary

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    private var title: String {
        thinking.duration.map { "Myślałem \(AssistantThoughtLine.clock($0))" } ?? "Myślałem chwilę"
    }

    private var writes: Int { thinking.steps.filter { $0.writes == true }.count }

    var body: some View {
        AssistantSheetScaffold(
            eyebrow: "Jak pracowałem",
            title: title,
            icon: "sparkles",
            compact: true,
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                facts
                    .scReveal(appeared, order: 0)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(thinking.steps.enumerated()), id: \.offset) { index, step in
                        ThinkingStepRow(
                            icon: ThinkingKind(step).icon(step),
                            text: step.label,
                            kind: ThinkingKind(step),
                            isFirst: index == 0,
                            isLast: false
                        )
                        .scReveal(appeared, order: index + 1)
                    }
                    ThinkingStepRow(
                        icon: "checkmark",
                        text: "Odpowiedź gotowa",
                        trailing: thinking.duration.map { AssistantThoughtLine.clock($0) },
                        kind: .done,
                        isFirst: thinking.steps.isEmpty,
                        isLast: true
                    )
                    .scReveal(appeared, order: thinking.steps.count + 1)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(40)
        .presentationBackground(Color.scPageBase(scheme))
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            appeared = true
        }
    }

    /// „5 kroków” · „Zapisałem w planie” — tylko to, co z przebiegu wynika.
    private var facts: some View {
        HStack(spacing: 6) {
            if !thinking.steps.isEmpty {
                SCTag(
                    title: "\(thinking.steps.count) \(Self.stepsWord(thinking.steps.count))",
                    icon: "list.bullet",
                    accent: AssistantLook.muted(scheme)
                )
            }
            if writes > 0 {
                SCTag(title: "Zapisałem zmiany", icon: "checkmark", accent: AssistantLook.sage(scheme))
            }
        }
    }

    static func stepsWord(_ count: Int) -> String {
        if count == 1 { return "krok" }
        let tens = count % 100
        let units = count % 10
        if (2...4).contains(units), !(12...14).contains(tens) { return "kroki" }
        return "kroków"
    }
}

/// Rodzaj pracy w kroku — kolor krążka i glif.
enum ThinkingKind: Equatable {
    case check, pick, handoff, write, done

    init(_ step: AgentProgressStepDTO) {
        if step.writes == true { self = .write; return }
        if step.isHandoff { self = .handoff; return }
        switch step.tool {
        case "get_household_context", "get_week_plan", "get_week_balance",
             "get_recipe_details", "check_plan_conflicts", "show_macro_gap",
             "show_shopping_list", "search_ingredients":
            self = .check
        default:
            self = .pick
        }
    }

    func tint(_ scheme: ColorScheme) -> Color {
        switch self {
        case .check: return AssistantLook.muted(scheme)
        case .pick: return AssistantLook.terra(scheme)
        case .handoff: return AssistantLook.indigo(scheme)
        case .write, .done: return AssistantLook.sage(scheme)
        }
    }

    func fill(_ scheme: ColorScheme) -> Color {
        switch self {
        case .check: return AssistantLook.quietTint(scheme)
        case .pick: return AssistantLook.terraTint(scheme)
        case .handoff: return AssistantLook.indigoTint(scheme)
        case .write, .done: return AssistantLook.sageTint(scheme)
        }
    }

    /// Glif rodzaju pracy — z nazwy narzędzia, której nie pokazujemy.
    func icon(_ step: AgentProgressStepDTO) -> String {
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

/// Wiersz osi: krążek z glifem, kreska łącząca z sąsiadami, zdanie,
/// opcjonalnie wartość po prawej (czas całości przy „Odpowiedź gotowa”).
private struct ThinkingStepRow: View {
    let icon: String
    let text: String
    var trailing: String? = nil
    let kind: ThinkingKind
    let isFirst: Bool
    let isLast: Bool

    @Environment(\.colorScheme) private var scheme

    private static let disc: CGFloat = 28
    private static let rowPadding: CGFloat = 7

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle().fill(kind.fill(scheme))
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(kind.tint(scheme))
            }
            .frame(width: Self.disc, height: Self.disc)
            .accessibilityHidden(true)

            Text(text)
                .font(.system(size: 15, weight: kind == .done ? .semibold : .regular))
                .tracking(-0.2)
                .foregroundStyle(kind == .done ? AssistantLook.sage(scheme) : AssistantLook.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let trailing {
                Text(trailing)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AssistantLook.faint(scheme))
            }
        }
        .padding(.vertical, Self.rowPadding)
        // Oś: kreska przez środek krążków, od sąsiada do sąsiada — nad
        // pierwszym i pod ostatnim jej nie ma.
        .background(alignment: .leading) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : AssistantLook.hair(scheme))
                    .frame(width: 1.5)
                Color.clear.frame(width: 1.5, height: Self.disc + 6)
                Rectangle()
                    .fill(isLast ? Color.clear : AssistantLook.hair(scheme))
                    .frame(width: 1.5)
            }
            .padding(.leading, Self.disc / 2 - 0.75)
        }
        .accessibilityElement(children: .combine)
    }
}
