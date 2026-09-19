import SwiftUI

// Karty asystenta — 1:1 z makietą v4 („03 · Karty propozycji”,
// „04 · Stany karty”): propozycja tygodnia i dnia, pytanie, dania do
// wyboru, zamiana, usunięcie, wspólne danie, bilans makro, zakupy, zapis.
//
// Cała treść przychodzi z serwera GOTOWA: nazwy dni, etykiety posiłków,
// napisy na przyciskach, liczby, zdania o celu. Ten plik jej nie liczy
// i nie tłumaczy — układa ją na wspólnych atomach z `AssistantCardKit`
// i decyduje, co się dzieje po dotknięciu.

// MARK: - Wspólne

/// Nadtytuł zapasowy, gdy serwer go nie przysłał (starszy kontrakt).
private enum CardEyebrowFallback {
    static let planWeek = "Propozycja"
    static let planDay = "Propozycja"
}

/// Pasek tygodnia z makiety (`LWeekRail filled`): kafelek 32 ze zdjęciem
/// głównego dania i lekką liczbą posiłków (biała cyfra na cieniu, bez
/// pigułki). W stanie zapisanym znacznik szałwii zamiast liczby.
private struct WeekRail: View {
    let days: [PlanWeekCardDayDTO]
    var selectedId: String?
    var sage: Bool = false
    var onSelect: ((String) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days) { day in
                let selected = day.id == selectedId
                Button {
                    onSelect?(day.id)
                } label: {
                    VStack(spacing: 5) {
                        Text(day.shortName)
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.2)
                            .foregroundStyle(selected ? AssistantLook.terra(scheme) : AssistantLook.faint(scheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        ZStack(alignment: .bottomTrailing) {
                            AssistantThumbnail(
                                url: (day.slots.first { $0.isNew } ?? day.slots.first)?.imageUrl.flatMap(URL.init(string:)),
                                size: 32
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            if sage {
                                ZStack {
                                    Circle().fill(AssistantLook.sage(scheme))
                                    Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 7, weight: .black))
                                        .foregroundStyle(Color.white)
                                }
                                .frame(width: 12, height: 12)
                                .offset(x: -2, y: -2)
                            } else {
                                LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.42)], startPoint: .top, endPoint: .bottom)
                                    .frame(width: 32, height: 18)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(alignment: .bottomTrailing) {
                                        Text("\(day.slots.count)")
                                            .font(.system(size: 10, weight: .bold))
                                            .monospacedDigit()
                                            .foregroundStyle(Color.white)
                                            .shadow(color: Color.black.opacity(0.35), radius: 1, y: 1)
                                            .padding(.trailing, 4)
                                            .padding(.bottom, 2)
                                    }
                            }
                        }
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selected ? AssistantLook.terra(scheme) : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onSelect == nil)
                .accessibilityLabel("\(day.dayLabel), \(day.slots.count) posiłki, \(day.kcalTotal) kcal")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}

/// Jeden dzień propozycji (`LDayBlock`): kolumna 26 ze skrótem dnia
/// i numerem, obok posiłki co 14 pt.
private struct DayBlock: View {
    let day: PlanWeekCardDayDTO
    var muted: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(day.shortName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AssistantLook.ink(scheme))
                    .lineLimit(1)
                Text(Self.dayNumber(day))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(AssistantLook.faint(scheme))
            }
            .frame(width: 26, alignment: .leading)
            .padding(.top, 2)
            .opacity(muted ? 0.6 : 1)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(day.slots) { slot in
                    AssistantMealRow(
                        slot: slot.mealLabel,
                        title: slot.title,
                        imageUrl: slot.imageUrl,
                        kcal: slot.kcalPerServing,
                        muted: muted || !slot.isNew
                    )
                }
            }
        }
        .padding(.horizontal, AssistantCardMetrics.inset)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .overlay(alignment: .top) { AssistantCardRule() }
    }

    /// „22” z `dateLabel` („22.09”) albo z daty ISO („2026-09-22”).
    static func dayNumber(_ day: PlanWeekCardDayDTO) -> String {
        if let label = day.dateLabel, let first = label.split(separator: ".").first, Int(first) != nil {
            return String(first)
        }
        if let number = Int(day.date.suffix(2)) { return String(number) }
        return ""
    }
}

