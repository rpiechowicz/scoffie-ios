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
/// Runda 3 („header do poprawy, po prawej daj czas, daj jakiś unikalny
/// title”): tytuł mówi, CO asystent zrobił w tej turze (`ThinkingHeadline`:
/// „Ułożyłem plan”, „Dobrałem dania”, „Znalazłem zamiennik”…), kafelek ma
/// glif i kolor tej pracy, a czas stoi kapsułką obok krzyżyka. Etykiety
/// z faktami pod nagłówkiem odpadły — tytuł i czas mówią to samo.
///
/// Kroki przychodzą z serwera gotowymi zdaniami (`AgentThinkingSummary.steps`,
/// także w historii) — bez kroków przejściowych. Nazwa narzędzia NIE wychodzi
/// na ekran; służy tylko do wyboru glifu i koloru.
struct AssistantThinkingSheet: View {
    let thinking: AgentThinkingSummary

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    private var headline: ThinkingHeadline { ThinkingHeadline(thinking.steps) }

    var body: some View {
        AssistantSheetScaffold(
            eyebrow: "Jak pracowałem",
            title: headline.title,
            icon: headline.icon,
            accent: headline.kind.tint(scheme),
            compact: true,
            onClose: { dismiss() },
            action: { durationChip },
            footer: { EmptyView() }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(thinking.steps.enumerated()), id: \.offset) { index, step in
                        ThinkingStepRow(
                            icon: ThinkingKind(step).icon(step),
                            text: step.label,
                            kind: ThinkingKind(step),
                            isFirst: index == 0,
                            isLast: false
                        )
                        .scReveal(appeared, order: index)
                    }
                    ThinkingStepRow(
                        icon: "checkmark",
                        text: "Odpowiedź gotowa",
                        kind: .done,
                        isFirst: thinking.steps.isEmpty,
                        isLast: true
                    )
                    .scReveal(appeared, order: thinking.steps.count)
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

    /// Czas tury obok krzyżyka — w wysokości krążka zamykania.
    @ViewBuilder
    private var durationChip: some View {
        if let duration = thinking.duration {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .bold))
                Text(AssistantThoughtLine.clock(duration))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(AssistantLook.muted(scheme))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule(style: .continuous).fill(AssistantLook.quietTint(scheme)))
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Czas odpowiedzi: \(AssistantThoughtLine.clock(duration))")
        }
    }
}

/// Tytuł arkusza — NAJWAŻNIEJSZA rzecz, którą tura zrobiła, po priorytecie:
/// zapis > plan > zamiana > dania > reszta > samo sprawdzanie. Glif i kolor
/// idą za tym samym krokiem.
struct ThinkingHeadline {
    let title: String
    let icon: String
    let kind: ThinkingKind

    private static let priority: [(tools: Set<String>, title: String)] = [
        (["apply_week_plan"], "Zapisałem w planie"),
        (["create_recipe", "update_recipe", "delete_recipe"], "Zapisałem przepis"),
        (["mark_meal_eaten"], "Odhaczyłem posiłek"),
        (["check_shopping_items"], "Odhaczyłem zakupy"),
        (["build_meal_plan", "propose_week_plan", "propose_day_plan", "start_planning"], "Ułożyłem plan"),
        (["propose_swap", "replace_plan_item", "revise_proposal"], "Znalazłem zamiennik"),
        (["propose_household_split"], "Podzieliłem porcje"),
        (["propose_remove_meal"], "Przygotowałem zmianę"),
        (["suggest_meals", "offer_options", "find_recipes"], "Dobrałem dania"),
        (["ask_clarifying_question"], "Dopytałem o szczegóły"),
        (["show_shopping_list"], "Sprawdziłem zakupy"),
        (["show_macro_gap", "get_week_balance"], "Policzyłem bilans"),
        (["remember_note"], "Zapamiętałem"),
    ]

    init(_ steps: [AgentProgressStepDTO]) {
        for entry in Self.priority {
            if let step = steps.last(where: { entry.tools.contains($0.tool) }) {
                let kind = ThinkingKind(step)
                title = entry.title
                icon = kind.icon(step)
                self.kind = kind
                return
            }
        }
        if let step = steps.last {
            title = "Sprawdziłem plan"
            icon = ThinkingKind(step).icon(step)
            kind = .check
        } else {
            title = "Odpowiedziałem od razu"
            icon = "sparkles"
            kind = .pick
        }
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

/// Wiersz osi: krążek z glifem, kreska łącząca z sąsiadami, zdanie.
private struct ThinkingStepRow: View {
    let icon: String
    let text: String
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
