import SwiftUI

// Karty asystenta — propozycja tygodnia i dnia, pytanie, dania do wyboru,
// podmiana, usunięcie, podział na domowników, luka makro, zakupy, zapis.
//
// Cała treść przychodzi z serwera GOTOWA: nazwy dni, etykiety posiłków,
// napisy na przyciskach, liczby, zdania o celu. Ten plik jej nie liczy
// i nie tłumaczy — układa ją na wspólnych atomach z `AssistantCardKit`
// i decyduje, co się dzieje po dotknięciu. Nowy rodzaj karty po stronie
// serwera nie wymaga wydania aplikacji, a stary build nie pokaże nigdy
// liczby, której serwer już nie uznaje.

// MARK: - Wspólne wiersze

/// Nadtytuł zapasowy, gdy serwer go nie przysłał (starszy kontrakt).
private enum CardEyebrowFallback {
    static let planWeek = "Propozycja planu"
    static let planDay = "Propozycja dnia"
}

/// Wiersz posiłku w stałych kolumnach: miniatura · pora · danie · kcal.
///
/// Stała kolumna pory jest informacją, nie ozdobą: siedem dni czyta się
/// w pionie i nazwy dań muszą zaczynać się w jednej linii, inaczej wzrok
/// szuka ich od nowa przy każdym wierszu.
private struct MealLine: View {
    let slot: String
    let title: String
    var imageUrl: String?
    var kcal: Int = 0
    var minutes: Int = 0
    /// Wyszarzone jest to, co ZOSTAJE — wzrok ma trafiać w to, co
    /// propozycja naprawdę zmienia.
    var dimmed: Bool = false

    /// Musi zmieścić „II ŚNIADANIE” bez łamania.
    private static let slotColumn: CGFloat = 78

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AssistantThumbnail(url: imageUrl.flatMap(URL.init(string:)), size: 32, dimmed: dimmed)

            Text(slot)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.scFaint(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: Self.slotColumn, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(dimmed ? Color.scMuted(scheme) : Color.scLabel(scheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if minutes > 0 {
                    Text("\(minutes) min")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.scFaint(scheme))
                }
            }

            Spacer(minLength: 6)

            if kcal > 0 {
                Text("\(kcal)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(dimmed ? Color.scFaint(scheme) : Color.scLabel(scheme))
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Pasek celu: gdzie plan ląduje wobec normy.
private struct TargetSummary: View {
    let label: String
    let value: Int
    let target: Int?
    let note: String?
    var unit: String = "kcal"

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AssistantCardSummaryRow(label: label, value: "\(value) \(unit)")

            if let target, target > 0 {
                AssistantTargetBar(value: value, target: target)

                HStack {
                    Text("Twój cel \(target) \(unit)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Color.scFaint(scheme))
                    Spacer(minLength: 8)
                    if let note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SCPalette.sage)
                    }
                }
            }
        }
        .padding(.horizontal, AssistantCardMetrics.inset)
        .padding(.vertical, AssistantCardMetrics.section)
        .overlay(alignment: .top) { AssistantCardRule() }
        .accessibilityElement(children: .combine)
    }
}

/// „Zniknie z planu” — zmiana planu nigdy nie jest cicha.
private struct RemovalsSection: View {
    let removals: [PlanWeekCardRemovalDTO]
    /// Karta dnia mówi o jednym dniu — nazwa dnia przy każdej pozycji to szum.
    var showsDay: Bool = true

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AssistantCardLabel(text: "Zniknie z planu · \(removals.count)", color: Color.scMuted(scheme))

            ForEach(removals) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(line(for: item))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.scMuted(scheme))
                        .strikethrough(true, color: Color.scStrike(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    // Powód po prawej („powtórka”, „ponad cel”) to jedno słowo
                    // od modelu — bez niego zniknięcie wygląda na przypadek.
                    if let reason = item.reason, !reason.isEmpty {
                        Text(reason)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.scFaint(scheme))
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AssistantCardMetrics.inset)
        .padding(.vertical, AssistantCardMetrics.section)
        .background(Color.scInsetSurface(scheme).opacity(scheme == .dark ? 1 : 0.6))
        .overlay(alignment: .top) { AssistantCardRule() }
    }

    private func line(for item: PlanWeekCardRemovalDTO) -> String {
        showsDay
            ? "\(item.dayLabel), \(item.mealLabel.lowercased()): \(item.title)"
            : "\(item.mealLabel): \(item.title)"
    }
}

