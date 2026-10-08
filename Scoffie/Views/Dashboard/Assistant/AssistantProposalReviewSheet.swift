import SwiftUI

// Przegląd propozycji dnia albo tygodnia (6.10.2026, „jak od Apple”: prościej,
// czytelniej, mniej ceremonii) — JEDNA przewijana lista zamiast stron „stories”
// z kreskami, filtrem pory i dnia, wachlarzem dań i osobnym półarkuszem
// „Co się zmieni”.
//
// Od góry: nagłówek arkusza (`EditorialSheetHeader`), w domu z kilku osób
// jeden filtr „Wszyscy · Ty · Ania” (`ProposalPersonFilter`), potem dni jako
// sekcje (propozycja dnia = jedna sekcja bez nagłówka). Wiersz mówi wszystko
// o daniu: pora z ikoną w jej kolorze, miniatura, nazwa, kcal, „dla kogo”,
// gdy nie cały dom, i ZMIANĘ wobec planu — „Nowe”, „Zamiast: …” albo
// usunięcie z powodem od modelu. Zamiana jednego dania to „…” w wierszu
// (i to samo pod przytrzymaniem) — małe okno akcji, nie kolejny arkusz.
// Na dole JEDEN przycisk wg stanu propozycji, nad nim zdanie o stanie.
//
// Bez kaskad i rolowania przy wejściu; rusza się tylko to, co zmienia stan
// (zapis: kręciołek → „Jest w planie”, ptaszki na miniaturach, haptyka).
//
// Stuknięcie w danie NIE otwiera szczegółów przepisu: `RecipeDetailView`
// zakłada bycie arkuszem (chowa pasek nawigacji, ma własny krzyżyk, sam
// otwiera „Dodaj do planu” jako kolejny arkusz), a propozycja niesie tylko
// `recipeId` — szczegóły jako push w arkuszu to osobna praca.

// MARK: - Dane listy

/// Propozycja dnia albo tygodnia ułożona do przeglądu: dni → wiersze.
struct ProposalReview {
    enum Kind { case day, week }

    /// Co wiersz zmienia w planie.
    enum Change: Equatable {
        /// Danie, które już stoi w planie (`KEPT`).
        case kept
        /// Nowe danie w porze, z której nic nie znika.
        case added
        /// Nowe danie w porze, z której znikają te dania.
        case replaces([String])
        /// Danie znika z planu; jedno słowo powodu od modelu („powtórka”).
        case removed(reason: String?)
    }

    struct Row: Identifiable {
        let id: String
        let slot: MealSlot?
        let mealLabel: String
        let title: String
        let imageURL: URL?
        let kcal: Int
        /// Puste = cały dom.
        let participantIds: [String]
        var change: Change
        /// Zdanie „Zamień to danie” — tylko dla dań propozycji, nie usunięć.
        let swapPrompt: String?
        /// Wiersze usunięć, które ten wiersz mówi jako „Zamiast: …”. Gdy filtr
        /// osoby schowa ten wiersz, wracają na ekran (`filtered`).
        var absorbed: [Row] = []

        var isRemoval: Bool {
            if case .removed = change { return true }
            return false
        }

        /// Nowe danie propozycji (z zamianą albo bez).
        var isNewDish: Bool {
            switch change {
            case .added, .replaces: return true
            case .kept, .removed: return false
            }
        }
    }

    struct Section: Identifiable {
        let id: String
        /// „Wtorek, 1 września”; `nil` = propozycja dnia (sekcja bez nagłówka).
        let label: String?
        let rows: [Row]
    }

    let kind: Kind
    /// Dzień („Wtorek, 1 września”) albo zakres tygodnia.
    let title: String
    let sections: [Section]

    /// „Nowe” niesie informację tylko wtedy, gdy propozycja coś w planie
    /// zostawia albo z niego zdejmuje. Gdy wszystko jest nowe, dwadzieścia
    /// jeden pigułek „Nowe” nic nie mówi — wtedy ich nie ma.
    var marksNew: Bool {
        sections.contains { section in
            section.rows.contains { row in
                switch row.change {
                case .kept, .replaces, .removed: return true
                case .added: return false
                }
            }
        }
    }

    /// Dania propozycji (bez usunięć).
    var dishCount: Int {
        sections.reduce(0) { sum, section in sum + section.rows.filter { !$0.isRemoval }.count }
    }

