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
/// Wygląd (runda 14, 23.09.2026 — „paskudny, zrób od nowa, porządnie,
/// czytelnie, naszymi standardami i animacjami”). Arkusz składa się
/// wyłącznie z klocków, które użytkownik zna z innych ekranów:
///
/// - **Nagłówek** — zdjęcie dania (`EditorialRecipeCover`), „DODAJ DO PLANU”,
///   nazwa i dwa fakty z ikonami (czas, kalorie). Zdjęcie mówi, CO się dodaje,
///   szybciej niż kafelek z kalendarzem.
/// - **Kiedy** — tydzień dokładnie jak `EditorialWeekBar` w Planie: podpis
///   „TEN TYDZIEŃ · 22–28 WRZ”, strzałki, „Wróć do dziś”, podkreślenie, które
///   przejeżdża między dniami, przeciąganie w bok zmienia tydzień, miniony
///   dzień przekreślony. Wszystko w jednej karcie.
/// - **Posiłek** — pory jako kafle (układ wg liczby pór): ikona w kolorze pory, nazwa, godzina.
///   Wybrany kafel w tincie pory (`scChoiceSurface`); co zapis podmieni, mówi JEDNA karta
///   „ZAMIENISZ” w stopce (danie w kaflach odpadło w rundzie 20 — „brzydkie”).
///   Lista wierszy z rundy 14 odpadła 24.09 — „nie do końca podoba mi się
///   design tego”.
/// - **Dla kogo** — `PlanAudienceChips` (tylko w domu wieloosobowym).
/// - **Porcje** — jeden wiersz: „Porcje”, rolująca liczba, `SCStepper`.
/// - **Stopka** (`scSheetFooter`, cień `SCEdgeShade`) — rolujące zdanie
///   „Środa, 24 września · Obiad” i przycisk, którego tytuł też roluje.
///
/// Sekcje wjeżdżają kaskadą jak w szczegółach posiłku (`scReveal`). Na
/// ekranie, na którym wszystko się mieści, lista nie odbija
/// (`scrollBounceBehavior(.basedOnSize)`), więc czyta się jak widok bez
/// przewijania; na małym przewija się pod przypiętym nagłówkiem.
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
    /// Kaskada sekcji (`scReveal`) — przestawiana w `.task` po klatce oddechu.
    @State private var hasAppeared = false

    // Gest tygodnia — te same liczby i ta sama logika, co w `EditorialWeekBar`.
    @State private var dragOffset: CGFloat = 0
    @State private var isHorizontalDrag: Bool?
    @State private var dragBaseline: CGFloat = 0
    @Namespace private var dayIndicatorNS

    private var calendar: Calendar { PlanWeek.calendar }

    // MARK: - Dane pochodne

    private var members: [HouseholdMemberSnapshot] { sessionStore.householdMembers }

    /// Liczba domowników albo `nil`, dopóki `SessionStore` nie wczyta listy.
    /// „Jeszcze nie wiem” i „dom jednoosobowy” dają tę samą jedynkę
    /// w `eaterCount`, a tylko w drugim przypadku to prawda.
    private var knownMemberCount: Int? {
        sessionStore.didLoadHouseholdMembers ? members.count : nil
    }

    /// Poniedziałek–niedziela tygodnia, w którym leży `selectedDate`.
    private var weekDates: [Date] {
        let monday = PlanWeek.monday(of: selectedDate)
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: monday)
        }
    }

    /// Jedno przejście po tygodniu: kreski „tu już coś stoi” pod dniami
    /// i pory wyłączone w ustawieniach, w których mimo to coś stoi
    /// (`visibleSlots(planned:)` pokazuje je, żeby jedzenie nie znikało).
    private func weekOverview(for days: [Date]) -> (plannedDays: Set<Date>, plannedSlots: [MealSlot]) {
        var plannedDays: Set<Date> = []
        var plannedSlots: Set<MealSlot> = []

        for day in days {
            // Dzień pobrany raz, nie sześć razy — body przelicza się przy
            // każdym stuknięciu.
            let plan = mealStore.plan(for: day)
            for slot in MealSlot.allCases where !plan.meals(for: slot).isEmpty {
                plannedDays.insert(calendar.startOfDay(for: day))
                plannedSlots.insert(slot)
            }
        }

        return (plannedDays, Array(plannedSlots).sortedByDay)
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

    /// Bieżący tydzień jest ostatnim, w którym cokolwiek da się zaplanować —
    /// wcześniejsze pokazywałyby siedem nieklikalnych komórek.
    private var canGoToPreviousWeek: Bool {
        PlanWeek.monday(of: selectedDate) > PlanWeek.monday(of: Date())
    }

    /// O ile tygodni oglądany tydzień jest od bieżącego.
    private var weekOffset: Int {
        let current = PlanWeek.monday(of: Date())
        let shown = PlanWeek.monday(of: selectedDate)
        let days = calendar.dateComponents([.day], from: current, to: shown).day ?? 0
        return Int((Double(days) / 7).rounded())
    }

    /// Czas i kalorie porcji pod nazwą — z ikonami, jak na kartach przepisów.
    /// Brakujących liczb nie udajemy zerem.
    private var facts: [HeaderFact] {
        var result: [HeaderFact] = []
        if recipe.prepTimeMinutes > 0 {
            result.append(HeaderFact(icon: "clock", text: "\(recipe.prepTimeMinutes) min"))
        }
        let kcal = Int(recipe.nutritionPerServing.kcal.rounded())
        if kcal > 0 {
            result.append(HeaderFact(icon: "flame", text: "\(kcal) kcal"))
        }
        return result
    }

    private struct HeaderFact: Identifiable {
        let icon: String
        let text: String
        var id: String { icon }
    }

    // MARK: - Body

    var body: some View {
        let overview = weekOverview(for: weekDates)
        let visibleSlots = sessionStore.mealSlots.visibleSlots(planned: overview.plannedSlots)

        return ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Nagłówek przypięty nad treścią — nie przewija się i nie zwija.
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        weekSection(plannedDays: overview.plannedDays)
                            .scReveal(hasAppeared, order: 0)

                        slotSection(visibleSlots)
                            .scReveal(hasAppeared, order: 1)

                        // Jednoosobowe gospodarstwo nie ma o czym decydować —
                        // każdy posiłek i tak jest „Wspólne".
                        if members.count > 1 {
                            PlanAudienceChips(
                                members: members,
                                selection: $selectedParticipants,
                                onChange: audienceChanged
                            )
                            .scReveal(hasAppeared, order: 2)
                            .transition(.opacity)
                        }

                        servingsSection
                            .scReveal(hasAppeared, order: 3)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                    // Lista domowników dojeżdża asynchronicznie — chipy mają
                    // wjechać, a nie wskoczyć i zepchnąć porcje.
                    .animation(.smooth(duration: 0.25), value: members.count > 1)
                }
                .scrollIndicators(.hidden)
                // Gdy wszystko się mieści, lista stoi jak zwykły widok — bez
                // gumowego odbicia, które zdradzałoby przewijanie.
                .scrollBounceBehavior(.basedOnSize)
                .scScrollEdgeFade()
                .disabled(isSaving)
                .scSheetFooter { footerContent }
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
        // Klatka oddechu jak w szczegółach posiłku: arkusz zaczyna wjeżdżać,
        // dopiero potem treść. W `onAppear` kaskada padałaby w klatce
        // wstawienia i nie grała.
        .task {
            guard !hasAppeared else { return }
            try? await Task.sleep(for: .milliseconds(80))
            hasAppeared = true
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

    // MARK: - Nagłówek

    /// Krój i układ `EditorialSheetHeader`, tylko w miejscu kafelka z ikoną
    /// stoi zdjęcie dania — to jego dotyczy cały arkusz.
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 12) {
                EditorialRecipeCover(recipe: recipe, size: 58, cornerRadius: 15)

                VStack(alignment: .leading, spacing: 3) {
                    Text("DODAJ DO PLANU")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(SCPalette.terracotta)
                        .lineLimit(1)

                    Text(recipe.name)
                        .font(.system(size: 20, weight: .heavy))
                        .tracking(-0.4)
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if !facts.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(facts) { fact in
                                HStack(spacing: 4) {
                                    Image(systemName: fact.icon)
                                        .font(.system(size: 10.5, weight: .semibold))
                                    Text(fact.text)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .monospacedDigit()
                                }
                                .foregroundStyle(Color.scMuted(scheme))
                            }
                        }
                        .padding(.top, 1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            SCSheetCloseButton(action: { dismiss() })
        }
    }

    // MARK: - Kiedy

    private func weekSection(plannedDays: Set<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            EditorialSheetSectionLabel(title: "Kiedy")

            VStack(spacing: 14) {
                weekCaptionRow

                HStack(spacing: 0) {
                    // Po pozycji w tygodniu, nie po dacie: przy zmianie tygodnia
                    // komórka zostaje ta sama i jej liczba roluje się na nową,
                    // zamiast gasnąć i zapalać się od nowa.
                    ForEach(Array(weekDates.enumerated()), id: \.offset) { _, date in
                        dayCell(
                            date,
                            isPlanned: plannedDays.contains(calendar.startOfDay(for: date))
                        )
                    }
                }
                // Przeciąganie łapie się w całym prostokącie planszy dni.
                .contentShape(Rectangle())
                .offset(x: dragOffset)
                // `simultaneousGesture`: plansza siedzi w pionowym `ScrollView`,
                // zwykły `DragGesture` zabrałby mu przewijanie.
                .simultaneousGesture(weekSwipe)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .background(cardShape.fill(Color.scTileBg(scheme)))
            .overlay(cardShape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
            // Plansza przesuwana palcem nie wyjeżdża poza kartę.
            .clipShape(cardShape)
        }
    }

    /// Podpis jak nad Planem: „TEN TYDZIEŃ · 22–28 WRZ”, „Wróć do dziś”
    /// poza bieżącym tygodniem i strzałki 26 pt.
    private var weekCaptionRow: some View {
        HStack(spacing: 6) {
            Text(weekCaption)
                .scFont(9.5, weight: .bold, relativeTo: .caption2)
                .tracking(1.1)
                .foregroundStyle(Color.scMuted(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
                .padding(.leading, 4)

            Spacer(minLength: 6)

            if weekOffset != 0 {
                Button {
                    changeWeek { selectedDate = Date() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("Wróć do dziś")
                            .scFont(11, weight: .semibold, relativeTo: .caption2)
                            .tracking(-0.1)
                    }
                    .foregroundStyle(SCPalette.terracotta)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .scSoftCapsule()
                    .frame(minWidth: 44)
                    .scTapHeight(drawn: 22)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                .accessibilityLabel("Wróć do bieżącego tygodnia")
            }

            weekArrow(
                systemName: "chevron.left",
                label: "Poprzedni tydzień",
                delta: -7,
                isEnabled: canGoToPreviousWeek
            )

            weekArrow(
                systemName: "chevron.right",
                label: "Następny tydzień",
                delta: 7,
                isEnabled: true
            )
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: weekOffset == 0)
    }

    private func weekArrow(
        systemName: String,
        label: String,
        delta: Int,
        isEnabled: Bool
    ) -> some View {
        Button {
            shiftWeek(by: delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.scLabel(scheme))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.scChipBg(scheme)))
                .overlay(Circle().stroke(Color.scTileStroke(scheme), lineWidth: 1))
                .scTapTarget(drawn: 26)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    /// Komórka dnia — wygląd `EditorialWeekBar.DayCell`: skrót dnia, liczba,
    /// pod spodem terakotowe podkreślenie, które PRZEJEŻDŻA między dniami
    /// (`matchedGeometryEffect`), i szałwiowa kreska przy dniu z posiłkami.
    private func dayCell(_ date: Date, isPlanned: Bool) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isPast = !isEditable(date)
        let label = Color.scLabel(scheme)
        let muted = Color.scMuted(scheme)

        return Button {
            withAnimation(DayNavigationMotion.spring) {
                selectedDate = date
            }
        } label: {
            VStack(spacing: 4) {
                Text(Self.shortDayFormatter.string(from: date).uppercased())
                    .scFont(9, weight: .bold, relativeTo: .caption2)
                    .tracking(1)
                    .foregroundStyle(isSelected ? label : muted)
                    .contentTransition(.interpolate)

                Text(Self.dayNumberFormatter.string(from: date))
                    .scFont(18, weight: isSelected ? .heavy : .semibold, relativeTo: .body)
                    .tracking(-0.3)
                    .monospacedDigit()
                    .foregroundStyle(isPast ? muted : label)
                    .strikethrough(isPast, color: Color.scStrike(scheme))
                    // Przy zmianie tygodnia liczba roluje się na nową — komórka
                    // zostaje ta sama (`ForEach` po pozycji w tygodniu).
                    .contentTransition(.numericText())

                ZStack {
                    // Wysokość zarezerwowana, żeby układ nie skakał, gdy
                    // wskaźniki pojawiają się i znikają.
                    Color.clear.frame(height: 2)

                    if isPlanned && !isSelected {
                        Capsule()
                            .fill(SCPalette.sage)
                            .frame(width: 10, height: 2)
                            .transition(.scale.combined(with: .opacity))
                    }

                    if isSelected {
                        Capsule()
                            .fill(SCPalette.terracotta)
                            .frame(width: 18, height: 2)
                            .matchedGeometryEffect(id: "addToPlan.dayIndicator", in: dayIndicatorNS)
                    }
                }
                .frame(height: 4)
                .padding(.top, 4)
            }
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            // Miniony dzień przygaszony w całości — mówi to samo, co brak
            // reakcji na stuknięcie.
            .opacity(isPast ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Wpisu wstecz nie dałoby się już usunąć — Plan i Kalendarz pokazują
        // minione dni tylko do odczytu.
        .disabled(isPast)
        .accessibilityLabel(dayAccessibilityLabel(date, isPast: isPast, isPlanned: isPlanned))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func dayAccessibilityLabel(_ date: Date, isPast: Bool, isPlanned: Bool) -> String {
        let day = Self.fullDateFormatter.string(from: date)
        if isPast { return day + ", minął" }
        let today = calendar.isDateInToday(date) ? day + ", dziś" : day
        return isPlanned ? today + ", coś już zaplanowane" : today
    }

    /// Przesunięcie o tydzień, z barierą na przeszłość: cofnięcie z przyszłego
    /// tygodnia potrafi wylądować na dniu, który już minął — wtedy wybór
    /// podciągamy do dziś, zamiast zostawić go na nieklikalnej komórce.
    private func shiftWeek(by delta: Int) {
        guard delta > 0 || canGoToPreviousWeek else { return }
        guard let shifted = calendar.date(byAdding: .day, value: delta, to: selectedDate) else { return }
        let target = isEditable(shifted) ? shifted : Date()
        changeWeek { selectedDate = target }
    }

    /// Zmiana tygodnia w jednej animacji z powrotem planszy na miejsce —
    /// ta sama sprężyna, którą przestawia się dzień w Planie.
    private func changeWeek(_ step: () -> Void) {
        withAnimation(DayNavigationMotion.spring) {
            step()
            dragOffset = 0
        }
        // Haptyka zmiany tygodnia to haptyka zmiany dnia — dzień zmienia się
        // razem z tygodniem, więc drugie stuknięcie w tej samej klatce byłoby
        // podwójne.
    }

    /// Przeciąganie planszy dni — kopia zachowania `EditorialWeekBar`: oś
    /// rozstrzygana raz, opór na krawędzi, próg z rozpędem palca.
    private var weekSwipe: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                if isHorizontalDrag == nil {
                    let horizontal = abs(value.translation.width)
                    let vertical = abs(value.translation.height)
                    guard max(horizontal, vertical) >= Self.axisLockDistance else { return }
                    isHorizontalDrag = horizontal > vertical
                    dragBaseline = value.translation.width
                }

                // Pion należy do przewijania arkusza.
                guard isHorizontalDrag == true else { return }
                dragOffset = Self.resisted(value.translation.width - dragBaseline)
            }
            .onEnded { value in
                let wasHorizontal = isHorizontalDrag == true
                let baseline = dragBaseline
                isHorizontalDrag = nil
                dragBaseline = 0

                let travel = value.predictedEndTranslation.width - baseline
                // Wstecz tylko wtedy, gdy jest dokąd — bieżący tydzień to
                // najwcześniejszy, w którym da się coś zaplanować.
                let canCommit = wasHorizontal
                    && abs(travel) >= Self.commitThreshold
                    && (travel < 0 || canGoToPreviousWeek)

                guard canCommit else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        dragOffset = 0
                    }
                    return
                }

                shiftWeek(by: travel < 0 ? 7 : -7)
            }
    }

    private static let commitThreshold: CGFloat = 56
    private static let dragLimit: CGFloat = 56
    private static let axisLockDistance: CGFloat = 14

    /// Opór na krawędzi: pierwsze punkty idą prawie 1:1, dalej ruch się
    /// wypłaszcza i nigdy nie przekracza `dragLimit`.
    private static func resisted(_ translation: CGFloat) -> CGFloat {
        let ratio = translation / dragLimit
        return dragLimit * ratio / (1 + abs(ratio))
    }

    /// „TEN TYDZIEŃ · 22–28 WRZ” — te same słowa, co nad Planem.
    private var weekCaption: String {
        let range = weekRangeText
        switch weekOffset {
        case 0:  return "TEN TYDZIEŃ · \(range)"
        case 1:  return "PRZYSZŁY TYDZIEŃ · \(range)"
        default: return "TYDZIEŃ · \(range)"
        }
    }

    /// „22–28 WRZ”, a przez granicę miesiąca „29 WRZ–5 PAŹ”.
    private var weekRangeText: String {
        let days = weekDates
        guard let first = days.first, let last = days.last else { return "" }
        let sameMonth = calendar.component(.month, from: first)
            == calendar.component(.month, from: last)
        let from = sameMonth
            ? Self.dayNumberFormatter.string(from: first)
            : Self.dayMonthFormatter.string(from: first)
        return "\(from)–\(Self.dayMonthFormatter.string(from: last))".uppercased()
    }

    // MARK: - Posiłek

    /// Układ kafli pór zależy od tego, ile pór ma użytkownik:
    /// 1–2 → poziome kafle (ikona obok nazwy) w jednym rzędzie,
    /// 3 → trzy pionowe kafle obok siebie, 4 → 2 × 2 poziome,
    /// 5–6 → siatka 3 kolumn pionowych. Pionowy kafel stawia nazwę pod ikoną,
    /// więc „Podwieczorek” mieści się też w jednej trzeciej szerokości.
    private enum SlotTileLayout {
        case wide(columns: Int)
        case compact(columns: Int)

        init(count: Int) {
            switch count {
            case ...2: self = .wide(columns: max(1, count))
            case 4: self = .wide(columns: 2)
            default: self = .compact(columns: 3)
            }
        }

        var columns: Int {
            switch self {
            case .wide(let columns), .compact(let columns): columns
            }
        }

        var isCompact: Bool {
            if case .compact = self { return true }
            return false
        }
    }

    private func slotSection(_ slots: [MealSlot]) -> some View {
        let layout = SlotTileLayout(count: slots.count)
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
            count: layout.columns
        )
        return VStack(alignment: .leading, spacing: 4) {
            EditorialSheetSectionLabel(title: "Posiłek")

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(slots) { slot in
                    slotTile(slot, compact: layout.isCompact)
                }
            }
        }
    }

    /// Kafel pory: kafelek z ikoną w kolorze pory, nazwa i godzina — nic
    /// więcej. Co zapis podmieni, mówi JEDNA karta „ZAMIENISZ” w stopce
    /// (runda 20: wiersz dania w każdym kaflu był „brzydki”, a karta na dole
    /// „wystarczy”). Wszystkie pory w pełnym kolorze — także te, pod które
    /// przepis nie jest oznaczony (Rafał: „obiad i kolacja wyszarzone, zostaw
    /// normalne”); mówi o tym tylko VoiceOver.
    private func slotTile(_ slot: MealSlot, compact: Bool) -> some View {
        let isSelected = slot == selectedSlot
        let fits = recipe.fits(slot)
        let replaced = isSelected ? conflictingMeal : nil
        let taken = replaced ?? occupant(of: slot)
        let time = sessionStore.mealSlotSchedule.time(for: slot)
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                selectedSlot = slot
            }
        } label: {
            Group {
                if compact {
                    compactSlotContent(slot, time: time, isSelected: isSelected)
                } else {
                    wideSlotContent(slot, time: time, isSelected: isSelected)
                }
            }
            .scChoiceSurface(
                shape,
                isOn: isSelected,
                accent: slot.cozyAccent,
                offFill: Color.scTileBg(scheme),
                style: .tile
            )
            .contentShape(shape)
        }
        .buttonStyle(PlanPressStyle(scale: 0.97))
        .accessibilityLabel(slotAccessibilityLabel(
            slot,
            fits: fits,
            takenBy: taken?.recipe.name,
            replacing: replaced != nil
        ))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Poziomy kafel (1, 2 albo 4 pory): ikona obok nazwy i godziny.
    private func wideSlotContent(
        _ slot: MealSlot,
        time: String?,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 10) {
            SCHeaderIconWell(icon: slot.icon, accent: slot.cozyAccent, size: 34)

            VStack(alignment: .leading, spacing: 1) {
                slotTitle(slot, size: 15, isSelected: isSelected)

                if let time {
                    slotTime(time)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    }

    /// Pionowy kafel (3, 5 albo 6 pór): ikona nad nazwą i godziną, wyśrodkowane.
    private func compactSlotContent(
        _ slot: MealSlot,
        time: String?,
        isSelected: Bool
    ) -> some View {
        VStack(spacing: 6) {
            SCHeaderIconWell(icon: slot.icon, accent: slot.cozyAccent, size: 32)

            VStack(spacing: 1) {
                slotTitle(slot, size: 13.5, isSelected: isSelected)

                if let time {
                    slotTime(time)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .top)
    }

    private func slotTitle(_ slot: MealSlot, size: CGFloat, isSelected: Bool) -> some View {
        Text(slot.title)
            .font(.system(size: size, weight: isSelected ? .bold : .semibold))
            .tracking(-0.2)
            .foregroundStyle(isSelected ? slot.cozyAccent : Color.scLabel(scheme))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private func slotTime(_ time: String) -> some View {
        Text(time)
            .font(.system(size: 11.5, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Color.scMuted(scheme))
            .lineLimit(1)
    }

    private func slotAccessibilityLabel(
        _ slot: MealSlot,
        fits: Bool,
        takenBy: String?,
        replacing: Bool
    ) -> String {
        var parts = [slot.title]
        if let takenBy { parts.append((replacing ? "zamienisz: " : "jest już: ") + takenBy) }
        if !fits { parts.append("przepis nie jest pod to oznaczony") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Porcje

    /// Porcje w jednym wierszu: etykieta, rolująca liczba i stepper.
    private var servingsSection: some View {
        HStack(spacing: 12) {
            Text("Porcje")
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Color.scLabel(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Liczba roluje — przy stepperze i przy regule auto, gdy chipy
            // „Dla kogo” przestawiają porcje.
            Text("\(servings)")
                .font(.system(size: 20, weight: .heavy))
                .tracking(-0.3)
                .monospacedDigit()
                .foregroundStyle(Color.scLabel(scheme))
                .contentTransition(.numericText(value: Double(servings)))
                .frame(minWidth: 26, alignment: .trailing)
                .accessibilityHidden(true)

            SCStepper(
                value: $servings,
                accessibilityTitle: "Liczba porcji",
                accessibilityValue: PolishPlural.servings(servings),
                onChange: { _ in didOverrideServings = true }
            )
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(minHeight: 54)
        .background(cardShape.fill(Color.scTileBg(scheme)))
        .overlay(cardShape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    // MARK: - Stopka

    // Bez czerwonego wiersza z `mealStore.errorMessage`: `save()` zamyka arkusz
    // synchronicznie, więc taki wiersz nigdy nie pokazałby błędu WŁASNEGO
    // zapisu. Błędy store jadą mostem z korzenia aplikacji.
    @ViewBuilder
    private var footerContent: some View {
        VStack(spacing: 10) {
            // Podmiana jest decyzją, nie dopiskiem — wyparte danie stoi nad
            // przyciskiem ze zdjęciem, zanim ktoś je nadpisze.
            if let replaced = replacedMeal {
                replacementNotice(replaced)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Jedno zdanie o tym, co się stanie. Słowa i cyfry rolują przy
            // każdej zmianie wyboru nad nim.
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
        }
        .animation(.smooth(duration: 0.25), value: replacedMeal?.id)

        EditorialPrimaryActionButton(
            title: ctaTitle,
            icon: ctaIcon,
            isEnabled: canSave,
            isLoading: isSaving,
            action: { save() }
        )
        .animation(.smooth(duration: 0.25), value: ctaTitle)
    }

    /// „Środa, 24 września · Obiad”. Dopisek „dla całego domu”, gdy ten sam
    /// przepis stoi już w porze dla kogoś innego i razem obejmuje to cały dom.
    /// Wypierane danie ma własny wiersz nad zdaniem (`replacementNotice`).
    private var summaryText: String {
        var parts = [Self.dayName(for: selectedDate)]
        if let selectedSlot { parts.append(selectedSlot.title) }
        if replacedMeal == nil, mergesIntoShared {
            parts.append("dla całego domu")
        }
        return parts.joined(separator: " · ")
    }

    /// Danie, które zapis naprawdę wyprze z planu.
    private var replacedMeal: PlanMeal? {
        isAlreadyPlanned ? nil : conflictingMeal
    }

    /// „ZAMIENISZ · Owsianka z jabłkiem” ze zdjęciem — karta nad zdaniem
    /// w stopce, w kolorze wybranej pory.
    private func replacementNotice(_ meal: PlanMeal) -> some View {
        let accent = selectedSlot?.cozyAccent ?? SCPalette.terracotta
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        return HStack(spacing: 10) {
            // Zdjęcie przenika się przy zmianie wypieranego dania (np.
            // śniadanie → obiad), karta stoi w miejscu.
            ZStack {
                EditorialRecipeCover(recipe: meal.recipe, size: 36, cornerRadius: 10)
                    .id(meal.recipe.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text("ZAMIENISZ")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(accent)
                    .lineLimit(1)

                Text(meal.recipe.name)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Nazwa ROLUJE jak zdanie pod kartą — `.opacity` przy
                    // tej długości tekstu wyglądało jak podmiana bez ruchu.
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                // Strzałki obracają się raz przy każdej zmianie dania.
                .symbolEffect(.rotate, value: meal.recipe.id)
        }
        .animation(.smooth(duration: 0.3), value: meal.recipe.id)
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(shape.fill(Color.scTileBg(scheme)))
        .overlay(shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Zamienisz: " + meal.recipe.name)
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

    /// Danie, które zajmuje daną porę wybranego dnia — najpierw to dla
    /// wybranych osób, potem jakiekolwiek.
    private func occupant(of slot: MealSlot) -> PlanMeal? {
        let audience = Set(participantsToSave)
        let meals = mealStore.meals(for: selectedDate, slot: slot)
        return meals.first { Set($0.participantIds) == audience } ?? meals.first
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

    /// Dzień z datą — arkusz przewija tygodnie, więc „czwartek” bywa
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

    /// „27 wrz” — z miesiącem na końcu zakresu i na granicy miesięcy.
    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMM"
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
