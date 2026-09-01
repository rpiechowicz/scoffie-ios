import SwiftUI

// Karty asystenta — propozycja tygodnia, propozycja dnia, pytanie
// i potwierdzenie zapisu.
//
// Cała treść przychodzi z serwera GOTOWA: nazwy dni, etykiety posiłków,
// napisy na przyciskach, liczby, zdania o celu. Ten plik jej nie liczy
// i nie tłumaczy — układa ją i decyduje, co się dzieje po dotknięciu.
// Dzięki temu nowy rodzaj karty po stronie serwera nie wymaga wydania
// aplikacji, a stary build nie pokaże nigdy liczby, której serwer już nie uznaje.

// MARK: - Wspólne atomy kart

/// Nadtytuł karty. Gdy serwer go nie przysłał (starszy build kontraktu),
/// zostaje wartość zapasowa — karta bez nadtytułu wygląda na niedokończoną.
private struct CardEyebrowFallback {
    static let planWeek = "Propozycja planu"
    static let planDay = "Propozycja dnia"
}

/// Wiersz posiłku: etykieta slotu w stałej kolumnie, nazwa dania obok.
///
/// Stała szerokość kolumny jest tu informacją, nie ozdobą: siedem dni
/// czyta się w pionie i nazwy dań muszą zaczynać się w jednej linii,
/// inaczej wzrok szuka ich od nowa przy każdym wierszu.
private struct MealLine: View {
    let slot: String
    let title: String
    var dimmed: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(slot)
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(Color.wmFaint(scheme))
                .frame(width: 62, alignment: .leading)

            Text(title)
                .font(.system(size: 13.5, weight: .medium))
                .tracking(-0.2)
                .foregroundStyle(dimmed ? Color.wmMuted(scheme) : Color.wmLabel(scheme))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
    }
}

/// Pasek celu: gdzie plan ląduje wobec normy.
///
/// Kreska celu jest częścią informacji — bez niej pasek mówi „ile", ale nie
/// „ile powinno", a to jest cała treść tego elementu.
private struct TargetBar: View {
    let label: String
    let value: Int
    let target: Int?
    let note: String?

    /// Ile ponad cel jeszcze mieści się w pasku. 1,25× zostawia miejsce na
    /// przekroczenie i nie spłaszcza typowego wyniku do połowy szerokości.
    private static let headroom = 1.25

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 12.5))
                    .tracking(-0.15)
                    .foregroundStyle(Color.wmMuted(scheme))
                Spacer(minLength: 8)
                Text("\(value)")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.3)
                    .monospacedDigit()
                    .foregroundStyle(Color.wmLabel(scheme))
            }

            if let target, target > 0 {
                GeometryReader { geometry in
                    let full = Double(target) * Self.headroom
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.wmBarTrack(scheme))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [WMPalette.terracottaDeep, WMPalette.terracotta],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * min(Double(value) / full, 1))
                        Rectangle()
                            .fill(Color.wmLabel(scheme).opacity(0.85))
                            .frame(width: 2)
                            .offset(x: geometry.size.width / Self.headroom)
                    }
                }
                .frame(height: 7)

                HStack {
                    Text("Twój cel \(target) kcal")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Color.wmFaint(scheme))
                    Spacer(minLength: 8)
                    if let note {
                        Text(note)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WMPalette.sage)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.wmRule(scheme)).frame(height: 1)
        }
    }
}

/// „Zniknie z planu” — zmiana planu nigdy nie jest cicha.
private struct RemovalsSection: View {
    let removals: [PlanWeekCardRemovalDTO]
    /// Karta dnia mówi o jednym dniu, więc powtarzanie w niej nazwy dnia
    /// przy każdej pozycji jest szumem.
    var showsDay: Bool = true

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Zniknie z planu")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(WMPalette.butter)