    /// Id wiersza dania — to samo w karcie (dotknięte danie) i w liście.
    static func rowID(dayKey: String, index: Int, slot: PlanWeekCardSlotDTO) -> String {
        "\(dayKey)-\(index)-\(slot.id)"
    }
}

extension ProposalReview {
    /// Propozycja tygodnia: dzień po dniu. Usunięcia z dni, których
    /// propozycja nie wypisuje (dzień bez nowych dań), dostają własną sekcję
    /// na swoim miejscu w tygodniu — wcześniej przepadały bez śladu.
    /// `image` = zdjęcie usuwanego dania z katalogu (po `recipeId`).
    init(week card: PlanWeekCardDTO, image: (String?) -> URL?) {
        var entries: [(section: Section, order: Int)] = []
        var used = Set<Int>()

        for (position, day) in card.days.enumerated() {
            let removals = card.removed.enumerated().filter { entry in
                !used.contains(entry.offset) && Self.sameDay(entry.element, day: day)
            }
            for entry in removals { used.insert(entry.offset) }
            let rows = Self.rows(
                dayKey: day.id,
                slots: day.slots,
                removals: removals.map { $0.element },
                swapDay: day.dayLabel,
                image: image
            )
            let section = Section(id: day.id, label: Self.dayLabel(day.date) ?? day.dayLabel, rows: rows)
            entries.append((section, Self.weekdayIndex(day.dayOfWeek) ?? position))
        }

        // Reszta usunięć — po dniu, w kolejności z serwera.
        var restOrder: [String] = []
        var restByDay: [String: [PlanWeekCardRemovalDTO]] = [:]
        for (offset, removal) in card.removed.enumerated() where !used.contains(offset) {
            let key = removal.dayOfWeek?.uppercased() ?? removal.dayLabel.lowercased()
            if restByDay[key] == nil { restOrder.append(key) }
            restByDay[key, default: []].append(removal)
        }
        for key in restOrder {
            let removals = restByDay[key] ?? []
            guard let first = removals.first else { continue }
            let index = Self.weekdayIndex(first.dayOfWeek)
            let label = index.flatMap { Self.date(weekStart: card.weekStart, offset: $0) }.map { Self.dayLabel($0) }
            let rows = Self.rows(
                dayKey: "removed-\(key)",
                slots: [],
                removals: removals,
                swapDay: first.dayLabel,
                image: image
            )
            entries.append((Section(id: "removed-\(key)", label: label ?? first.dayLabel, rows: rows), index ?? Int.max))
        }

        let ordered = entries.enumerated().sorted { left, right in
            left.element.order != right.element.order
                ? left.element.order < right.element.order
                : left.offset < right.offset
        }
        self.init(
            kind: .week,
            title: Self.capitalizedFirst(card.eyebrowDetail) ?? card.title,
            sections: ordered.map { $0.element.section }
        )
    }

    /// Propozycja dnia: jedna sekcja bez nagłówka — dzień stoi w tytule.
    init(day card: PlanDayCardDTO, image: (String?) -> URL?) {
        let rows = Self.rows(
            dayKey: card.date,
            slots: card.slots,
            removals: card.removed,
            swapDay: nil,
            image: image
        )
        self.init(
            kind: .day,
            title: Self.dayLabel(card.date) ?? Self.capitalizedFirst(card.eyebrowDetail) ?? card.title,
            sections: [Section(id: card.date, label: nil, rows: rows)]
        )
    }

