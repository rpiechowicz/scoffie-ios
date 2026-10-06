import SwiftUI

/// „Jak pracowałem” — przebieg tury, otwierany z podpisu „✦ Myślałem 42 s ›”
/// pod odpowiedzią (27.09.2026).
///
/// Oś czasu z prawdziwych danych tury — wiersz na AKCJĘ asystenta (runda 8,
/// `ThinkingEntry`): zdanie w czasie przeszłym z serwera (`done`), pod nim
/// fakty z wejścia i wyniku narzędzia (`detail`), po prawej ile trwała —
/// od swojego początku do początku następnej, więc suma = czas w nagłówku.
/// Bez „Napisałem odpowiedź”, „Wyniku” i wierszy przerw; glify szare.
///
/// Nagłówek: tytuł = co tura zrobiła (`ThinkingHeadline`), stała ikona
/// przebiegu, czas kapsułką obok krzyżyka. Nazwa narzędzia NIE wychodzi na
/// ekran; służy tylko do wyboru glifu.
struct AssistantThinkingSheet: View {
    let thinking: AgentThinkingSummary

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
            }
            .padding(.horizontal, 4)
            // Oddech pod nagłówkiem — oś nie klei się do tytułu.
            .padding(.top, 14)
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
                    .font(.sc(size: 11, weight: .bold))
                Text(AssistantThoughtLine.clock(duration))
                    .font(.sc(size: 13, weight: .semibold))
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

// MARK: - Oś czasu

/// Wiersz osi = JEDNA akcja asystenta (runda 8, Rafał: „wszystkie w czasie
/// przeszłym, po prawej czas, nie może się powielać czynność… każda taka
/// sama jak »układam ten dzień« — ikona, tekst i czas po prawej, a suma czasów
/// ma być taka jak w nagłówku”; „napisałem odpowiedź — nie pokazuj, nic nie
/// wnosi”).
///
/// Akcja trwa od swojego początku do początku następnej — pierwsza od startu
/// tury (myślenie przed nią to część jej pracy), ostatnia do końca tury
/// (pisanie odpowiedzi też). Granice zaokrąglone do sekundy PRZED odjęciem,
/// więc suma wierszy = czas w nagłówku co do sekundy. Bez osobnych wierszy
/// „przerwy” i „napisałem odpowiedź”: tyle wierszy, ile akcji.
struct ThinkingEntry {
    let step: AgentProgressStepDTO?
    let seconds: Int?
    /// Pierwszy wiersz „Przemyślałem, od czego zacząć” — zawsze jest.
    var isStart = false

    /// Wiersz startu trwa tyle, ile model naprawdę myślał przed pierwszą
    /// akcją, ale nie krócej niż 2 s i nie dłużej niż 10 s (runda 9, Rafał:
    /// „daj zawsze 1 wiadomość, że zaczął pracę, żeby nie było, że w 1 kroku
    /// wszystko ogarnął… odejmij ten czas od reszty — ma być widać, że system
    /// myślał”). Nadwyżka ponad 10 s zostaje w pierwszej akcji, a brak do 2 s
    /// schodzi z niej — suma dalej = czas w nagłówku.
    static let startRange: ClosedRange<Int> = 2...10

    static func timeline(_ thinking: AgentThinkingSummary) -> [ThinkingEntry] {
        let steps = thinking.steps
        let times: [Date?] = steps.map { AgentStore.parseTimestamp($0.at) }
        let start: Date? = thinking.startedAt ?? times.compactMap { $0 }.first
        let total: Int? = thinking.duration.map { Int($0.rounded()) }

        guard !steps.isEmpty else {
            return [ThinkingEntry(step: nil, seconds: total)]
        }

        // Sekunda tury, w której akcja ruszyła naprawdę.
        let real: [Int?] = times.map { at in
            guard let at, let start else { return nil }
            return max(0, Int(at.timeIntervalSince(start).rounded()))
        }

        // Start: prawdziwe myślenie przed 1. akcją w widełkach 2–10 s, ale
        // każdej akcji zostaje co najmniej sekunda.
        var startSeconds = min(max(real[0] ?? startRange.lowerBound, startRange.lowerBound), startRange.upperBound)
        if let total {
            startSeconds = min(startSeconds, max(0, total - steps.count))
        }

        // Granice akcji: pierwsza od końca wiersza startu, kolejne od swojej
        // prawdziwej sekundy — nigdy wstecz.
        var boundaries: [Int?] = []
        var previous = startSeconds
        for index in steps.indices {
            if index == 0 {
                boundaries.append(startSeconds)
                continue
            }
            guard let value = real[index] else {
                boundaries.append(nil)
                continue
            }
            previous = max(previous, value)
            boundaries.append(previous)
        }

        let actions: [ThinkingEntry] = steps.indices.map { index in
            let from = boundaries[index]
            let to: Int? = index + 1 < steps.count ? boundaries[index + 1] : total
            var seconds: Int?
            if let from, let to { seconds = max(0, to - from) }
            return ThinkingEntry(step: steps[index], seconds: seconds)
        }
        return [ThinkingEntry(step: nil, seconds: startSeconds, isStart: true)] + actions
    }
}

