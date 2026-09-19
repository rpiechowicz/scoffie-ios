import SwiftUI

// Widok briefingu na pustej rozmowie — 1:1 z makietą „01 · Ekrany główne”:
// nadtytuł ze znakiem i datą po prawej, nagłówek na dwie linie, jedno zdanie,
// ilustracja w zagłębionym panelu z podsumowaniem, WYPEŁNIONY przycisk
// główny ze strzałką, dopisek pod nim i dwie akcje wtórne jako wiersze
// z kafelkiem ikony i chevronem — wszystko w JEDNEJ karcie. Rysuje
// `AssistantBriefing`, nie liczy nic sam.

// MARK: - Karta

struct AssistantBriefingCard: View {
    let briefing: AssistantBriefing
    let onAction: (AssistantBriefing.Action) -> Void

    @Environment(\.colorScheme) private var scheme

    private var tone: AssistantTone {
        switch briefing.kind {
        case .balanceIssue: return .indigo
        case .trialExhausted: return .muted
        default: return .neutral
        }
    }

    private var accent: Color {
        briefing.kind == .balanceIssue ? SCPalette.indigo : SCPalette.terracotta
    }

    var body: some View {
        AssistantCard(tone: tone) {
            head

            Text(briefing.headline)
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.6)
                .lineSpacing(1)
                .foregroundStyle(Color.scLabel(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AssistantCardMetrics.inset)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)

            Text(briefing.supporting)
                .font(.system(size: 14.5))
                .tracking(-0.15)
                .lineSpacing(2)
                .foregroundStyle(Color.scMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AssistantCardMetrics.inset)
                .padding(.top, 6)

            visualPanel
                .padding(.horizontal, AssistantCardMetrics.inset)
                .padding(.top, 14)

            AssistantCardActions(
                primary: AssistantCardAction(title: briefing.primary.title, icon: primaryIcon) {
                    onAction(briefing.primary)
                },
                tone: tone == .muted ? .neutral : tone,
                showsRule: false,
                filledPrimary: true
            )
            .padding(.top, 4)

            if let helper = briefing.helper {
                Text(helper)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.scFaint(scheme))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AssistantCardMetrics.inset)
                    .padding(.top, -4)
                    .padding(.bottom, 14)
            } else {
                Color.clear.frame(height: 6)
            }

            if !briefing.secondary.isEmpty {
                secondaryRows
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Znak marki · NADTYTUŁ · data po prawej.
    private var head: some View {
        HStack(alignment: .center, spacing: 8) {
            SCMarkShape()
                .fill(accent)
                .frame(width: 13, height: 13)
                .accessibilityHidden(true)
            Text(briefing.eyebrow)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            if let dateLabel = briefing.dateLabel {
                Text(dateLabel)
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, AssistantCardMetrics.inset)
        .padding(.top, AssistantCardMetrics.headTop + 2)
        .accessibilityElement(children: .combine)
    }

    private var primaryIcon: String? {
        switch briefing.primary.kind {
        case .ask: return "arrow.right"
        case .openPlans: return "arrow.right"
        case .openHistory: return "clock"
        }
    }

    /// Ilustracja i podsumowanie w jednym zagłębionym panelu.
    @ViewBuilder
    private var visualPanel: some View {
        if briefing.visual != .none || briefing.summary != nil {
            VStack(alignment: .leading, spacing: 12) {
                visual
                if let summary = briefing.summary {
                    HStack(spacing: 4) {
                        if let prefix = summary.prefix {
                            Text(prefix)
                        }
                        CountingNumber(target: summary.value)
                        Text(summary.text)
                    }
                    .font(.system(size: 12.5))
                    .tracking(-0.15)
                    .foregroundStyle(Color.scMuted(scheme))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(summary.sentence)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AssistantCardMetrics.innerRadius + 2, style: .continuous)
                    .fill(Color.scInsetSurface(scheme))
            )
        }
    }

    @ViewBuilder
    private var visual: some View {
        switch briefing.visual {
        case .none:
            EmptyView()
        case let .weekStrip(days):
            WeekStrip(days: days)
        case let .slots(marks):
            SlotChecklist(marks: marks)
        case let .meals(meals):
            MealsPreview(meals: meals)
        case let .balance(current, target, unit):
            VStack(alignment: .leading, spacing: 8) {
                AssistantTargetBar(value: current, target: target, color: SCPalette.indigo, height: 8)
                HStack(spacing: 4) {
                    CountingNumber(target: current)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.scLabel(scheme))
                    Text("\(unit) dziennie")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.scLabel(scheme))
                    Spacer(minLength: 8)
                    Text("cel \(target) \(unit)")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(current) \(unit) dziennie, cel \(target) \(unit)")
        }
    }

    /// Akcje wtórne jako wiersze: kafelek ikony · tytuł i podtytuł · chevron,
    /// na własnej, o pół tonu ciemniejszej półce pod korpusem karty.
    private var secondaryRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(briefing.secondary.prefix(2).enumerated()), id: \.element.id) { index, action in
                Button { onAction(action) } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.scCardSurface(scheme))
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
                            if action.icon == "mark" {
                                SCMarkShape()
                                    .fill(accent)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: action.icon ?? "arrow.up.right")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(accent)
                            }
                        }
                        .frame(width: 40, height: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(.system(size: 15, weight: .semibold))
                                .tracking(-0.25)
                                .foregroundStyle(Color.scLabel(scheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                            if let subtitle = action.subtitle {
                                Text(subtitle)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Color.scMuted(scheme))
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.scFaint(scheme))
                    }
                    .padding(.horizontal, AssistantCardMetrics.inset)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlanPressStyle(scale: 0.985))
                .overlay(alignment: .top) {
                    AssistantCardRule(leadingInset: index == 0 ? 0 : AssistantCardMetrics.inset + 52)
                }
                .accessibilityHint(hint(for: action))
            }
        }
        .background(Color.scInsetSurface(scheme).opacity(scheme == .dark ? 1 : 0.55))
    }

    private func hint(for action: AssistantBriefing.Action) -> String {
        switch action.kind {
        case .ask: return "Wysyła pytanie do asystenta"
        case .openPlans: return "Otwiera plany"
        case .openHistory: return "Otwiera historię rozmów"
        }
    }

    // MARK: Ilustracje

    /// Siedem dni: skrót, kafelek (kreskowany = pusty, ptaszek albo
    /// miniatura = zaplanowany), numer dnia pod spodem; dziś obwiedzione.
    private struct WeekStrip: View {
        let days: [AssistantBriefing.DayMark]

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            HStack(spacing: 6) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        Text(day.short)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(day.isToday ? SCPalette.terracotta : Color.scMuted(scheme))
                            .lineLimit(1)

                        ZStack {
                            if day.planned {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.scSageTint(scheme))
                                if let url = day.imageURL {
                                    AssistantThumbnail(url: url, size: 36)
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(SCPalette.sage)
                                }
                            } else {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(
                                        Color.scFaint(scheme).opacity(0.7),
                                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                                    )
                            }
                        }
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(day.isToday ? SCPalette.terracotta.opacity(0.75) : Color.clear, lineWidth: 1.5)
                        )

                        Text(day.dayNumber)
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(Color.scFaint(scheme))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.short) \(day.dayNumber): \(day.planned ? "zaplanowany" : "pusty")\(day.isToday ? ", dziś" : "")")
                }
            }
        }
    }

    /// Pory dnia z ptaszkiem albo pustym kółkiem — „✓ śniadanie · ○ kolacja”.
    private struct SlotChecklist: View {
        let marks: [AssistantBriefing.SlotMark]

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(marks.enumerated()), id: \.element.id) { index, mark in
                    HStack(spacing: 10) {
                        Image(systemName: mark.filled ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(mark.filled ? SCPalette.sage : Color.scFaint(scheme))
                            .frame(width: 20)
                        Text(mark.title)
                            .font(.system(size: 13.5, weight: mark.filled ? .regular : .semibold))
                            .foregroundStyle(mark.filled ? Color.scMuted(scheme) : Color.scLabel(scheme))
                        Spacer(minLength: 8)
                        if let time = mark.time {
                            Text(time)
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .foregroundStyle(Color.scFaint(scheme))
                        }
                    }
                    .padding(.vertical, 6)
                    .overlay(alignment: .top) {
                        if index > 0 { AssistantCardRule(leadingInset: 30) }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(mark.title): \(mark.filled ? "jest" : "pusto")")
                }
            }
        }
    }

    /// Dwa–trzy dania dnia z miniaturami.
    private struct MealsPreview: View {
        let meals: [AssistantBriefing.MealPreview]

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                    HStack(spacing: 10) {
                        AssistantThumbnail(url: meal.imageURL, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            AssistantCardLabel(text: meal.slotTitle)
                            Text(meal.title)
                                .font(.system(size: 13.5, weight: .medium))
                                .tracking(-0.2)
                                .foregroundStyle(Color.scLabel(scheme))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if meal.kcal > 0 {
                            HStack(spacing: 3) {
                                CountingNumber(target: meal.kcal)
                                Text("kcal")
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(Color.scFaint(scheme))
                        }
                    }
                    .padding(.vertical, 6)
                    .overlay(alignment: .top) {
                        if index > 0 { AssistantCardRule(leadingInset: 46) }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Znak

/// Znak marki w miękkim krążku — ten sam glif, który oddycha w wierszu tury.
struct AssistantMarkBadge: View {
    var size: CGFloat = 56

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle().fill(Color.scAccentTint(scheme))
            Circle().strokeBorder(SCPalette.terracotta.opacity(scheme == .dark ? 0.28 : 0.18), lineWidth: 1)
            SCMarkShape()
                .fill(SCPalette.terracotta)
                .frame(width: size * 0.42, height: size * 0.42)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