/// „Zniknie z planu” — zmiana planu nigdy nie jest cicha.
private struct RemovalsSection: View {
    let removals: [PlanWeekCardRemovalDTO]
    var showsDay: Bool = true

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AssistantCardLabel(text: "Zniknie z planu · \(removals.count)")

            ForEach(removals) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(line(for: item))
                        .font(.system(size: 14))
                        .foregroundStyle(AssistantLook.muted(scheme))
                        .strikethrough(true, color: AssistantLook.faint(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if let reason = item.reason, !reason.isEmpty {
                        Text(reason)
                            .font(.system(size: 12))
                            .foregroundStyle(AssistantLook.faint(scheme))
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AssistantCardMetrics.inset)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { AssistantCardRule() }
    }

    private func line(for item: PlanWeekCardRemovalDTO) -> String {
        showsDay
            ? "\(item.dayLabel), \(item.mealLabel.lowercased()): \(item.title)"
            : "\(item.mealLabel): \(item.title)"
    }
}

/// Wiersz „Pokaż pozostałe 6 dni” — terakota 14/600 z chevronem.
private struct ExpandRow: View {
    let title: String
    let expanded: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.2)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .foregroundStyle(AssistantLook.terra(scheme))
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { AssistantCardRule() }
        }
        .buttonStyle(.plain)
        .accessibilityHint(expanded ? "Zwija pozostałe dni" : "Rozwija pozostałe dni")
    }
}

private func daysWord(_ count: Int) -> String {
    if count == 1 { return "dzień" }
    return "dni"
}

// MARK: - Propozycja tygodnia

/// `LProposal`: nagłówek ze stanem, pasek tygodnia, JEDEN dzień rozwinięty
/// z oddechem, reszta pod „Pokaż pozostałe”, jedno zdanie podsumowania,
/// akcje w stopce.
struct AssistantPlanWeekCard: View {
    let card: PlanWeekCardDTO
    let isBusy: Bool
    @Binding var isExpanded: Bool
    let onApply: (_ force: Bool) -> Void
    let onRevise: () -> Void
    let onAskNew: () -> Void
    var onUndo: (() -> Void)? = nil
    var onOpenPlan: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @State private var selectedDayId: String?

    private var status: AssistantCardStatus { AssistantCardStatus(card.state) }
    private var muted: Bool { status.tone == .muted }

    private var focusedDay: PlanWeekCardDayDTO? {
        if let selectedDayId, let day = card.days.first(where: { $0.id == selectedDayId }) {
            return day
        }
        return card.days.first { day in day.slots.contains { $0.isNew } } ?? card.days.first
    }

    private var otherDays: [PlanWeekCardDayDTO] {
        card.days.filter { $0.id != focusedDay?.id }
    }

    private var summaryItems: [String] {
        var items = ["Śr. \(card.summary.averageKcalPerDay) kcal dziennie"]
        if let note = card.summary.goalNote, !note.isEmpty { items.append(note) }
        return items
    }

    var body: some View {
        AssistantCard(tone: status.tone) {
            AssistantCardHead(
                eyebrow: card.eyebrow ?? CardEyebrowFallback.planWeek,
                eyebrowDetail: card.eyebrowDetail,
                title: card.title,
                subtitle: card.subtitle,
                status: status
            )

            if card.days.count > 1 {
                WeekRail(days: card.days, selectedId: focusedDay?.id, sage: status == .applied) { id in
                    withAnimation(.easeInOut(duration: 0.2)) { selectedDayId = id }
                }
                .padding(.horizontal, AssistantCardMetrics.inset)
                .padding(.vertical, 14)
            } else {
                Color.clear.frame(height: 14)
            }

            if let day = focusedDay {
                DayBlock(day: day, muted: muted)
            }

            if isExpanded {
                ForEach(otherDays) { day in
                    DayBlock(day: day, muted: muted)
                        .transition(.opacity)
                }
            }

            if !otherDays.isEmpty {
                ExpandRow(
                    title: isExpanded ? "Pokaż mniej" : "Pokaż pozostałe \(otherDays.count) \(daysWord(otherDays.count))",
                    expanded: isExpanded
                ) {
                    withAnimation(.easeInOut(duration: 0.22)) { isExpanded.toggle() }
                }
            }

            if !card.removed.isEmpty {
                RemovalsSection(removals: card.removed)
            }

            AssistantCardSummary(items: summaryItems)

            AssistantProposalFooter(
                state: card.state,
                applyLabel: applyLabel,
                reviseLabel: "Zmień coś",
                isBusy: isBusy,
                onApply: onApply,
                onRevise: onRevise,
                onAskNew: onAskNew,
                onUndo: onUndo,
                onOpenPlan: onOpenPlan
            )
        }
    }