private struct ThinkingRow: View {
    let entry: ThinkingEntry
    let isFirst: Bool
    let isLast: Bool

    @Environment(\.colorScheme) private var scheme

    private static let disc: CGFloat = 28

    private var title: String {
        if entry.isStart { return "Przemyślałem, od czego zacząć" }
        guard let step = entry.step else { return "Przemyślałem i odpowiedziałem" }
        return step.done ?? step.label
    }

    private var icon: String {
        if entry.isStart { return "brain" }
        return entry.step.map(ThinkingKind.icon) ?? "sparkles"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.scPageBase(scheme))
                Circle().fill(AssistantLook.quietTint(scheme))
                Image(systemName: icon)
                    .font(.sc(size: 12, weight: .semibold))
                    .foregroundStyle(AssistantLook.muted(scheme))
            }
            .frame(width: Self.disc, height: Self.disc)
            .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.sc(size: 15, weight: .medium))
                        .tracking(-0.2)
                        .foregroundStyle(AssistantLook.ink(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = entry.step?.detail, !detail.isEmpty {
                        // Najwyżej dwie linie — fakty, nie przepisana prośba.
                        Text(detail)
                            .font(.sc(size: 13))
                            .lineSpacing(1)
                            .foregroundStyle(AssistantLook.muted(scheme))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let seconds = entry.seconds {
                    Text(AssistantThoughtLine.clock(TimeInterval(seconds)))
                        .font(.sc(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(AssistantLook.faint(scheme))
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
        .background(alignment: .leading) { axis }
        .accessibilityElement(children: .combine)
    }

    /// Oś: kreska przez środek krążków, od sąsiada do sąsiada.
    private var axis: some View {
        VStack(spacing: 0) {
            segment(visible: !isFirst)
                .frame(height: 8)
            Color.clear.frame(height: Self.disc)
            segment(visible: !isLast)
        }
        .frame(width: 2)
        .padding(.leading, Self.disc / 2 - 1)
    }

    @ViewBuilder
    private func segment(visible: Bool) -> some View {
        if visible {
            AxisLine()
                .stroke(AssistantLook.hair(scheme), lineWidth: 1.5)
        } else {
            Color.clear
        }
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

// MARK: - Tytuł

/// Tytuł arkusza — EFEKT tury jako rzeczownik („Plan gotowy”),
/// po priorytecie: zapis > plan > zamiana > dania > reszta > samo
/// sprawdzanie. Rzeczownik, nie czasownik: tytuł „Ułożyłem plan” powtarzał
/// zdanie z wiersza osi (runda 10, „head title, który się potem nie
/// powtarza”).
struct ThinkingHeadline {
    let title: String

    private static let priority: [(tools: Set<String>, title: String)] = [
        // KRÓTKO — obok stoją kapsułka czasu i krzyżyk, a „Propozycja planu
        // gotowa” łamała się na dwie linie (runda 11).
        (["apply_week_plan"], "Plan zapisany"),
        (["create_recipe", "update_recipe", "delete_recipe"], "Przepis zapisany"),
        (["mark_meal_eaten"], "Odhaczone"),
        (["check_shopping_items"], "Zakupy odhaczone"),
        (["build_meal_plan", "propose_week_plan", "propose_day_plan", "start_planning"], "Plan gotowy"),
        (["propose_swap", "replace_plan_item", "revise_proposal"], "Zamiennik"),
        (["propose_household_split"], "Porcje"),
        (["propose_remove_meal"], "Zmiana w planie"),
        (["suggest_meals", "offer_options", "find_recipes"], "Dania do wyboru"),
        (["ask_clarifying_question"], "Pytanie do Ciebie"),
        (["show_shopping_list"], "Lista zakupów"),
        (["show_macro_gap", "get_week_balance"], "Bilans policzony"),
        (["remember_note"], "Zapamiętane"),
    ]

    init(_ steps: [AgentProgressStepDTO]) {
        for entry in Self.priority where steps.contains(where: { entry.tools.contains($0.tool) }) {
            title = entry.title
            return
        }
        title = steps.isEmpty ? "Szybka odpowiedź" : "Plan sprawdzony"
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
