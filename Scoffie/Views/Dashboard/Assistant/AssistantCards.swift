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
    /// Dotknięcie dania otwiera je w arkuszu przeglądu propozycji.
    var onOpen: ((PlanWeekCardSlotDTO) -> Void)? = nil

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

            VStack(alignment: .leading, spacing: 18) {
                ForEach(day.slots) { slot in
                    ProposalMealButton(slot: slot, muted: muted, onOpen: onOpen)
                }
            }
        }
        .padding(.horizontal, AssistantCardMetrics.inset)
        .padding(.top, 18)
        .padding(.bottom, 20)
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
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(.vertical, 14)
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
            .frame(minHeight: 44)
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
    /// Zamiana jednego dania z arkusza przeglądu — zwykła wiadomość.
    var onAsk: ((String) -> Void)? = nil
    var onCompose: () -> Void = {}
    /// Id wiadomości, która właśnie przyszła; `nil` dla historii — patrz
    /// `ProposalAutoPresent`.
    var autoPresentID: String? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.recipeCatalogStore) private var recipeCatalog
    @State private var selectedDayId: String?
    @State private var presented: OptionsSheetPage?

    /// Wszystkie dania tygodnia po kolei — strony arkusza przeglądu.
    private var storyEntries: [(day: PlanWeekCardDayDTO, slot: PlanWeekCardSlotDTO)] {
        card.days.flatMap { day in day.slots.map { (day: day, slot: $0) } }
    }

    private func open(_ slot: PlanWeekCardSlotDTO, in day: PlanWeekCardDayDTO) {
        let index = storyEntries.firstIndex { $0.day.id == day.id && $0.slot.id == slot.id } ?? 0
        presented = OptionsSheetPage(id: index)
    }

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
                DayBlock(day: day, muted: muted) { open($0, in: day) }
            }

            if isExpanded {
                ForEach(otherDays) { day in
                    DayBlock(day: day, muted: muted) { open($0, in: day) }
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

            if !storyEntries.isEmpty {
                OptionsBrowseRow(title: "Przeglądaj dania", subtitle: browseSubtitle) {
                    presented = OptionsSheetPage(id: 0)
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
        .sheet(item: $presented) { page in
            AssistantOptionsStorySheet(
                slotDetail: card.eyebrowDetail,
                options: storyEntries.map { ProposalStory.item($0.slot, day: $0.day) },
                initialPage: page.id,
                mode: ProposalStory.mode(state: card.state, applyLabel: applyLabel, canSwap: onAsk != nil),
                catalog: recipeCatalog,
                onChoose: { option in
                    presented = nil
                    onAsk?(option.prompt)
                },
                onCompose: {
                    presented = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onCompose() }
                },
                // Arkusz zostaje otwarty: strona końcowa przechodzi
                // w „Zapisuję…”, a potem w „Jest w planie”.
                onApply: { onApply(false) },
                contexts: storyEntries.map { ProposalStory.context($0.slot, date: $0.day.date) },
                isBusy: isBusy,
                onOpenPlan: onOpenPlan == nil ? nil : {
                    presented = nil
                    onOpenPlan?()
                },
                onRegenerate: onAsk == nil ? nil : {
                    presented = nil
                    onAsk?("Zaproponuj inny plan tego tygodnia — z innymi daniami.")
                }
            )
        }
        .task(id: autoPresentID) {
            guard await ProposalAutoPresent.shouldOpen(autoPresentID, state: card.state, isEmpty: storyEntries.isEmpty) else { return }
            presented = OptionsSheetPage(id: 0)
        }
    }

    private var browseSubtitle: String {
        card.state.isPending ? "Zdjęcia, opis i zamiana jednego dania" : "Zdjęcia, opis i wartości odżywcze"
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
    /// Zamiana jednego dania z arkusza przeglądu — zwykła wiadomość.
    var onAsk: ((String) -> Void)? = nil
    var onCompose: () -> Void = {}
    /// Id wiadomości, która właśnie przyszła; `nil` dla historii — patrz
    /// `ProposalAutoPresent`.
    var autoPresentID: String? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.recipeCatalogStore) private var recipeCatalog
    @State private var presented: OptionsSheetPage?

    private var status: AssistantCardStatus { AssistantCardStatus(card.state) }
    private var muted: Bool { status.tone == .muted }

    private var applyLabel: String {
        card.actions.first { $0.kind == .apply }?.label ?? "Zapisz dzień"
    }

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

            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(card.slots.enumerated()), id: \.element.id) { index, slot in
                    ProposalMealButton(slot: slot, muted: muted) { _ in
                        presented = OptionsSheetPage(id: index)
                    }
                }
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.top, 16)
            .padding(.bottom, 18)

            if !card.slots.isEmpty {
                OptionsBrowseRow(
                    title: "Przeglądaj dania",
                    subtitle: card.state.isPending ? "Zdjęcia, opis i zamiana jednego dania" : "Zdjęcia, opis i wartości odżywcze"
                ) {
                    presented = OptionsSheetPage(id: 0)
                }
            }

            if !card.removed.isEmpty {
                RemovalsSection(removals: card.removed, showsDay: false)
            }

            AssistantCardSummary(items: summaryItems)

            AssistantProposalFooter(
                state: card.state,
                applyLabel: applyLabel,
                reviseLabel: "Inny zestaw",
                isBusy: isBusy,
                onApply: onApply,
                onRevise: onRevise,
                onAskNew: onAskNew,
                onUndo: onUndo,
                onOpenPlan: onOpenPlan
            )
        }
        .sheet(item: $presented) { page in
            AssistantOptionsStorySheet(
                slotDetail: card.eyebrowDetail,
                options: card.slots.map { ProposalStory.item($0, day: nil) },
                initialPage: page.id,
                mode: ProposalStory.mode(state: card.state, applyLabel: applyLabel, canSwap: onAsk != nil),
                catalog: recipeCatalog,
                onChoose: { option in
                    presented = nil
                    onAsk?(option.prompt)
                },
                onCompose: {
                    presented = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onCompose() }
                },
                // Arkusz zostaje otwarty: strona końcowa przechodzi
                // w „Zapisuję…”, a potem w „Jest w planie”.
                onApply: { onApply(false) },
                contexts: card.slots.map { ProposalStory.context($0, date: card.date) },
                isBusy: isBusy,
                onOpenPlan: onOpenPlan == nil ? nil : {
                    presented = nil
                    onOpenPlan?()
                },
                onRegenerate: onAsk == nil ? nil : {
                    presented = nil
                    onAsk?(card.slots.count == 1
                        ? "Zaproponuj inne danie zamiast tego."
                        : "Zaproponuj inny zestaw dań na ten dzień.")
                }
            )
        }
        .task(id: autoPresentID) {
            guard await ProposalAutoPresent.shouldOpen(autoPresentID, state: card.state, isEmpty: card.slots.isEmpty) else { return }
            presented = OptionsSheetPage(id: 0)
        }
    }
}

/// Świeża propozycja dnia albo tygodnia otwiera przegląd dań SAMA
/// (24.09.2026, Rafał: „sheet z podglądem powinien się z defaultu otwierać
/// zawsze”) — jak karta dań do wyboru. Jedno danie = arkusz z jedną stroną
/// i od razu „Wszystko pasuje?” obok, kilka = strony po kolei od pierwszego.
/// RAZ na wiadomość (leniwa lista odtwarza stan wiersza przy każdym powrocie
/// na ekran), nigdy dla historii i nigdy dla propozycji, której nie da się
/// już zapisać ani zmienić (zapisana, cofnięta, nieaktualna, wygasła) —
/// tam arkusz otwiera tylko dotknięcie.
@MainActor
private enum ProposalAutoPresent {
    private static var opened = Set<String>()

    static func shouldOpen(_ id: String?, state: AgentCardStateDTO, isEmpty: Bool) async -> Bool {
        guard let id, !isEmpty, state.isPending, !opened.contains(id) else { return false }
        opened.insert(id)
        // Najpierw karta wjeżdża pod tekstem, potem arkusz — nie oba naraz.
        try? await Task.sleep(for: .milliseconds(450))
        return !Task.isCancelled
    }
}

// MARK: - Przegląd dań propozycji

/// Danie propozycji jako przycisk: dotknięcie otwiera je w arkuszu wyboru
/// posiłku — tym samym, w którym wybiera się kolację z kilku (zdjęcie,
/// opis, makro), tylko w trybie przeglądu.
private struct ProposalMealButton: View {
    let slot: PlanWeekCardSlotDTO
    var muted: Bool = false
    var onOpen: ((PlanWeekCardSlotDTO) -> Void)?

    var body: some View {
        let row = AssistantMealRow(
            slot: slot.mealLabel,
            title: slot.title,
            imageUrl: slot.imageUrl,
            kcal: slot.kcalPerServing,
            muted: muted || !slot.isNew
        )
        if let onOpen {
            Button { onOpen(slot) } label: {
                row.contentShape(Rectangle())
            }
            .buttonStyle(PlanPressStyle(scale: 0.985))
            .accessibilityHint("Otwiera zdjęcie, opis i wartości odżywcze")
        } else {
            row
        }
    }
}

/// Dania propozycji dnia albo tygodnia jako strony arkusza wyboru posiłku.
private enum ProposalStory {
    /// Tag przy nazwie mówi porę (i dzień w tygodniu), a zdanie pod
    /// przyciskiem „Zamień to danie” prosi o dania DO WYBORU — serwer
    /// odpowiada kartą OPTIONS, więc zamiana też dzieje się w arkuszu.
    static func item(_ slot: PlanWeekCardSlotDTO, day: PlanWeekCardDayDTO?) -> OptionsCardItemDTO {
        let when = day.map { "\(slot.mealLabel.lowercased()), \($0.dayLabel.lowercased())" } ?? slot.mealLabel.lowercased()
        return OptionsCardItemDTO(
            recipeId: slot.recipeId,
            title: slot.title,
            kcalPerServing: slot.kcalPerServing,
            prepTimeMinutes: slot.prepTimeMinutes,
            imageUrl: slot.imageUrl,
            description: nil,
            proteinGrams: nil,
            carbsGrams: nil,
            fatGrams: nil,
            ingredientCount: nil,
            tag: day.map { "\(slot.mealLabel) · \($0.shortName)" } ?? slot.mealLabel,
            prompt: "Zamień w tej propozycji \(when): \(slot.title). Pokaż 3 inne dania na tę porę do wyboru."
        )
    }

    /// Zamiana tylko, dopóki propozycja czeka; zapis — dopóki serwer mówi,
    /// że się da (także po cofnięciu). Stan jedzie razem z trybem, więc
    /// otwarty arkusz przechodzi w „Zapisane” w chwili, gdy zapis się uda.
    static func mode(state: AgentCardStateDTO, applyLabel: String, canSwap: Bool) -> OptionsStoryMode {
        let status = AssistantCardStatus(state)
        return .review(
            swapTitle: state.isPending && canSwap ? "Zamień to danie" : nil,
            applyTitle: state.canApply && status != .applied ? applyLabel : nil,
            status: status
        )
    }

