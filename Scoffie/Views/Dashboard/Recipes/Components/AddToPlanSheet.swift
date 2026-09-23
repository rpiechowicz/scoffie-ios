import SwiftUI

/// Szczegół przepisu → „Dodaj do planu".
///
/// Drugie wejście do planu tygodnia, obok `PlanSlotPickerSheet`. Tamten arkusz
/// startuje od znanego `(dzień, slot)` i pyta o przepis; ten idzie odwrotnie —
/// przepis jest już wybrany, a użytkownik dokłada do niego dzień, posiłek,
/// audytorium i liczbę porcji. Rząd chipów i reguła zwijania „wszyscy" do
/// „Wspólne" są wspólne (`PlanAudienceChips`), więc oba wejścia wysyłają
/// identyczny payload.
///
/// Układ (runda 13, 23.09.2026 — „napisz od zera lepiej, podejdź inaczej”):
/// trzy pytania, każde w jednym miejscu, bez przewijania.
///
/// - **Kiedy** — przewijany pasek dni od dziś na cztery tygodnie naprzód.
///   Minionych dni w nim nie ma (nie było czego przekreślać), strzałek
///   tygodnia też nie — tydzień oddziela cienka kreska przed poniedziałkiem.
/// - **Posiłek** — lista pór jak w Ustawieniach: kafelek pory, nazwa, a po
///   prawej to, co już w niej stoi tego dnia, i kółko wyboru. Zajętość widać
///   PRZED stuknięciem w przycisk, a przycisk zmienia wtedy znaczenie na
///   „Zamień w planie”.
/// - **Dla kogo i ile** — audytorium i porcje w jednej karcie, bo jedno
///   wynika z drugiego (porcje nadążają za osobami).
///
/// Nad przyciskiem jedno rolujące zdanie „Środa, 24 września · Obiad”.
/// Na małym ekranie formularz jedzie w `ScrollView` (`ViewThatFits`).
///
/// Cztery decyzje, które łatwo cofnąć przez nieuwagę:
///
/// 1. **Arkusz trzyma własną datę.** Wybór dnia jest tutaj częścią formularza,
///    a nie nawigacją po aplikacji — `datesViewModel.selectDate(...)`
///    przestawiłby użytkownikowi dzień w Planie i Kalendarzu. Z
///    `DatesViewModel` bierzemy wyłącznie regułę `isEditable(_:)`.
/// 2. **Chipy audytorium przestawiają porcje tylko do pierwszego ruchu ręką.**
///    Patrz `didOverrideServings` i `applyAutoServings(for:animated:)`.
/// 3. **Przeszłego dnia nie da się wybrać.** Plan i Kalendarz pokazują minione
///    dni tylko do odczytu, więc wpis dodany stąd byłby nie do usunięcia.
/// 4. **Ten sam przepis w porze łączy osoby, a nie nadpisuje.** Pozycja planu
///    to para (pora, przepis): zapis obiadu Rafała dla Ani przepisywał go na
///    nią i Rafał zostawał bez obiadu. Teraz osoby się sumują, a pełny dom
///    zwija się do „Wspólne” (`PlanAudienceChips.merged`).
struct AddToPlanSheet: View {
    let recipe: Recipe
    /// Liczba porcji ustawiona stepperem w szczegółach — punkt startowy,
    /// który chipy audytorium mogą jeszcze przeliczyć.
    let initialServings: Int
    var onAdded: ((Date, MealSlot) -> Void)? = nil