    /// Wiersze jednego dnia: dania propozycji i usunięcia, po porze dnia.
    /// Usunięcie w porze, do której wchodzi nowe danie, to ZAMIANA — mówi ją
    /// wiersz nowego dania („Zamiast: …”), a nie osobny wiersz. Przy kilku
    /// nowych daniach w jednej porze („Każdy je inaczej”) usunięcia idą do
    /// nich PO KOLEI, jedno na danie, a nadmiar bierze ostatnie — dawniej
    /// każde nowe danie pory mówiło to samo „Zamiast: X” (6.10.2026).
    private static func rows(
        dayKey: String,
        slots: [PlanWeekCardSlotDTO],
        removals: [PlanWeekCardRemovalDTO],
        swapDay: String?,
        image: (String?) -> URL?
    ) -> [Row] {
        var result: [(row: Row, offset: Int)] = []
        var paired = Set<Int>()

        // Każde usunięcie jako wiersz — także to, które przejmie nowe danie
        // („Zamiast: …”): leży wtedy w jego `absorbed`.
        let removalRows: [Row] = removals.enumerated().map { index, removal in
            let reason = removal.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Row(
                id: "\(dayKey)-removed-\(index)-\(removal.id)",
                slot: removal.mealType.flatMap { MealSlot(backendMealType: $0) },
                mealLabel: removal.mealLabel,
                title: removal.title,
                imageURL: image(removal.recipeId),
                kcal: 0,
                participantIds: [],
                change: .removed(reason: (reason?.isEmpty ?? true) ? nil : reason),
                swapPrompt: nil
            )
        }

        // Indeks nowego dania → usunięcia, które zastępuje.
        let newIndexes = slots.indices.filter { slots[$0].isNew }
        var replacedBy: [Int: [Int]] = [:]
        for (offset, removal) in removals.enumerated() {
            let candidates = newIndexes.filter { sameMeal(removal, slot: slots[$0]) }
            guard let last = candidates.last else { continue }
            let target = candidates.first { replacedBy[$0] == nil } ?? last
            replacedBy[target, default: []].append(offset)
            paired.insert(offset)
        }

        for (index, slot) in slots.enumerated() {
            let change: Change
            var absorbed: [Row] = []
            if slot.isNew {
                let replaced = replacedBy[index] ?? []
                absorbed = replaced.map { removalRows[$0] }
                change = replaced.isEmpty ? .added : .replaces(replaced.map { removals[$0].title })
            } else {
                change = .kept
            }
            let row = Row(
                id: rowID(dayKey: dayKey, index: index, slot: slot),
                slot: MealSlot(backendMealType: slot.mealType),
                mealLabel: slot.mealLabel,
                title: slot.title,
                imageURL: slot.imageUrl.flatMap { URL(string: $0) },
                kcal: slot.kcalPerServing,
                participantIds: slot.participantIds,
                change: change,
                swapPrompt: swapPrompt(slot, day: swapDay),
                absorbed: absorbed
            )
            result.append((row, index))
        }

        for (index, row) in removalRows.enumerated() where !paired.contains(index) {
            result.append((row, slots.count + index))
        }

        return byDayOrder(result.map { $0.row })
    }

    /// Porządek dnia: po porze, gdy znana; nieznana za znanymi; w porze —
    /// kolejność wejściowa.
    private static func byDayOrder(_ rows: [Row]) -> [Row] {
        rows.enumerated().sorted { left, right in
            switch (left.element.slot, right.element.slot) {
            case let (a?, b?) where a != b: return a < b
            case (.some, .none): return true
            case (.none, .some): return false
            default: return left.offset < right.offset
            }
        }
        .map { $0.element }
    }

    /// Wiersze dnia po filtrze osoby. Zamiana nie znika razem z wierszem, do
    /// którego ją przypięto (Codex 6.10.2026: „Zamiast: pizza” przy omlecie
    /// Rafała chowało przed Anią, że pizza też jej zniknie): usunięcia
    /// schowanego dania przechodzą na pierwsze WIDOCZNE nowe danie tej pory,
    /// a gdy takiego nie ma — stają jako osobne wiersze „Usunięte”. Zapis
    /// i tak zdejmuje je z planu całego domu.
    static func filtered(_ rows: [Row], keeping isShown: (Row) -> Bool) -> [Row] {
        var orphans: [String: [Row]] = [:]
        for row in rows where !isShown(row) && !row.absorbed.isEmpty {
            orphans[slotKey(row), default: []].append(contentsOf: row.absorbed)
        }

        var result: [Row] = []
        for row in rows where isShown(row) {
            let key = slotKey(row)
            guard row.isNewDish, let moved = orphans[key], !moved.isEmpty else {
                result.append(row)
                continue
            }
            var merged = row
            var titles: [String] = []
            if case .replaces(let existing) = row.change { titles = existing }
            merged.change = .replaces(titles + moved.map { $0.title })
            merged.absorbed = row.absorbed + moved
            orphans[key] = nil
            result.append(merged)
        }

        let leftovers = orphans.keys.sorted().flatMap { orphans[$0] ?? [] }
        return leftovers.isEmpty ? result : byDayOrder(result + leftovers)
    }