    /// Kiedy i na jaką porę — nad nazwą dania w arkuszu przeglądu.
    static func context(_ slot: PlanWeekCardSlotDTO, date: String) -> ProposalStoryContext {
        ProposalStoryContext(
            slot: MealSlot(backendMealType: slot.mealType),
            mealLabel: slot.mealLabel,
            day: ProposalStoryContext.dayLabel(date)
        )
    }
}

/// Pora i dzień jednego dania propozycji: „Śniadanie” + „Dziś, 23 września”.
/// Wcześniej arkusz mówił to małym drukiem w eyebrow („PROPOZYCJA ·
/// WTOREK, 1 WRZEŚNIA”) — nie było widać, że to dzisiejsze śniadanie.
struct ProposalStoryContext: Equatable {
    let slot: MealSlot?
    let mealLabel: String
    /// „Dziś, 23 września”, „Jutro, 24 września”, „Piątek, 26 września”;
    /// `nil`, gdy daty nie dało się odczytać.
    let day: String?

    private static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMMM"
        return formatter
    }()

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    /// Dzień względem DZISIAJ na telefonie — serwer stoi w UTC i „dziś”
    /// wie tylko telefon.
    static func dayLabel(_ iso: String, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let date = isoDay.date(from: String(iso.prefix(10))) else { return nil }
        let lead: String
        if calendar.isDate(date, inSameDayAs: now) {
            lead = "Dziś"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            lead = "Jutro"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            lead = "Wczoraj"
        } else {
            let name = weekday.string(from: date)
            lead = name.prefix(1).uppercased() + name.dropFirst()
        }
        return "\(lead), \(dayMonth.string(from: date))"
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

/// Starszy wariant karuzelowy zostaje lokalnie jako punkt odniesienia podczas
/// iteracji, ale karta używana w rozmowie jest poniżej wariantem kotwicy + arkusza.
private struct AssistantOptionsCarouselCard: View {
    let card: OptionsCardDTO
    let onAsk: (String) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeIndex = 0
    @State private var dragOffset: CGFloat = 0

    private let slideGap: CGFloat = 10

    var body: some View {
        AssistantCard {
            AssistantCardHead(eyebrow: card.eyebrow, title: card.title, subtitle: "Wybierz jedno.")

            if let activeOption {
                carousel
                    .padding(.top, 14)

                optionSummary(activeOption)
                    .padding(.horizontal, AssistantCardMetrics.inset)
                    .padding(.top, 12)

                carouselControls
                    .padding(.horizontal, AssistantCardMetrics.inset)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
            } else {
                Text("Nie mam teraz dań do pokazania.")
                    .font(.system(size: 14))
                    .foregroundStyle(AssistantLook.muted(scheme))
                    .padding(.horizontal, AssistantCardMetrics.inset)
                    .padding(.vertical, 18)
            }

            if let other = card.actions.first {
                AssistantCardActions(
                    secondary: AssistantCardAction(title: other.label, icon: "arrow.triangle.2.circlepath") {
                        onAsk(other.prompt ?? other.label)
                    }
                )
            }
        }
        .onChange(of: card.options) { _, options in
            activeIndex = min(activeIndex, max(options.count - 1, 0))
            dragOffset = 0
        }
    }

    private var activeOption: OptionsCardItemDTO? {
        guard card.options.indices.contains(activeIndex) else { return nil }
        return card.options[activeIndex]
    }

    private var carousel: some View {
        GeometryReader { proxy in
            let pageWidth = max(230, proxy.size.width - 54)
            let step = pageWidth + slideGap

            HStack(spacing: slideGap) {
                ForEach(Array(card.options.enumerated()), id: \.element.id) { index, option in
                    OptionSlide(
                        option: option,
                        isActive: index == activeIndex,
                        width: pageWidth
                    ) {
                        choose(option, at: index)
                    }
                }
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .offset(x: -CGFloat(activeIndex) * step + dragOffset)
            .animation(reduceMotion ? nil : .snappy(duration: 0.34), value: activeIndex)
            .contentShape(Rectangle())
            .gesture(swipeGesture(pageWidth: pageWidth))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Propozycje posiłków")
            .accessibilityValue("\(activeIndex + 1) z \(card.options.count)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: move(by: 1)
                case .decrement: move(by: -1)
                @unknown default: break
                }
            }
        }
        .frame(height: 260)
        .clipped()
    }

    private var carouselControls: some View {
        HStack(spacing: 10) {
            carouselButton(systemName: "chevron.left", label: "Poprzednia propozycja", enabled: activeIndex > 0) {
                move(by: -1)
            }

            HStack(spacing: 6) {
                ForEach(card.options.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == activeIndex ? AssistantLook.terraFill(scheme) : AssistantLook.hair(scheme))
                        .frame(width: index == activeIndex ? 18 : 6, height: 5)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: activeIndex)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)

            carouselButton(systemName: "chevron.right", label: "Następna propozycja", enabled: activeIndex < card.options.count - 1) {
                move(by: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Nawigacja propozycji")
    }

    private func carouselButton(
        systemName: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? AssistantLook.terra(scheme) : AssistantLook.faint(scheme))
                .frame(width: 30, height: 30)
                .background(Circle().fill(AssistantLook.wash(scheme)))
                .overlay(Circle().stroke(AssistantLook.hair(scheme), lineWidth: 1))
                .scTapTarget(44, drawn: 30)
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func optionSummary(_ option: OptionsCardItemDTO) -> some View {
        HStack(spacing: 0) {
            summaryMetric {
                SCRollingNumber(value: option.kcalPerServing)
                    .font(.system(size: 17, weight: .bold))
            } label: {
                Text("kcal / porcja")
            }

            Rectangle()
                .fill(AssistantLook.hair(scheme))
                .frame(width: 1, height: 27)

            summaryMetric {
                SCRollingNumber(value: option.prepTimeMinutes, unit: "min")
                    .font(.system(size: 17, weight: .bold))
            } label: {
                Text("przygotowanie")
            }
        }
        .foregroundStyle(AssistantLook.ink(scheme))
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AssistantLook.wash(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AssistantLook.hair(scheme), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(option.kcalPerServing) kilokalorii na porcję, \(option.prepTimeMinutes) minut przygotowania")
    }

    private func summaryMetric<Value: View, Label: View>(
        @ViewBuilder value: () -> Value,
        @ViewBuilder label: () -> Label
    ) -> some View {
        VStack(spacing: 2) {
            value()
                .monospacedDigit()
            label()
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AssistantLook.faint(scheme))
        }
        .frame(maxWidth: .infinity)
    }

    private func swipeGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !reduceMotion else { return }
                // Opór na krawędziach daje sygnał, że to już pierwszy/ostatni
                // slajd, bez przesuwania karty poza bezpieczny obszar.
                let atEdge = (activeIndex == 0 && value.translation.width > 0)
                    || (activeIndex == card.options.count - 1 && value.translation.width < 0)
                dragOffset = atEdge ? value.translation.width * 0.22 : value.translation.width
            }
            .onEnded { value in
                let threshold = max(36, pageWidth * 0.18)
                let direction = value.translation.width < -threshold ? 1 : value.translation.width > threshold ? -1 : 0
                move(by: direction)
            }
    }

    private func move(by delta: Int) {
        guard !card.options.isEmpty else { return }
        let next = min(max(activeIndex + delta, 0), card.options.count - 1)
        let animation: Animation? = reduceMotion ? nil : .snappy(duration: 0.34)
        withAnimation(animation) {
            activeIndex = next
            dragOffset = 0
        }
    }

    private func choose(_ option: OptionsCardItemDTO, at index: Int) {
        let animation: Animation? = reduceMotion ? nil : .smooth(duration: 0.2)
        withAnimation(animation) {
            activeIndex = index
            dragOffset = 0
        }
        onAsk(option.prompt)
    }

    private struct OptionSlide: View {
        let option: OptionsCardItemDTO
        let isActive: Bool
        let width: CGFloat
        let onTap: () -> Void

        @Environment(\.colorScheme) private var scheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        // Zdjęcie dostaje ramkę o znanej wielkości, więc
                        // obraz nie zgłasza własnej szerokości do karuzeli.
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 156)
                            .overlay {
                                CachedAsyncImage(url: option.imageUrl.flatMap(URL.init(string:))) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    default:
                                        ZStack {
                                            AssistantLook.wash(scheme)
                                            Image(systemName: "fork.knife")
                                                .font(.system(size: 24))
                                                .foregroundStyle(AssistantLook.faint(scheme))
                                        }
                                    }
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Color.black.opacity(0.12), radius: 1, y: 1)

                        if let tag = option.tag, !tag.isEmpty {
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

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(option.title)
                            .font(.system(size: 15.5, weight: .semibold))
                            .tracking(-0.3)
                            .lineSpacing(1)
                            .foregroundStyle(AssistantLook.ink(scheme))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AssistantLook.terra(scheme))
                            .accessibilityHidden(true)
                    }
                    .padding(.top, 10)

                    HStack(spacing: 6) {
                        if option.prepTimeMinutes > 0 {
                            Text("\(option.prepTimeMinutes) min")
                        }
                        Text("·")
                        Text("\(option.kcalPerServing) kcal")
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(AssistantLook.faint(scheme))
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .padding(10)
            .frame(width: width, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AssistantCardMetrics.innerRadius, style: .continuous)
                    .fill(AssistantLook.field(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AssistantCardMetrics.innerRadius, style: .continuous)
                    .stroke(
                        isActive ? AssistantLook.terra(scheme).opacity(0.42) : AssistantLook.cardStroke(scheme),
                        lineWidth: isActive ? 1.4 : 1
                    )
            )
            .scaleEffect(isActive ? 1 : 0.975)
            .opacity(isActive ? 1 : 0.68)
            .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: isActive)
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

/// Karta rozmowy wg makiety „Asystent — Wybór posiłku” (`OptAnchorCard`):
/// kompaktowa kotwica zostaje w historii, a zdjęcia, opis i makro otwierają
/// się w arkuszu nad rozmową. Świeża odpowiedź otwiera arkusz sama; dotknięcie
/// kotwicy otwiera go ponownie — dziś i za tydzień.
struct AssistantOptionsCard: View {
    let card: OptionsCardDTO
    /// Następna wiadomość użytkownika — kotwica zaznacza nią wybrane danie.
    var reply: String? = nil
    /// Id wiadomości, która właśnie przyszła; `nil` dla historii.
    var autoPresentID: String? = nil
    /// Strona, na której arkusz otwiera się sam — w rozmowie zawsze pierwsza.
    var autoPresentPage: Int = 0
    let onAsk: (String) -> Void
    /// „Napisz, na co masz ochotę” — fokus na polu rozmowy.
    var onCompose: () -> Void = {}

    @Environment(\.colorScheme) private var scheme
    @Environment(\.recipeCatalogStore) private var recipeCatalog
    @State private var presented: OptionsSheetPage?

    /// Arkusz otwiera się sam RAZ na wiadomość — nie przy każdym powrocie
    /// wiersza na ekran (leniwa lista odtwarza stan widoku).
    @MainActor private static var autoPresented = Set<String>()

