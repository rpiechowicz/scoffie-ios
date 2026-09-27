import SwiftUI

/// „Jak pracowałem” — przebieg tury, otwierany z podpisu „✦ Myślałem 42 s ›”
/// pod odpowiedzią (27.09.2026).
///
/// Runda 5 (Rafał: „chcę tutaj serio pokazywać, co się działo, jak myślał —
/// »Odpowiedź gotowa« jest bez sensu, stare pozycje daj szare, bo wygląda to
/// zbyt cukierkowo”). Oś czasu z prawdziwych danych tury:
/// - krok = zdanie w czasie PRZESZŁYM z serwera (`done`, zapas: `label`),
///   pod nim fakty z wejścia i wyniku narzędzia (`detail`: „Kolacja · na
///   środę · lekkie — 3 z 38 pasujących”), po prawej sekunda tury („0:08”);
/// - przerwy między krokami, w których model myślał (≥ 2 s), są osobnymi,
///   cichymi wierszami „Przemyślałem wyniki · 6 s” na przerywanej osi — tak
///   widać, gdzie szedł czas;
/// - ostatni odcinek to „Napisałem odpowiedź · 4 s”;
/// - na końcu „Wynik” — to, co faktycznie wyszło (karta: nadtytuł i tytuł,
///   albo początek odpowiedzi), zamiast pustego „Odpowiedź gotowa”.
/// Wszystkie glify osi szare (neutralny krążek); kolor zostaje tylko w wyniku.
///
/// Nagłówek: tytuł = co tura zrobiła (`ThinkingHeadline`), stała ikona
/// przebiegu, czas kapsułką obok krzyżyka. Nazwa narzędzia NIE wychodzi na
/// ekran; służy tylko do wyboru glifu.
struct AssistantThinkingSheet: View {
    let thinking: AgentThinkingSummary
    /// Odpowiedź, której przebieg pokazujemy — z niej „Wynik”.
    var message: AgentChatMessage? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    private var headline: ThinkingHeadline { ThinkingHeadline(thinking.steps) }
    private var entries: [ThinkingEntry] { ThinkingEntry.timeline(thinking) }

