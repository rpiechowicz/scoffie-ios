import SwiftUI

// Widok briefingu na pustej rozmowie — rysuje `AssistantBriefing`, nie liczy
// nic sam. Ta sama anatomia co karty w rozmowie (nadtytuł → tytuł → treść →
// podsumowanie → akcja), więc pusty ekran i odpowiedź asystenta wyglądają
// jak jedna rodzina: pierwsze spotkanie z asystentem jest spotkaniem z kartą,
// nie z ikoną z katalogu.

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

    private var eyebrowColor: Color {
        briefing.kind == .balanceIssue ? SCPalette.indigo : SCPalette.terracotta
    }

    var body: some View {
        AssistantCard(tone: tone) {
            AssistantCardHead(
                eyebrow: briefing.eyebrow,
                eyebrowDetail: briefing.dateLabel,
                eyebrowColor: eyebrowColor,
                title: briefing.headline,
                subtitle: briefing.supporting
            )

            visual

            if let summary = briefing.summary {
                Text(summary)
                    .font(.system(size: 12.5))
                    .tracking(-0.15)
                    .monospacedDigit()
                    .foregroundStyle(Color.scMuted(scheme))
                    .padding(.horizontal, AssistantCardMetrics.inset)
                    .padding(.bottom, AssistantCardMetrics.section)
            }

            AssistantCardActions(
                primary: AssistantCardAction(title: briefing.primary.title, icon: primaryIcon) {
                    onAction(briefing.primary)
                },
                tone: tone == .muted ? .neutral : tone,
                showsRule: true
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var primaryIcon: String? {
        switch briefing.primary.kind {
        case .ask: return "arrow.up"
        case .openPlans: return "sparkles"
        case .openHistory: return "clock"
        }
    }

    @ViewBuilder
    private var visual: some View {
        switch briefing.visual {
        case .none:
            EmptyView()
        case let .weekStrip(days):
            WeekStrip(days: days)
                .padding(.horizontal, AssistantCardMetrics.inset)
                .padding(.bottom, briefing.summary == nil ? AssistantCardMetrics.section : 8)
        case let .slots(marks):
            SlotChecklist(marks: marks)
                .padding(.horizontal, AssistantCardMetrics.inset)
                .padding(.bottom, AssistantCardMetrics.section)
        case let .meals(meals):
            MealsPreview(meals: meals)
                .padding(.horizontal, AssistantCardMetrics.inset)
                .padding(.bottom, AssistantCardMetrics.section)
        case let .balance(current, target, unit):
            VStack(alignment: .leading, spacing: 8) {
                AssistantTargetBar(value: current, target: target, color: SCPalette.indigo, height: 8)
                HStack {
                    Text("\(current) \(unit) dziennie")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(scheme))
                    Spacer(minLength: 8)
                    Text("cel \(target) \(unit)")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                }
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.bottom, briefing.summary == nil ? AssistantCardMetrics.section : 8)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Ilustracje

    /// Siedem dni: skrót, kropka „ma plan” albo miniatura, dziś podkreślone.
    private struct WeekStrip: View {
        let days: [AssistantBriefing.DayMark]

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            HStack(spacing: 6) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        Text(day.short)
                            .font(.system(size: 10.5, weight: day.isToday ? .bold : .semibold))
                            .foregroundStyle(day.isToday ? SCPalette.terracotta : Color.scMuted(scheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(day.planned ? Color.scSageTint(scheme) : Color.scInsetSurface(scheme))
                            if day.planned {
                                if let url = day.imageURL {
                                    AssistantThumbnail(url: url, size: 32)
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(SCPalette.sage)
                                }
                            } else {
                                Circle()
                                    .strokeBorder(Color.scFaint(scheme).opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                    .frame(width: 12, height: 12)
                            }
                        }
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(day.isToday ? SCPalette.terracotta.opacity(0.7) : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.short): \(day.planned ? "zaplanowany" : "pusty")\(day.isToday ? ", dziś" : "")")
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
                    .padding(.vertical, 7)
                    .overlay(alignment: .top) {
                        if index > 0 { AssistantCardRule(leadingInset: 30) }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(mark.title): \(mark.filled ? "jest" : "pusto")")
                }
            }
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: AssistantCardMetrics.innerRadius, style: .continuous)
                    .fill(Color.scInsetSurface(scheme))
            )
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
                            Text("\(meal.kcal) kcal")
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .foregroundStyle(Color.scFaint(scheme))
                        }
                    }
                    .padding(.vertical, 7)
                    .overlay(alignment: .top) {
                        if index > 0 { AssistantCardRule(leadingInset: 46) }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: AssistantCardMetrics.innerRadius, style: .continuous)
                    .fill(Color.scInsetSurface(scheme))
            )
        }
    }
}

// MARK: - Akcje wtórne

/// Najwyżej dwie podpowiedzi pod kartą — chipy w kolorze marki.
struct AssistantBriefingSecondaryActions: View {
    let actions: [AssistantBriefing.Action]
    let onAction: (AssistantBriefing.Action) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(actions.prefix(2)) { action in
                Button { onAction(action) } label: {
                    Text(action.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .tracking(-0.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(SCPalette.terracotta)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Capsule().fill(Color.scAccentTint(scheme).opacity(0.5)))
                        .overlay(Capsule().stroke(SCPalette.terracotta.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Znak

/// Znak marki nad briefingiem — ten sam glif, który oddycha w wierszu tury.
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