            ForEach(removals) { item in
                Text(line(for: item))
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

    private func line(for item: PlanWeekCardRemovalDTO) -> String {
        showsDay
            ? "\(item.dayLabel), \(item.mealLabel.lowercased()): \(item.title)"
            : "\(item.mealLabel): \(item.title)"
    }
}

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
            AssistantCardHead(
                eyebrow: card.eyebrow ?? CardEyebrowFallback.planWeek,
                title: card.title
            ) {
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
                    DayBlock(day: day)
                        .overlay(alignment: .top) {
                            if day.id != visibleDays.first?.id {
                                Rectangle()
                                    .fill(Color.wmRule(scheme))
                                    .frame(height: 1)
                                    .padding(.leading, 16)
                            }
                        }
                }
            }

            if hiddenDaysCount > 0 {
                expandButton
            }

            if !card.removed.isEmpty {
                RemovalsSection(removals: card.removed)
            }

            TargetBar(
                label: "Średnio dziennie",
                value: card.summary.averageKcalPerDay,
                target: card.summary.targetKcalPerDay,
                note: card.summary.goalNote
            )

            footer
        }
    }

    private var mealsBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "fork.knife")
                .font(.system(size: 10, weight: .semibold))
            Text("\(card.summary.meals)")
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(Color.wmMuted(scheme))
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Capsule().fill(Color.wmChipBg(scheme)))
    }

    private var expandButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(isExpanded ? "Pokaż mniej" : "Pokaż pozostałe dni")
                    .font(.system(size: 13.5, weight: .semibold))
                    .tracking(-0.2)
                if !isExpanded {
                    Text("\(hiddenDaysCount)")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .opacity(0.7)
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(WMPalette.terracotta)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.wmRule(scheme)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

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

    private struct DayBlock: View {
        let day: PlanWeekCardDayDTO

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(day.shortName)
                        .font(.system(size: 12, weight: .bold))
                        .tracking(-0.1)
                        .foregroundStyle(Color.wmLabel(scheme))
                    if let dateLabel = day.dateLabel {
                        Text(dateLabel)
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.wmFaint(scheme))
                    }
                    Spacer(minLength: 8)
                    if day.kcalTotal > 0 {
                        Text("\(day.kcalTotal) kcal")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(Color.wmFaint(scheme))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(day.slots) { slot in
                        MealLine(
                            slot: slot.mealLabel,
                            title: slot.title,
                            // Wyszarzone jest to, co ZOSTAJE — wzrok ma
                            // trafiać w to, co propozycja naprawdę zmienia.
                            dimmed: !slot.isNew
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 9)
            .padding(.bottom, 10)
        }
    }
}

// MARK: - Propozycja dnia

/// Jeden dzień: posiłek po posiłku, z sumą wobec celu.
///
/// Tydzień pokazuje układ, dzień pokazuje talerz — dlatego to osobna karta,
/// a nie tydzień z jednym wierszem.
struct AssistantPlanDayCard: View {
    let card: PlanDayCardDTO
    let isBusy: Bool
    let onApply: () -> Void
    let onRevise: () -> Void

    /// Kolory pasków przy posiłkach — kolejność dnia, nie znaczenie.
    /// Poranek jest ciepły, wieczór chłodny; to jedyna treść tego koloru.
    private static let rails: [Color] = [
        WMPalette.butter, WMPalette.terracotta, WMPalette.indigo, WMPalette.sage,
    ]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AssistantCard(tone: .neutral) {
            AssistantCardHead(
                eyebrow: card.eyebrow ?? CardEyebrowFallback.planDay,
                title: card.title
            ) {
                EmptyView()
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
                ForEach(Array(card.slots.enumerated()), id: \.element.id) { index, slot in
                    MealRow(
                        slot: slot,
                        rail: Self.rails[index % Self.rails.count]
                    )
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.wmRule(scheme))
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                }
            }

            if !card.removed.isEmpty {
                RemovalsSection(removals: card.removed, showsDay: false)
            }

            total

            footer
        }
    }

    /// „Razem 1 872 z 2 100 kcal” — jedna linia, która odpowiada na pytanie,
    /// po które użytkownik otworzył tę kartę.
    private var total: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(totalLabel)
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(Color.wmMuted(scheme))

                if let target = card.summary.targetKcalPerDay, target > 0 {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.wmBarTrack(scheme))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [WMPalette.terracottaDeep, WMPalette.terracotta],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: geometry.size.width
                                        * min(Double(card.summary.kcalTotal) / Double(target), 1)
                                )
                        }
                    }
                    .frame(height: 7)
                }
            }

            if let note = card.summary.goalNote {
                Text(note)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(WMPalette.sage)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(Color.wmSageTint(scheme)))
                    .overlay(Capsule().stroke(WMPalette.sage.opacity(0.24), lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.wmRule(scheme)).frame(height: 1)
        }
    }

    private var totalLabel: String {
        guard let target = card.summary.targetKcalPerDay, target > 0 else {
            return "Razem \(card.summary.kcalTotal) kcal"
        }
        return "Razem \(card.summary.kcalTotal) z \(target) kcal"
    }

    @ViewBuilder
    private var footer: some View {
        if card.state.canApply {
            AssistantCardActions(
                primaryTitle: applyLabel,
                primaryIcon: "checkmark",
                isBusy: isBusy,
                secondaryTitle: "Inny zestaw",
                secondaryIcon: "arrow.triangle.2.circlepath",
                onSecondary: onRevise,
                onPrimary: onApply
            )
        } else {
            AssistantCardStatusFooter(state: card.state)
        }
    }

    private var applyLabel: String {
        card.actions.first { $0.type == .apply }?.label ?? "Zapisz dzień"
    }

    private struct MealRow: View {
        let slot: PlanWeekCardSlotDTO
        let rail: Color

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                Capsule()
                    .fill(rail.opacity(0.85))
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.mealLabel)
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.7)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.wmFaint(scheme))

                    Text(slot.title)
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.25)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if slot.prepTimeMinutes > 0 {
                        Text("\(slot.prepTimeMinutes) min")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.wmMuted(scheme))
                    }
                }

                Spacer(minLength: 8)

                if slot.kcalPerServing > 0 {
                    Text("\(slot.kcalPerServing)")
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.wmLabel(scheme))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Pytanie z gotowymi odpowiedziami