    private var slotDetail: String? { OptionsCopy.slotDetail(card.eyebrow) }

    private var morePrompt: String? {
        card.actions.first(where: { $0.prompt != nil })?.prompt
    }

    private var chosenID: String? {
        guard let reply else { return nil }
        return card.options.first { OptionsCopy.matches($0.prompt, reply: reply) }?.id
    }

    var body: some View {
        AssistantCard {
            AssistantCardHead(
                eyebrow: "Do wyboru",
                eyebrowDetail: slotDetail,
                title: card.title,
                subtitle: OptionsCopy.subtitle(for: card.options)
            )

            if card.options.isEmpty {
                Text("Nie mam teraz dań do pokazania.")
                    .font(.system(size: 14))
                    .foregroundStyle(AssistantLook.muted(scheme))
                    .padding(.horizontal, AssistantCardMetrics.inset)
                    .padding(.vertical, 18)
            } else {
                // `padding: 12px 18px 14px; gap: 12` — bez kresek między daniami.
                VStack(spacing: 12) {
                    ForEach(Array(card.options.enumerated()), id: \.element.id) { index, option in
                        anchorRow(option, at: index)
                    }
                }
                .padding(.horizontal, AssistantCardMetrics.inset)
                .padding(.top, 12)
                .padding(.bottom, 14)

                OptionsBrowseRow(title: "Przeglądaj propozycje", subtitle: "Zdjęcia, opis i wartości odżywcze") {
                    presented = OptionsSheetPage(id: 0)
                }
            }
        }
        .sheet(item: $presented) { page in
            AssistantOptionsStorySheet(
                slotDetail: slotDetail,
                options: card.options,
                initialPage: page.id,
                mode: .choose(insertTitle: OptionsCopy.insertTitle(card.eyebrow), morePrompt: morePrompt),
                // Jawnie, nie przez środowisko: arkusz ma czytać TEN katalog,
                // który ma ekran, a nie pusty domyślny.
                catalog: recipeCatalog,
                onChoose: { option in
                    presented = nil
                    onAsk(option.prompt)
                },
                onMore: { prompt in
                    presented = nil
                    onAsk(prompt)
                },
                onCompose: {
                    presented = nil
                    // Fokus dopiero po zjeździe arkusza — w trakcie przejścia
                    // klawiatura nie ma gdzie się pokazać.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onCompose() }
                }
            )
        }
        .task(id: autoPresentID) { await autoPresentIfFresh() }
    }

    /// `LMealRow` 40 px. Po wyborze: znacznik szałwii przy wybranym, reszta
    /// wyciszona — tak jak karta pytania zaznacza udzieloną odpowiedź.
    private func anchorRow(_ option: OptionsCardItemDTO, at index: Int) -> some View {
        let chosen = chosenID == option.id
        let dimmed = chosenID != nil && !chosen
        return Button {
            presented = OptionsSheetPage(id: index)
        } label: {
            HStack(spacing: 8) {
                AssistantMealRow(
                    slot: nil,
                    title: option.title,
                    imageUrl: option.imageUrl,
                    kcal: option.kcalPerServing,
                    size: 40,
                    muted: dimmed,
                    titleWeight: chosen ? .semibold : .medium
                )
                if chosen {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AssistantLook.sage(scheme))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .accessibilityHint("Otwiera zdjęcie, opis i wartości odżywcze")
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }

    private func autoPresentIfFresh() async {
        guard let id = autoPresentID, reply == nil, !card.options.isEmpty,
              !Self.autoPresented.contains(id) else { return }
        Self.autoPresented.insert(id)
        // Najpierw karta wjeżdża pod tekstem, potem arkusz — nie oba naraz.
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        presented = OptionsSheetPage(id: autoPresentPage)
    }
}

/// Strona arkusza do otwarcia: indeks dania albo `options.count` = „Coś innego”.
private struct OptionsSheetPage: Identifiable {
    let id: Int
}

/// Co arkusz robi z daniem.
private enum OptionsStoryMode {
    /// Wybór jednego z kilku dań (karta OPTIONS): „Wstaw na środę”,
    /// na końcu „Pokaż 3 kolejne”.
    case choose(insertTitle: String, morePrompt: String?)
    /// Przegląd dań propozycji dnia albo tygodnia: „Zamień to danie”,
    /// na końcu „Zapisz w planie”. `nil` = tej akcji nie ma. `status` =
    /// stan propozycji z serwera — mówi, co pokazuje strona końcowa.
    case review(swapTitle: String?, applyTitle: String?, status: AssistantCardStatus)
}

/// `LRow` na tle `wash`: kafelek 36 ze znakiem, tytuł w terakocie, chevron —
/// wejście do arkusza wyboru posiłku z karty dań do wyboru i z propozycji.
private struct OptionsBrowseRow: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(AssistantLook.terraTint(scheme))
                    OptionsKesMark(size: 17, color: AssistantLook.terraFill(scheme))
                }
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(AssistantLook.terra(scheme))
                        .lineHeight(.exact(points: 20))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(AssistantLook.muted(scheme))
                        .lineHeight(.exact(points: 17))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AssistantLook.ink(scheme).opacity(0.35))
            }
            .padding(.leading, 16)
            .padding(.trailing, AssistantCardMetrics.inset)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AssistantLook.wash(scheme))
            .overlay(alignment: .top) { AssistantCardRule() }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .accessibilityElement(children: .combine)
    }
}

/// Teksty karty i arkusza — liczone z danych karty, nie z pamięci modelu.
private enum OptionsCopy {
    /// „Kolacja · wtorek” → „Kolacja, wtorek”; sam „Do wyboru” nic nie dodaje.
    static func slotDetail(_ eyebrow: String) -> String? {
        let trimmed = eyebrow.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare("Do wyboru") != .orderedSame else { return nil }
        let parts = trimmed
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Rdzeń słowa → biernik po „na”. Rdzeń, bo model pisze raz „środa”,
    /// raz „środę”, raz „śr.”.
    private static let days: [(stem: String, target: String)] = [
        ("pon", "poniedziałek"), ("wt", "wtorek"), ("śr", "środę"), ("czw", "czwartek"),
        ("pt", "piątek"), ("piąt", "piątek"), ("sob", "sobotę"), ("nd", "niedzielę"),
        ("niedz", "niedzielę"), ("dziś", "dziś"), ("dzisiaj", "dziś"), ("jutr", "jutro"),
    ]

    /// „Wstaw na środę”, gdy z nagłówka da się wyczytać dzień; inaczej
    /// „Wstaw do planu”.
    static func insertTitle(_ eyebrow: String) -> String {
        let words = eyebrow.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        for word in words {
            if let day = days.first(where: { word.hasPrefix($0.stem) }) {
                return "Wstaw na \(day.target)"
            }
        }
        return "Wstaw do planu"
    }

    static func subtitle(for options: [OptionsCardItemDTO]) -> String {
        let count = options.count
        guard count > 1 else { return "Wybierz jedno." }
        let (lead, all): (String, String)
        switch count {
        case 2: (lead, all) = ("Dwa z Twoich przepisów", "oba")
        case 3: (lead, all) = ("Trzy z Twoich przepisów", "wszystkie")
        case 4: (lead, all) = ("Cztery z Twoich przepisów", "wszystkie")
        default: (lead, all) = ("\(count) z Twoich przepisów", "wszystkie")
        }
        let maxMinutes = options.map(\.prepTimeMinutes).max() ?? 0
        guard maxMinutes > 0 else { return "\(lead). Wybierz jedno." }
        return "\(lead), \(all) do \(maxMinutes) minut."
    }

    /// Samo słowo do liczby składników: 1 składnik, 2–4 składniki, 5+ składników.
    static func ingredientsWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if count == 1 { return "składnik" }
        if (2...4).contains(mod10), !(12...14).contains(mod100) { return "składniki" }
        return "składników"
    }

    /// „Pokaż 3 kolejne” — liczba po polsku: 2–4 „kolejne”, 5+ „kolejnych”.
    static func moreTitle(_ count: Int) -> String {
        (2...4).contains(count) ? "Pokaż \(count) kolejne" : "Pokaż \(count) kolejnych"
    }

    static func matches(_ prompt: String, reply: String) -> Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(reply.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}

/// To, co arkusz pokazuje o daniu poza nazwą, kcal i czasem.
///
/// Najpierw dane z karty (serwer policzył je z bazy w chwili propozycji).
/// Karty zapisane w historii PRZED tymi polami ich nie mają — wtedy bierzemy
/// przepis z katalogu aplikacji: ten sam rekord, te same liczby, tylko
/// policzone tutaj (makro całego przepisu ÷ porcje, jak na serwerze).
private struct OptionsDishFacts: Equatable {
    var description: String?
    var protein: Int?
    var carbs: Int?
    var fat: Int?
    var ingredientCount: Int?

    init(option: OptionsCardItemDTO, recipe: Recipe?) {
        let servings = Double(max(1, recipe?.servings ?? 1))
        func perServing(_ value: Double?) -> Int? {
            guard let value, value.isFinite, value > 0 else { return nil }
            return Int((value / servings).rounded())
        }
        func text(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        description = text(option.description) ?? text(recipe?.description)

        // Makro zawsze z JEDNEGO źródła — białko z karty i węgle z katalogu
        // dałyby pasek, który nie sumuje się do żadnego przepisu.
        if let protein = option.proteinGrams, let carbs = option.carbsGrams, let fat = option.fatGrams {
            (self.protein, self.carbs, self.fat) = (protein, carbs, fat)
        } else if let nutrition = recipe?.nutrition {
            protein = perServing(nutrition.protein)
            carbs = perServing(nutrition.carbs)
            fat = perServing(nutrition.fat)
        }

        if let count = option.ingredientCount, count > 0 {
            ingredientCount = count
        } else if let count = recipe?.ingredients.count, count > 0 {
            ingredientCount = count
        }
    }

    var macros: (protein: Int, carbs: Int, fat: Int)? {
        guard let protein, let carbs, let fat, protein + carbs + fat > 0 else { return nil }
        return (protein, carbs, fat)
    }
}

/// Arkusz-story (największy detent) z makiety `OptStorySheet`: zdjęcie
/// wypełnia górę, pod nim eyebrow z tagiem, nazwa, opis, kcal · min z paskiem
/// makro i jedna decyzja. Segmenty u góry: dania + kreskowany = „Coś innego”.
/// Przesunięcie w bok zmienia stronę; uchwyt, X i gest w dół zamykają.
///
/// JEDEN trwały układ na wszystkie dania, a nie strona podmieniana w całości:
/// każdy element ma stały slot o wysokości największego z dań, więc zdjęcie,
/// nazwa, liczby i przycisk stoją w tym samym miejscu na każdej stronie.
/// Zmiana dania to przenikanie w miejscu — zdjęcia przez siebie, nazwa i opis
/// z lekkim przesunięciem w stronę gestu, cyfry rolują się, a pasek makro
/// przechodzi z proporcji jednego dania w proporcje drugiego.
private struct AssistantOptionsStorySheet: View {
    let slotDetail: String?
    let options: [OptionsCardItemDTO]
    let mode: OptionsStoryMode
    let catalog: RecipeCatalogStore
    let onChoose: (OptionsCardItemDTO) -> Void
    let onMore: (String) -> Void
    let onCompose: () -> Void
    /// „Zapisz w planie” ze strony końcowej przeglądu propozycji.
    var onApply: (() -> Void)? = nil
    /// Pora i dzień każdego dania — tylko w przeglądzie propozycji.
    var contexts: [ProposalStoryContext] = []
    /// Zapis w toku — arkusz zostaje otwarty i sam przechodzi w „Zapisane”.
    var isBusy: Bool = false
    /// „Otwórz plan” po zapisie.
    var onOpenPlan: (() -> Void)? = nil
    /// „Zaproponuj inne dania” pod listą strony końcowej przeglądu — nowy
    /// zestaw zamiast tego; `nil` = odnośnika nie ma.
    var onRegenerate: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var segmentSpace