    private var applyLabel: String {
        card.actions.first { $0.kind == .apply }?.label ?? "Dodaj do planu"
    }
}

// MARK: - Propozycja dnia

/// Jeden dzień: posiłek po posiłku (`LStale` bez wyciszenia), suma w podsumowaniu.
struct AssistantPlanDayCard: View {
    let card: PlanDayCardDTO
    let isBusy: Bool
    let onApply: (_ force: Bool) -> Void
    let onRevise: () -> Void
    let onAskNew: () -> Void
    var onUndo: (() -> Void)? = nil
    var onOpenPlan: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    private var status: AssistantCardStatus { AssistantCardStatus(card.state) }
    private var muted: Bool { status.tone == .muted }

    private var summaryItems: [String] {
        var items = ["\(card.slots.count) \(mealsWord(card.slots.count))", "\(card.summary.kcalTotal) kcal"]
        if let note = card.summary.goalNote, !note.isEmpty { items.append(note) }
        return items
    }

    private func mealsWord(_ count: Int) -> String {
        if count == 1 { return "posiłek" }
        return (2...4).contains(count) ? "posiłki" : "posiłków"
    }

    var body: some View {
        AssistantCard(tone: status.tone) {
            AssistantCardHead(
                eyebrow: card.eyebrow ?? CardEyebrowFallback.planDay,
                eyebrowDetail: card.eyebrowDetail,
                title: card.title,
                subtitle: card.subtitle,
                status: status
            )

            VStack(alignment: .leading, spacing: 10) {
                ForEach(card.slots) { slot in
                    AssistantMealRow(
                        slot: slot.mealLabel,
                        title: slot.title,
                        imageUrl: slot.imageUrl,
                        kcal: slot.kcalPerServing,
                        muted: muted || !slot.isNew
                    )
                }
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.top, 12)
            .padding(.bottom, 14)

            if !card.removed.isEmpty {
                RemovalsSection(removals: card.removed, showsDay: false)
            }

            AssistantCardSummary(items: summaryItems)

            AssistantProposalFooter(
                state: card.state,
                applyLabel: card.actions.first { $0.kind == .apply }?.label ?? "Zapisz dzień",
                reviseLabel: "Inny zestaw",
                isBusy: isBusy,
                onApply: onApply,
                onRevise: onRevise,
                onAskNew: onAskNew,
                onUndo: onUndo,
                onOpenPlan: onOpenPlan
            )
        }
    }
}

// MARK: - Pytanie z gotowymi odpowiedziami

/// `LClarify`: pytanie jak odpowiedź asystenta (znak + 17/600), szybkie
/// odpowiedzi jako pigułki. Bez eyebrow, bez stopki.
struct AssistantClarifyCard: View {
    let card: ClarifyCardDTO
    /// Co użytkownik odpowiedział — po odpowiedzi zaznaczona jest wybrana opcja.
    var reply: String? = nil
    let onAsk: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AssistantCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    SCMarkShape()
                        .fill(AssistantLook.terraFill(scheme))
                        .frame(width: 18, height: 18)
                        .padding(.top, 3)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.question)
                            .font(.system(size: 17, weight: .semibold))
                            .tracking(-0.4)
                            .lineSpacing(2)
                            .foregroundStyle(AssistantLook.ink(scheme))
                            .fixedSize(horizontal: false, vertical: true)

                        if let hint = card.hint, !hint.isEmpty {
                            Text(hint)
                                .font(.system(size: 13.5))
                                .lineSpacing(2)
                                .foregroundStyle(AssistantLook.muted(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                AssistantAnswerChips(actions: card.actions, reply: reply, onAsk: onAsk)
                    .padding(.leading, 28)
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.top, 16)
            .padding(.bottom, 18)
        }
    }
}