// MARK: - Propozycja tygodnia

/// Propozycja planu — tydzień do obejrzenia, zanim cokolwiek się zapisze.
///
/// Siedem dni w pasku, JEDEN dzień rozwinięty pod nim (stuknięcie w pasek
/// przełącza), „Pokaż pozostałe dni” rozkłada resztę. Nie pokazujemy siedmiu
/// dni naraz: karta ma być do ogarnięcia jednym spojrzeniem, a przycisk
/// „Dodaj do planu” ma zawsze mieć miejsce bez przewijania pół ekranu.
struct AssistantPlanWeekCard: View {
    let card: PlanWeekCardDTO
    let isBusy: Bool
    /// Rozwinięcie należy do ekranu rozmowy, nie do karty: karta ostatniej
    /// tury zmienia miejsce w drzewie po następnym pytaniu i `@State`
    /// zwijałby tydzień skokiem w klatce wysyłki.
    @Binding var isExpanded: Bool
    let onApply: (_ force: Bool) -> Void
    let onRevise: () -> Void
    let onAskNew: () -> Void
    var onUndo: (() -> Void)? = nil
    var onOpenPlan: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    /// Dzień rozwinięty pod paskiem. `nil` = pierwszy dzień ze zmianą.
    @State private var selectedDayId: String?

    private var status: AssistantCardStatus { AssistantCardStatus(card.state) }

    private var focusedDay: PlanWeekCardDayDTO? {
        if let selectedDayId, let day = card.days.first(where: { $0.id == selectedDayId }) {
            return day
        }
        return card.days.first { day in day.slots.contains { $0.isNew } } ?? card.days.first
    }

    private var otherDays: [PlanWeekCardDayDTO] {
        card.days.filter { $0.id != focusedDay?.id }
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
                dayStrip
            }

            if let day = focusedDay {
                DayBlock(day: day, emphasized: true)
                    .overlay(alignment: .top) { AssistantCardRule() }
            }

            if isExpanded {
                ForEach(otherDays) { day in
                    DayBlock(day: day, emphasized: false)
                        .overlay(alignment: .top) { AssistantCardRule(leadingInset: AssistantCardMetrics.inset) }
                        .transition(.opacity)
                }
            }

            if !otherDays.isEmpty {
                expandButton
            }

            if !card.removed.isEmpty {
                RemovalsSection(removals: card.removed)
            }

            TargetSummary(
                label: "Średnio dziennie",
                value: card.summary.averageKcalPerDay,
                target: card.summary.targetKcalPerDay,
                note: card.summary.goalNote
            )

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