    @State private var page: Int
    /// Danie pokazywane w warstwie dań. Na stronie końcowej zostaje ostatnie
    /// oglądane — warstwa gaśnie z treścią, a nie z zerami.
    @State private var dish: Int
    /// Danie sprzed zmiany: zostaje nieprzezroczyste POD nowym zdjęciem, żeby
    /// w połowie przenikania nie prześwitywało tło arkusza.
    @State private var previousDish: Int
    /// Wejście arkusza: treść wjeżdża kaskadą, liczby liczą od zera, pasek
    /// makro wypełnia się od lewej.
    @State private var appeared = false
    /// Zmierzona wysokość stosu „nazwa + opis” każdego dania — eyebrow stoi
    /// tuż nad stosem BIEŻĄCEGO dania.
    @State private var textHeights: [Int: CGFloat] = [:]
    /// Palec na ekranie — treść ugina się za nim, zanim strona się zmieni.
    /// Zwykły stan, nie `@GestureState`: gest przewracania stron jest
    /// UIKit-owy (`OptionsPagePan`), więc powrót do zera robimy sami.
    @State private var dragX: CGFloat = 0

    init(
        slotDetail: String?,
        options: [OptionsCardItemDTO],
        initialPage: Int,
        mode: OptionsStoryMode,
        catalog: RecipeCatalogStore,
        onChoose: @escaping (OptionsCardItemDTO) -> Void,
        onMore: @escaping (String) -> Void = { _ in },
        onCompose: @escaping () -> Void,
        onApply: (() -> Void)? = nil,
        contexts: [ProposalStoryContext] = [],
        isBusy: Bool = false,
        onOpenPlan: (() -> Void)? = nil,
        onRegenerate: (() -> Void)? = nil
    ) {
        self.slotDetail = slotDetail
        self.options = options
        self.mode = mode
        self.catalog = catalog
        self.onChoose = onChoose
        self.onMore = onMore
        self.onCompose = onCompose
        self.onApply = onApply
        self.contexts = contexts
        self.isBusy = isBusy
        self.onOpenPlan = onOpenPlan
        self.onRegenerate = onRegenerate
        let start = min(max(initialPage, 0), options.count)
        let startDish = min(start, max(options.count - 1, 0))
        _page = State(initialValue: start)
        _dish = State(initialValue: startDish)
        _previousDish = State(initialValue: startDish)
    }

    private var endPage: Int { options.count }
    private var isEnd: Bool { page == endPage }

    /// Przycisk pod daniem: „Wstaw na środę” przy wyborze, „Zamień to danie”
    /// przy przeglądzie propozycji; `nil` = sam podgląd (propozycja już
    /// zapisana albo nieaktualna).
    private var dishActionTitle: String? {
        switch mode {
        case let .choose(insertTitle, _): return insertTitle
        case let .review(swapTitle, _, _): return swapTitle
        }
    }

    private var dishActionIcon: String {
        switch mode {
        case .choose: return "arrow.right"
        case .review: return "arrow.triangle.2.circlepath"
        }
    }

    private var morePrompt: String? {
        if case let .choose(_, morePrompt) = mode { return morePrompt }
        return nil
    }

    private var isReview: Bool {
        if case .review = mode { return true }
        return false
    }

    private var applyTitle: String? {
        if case let .review(_, applyTitle, _) = mode { return applyTitle }
        return nil
    }

    /// Stan propozycji w przeglądzie; `nil` przy wyborze z kilku dań.
    private var reviewStatus: AssistantCardStatus? {
        if case let .review(_, _, status) = mode { return status }
        return nil
    }

    private func context(_ index: Int) -> ProposalStoryContext? {
        contexts.indices.contains(index) ? contexts[index] : nil
    }

    /// Chrom (uchwyt, nagłówek, segmenty) jest biały tylko na zdjęciu.
    private var chromeOnPhoto: Bool {
        !isEnd && options.indices.contains(dish) && options[dish].imageUrl != nil
    }

    /// `rgba(20,12,8,…)` — przyciemnienie góry zdjęcia pod białym chromem.
    private static let photoShade = Color(red: 20 / 255, green: 12 / 255, blue: 8 / 255)

    var body: some View {
        let allFacts = options.map { facts(for: $0) }
        return ZStack(alignment: .top) {
            Color.scPageBase(scheme)
                .ignoresSafeArea()

            if !options.isEmpty {
                dishLayer(allFacts)
                    // Gaśnie jako JEDEN obraz. Bez spłaszczenia każda warstwa
                    // (zdjęcia, gradient) blaknie osobno i zdjęcie prześwituje
                    // przez dół gradientu twardą krawędzią.
                    .compositingGroup()
                    .opacity(isEnd ? 0 : 1)
                    .allowsHitTesting(!isEnd)
                    .accessibilityHidden(isEnd)
                    // Opis i makro dociągnięte po otwarciu wchodzą miękko.
                    .animation(motion(.smooth(duration: 0.35)), value: allFacts)
            }

            endLayer
                .allowsHitTesting(isEnd)
                .accessibilityHidden(!isEnd)

            chrome
        }
        // Gest UIKit-owy, nie `DragGesture`: SwiftUI-owy przeciąg na całym
        // arkuszu zaczynał się przy KAŻDYM ruchu powyżej 12 pt i odbierał
        // systemowi przeciągnięcie arkusza w dół — zamknięcie palcem raz
        // działało, raz nie. Ten rusza wyłącznie przy ruchu wyraźnie
        // poziomym; pionowy od pierwszej klatki należy do arkusza.
        .gesture(
            OptionsPagePan(
                onChanged: { dragX = $0 },
                onEnded: { dx, velocity in finishSwipe(dx: dx, velocity: velocity) }
            )
        )
        .sensoryFeedback(.selection, trigger: page)
        .task {
            // Klatka oddechu: arkusz zaczyna wjeżdżać, dopiero potem treść.
            try? await Task.sleep(for: .milliseconds(80))
            appeared = true
        }
        .task { await loadMissingFacts() }
        #if DEBUG
        .task { await debugAutoplay() }
        #endif
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(40)
        .presentationBackground(Color.scPageBase(scheme))
    }

    // MARK: Ruch

    /// Przy „Ogranicz ruch” zostają same krótkie przenikania.
    private func motion(_ animation: Animation) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : animation
    }

    /// Kaskada wejścia: `order` to kolejność od góry treści.
    ///
    /// `geometryGroup()`: blok podjeżdża jako JEDNA całość. Bez tego elementy
    /// z własną animacją w środku (segmenty paska, liczące cyfry) podjeżdżałyby
    /// każdy swoim tempem i przez chwilę stały na różnych wysokościach.
    private func entrance<Content: View>(_ order: Int, _ content: Content) -> some View {
        content
            .geometryGroup()
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 14)
            .animation(motion(.smooth(duration: 0.55).delay(0.10 + Double(order) * 0.05)), value: appeared)
    }

    /// −1 / 0 / +1: po której stronie bieżącego dania stoi `index`.
    private func side(_ index: Int) -> CGFloat {
        CGFloat((index - dish).signum())
    }

    /// Nazwa, opis, tag, stopka: nieaktywne czekają 26 pt z boku i wjeżdżają
    /// w stronę gestu. Znikające gaśnie SZYBCIEJ niż wchodzi nowe — dwa teksty
    /// naraz w pół krycia to kasza.
    private func swapping<Content: View>(_ index: Int, shift: CGFloat = 26, _ content: Content) -> some View {
        let current = index == dish
        let sideShift = reduceMotion ? 0 : side(index) * shift
        // Animacja ZAWĘŻONA do krycia i bocznego przesunięcia. Zwykłe
        // `.animation(value:)` nadpisałoby transakcję całemu poddrzewu, więc
        // tag jechałby w pionie własnym tempem, osobno od eyebrow obok.
        return content
            .animation(
                current ? motion(.smooth(duration: 0.38).delay(0.11)) : motion(.easeOut(duration: 0.12))
            ) {
                $0.opacity(current ? 1 : 0).offset(x: sideShift)
            }
            .accessibilityHidden(!current)
    }

    // MARK: Dane dania

    private func recipe(for option: OptionsCardItemDTO) -> Recipe? {
        guard let id = UUID(uuidString: option.recipeId) else { return nil }
        return catalog.recipes.first { $0.id == id }
    }

    private func facts(for option: OptionsCardItemDTO) -> OptionsDishFacts {
        OptionsDishFacts(option: option, recipe: recipe(for: option))
    }

    /// Karta sprzed pól szczegółu (albo przepis bez opisu w karcie): bierzemy
    /// je z katalogu. Najpierw CAŁY katalog — tak jak robią to inne arkusze —
    /// bo pojedyncze `loadRecipeDetail` na pustym katalogu zapisałoby do
    /// cache'u trzy przepisy jako „cały katalog”. Dopiero czego dalej brakuje,
    /// dociągamy po id, od otwartej strony.
    private func loadMissingFacts() async {
        func isComplete(_ option: OptionsCardItemDTO) -> Bool {
            option.description != nil && option.proteinGrams != nil && option.carbsGrams != nil
                && option.fatGrams != nil && option.ingredientCount != nil
        }
        guard options.contains(where: { !isComplete($0) }) else { return }
        await catalog.loadIfNeeded()

        let order = options.indices.sorted { abs($0 - page) < abs($1 - page) }
        for index in order {
            let option = options[index]
            guard !isComplete(option), let id = UUID(uuidString: option.recipeId) else { continue }
            if let known = recipe(for: option), !known.ingredients.isEmpty { continue }
            if Task.isCancelled { return }
            _ = await catalog.loadRecipeDetail(recipeId: id)
        }
    }

    // MARK: Chrom