/// Gotowe odpowiedzi jako pigułki; po odpowiedzi wybrana zostaje
/// wyróżniona, reszta schodzi w tło.
struct AssistantAnswerChips: View {
    let actions: [AgentCardActionDTO]
    var reply: String? = nil
    let onAsk: (String) -> Void

    private func isHighlighted(_ action: AgentCardActionDTO) -> Bool {
        guard let reply else { return false }
        return Self.matches(action, reply: reply)
    }

    private static func matches(_ action: AgentCardActionDTO, reply: String) -> Bool {
        let sent = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        return [action.prompt, action.label].contains {
            $0?.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(sent) == .orderedSame
        }
    }

    var body: some View {
        let answered = reply.map { r in actions.contains { Self.matches($0, reply: r) } } ?? false
        AllergenChipFlow(spacing: 8) {
            ForEach(actions) { action in
                let highlighted = isHighlighted(action)
                AssistantChip(title: action.label, highlighted: highlighted, dimmed: answered && !highlighted) {
                    onAsk(action.prompt ?? action.label)
                }
                .accessibilityAddTraits(answered && highlighted ? [.isSelected] : [])
            }
        }
        .animation(.easeInOut(duration: 0.2), value: answered)
    }
}

// MARK: - Dania do wyboru

/// `LOptions`: 2×2 zdjęć, tap w kafelek = wybór. Tagi tylko z danych,
/// które system zna.
struct AssistantOptionsCard: View {
    let card: OptionsCardDTO
    let onAsk: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    /// Dwa kafelki w rzędzie; nieparzysty rząd dostaje pustą połowę.
    /// `HStack` zamiast `LazyVGrid`: siatka w karcie w `LazyVStack`
    /// proponowała kafelkom szerokość spoza kolumny i nazwy nachodziły
    /// na sąsiada.
    private var rows: [[OptionsCardItemDTO]] {
        stride(from: 0, to: card.options.count, by: 2).map { start in
            Array(card.options[start..<min(start + 2, card.options.count)])
        }
    }

    var body: some View {
        AssistantCard {
            AssistantCardHead(eyebrow: card.eyebrow, title: card.title, subtitle: "Wybierz jedno.")

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(row) { option in
                            OptionTile(option: option) { onAsk(option.prompt) }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        if row.count == 1 {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                        }
                    }
                }
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.top, 14)
            .padding(.bottom, 16)

            if let other = card.actions.first {
                AssistantCardActions(
                    secondary: AssistantCardAction(title: other.label, icon: "arrow.triangle.2.circlepath") {
                        onAsk(other.prompt ?? other.label)
                    }
                )
            }
        }
    }

    private struct OptionTile: View {
        let option: OptionsCardItemDTO
        let onTap: () -> Void

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        CachedAsyncImage(url: option.imageUrl.flatMap(URL.init(string:))) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                ZStack {
                                    AssistantLook.wash(scheme)
                                    Image(systemName: "fork.knife")
                                        .font(.system(size: 22))
                                        .foregroundStyle(AssistantLook.faint(scheme))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 126)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color.black.opacity(0.12), radius: 1, y: 1)

                        if let tag = option.tag, !tag.isEmpty {
                            // Pigułka jest biała w obu motywach, więc tusz też
                            // musi być stały — w ciemnym motywie jasny tusz
                            // znikał na białym.
                            Text(tag)
                                .font(.system(size: 11, weight: .bold))
                                .tracking(0.2)
                                .foregroundStyle(AssistantLook.ink(.light))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.9)))
                                .padding(8)
                        }
                    }

                    Text(option.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .tracking(-0.3)
                        .lineSpacing(1)
                        .foregroundStyle(AssistantLook.ink(scheme))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 9)

                    Text(option.prepTimeMinutes > 0 ? "\(option.kcalPerServing) kcal · \(option.prepTimeMinutes) min" : "\(option.kcalPerServing) kcal")
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(AssistantLook.faint(scheme))
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlanPressStyle(scale: 0.97))
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Wybiera to danie")
        }

        private var accessibilityText: String {
            var parts = [option.title, "\(option.kcalPerServing) kilokalorii"]
            if option.prepTimeMinutes > 0 { parts.append("\(option.prepTimeMinutes) minut") }
            if let tag = option.tag, !tag.isEmpty { parts.append(tag) }
            return parts.joined(separator: ", ")
        }
    }
}