    /// Pora wiersza do łączenia zamian: znana pora albo — gdy serwer jej nie
    /// podał — nazwa posiłku.
    private static func slotKey(_ row: Row) -> String {
        row.slot?.rawValue ?? row.mealLabel.lowercased()
    }

    /// TO SAMO zdanie, które wysyłało „Zamień to danie” na stronie dania
    /// w dawnym przeglądzie: serwer odpowiada kartą dań do wyboru, a wybór
    /// wraca jako ta sama propozycja z nowym daniem.
    private static func swapPrompt(_ slot: PlanWeekCardSlotDTO, day: String?) -> String {
        let when = day.map { "\(slot.mealLabel.lowercased()), \($0.lowercased())" } ?? slot.mealLabel.lowercased()
        return "Zamień w tej propozycji \(when): \(slot.title). Pokaż 3 inne dania na tę porę do wyboru."
    }

    private static func sameMeal(_ removal: PlanWeekCardRemovalDTO, slot: PlanWeekCardSlotDTO) -> Bool {
        if let type = removal.mealType {
            return type.uppercased() == slot.mealType.uppercased()
        }
        return removal.mealLabel.compare(slot.mealLabel, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private static func sameDay(_ removal: PlanWeekCardRemovalDTO, day: PlanWeekCardDayDTO) -> Bool {
        if let code = removal.dayOfWeek {
            return code.uppercased() == day.dayOfWeek.uppercased()
        }
        return removal.dayLabel.compare(day.dayLabel, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private static let weekdayCodes = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    private static func weekdayIndex(_ code: String?) -> Int? {
        guard let code else { return nil }
        return weekdayCodes.firstIndex(of: code.uppercased())
    }

    private static func capitalizedFirst(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return String(text.prefix(1)).uppercased() + String(text.dropFirst())
    }

    // MARK: Dzień słowami

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

    /// Data `offset` dni po poniedziałku tygodnia propozycji.
    private static func date(weekStart: String, offset: Int) -> Date? {
        guard let monday = isoDay.date(from: String(weekStart.prefix(10))) else { return nil }
        return Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: monday)
    }

    /// „Dziś, 23 września”, „Jutro, 24 września”, „Piątek, 26 września” —
    /// względem DZISIAJ na telefonie (serwer stoi w UTC i „dziś” wie tylko
    /// telefon); `nil`, gdy daty nie dało się odczytać.
    static func dayLabel(_ iso: String, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let date = isoDay.date(from: String(iso.prefix(10))) else { return nil }
        return dayLabel(date, now: now, calendar: calendar)
    }

    static func dayLabel(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
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

/// Otwarty przegląd propozycji. `focus` = id wiersza dotkniętego w karcie
/// (lista zaczyna od niego); `nil` = od góry.
struct ProposalReviewFocus: Identifiable {
    let focus: String?
    var id: String { focus ?? "" }
}

// MARK: - Arkusz

struct AssistantProposalReviewSheet: View {
    let review: ProposalReview
    /// Stan propozycji z serwera — mówi, co jest w stopce.
    let status: AssistantCardStatus
    /// „Zapisz wtorek” — zapis całości; `nil` = tej propozycji nie da się już
    /// zapisać (zapisana, nieaktualna bez zgody serwera…).
    let applyTitle: String?
    /// Zapis w toku — arkusz zostaje otwarty i sam przechodzi w „Jest w planie”.
    let isBusy: Bool
    /// Domownicy i „ja” — jawnie, nie przez środowisko.
    let members: [HouseholdMemberSnapshot]
    let me: String?
    /// Id wiersza, od którego lista zaczyna (dotknięte danie w karcie).
    var focus: String? = nil
    /// „Zamień to danie” — wysyła gotowe zdanie. `nil` = zamiany nie ma
    /// (propozycja już nie czeka).
    var onSwap: ((String) -> Void)? = nil
    let onApply: () -> Void
    /// „Otwórz plan” po zapisie.
    var onOpenPlan: (() -> Void)? = nil
    /// „Zaproponuj inne dania” pod listą; `nil` = odnośnika nie ma.
    var onRegenerate: (() -> Void)? = nil
    /// „Napisz, co zmienić” — gdy propozycji nie da się już zapisać.
    let onCompose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// `nil` = wszyscy.
    @State private var person: String?

    private static let thumb: CGFloat = 44

    private var multiPerson: Bool { members.count > 1 }

    var body: some View {
        VStack(spacing: 0) {
            EditorialSheetHeader(
                eyebrow: review.kind == .week ? "Propozycja tygodnia" : "Propozycja dnia",
                title: review.title,
                icon: review.kind == .week ? "calendar" : "fork.knife",
                accent: status.tint(scheme),
                onClose: { dismiss() }
            )
            .padding(.horizontal, 20)
            .padding(.top, 18)

            if multiPerson {
                ProposalPersonFilter(members: members, me: me, selection: $person)
                    .padding(.top, 14)
            }

            ScrollViewReader { proxy in
                list
                    .onAppear {
                        guard let focus else { return }
                        proxy.scrollTo(focus, anchor: .center)
                    }
            }
            .padding(.top, 6)
        }
        .background(SCPageBackground(scheme: scheme).ignoresSafeArea())
        // Zapis się udał — ta sama chwila, w której na miniaturach staje
        // szałwiowy ptaszek.
        .sensoryFeedback(trigger: status) { old, new in
            old != .applied && new == .applied ? .success : nil
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(40)
        .presentationBackground(Color.scPageBase(scheme))
    }

    // MARK: Lista

    private var list: some View {
        let sections = visibleSections
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if sections.isEmpty {
                    Text("Ta propozycja nie zmienia nic dla tej osoby.")
                        .font(.sc(size: 14))
                        .foregroundStyle(AssistantLook.muted(scheme))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        if let label = section.label {
                            EditorialSheetSectionLabel(title: label)
                        }
                        sectionCard(section.rows)
                    }
                }

                if status == .pending, !isBusy, let onRegenerate {
                    ProposalRegenerateLink(
                        title: review.dishCount == 1 ? "Zaproponuj inne danie" : "Zaproponuj inne dania",
                        action: onRegenerate
                    )
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .animation(motion(.smooth(duration: 0.3)), value: isBusy)
            .animation(motion(.smooth(duration: 0.3)), value: status)
        }
        .scrollIndicators(.hidden)
        // Treść gaśnie pod przypiętym nagłówkiem zamiast kreski.
        .scScrollEdgeFade()
        // Stopka natywnie (`safeAreaBar`): lista przejeżdża pod szklanym
        // przyciskiem i kończy się nad nim.
        .scSheetFooter(horizontalPadding: 16) { footer }
    }

    /// Wiersze osoby z filtra (albo wszystkie). Dania całego domu są każdej
    /// osoby; usunięcia dotyczą planu, więc zostają zawsze.
    private var visibleSections: [ProposalReview.Section] {
        guard let person else { return review.sections }
        return review.sections.compactMap { section in
            let rows = ProposalReview.filtered(section.rows) { row in
                row.isRemoval
                    || ProposalAudience.isShared(row.participantIds, members: members)
                    || ProposalAudience.eats(row.participantIds, person: person)
            }
            return rows.isEmpty ? nil : ProposalReview.Section(id: section.id, label: section.label, rows: rows)
        }
    }

    /// Dzień = jedna karta listy Ustawień (`EditorialSettingsCardGroup`,
    /// 7.10.2026 — dawniej własna karta o promieniu 20 z kreską w kolorze
    /// obwódki), wiersze rozdzielone kreską listy (`scRule`) od miniatury
    /// w prawo, jak listy iOS.
    private func sectionCard(_ rows: [ProposalReview.Row]) -> some View {
        EditorialSettingsCardGroup {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.scRule(scheme))
                            .frame(height: 1)
                            .padding(.leading, 14 + Self.thumb + 12)
                    }
                    rowView(row)
                        .id(row.id)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Wiersz

    private func rowView(_ row: ProposalReview.Row) -> some View {
        let swap: String? = onSwap == nil ? nil : row.swapPrompt
        return HStack(alignment: .center, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                AssistantThumbnail(url: row.imageURL, size: Self.thumb, dimmed: row.isRemoval)
                    .saturation(row.isRemoval ? 0 : 1)
                    .overlay(alignment: .bottomTrailing) { savedBadge(row) }

                VStack(alignment: .leading, spacing: 3) {
                    mealLine(row)
                    Text(row.title)
                        .font(.sc(size: 15, weight: row.isRemoval ? .regular : .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(row.isRemoval ? AssistantLook.faint(scheme) : AssistantLook.ink(scheme))
                        .strikethrough(row.isRemoval, color: AssistantLook.faint(scheme))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    changeLine(row)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if row.kcal > 0 {
                    Text("\(row.kcal) kcal")
                        .font(.sc(size: 12.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(AssistantLook.faint(scheme))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, swap == nil ? 14 : 4)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .contextMenu {
                if let swap {
                    swapButton(swap)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(row))

            if let swap {
                Menu {
                    swapButton(swap)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.sc(size: 15, weight: .semibold))
                        .foregroundStyle(AssistantLook.muted(scheme))
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .padding(.trailing, 6)
                .accessibilityLabel("Więcej: \(row.title)")
            }
        }
    }

    private func swapButton(_ prompt: String) -> some View {
        Button {
            // Po zamknięciu menu — arkusz schodzi dopiero, gdy menu już
            // zniknęło (zamykanie pod gasnącym menu szarpało).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onSwap?(prompt)
            }
        } label: {
            Label("Zamień to danie", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    /// Ikona pory w jej kolorze · PORA · „dla kogo” (tylko gdy nie cały dom).
    private func mealLine(_ row: ProposalReview.Row) -> some View {
        HStack(spacing: 5) {
            if let slot = row.slot {
                Image(systemName: slot.icon)
                    .font(.sc(size: 10, weight: .bold))
                    .foregroundStyle(slot.cozyAccent)
            }
            Text(row.slot?.title ?? row.mealLabel)
                .font(.sc(size: 11, weight: .semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(AssistantLook.faint(scheme))
                .lineLimit(1)
            if showsAudience(row) {
                ProposalAudiencePill(
                    participantIds: row.participantIds,
                    members: members,
                    me: me,
                    size: 16,
                    filled: false
                )
                .padding(.leading, 3)
            }
        }
    }

    private func showsAudience(_ row: ProposalReview.Row) -> Bool {
        multiPerson && !row.isRemoval && !ProposalAudience.isShared(row.participantIds, members: members)
    }

    /// Zmiana wobec planu w samym wierszu.
    @ViewBuilder
    private func changeLine(_ row: ProposalReview.Row) -> some View {
        switch row.change {
        case .kept:
            EmptyView()
        case .added:
            if review.marksNew {
                changeTag("Nowe", icon: "plus", color: AssistantLook.sage(scheme))
                    .padding(.top, 2)
            }
        case .replaces(let titles):
            HStack(spacing: 4) {
                Text("Zamiast:")
                    .fixedSize()
                Text(titles.joined(separator: ", "))
                    .strikethrough(true, color: AssistantLook.faint(scheme))
                    .lineLimit(1)
            }
            .font(.sc(size: 12.5))
            .foregroundStyle(AssistantLook.faint(scheme))
        case .removed(let reason):
            changeTag(
                reason.map { "Usunięte · \($0)" } ?? "Usunięte",
                icon: "minus",
                color: AssistantLook.muted(scheme)
            )
            .padding(.top, 2)
        }
    }

    private func changeTag(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.sc(size: 8.5, weight: .bold))
            Text(title)
                .font(.sc(size: 11.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Capsule(style: .continuous).fill(color.opacity(scheme == .dark ? 0.16 : 0.1)))
        .fixedSize()
    }

    /// Po zapisie: szałwiowy ptaszek na miniaturze — wyskakuje w chwili
    /// zapisu, a przegląd zapisanej propozycji ma go od razu.
    private func savedBadge(_ row: ProposalReview.Row) -> some View {
        let saved = status == .applied && !row.isRemoval
        return ZStack {
            Circle().fill(AssistantLook.sage(scheme))
            Image(systemName: "checkmark")
                .font(.sc(size: 9, weight: .heavy))
                .foregroundStyle(Color.white)
        }
        .frame(width: 19, height: 19)
        .overlay(Circle().strokeBorder(Color.scPageBase(scheme), lineWidth: 2).padding(-2))
        .offset(x: 5, y: 5)
        .scaleEffect(saved ? 1 : 0.2)
        .opacity(saved ? 1 : 0)
        .animation(motion(.spring(response: 0.4, dampingFraction: 0.55)), value: saved)
        .accessibilityHidden(true)
    }

    private func spoken(_ row: ProposalReview.Row) -> String {
        var parts = [row.slot?.title ?? row.mealLabel, row.title]
        if row.kcal > 0 { parts.append("\(row.kcal) kilokalorii") }
        if showsAudience(row), let who = ProposalAudience.label(row.participantIds, members: members, me: me) {
            parts.append("dla: \(who)")
        }
        switch row.change {
        case .kept:
            break
        case .added:
            if review.marksNew { parts.append("nowe") }
        case .replaces(let titles):
            parts.append("zamiast: \(titles.joined(separator: ", "))")
        case .removed(let reason):
            parts.append(reason.map { "zniknie z planu, \($0)" } ?? "zniknie z planu")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Stopka

    /// Zdanie o stanie i JEDEN przycisk: zapis całości (w szałwii), po
    /// zapisie „Otwórz plan”, a gdy propozycji nie da się już zapisać —
    /// „Napisz, co zmienić”. Zapis NIE zamyka arkusza: stopka przechodzi
    /// przez „Wstawiam do planu…” w „Jest w planie”.
    private var footer: some View {
        let copy = ProposalEndCopy(status: status, isBusy: isBusy)
        return VStack(spacing: 12) {
            VStack(spacing: 3) {
                Text(copy.title)
                    .font(.sc(size: 15, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(AssistantLook.ink(scheme))
                    .contentTransition(.numericText())
                Text(copy.body)
                    .font(.sc(size: 13))
                    .foregroundStyle(AssistantLook.muted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.numericText())
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .animation(motion(SCMotion.textRoll), value: copy.title)

            footerButton(copy)
                .frame(maxWidth: .infinity)
                .animation(motion(.smooth(duration: 0.35)), value: status)
                .animation(motion(.smooth(duration: 0.3)), value: isBusy)
        }
    }

    /// Zapis i „Otwórz plan” = wspólny przycisk Asystenta w szałwii
    /// (`AssistantPrimaryButton(tint:)`, jak zapis w karcie propozycji) —
    /// prywatna kopia `ProposalAcceptButton` odpadła 7.10.2026.
    @ViewBuilder
    private func footerButton(_ copy: ProposalEndCopy) -> some View {
        if let applyTitle {
            AssistantPrimaryButton(
                action: AssistantCardAction(title: isBusy ? "Zapisuję…" : applyTitle, icon: "checkmark", action: onApply),
                isBusy: isBusy,
                tint: AssistantLook.sage(scheme)
            )
            .transition(.opacity)
        } else if status == .applied, let onOpenPlan {
            AssistantPrimaryButton(
                action: AssistantCardAction(title: "Otwórz plan", icon: "arrow.right", action: onOpenPlan),
                tint: AssistantLook.sage(scheme)
            )
            .transition(.opacity)
        } else if !isBusy {
            AssistantGhostButton(
                action: AssistantCardAction(title: copy.composeTitle, icon: "square.and.pencil") {
                    onCompose()
                }
            )
            .transition(.opacity)
        }
    }

    /// Przy „Ogranicz ruch” zostają same krótkie przenikania.
    private func motion(_ animation: Animation) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : animation
    }
}

// MARK: - Stan, zgoda, nowy zestaw

/// Słowa stopki przeglądu dla każdego stanu propozycji.
private struct ProposalEndCopy {
    let status: AssistantCardStatus
    let isBusy: Bool

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
}

/// Cichy odnośnik pod listą: ikona odświeżenia + tytuł w terakocie, bez tła —
/// opcja, nie druga decyzja obok zapisu.
private struct ProposalRegenerateLink: View {
    let title: String
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.sc(size: 13, weight: .semibold))
                Text(title)
                    .font(.sc(size: 14.5, weight: .semibold))
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

#if DEBUG
/// `SCOFFIE_DEBUG_OPTIONS=propozycja` — przegląd propozycji dnia na
/// prawdziwych zdjęciach z katalogu, w domu dwóch osób: zamiana („Zamiast:
/// …”), nowe dania dla różnych osób, usunięcie z powodem i danie, które
/// zostaje. Po chwili „zapisuje” (kręciołek) i kończy na „Jest w planie” —
/// żeby zmianę stanu dało się nagrać.
struct ProposalReviewDebugScreen: View {
    @State private var status: AssistantCardStatus = .pending
    @State private var busy = false

    private static let json = #"""
    {"kind": "PLAN_DAY", "v": 1, "proposalId": "66666666-6666-4666-8666-666666666666", "weekStart": "2026-09-21", "date": "2026-09-27", "eyebrow": "Propozycja dnia", "eyebrowDetail": "niedziela, 27 września", "title": "Cały dzień pod Twój cel", "subtitle": null, "slots": [
      {"mealType": "BREAKFAST", "mealLabel": "Śniadanie", "recipeId": "9e845247-f630-4dcc-9bab-3656828cac29", "title": "Owsianka z bananem i borówką", "kcalPerServing": 447, "prepTimeMinutes": 12, "imageUrl": "https://img.scoffie.app/recipe-images/9e845247-f630-4dcc-9bab-3656828cac29.webp", "participantIds": [], "change": "NEW"},
      {"mealType": "LUNCH", "mealLabel": "Obiad", "recipeId": "1a66ef3b-f1dc-4427-b6b3-3ca5d6986e80", "title": "Omlet ze szpinakiem i fetą", "kcalPerServing": 620, "prepTimeMinutes": 15, "imageUrl": "https://img.scoffie.app/recipe-images/1a66ef3b-f1dc-4427-b6b3-3ca5d6986e80.webp", "participantIds": ["u-me"], "change": "NEW"},
      {"mealType": "LUNCH", "mealLabel": "Obiad", "recipeId": "d0d09af3-1821-47be-be95-63a208fc47bd", "title": "Jogurt naturalny z musli, truskawkami i borówkami", "kcalPerServing": 316, "prepTimeMinutes": 6, "imageUrl": "https://img.scoffie.app/recipe-images/d0d09af3-1821-47be-be95-63a208fc47bd.webp", "participantIds": ["u-ania"], "change": "NEW"},
      {"mealType": "DINNER", "mealLabel": "Kolacja", "recipeId": "386586d2-b4f8-41f0-9641-cce2b7c20dd7", "title": "Skyr z granolą i malinami", "kcalPerServing": 393, "prepTimeMinutes": 5, "imageUrl": "https://img.scoffie.app/recipe-images/386586d2-b4f8-41f0-9641-cce2b7c20dd7.webp", "participantIds": [], "change": "KEPT"}
    ], "removed": [
      {"dayLabel": "Niedziela", "mealLabel": "Obiad", "title": "Pizza mrożona", "dayOfWeek": "SUN", "mealType": "LUNCH", "recipeId": null, "reason": "ponad cel"},
      {"dayLabel": "Niedziela", "mealLabel": "Podwieczorek", "title": "Pudding ryżowy z musem malinowym", "dayOfWeek": "SUN", "mealType": "AFTERNOON_SNACK", "recipeId": null, "reason": "powtórka"}
    ], "summary": {"meals": 4, "kcalTotal": 1776, "targetKcalPerDay": 2100, "goalNote": null}, "actions": [{"type": "APPLY", "proposalId": "66666666-6666-4666-8666-666666666666", "label": "Zapisz niedzielę", "style": "PRIMARY"}], "state": {"status": "PENDING", "canApply": true, "canUndo": false, "until": "2026-09-28T10:00:00.000Z"}}
    """#

    private static var card: PlanDayCardDTO {
        guard case .planDay(let card) = AssistantPreviewFixtures.card(json) else { fatalError("PLAN_DAY") }
        return card
    }

    private static let members: [HouseholdMemberSnapshot] = [
        HouseholdMemberSnapshot(id: "u-me", displayName: "Rafał", email: nil, avatarUrl: nil, avatarColor: 0, role: "OWNER"),
        HouseholdMemberSnapshot(id: "u-ania", displayName: "Ania", email: nil, avatarUrl: nil, avatarColor: 3, role: "MEMBER"),
    ]

    var body: some View {
        SCPageBackground(scheme: .light).ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                AssistantProposalReviewSheet(
                    review: ProposalReview(day: Self.card, image: { _ in nil }),
                    status: status,
                    applyTitle: status == .pending ? "Zapisz niedzielę" : nil,
                    isBusy: busy,
                    members: Self.members,
                    me: "u-me",
                    onSwap: status == .pending ? { _ in } : nil,
                    onApply: {},
                    onOpenPlan: {},
                    onRegenerate: {},
                    onCompose: {}
                )
                .interactiveDismissDisabled()
            }
            .task {
                try? await Task.sleep(for: .seconds(4))
                busy = true
                try? await Task.sleep(for: .seconds(1.2))
                busy = false
                status = .applied
            }
    }
}
#endif