    /// Uchwyt `top: 8`, nagłówek `top: 20; height: 40`, segmenty `top: 70`.
    private var chrome: some View {
        let light = chromeOnPhoto
        return VStack(spacing: 0) {
            Capsule(style: .continuous)
                .fill(light ? Color.white.opacity(0.8) : AssistantLook.ink(scheme).opacity(0.18))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .accessibilityHidden(true)

            ZStack {
                HStack(spacing: 7) {
                    OptionsKesMark(size: 15, color: light ? Color.white : AssistantLook.terraFill(scheme))
                        .accessibilityHidden(true)
                    Text("Asystent")
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(light ? Color.white : AssistantLook.ink(scheme))
                }
                .shadow(color: .black.opacity(light ? 0.35 : 0), radius: 1, y: 1)
                .accessibilityAddTraits(.isHeader)

                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(light ? AssistantLook.ink(.light) : AssistantLook.ink(scheme))
                            .frame(width: 34, height: 34)
                            .background(
                                Circle().fill(light ? Color.white.opacity(0.92) : AssistantLook.field(scheme))
                            )
                            .overlay(Circle().stroke(AssistantLook.cardStroke(scheme), lineWidth: light ? 0 : 1))
                            .contentShape(Circle().inset(by: -5))
                    }
                    .buttonStyle(PlanPressStyle(scale: 0.94))
                    .accessibilityLabel("Zamknij")
                }
            }
            .frame(height: 40)
            .padding(.top, 7)
            .padding(.horizontal, 16)