// MARK: - Podmiana

/// `LSwap`: Teraz → Propozycja, różnice jako pigułki (szałwia = na korzyść).
struct AssistantSwapCard: View {
    let card: SwapCardDTO
    let isBusy: Bool
    let onApply: (_ force: Bool) -> Void
    let onRevise: () -> Void
    let onAskNew: () -> Void
    /// „Szukaj dalej” — gotowe zdanie o inną podmianę, bez zapisu.
    let onAsk: (String) -> Void
    var onUndo: (() -> Void)? = nil
    var onOpenPlan: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    private var status: AssistantCardStatus { AssistantCardStatus(card.state) }

    var body: some View {
        AssistantCard(tone: status.tone) {
            AssistantCardHead(eyebrow: card.eyebrow, title: card.title, status: status)

            VStack(alignment: .leading, spacing: 0) {
                if let from = card.from {
                    dish(from, label: "Teraz", now: true)
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AssistantLook.terra(scheme))
                            .frame(width: 46)
                        AssistantCardRule()
                    }
                    .frame(height: 26)
                    .padding(.vertical, 2)
                    .accessibilityHidden(true)
                }
                dish(card.to, label: card.from == nil ? "Dołożone" : "Propozycja", now: false)

                if !card.deltas.isEmpty {
                    AssistantCardLabel(text: "Co się zmieni")
                        .padding(.top, 16)
                    AllergenChipFlow(spacing: 6) {
                        ForEach(card.deltas) { delta in
                            Text(delta.label.isEmpty ? delta.value : "\(delta.value) \(delta.label)")
                                .font(.system(size: 12.5, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(delta.good ? AssistantLook.sage(scheme) : AssistantLook.muted(scheme))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(delta.good ? AssistantLook.sageTint(scheme) : AssistantLook.quietTint(scheme)))
                        }
                    }
                    .padding(.top, 7)
                }
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.top, 14)
            .padding(.bottom, 16)

            AssistantProposalFooter(
                state: card.state,
                applyLabel: card.actions.first { $0.kind == .apply }?.label ?? "Zamień",
                reviseLabel: "Szukaj dalej",
                isBusy: isBusy,
                onApply: onApply,
                onRevise: { onAsk("Zaproponuj inną podmianę tego dania: \(card.to.title) mi nie pasuje.") },
                onAskNew: onAskNew,
                onUndo: onUndo,
                onOpenPlan: onOpenPlan
            )
        }
    }

    /// Jedna strona podmiany: miniatura 46, etykieta, nazwa, kcal.
    private func dish(_ side: SwapCardSideDTO, label: String, now: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            AssistantThumbnail(url: nil, size: 46, dimmed: now)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(now ? AssistantLook.faint(scheme) : AssistantLook.terra(scheme))
                Text(side.title)
                    .font(.system(size: 15.5, weight: now ? .medium : .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(AssistantLook.ink(scheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                CountingNumber(target: side.kcalPerServing)
                Text("kcal")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(now ? AssistantLook.muted(scheme) : AssistantLook.ink(scheme))
            .fixedSize()
        }
        .opacity(now ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Usunięcie posiłku

/// `LRemove`: propozycja, nie alert. „Powód propozycji” w cichym bloku.
struct AssistantRemoveMealCard: View {
    let card: RemoveMealCardDTO
    let isBusy: Bool
    let onApply: (_ force: Bool) -> Void
    let onRevise: () -> Void
    let onAskNew: () -> Void
    /// „Zostaw” — gotowe zdanie, że danie ma zostać.
    let onAsk: (String) -> Void
    var onUndo: (() -> Void)? = nil
    var onOpenPlan: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    private var status: AssistantCardStatus { AssistantCardStatus(card.state) }

    var body: some View {
        AssistantCard(tone: status.tone) {
            AssistantCardHead(eyebrow: card.eyebrow, title: card.title, status: status)

            VStack(alignment: .leading, spacing: 14) {
                AssistantMealRow(slot: nil, title: card.removed.title, kcal: card.removed.kcalPerServing, size: 46, titleWeight: .semibold)

                VStack(alignment: .leading, spacing: 4) {
                    AssistantCardLabel(text: "Powód propozycji")
                    Text(reason)
                        .font(.system(size: 14))
                        .lineSpacing(2)
                        .foregroundStyle(AssistantLook.muted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AssistantLook.wash(scheme)))
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.top, 14)
            .padding(.bottom, 16)

            AssistantProposalFooter(
                state: card.state,
                applyLabel: card.actions.first { $0.kind == .apply }?.label ?? "Usuń z planu",
                reviseLabel: "Zostaw",
                isBusy: isBusy,
                onApply: onApply,
                onRevise: { onAsk("Zostaw \(card.removed.title) w planie, niczego nie usuwaj.") },
                onAskNew: onAskNew,
                onUndo: onUndo,
                onOpenPlan: onOpenPlan
            )
        }
    }

    /// Powód od modelu; gdy nie zmieścił się w osobnym polu, jest w tytule.
    private var reason: String {
        if let note = card.note, !note.isEmpty { return note }
        return card.title
    }
}

// MARK: - Jedno danie, różne porcje

/// `LHousehold`: jedno danie, wiersz na osobę. Ograniczenie jako pigułka
/// w tincie terakoty — wyraźniejsza niż inicjał, bo to ona decyduje o porcji.
struct AssistantHouseholdSplitCard: View {
    let card: HouseholdSplitCardDTO
    let isBusy: Bool
    let onApply: (_ force: Bool) -> Void
    let onRevise: () -> Void
    let onAskNew: () -> Void
    var onUndo: (() -> Void)? = nil
    var onOpenPlan: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    private var status: AssistantCardStatus { AssistantCardStatus(card.state) }

    var body: some View {
        AssistantCard(tone: status.tone) {
            AssistantCardHead(eyebrow: card.eyebrow, title: "Jedno danie, różne porcje", status: status)

            AssistantMealRow(
                slot: card.prepTimeMinutes > 0 ? "Porcja bazowa · \(card.prepTimeMinutes) min" : "Porcja bazowa",
                title: card.title,
                size: 46,
                titleWeight: .semibold
            )
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.top, 14)
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(card.portions) { portion in
                    PortionRow(portion: portion)
                        .overlay(alignment: .top) { AssistantCardRule() }
                }
            }

            AssistantProposalFooter(
                state: card.state,
                applyLabel: card.actions.first { $0.kind == .apply }?.label ?? "Dodaj do planu",
                reviseLabel: "Zmień danie",
                isBusy: isBusy,
                onApply: onApply,
                onRevise: onRevise,
                onAskNew: onAskNew,
                onUndo: onUndo,
                onOpenPlan: onOpenPlan
            )
        }
    }

    private struct PortionRow: View {
        let portion: HouseholdSplitPortionDTO

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().fill(AssistantLook.ink(scheme).opacity(0.06))
                    Text(portion.initial)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(AssistantLook.muted(scheme))
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 7) {
                        Text(portion.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .tracking(-0.3)
                            .foregroundStyle(AssistantLook.ink(scheme))
                        if !portion.goalLabel.isEmpty {
                            Text(portion.goalLabel)
                                .font(.system(size: 11, weight: .bold))
                                .tracking(0.2)
                                .foregroundStyle(AssistantLook.terra(scheme))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(AssistantLook.terraTint(scheme)))
                                .lineLimit(1)
                        }
                    }
                    if let note = portion.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 13))
                            .foregroundStyle(AssistantLook.muted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                if portion.kcal > 0 {
                    HStack(spacing: 3) {
                        CountingNumber(target: portion.kcal)
                        Text("kcal")
                    }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(AssistantLook.muted(scheme))
                    .fixedSize()
                }
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Luka makro

/// `LMacroGap`: zdanie jako tytuł, cienka linia „średnio vs cel” (indygo
/// tylko jako akcent), propozycje jako wiersze prowadzące dalej. Nie dashboard.
struct AssistantMacroGapCard: View {
    let card: MacroGapCardDTO
    let onAsk: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AssistantCard {
            AssistantCardHead(eyebrow: card.eyebrow, title: card.title)

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 4) {
                        Text("Średnio")
                        HStack(spacing: 3) {
                            CountingNumber(target: card.current)
                            Text(card.unit)
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AssistantLook.ink(scheme))
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        Text("Cel")
                        Text("\(card.target) \(card.unit)")
                            .font(.system(size: 13, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(AssistantLook.ink(scheme))
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(AssistantLook.muted(scheme))

                AssistantTargetBar(value: card.current, target: card.target, color: AssistantLook.indigo(scheme))
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .accessibilityElement(children: .combine)

            if !card.boosters.isEmpty {
                boosters
            }
        }
    }

    private var boosters: some View {
        VStack(spacing: 0) {
            AssistantCardLabel(text: "Jak nadrobić")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AssistantCardMetrics.inset)
                .padding(.top, 10)
                .padding(.bottom, 2)
                .overlay(alignment: .top) { AssistantCardRule() }

            ForEach(Array(card.boosters.prefix(3).enumerated()), id: \.element.id) { index, booster in
                Button { onAsk(booster.askPrompt) } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Text(booster.text)
                            .font(.system(size: 15, weight: .medium))
                            .tracking(-0.3)
                            .foregroundStyle(AssistantLook.ink(scheme))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 8)

                        Text(booster.amountLabel(unit: card.unit))
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(AssistantLook.sage(scheme))

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AssistantLook.ink(scheme).opacity(0.35))
                    }
                    .padding(.horizontal, AssistantCardMetrics.inset)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlanPressStyle(scale: 0.985))
                .overlay(alignment: .top) {
                    if index > 0 { AssistantCardRule() }
                }
                .accessibilityHint("Wysyła pytanie o tę zmianę")
            }

            Color.clear.frame(height: 6)
        }
    }
}

