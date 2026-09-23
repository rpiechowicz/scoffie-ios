import SwiftUI

// Karta briefingu na pustej rozmowie — 1:1 z makietą „Scoffie — Asystent ·
// Dynamic Empty States” (`EBriefing`, `ekit.jsx`): jeden komponent,
// dwanaście sytuacji zmienia tylko dane.
//
// Anatomia: znak + eyebrow (sytuacja) · data/zakres po prawej · headline
// (26/700, ZAREZERWOWANE 2 linie) · supporting copy (15) · wizualizacja
// kontekstu w panelu o STAŁEJ wysokości 112 · główny przycisk 50 ·
// helper (12,5, jedna linia) · najwyżej dwa wiersze akcji w stopce tej
// samej karty (ikona 30 · tytuł · chevron). Karta jest tak samo wysoka
// w poniedziałek rano i w sobotę — ekran nie skacze każdego dnia.
//
// Stan dnia albo posiłku to KÓŁKO: puste (kreskowane), częściowe (ring
// z ułamkiem), gotowe (pełne z ptaszkiem). Rysuje `AssistantBriefing`,
// nie liczy nic sam.

// MARK: - Karta

struct AssistantBriefingCard: View {
    let briefing: AssistantBriefing
    let onAction: (AssistantBriefing.Action) -> Void

    @Environment(\.colorScheme) private var scheme

    /// Stała wysokość strefy wizualizacji.
    private static let visualHeight: CGFloat = 112

    private var quiet: Bool { briefing.isQuiet }