    init(
        recipe: Recipe,
        initialServings: Int,
        didOverrideServings: Bool = false,
        onAdded: ((Date, MealSlot) -> Void)? = nil
    ) {
        self.recipe = recipe
        self.initialServings = initialServings
        self.onAdded = onAdded
        // Klamrujemy już przy wejściu: `initialServings` przychodzi z innego
        // ekranu i arkusz nie ma jak pokazać wartości spoza widełek steppera.
        _servings = State(initialValue: min(12, max(1, initialServings)))
        // Stepper w szczegółach i tutaj regulują to samo — świadome „gotuję
        // 4 porcje” ustawione ekran wcześniej nie może zniknąć przy otwarciu.
        _didOverrideServings = State(initialValue: didOverrideServings)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.toasts) private var toasts
    @Environment(\.mealCalendarStore) private var mealStore
    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.colorScheme) private var scheme

    /// Dzień wybrany w tym arkuszu. Startuje od dziś — „dodaj do planu”
    /// najczęściej znaczy „na dzisiaj albo na najbliższe dni”.
    @State private var selectedDate = Date()
    /// `nil` do pierwszego przemalowania — domyślny slot znamy dopiero wtedy,
    /// gdy wiadomo, które posiłki gospodarstwo w ogóle planuje.
    @State private var selectedSlot: MealSlot?
    /// Pusty zbiór znaczy „Wspólne" — danie je całe gospodarstwo.
    @State private var selectedParticipants: Set<String> = []
    @State private var servings: Int
    /// Czy użytkownik ruszył stepper ręcznie — tutaj albo jeszcze w szczegółach
    /// przepisu. Dopóki `false`, porcje nadążają za audytorium i nie lecą na
    /// serwer (patrz `save()`); potem są jego decyzją i chipy ich nie ruszają.
    @State private var didOverrideServings = false
    @State private var isSaving = false

    /// Ile dni naprzód pokazuje pasek. Cztery tygodnie to więcej, niż ktokolwiek
    /// planuje z poziomu przepisu, a pasek bez strzałek zostaje krótki.
    private static let horizonDays = 28

    private var calendar: Calendar { PlanWeek.calendar }

    // MARK: - Dane pochodne

    private var members: [HouseholdMemberSnapshot] { sessionStore.householdMembers }

    /// Liczba domowników albo `nil`, dopóki `SessionStore` nie wczyta listy.
    /// „Jeszcze nie wiem” i „dom jednoosobowy” dają tę samą jedynkę
    /// w `eaterCount`, a tylko w drugim przypadku to prawda.
    private var knownMemberCount: Int? {
        sessionStore.didLoadHouseholdMembers ? members.count : nil
    }

    /// Dni paska: od dziś, tylko te, które plan jeszcze przyjmie.
    private var stripDays: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (0..<Self.horizonDays)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .filter { isEditable($0) }
    }

    /// Dni paska, w których coś już stoi — kropka pod liczbą.
    private func plannedDays(in days: [Date]) -> Set<Date> {
        var result: Set<Date> = []
        for day in days {
            // Dzień pobrany raz, nie 6× — body przelicza się przy każdym stuknięciu.
            let plan = mealStore.plan(for: day)
            if MealSlot.allCases.contains(where: { !plan.meals(for: $0).isEmpty }) {
                result.insert(calendar.startOfDay(for: day))
            }
        }
        return result
    }

    /// Pory wyłączone w ustawieniach gospodarstwa, w których w tygodniu
    /// wybranego dnia mimo to coś stoi — `visibleSlots(planned:)` pokazuje je,
    /// żeby jedzenie nie znikało z widoku.
    private var plannedSlotsInSelectedWeek: [MealSlot] {
        let monday = PlanWeek.monday(of: selectedDate)
        var planned: Set<MealSlot> = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: monday) else { continue }
            for slot in MealSlot.allCases where !mealStore.meals(for: day, slot: slot).isEmpty {
                planned.insert(slot)
            }
        }
        return Array(planned).sortedByDay
    }

    /// Slot zaznaczany przy otwarciu: slot bazowy przepisu, o ile
    /// gospodarstwo ten posiłek planuje; inaczej pierwszy widoczny, w który
    /// przepis pasuje. Bazowy slot, a nie kategoria — „Przekąski i desery”
    /// zbiera trzy sloty naraz.
    private func defaultSlot(from visible: [MealSlot]) -> MealSlot? {
        if let base = recipe.primarySlot, visible.contains(base) { return base }
        return visible.first { recipe.fits($0) } ?? visible.first
    }

    private var participantsToSave: [String] {
        PlanAudienceChips.collapsed(selectedParticipants, members: members)
    }

    /// Ta sama reguła, którą Plan i Kalendarz stosują do minionych dni.
    private func isEditable(_ date: Date) -> Bool {
        datesViewModel.isEditable(date)
    }

    /// Czas i kalorie porcji pod nazwą przepisu. Brakujących liczb nie udajemy
    /// zerem.
    private var recipeFacts: String? {
        var parts: [String] = []
        if recipe.prepTimeMinutes > 0 { parts.append("\(recipe.prepTimeMinutes) min") }
        let kcal = Int(recipe.nutritionPerServing.kcal.rounded())
        if kcal > 0 { parts.append("\(kcal) kcal na porcję") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Body

    var body: some View {
        let days = stripDays
        let planned = plannedDays(in: days)
        let visibleSlots = sessionStore.mealSlots.visibleSlots(planned: plannedSlotsInSelectedWeek)

        return ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                EditorialSheetHeader(
                    eyebrow: "Dodaj do planu",
                    title: recipe.name,
                    icon: "calendar.badge.plus",
                    accent: SCPalette.terracotta,
                    subtitle: recipeFacts,
                    onClose: { dismiss() }
                )
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

                // Formularz mieści się pod nagłówkiem na każdym współczesnym
                // iPhonie; dopiero gdy nie wejdzie (SE, duża czcionka), ta sama
                // treść jedzie w `ScrollView`.
                ViewThatFits(in: .vertical) {
                    form(days: days, plannedDays: planned, slots: visibleSlots)
                        .padding(.bottom, 20)
                        .frame(maxHeight: .infinity, alignment: .top)

                    ScrollView {
                        form(days: days, plannedDays: planned, slots: visibleSlots)
                            // Zapas na cień stopki (`SCEdgeShade`), który leży na liście.
                            .padding(.bottom, SCEdgeShade.bottomHeight)
                    }
                    .scrollIndicators(.hidden)
                    .scScrollEdgeFade()
                }
                .disabled(isSaving)

                footer
            }
        }
        .onAppear {
            if selectedSlot == nil {
                selectedSlot = defaultSlot(from: visibleSlots)
            }
            // Reguła auto-porcji musi zadziałać PRZED pierwszym tapnięciem:
            // domyślne „Wspólne" nie jest wyborem użytkownika, więc `onChange`
            // chipów nigdy się dla niego nie odpala. W `init` nie ma jeszcze
            // środowiska, czyli domowników. Bez animacji — nie ma czego animować.
            applyAutoServings(for: selectedParticipants, animated: false)
        }
        // Zmiana dnia albo pory potrafi trafić na ten sam przepis stojący już
        // dla kogoś innego — porcje liczą się wtedy z połączonego audytorium.
        .onChange(of: samePlanned?.id) { _, _ in
            applyAutoServings(for: selectedParticipants, animated: true)
        }
        // Lista domowników dojeżdża asynchronicznie, więc `onAppear` często
        // widzi jeszcze pustkę.
        .onChange(of: knownMemberCount) { _, _ in
            applyAutoServings(for: selectedParticipants, animated: true)
        }
        .onChange(of: visibleSlots) { _, next in
            // Inny tydzień potrafi schować porę, która była widoczna tylko
            // dlatego, że coś w niej stało.
            if let selectedSlot, !next.contains(selectedSlot) {
                self.selectedSlot = defaultSlot(from: next)
            }
        }
        // Bez stuknięcia przy otwarciu: pierwsze ustawienie pory w `onAppear`
        // (z `nil`) nie jest wyborem użytkownika.
        .sensoryFeedback(.selection, trigger: selectedSlot) { old, new in
            old != nil && new != nil
        }
        .sensoryFeedback(.selection, trigger: calendar.startOfDay(for: selectedDate))
        .presentationDetents([.large])
        .dashboardLiquidSheet()
    }

    /// Cały formularz — jedna kopia dla obu gałęzi `ViewThatFits`.
    private func form(days: [Date], plannedDays: Set<Date>, slots: [MealSlot]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            daySection(days: days, plannedDays: plannedDays)
            slotSection(slots)
            audienceCard
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    // MARK: - Kiedy

    private func daySection(days: [Date], plannedDays: Set<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            EditorialSheetSectionLabel(title: "Kiedy")

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(days, id: \.self) { date in
                        HStack(spacing: 6) {
                            // Kreska przed poniedziałkiem — granica tygodnia
                            // bez podpisów i strzałek.
                            if date != days.first, calendar.component(.weekday, from: date) == 2 {
                                Capsule()
                                    .fill(Color.scTileStroke(scheme))
                                    .frame(width: 1.5, height: 34)
                                    .padding(.horizontal, 4)
                            }

                            dayCell(date, isPlanned: plannedDays.contains(date))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            // Pasek sięga krawędzi arkusza — widać, że jedzie dalej.
            // Start zawsze od dziś, czyli od pierwszej komórki — bez przewijania
            // do wyboru.
            .padding(.horizontal, -20)
        }
    }

    private func dayCell(_ date: Date, isPlanned: Bool) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                selectedDate = date
            }
        } label: {
            VStack(spacing: 2) {
                Text(isToday ? "DZIŚ" : Self.shortDayFormatter.string(from: date).uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(isSelected ? SCPalette.terracotta : Color.scMuted(scheme))

                Text(Self.dayNumberFormatter.string(from: date))
                    .font(.system(size: 18, weight: isSelected ? .heavy : .semibold))
                    .tracking(-0.3)
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))

                // Miejsce na kropkę zarezerwowane zawsze — komórki równej wysokości.
                Circle()
                    .fill(SCPalette.sage)
                    .frame(width: 4, height: 4)
                    .opacity(isPlanned ? 1 : 0)
            }
            .frame(width: 44, height: 56)
            .scChoiceSurface(
                shape,
                isOn: isSelected,
                accent: SCPalette.terracotta,
                offFill: Color.scTileBg(scheme),
                style: .tile
            )
            .contentShape(shape)
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .accessibilityLabel(dayAccessibilityLabel(date, isPlanned: isPlanned))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func dayAccessibilityLabel(_ date: Date, isPlanned: Bool) -> String {
        let day = Self.fullDateFormatter.string(from: date)
        return isPlanned ? day + ", coś już zaplanowane" : day
    }

    // MARK: - Posiłek

    private func slotSection(_ slots: [MealSlot]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            EditorialSheetSectionLabel(title: "Posiłek")

            VStack(spacing: 0) {
                ForEach(Array(slots.enumerated()), id: \.element) { index, slot in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.scTileStroke(scheme))
                            .frame(height: 1)
                            .padding(.leading, 50)
                    }
                    slotRow(slot)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    /// Wiersz pory: kafelek w kolorze pory, nazwa, co już tu stoi, kółko.
    /// Pora, pod którą przepis nie jest oznaczony, jest przygaszona, ale da
    /// się ją wybrać — wczorajszy obiad na podwieczorek to normalna rzecz.
    private func slotRow(_ slot: MealSlot) -> some View {
        let isSelected = slot == selectedSlot
        let fits = recipe.fits(slot)
        let takenBy = occupiedBy(slot)

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                selectedSlot = slot
            }
        } label: {
            HStack(spacing: 12) {
                SCHeaderIconWell(icon: slot.icon, accent: slot.cozyAccent, size: 26)

                Text(slot.title)
                    .font(.system(size: 14.5, weight: isSelected ? .bold : .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer(minLength: 8)

                if let takenBy {
                    Text(takenBy)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.scFaint(scheme))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentTransition(.opacity)
                }

                SCRadioMark(isOn: isSelected, accent: slot.cozyAccent, size: 20)
            }
            .opacity(fits ? 1 : 0.5)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                slot.cozyAccent
                    .opacity(isSelected ? (scheme == .dark ? 0.16 : 0.10) : 0)
            )
            .contentShape(Rectangle())
            .animation(.smooth(duration: 0.2), value: takenBy)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(slotAccessibilityLabel(slot, fits: fits, takenBy: takenBy))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func slotAccessibilityLabel(_ slot: MealSlot, fits: Bool, takenBy: String?) -> String {
        var parts = [slot.title]
        if let takenBy { parts.append("jest już: " + takenBy) }
        if !fits { parts.append("przepis nie jest pod to oznaczony") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Dla kogo i ile

    /// Audytorium i porcje w jednej karcie — porcje nadążają za osobami,
    /// dopóki nie ruszy się steppera. W domu jednoosobowym zostają same porcje.
    private var audienceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if members.count > 1 {
                PlanAudienceChips(
                    members: members,
                    selection: $selectedParticipants,
                    onChange: audienceChanged
                )

                Rectangle()
                    .fill(Color.scTileStroke(scheme))
                    .frame(height: 1)
            }

            HStack(spacing: 12) {
                // Bez etykiety „Porcje” — „2 porcje” mówi to samo.
                // Liczba roluje — przy stepperze i przy regule auto.
                Text(PolishPlural.servings(servings))
                    .font(.system(size: 17, weight: .heavy))
                    .tracking(-0.3)
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))
                    .contentTransition(.numericText(value: Double(servings)))
                    .padding(.leading, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SCStepper(
                    value: $servings,
                    accessibilityTitle: "Liczba porcji",
                    accessibilityValue: PolishPlural.servings(servings),
                    onChange: { _ in didOverrideServings = true }
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }

    // MARK: - Stopka

    // Bez czerwonego wiersza z `mealStore.errorMessage`: `save()` zamyka arkusz
    // synchronicznie, więc taki wiersz nigdy nie pokazałby błędu WŁASNEGO
    // zapisu. Błędy store jadą mostem z korzenia aplikacji.
    private var footer: some View {
        SCSheetFooter {
            Text(summaryText)
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.2)
                .monospacedDigit()
                .foregroundStyle(Color.scMuted(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)
                .animation(.smooth(duration: 0.25), value: summaryText)

            EditorialPrimaryActionButton(
                title: ctaTitle,
                icon: ctaIcon,
                isEnabled: canSave,
                isLoading: isSaving,
                action: { save() }
            )
            .animation(.smooth(duration: 0.25), value: ctaTitle)
        }
    }

    /// „Środa, 24 września · Obiad”. Dopiski: danie, które zapis wyprze
    /// („zamiast: Owsianka”), albo „dla całego domu”, gdy ten sam przepis stoi
    /// już w porze dla kogoś innego i razem obejmuje to cały dom.
    private var summaryText: String {
        var parts = [Self.dayName(for: selectedDate)]
        if let selectedSlot { parts.append(selectedSlot.title) }
        if !isAlreadyPlanned, let replaced = conflictingMeal?.recipe.name {
            parts.append("zamiast: " + replaced)
        } else if mergesIntoShared {
            parts.append("dla całego domu")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Akcje

    /// Chipy audytorium ruszyły — przelicz porcje po tej samej regule.
    /// Selekcja przychodzi parametrem: w domknięciu siedzi jeszcze wartość
    /// sprzed zapisu do bindingu.
    private func audienceChanged(_ selection: Set<String>) {
        applyAutoServings(for: selection, animated: true)
    }

    /// Reguła auto-porcji po stronie klienta — bliźniacza do tej, którą serwer
    /// stosuje, gdy `plannedServings` nie przyjdzie w payloadzie.
    private func applyAutoServings(for selection: Set<String>, animated: Bool) {
        // Ręczny wybór wygrywa ze zgadywaniem — na zawsze.
        guard !didOverrideServings else { return }

        // „Wspólne" liczy się z liczby domowników, a tej jeszcze nie znamy —
        // zostawiamy wartość startową i przeliczamy, gdy lista dojedzie.
        if selection.isEmpty, knownMemberCount == nil { return }

        // Z audytorium PO połączeniu z tymi, dla których przepis już tu stoi.
        let collapsed = PlanAudienceChips.collapsed(selection, members: members)
        let merged = PlanAudienceChips.merged(collapsed, with: samePlanned, members: members)
        let eaters = min(12, max(1, PlanAudienceChips.eaterCount(Set(merged), memberCount: members.count)))
        guard eaters != servings else { return }

        if animated {
            withAnimation(.smooth(duration: 0.18)) { servings = eaters }
        } else {
            servings = eaters
        }
    }

    /// Ten sam przepis stoi już w wybranej porze wybranego dnia — dla
    /// kogokolwiek.
    private var samePlanned: PlanMeal? {
        guard let selectedSlot else { return nil }
        return mealStore
            .meals(for: selectedDate, slot: selectedSlot)
            .first { $0.recipe.id == recipe.id }
    }

    /// Audytorium, z którym przepis naprawdę trafi do planu: wybrane osoby
    /// plus te, dla których ten przepis już tu stoi, a pełny dom zwinięty
    /// do „Wspólne”.
    private var audienceToSave: [String] {
        PlanAudienceChips.merged(participantsToSave, with: samePlanned, members: members)
    }

    /// Wybrane były konkretne osoby, a po zsumowaniu wychodzi cały dom.
    private var mergesIntoShared: Bool {
        samePlanned != nil && !participantsToSave.isEmpty && audienceToSave.isEmpty
    }

    /// Posiłek, który ten zapis zastąpi: ten sam dzień, slot i audytorium,
    /// INNY przepis. Slot z założenia mieści kilka posiłków („Każdy je
    /// inaczej”) — kolizją jest dopiero drugie danie dla TYCH SAMYCH osób.
    /// Porównujemy z wybranymi osobami i z audytorium po połączeniu —
    /// inaczej suma do „Wspólne” stawiała drugie wspólne danie obok.
    private var conflictingMeal: PlanMeal? {
        guard let selectedSlot else { return nil }
        let audiences: Set<Set<String>> = [Set(participantsToSave), Set(audienceToSave)]
        return mealStore
            .meals(for: selectedDate, slot: selectedSlot)
            .first { $0.recipe.id != recipe.id && audiences.contains(Set($0.participantIds)) }
    }

    /// Ten przepis już tu jest dla wybranych osób — nie ma czego zapisywać.
    private var isAlreadyPlanned: Bool {
        guard let existing = samePlanned else { return false }
        if existing.isShared { return true }
        let audience = Set(participantsToSave)
        return !audience.isEmpty && audience.isSubset(of: Set(existing.participantIds))
    }

    /// Nazwa dania, które zajmuje daną porę wybranego dnia — najpierw to dla
    /// wybranych osób, potem cokolwiek.
    private func occupiedBy(_ slot: MealSlot) -> String? {
        let audience = Set(participantsToSave)
        let meals = mealStore.meals(for: selectedDate, slot: slot)
        let mine = meals.first { Set($0.participantIds) == audience }
        return (mine ?? meals.first)?.recipe.name
    }

    private var ctaTitle: String {
        if isAlreadyPlanned { return "Już jest w planie" }
        if conflictingMeal != nil { return "Zamień w planie" }
        return "Dodaj do planu"
    }

    private var ctaIcon: String {
        if isAlreadyPlanned { return "checkmark" }
        if conflictingMeal != nil { return "arrow.2.squarepath" }
        return "calendar.badge.plus"
    }

    /// Arkusz potrafi zostać otwarty przez północ — wtedy zaznaczone „dziś”
    /// staje się „wczoraj” pod ręką.
    private var canSave: Bool {
        selectedSlot != nil && isEditable(selectedDate) && !isAlreadyPlanned
    }

    private func save() {
        guard let slot = selectedSlot, !isSaving, isEditable(selectedDate), !isAlreadyPlanned else { return }
        isSaving = true
        let date = selectedDate
        // Zajęty slot podmieniamy, zamiast dokładać obok — drugie „Wspólne”
        // śniadanie wjeżdżało do bazy jako wpis, którego plan nie pokazywał.
        let replacing = conflictingMeal?.recipe.id
        // Nazwę wypieranego dania i audytorium bierzemy TERAZ — po zapisie
        // optymistycznym liczyłyby się już od nowego dania.
        let replacedName = conflictingMeal?.recipe.name
        let audience = audienceToSave
        let becameShared = mergesIntoShared

        // Dismiss od razu, jak w PlanSlotPickerSheet: wpis optymistyczny
        // ląduje w store przed siecią. Kolejkę toastów bierzemy do stałej
        // PRZED zadaniem — po zamknięciu arkusza jego środowiska już nie ma.
        let store = mealStore
        let toasts = toasts
        // Nazwy pory NIE zniżamy: „II śniadanie" wyszłoby jako „ii śniadanie".
        let place = "\(Self.dayName(for: date)) · \(slot.title)"
        let placement = becameShared ? place + " · dla całego domu" : place
        // Dwa identyczne błędy pod rząd nie są dla mostu zmianą — pamiętamy,
        // co było przed zapisem.
        let errorBefore = store.errorMessage
        Task { @MainActor in
            let saved = await store.upsertWeekSlot(
                recipe: recipe,
                participantIds: audience,
                // Liczbę wysyłamy tylko jako wybór użytkownika — brak pola
                // znaczy dla serwera „policz sam z audytorium” na świeżej
                // liście domowników. Przy łączeniu z istniejącą pozycją ręczna
                // liczba zjadłaby porcję tamtej osoby, więc też jej nie ma.
                plannedServings: didOverrideServings && samePlanned == nil ? servings : nil,
                householdMemberCount: members.isEmpty ? nil : members.count,
                replacingRecipeId: replacing,
                for: date,
                slot: slot,
                weekStart: PlanWeek.dateKey(PlanWeek.monday(of: date))
            )

            guard saved else {
                // Błąd łączności NIE ustawia `errorMessage`, więc bez tego
                // użytkownik odszedłby przekonany, że posiłek jest w planie.
                // Bez „sprawdź połączenie” — brak sieci ma jedno miejsce.
                if store.errorMessage == errorBefore {
                    toasts.error("Nie udało się dodać do planu", "Plan został bez zmian.")
                }
                return
            }

            if let replacedName {
                toasts.success("Zamieniono w planie", "\(slot.title) — zamiast: \(replacedName)")
            } else {
                toasts.success("Dodano do planu", placement)
            }
        }
        onAdded?(date, slot)
        dismiss()
    }

    // MARK: - Formatowanie

    /// Dzień z datą — pasek sięga czterech tygodni, więc „czwartek” bywa
    /// dwuznaczny. Formatter oddaje małą literę, a to początek zdania.
    private static func dayName(for date: Date) -> String {
        let raw = dayFormatter.string(from: date)
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter
    }()

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "EE"
        return formatter
    }()

    private static let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d"
        return formatter
    }()

    /// Pełna data dla VoiceOver — po polsku, jak cała aplikacja.
    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()
}

// MARK: - Preview

// `RecipesMock` żyje w `#if DEBUG`, a makro `#Preview` rozwija się także
// w Release — bez tej bramki archiwum nie kompiluje się.
#if DEBUG

#Preview("Add To Plan — Dark") {
    AddToPlanSheet(recipe: RecipesMock.chickenBowl, initialServings: 2)
        .preferredColorScheme(.dark)
}

#Preview("Add To Plan — Light") {
    AddToPlanSheet(recipe: RecipesMock.chickenBowl, initialServings: 2)
        .preferredColorScheme(.light)
}

#endif