// MARK: - Lista zakupów

/// `LShopping`: skrót listy — dwa działy rozwinięte, reszta jedną linią,
/// akcja otwiera pełną listę.
struct AssistantShoppingListCard: View {
    let card: ShoppingListCardDTO
    let onOpenShopping: () -> Void

    private static let maxGroups = 2
    private static let maxRows = 3

    @Environment(\.colorScheme) private var scheme

    private var visibleGroups: [ShoppingListCardGroupDTO] {
        Array(card.groups.prefix(Self.maxGroups))
    }

    private var hiddenGroups: [ShoppingListCardGroupDTO] {
        Array(card.groups.dropFirst(Self.maxGroups))
    }

    private var subtitle: String {
        let total = card.summary.remaining + card.summary.checked
        return "\(total) \(Self.itemsWord(total)) · \(card.summary.checked) \(Self.checkedWord(card.summary.checked))"
    }

    private var restLine: String? {
        guard !hiddenGroups.isEmpty else { return nil }
        let count = hiddenGroups.reduce(0) { $0 + $1.rows.count + ($1.hidden ?? 0) }
        let names = hiddenGroups.map(\.department)
        let joined = names.count > 2
            ? names.prefix(2).joined(separator: ", ") + " i inne"
            : names.joined(separator: " i ")
        return "\(joined) · \(count) \(Self.itemsWord(count))"
    }