            segments
                .padding(.horizontal, 16)
                .padding(.top, 10)
        }
        .opacity(appeared ? 1 : 0)
        .animation(motion(.easeOut(duration: 0.35)), value: appeared)
        .animation(motion(.easeInOut(duration: 0.3)), value: light)
    }

    /// `gap: 5; height: 3; radius: 2`. Na zdjęciu biel (aktywny 1, reszta
    /// 0,45, kreski 0,6); na stronie końcowej szarość 0,16 i pełna terakota.
    /// Aktywny segment to JEDEN kształt, który przesuwa się między slotami.
    private var segments: some View {
        let light = chromeOnPhoto
        let on = light ? Color.white : AssistantLook.terra(scheme)
        let off = light ? Color.white.opacity(0.45) : AssistantLook.ink(scheme).opacity(0.16)
        return HStack(spacing: 5) {
            ForEach(options.indices, id: \.self) { index in
                segmentButton(index, label: "Danie \(index + 1) z \(options.count)") {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(off)
                } active: {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(on)
                }
            }
            // „Coś innego” to nie kolejne danie, tylko wyjście — krótka pełna
            // pigułka zamiast kolejnego pełnego segmentu (i zamiast dawnych
            // kresek). Aktywny wskaźnik zwęża się do niej tym samym ruchem.
            // W przeglądzie koniec to zgoda na całość — szałwia, kolor zapisu.
            segmentButton(endPage, label: isReview ? "Cały zestaw" : "Coś innego", width: Self.endSegmentWidth) {
                Capsule(style: .continuous).fill(off)
            } active: {
                Capsule(style: .continuous).fill(isReview ? AssistantLook.sage(scheme) : AssistantLook.terra(scheme))
            }
        }
    }

    /// Segment jest też skokiem na stronę — pole dotyku wyższe niż sama kreska,
    /// ale bez wpływu na układ (ujemny margines zjada dodaną wysokość).
    private static let endSegmentWidth: CGFloat = 18

    private func segmentButton<Track: View, Active: View>(
        _ target: Int,
        label: String,
        width: CGFloat? = nil,
        @ViewBuilder track: () -> Track,
        @ViewBuilder active: () -> Active
    ) -> some View {
        Button { go(to: target) } label: {
            ZStack {
                track()
                if target == page {
                    active().matchedGeometryEffect(id: "active", in: segmentSpace)
                }
            }
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(height: 3)
            .frame(height: 23)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -10)
        .accessibilityLabel(label)
        .accessibilityAddTraits(target == page ? [.isSelected] : [])
    }

    // MARK: Warstwa dań

    /// Treść przypięta do dołu (`CTA bottom: 40`, blok informacji 24 nad nim),
    /// zdjęcie od góry do początku treści + 13 pt zakładki — dokładnie tyle,
    /// ile w makiecie (zdjęcie 440, eyebrow od 427). Wysokość treści jest ta
    /// sama dla każdego dania, więc i zdjęcie ma jeden rozmiar.
    private func dishLayer(_ allFacts: [OptionsDishFacts]) -> some View {
        OptionsStoryLayout {
            photos

            VStack(spacing: 0) {
                info(allFacts)
                if let dishActionTitle {
                    entrance(
                        5,
                        AssistantPrimaryButton(
                            action: AssistantCardAction(title: dishActionTitle, icon: dishActionIcon) {
                                if options.indices.contains(dish) { onChoose(options[dish]) }
                            }
                        )
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 6)
                } else {
                    Color.clear.frame(height: 30)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Wszystkie zdjęcia leżą w jednym miejscu od otwarcia arkusza (więc są
    /// już pobrane, gdy przychodzi ich kolej). Nowe przenika NAD poprzednim,
    /// schodząc z lekkiego powiększenia; oba mają zapas kadru na ugięcie za
    /// palcem, żeby przy krawędzi nie wyszło tło.
    private var photos: some View {
        let base = Color.scPageBase(scheme)
        let drag = reduceMotion ? 0 : max(-8, min(8, dragX * 0.06))
        return ZStack {
            ForEach(options.indices, id: \.self) { index in
                let current = index == dish
                photo(options[index])
                    .scaleEffect(reduceMotion ? 1 : (current ? (appeared ? 1.04 : 1.12) : 1.10))
                    .offset(x: reduceMotion ? 0 : (current ? drag : side(index) * 8))
                    .opacity(current || index == previousDish ? 1 : 0)
                    .zIndex(current ? 2 : (index == previousDish ? 1 : 0))
                    .animation(motion(.smooth(duration: 0.55)), value: dish)
                    .animation(motion(.easeOut(duration: 1.1)), value: appeared)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        // `linear-gradient(180deg, rgba(20,12,8,.5) 0%, rgba(20,12,8,0) 30%,
        // tło 0 → 58%, tło 100%)` — dół zdjęcia rozpływa się w arkusz.
        .overlay {
            LinearGradient(
                stops: [
                    .init(color: Self.photoShade.opacity(chromeOnPhoto ? 0.5 : 0), location: 0),
                    .init(color: Self.photoShade.opacity(0), location: 0.30),
                    .init(color: base.opacity(0), location: 0.58),
                    .init(color: base, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
    }

    private func photo(_ option: OptionsCardItemDTO) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                CachedAsyncImage(url: option.imageUrl.flatMap(URL.init(string:)), variant: .large) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity.animation(.easeOut(duration: 0.35)))
                    default:
                        ZStack {
                            AssistantLook.terraTint(scheme)
                            Image(systemName: "fork.knife")
                                .font(.system(size: 38, weight: .medium))
                                .foregroundStyle(AssistantLook.terra(scheme).opacity(0.5))
                        }
                    }
                }
            }
            .clipped()
    }

    /// `OptSheetInfo`: eyebrow z tagiem · nazwa 30/34 · opis 15/21 · liczby.
    ///
    /// Tekst jest przypięty do DOŁU slotu, tuż nad liczbami: opis zawsze klei
    /// się do nazwy, a nazwa do eyebrow — bez pustej linijki przy krótkiej
    /// nazwie. Slot ma wysokość najdłuższego dania, więc zdjęcie, liczby
    /// i przycisk stoją w miejscu; przy krótszym daniu luz zostaje NAD
    /// eyebrow, gdzie zdjęcie i tak rozpływa się już w tło. Eyebrow dojeżdża
    /// do nowej wysokości płynnie, razem ze zmianą dania.
    private func info(_ allFacts: [OptionsDishFacts]) -> some View {
        let drag = reduceMotion ? 0 : dragX * 0.16
        let currentFacts = allFacts.indices.contains(dish) ? allFacts[dish] : nil
        let currentHeight = textHeights[dish] ?? textHeights.values.max() ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Miejsce na eyebrow i odstęp (10) nad NAJWYŻSZYM stosem.
                Color.clear.frame(height: eyebrowHeight + 10)

                ZStack(alignment: .bottomLeading) {
                    ForEach(options.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            entrance(1, swapping(index, titleText(options[index])))
                            if let description = allFacts[index].description {
                                entrance(2, swapping(index, shift: 18, descriptionText(description)))
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            textHeights[index] = height
                        }
                    }
                }
                .offset(x: drag)
            }
            .overlay(alignment: .bottomLeading) {
                entrance(0, eyebrowRow)
                    .offset(y: -(currentHeight + 10))
                    .animation(motion(.smooth(duration: 0.42)), value: dish)
                    .animation(motion(.smooth(duration: 0.35)), value: textHeights)
            }

            entrance(
                3,
                OptionsMacroStats(
                    kcal: options.indices.contains(dish) ? options[dish].kcalPerServing : 0,
                    minutes: options.indices.contains(dish) ? options[dish].prepTimeMinutes : 0,
                    ingredients: currentFacts?.ingredientCount,
                    macros: currentFacts?.macros,
                    reservesMacros: allFacts.contains { $0.macros != nil },
                    armed: appeared
                )
            )
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    /// Wysokość rzędu nad nazwą: pigułki pory i dnia w przeglądzie są
    /// wyższe niż sam eyebrow przy wyborze.
    private var eyebrowHeight: CGFloat { usesWhenRow ? 28 : 21 }

    private var usesWhenRow: Bool { isReview && !contexts.isEmpty }

    @ViewBuilder
    private var eyebrowRow: some View {
        if usesWhenRow {
            whenRow
        } else {
            choiceEyebrowRow
        }
    }

    /// Przegląd propozycji: KIEDY i NA CO, zanim przeczyta się nazwę —
    /// „Śniadanie” w kolorze pory i „Dziś, 23 września”. Zmienia się razem
    /// z daniem, tym samym ruchem co tag przy wyborze.
    private var whenRow: some View {
        ZStack(alignment: .leading) {
            ForEach(options.indices, id: \.self) { index in
                if let when = context(index) {
                    swapping(
                        index,
                        shift: 10,
                        ProposalWhenPills(context: when, saved: reviewStatus == .applied)
                    )
                }
            }
        }
        .frame(minHeight: eyebrowHeight, alignment: .leading)
    }

    /// Eyebrow stoi w miejscu; zmienia się tylko tag obok niego.
    private var choiceEyebrowRow: some View {
        HStack(spacing: 8) {
            Text(eyebrowText)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundStyle(AssistantLook.terra(scheme))
                .lineHeight(.exact(points: 14))
                .lineLimit(1)
                .layoutPriority(1)

            ZStack(alignment: .leading) {
                ForEach(options.indices, id: \.self) { index in
                    if let tag = options[index].tag, !tag.isEmpty {
                        swapping(
                            index,
                            shift: 10,
                            Text(tag)
                                .font(.system(size: 11, weight: .bold))
                                .tracking(0.3)
                                .foregroundStyle(AssistantLook.terra(scheme))
                                .lineHeight(.exact(points: 13))
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(AssistantLook.terraTint(scheme)))
                        )
                    }
                }
            }
        }
        .frame(minHeight: 21, alignment: .leading)
    }

    private func titleText(_ option: OptionsCardItemDTO) -> some View {
        Text(option.title)
            .font(.system(size: 30, weight: .bold))
            .tracking(-0.8)
            .foregroundStyle(AssistantLook.ink(scheme))
            .lineHeight(.exact(points: 34))
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func descriptionText(_ description: String) -> some View {
        Text(description)
            .font(.system(size: 15))
            .tracking(-0.2)
            .foregroundStyle(AssistantLook.muted(scheme))
            .lineHeight(.exact(points: 21))
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eyebrowText: String {
        let lead = isReview ? "Propozycja" : "Do wyboru"
        guard let slotDetail else { return lead }
        return "\(lead) · \(slotDetail)"
    }

    // MARK: Strona końcowa

    @ViewBuilder
    private var endLayer: some View {
        if let reviewStatus {
            reviewEndLayer(reviewStatus)
        } else {
            choiceEndLayer
        }
    }

    /// Strona końcowa PRZEGLĄDU propozycji — mówi, w jakim stanie JEST
    /// propozycja, a nie zawsze „Wszystko pasuje?”. Stan przychodzi
    /// z serwera przy każdym odświeżeniu karty, więc otwarty arkusz sam
    /// przechodzi z „Wszystko pasuje?” przez „Zapisuję…” w „Jest w planie”.
    /// Zgoda na całość jest w szałwii — to kolor zapisu w całej aplikacji.
    private func reviewEndLayer(_ status: AssistantCardStatus) -> some View {
        let copy = ProposalEndCopy(status: status, isBusy: isBusy)
        let text = reduceMotion ? 0 : dragX * 0.16
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    endStep(0, scale: 0.8) {
                        ProposalStatusBadge(status: status, isBusy: isBusy)
                    }

                    endStep(1, rise: 14) {
                        VStack(spacing: 0) {
                            Text(copy.eyebrow)
                                .font(.system(size: 11, weight: .bold))
                                .tracking(0.9)
                                .textCase(.uppercase)
                                .foregroundStyle(copy.accent(scheme))
                                .lineHeight(.exact(points: 14))
                            Text(copy.title)
                                .font(.system(size: 30, weight: .bold))
                                .tracking(-0.9)
                                .foregroundStyle(AssistantLook.ink(scheme))
                                .lineHeight(.exact(points: 34))
                                .padding(.top, 10)
                            Text(copy.body)
                                .font(.system(size: 15))
                                .foregroundStyle(AssistantLook.muted(scheme))
                                .lineHeight(.exact(points: 21))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 10)
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .offset(x: text)
                    }
                    .padding(.top, 22)

                    endStep(2, rise: 16) {
                        ProposalRecap(
                            options: options,
                            contexts: contexts,
                            status: status
                        )
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 24)

                    if status == .pending, !isBusy, let onRegenerate {
                        endStep(3, rise: 10) {
                            ProposalRegenerateLink(title: regenerateTitle, action: onRegenerate)
                        }
                        .padding(.top, 10)
                        .transition(.opacity)
                    }
                }
                // 118 = uchwyt, nagłówek i segmenty nad treścią.
                .padding(.top, 118)
                .padding(.bottom, 16)
                .animation(motion(.smooth(duration: 0.4)), value: status)
                .animation(motion(.smooth(duration: 0.3)), value: isBusy)
            }
            // Krótka treść stoi na środku wolnego miejsca; dłuższa
            // (tydzień, mały telefon) zaczyna od góry i się przewija.
            .defaultScrollAnchor(.center, for: .alignment)
            .defaultScrollAnchor(.top, for: .initialOffset)
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .scScrollEdgeFade()

            endStep(3, rise: 20) {
                // JEDEN przycisk na dole (runda 15, Rafał): zapis całości,
                // po zapisie „Otwórz plan”, a gdy propozycji nie da się już
                // zapisać — „Napisz, co zmienić”. Nowe dania to cichy
                // odnośnik pod listą, nie drugi przycisk.
                Group {
                    if let applyTitle, let onApply {
                        ProposalAcceptButton(
                            title: isBusy ? "Zapisuję…" : applyTitle,
                            icon: "checkmark",
                            isBusy: isBusy,
                            action: onApply
                        )
                        .transition(.opacity)
                    } else if status == .applied, let onOpenPlan {
                        ProposalAcceptButton(title: "Otwórz plan", icon: "arrow.right", action: onOpenPlan)
                            .transition(.opacity)
                    } else if !isBusy {
                        AssistantGhostButton(
                            action: AssistantCardAction(
                                title: copy.composeTitle,
                                icon: "square.and.pencil"
                            ) {
                                onCompose()
                            }
                        )
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
                .animation(motion(.smooth(duration: 0.35)), value: status)
                .animation(motion(.smooth(duration: 0.3)), value: isBusy)
            }
        }
        .background(
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()
                .opacity(isEnd ? 1 : 0)
                .animation(motion(.easeInOut(duration: 0.35)), value: isEnd)
        )
    }

    /// `OptStorySheet end`: kreskowany segment staje się pełny — znak marki
    /// (`EBrand` × 1,7, środek na 248/798), jedno pytanie (od 366/798), dwa
    /// wyjścia przypięte do dołu. Wchodzi kaskadą: znak, pytanie, przyciski.
    private var choiceEndLayer: some View {
        GeometryReader { geo in
            let full = geo.size.height + geo.safeAreaInsets.bottom
            let text = reduceMotion ? 0 : dragX * 0.16
            ZStack(alignment: .top) {
                endStep(0, scale: 0.8) {
                    OptionsBrandBadge()
                }
                .position(x: geo.size.width / 2, y: full * 248 / 798)

                endStep(1, rise: 14) {
                    VStack(spacing: 0) {
                        Text("Coś innego")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.9)
                            .textCase(.uppercase)
                            .foregroundStyle(AssistantLook.terra(scheme))
                            .lineHeight(.exact(points: 14))
                        Text("Żadne nie pasuje?")
                            .font(.system(size: 32, weight: .bold))
                            .tracking(-0.9)
                            .foregroundStyle(AssistantLook.ink(scheme))
                            .lineHeight(.exact(points: 36))
                            .padding(.top, 10)
                        Text(endBody)
                            .font(.system(size: 15))
                            .foregroundStyle(AssistantLook.muted(scheme))
                            .lineHeight(.exact(points: 21))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .offset(x: text)
                }
                .padding(.top, full * 366 / 798)

                endStep(2, rise: 20) {
                    // Ten sam układ pary co w stopce karty: poboczna pierwsza,
                    // główna na końcu. „Napisz, na co masz ochotę” nie mieści
                    // się w połówce, więc para staje w stos i główna ląduje
                    // NA DOLE — dokładnie tam, gdzie na stronach dań stoi
                    // „Wstaw na środę”; przy przewracaniu na stronę końcową
                    // główna akcja nie skacze.
                    AssistantActionPair(spacing: 10) {
                        AssistantGhostButton(
                            action: AssistantCardAction(
                                title: "Napisz, na co masz ochotę",
                                icon: "square.and.pencil"
                            ) {
                                onCompose()
                            }
                        )
                        if let morePrompt {
                            AssistantPrimaryButton(
                                action: AssistantCardAction(
                                    title: OptionsCopy.moreTitle(options.count),
                                    icon: "arrow.clockwise"
                                ) { onMore(morePrompt) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .background(
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()
                .opacity(isEnd ? 1 : 0)
                .animation(motion(.easeInOut(duration: 0.35)), value: isEnd)
        )
    }

    /// Jedno danie — „Zaproponuj inne danie”, kilka — „inne dania”.
    private var regenerateTitle: String {
        options.count == 1 ? "Zaproponuj inne danie" : "Zaproponuj inne dania"
    }

    private var endBody: String {
        morePrompt == nil
            ? "Napisz, na co masz ochotę — poszukam w Twoich przepisach."
            : "Pokażę \(options.count) kolejne z Twoich przepisów — albo napisz, na co masz ochotę."
    }

    /// Element strony końcowej: wchodzi z opóźnieniem wg `order`, wychodzi od
    /// razu — opóźnione ZNIKANIE wyglądałoby jak zacięcie.
    private func endStep<Content: View>(
        _ order: Int,
        scale: CGFloat = 1,
        rise: CGFloat = 0,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        content()
            .scaleEffect(isEnd || reduceMotion ? 1 : scale)
            .offset(y: isEnd || reduceMotion ? 0 : rise)
            .opacity(isEnd ? 1 : 0)
            .animation(
                isEnd
                    ? motion(.spring(duration: 0.6, bounce: scale < 1 ? 0.28 : 0).delay(0.08 + Double(order) * 0.07))
                    : motion(.easeOut(duration: 0.16)),
                value: isEnd
            )
    }

    // MARK: Nawigacja

    /// Koniec poziomego przeciągnięcia (`OptionsPagePan`). Krótki, ale
    /// szybki ruch też przewraca stronę.
    private func finishSwipe(dx: CGFloat, velocity: CGFloat) {
        if dx < -50 || (dx < -16 && velocity < -450) {
            go(to: page + 1)
        } else if dx > 50 || (dx > 16 && velocity > 450) {
            go(to: page - 1)
        }
        // Treść wraca spod palca sprężyną — także gdy strona się zmieniła,
        // bo wtedy odjeżdża razem z przewróceniem.
        withAnimation(motion(.snappy(duration: 0.3))) { dragX = 0 }
    }

    private func go(to target: Int) {
        let next = min(max(target, 0), endPage)
        guard next != page else { return }
        withAnimation(motion(.smooth(duration: 0.42))) {
            if next < endPage, next != dish {
                previousDish = dish
                dish = next
            }
            page = next
        }
    }

    #if DEBUG
    /// `SCOFFIE_DEBUG_OPTIONS_AUTOPLAY` — arkusz sam przechodzi po stronach,
    /// żeby animacje dało się nagrać na symulatorze bez dotyku.
    private func debugAutoplay() async {
        guard ProcessInfo.processInfo.environment["SCOFFIE_DEBUG_OPTIONS_AUTOPLAY"] != nil,
              endPage >= 1 else { return }
        try? await Task.sleep(for: .seconds(3))
        for target in Array(1...endPage) + Array((0..<endPage).reversed()) {
            if Task.isCancelled { return }
            go(to: target)
            try? await Task.sleep(for: .milliseconds(1500))
        }
    }
    #endif
}

/// `OptStats variant="macro"`: kcal · min 22/700, pod nimi pasek białko /
/// węgle / tłuszcz (8 pt, odstęp 3) i legenda 12,5. Bez makro — same liczby.
///
/// Liczba składników stoi w TYM SAMYM rzędzie co kcal i min (w makiecie była
/// szarą linijką pod legendą — czytała się jak przypis, a jest jedną z trzech
/// rzeczy, po których wybiera się danie). „na porcję” domyka rząd po prawej
/// i znika, gdy się nie mieści.
///
/// Widok jest TRWAŁY między daniami: dostaje nowe wartości, a nie nowe życie,
/// więc cyfry rolują się, a segmenty paska płynnie zmieniają szerokość.
// MARK: - Przegląd propozycji: kiedy, stan, zgoda

/// „☀ Śniadanie” w kolorze pory + „Dziś, 23 września” (+ „W planie” po
/// zapisie, gdy się mieści) — nad nazwą dania w arkuszu przeglądu.
private struct ProposalWhenPills: View {
    let context: ProposalStoryContext
    let saved: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            pills(showsSaved: saved)
            pills(showsSaved: false)
        }
        .accessibilityElement(children: .combine)
    }

    private func pills(showsSaved: Bool) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                if let slot = context.slot {
                    Image(systemName: slot.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(slot.cozyAccent)
                }
                Text(context.slot?.title ?? context.mealLabel)
                    .font(.system(size: 13.5, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(AssistantLook.ink(scheme))
            }
            .modifier(ProposalPill(fill: (context.slot?.cozyAccent ?? AssistantLook.terraFill(scheme)).opacity(scheme == .dark ? 0.22 : 0.16)))

            if let day = context.day {
                Text(day)
                    .font(.system(size: 13.5, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(AssistantLook.ink(scheme))
                    .modifier(ProposalPill(fill: AssistantLook.field(scheme)))
            }

            if showsSaved {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("W planie")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(AssistantLook.sage(scheme))
                .modifier(ProposalPill(fill: AssistantLook.sageTint(scheme)))
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

private struct ProposalPill: ViewModifier {
    let fill: Color

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule(style: .continuous).fill(fill))
    }
}

/// Słowa strony końcowej przeglądu dla każdego stanu propozycji.
private struct ProposalEndCopy {
    let status: AssistantCardStatus
    let isBusy: Bool

    var eyebrow: String {
        if isBusy { return "Zapisuję" }
        switch status {
        case .pending: return "Cały zestaw"
        case .applied: return "Zapisane"
        case .undone: return "Cofnięte"
        case .stale: return "Nieaktualna"
        case .expired: return "Wygasła"
        case .failed: return "Nie zapisano"
        }
    }

    var title: String {
        if isBusy { return "Wstawiam do planu…" }
        switch status {
        case .pending: return "Wszystko pasuje?"
        case .applied: return "Jest w planie"
        case .undone: return "Plan wrócił"
        case .stale: return "Plan się zmienił"
        case .expired: return "Propozycja wygasła"
        case .failed: return "Nie udało się zapisać"
        }
    }

    var body: String {
        if isBusy { return "Chwila — zaraz wszystko będzie w planie." }
        switch status {
        case .pending: return "Zapiszę cały zestaw jednym dotknięciem."
        case .applied: return "Wszystkie dania z tej propozycji czekają w Twoim planie."
        case .undone: return "Cofnąłem ten zapis. Możesz zastosować go jeszcze raz."
        case .stale: return "Od tej propozycji plan się zmienił. Poproś o nową — policzę od nowa."
        case .expired: return "Poproś o nową — policzę ją od nowa."
        case .failed: return "Plan jest bez zmian. Spróbuj jeszcze raz."
        }
    }

    var composeTitle: String { "Napisz, co zmienić" }

    func accent(_ scheme: ColorScheme) -> Color {
        switch status {
        case .pending, .applied: return AssistantLook.sage(scheme)
        case .failed: return AssistantLook.terra(scheme)
        case .undone, .stale, .expired: return AssistantLook.faint(scheme)
        }
    }
}

/// Odznaka nad pytaniem: propozycja = szałwiowy krążek z ptaszkiem
/// w obwódce (zgoda czeka), zapis = pełna szałwia, zapis w toku = kółko
/// postępu. Pozostałe stany w cichej szarości.
private struct ProposalStatusBadge: View {
    let status: AssistantCardStatus
    let isBusy: Bool

    @Environment(\.colorScheme) private var scheme

    private var solid: Bool { status == .applied && !isBusy }

    private var symbol: String {
        switch status {
        case .pending, .applied: return "checkmark"
        case .undone: return "arrow.uturn.backward"
        case .stale: return "arrow.triangle.2.circlepath"
        case .expired: return "hourglass"
        case .failed: return "exclamationmark"
        }
    }

    private var color: Color {
        switch status {
        case .pending, .applied: return AssistantLook.sage(scheme)
        case .failed: return AssistantLook.terra(scheme)
        case .undone, .stale, .expired: return AssistantLook.faint(scheme)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(solid ? color : color.opacity(scheme == .dark ? 0.18 : 0.13))
            Circle()
                .strokeBorder(color.opacity(solid ? 0 : 0.45), lineWidth: 1.5)
            if isBusy {
                ProgressView()
                    .controlSize(.regular)
                    .tint(color)
                    .transition(.opacity)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(solid ? Color.white : color)
                    .contentTransition(.symbolEffect(.replace))
                    .transition(.opacity)
            }
        }
        .frame(width: 84, height: 84)
        .scaleEffect(solid ? 1.04 : 1)
        .animation(.spring(duration: 0.5, bounce: 0.35), value: solid)
        .accessibilityHidden(true)
    }
}

/// Cały zestaw jeszcze raz, w jednej karcie (runda 15, 24.09.2026 — Rafał:
/// „dopracuj design tych wybranych posiłków”): miniatura dania, pora
/// z ikoną w kolorze pory, nazwa i kcal po prawej. Do pięciu dań — wiersz na
/// danie; tydzień — wiersz na dzień z miniaturami jego dań, liczbą i sumą
/// kalorii. Nad listą dzień (jeden) i suma kcal zestawu. Karta jak każda
/// w aplikacji: `scTileBg` + `scTileStroke`, bez cienia.
private struct ProposalRecap: View {
    let options: [OptionsCardItemDTO]
    let contexts: [ProposalStoryContext]
    let status: AssistantCardStatus

    @Environment(\.colorScheme) private var scheme

    private static let thumb: CGFloat = 46

    private struct Row: Identifiable {
        let id: Int
        let icon: String?
        let accent: Color?
        let label: String
        let title: String
        let kcal: Int
        /// Zdjęcia: jedno dla dania, kilka (do trzech) dla dnia tygodnia.
        let images: [URL?]
    }

    private var days: [String] {
        var seen: [String] = []
        for day in contexts.compactMap(\.day) where !seen.contains(day) { seen.append(day) }
        return seen
    }

    private var isWeek: Bool { options.count > 5 }

    /// Jeden dzień → jego nazwa nad listą; tydzień → „Cały tydzień”.
    private var header: String {
        if days.count == 1 { return days[0] }
        return isWeek ? "Cały tydzień" : "Zestaw"
    }

    private var totalKcal: Int { options.reduce(0) { $0 + $1.kcalPerServing } }

    private func url(_ option: OptionsCardItemDTO) -> URL? {
        option.imageUrl.flatMap(URL.init(string:))
    }

    private var rows: [Row] {
        if !isWeek {
            return options.indices.map { index in
                let context = contexts.indices.contains(index) ? contexts[index] : nil
                var label = context?.slot?.title ?? context?.mealLabel ?? ""
                // Kilka dni w jednym zestawie (rzadkie) — dzień przy porze.
                if days.count > 1, let day = context?.day {
                    label += " · \(day.components(separatedBy: ",").first ?? day)"
                }
                return Row(
                    id: index,
                    icon: context?.slot?.icon,
                    accent: context?.slot?.cozyAccent,
                    label: label,
                    title: options[index].title,
                    kcal: options[index].kcalPerServing,
                    images: [url(options[index])]
                )
            }
        }
        return days.enumerated().map { offset, day in
            let indices = contexts.indices.filter { contexts[$0].day == day && options.indices.contains($0) }
            let kcal = indices.reduce(0) { $0 + options[$1].kcalPerServing }
            let count = indices.count
            let word = count == 1 ? "danie" : ((2...4).contains(count % 10) && !(12...14).contains(count % 100) ? "dania" : "dań")
            return Row(
                id: offset,
                icon: "calendar",
                accent: nil,
                label: day,
                title: "\(count) \(word)",
                kcal: kcal,
                images: indices.prefix(3).map { url(options[$0]) }
            )
        }
    }

    private var checkColor: Color? {
        switch status {
        case .pending, .applied: return AssistantLook.sage(scheme)
        default: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(header)
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(AssistantLook.faint(scheme))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if totalKcal > 0 {
                    Text("\(totalKcal) kcal")
                        .font(.system(size: 12.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(AssistantLook.muted(scheme))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                if offset > 0 {
                    Rectangle()
                        .fill(Color.scTileStroke(scheme))
                        .frame(height: 1)
                        .padding(.leading, 16 + Self.thumb + 12)
                        .padding(.trailing, 16)
                }
                rowView(row)
            }
        }
        .padding(.bottom, 6)
        .background(
            RoundedRectangle(cornerRadius: AssistantCardMetrics.listRadius, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AssistantCardMetrics.listRadius, style: .continuous)
                .strokeBorder(Color.scTileStroke(scheme), lineWidth: 1)
        )
        .opacity(status.tone == .muted ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 12) {
            thumbnails(row)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if let icon = row.icon {
                        Image(systemName: icon)
                            .font(.system(size: 10, weight: .bold))
                    }
                    Text(row.label)
                        .font(.system(size: 11.5, weight: .bold))
                        .tracking(0.2)
                        .lineLimit(1)
                }
                .foregroundStyle(row.accent ?? AssistantLook.muted(scheme))

                Text(row.title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(AssistantLook.ink(scheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                if let checkColor {
                    Image(systemName: status == .applied ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(checkColor)
                        .contentTransition(.symbolEffect(.replace))
                }
                if row.kcal > 0 {
                    Text("\(row.kcal) kcal")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(AssistantLook.faint(scheme))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Danie = jedna miniatura; dzień tygodnia = do trzech nałożonych
    /// krążków w tym samym kwadracie, żeby kolumna nazw nie skakała.
    @ViewBuilder
    private func thumbnails(_ row: Row) -> some View {
        if row.images.count <= 1 {
            AssistantThumbnail(url: row.images.first ?? nil, size: Self.thumb)
        } else {
            let small: CGFloat = 30
            let far = Self.thumb - small
            ZStack(alignment: .topLeading) {
                ForEach(Array(row.images.enumerated()), id: \.offset) { index, image in
                    AssistantThumbnail(url: image, size: small)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.scTileBg(scheme), lineWidth: 2))
                        .offset(
                            x: index == 1 ? far : (index == 2 ? far / 2 : 0),
                            y: index == 0 ? 0 : (index == 1 ? far / 2 : far)
                        )
                        .zIndex(Double(-index))
                }
            }
            .frame(width: Self.thumb, height: Self.thumb, alignment: .topLeading)
        }
    }
}

/// Cichy odnośnik pod listą zestawu: ikona odświeżenia + tytuł w terakocie,
/// bez tła — opcja, nie druga decyzja obok zapisu.
private struct ProposalRegenerateLink: View {
    let title: String
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .tracking(-0.2)
            }
            .foregroundStyle(AssistantLook.terra(scheme))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.97))
        .accessibilityHint("Asystent przygotuje nowy zestaw zamiast tego")
    }
}

/// Zgoda na całość: pigułka „soft” w szałwii — ten sam przycisk co
/// `AssistantPrimaryButton` (rozmiar `.regular`), tylko w kolorze zapisu.
private struct ProposalAcceptButton: View {
    let title: String
    var icon: String = "checkmark"
    var isBusy: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    private let size = AssistantButtonSize.regular

    var body: some View {
        let sage = AssistantLook.sage(scheme)
        Button(action: action) {
            HStack(spacing: 7) {
                if isBusy {
                    ProgressView().controlSize(.small).tint(sage)
                }
                Text(title)
                    .font(.system(size: size.fontSize, weight: .semibold))
                    .tracking(-0.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .contentTransition(.numericText())
                if !isBusy {
                    Image(systemName: icon)
                        .font(.system(size: size.iconSize, weight: .bold))
                }
            }
            .foregroundStyle(sage)
            .padding(.horizontal, size.horizontalPadding)
            .frame(maxWidth: .infinity)
            .frame(height: size.height)
            .scSoftCapsule(sage)
            .contentShape(Capsule())
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .disabled(isBusy)
    }
}

private struct OptionsMacroStats: View {
    let kcal: Int
    let minutes: Int
    let ingredients: Int?
    let macros: (protein: Int, carbs: Int, fat: Int)?
    /// Któreś danie ma makro — trzymamy miejsce na pasek, nawet gdy to nie ma.
    let reservesMacros: Bool
    /// Arkusz wjechał: liczby ruszają od zera, pasek wypełnia się od lewej.
    let armed: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Macro: Identifiable {
        let label: String
        let spoken: String
        let grams: Int
        let color: Color
        var id: String { label }
    }

    private var items: [Macro] {
        [
            Macro(label: "białko", spoken: "białka", grams: macros?.protein ?? 0,
                  color: AssistantLook.terraFill(scheme)),
            Macro(label: "węgle", spoken: "węglowodanów", grams: macros?.carbs ?? 0,
                  color: Color(red: 214 / 255, green: 170 / 255, blue: 60 / 255)),      // #D6AA3C
            Macro(label: "tłuszcz", spoken: "tłuszczu", grams: macros?.fat ?? 0,
                  color: Color(red: 123 / 255, green: 132 / 255, blue: 214 / 255)),     // #7B84D6
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    metric(kcal, unit: "kcal")
                    metric(minutes, unit: "min")
                        .opacity(minutes > 0 ? 1 : 0)
                    metric(ingredients ?? 0, unit: OptionsCopy.ingredientsWord(ingredients ?? 0))
                        .opacity(ingredients == nil ? 0 : 1)
                }
                .fixedSize()
                .layoutPriority(1)

                Spacer(minLength: 0)

                ViewThatFits(in: .horizontal) {
                    Text("na porcję")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(AssistantLook.faint(scheme))
                        .lineLimit(1)
                        .fixedSize()
                    Color.clear.frame(width: 0, height: 0)
                }
            }

            if reservesMacros || macros != nil {
                Group {
                    bar
                        .padding(.top, 10)
                    legend
                        .padding(.top, 8)
                }
                .opacity(macros == nil ? 0 : 1)
                .transition(.opacity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func metric(_ value: Int, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            OptionsStatNumber(value: value, armed: armed)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(AssistantLook.ink(scheme))
            Text(unit)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AssistantLook.faint(scheme))
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: unit)
        }
    }

    /// `flex: v / tot; gap: 3`. Trzy TE SAME kapsuły dla każdego dania —
    /// zmieniają szerokość i pozycję, zamiast znikać i pojawiać się od nowa.
    ///
    /// Przy wejściu pasek rośnie od lewej JEDNYM ruchem: kapsuły stoją od razu
    /// w docelowych proporcjach, a odsłania je jedna maska. Wcześniej każdy
    /// segment wyrastał osobno, ze swoim opóźnieniem — pasek składał się
    /// „per makro” zamiast rosnąć jako całość.
    private var bar: some View {
        let values = items.map { CGFloat(max(0, $0.grams)) }
        let total = max(1, values.reduce(0, +))
        let visible = values.filter { $0 > 0 }.count
        let grown = armed || reduceMotion
        return GeometryReader { geo in
            let free = max(0, geo.size.width - 3 * CGFloat(max(0, visible - 1)))
            let widths = values.map { $0 > 0 ? max(6, free * $0 / total) : 0 }
            let scale = widths.reduce(0, +) > 0 ? free / widths.reduce(0, +) : 0
            ZStack(alignment: .leading) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, macro in
                    let width = widths[index] * scale
                    let before = widths[..<index].reduce(0) { $0 + $1 * scale }
                    let gaps = CGFloat(values[..<index].filter { $0 > 0 }.count) * 3
                    Capsule()
                        .fill(macro.color)
                        .frame(width: width)
                        .offset(x: before + gaps)
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            // Zmiana dania: proporcje przechodzą w miejscu.
            .animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.14), value: values)
            .mask(alignment: .leading) {
                Capsule()
                    .frame(width: grown ? geo.size.width : 0)
                    .animation(
                        reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.9).delay(0.32),
                        value: grown
                    )
            }
        }
        .frame(height: 8)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(items) { macro in
                HStack(spacing: 6) {
                    Circle().fill(macro.color).frame(width: 8, height: 8)
                    HStack(spacing: 3) {
                        HStack(spacing: 3) {
                            OptionsStatNumber(value: macro.grams, armed: armed)
                            Text("g")
                        }
                        .fontWeight(.bold)
                        .foregroundStyle(AssistantLook.ink(scheme))
                        Text(macro.label)
                            .foregroundStyle(AssistantLook.muted(scheme))
                    }
                }
            }
        }
        .font(.system(size: 12.5))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private var accessibilityText: String {
        var parts = ["\(kcal) kilokalorii na porcję"]
        if minutes > 0 { parts.append("\(minutes) minut") }
        if let ingredients { parts.append("\(ingredients) \(OptionsCopy.ingredientsWord(ingredients))") }
        if macros != nil { parts += items.map { "\($0.grams) gramów \($0.spoken)" } }
        return parts.joined(separator: ", ")
    }
}

/// Liczba w arkuszu: przy wejściu liczy od zera (jak `CountingNumber`), a przy
/// zmianie dania roluje cyfry w miejscu (jak `SCRollingNumber`).
private struct OptionsStatNumber: View {
    let value: Int
    let armed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var counted = false

    var body: some View {
        Group {
            if counted || reduceMotion {
                SCRollingNumber(value: value, duration: 0.4)
            } else {
                // Niewidoczna wartość docelowa trzyma szerokość od pierwszej
                // klatki, żeby jednostka obok („kcal”) nie jeździła w trakcie
                // liczenia.
                Text(verbatim: String(value))
                    .monospacedDigit()
                    .hidden()
                    .overlay(alignment: .leading) {
                        OptionsTickingNumber(value: armed ? Double(value) : 0)
                            .fixedSize()
                            .animation(.easeOut(duration: 0.9).delay(0.25), value: armed)
                            .animation(.easeOut(duration: 0.3), value: value)
                    }
            }
        }
        .task(id: armed) {
            guard armed, !counted else { return }
            try? await Task.sleep(for: .milliseconds(1250))
            counted = true
        }
    }
}

/// Cyfry tykające w miejscu — SwiftUI interpoluje `value`, tekst pokazuje
/// zaokrągloną wartość z każdej klatki.
private struct OptionsTickingNumber: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(verbatim: String(Int(value.rounded())))
            .monospacedDigit()
    }
}

/// Strona dania: pierwsze dziecko (zdjęcie) od góry do początku drugiego
/// (treść przypięta do dołu) + `overlap`. W makiecie to 440 pt zdjęcia przy
/// treści zaczynającej się na 427. Zdjęcie nie schodzi poniżej 45 % i nie
/// rośnie ponad 72 % wysokości — przy bardzo krótkiej treści zostaje oddech
/// zamiast rozciągniętego kadru.
private struct OptionsStoryLayout: Layout {
    var overlap: CGFloat = 13

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let content = subviews[1]
        let contentHeight = content.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
        content.place(
            at: CGPoint(x: bounds.minX, y: bounds.maxY - contentHeight),
            proposal: ProposedViewSize(width: bounds.width, height: contentHeight)
        )
        let photoHeight = min(
            bounds.height * 0.72,
            max(bounds.height * 0.45, bounds.height - contentHeight + overlap)
        )
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            proposal: ProposedViewSize(width: bounds.width, height: photoHeight)
        )
    }
}

/// `Kes size={n}` z makiety: ramka `n`, ale sam dysk to 68 % ramki (promień
/// 34 w polu 100). `SCMarkShape` wypełnia ramkę w całości, więc bez tej
/// poprawki znak wychodzi o połowę większy niż w projekcie.
private struct OptionsKesMark: View {
    let size: CGFloat
    let color: Color

    var body: some View {
        SCMarkShape()
            .fill(color)
            .frame(width: size * 0.68, height: size * 0.68)
            .frame(width: size, height: size)
    }
}

/// `EBrand` × 1,7 ze strony końcowej: dysk 95 w tincie terakoty, wokół —
/// z odstępem — kreskowany pierścień 143 (obrys 2,55), w środku znak 28 × 1,7.
private struct OptionsBrandBadge: View {
    @Environment(\.colorScheme) private var scheme

    private static let scale: CGFloat = 1.7

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    AssistantLook.terraFill(scheme).opacity(0.28),
                    style: StrokeStyle(lineWidth: 1.5 * Self.scale, dash: [3 * Self.scale, 3 * Self.scale])
                )
                .frame(width: 84 * Self.scale, height: 84 * Self.scale)
            Circle()
                .fill(AssistantLook.terraTint(scheme))
                .frame(width: 56 * Self.scale, height: 56 * Self.scale)
            OptionsKesMark(size: 28 * Self.scale, color: AssistantLook.terraFill(scheme))
        }
        .frame(width: 84 * Self.scale, height: 84 * Self.scale)
        .accessibilityHidden(true)
    }
}

/// Poziome przewracanie stron arkusza wyboru — gest UIKit-owy.
///
/// Rusza WYŁĄCZNIE przy ruchu wyraźnie poziomym (decyzja zapada w pierwszej
/// klatce, z prędkości). Przy pionowym nie zaczyna się wcale, więc
/// systemowe przeciągnięcie arkusza w dół nie ma z kim konkurować —
/// `DragGesture` ze SwiftUI tego nie potrafi: zaczyna się przy każdym ruchu
/// i dopiero potem mógłby „oddać” palec, a wtedy arkusz już go nie dostaje.
/// Równolegle z innymi gestami, żeby przyciski i segmenty dalej łapały dotyk.
private struct OptionsPagePan: UIGestureRecognizerRepresentable {
    /// Bieżące przesunięcie palca w poziomie.
    let onChanged: (CGFloat) -> Void
    /// Koniec: przesunięcie i prędkość pozioma (pt/s).
    let onEnded: (_ dx: CGFloat, _ velocity: CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let dx = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            onChanged(dx)
        case .ended:
            onEnded(dx, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            onEnded(0, 0)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.2
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
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
                    .frame(minHeight: 44)
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