    var body: some View {
        AssistantSheetScaffold(
            eyebrow: "Jak pracowałem",
            title: headline.title,
            // Kafelek mówi „przebieg”, nie ostatnie narzędzie (runda 4).
            icon: "point.3.filled.connected.trianglepath.dotted",
            compact: true,
            onClose: { dismiss() },
            action: { durationChip },
            footer: { EmptyView() }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    ThinkingRow(
                        entry: entry,
                        isFirst: index == 0,
                        isLast: index == entries.count - 1
                    )
                    .scReveal(appeared, order: min(index, 8))
                }

                if let result = ThinkingResult(message) {
                    EditorialSheetSectionLabel(title: "Wynik")
                        .padding(.top, 22)
                        .padding(.bottom, 10)
                        .scReveal(appeared, order: min(entries.count, 9))
                    resultCard(result)
                        .scReveal(appeared, order: min(entries.count, 9))
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
            try? await Task.sleep(for: .milliseconds(60))
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

    private func resultCard(_ result: ThinkingResult) -> some View {
        let shape = RoundedRectangle(cornerRadius: AssistantCardMetrics.listRadius, style: .continuous)
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(AssistantLook.terraTint(scheme))
                SCMarkShape()
                    .fill(AssistantLook.terraFill(scheme))
                    .frame(width: 13, height: 13)
            }
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                if let eyebrow = result.eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(AssistantLook.terra(scheme))
                        .lineLimit(1)
                }
                Text(result.title)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(AssistantLook.ink(scheme))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(shape.fill(Color.scTileBg(scheme)))
        .overlay(shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Oś czasu

/// Wpis osi: krok albo przerwa, w której model myślał / pisał.
enum ThinkingEntry {
    case step(AgentProgressStepDTO, offset: TimeInterval?)
    case pause(text: String, icon: String, seconds: TimeInterval)

    /// Najkrótsza przerwa warta wiersza — krótsze to szum strumienia.
    static let pauseThreshold: TimeInterval = 2

    static func timeline(_ thinking: AgentThinkingSummary) -> [ThinkingEntry] {
        let steps = thinking.steps
        let times: [Date?] = steps.map { AgentStore.parseTimestamp($0.at) }
        let start: Date? = thinking.startedAt ?? times.compactMap { $0 }.first
        var end: Date?
        if let start, let duration = thinking.duration {
            end = start.addingTimeInterval(duration)
        }

        guard !steps.isEmpty else {
            return [.pause(text: "Przemyślałem pytanie i napisałem odpowiedź", icon: "text.bubble", seconds: thinking.duration ?? 0)]
        }

        var entries: [ThinkingEntry] = []
        if let start, let first = times[0] {
            let gap = first.timeIntervalSince(start)
            if gap >= pauseThreshold {
                entries.append(.pause(text: "Zastanowiłem się, od czego zacząć", icon: "brain", seconds: gap))
            }
        }
        for (index, step) in steps.enumerated() {
            let at = times[index]
            var offset: TimeInterval?
            if let at, let start { offset = at.timeIntervalSince(start) }
            entries.append(.step(step, offset: offset))

            let isLastStep = index + 1 == steps.count
            let next: Date? = isLastStep ? end : times[index + 1]
            guard let at, let next else { continue }
            let gap = next.timeIntervalSince(at)
            if !isLastStep {
                if gap >= pauseThreshold {
                    entries.append(.pause(text: "Przemyślałem wyniki", icon: "brain", seconds: gap))
                }
            } else if gap >= 1 {
                entries.append(.pause(text: "Napisałem odpowiedź", icon: "text.bubble", seconds: gap))
            }
        }
        return entries
    }
}

private struct ThinkingRow: View {
    let entry: ThinkingEntry
    let isFirst: Bool
    let isLast: Bool

    @Environment(\.colorScheme) private var scheme

    private static let disc: CGFloat = 28
    private static let pauseMark: CGFloat = 20

    private var isPause: Bool {
        if case .pause = entry { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            marker
            content
        }
        .padding(.vertical, isPause ? 5 : 8)
        .background(alignment: .leading) { axis }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var marker: some View {
        switch entry {
        case let .step(step, _):
            ZStack {
                Circle().fill(Color.scPageBase(scheme))
                Circle().fill(AssistantLook.quietTint(scheme))
                Image(systemName: ThinkingKind.icon(step))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AssistantLook.muted(scheme))
            }
            .frame(width: Self.disc, height: Self.disc)
            .accessibilityHidden(true)
        case let .pause(_, icon, _):
            ZStack {
                Capsule().fill(Color.scPageBase(scheme)).frame(width: 18)
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AssistantLook.faint(scheme))
            }
            .frame(width: Self.disc, height: Self.pauseMark)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch entry {
        case let .step(step, offset):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(step.done ?? step.label)
                        .font(.system(size: 15, weight: .medium))
                        .tracking(-0.2)
                        .foregroundStyle(AssistantLook.ink(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = step.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 13))
                            .lineSpacing(1)
                            .foregroundStyle(AssistantLook.muted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

                if let offset {
                    Text(Self.stamp(offset))
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(AssistantLook.faint(scheme))
                        .padding(.top, 5)
                }
            }
        case let .pause(text, _, seconds):
            Text("\(text) · \(AssistantThoughtLine.clock(seconds))")
                .font(.system(size: 13))
                .foregroundStyle(AssistantLook.faint(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
    }

    /// Oś: kreska przez środek znaczników, od sąsiada do sąsiada. Przy
    /// przerwach przerywana — to czas bez kroku.
    private var axis: some View {
        VStack(spacing: 0) {
            segment(visible: !isFirst)
                .frame(height: isPause ? 5 : 8)
            Color.clear.frame(height: isPause ? Self.pauseMark : Self.disc)
            segment(visible: !isLast)
        }
        .frame(width: 2)
        .padding(.leading, Self.disc / 2 - 1)
    }

    @ViewBuilder
    private func segment(visible: Bool) -> some View {
        if !visible {
            Color.clear
        } else if isPause {
            AxisLine()
                .stroke(AssistantLook.hair(scheme), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
        } else {
            AxisLine()
                .stroke(AssistantLook.hair(scheme), lineWidth: 1.5)
        }
    }

    /// „0:08”, „1:12” — sekunda tury, w której krok ruszył.
    static func stamp(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

/// Pionowa linia przez środek ramki — oś przebiegu.
private struct AxisLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

// MARK: - Wynik

/// Co faktycznie wyszło z tury — z karty (nadtytuł + tytuł) albo z tekstu.
struct ThinkingResult {
    let eyebrow: String?
    let title: String

    init?(_ message: AgentChatMessage?) {
        guard let message else { return nil }
        guard let card = message.card else {
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            eyebrow = "Odpowiedź"
            title = text
            return
        }
        switch card {
        case let .planWeek(card):
            eyebrow = card.eyebrow ?? "Propozycja tygodnia"
            title = card.title
        case let .planDay(card):
            eyebrow = card.eyebrow ?? "Propozycja dnia"
            if let detail = card.eyebrowDetail, !detail.isEmpty {
                title = String(detail.prefix(1)).uppercased() + String(detail.dropFirst()) + " · " + card.title
            } else {
                title = card.title
            }
        case let .options(card):
            eyebrow = card.eyebrow
            title = card.title
        case let .swap(card):
            eyebrow = card.eyebrow
            title = card.title
        case let .removeMeal(card):
            eyebrow = card.eyebrow
            title = card.title
        case let .householdSplit(card):
            eyebrow = card.eyebrow
            title = card.title
        case let .macroGap(card):
            eyebrow = card.eyebrow
            title = card.title
        case let .shoppingList(card):
            eyebrow = card.eyebrow
            title = card.title
        case let .clarify(card):
            eyebrow = "Pytanie do Ciebie"
            title = card.question
        case let .applied(card):
            eyebrow = "Zapisane w planie"
            title = card.title
        case .unknown:
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            eyebrow = "Odpowiedź"
            title = text
        }
    }
}

// MARK: - Tytuł

/// Tytuł arkusza — NAJWAŻNIEJSZA rzecz, którą tura zrobiła, po priorytecie:
/// zapis > plan > zamiana > dania > reszta > samo sprawdzanie.
struct ThinkingHeadline {
    let title: String

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
        for entry in Self.priority where steps.contains(where: { entry.tools.contains($0.tool) }) {
            title = entry.title
            return
        }
        title = steps.isEmpty ? "Odpowiedziałem od razu" : "Sprawdziłem plan"
    }
}

/// Glif rodzaju pracy — z nazwy narzędzia, której nie pokazujemy.
enum ThinkingKind {
    static func icon(_ step: AgentProgressStepDTO) -> String {
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