    /// Pasek dni: skrót, miniatura pierwszego nowego dania, kropka „ma zmiany”.
    private var dayStrip: some View {
        HStack(spacing: 6) {
            ForEach(card.days) { day in
                let selected = day.id == focusedDay?.id
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedDayId = day.id }
                } label: {
                    VStack(spacing: 5) {
                        Text(day.shortName)
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(0.2)
                            .foregroundStyle(selected ? SCPalette.terracotta : Color.scMuted(scheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        AssistantThumbnail(
                            url: (day.slots.first { $0.isNew } ?? day.slots.first)?.imageUrl.flatMap(URL.init(string:)),
                            size: 34
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(selected ? SCPalette.terracotta : Color.clear, lineWidth: 1.5)
                        )
                        Circle()
                            .fill(day.slots.contains { $0.isNew } ? SCPalette.terracotta : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: AssistantCardMetrics.innerRadius, style: .continuous)
                            .fill(selected ? Color.scAccentTint(scheme) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(day.dayLabel), \(day.kcalTotal) kcal")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, AssistantCardMetrics.footerInset)
        .padding(.bottom, 8)
    }

    private var expandButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(isExpanded ? "Pokaż mniej" : "Pokaż pozostałe dni")
                    .font(.system(size: 13.5, weight: .semibold))
                    .tracking(-0.2)
                if !isExpanded {
                    Text("\(otherDays.count)")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .opacity(0.7)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .foregroundStyle(SCPalette.terracotta)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { AssistantCardRule() }
        }
        .buttonStyle(.plain)
        .accessibilityHint(isExpanded ? "Zwija pozostałe dni" : "Rozwija pozostałe dni")
    }

    private var applyLabel: String {
        card.actions.first { $0.kind == .apply }?.label ?? "Dodaj do planu"
    }

    private struct DayBlock: View {
        let day: PlanWeekCardDayDTO
        let emphasized: Bool

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            VStack(alignment: .leading, spacing: emphasized ? 6 : 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(emphasized ? day.dayLabel : day.shortName)
                        .font(.system(size: emphasized ? 13 : 12, weight: .bold))
                        .tracking(-0.1)
                        .foregroundStyle(Color.scLabel(scheme))
                    if let dateLabel = day.dateLabel {
                        Text(dateLabel)
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.scFaint(scheme))
                    }
                    Spacer(minLength: 8)
                    if day.kcalTotal > 0 {
                        Text("\(day.kcalTotal) kcal")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(Color.scFaint(scheme))
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(day.slots) { slot in
                        MealLine(
                            slot: slot.mealLabel,
                            title: slot.title,
                            imageUrl: slot.imageUrl,
                            kcal: emphasized ? slot.kcalPerServing : 0,
                            minutes: emphasized ? slot.prepTimeMinutes : 0,
                            dimmed: !slot.isNew
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.top, emphasized ? 12 : 9)
            .padding(.bottom, emphasized ? 10 : 8)
        }
    }
}

// MARK: - Propozycja dnia

/// Jeden dzień: posiłek po posiłku, z sumą wobec celu.
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

    var body: some View {
        AssistantCard(tone: status.tone) {
            AssistantCardHead(
                eyebrow: card.eyebrow ?? CardEyebrowFallback.planDay,
                eyebrowDetail: card.eyebrowDetail,
                title: card.title,
                subtitle: card.subtitle,
                status: status
            )

            VStack(alignment: .leading, spacing: 0) {
                ForEach(card.slots) { slot in
                    MealLine(
                        slot: slot.mealLabel,
                        title: slot.title,
                        imageUrl: slot.imageUrl,
                        kcal: slot.kcalPerServing,
                        minutes: slot.prepTimeMinutes,
                        dimmed: !slot.isNew
                    )
                }
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.vertical, 6)
            .overlay(alignment: .top) { AssistantCardRule() }

            if !card.removed.isEmpty {
                RemovalsSection(removals: card.removed, showsDay: false)
            }

            TargetSummary(
                label: "Razem",
                value: card.summary.kcalTotal,
                target: card.summary.targetKcalPerDay,
                note: card.summary.goalNote
            )

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

/// Pytanie, które da się odpowiedzieć dotknięciem.
///
/// Nie karta w ramce, tylko wypowiedź z pionową kreską — to wciąż zdanie
/// asystenta, a nie zestawienie danych. Odpowiedzi wysyłają się jak zwykłe
/// wiadomości, więc w historii zostaje to, co użytkownik „powiedział”.
struct AssistantClarifyCard: View {
    let card: ClarifyCardDTO
    /// Co użytkownik odpowiedział (jego następna wiadomość) — po odpowiedzi
    /// zaznaczona jest wybrana opcja, nie „najbardziej prawdopodobna”.
    var reply: String? = nil
    let onAsk: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(SCPalette.terracotta.opacity(0.7))
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.question)
                        .font(.system(size: 15.5))
                        .foregroundStyle(Color.scLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    if let hint = card.hint, !hint.isEmpty {
                        Text(hint)
                            .font(.system(size: 13))
                            .tracking(-0.15)
                            .foregroundStyle(Color.scMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            AssistantAnswerChips(actions: card.actions, reply: reply, onAsk: onAsk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Gotowe odpowiedzi jako chipy. Pierwsza wyróżniona, bo model wymienia je
/// od najbardziej prawdopodobnej — cztery równorzędne oddawałyby decyzję.
struct AssistantAnswerChips: View {
    let actions: [AgentCardActionDTO]
    /// Odpowiedź, która już padła — zaznacza wybraną opcję i gasi resztę.
    var reply: String? = nil
    let onAsk: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    private func isHighlighted(_ action: AgentCardActionDTO) -> Bool {
        guard let reply else { return action.isPrimary }
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
        AllergenChipFlow(spacing: 7) {
            ForEach(actions) { action in
                let highlighted = isHighlighted(action)
                Button {
                    onAsk(action.prompt ?? action.label)
                } label: {
                    Text(action.label)
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(highlighted ? SCPalette.terracotta : Color.scLabel(scheme))
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(
                            Capsule().fill(highlighted ? Color.scAccentTint(scheme) : Color.scTileBg(scheme))
                        )
                        .overlay(
                            Capsule().stroke(
                                highlighted ? SCPalette.terracotta.opacity(0.34) : Color.scTileStroke(scheme),
                                lineWidth: 1
                            )
                        )
                        // Po odpowiedzi niewybrane opcje schodzą w tło.
                        .opacity(answered && !highlighted ? 0.45 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(answered && highlighted ? [.isSelected] : [])
            }
        }
        .animation(.easeInOut(duration: 0.2), value: answered)
    }
}

// MARK: - Dania do wyboru

/// Kilka dań jako kafle ze zdjęciem — pytanie zadane obrazkami.
///
/// Karuzela, nie lista: wybór z trzech zdjęć trwa sekundę. Karta nie ma
/// stanu — dotknięcie wysyła wiadomość, a nie zapisuje plan.
struct AssistantOptionsCard: View {
    let card: OptionsCardDTO
    let onAsk: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                AssistantCardLabel(text: card.eyebrow, color: SCPalette.terracotta)
                Text(card.title)
                    .font(.system(size: 17, weight: .bold))
                    .tracking(-0.35)
                    .foregroundStyle(Color.scLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(card.options) { option in
                        OptionTile(option: option) { onAsk(option.prompt) }
                    }
                }
                // Karuzela sięga poza margines rozmowy: ostatni kafel ucięty
                // krawędzią ekranu to jedyny sygnał przewijania bez paska.
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()

            if !card.actions.isEmpty {
                AssistantAnswerChips(actions: card.actions, onAsk: onAsk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct OptionTile: View {
        let option: OptionsCardItemDTO
        let onTap: () -> Void

        private static let width: CGFloat = 176
        private static let coverHeight: CGFloat = 112

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 0) {
                    cover

                    VStack(alignment: .leading, spacing: 6) {
                        Text(option.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(Color.scLabel(scheme))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .frame(height: 36, alignment: .top)

                        HStack(spacing: 8) {
                            Label {
                                Text("\(option.kcalPerServing) kcal").monospacedDigit()
                            } icon: {
                                Image(systemName: "flame").foregroundStyle(SCPalette.terracotta)
                            }
                            if option.prepTimeMinutes > 0 {
                                Label {
                                    Text("\(option.prepTimeMinutes) min").monospacedDigit()
                                } icon: {
                                    Image(systemName: "clock").foregroundStyle(Color.scMuted(scheme))
                                }
                            }
                        }
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                }
                .frame(width: Self.width, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AssistantCardMetrics.radius - 4, style: .continuous)
                        .fill(Color.scCardSurface(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AssistantCardMetrics.radius - 4, style: .continuous)
                        .stroke(Color.scCardStroke(scheme), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AssistantCardMetrics.radius - 4, style: .continuous))
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

        private var cover: some View {
            ZStack(alignment: .topLeading) {
                CachedAsyncImage(url: option.imageUrl.flatMap(URL.init(string:))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        ZStack {
                            Color.scInsetSurface(scheme)
                            Image(systemName: "fork.knife")
                                .font(.system(size: 22))
                                .foregroundStyle(Color.scFaint(scheme))
                        }
                    }
                }
                .frame(width: Self.width, height: Self.coverHeight)
                .clipped()

                if let tag = option.tag, !tag.isEmpty {
                    Text(tag)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(SCPalette.terracotta)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.scCardSurface(scheme).opacity(0.92)))
                        .padding(8)
                }
            }
        }
    }
}

// MARK: - Podmiana

/// TERAZ → PROPOZYCJA, z różnicą, dla której o podmianę poproszono.
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
                    SideRow(label: "Teraz", side: from, isOutgoing: true)
                    HStack(spacing: 0) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(SCPalette.sage)
                            .frame(width: 22)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                    .accessibilityHidden(true)
                }
                SideRow(label: card.from == nil ? "Dołożone" : "Propozycja", side: card.to, isOutgoing: false)
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.top, 2)
            .padding(.bottom, card.deltas.isEmpty ? AssistantCardMetrics.section : 4)
            .overlay(alignment: .top) { AssistantCardRule() }

            if !card.deltas.isEmpty {
                deltas
            }

            AssistantProposalFooter(
                state: card.state,
                applyLabel: card.actions.first { $0.kind == .apply }?.label ?? "Zamień",
                applyIcon: "arrow.triangle.2.circlepath",
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

    private var deltas: some View {
        AllergenChipFlow(spacing: 6) {
            ForEach(card.deltas) { delta in
                HStack(spacing: 5) {
                    Text(delta.value)
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(delta.good ? SCPalette.sage : Color.scMuted(scheme))
                    Text(delta.label)
                        .font(.system(size: 11.5))
                        .foregroundStyle(delta.good ? SCPalette.sage.opacity(0.8) : Color.scFaint(scheme))
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(delta.good ? Color.scSageTint(scheme) : Color.scChipBg(scheme)))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, AssistantCardMetrics.inset)
        .padding(.top, 8)
        .padding(.bottom, AssistantCardMetrics.section)
    }

    /// Wiersz jednej strony podmiany. To, co znika, jest przekreślone
    /// i wyszarzone — inaczej obie linie wyglądają jak dwa dania do wyboru.
    private struct SideRow: View {
        let label: String
        let side: SwapCardSideDTO
        let isOutgoing: Bool

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: isOutgoing ? "xmark" : "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isOutgoing ? Color.scFaint(scheme) : SCPalette.sage)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    AssistantCardLabel(text: label, color: isOutgoing ? nil : SCPalette.sage)
                    Text(side.title)
                        .font(.system(size: 14.5, weight: isOutgoing ? .regular : .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(isOutgoing ? Color.scFaint(scheme) : Color.scLabel(scheme))
                        .strikethrough(isOutgoing, color: Color.scStrike(scheme))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(detail)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(isOutgoing ? Color.scFaint(scheme) : Color.scLabel(scheme))
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        }

        private var detail: String {
            side.prepTimeMinutes > 0
                ? "\(side.kcalPerServing) kcal · \(side.prepTimeMinutes) min"
                : "\(side.kcalPerServing) kcal"
        }
    }
}

// MARK: - Usunięcie posiłku

/// Danie, które ma zniknąć z planu.
///
/// Ton neutralny, nie czerwony: to zwykła zmiana planu, którą użytkownik sam
/// zamówił i którą cofnie jednym przyciskiem — straszenie kolorem robiłoby
/// z niej wydarzenie.
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

            row
                .padding(.horizontal, AssistantCardMetrics.inset)
                .overlay(alignment: .top) { AssistantCardRule() }

            VStack(alignment: .leading, spacing: 4) {
                AssistantCardLabel(text: "Powód propozycji")
                Text(reason)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.vertical, AssistantCardMetrics.section)
            .overlay(alignment: .top) { AssistantCardRule() }

            AssistantProposalFooter(
                state: card.state,
                applyLabel: card.actions.first { $0.kind == .apply }?.label ?? "Usuń z planu",
                applyIcon: "minus.circle",
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

    private var row: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.scFaint(scheme))
                .frame(width: 22)

            Text(card.removed.title)
                .font(.system(size: 14.5))
                .tracking(-0.2)
                .foregroundStyle(Color.scFaint(scheme))
                .strikethrough(true, color: Color.scStrike(scheme))
                .lineLimit(2)

            Spacer(minLength: 8)

            Text(detail)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Color.scFaint(scheme))
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        card.removed.prepTimeMinutes > 0
            ? "\(card.removed.kcalPerServing) kcal · \(card.removed.prepTimeMinutes) min"
            : "\(card.removed.kcalPerServing) kcal"
    }
}

// MARK: - Jedno danie, kilka talerzy

/// Podział wspólnego dania na porcje.
///
/// Plakietka ograniczenia (cel, „bez laktozy”) jest wyżej w hierarchii niż
/// inicjał w kółku: to ona mówi, DLACZEGO ta porcja jest inna.
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
            AssistantCardHead(
                eyebrow: card.eyebrow,
                eyebrowDetail: card.prepTimeMinutes > 0 ? "\(card.prepTimeMinutes) min" : nil,
                title: card.title,
                status: status
            )

            VStack(spacing: 0) {
                ForEach(Array(card.portions.enumerated()), id: \.element.id) { index, portion in
                    PortionRow(portion: portion)
                        .overlay(alignment: .top) {
                            AssistantCardRule(leadingInset: index == 0 ? 0 : AssistantCardMetrics.inset)
                        }
                }
            }

            AssistantProposalFooter(
                state: card.state,
                applyLabel: card.actions.first { $0.kind == .apply }?.label ?? "Zapisz",
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

    private struct PortionRow: View {
        let portion: HouseholdSplitPortionDTO

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    Circle().fill(Color.scChipBg(scheme))
                    Text(portion.initial)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.scMuted(scheme))
                }
                .frame(width: 28, height: 28)
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(portion.displayName)
                            .font(.system(size: 14.5, weight: .semibold))
                            .tracking(-0.25)
                            .foregroundStyle(Color.scLabel(scheme))
                        Spacer(minLength: 8)
                        if portion.kcal > 0 {
                            Text("\(portion.kcal) kcal")
                                .font(.system(size: 13, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.scLabel(scheme))
                        }
                    }

                    if !portion.goalLabel.isEmpty {
                        Text(portion.goalLabel)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(SCPalette.indigo)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Capsule().fill(Color.scIndigoTint(scheme)))
                            .lineLimit(1)
                    }

                    if let note = portion.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 13))
                            .tracking(-0.15)
                            .foregroundStyle(Color.scMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.vertical, 11)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Luka makro

/// Ile brakuje do celu — i co to domknie.
///
/// Indygo, nie terakota: to analiza, a nie propozycja do zatwierdzenia.
/// Subtelny pasek, dwa–trzy wiersze zmian, żadnego pulpitu fitness.
struct AssistantMacroGapCard: View {
    let card: MacroGapCardDTO
    let onAsk: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AssistantCard(tone: .indigo) {
            AssistantCardHead(eyebrow: card.eyebrow, eyebrowColor: SCPalette.indigo, title: card.title)

            VStack(alignment: .leading, spacing: 8) {
                AssistantTargetBar(value: card.current, target: card.target, color: SCPalette.indigo, height: 8)
                HStack {
                    Text("\(card.current) \(card.unit) z planu")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(scheme))
                    Spacer(minLength: 8)
                    Text("cel \(card.target) \(card.unit)")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                }
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.bottom, AssistantCardMetrics.section)
            .accessibilityElement(children: .combine)

            if !card.boosters.isEmpty {
                boosters
            }

            if let action = card.actions.first, let prompt = action.prompt {
                AssistantCardActions(
                    primary: AssistantCardAction(title: action.label, icon: "checkmark") { onAsk(prompt) },
                    tone: .indigo
                )
            }
        }
    }

    private var boosters: some View {
        VStack(spacing: 0) {
            AssistantCardLabel(text: "Zapytaj o zmianę")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AssistantCardMetrics.inset)
                .padding(.top, 11)
                .padding(.bottom, 4)

            ForEach(Array(card.boosters.prefix(3).enumerated()), id: \.element.id) { index, booster in
                Button { onAsk(booster.askPrompt) } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Text(booster.text)
                            .font(.system(size: 13.5))
                            .tracking(-0.2)
                            .foregroundStyle(Color.scLabel(scheme))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 8)

                        Text(booster.amountLabel(unit: card.unit))
                            .font(.system(size: 12.5, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(SCPalette.indigo)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.scFaint(scheme))
                    }
                    .padding(.horizontal, AssistantCardMetrics.inset)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlanPressStyle(scale: 0.985))
                .overlay(alignment: .top) {
                    if index > 0 { AssistantCardRule(leadingInset: AssistantCardMetrics.inset) }
                }
                .accessibilityHint("Wysyła pytanie o tę zmianę")
            }

            // Strzałka wysyła pytanie, nic nie zapisuje — żeby nikt nie szukał
            // w planie zmiany, której nie ma.
            Text("Stuknięcie wysyła pytanie — nic nie zapisuje się samo.")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.scFaint(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AssistantCardMetrics.inset)
                .padding(.top, 4)
                .padding(.bottom, 10)
        }
        .overlay(alignment: .top) { AssistantCardRule() }
    }
}

// MARK: - Lista zakupów

/// Skrót listy: najwyżej trzy działy po kilka pozycji, reszta w Liście.
struct AssistantShoppingListCard: View {
    let card: ShoppingListCardDTO
    let onOpenShopping: () -> Void

    private static let maxGroups = 3
    private static let maxRows = 4

    @Environment(\.colorScheme) private var scheme

    private var visibleGroups: [ShoppingListCardGroupDTO] {
        Array(card.groups.prefix(Self.maxGroups))
    }

    private var hiddenGroups: Int { max(0, card.groups.count - visibleGroups.count) }

    var body: some View {
        AssistantCard {
            AssistantCardHead(eyebrow: card.eyebrow, title: card.title, subtitle: card.checkedNote)

            VStack(spacing: 0) {
                ForEach(visibleGroups) { group in
                    GroupBlock(group: group, maxRows: Self.maxRows)
                        .overlay(alignment: .top) { AssistantCardRule() }
                }
            }
            .padding(.horizontal, AssistantCardMetrics.inset)

            if hiddenGroups > 0 {
                Text("+ \(hiddenGroups) \(Self.departmentsWord(hiddenGroups)) w Liście zakupów")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.scFaint(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
            }

            AssistantCardActions(
                primary: AssistantCardAction(title: "Otwórz listę", icon: "cart", action: onOpenShopping),
                style: .navigation
            )
        }
    }

    static func departmentsWord(_ count: Int) -> String {
        if count == 1 { return "dział" }
        let mod100 = count % 100
        if (12...14).contains(mod100) { return "działów" }
        return (2...4).contains(count % 10) ? "działy" : "działów"
    }

    private struct GroupBlock: View {
        let group: ShoppingListCardGroupDTO
        let maxRows: Int

        @Environment(\.colorScheme) private var scheme

        private var rows: [ShoppingListCardEntryDTO] { Array(group.rows.prefix(maxRows)) }
        private var hidden: Int { max(0, group.rows.count - rows.count) + (group.hidden ?? 0) }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    AssistantCardLabel(text: group.department, color: Color.scMuted(scheme))
                    Text("\(group.remainingCount)/\(group.rows.count)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Color.scFaint(scheme))
                    Spacer(minLength: 0)
                }

                ForEach(rows) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: entry.isChecked ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(entry.isChecked ? SCPalette.sage : Color.scFaint(scheme))
                        Text(entry.label)
                            .font(.system(size: 13.5))
                            .tracking(-0.15)
                            .foregroundStyle(entry.isChecked ? Color.scFaint(scheme) : Color.scLabel(scheme))
                            .strikethrough(entry.isChecked, color: Color.scStrike(scheme))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(entry.isChecked ? "\(entry.label), kupione" : entry.label)
                }

                if hidden > 0 {
                    Text("+ \(hidden) więcej")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.scFaint(scheme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Potwierdzenie zapisu

/// „Zapisane” z „Cofnij” — W KARCIE, nie w toaście.
///
/// Toast znika po trzech sekundach i zabiera ze sobą jedyną drogę odwrotu.
struct AssistantAppliedCard: View {
    let card: AppliedCardDTO
    let isBusy: Bool
    let onUndo: () -> Void
    let onOpenPlan: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var status: AssistantCardStatus { AssistantCardStatus(card.state) }
    private var undoAction: AgentCardActionDTO? { card.actions.first { $0.kind == .undo } }
    private var openPlanLabel: String { card.actions.first { $0.kind == .openPlan }?.label ?? "Otwórz plan" }

    var body: some View {
        AssistantCard(tone: status.tone) {
            AssistantCardHead(
                eyebrow: "Zapisane",
                eyebrowColor: SCPalette.sage,
                title: card.title,
                subtitle: card.subtitle,
                status: status
            )

            summary

            ForEach(card.notes, id: \.self) { note in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.scFaint(scheme))
                        .padding(.top, 1)
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, AssistantCardMetrics.inset)
                .padding(.bottom, 10)
            }

            AssistantStateNote(status: status, until: card.state.until)

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
                    tone: .sage,
                    style: .navigation
                )
            }
        }
    }

    /// Ile zmian — tylko te liczby, które są większe od zera.
    @ViewBuilder
    private var summary: some View {
        let rows: [(String, Int)] = [
            ("Nowe pozycje", card.summary.created),
            ("Zmienione", card.summary.updated),
            ("Usunięte", card.summary.removed),
        ].filter { $0.1 > 0 }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    AssistantCardSummaryRow(label: row.0, value: "\(row.1)")
                }
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.vertical, 10)
            .overlay(alignment: .top) { AssistantCardRule() }
            .accessibilityElement(children: .combine)
        }
    }
}