    static func itemsWord(_ count: Int) -> String {
        if count == 1 { return "pozycja" }
        let mod100 = count % 100
        if (12...14).contains(mod100) { return "pozycji" }
        return (2...4).contains(count % 10) ? "pozycje" : "pozycji"
    }

    static func checkedWord(_ count: Int) -> String {
        if count == 1 { return "odhaczona" }
        let mod100 = count % 100
        if (12...14).contains(mod100) { return "odhaczonych" }
        return (2...4).contains(count % 10) ? "odhaczone" : "odhaczonych"
    }

    var body: some View {
        AssistantCard {
            AssistantCardHead(eyebrow: card.eyebrow, title: card.title, subtitle: card.checkedNote ?? subtitle)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(visibleGroups) { group in
                    GroupBlock(group: group, maxRows: Self.maxRows)
                }
            }
            .padding(.top, 4)

            if let restLine {
                Text(restLine)
                    .font(.system(size: 13))
                    .foregroundStyle(AssistantLook.faint(scheme))
                    .padding(.horizontal, AssistantCardMetrics.inset)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
            } else {
                Color.clear.frame(height: 14)
            }

            AssistantCardActions(
                primary: AssistantCardAction(title: "Otwórz listę", icon: "arrow.right", action: onOpenShopping)
            )
        }
    }

    private struct GroupBlock: View {
        let group: ShoppingListCardGroupDTO
        let maxRows: Int

        @Environment(\.colorScheme) private var scheme

        private var rows: [ShoppingListCardEntryDTO] { Array(group.rows.prefix(maxRows)) }
        private var done: Int { group.rows.filter(\.isChecked).count }

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.department)
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(AssistantLook.faint(scheme))
                    Spacer(minLength: 8)
                    Text("\(done) z \(group.rows.count)")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(AssistantLook.faint(scheme))
                }

                ForEach(rows) { entry in
                    HStack(spacing: 10) {
                        ZStack {
                            if entry.isChecked {
                                Circle().fill(AssistantLook.sage(scheme))
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundStyle(Color.white)
                            } else {
                                Circle().stroke(AssistantLook.ink(scheme).opacity(0.28), lineWidth: 1.5)
                            }
                        }
                        .frame(width: 20, height: 20)
                        Text(entry.label)
                            .font(.system(size: 15))
                            .tracking(-0.2)
                            .foregroundStyle(entry.isChecked ? AssistantLook.faint(scheme) : AssistantLook.ink(scheme))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 34)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(entry.isChecked ? "\(entry.label), kupione" : entry.label)
                }
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.top, 10)
            .padding(.bottom, 2)
        }
    }
}

