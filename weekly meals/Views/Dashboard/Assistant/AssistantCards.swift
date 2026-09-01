import SwiftUI

// Karty asystenta — propozycja tygodnia i potwierdzenie zapisu.
//
// Cała treść przychodzi z serwera GOTOWA: nazwy dni, etykiety posiłków,
// napisy na przyciskach, liczby. Ten plik jej nie liczy i nie tłumaczy —
// układa ją i decyduje, co się dzieje po dotknięciu. Dzięki temu nowy rodzaj
// karty po stronie serwera nie wymaga wydania aplikacji, a stary build nie
// pokaże nigdy liczby, której serwer już nie uznaje.

// MARK: - Propozycja tygodnia

/// Propozycja planu — tydzień do obejrzenia, zanim cokolwiek się zapisze.
///
/// Przycisk jest W KARCIE, a nie na dole ekranu: użytkownik zatwierdza TO,
/// na co właśnie patrzy, i po tygodniu w historii dalej widać, co dokładnie
/// zostało zatwierdzone.
struct AssistantPlanWeekCard: View {
    let card: PlanWeekCardDTO
    let isBusy: Bool
    let onApply: () -> Void
    let onRevise: () -> Void

    /// Ile dni widać przed rozwinięciem. Trzy, bo tyle mieści się na ekranie
    /// bez przewijania — a karta ma być do ogarnięcia jednym spojrzeniem.
    private static let previewDays = 3

    @State private var isExpanded = false
    @Environment(\.colorScheme) private var scheme

    private var visibleDays: [PlanWeekCardDayDTO] {
        isExpanded ? card.days : Array(card.days.prefix(Self.previewDays))
    }

    private var hiddenDaysCount: Int {
        max(0, card.days.count - Self.previewDays)
    }

    var body: some View {
        AssistantCard(tone: .neutral) {
            AssistantCardHead(eyebrow: "Propozycja", title: card.title) {
                mealsBadge
            }

            if let subtitle = card.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            VStack(spacing: 0) {
                ForEach(visibleDays) { day in
                    DayRow(day: day)
                    if day.id != visibleDays.last?.id {
                        Rectangle()
                            .fill(Color.wmRule(scheme))
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                }
            }

            if hiddenDaysCount > 0 {
                expandButton
            }

            if !card.removed.isEmpty {
                removals
            }

            goalBar

            footer
        }
    }

    private var mealsBadge: some View {
        Text("\(card.summary.meals) \(Self.mealsWord(card.summary.meals))")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.wmMuted(scheme))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Color.wmChipBg(scheme)))
    }

    private var expandButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(
                    isExpanded
                        ? "Pokaż mniej"
                        : "Pokaż pozostałe \(hiddenDaysCount) \(Self.daysWord(hiddenDaysCount))"
                )
                .font(.system(size: 13, weight: .semibold))
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(WMPalette.terracotta)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.wmRule(scheme)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    /// Co ZNIKNIE po zapisaniu. Zmiana planu nigdy nie jest cicha — inaczej
    /// użytkownik dowiaduje się o niej dopiero w zakładce Plan.
    private var removals: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Zniknie z planu")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(WMPalette.butter)

            ForEach(card.removed) { item in
                Text("\(item.dayLabel), \(item.mealLabel.lowercased()): \(item.title)")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .strikethrough(true, color: Color.wmStrike(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.wmButterTint(scheme))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.wmRule(scheme)).frame(height: 1)
        }
    }

    /// Średnia dnia wobec celu — jedna kreska mówi więcej niż dwie liczby.
    @ViewBuilder
    private var goalBar: some View {
        let average = card.summary.averageKcalPerDay
        let target = card.summary.targetKcalPerDay

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Średnio na dzień")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.wmMuted(scheme))
                Spacer(minLength: 8)
                Text(target.map { "\(average) / \($0) kcal" } ?? "\(average) kcal")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.wmLabel(scheme))
            }

            if let target, target > 0 {
                GeometryReader { geometry in
                    let ratio = min(Double(average) / Double(target), 1.4)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.wmBarTrack(scheme))
                        Capsule()
                            .fill(Self.goalColor(ratio: ratio))
                            .frame(width: geometry.size.width * min(ratio / 1.4, 1))
                        // Kreska celu: bez niej pasek pokazuje „ile", ale nie
                        // „ile powinno" — a to jest cała informacja.
                        Rectangle()
                            .fill(Color.wmLabel(scheme).opacity(0.45))
                            .frame(width: 1.5)
                            .offset(x: geometry.size.width * (1 / 1.4))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.wmRule(scheme)).frame(height: 1)
        }
    }

    /// Przyciski albo — gdy klikać już nie ma czego — jedno zdanie dlaczego.
    @ViewBuilder
    private var footer: some View {
        if card.state.canApply {
            AssistantCardActions(
                primaryTitle: applyLabel,
                primaryIcon: "checkmark",
                isBusy: isBusy,
                secondaryTitle: "Zmień",
                secondaryIcon: "slider.horizontal.3",
                onSecondary: onRevise,
                onPrimary: onApply
            )
        } else {
            AssistantCardStatusFooter(state: card.state)
        }
    }

    private var applyLabel: String {
        card.actions.first { $0.type == .apply }?.label ?? "Dodaj do planu"
    }

    private static func goalColor(ratio: Double) -> Color {
        // Zielony w okolicy celu, masło poza nim. Nie czerwony: to jest plan
        // posiłków, a nie ostrzeżenie — 300 kcal obok celu to nie awaria.
        (0.85...1.15).contains(ratio) ? WMPalette.sage : WMPalette.butter
    }

    private static func mealsWord(_ count: Int) -> String {
        pluralize(count, one: "danie", few: "dania", many: "dań")
    }

    private static func daysWord(_ count: Int) -> String {
        pluralize(count, one: "dzień", few: "dni", many: "dni")
    }

    /// Polska odmiana po liczbie — „1 danie", „3 dania", „5 dań".
    static func pluralize(_ count: Int, one: String, few: String, many: String) -> String {
        let mod100 = count % 100
        if count == 1 { return one }
        if (12...14).contains(mod100) { return many }
        return (2...4).contains(count % 10) ? few : many
    }

    private struct DayRow: View {
        let day: PlanWeekCardDayDTO

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(day.dayLabel)
                        .font(.system(size: 14, weight: .bold))
                        .tracking(-0.2)
                        .foregroundStyle(Color.wmLabel(scheme))
                    Spacer(minLength: 8)
                    if day.kcalTotal > 0 {
                        Text("\(day.kcalTotal) kcal")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(Color.wmFaint(scheme))
                    }
                }

                ForEach(day.slots) { slot in
                    HStack(alignment: .top, spacing: 8) {
                        // Kropka „nowe" tylko przy tym, co propozycja zmienia
                        // — reszta dnia zostaje taka, jaka była.
                        Circle()
                            .fill(slot.isNew ? WMPalette.terracotta : Color.clear)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(slot.title)
                                .font(.system(size: 14))
                                .foregroundStyle(Color.wmLabel(scheme))
                                .fixedSize(horizontal: false, vertical: true)

                            Text(detail(for: slot))
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color.wmFaint(scheme))
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }

        private func detail(for slot: PlanWeekCardSlotDTO) -> String {
            var parts = [slot.mealLabel]
            if slot.kcalPerServing > 0 { parts.append("\(slot.kcalPerServing) kcal") }
            if slot.prepTimeMinutes > 0 { parts.append("\(slot.prepTimeMinutes) min") }
            return parts.joined(separator: " · ")
        }
    }
}