    var body: some View {
        AssistantCard {
            VStack(alignment: .leading, spacing: 0) {
                head

                Text(briefing.headline)
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.7)
                    .lineSpacing(2)
                    .foregroundStyle(AssistantLook.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 62, alignment: .topLeading)
                    .padding(.top, 14)
                    .accessibilityAddTraits(.isHeader)

                Text(briefing.supporting)
                    .font(.system(size: 15))
                    .tracking(-0.2)
                    .lineSpacing(3)
                    .foregroundStyle(AssistantLook.muted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                visualPanel
                    .padding(.top, 16)

                AssistantPrimaryButton(
                    action: AssistantCardAction(title: briefing.primary.title, icon: primaryIcon) {
                        onAction(briefing.primary)
                    },
                    height: 50
                )
                .padding(.top, 16)

                Text(briefing.helper ?? " ")
                    .font(.system(size: 12.5))
                    .foregroundStyle(AssistantLook.faint(scheme))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 15)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                    .accessibilityHidden(briefing.helper == nil)
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.top, 18)

            if !briefing.secondary.isEmpty {
                secondaryRows
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Znak marki 17 · EYEBROW · data po prawej. Wyciszone przy limicie.
    private var head: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                SCMarkShape()
                    .fill(quiet ? AssistantLook.ink(scheme).opacity(0.35) : AssistantLook.terraFill(scheme))
                    .frame(width: 17, height: 17)
                    .accessibilityHidden(true)
                Text(briefing.eyebrow)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(quiet ? AssistantLook.faint(scheme) : AssistantLook.terra(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 8)
            if let dateLabel = briefing.dateLabel {
                Text(dateLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AssistantLook.faint(scheme))
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var primaryIcon: String? {
        switch briefing.primary.kind {
        case .ask, .openPlans: return "arrow.right"
        case .openHistory: return "clock"
        }
    }

    /// Wizualizacja kontekstu w panelu `wash`, promień 16, stała wysokość.
    private var visualPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            visual
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: Self.visualHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AssistantCardMetrics.innerRadius, style: .continuous)
                .fill(AssistantLook.wash(scheme))
        )
    }

    @ViewBuilder
    private var visual: some View {
        switch briefing.visual {
        case let .week(days):
            WeekDots(days: days, summary: briefing.summary)
        case let .day(label, slots):
            DayAxis(label: label, summary: briefing.summary, slots: slots)
        case let .meals(meals):
            MealsPreview(meals: meals)
        case let .balance(current, target, unit):
            Balance(current: current, target: target, unit: unit, summary: briefing.summary)
        case let .teaser(urls):
            Teaser(urls: urls)
        case let .brand(muted):
            HStack {
                Spacer(minLength: 0)
                AssistantMarkBadge(size: 56, muted: muted)
                Spacer(minLength: 0)
            }
            .frame(height: 76)
        }
    }

    /// Akcje wtórne jako wiersze w stopce karty: kafelek ikony 30 · tytuł
    /// 15/500 · chevron, na półce `wash` pod włoskowatą kreską.
    private var secondaryRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(briefing.secondary.prefix(2).enumerated()), id: \.element.id) { index, action in
                Button { onAction(action) } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AssistantLook.field(scheme))
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AssistantLook.cardStroke(scheme), lineWidth: 1)
                            Image(systemName: action.icon ?? "arrow.up.right")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AssistantLook.terra(scheme))
                        }
                        .frame(width: 30, height: 30)

                        Text(action.title)
                            .font(.system(size: 15, weight: .medium))
                            .tracking(-0.3)
                            .foregroundStyle(AssistantLook.ink(scheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AssistantLook.ink(scheme).opacity(0.35))
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, AssistantCardMetrics.inset)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlanPressStyle(scale: 0.985))
                .overlay(alignment: .top) {
                    AssistantCardRule()
                        .opacity(index == 0 ? 1 : 1)
                }
                .accessibilityHint(hint(for: action))
            }
        }
        .background(AssistantLook.wash(scheme))
    }

    private func hint(for action: AssistantBriefing.Action) -> String {
        switch action.kind {
        case .ask: return "Wysyła pytanie do asystenta"
        case .openPlans: return "Otwiera plany"
        case .openHistory: return "Otwiera historię rozmów"
        }
    }

    // MARK: Kółka

    /// `EDot`: pusty = kreskowany ring · częściowy = ring z ułamkiem ·
    /// gotowy = dysk z ptaszkiem. Skaluje się do dowolnej liczby posiłków.
    private struct Dot: View {
        let state: AssistantBriefing.DotState
        var size: CGFloat = 28

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            switch state {
            case .full:
                ZStack {
                    Circle().fill(AssistantLook.terraFill(scheme))
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.42, weight: .heavy))
                        .foregroundStyle(Color.white)
                }
                .frame(width: size, height: size)
            case let .partial(fraction):
                ZStack {
                    Circle()
                        .stroke(AssistantLook.ink(scheme).opacity(0.14), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: max(0, min(1, fraction)))
                        .stroke(AssistantLook.terraFill(scheme), style: StrokeStyle(lineWidth: 4, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                .padding(2)
                .frame(width: size, height: size)
            case .empty:
                Circle()
                    .strokeBorder(AssistantLook.dash(scheme), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: size, height: size)
            }
        }
    }

    /// Podsumowanie z liczbą, która się przewija: „0 z 7 dni zaplanowanych”.
    private struct SummaryLine: View {
        let summary: AssistantBriefing.Summary
        var size: CGFloat = 12

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            HStack(spacing: 4) {
                if let prefix = summary.prefix { Text(prefix) }
                CountingNumber(target: summary.value)
                Text(summary.text)
            }
            .font(.system(size: size))
            .foregroundStyle(AssistantLook.faint(scheme))
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary.sentence)
        }
    }

    /// `EWeek`: siedem dni jako kółka, numery dni pod spodem, dziś w terakocie.
    private struct WeekDots: View {
        let days: [AssistantBriefing.DayMark]
        let summary: AssistantBriefing.Summary?

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 4) {
                    ForEach(days) { day in
                        VStack(spacing: 6) {
                            Text(day.short)
                                .font(.system(size: 11, weight: day.isToday ? .bold : .semibold))
                                .tracking(0.2)
                                .foregroundStyle(day.isToday ? AssistantLook.terra(scheme) : AssistantLook.faint(scheme))
                                .lineLimit(1)
                            Dot(state: day.state)
                            Text(day.dayNumber)
                                .font(.system(size: 10.5, weight: day.isToday ? .semibold : .regular))
                                .monospacedDigit()
                                .foregroundStyle(day.isToday ? AssistantLook.ink(scheme) : AssistantLook.faint(scheme))
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(day.short) \(day.dayNumber): \(label(day.state))\(day.isToday ? ", dziś" : "")")
                    }
                }
                if let summary {
                    SummaryLine(summary: summary)
                }
            }
        }

        private func label(_ state: AssistantBriefing.DotState) -> String {
            switch state {
            case .empty: return "pusty"
            case .partial: return "częściowo zaplanowany"
            case .full: return "zaplanowany"
            }
        }
    }

    /// `EDay`: etykieta i „0 z 3 posiłków” w nagłówku, pod nim mini oś —
    /// kółka połączone linią, nazwy pór pod nimi; pusta pora ciemniejsza.
    private struct DayAxis: View {
        let label: String
        let summary: AssistantBriefing.Summary?
        let slots: [AssistantBriefing.SlotMark]

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(AssistantLook.ink(scheme))
                    Spacer(minLength: 8)
                    if let summary {
                        SummaryLine(summary: summary)
                    }
                }

                HStack(spacing: 0) {
                    ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                        VStack(spacing: 7) {
                            Dot(state: slot.filled ? .full : .empty)
                            Text(slot.title)
                                .font(.system(size: 11.5, weight: slot.filled ? .medium : .semibold))
                                .foregroundStyle(slot.filled ? AssistantLook.faint(scheme) : AssistantLook.ink(scheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .background(alignment: .top) {
                            if index < slots.count - 1 {
                                GeometryReader { geometry in
                                    Rectangle()
                                        .fill(AssistantLook.ink(scheme).opacity(0.12))
                                        .frame(width: max(0, geometry.size.width - 40), height: 1.5)
                                        .offset(x: geometry.size.width / 2 + 20, y: 13)
                                }
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(slot.title): \(slot.filled ? "jest" : "pusto")")
                    }
                }
            }
        }
    }

    /// `EMeals`: miniatura 26 · pora (12, kolumna 64) · nazwa (14/500).
    private struct MealsPreview: View {
        let meals: [AssistantBriefing.MealPreview]

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(meals) { meal in
                    HStack(spacing: 10) {
                        AssistantThumbnail(url: meal.imageURL, size: 26)
                        Text(meal.slotTitle)
                            .font(.system(size: 12))
                            .foregroundStyle(AssistantLook.faint(scheme))
                            .lineLimit(1)
                            .frame(width: 64, alignment: .leading)
                        Text(meal.title)
                            .font(.system(size: 14, weight: .medium))
                            .tracking(-0.2)
                            .foregroundStyle(AssistantLook.ink(scheme))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// `EBalance`: „104 g średnio dziennie · cel 128 g”, pasek 6 pt
    /// z kreską celu na końcu, notka „Poniżej celu w 5 z 7 dni”.
    private struct Balance: View {
        let current: Int
        let target: Int
        let unit: String
        let summary: AssistantBriefing.Summary?

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 4) {
                        HStack(spacing: 3) {
                            CountingNumber(target: current)
                            Text(unit)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AssistantLook.ink(scheme))
                        Text("średnio dziennie")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AssistantLook.faint(scheme))
                    }
                    .tracking(-0.2)
                    Spacer(minLength: 8)
                    Text("cel \(target) \(unit)")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(AssistantLook.faint(scheme))
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AssistantLook.ink(scheme).opacity(0.09))
                        Capsule()
                            .fill(AssistantLook.terraFill(scheme))
                            .frame(width: geometry.size.width * min(1, Double(current) / Double(max(target, 1))))
                        HStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(AssistantLook.ink(scheme).opacity(0.35))
                                .frame(width: 2, height: 14)
                        }
                    }
                }
                .frame(height: 6)

                if let summary {
                    SummaryLine(summary: summary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(current) \(unit) średnio dziennie, cel \(target) \(unit)")
        }
    }

    /// `ETeaser`: trzy miniatury 76 pt, promień 14 — bez nazw i bez wyboru.
    private struct Teaser: View {
        let urls: [URL?]
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            HStack(spacing: 8) {
                ForEach(Array(urls.prefix(3).enumerated()), id: \.offset) { _, url in
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            ZStack {
                                AssistantLook.field(scheme)
                                Image(systemName: "fork.knife")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.black.opacity(0.12), radius: 1, y: 1)
                }
            }
            .accessibilityHidden(true)
        }
    }
}