/// Pytanie, które da się odpowiedzieć dotknięciem.
///
/// Nie jest kartą w ramce, tylko wiadomością z pionową kreską — bo to wciąż
/// wypowiedź asystenta, a nie zestawienie danych. Odpowiedzi wysyłają się jak
/// zwykłe wiadomości, więc w historii zostaje to, co użytkownik „powiedział".
struct AssistantClarifyCard: View {
    let card: ClarifyCardDTO
    let onAsk: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(WMPalette.butter.opacity(0.8))
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.question)
                        .font(.system(size: 15.5))
                        .foregroundStyle(Color.wmLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    if let hint = card.hint, !hint.isEmpty {
                        Text(hint)
                            .font(.system(size: 13))
                            .tracking(-0.15)
                            .foregroundStyle(Color.wmMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            AssistantAnswerChips(actions: card.actions, onAsk: onAsk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Gotowe odpowiedzi jako przyciski. Pierwsza jest wyróżniona, bo model
/// wymienia je od najbardziej prawdopodobnej — cztery równorzędne przyciski
/// oddawałyby decyzję z powrotem użytkownikowi.
struct AssistantAnswerChips: View {
    let actions: [AgentCardActionDTO]
    let onAsk: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AllergenChipFlow(spacing: 7) {
            ForEach(actions) { action in
                Button {
                    onAsk(action.prompt ?? action.label)
                } label: {
                    Text(action.label)
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(
                            action.isPrimary ? WMPalette.butter : Color.wmLabel(scheme)
                        )
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(
                            Capsule().fill(
                                action.isPrimary
                                    ? Color.wmButterTint(scheme)
                                    : Color.wmTileBg(scheme)
                            )
                        )
                        .overlay(
                            Capsule().stroke(
                                action.isPrimary
                                    ? WMPalette.butter.opacity(0.34)
                                    : Color.wmTileStroke(scheme),
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Potwierdzenie zapisu

/// „Zapisano" z „Cofnij" — w WIADOMOŚCI, nie w toaście.
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
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().fill(WMPalette.sage.opacity(0.22))
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(WMPalette.sage)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.system(size: 15, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.wmLabel(scheme))

                    if let subtitle = card.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12.5))
                            .tracking(-0.15)
                            .foregroundStyle(Color.wmMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

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
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            actions
        }
    }

    /// Przyciski karty zapisu są SPOKOJNE — pełny terakotowy guzik krzyczałby
    /// o coś, co już się stało. „Cofnij" jest obok, ale nie wyżej: cofanie ma
    /// być łatwe do znalezienia, nie łatwiejsze niż otwarcie planu.
    private var actions: some View {
        HStack(spacing: 8) {
            if card.state.canUndo, let undoAction {
                Button(action: onUndo) {
                    HStack(spacing: 6) {
                        if isBusy {
                            ProgressView().controlSize(.small).tint(Color.wmMuted(scheme))
                        } else {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.wmMuted(scheme))
                        }
                        Text(undoAction.label)
                            .font(.system(size: 14, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(Color.wmLabel(scheme))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(Capsule().fill(Color.wmTileBg(scheme)))
                    .overlay(Capsule().stroke(Color.wmTileStroke(scheme), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }

            Button(action: onOpenPlan) {
                HStack(spacing: 6) {
                    Text(openPlanLabel)
                        .font(.system(size: 14, weight: .bold))
                        .tracking(-0.2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(WMPalette.sage)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Capsule().fill(WMPalette.sage.opacity(0.18)))
                .overlay(Capsule().stroke(WMPalette.sage.opacity(0.34), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var openPlanLabel: String {
        card.actions.first { $0.type == .openPlan }?.label ?? "Otwórz Plan tygodnia"
    }
}