// MARK: - Potwierdzenie zapisu

/// „Zapisałem" z „Cofnij" — w WIADOMOŚCI, nie w toaście.
///
/// Toast znika po trzech sekundach i zabiera ze sobą jedyną drogę odwrotu.
/// Wiadomość zostaje w rozmowie, więc cofnięcie jest tam, gdzie użytkownik
/// będzie go szukał: przy zmianie, która go zaskoczyła.
struct AssistantAppliedCard: View {
    let card: AppliedCardDTO
    let isBusy: Bool
    let onUndo: () -> Void
    let onOpenPlan: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var undoAction: AgentCardActionDTO? {
        card.actions.first { $0.type == .undo }
    }

    var body: some View {
        AssistantCard(tone: .sage) {
            AssistantCardHead(
                eyebrow: "Zapisano",
                eyebrowColor: WMPalette.sage,
                title: card.title
            ) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(WMPalette.sage)
            }

            if !summaryText.isEmpty {
                Text(summaryText)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .padding(.horizontal, 16)
                    .padding(.bottom, card.notes.isEmpty ? 12 : 8)
            }

            ForEach(card.notes, id: \.self) { note in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wmFaint(scheme))
                        .padding(.top, 1)
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            if card.state.canUndo, let undoAction {
                AssistantCardActions(
                    primaryTitle: openPlanLabel,
                    primaryIcon: "calendar",
                    isBusy: isBusy,
                    secondaryTitle: undoAction.label,
                    secondaryIcon: "arrow.uturn.backward",
                    onSecondary: onUndo,
                    onPrimary: onOpenPlan
                )
            } else {
                AssistantCardActions(
                    primaryTitle: openPlanLabel,
                    primaryIcon: "calendar",
                    isBusy: isBusy,
                    onPrimary: onOpenPlan
                )
            }
        }
    }

    private var openPlanLabel: String {
        card.actions.first { $0.type == .openPlan }?.label ?? "Otwórz Plan tygodnia"
    }

    private var summaryText: String {
        var parts: [String] = []
        if card.summary.created > 0 {
            parts.append("dodane: \(card.summary.created)")
        }
        if card.summary.updated > 0 {
            parts.append("zmienione: \(card.summary.updated)")
        }
        if card.summary.removed > 0 {
            parts.append("usunięte: \(card.summary.removed)")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Stopka stanu

/// Karta, w której nie ma już czego kliknąć — z powodem.
///
/// Sam wyszarzony przycisk mówiłby „nie da się" i nic więcej. Tydzień
/// zmieniony przez kogoś w domu, wygaśnięcie i zapis to trzy różne historie
/// i tylko po nazwie tej właściwej wiadomo, co zrobić dalej.
struct AssistantCardStatusFooter: View {
    let state: AgentCardStateDTO

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color.wmMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.wmRule(scheme)).frame(height: 1)
        }
    }

    private var icon: String {
        switch state.status {
        case "APPLIED": return "checkmark.circle.fill"
        case "UNDONE": return "arrow.uturn.backward.circle"
        default: return "clock.badge.exclamationmark"
        }
    }

    private var tint: Color {
        switch state.status {
        case "APPLIED": return WMPalette.sage
        case "UNDONE": return Color.wmFaint(scheme)
        default: return WMPalette.butter
        }
    }

    private var text: String {
        switch state.status {
        case "APPLIED": return "Ta propozycja jest już w planie."
        case "UNDONE": return "Zapis został cofnięty."
        case "STALE": return "Plan zmienił się od czasu tej propozycji."
        case "EXPIRED": return "Ta propozycja jest już nieaktualna."
        case "FAILED": return "Tej propozycji nie udało się zapisać."
        default: return "Tej propozycji nie da się już zatwierdzić."
        }
    }
}