// MARK: - Potwierdzenie zapisu

/// `LApplied`: ta sama karta „Propozycja” w stanie Zapisane — szałwia niesie
/// STAN (znak, eyebrow, plakietka), przyciski zostają w języku systemu:
/// Cofnij (poboczna) · Otwórz plan (główna).
struct AssistantAppliedCard: View {
    let card: AppliedCardDTO
    let isBusy: Bool
    let onUndo: () -> Void
    let onOpenPlan: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var status: AssistantCardStatus { AssistantCardStatus(card.state) }
    private var undoAction: AgentCardActionDTO? { card.actions.first { $0.kind == .undo } }
    private var openPlanLabel: String { card.actions.first { $0.kind == .openPlan }?.label ?? "Otwórz plan" }

    private var rows: [(String, Int)] {
        [
            ("Nowe pozycje", card.summary.created),
            ("Zmienione", card.summary.updated),
            ("Usunięte", card.summary.removed),
        ].filter { $0.1 > 0 }
    }

    var body: some View {
        AssistantCard(tone: status.tone) {
            AssistantCardHead(
                eyebrow: "Propozycja",
                mark: true,
                title: card.title,
                subtitle: card.subtitle,
                status: status
            )

            if !rows.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Text("·").foregroundStyle(AssistantLook.ink(scheme).opacity(0.3))
                        }
                        HStack(spacing: 4) {
                            CountingNumber(target: row.1)
                                .foregroundStyle(AssistantLook.ink(scheme))
                                .fontWeight(.semibold)
                            Text(row.0.lowercased())
                        }
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: 13))
                .foregroundStyle(AssistantLook.muted(scheme))
                .padding(.horizontal, AssistantCardMetrics.inset)
                .padding(.top, 14)
                .accessibilityElement(children: .combine)
            }

            ForEach(card.notes, id: \.self) { note in
                Text(note)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AssistantLook.faint(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AssistantCardMetrics.inset)
                    .padding(.top, 8)
            }

            Color.clear.frame(height: 16)

            if card.state.canUndo, let undoAction {
                AssistantCardActions(
                    primary: AssistantCardAction(title: openPlanLabel, icon: "arrow.right", action: onOpenPlan),
                    secondary: AssistantCardAction(title: undoAction.label, icon: "arrow.uturn.backward", action: onUndo),
                    tone: .sage,
                    isBusy: isBusy
                )
            } else {
                AssistantCardActions(
                    primary: AssistantCardAction(title: openPlanLabel, icon: "arrow.right", action: onOpenPlan),
                    tone: .sage
                )
            }
        }
    }
}
