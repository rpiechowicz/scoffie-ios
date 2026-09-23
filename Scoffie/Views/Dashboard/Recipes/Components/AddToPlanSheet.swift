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
/// Trzy decyzje, które łatwo cofnąć przez nieuwagę:
///
/// 1. **Arkusz trzyma własną datę.** Wybór dnia jest tutaj częścią formularza,
///    a nie nawigacją po aplikacji — dlatego pasek dni jest lokalny i pisany
///    na `selectedDate`, zamiast sięgać po `EditorialWeekBar`
///    (`datesViewModel.selectDate(...)` przestawiłby użytkownikowi dzień
///    w Planie i Kalendarzu, choć chciał tylko dorzucić kolację na czwartek).
///    Z `DatesViewModel` bierzemy tu wyłącznie `isEditable(_:)` — czytanie
///    reguły „czego już nie wolno planować" niczego nie przestawia, a własna
///    kopia tej reguły rozjechałaby się z resztą aplikacji.
/// 2. **Chipy audytorium przestawiają stepper tylko do pierwszego ruchu ręką.**
///    Patrz `didOverrideServings`. Sama reguła auto działa od otwarcia arkusza,
///    nie dopiero po tapnięciu w chip — patrz `applyAutoServings(for:animated:)`.
/// 3. **Przeszłego dnia nie da się wybrać.** Reszta aplikacji blokuje edycję
///    minionych dni (`DatesViewModel.isEditable`), a taki wpis dodany stąd
///    byłby nie do usunięcia z Planu — bo tam ten dzień jest już tylko do
///    odczytu.
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
        // Flaga „to już jest wybór użytkownika" musi przejść przez granicę
        // arkusza, bo stepper w szczegółach przepisu i stepper tutaj regulują
        // to samo. Bez niej reguła auto nadpisałaby przy otwarciu świadome
        // „gotuję 4 porcje" ustawione ekran wcześniej.
        _didOverrideServings = State(initialValue: didOverrideServings)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.toasts) private var toasts
    @Environment(\.mealCalendarStore) private var mealStore
    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.colorScheme) private var scheme

    /// Dzień wybrany w tym arkuszu. Startuje od dziś, bo „dodaj do planu"
    /// najczęściej znaczy „na dzisiaj albo na najbliższe dni", a przeniesienie
    /// tu dnia zaznaczonego w Planie kazałoby użytkownikowi pamiętać, gdzie
    /// zostawił tamten ekran.
    @State private var selectedDate = Date()
    /// `nil` do pierwszego przemalowania — domyślny slot znamy dopiero wtedy,
    /// gdy wiadomo, które posiłki gospodarstwo w ogóle planuje.
    @State private var selectedSlot: MealSlot?
    /// Pusty zbiór znaczy „Wspólne" — danie je całe gospodarstwo.
    @State private var selectedParticipants: Set<String> = []
    @State private var servings: Int
    /// Czy użytkownik ruszył stepper ręcznie — tutaj albo jeszcze w szczegółach
    /// przepisu (wtedy przychodzi jako `true` z parametru inicjalizatora).
    ///
    /// Dopóki `false`, liczba porcji nadąża za audytorium (jest najlepszym
    /// zgadywaniem) i nie leci na serwer — patrz `save()`. Po pierwszym
    /// stuknięciu w stepper przestajemy ją nadpisywać i wysyłamy jawnie: bez
    /// tego świadome „gotuję 4 porcje na zapas" znikałoby przy każdym
    /// tapnięciu w chip i wracało do liczby jedzących.
    @State private var didOverrideServings = false
    @State private var isSaving = false
    @Namespace private var dayIndicatorNS

    // MARK: - Dane pochodne

    private var members: [HouseholdMemberSnapshot] { sessionStore.householdMembers }

    /// Liczba domowników albo `nil`, dopóki `SessionStore` nie wczyta listy.
    ///
    /// Rozróżnienie jest tu potrzebne, bo „jeszcze nie wiem" i „jednoosobowe
    /// gospodarstwo" dają tę samą jedynkę w `eaterCount`, a tylko w drugim
    /// przypadku to prawda. Lista dojeżdża asynchronicznie (socket albo cache),
    /// więc arkusz otwarty zaraz po starcie apki widzi na początku pustkę.
    private var knownMemberCount: Int? {
        sessionStore.didLoadHouseholdMembers ? members.count : nil
    }

    /// Poniedziałek–niedziela tygodnia, w którym leży `selectedDate`.
    private var weekDates: [Date] {
        let monday = PlanWeek.monday(of: selectedDate)
        return (0..<7).compactMap {
            PlanWeek.calendar.date(byAdding: .day, value: $0, to: monday)
        }
    }

    /// Jedno przejście po tygodniu zamiast dwóch: pasek dni potrzebuje kropek
    /// „tu już coś stoi", a lista posiłków — wyłączonych slotów, w których
    /// mimo wyłączenia zostało jedzenie. Oba pytania odpowiadają tym samym
    /// zajrzeniom do planu.
    private func weekOverview(for days: [Date]) -> (plannedDays: Set<Date>, plannedSlots: [MealSlot]) {
        var plannedDays: Set<Date> = []
        var plannedSlots: Set<MealSlot> = []

        for day in days {
            for slot in MealSlot.allCases where !mealStore.meals(for: day, slot: slot).isEmpty {
                plannedDays.insert(PlanWeek.calendar.startOfDay(for: day))
                plannedSlots.insert(slot)
            }
        }

        return (plannedDays, Array(plannedSlots).sortedByDay)
    }

    /// Slot zaznaczany przy otwarciu: slot bazowy przepisu, o ile
    /// gospodarstwo ten posiłek planuje. Gdy nie planuje, spadamy na pierwszy
    /// widoczny slot, w który przepis pasuje — pusty wybór zostawiłby CTA
    /// zablokowane bez wyjaśnienia.
    ///
    /// Bazowy slot, a nie kategoria: sekcja „Przekąski i desery" zbiera trzy
    /// sloty naraz, więc z kategorii wychodziłaby zawsze przekąska — także dla
    /// koktajlu opisanego jako II śniadanie.
    private func defaultSlot(from visible: [MealSlot]) -> MealSlot? {
        if let base = recipe.primarySlot, visible.contains(base) { return base }
        return visible.first { recipe.fits($0) } ?? visible.first
    }

    private var participantsToSave: [String] {
        PlanAudienceChips.collapsed(selectedParticipants, members: members)
    }

    /// Ta sama reguła, którą Plan i Kalendarz stosują do minionych dni.
    /// Czytamy ją z `DatesViewModel`, żeby nie było w aplikacji dwóch definicji
    /// „dzień do edycji" — ta metoda niczego nie przestawia, więc nie łamie
    /// zasady, że arkusz trzyma własną datę.
    private func isEditable(_ date: Date) -> Bool {
        datesViewModel.isEditable(date)
    }

    /// Czy strzałka wstecz ma jeszcze dokąd cofać.
    ///
    /// Bieżący tydzień jest ostatnim, w którym cokolwiek da się zaplanować, więc
    /// wcześniejsze pokazywałyby tylko siedem nieklikalnych komórek.
    private var canGoToPreviousWeek: Bool {
        PlanWeek.monday(of: selectedDate) > PlanWeek.monday(of: Date())
    }

    // MARK: - Body

    var body: some View {
        let overview = weekOverview(for: weekDates)
        let visibleSlots = sessionStore.mealSlots.visibleSlots(planned: overview.plannedSlots)

        return ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Nagłówek przypięty nad treścią, jak stopka pod nią — wcześniej
                // przewijał się razem z sekcjami i krzyżyk uciekał z ekranu.
                EditorialSheetHeader(
                    eyebrow: "DODAJ DO PLANU",
                    title: recipe.name,
                    onClose: { dismiss() }
                )
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        daySection(plannedDays: overview.plannedDays)
                        slotSection(visibleSlots)

                        // Jednoosobowe gospodarstwo nie ma o czym decydować —
                        // każdy posiłek i tak jest „Wspólne".
                        if members.count > 1 {
                            PlanAudienceChips(
                                members: members,
                                selection: $selectedParticipants,
                                onChange: audienceChanged
                            )
                        }

                        servingsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    // Zapas na cień stopki (`SCEdgeShade`), który leży na liście.
                    .padding(.bottom, SCEdgeShade.bottomHeight)
                }
                .scrollIndicators(.hidden)
                .scScrollEdgeFade()
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
            // chipów nigdy się dla niego nie odpala, a wspólna kolacja w domu
            // dwuosobowym pokazywałaby (i zapisywała) jedną porcję.
            //
            // Nie da się tego zrobić w `init`: tam nie ma jeszcze środowiska,
            // czyli nie ma `sessionStore`, czyli nie ma z czego policzyć
            // domowników. `onAppear` to pierwszy moment po zainstalowaniu
            // środowiska. Bez animacji, bo użytkownik nie zdążył zobaczyć
            // wartości startowej i nie ma czego animować.
            applyAutoServings(for: selectedParticipants, animated: false)
        }
        // Drugie wejście do tej samej reguły: lista domowników dojeżdża
        // asynchronicznie, więc `onAppear` często widzi jeszcze pustkę.
        // Odczyt `knownMemberCount` dzieje się przy budowaniu body, więc
        // obserwacja `@Observable` na `SessionStore` łapie i pojawienie się
        // listy, i późniejszą zmianę jej długości.
        .onChange(of: knownMemberCount) { _, _ in
            applyAutoServings(for: selectedParticipants, animated: true)
        }
        .onChange(of: visibleSlots) { _, next in
            // Przeskok na inny tydzień potrafi schować slot, który był widoczny
            // tylko dlatego, że coś w nim stało. Zaznaczenie zostałoby wtedy na
            // kaflu, którego nie ma na ekranie.
            if let selectedSlot, !next.contains(selectedSlot) {
                self.selectedSlot = defaultSlot(from: next)
            }
        }
        .presentationDetents([.large])
        .dashboardLiquidSheet()
    }

    // MARK: - Dzień

    private func daySection(plannedDays: Set<Date>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                EditorialSheetSectionLabel(title: "Dzień")

                HStack(spacing: 8) {
                    weekArrow(
                        systemName: "chevron.left",
                        label: "Poprzedni tydzień",
                        delta: -7,
                        isEnabled: canGoToPreviousWeek
                    )

                    Text(weekCaption)
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(minWidth: 74)

                    weekArrow(
                        systemName: "chevron.right",
                        label: "Następny tydzień",
                        delta: 7,
                        isEnabled: true
                    )
                }
                // Etykieta sekcji nosi własny dolny padding — bez tego samego
                // odstępu strzałki siedziałyby niżej niż napis obok.
                .padding(.bottom, 6)
            }

            HStack(spacing: 0) {
                ForEach(weekDates, id: \.self) { date in
                    let canPlan = isEditable(date)

                    DayCell(
                        date: date,
                        isSelected: PlanWeek.calendar.isDate(date, inSameDayAs: selectedDate),
                        isPast: !canPlan,
                        isPlanned: plannedDays.contains(PlanWeek.calendar.startOfDay(for: date)),
                        indicatorNS: dayIndicatorNS
                    )
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            selectedDate = date
                        }
                    }
                    // Miniony dzień w ogóle nie łapie tapnięcia. Wpis wstecz
                    // dałoby się stąd dodać, ale nie dałoby się go już usunąć:
                    // Plan i Kalendarz pokazują przeszłe dni tylko do odczytu.
                    .allowsHitTesting(canPlan)
                }
            }
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
        }
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
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(SCPalette.terracotta)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.scChipBg(scheme)))
                .overlay(Circle().stroke(Color.scTileStroke(scheme), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    /// Przesunięcie paska o tydzień, z dwiema barierami na przeszłość.
    ///
    /// Sam `guard` na `canGoToPreviousWeek` nie wystarczy: bieżący tydzień jest
    /// zwykle w połowie, więc cofnięcie o siedem dni z przyszłego tygodnia
    /// potrafi wylądować na dniu, który już minął. Zaznaczenie stanęłoby wtedy
    /// na nieklikalnej komórce, a CTA dalej próbowałoby zapisać wpis wstecz —
    /// dlatego w takim wypadku podciągamy wybór do dziś.
    private func shiftWeek(by delta: Int) {
        guard delta > 0 || canGoToPreviousWeek else { return }
        guard let shifted = PlanWeek.calendar.date(
            byAdding: .day,
            value: delta,
            to: selectedDate
        ) else { return }

        let target = isEditable(shifted) ? shifted : Date()
        withAnimation(.smooth(duration: 0.22)) { selectedDate = target }
    }

    /// Podpis nad paskiem. Tydzień potrafi przeciąć miesiąc, a wtedy sam
    /// „Sierpień" kłamie o połowie komórek.
    private var weekCaption: String {
        let days = weekDates
        guard let first = days.first, let last = days.last else { return "" }

        let firstMonth = Self.monthFormatter.string(from: first)
        let lastMonth = Self.monthFormatter.string(from: last)
        if firstMonth == lastMonth { return firstMonth.uppercased() }
        return "\(firstMonth.uppercased()) / \(lastMonth.uppercased())"
    }

    // MARK: - Posiłek

    private func slotSection(_ slots: [MealSlot]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorialSheetSectionLabel(title: "Posiłek")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(slots) { slot in
                    slotTile(slot)
                }
            }

            if slots.contains(where: { !recipe.fits($0) }) {
                offSlotNote
            }
        }
    }

    private func slotTile(_ slot: MealSlot) -> some View {
        let isSelected = slot == selectedSlot
        let fits = recipe.fits(slot)

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                selectedSlot = slot
            }
        } label: {
            HStack(spacing: 10) {
                EditorialSettingsTileIcon(
                    icon: slot.icon,
                    color: slot.cozyAccent,
                    size: 32,
                    radius: 10
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(slot.title)
                        .font(.system(size: 13.5, weight: .bold))
                        .tracking(-0.2)
                        .foregroundStyle(isSelected ? Color.scLabel(scheme) : Color.scMuted(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    // Co już stoi w tym slocie. Bez tego wybór zajętego slotu
                    // wyglądał jak wybór pustego, a przycisk na dole po cichu
                    // zmieniał znaczenie z „dodaj" na „zmień".
                    if let taken = occupiedBy(slot) {
                        Text(taken)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.scFaint(scheme))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isSelected
                            ? SCPalette.terracotta.opacity(scheme == .dark ? 0.16 : 0.10)
                            : Color.scTileBg(scheme)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected
                            ? SCPalette.terracotta.opacity(scheme == .dark ? 0.55 : 0.42)
                            : Color.scTileStroke(scheme),
                        lineWidth: isSelected ? 1.4 : 1
                    )
            )
            // Przygaszenie zamiast blokady: przepis spoza slotu wolno wstawić,
            // tylko nie jest pierwszym wyborem.
            .opacity(fits ? 1 : 0.55)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(fits ? slot.title : "\(slot.title), przepis nie jest pod to oznaczony")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Wyjaśnia przygaszone kafle. Bez tego wyglądają na zepsute albo
    /// zablokowane — a wolno w nie stuknąć: czasem na podwieczorek je się
    /// wczorajszy obiad i aplikacja nie ma prawa tego zabronić.
    private var offSlotNote: some View {
        Text("Przygaszone posiłki też możesz wybrać — przepis po prostu nie jest pod nie oznaczony.")
            .font(.system(size: 11.5, weight: .regular))
            .foregroundStyle(Color.scFaint(scheme))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
    }

    // MARK: - Porcje

    private var servingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorialSheetSectionLabel(title: "Porcje")

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(PolishPlural.servings(servings))
                        .font(.system(size: 16, weight: .heavy))
                        .tracking(-0.3)
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(scheme))

                    Text(servingsHint)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(Color.scFaint(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SCStepper(
                    value: $servings,
                    accessibilityTitle: "Liczba porcji",
                    accessibilityValue: PolishPlural.servings(servings),
                    onChange: { _ in didOverrideServings = true }
                )
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
        }
    }

    /// Podpis musi opisywać stan, w którym stepper naprawdę jest.
    ///
    /// „Tyle, ile osób je to danie" jest prawdą dopiero od C1 — wcześniej
    /// arkusz startował od jedynki niezależnie od audytorium. Zostaje jeszcze
    /// jedna dziura: dopóki lista domowników nie dojedzie, przy „Wspólne" nie
    /// mamy z czego policzyć jedzących. Liczbę wyliczy wtedy serwer (patrz
    /// `save()`), więc podpis obiecuje dokładnie to, a nie liczbę na stepperze.
    private var servingsHint: String {
        if didOverrideServings {
            return "Twoja liczba — chipy \u{201E}dla kogo\u{201D} już jej nie zmienią."
        }
        if selectedParticipants.isEmpty, knownMemberCount == nil {
            return "Tyle, ile osób je to danie — dokładną liczbę ustalimy przy zapisie."
        }
        return "Tyle, ile osób je to danie. Zmień, jeśli gotujesz na zapas."
    }

    // MARK: - Stopka

    // Bez czerwonego wiersza z `mealStore.errorMessage`. Nie był duplikatem
    // toastu — był gorszy: `save()` woła `dismiss()` synchronicznie, więc ten
    // wiersz nigdy nie mógł pokazać błędu WŁASNEGO zapisu. Jedyne, co potrafił
    // wyrenderować, to nieświeży komunikat zostawiony w store przez coś
    // wcześniejszego. Błędy store jadą mostem z korzenia aplikacji.
    private var footer: some View {
        // Wspólna stopka arkuszy — płyta w kolorze tła i miękkie przejście
        // nad nią zamiast półprzezroczystego pasa z kreską.
        SCSheetFooter {
            EditorialPrimaryActionButton(
                title: ctaTitle,
                icon: "calendar.badge.plus",
                isEnabled: canSave,
                isLoading: isSaving,
                action: { save() }
            )
        }
    }

    // MARK: - Akcje

    /// Chipy audytorium ruszyły — przelicz porcje po tej samej regule.
    ///
    /// Selekcja przychodzi parametrem, a nie z `selectedParticipants`: widok
    /// jest strukturą, więc w domknięciu `onChange` siedzi jeszcze wartość
    /// sprzed zapisu do bindingu.
    private func audienceChanged(_ selection: Set<String>) {
        applyAutoServings(for: selection, animated: true)
    }

    /// Reguła auto-porcji po stronie klienta — bliźniacza do tej, którą serwer
    /// stosuje, gdy `plannedServings` nie przyjdzie w payloadzie.
    ///
    /// Wołana z trzech miejsc: przy otwarciu arkusza, po dojechaniu listy
    /// domowników i po każdej zmianie chipów. Dwa pierwsze wejścia są tu
    /// najważniejsze — domyślne „Wspólne" nie jest niczyim tapnięciem, więc
    /// bez nich reguła nie odpaliłaby ani razu.
    private func applyAutoServings(for selection: Set<String>, animated: Bool) {
        // Ręczny wybór wygrywa ze zgadywaniem — i to na zawsze, bo cofnąć go
        // może tylko sam stepper.
        guard !didOverrideServings else { return }

        // „Wspólne" liczy się z liczby domowników, a tej jeszcze nie znamy.
        // Wpisanie tu jedynki byłoby zgadywaniem, które w domu dwuosobowym
        // wygląda jak decyzja użytkownika — lepiej zostawić wartość startową
        // i przeliczyć, gdy lista dojedzie.
        if selection.isEmpty, knownMemberCount == nil { return }

        let eaters = min(12, max(1, PlanAudienceChips.eaterCount(selection, memberCount: members.count)))
        guard eaters != servings else { return }

        if animated {
            withAnimation(.smooth(duration: 0.18)) { servings = eaters }
        } else {
            servings = eaters
        }
    }

    /// Posiłek, który ten zapis zastąpi: ten sam dzień, ten sam slot i to samo
    /// audytorium.
    ///
    /// Porównujemy audytoria, a nie sam slot, bo slot z założenia mieści kilka
    /// posiłków — na tym stoi „Każdy je inaczej". Kolizją jest dopiero drugie
    /// danie dla TYCH SAMYCH osób: dwa śniadania „Wspólne" tego samego dnia to
    /// nie podział, tylko pomyłka.
    private var conflictingMeal: PlanMeal? {
        guard let selectedSlot else { return nil }
        let audience = Set(participantsToSave)
        return mealStore
            .meals(for: selectedDate, slot: selectedSlot)
            .first { Set($0.participantIds) == audience }
    }

    /// Ten sam przepis już tu stoi — nie ma czego zapisywać.
    private var isAlreadyPlanned: Bool {
        conflictingMeal?.recipe.id == recipe.id
    }

    /// Nazwa dania, które zajmuje dany slot wybranego dnia. Pokazywana na
    /// kaflu, żeby zajęty slot było widać PRZED tapnięciem w „Dodaj".
    private func occupiedBy(_ slot: MealSlot) -> String? {
        let audience = Set(participantsToSave)
        let meals = mealStore.meals(for: selectedDate, slot: slot)
        let mine = meals.first { Set($0.participantIds) == audience }
        return (mine ?? meals.first)?.recipe.name
    }

    private var ctaTitle: String {
        if isAlreadyPlanned { return "Ten przepis już tu jest" }
        if conflictingMeal != nil { return "Zmień · \(PolishPlural.servings(servings))" }
        return "Dodaj · \(PolishPlural.servings(servings))"
    }

    /// CTA jest aktywne tylko dla dnia, który plan jeszcze przyjmie.
    /// Sam pasek dni już tego pilnuje, ale arkusz potrafi zostać otwarty przez
    /// północ — wtedy zaznaczony „dziś" staje się „wczoraj" pod ręką.
    private var canSave: Bool {
        selectedSlot != nil && isEditable(selectedDate) && !isAlreadyPlanned
    }

    private func save() {
        guard let slot = selectedSlot, !isSaving, isEditable(selectedDate), !isAlreadyPlanned else { return }
        isSaving = true
        let date = selectedDate
        // Zajęty slot podmieniamy, zamiast dokładać obok. Bez tego drugie
        // „Wspólne" śniadanie tego samego dnia wjeżdżało do bazy jako osobny
        // wpis, którego plan i tak nie pokazywał — z perspektywy użytkownika
        // przycisk po prostu nic nie robił.
        let replacing = conflictingMeal?.recipe.id
        // Nazwę wypieranego dania trzeba wziąć TERAZ. Po zapisie
        // optymistycznym `conflictingMeal` zwraca już nowe danie i nie ma
        // z czego powiedzieć, co zniknęło.
        let replacedName = conflictingMeal?.recipe.name

        // Dismiss od razu, jak w PlanSlotPickerSheet: wpis optymistyczny
        // w store ląduje przed siecią, więc nie trzymamy arkusza przez cały
        // round-trip. Błąd wraca rollbackiem i `errorMessage` w store.
        //
        // Kolejkę toastów i gotowe zdanie bierzemy do stałych PRZED zadaniem:
        // arkusz jest zamykany synchronicznie kilka linijek niżej, a wtedy
        // jego środowisko już nie istnieje. Sama kolejka żyje w korzeniu
        // aplikacji i przeżywa zamknięcie bez szwanku.
        let store = mealStore
        let toasts = toasts
        // Nazwy pory NIE zniżamy: „II śniadanie" wyszłoby jako „ii śniadanie".
        // Po kropce wielka litera i tak czyta się naturalnie.
        let placement = "\(Self.dayName(for: date)) · \(slot.title)"
        // Zapamiętane, żeby po `await` odróżnić „most już to pokazał" od
        // „nic się nie zmieniło". Sam warunek `errorMessage == nil` na to nie
        // wystarcza: dwa identyczne błędy pod rząd nie są dla mostu zmianą,
        // więc nie pokazałby ich ani on, ani my.
        let errorBefore = store.errorMessage
        Task { @MainActor in
            let saved = await store.upsertWeekSlot(
                recipe: recipe,
                participantIds: participantsToSave,
                // Wysyłamy liczbę tylko wtedy, gdy jest wyborem użytkownika.
                // Pominięcie pola znaczy dla serwera „policz sam z audytorium",
                // a on liczy to na świeżej liście domowników — w odróżnieniu od
                // klienta, który może mieć nieaktualną albo jeszcze żadną.
                // Jawna jedynka z takiej sytuacji byłaby kłamstwem nie do
                // odróżnienia od świadomego „gotuję jedną porcję".
                plannedServings: didOverrideServings ? servings : nil,
                householdMemberCount: members.isEmpty ? nil : members.count,
                replacingRecipeId: replacing,
                for: date,
                slot: slot,
                weekStart: PlanWeek.dateKey(PlanWeek.monday(of: date))
            )

            guard saved else {
                // Jedyna naprawdę cicha awaria na tej ścieżce. Błąd łączności
                // NIE ustawia `errorMessage` (mapper oddaje na niego `nil`),
                // więc most z korzenia nie ma czego pokazać i użytkownik
                // odchodzi przekonany, że posiłek jest w planie.
                //
                // Podtytuł mówi wyłącznie o skutku po naszej stronie. Diagnozy
                // łączności tu nie ma i być nie może: brak sieci ma w tej
                // aplikacji jedno miejsce — trwały pasek u góry — a dopisane
                // tutaj „sprawdź połączenie" wyprzedzałoby go o sześć sekund
                // i mówiło to samo dwa razy, w tej samej kapsule.
                if store.errorMessage == errorBefore {
                    toasts.error("Nie udało się dodać do planu", "Plan został bez zmian.")
                }
                return
            }

            // Zajęty slot znaczy, że coś stąd zniknęło — i tylko nazwa mówi,
            // co. W gospodarstwie mógł to postawić ktoś inny. Prefiks ustępuje
            // wtedy miejsca nazwie: podtytuł ma dwie linie, a nazwa dania jest
            // jedynym powodem, dla którego ten toast w ogóle istnieje.
            if let replacedName {
                toasts.success("Zamieniono w planie", "\(slot.title) — zamiast: \(replacedName)")
            } else {
                toasts.success("Dodano do planu", placement)
            }
        }
        onAdded?(date, slot)
        dismiss()
    }

    /// Dzień z datą, nie sam dzień tygodnia: ten arkusz ma własny pasek dni
    /// i da się go przewinąć na kolejny tydzień, więc „czwartek" bywa
    /// dwuznaczny. Polski formatter oddaje nazwę dnia z małej litery, a to
    /// początek zdania.
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

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "LLLL"
        return formatter
    }()

    // MARK: - Komórka dnia

    /// Wygląd przeniesiony z `EditorialWeekBar`, ale bez `DatesViewModel`:
    /// zaznaczenie jest tu stanem formularza, nie nawigacją po aplikacji.
    private struct DayCell: View {
        let date: Date
        let isSelected: Bool
        let isPast: Bool
        let isPlanned: Bool
        let indicatorNS: Namespace.ID

        @Environment(\.colorScheme) private var scheme

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

        var body: some View {
            let label = Color.scLabel(scheme)
            let muted = Color.scMuted(scheme)

            VStack(spacing: 4) {
                Text(Self.shortDayFormatter.string(from: date).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(isSelected ? label : muted)

                Text(Self.dayNumberFormatter.string(from: date))
                    .font(.system(size: 18, weight: isSelected ? .heavy : .semibold))
                    .tracking(-0.3)
                    .monospacedDigit()
                    .foregroundStyle(isPast ? muted : label)
                    .strikethrough(isPast, color: Color.scStrike(scheme))

                ZStack {
                    // Wysokość rezerwowana z góry, żeby układ nie skakał, gdy
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
                            .matchedGeometryEffect(id: "addToPlan.dayIndicator", in: indicatorNS)
                    }
                }
                .frame(height: 4)
                .padding(.top, 4)
            }
            .padding(.vertical, 6)
            // Przekreślenie samo w sobie czyta się jak „nic tu dziś nie jem",
            // a nie jak „tego dnia nie da się wybrać". Przygaszenie całej
            // komórki mówi to samo, co jej brak reakcji na tapnięcie.
            .opacity(isPast ? 0.45 : 1)
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        private var accessibilityLabel: String {
            let day = DateFormatter.localizedString(from: date, dateStyle: .full, timeStyle: .none)
            if isPast { return "\(day), minął, nie można planować" }
            if isPlanned { return "\(day), zaplanowany" }
            return day
        }
    }
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
