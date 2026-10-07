import SwiftUI

/// „Twój dzień” — pionowa oś dnia ze wszystkimi sześcioma porami w kolejności
/// doby (wersja 4 · czytelnie, 6.10.2026). JEDNA dla Ustawień → „Posiłki
/// w planie” (`MealSlotsSheet`) i kroku „Posiłki” kreatora (`WelcomeMealsStep`).
///
/// Włączona pora = godzina dużą cyfrą, kółko w kolorze pory na linii dnia,
/// pełna nazwa i szewron — stuknięcie otwiera koło godzin w arkuszu na 1/3
/// ekranu (`MealTimeEditorSheet`). Pora, której dom nie je, stoi przygaszona
/// W SWOIM miejscu z pigułką „Dodaj”. Wyłączenie pory dodatkowej: przesunięcie
/// wiersza w lewo (jak usuwanie w Mailu), przytrzymanie albo „Wyłącz” obok
/// krzyżyka w okienku godziny. Dlatego treść to `List(.insetGrouped)` —
/// `swipeActions` działa tylko w liście, i to tylko w PRZEWIJANEJ
/// (`scrollDisabled` wyłącza też przesunięcie).
///
/// 7.10.2026 (Rafał: „zrób na onboarding user te nowe widoki z ustawień…”):
/// kreator miał własną poziomą oś (`MealDayTimesCard`, usunięta) i osobne
/// karty „Dodatkowe posiłki”. Teraz oba miejsca stoją na tej liście; widok
/// niczego nie zapisuje — oddaje zmiany wyżej. Ustawienia zapisują od razu
/// (i pytają, gdy w porze stoją dania), kreator trzyma wybór lokalnie do
/// utworzenia gospodarstwa.
struct MealDayAxisList<Top: View, Status: View>: View {
    let configuration: MealSlotConfiguration
    let schedule: MealSlotSchedule
    /// Ile dań stoi w porze w oglądanym tygodniu — podpis „W tym tygodniu: N”
    /// przy wyłączonej porze. Kreator: zawsze 0 (domu jeszcze nie ma).
    let plannedCount: (MealSlot) -> Int
    /// Włączenie / wyłączenie pory z listy („Dodaj”, przesunięcie, menu).
    let onSetEnabled: (MealSlot, Bool) -> Void
    /// Wyłączenie z okienka godziny — okienko już schodzi, więc ewentualne
    /// pytanie musi poczekać (Ustawienia). `nil` = jak z listy.
    let onDisableFromEditor: ((MealSlot) -> Void)?
    /// Nowa pora w minutach od północy; `nil` = bez stałej pory.
    let onSetTime: (MealSlot, Int?) -> Void
    let onResetTimes: () -> Void
    /// Treść NAD kartą, przewijana razem z nią (nagłówek kroku kreatora).
    let showsTop: Bool
    let topMargin: CGFloat
    @ViewBuilder let top: () -> Top
    /// Stan zapisu pod kartą (Ustawienia: błąd i „Spróbuj ponownie”).
    @ViewBuilder let status: () -> Status

    @Environment(\.colorScheme) private var scheme

    /// Pora, której godzinę zmienia teraz okienko z kołem (wiersz podświetlony).
    @State private var editing: MealSlot?
    /// Liczniki „pop” świeżo dodanych pór — wyzwalacz `keyframeAnimator`.
    @State private var popCounts: [MealSlot: Int] = [:]

    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 56

    init(
        configuration: MealSlotConfiguration,
        schedule: MealSlotSchedule,
        plannedCount: @escaping (MealSlot) -> Int,
        onSetEnabled: @escaping (MealSlot, Bool) -> Void,
        onDisableFromEditor: ((MealSlot) -> Void)? = nil,
        onSetTime: @escaping (MealSlot, Int?) -> Void,
        onResetTimes: @escaping () -> Void,
        topMargin: CGFloat = 0,
        @ViewBuilder top: @escaping () -> Top,
        @ViewBuilder status: @escaping () -> Status
    ) {
        self.configuration = configuration
        self.schedule = schedule
        self.plannedCount = plannedCount
        self.onSetEnabled = onSetEnabled
        self.onDisableFromEditor = onDisableFromEditor
        self.onSetTime = onSetTime
        self.onResetTimes = onResetTimes
        self.showsTop = true
        self.topMargin = topMargin
        self.top = top
        self.status = status
    }

    var body: some View {
        // Kolejność liczona po porach, które są w dniu (wiersze z godziną).
        let pair = schedule.outOfOrderPair(among: configuration.enabled)

        // Cała treść to `List`, bo tylko lista daje systemowe `swipeActions`
        // („Wyłącz” przesunięciem). Lista MUSI się przewijać — `scrollDisabled`
        // wyłącza też gest przesunięcia (tak nie działało „Wyłącz” w pierwszej
        // wersji, 6.10.2026). `insetGrouped` rysuje kartę z zaokrąglonymi
        // rogami sam.
        List {
            if showsTop {
                Section {
                    top()
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                ForEach(Array(MealSlot.allCases.enumerated()), id: \.element) { index, slot in
                    axisRow(
                        slot,
                        isFirst: index == 0,
                        isLast: index == MealSlot.allCases.count - 1,
                        isShown: configuration.isEnabled(slot),
                        warning: pair?.later == slot ? pair?.earlier : nil
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.scTileBg(scheme))
                    // To samo pod przytrzymaniem — gest przesunięcia nie każdy zna.
                    .contextMenu {
                        if configuration.isEnabled(slot), MealSlot.optionalSlots.contains(slot) {
                            Button(role: .destructive) {
                                onSetEnabled(slot, false)
                            } label: {
                                Label("Wyłącz \(slot.accusativeName)", systemImage: "minus.circle")
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if configuration.isEnabled(slot), MealSlot.optionalSlots.contains(slot) {
                            Button(role: .destructive) {
                                onSetEnabled(slot, false)
                            } label: {
                                Label("Wyłącz", systemImage: "minus.circle")
                            }
                            .tint(.red)
                        }
                    }
                }

                if pair != nil {
                    orderNotice
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.scTileBg(scheme))
                }
            } header: {
                EditorialSheetSectionLabel(title: "Twój dzień")
                    .textCase(nil)
            } footer: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Wspólne dla całego domu. Śniadanie, obiad i kolacja są zawsze. Dodatkową porę wyłączysz, przesuwając ją w lewo.")
                        .font(.sc(size: 12.5, weight: .regular))
                        .foregroundStyle(Color.scFaint(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    if !schedule.isDefault {
                        Button("Przywróć domyślne godziny") {
                            onResetTimes()
                        }
                        .font(.sc(size: 12.5, weight: .semibold))
                        .foregroundStyle(SCPalette.terracotta)
                        .buttonStyle(.plain)
                    }

                    status()
                }
                .textCase(nil)
                .padding(.top, 4)
            }
        }
        .listStyle(.insetGrouped)
        .listRowSpacing(0)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .contentMargins(.top, topMargin, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scScrollEdgeFade()
        .animation(.smooth(duration: 0.22), value: configuration.enabled)
        .animation(.smooth(duration: 0.22), value: pair == nil)
        .animation(.smooth(duration: 0.22), value: schedule.isDefault)
        // Koło godzin we własnym arkuszu, nie w karcie: `DatePicker(.wheel)`
        // przejmuje pionowe przeciągnięcia i w przewijanej treści zjadał
        // przewijanie oraz gest zamknięcia arkusza.
        .sheet(item: $editing) { slot in
            editorSheet(slot)
                // Jedna trzecia ekranu — nad nią dalej widać oś dnia.
                // Pory dodatkowe mają „Wyłącz” obok krzyżyka i koło w pełnych
                // 216 pt (ściśnięte wystawało nad nagłówek i zjadało stuknięcie).
                .presentationDetents([MealSlot.optionalSlots.contains(slot) ? .height(370) : .fraction(1.0 / 3.0)])
                .dashboardLiquidSheet(cornerRadius: 26)
        }
    }

    // MARK: - Oś dnia

    /// Ostatni wiersz karty, gdy godziny nie idą po kolei.
    private var orderNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.sc(size: 11.5, weight: .semibold))
                .foregroundStyle(SCPalette.terracotta)

            Text("Plan i tak pokaże posiłki w stałej kolejności dnia.")
                .font(.sc(size: 12.5, weight: .regular))
                .foregroundStyle(Color.scMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    /// Wiersz osi. `isShown` — pora jest w dniu Planu; inaczej stoi
    /// przygaszona z „Dodaj”.
    ///
    /// „Pop” siedzi na kontenerze, nie na wierszu włączonej pory: licznik
    /// rośnie przy stuknięciu w „Dodaj”, zanim konfiguracja przestawi wiersz,
    /// a animator wstawiony razem z nowym wierszem nie zagrałby wcale.
    private func axisRow(
        _ slot: MealSlot,
        isFirst: Bool,
        isLast: Bool,
        isShown: Bool,
        warning: MealSlot?
    ) -> some View {
        ZStack {
            if isShown {
                onRow(
                    slot,
                    isFirst: isFirst,
                    isLast: isLast,
                    isDimmed: !configuration.isEnabled(slot),
                    warning: warning
                )
            } else {
                offRow(slot, isFirst: isFirst, isLast: isLast, planned: plannedCount(slot))
            }
        }
        .keyframeAnimator(initialValue: 1.0, trigger: popCounts[slot] ?? 0) { row, scale in
            row.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(1.04, duration: 0.12, spring: .snappy)
                SpringKeyframe(1, duration: 0.3, spring: .bouncy)
            }
        }
    }

    private func onRow(
        _ slot: MealSlot,
        isFirst: Bool,
        isLast: Bool,
        isDimmed: Bool,
        warning: MealSlot?
    ) -> some View {
        let time = schedule.time(for: slot)
        let isEditing = editing == slot
        let timeColor: Color = (warning != nil || isEditing)
            ? SCPalette.terracotta
            : Color.scLabel(scheme)

        return Button {
            editing = slot
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let time {
                        Text(time)
                            .font(.sc(size: 18, weight: .bold))
                            .tracking(-0.3)
                            .monospacedDigit()
                            .foregroundStyle(timeColor)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("kiedy\nchcesz")
                            .font(.sc(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color.scMuted(scheme))
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                    }
                }
                .frame(width: 62, alignment: .trailing)

                axisMark(isFirst: isFirst, isLast: isLast, gap: 30 + 8) {
                    Image(systemName: slot.icon)
                        .font(.sc(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(slot.cozyAccent))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(slot.title)
                        .font(.sc(size: 16, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(1)

                    if let warning {
                        Text(warningText(earlier: warning))
                            .font(.sc(size: 12.5, weight: .medium))
                            .foregroundStyle(SCPalette.terracotta)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.sc(size: 13, weight: .semibold))
                    .foregroundStyle(Color.scFaint(scheme))
            }
            .padding(.leading, 14)
            .padding(.trailing, 14)
            .frame(height: rowHeight)
            .opacity(isDimmed ? 0.5 : 1)
            .background(SCPalette.terracotta.opacity(isEditing ? 0.08 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle())
        .animation(.smooth(duration: 0.22), value: time)
        .animation(.smooth(duration: 0.2), value: isEditing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(slot.title), \(time ?? "bez stałej pory")")
        .accessibilityHint("Stuknij, aby zmienić porę")
        .accessibilityAddTraits(.isButton)
    }

    /// Pora, której dom nie je: na swoim miejscu, przygaszona, z „Dodaj”.
    private func offRow(_ slot: MealSlot, isFirst: Bool, isLast: Bool, planned: Int) -> some View {
        HStack(spacing: 10) {
            Text(schedule.time(for: slot) ?? "—")
                .font(.sc(size: 18, weight: .medium))
                .tracking(-0.3)
                .monospacedDigit()
                .foregroundStyle(Color.scFaint(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 62, alignment: .trailing)

            axisMark(isFirst: isFirst, isLast: isLast, gap: 14 + 12) {
                Circle()
                    .strokeBorder(
                        slot.cozyAccent.opacity(0.6),
                        style: StrokeStyle(lineWidth: 2, dash: [3, 2.5])
                    )
                    .frame(width: 14, height: 14)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(slot.title)
                    .font(.sc(size: 16, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)

                // Wyłączona, ale w tym tygodniu zostały w niej dania — Plan
                // dalej ją pokazuje, więc mówimy, dlaczego.
                if planned > 0 {
                    Text("W tym tygodniu: \(planned) \(Self.dishesPlural(planned))")
                        .font(.sc(size: 12.5, weight: .regular))
                        .foregroundStyle(Color.scFaint(scheme))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                popCounts[slot, default: 0] += 1
                onSetEnabled(slot, true)
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "plus")
                        .font(.sc(size: 13, weight: .semibold))
                    Text("Dodaj")
                        .font(.sc(size: 13.5, weight: .semibold))
                }
                .foregroundStyle(Color.scLabel(scheme))
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .frame(height: 32)
                .scChromeGlass(in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(PlanPressStyle(scale: 0.94))
            .accessibilityLabel("Dodaj \(slot.accusativeName)")
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(height: rowHeight)
    }

    /// Znak pory na linii dnia. Linia to dwa odcinki — nad i pod znakiem —
    /// z przerwą `gap`, a nie jedna kreska pod kółkami: tło karty jest
    /// półprzezroczyste, więc „obwódka w kolorze tła” nie zakryłaby kreski.
    /// Pierwszy wiersz nie ma odcinka u góry, ostatni u dołu.
    private func axisMark<Mark: View>(
        isFirst: Bool,
        isLast: Bool,
        gap: CGFloat,
        @ViewBuilder mark: () -> Mark
    ) -> some View {
        let rule = Color.scRule(scheme)

        return ZStack {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : rule)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                Color.clear
                    .frame(width: 2, height: gap)
                Rectangle()
                    .fill(isLast ? Color.clear : rule)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            mark()
        }
        .frame(width: 30)
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    private func warningText(earlier: MealSlot) -> String {
        let time = schedule.time(for: earlier).map { " (\($0))" } ?? ""
        return "Nie później niż \(earlier.lowercaseName)\(time)"
    }

    // MARK: - Okienko godziny

    private func editorSheet(_ slot: MealSlot) -> some View {
        MealTimeEditorSheet(
            slot: slot,
            minutes: schedule.minutes(for: slot),
            onPick: { picked in
                guard picked != schedule.minutes(for: slot) else { return }
                onSetTime(slot, picked)
            },
            onClearTime: {
                editing = nil
                onSetTime(slot, nil)
            },
            onClose: { editing = nil },
            inPlan: inPlanToggle(for: slot)
        )
    }

    /// „Wyłącz” / „Włącz” obok krzyżyka — tylko przy porach dodatkowych
    /// (obowiązkowych nie da się wyłączyć). Wyłączenie od razu zamyka okienko
    /// (oś pod spodem pokazuje skutek); włączenie zostawia je otwarte, bo
    /// zwykle chce się od razu ustawić godzinę.
    private func inPlanToggle(for slot: MealSlot) -> MealTimeEditorSheet.InPlan? {
        guard MealSlot.optionalSlots.contains(slot) else { return nil }
        return MealTimeEditorSheet.InPlan(
            isOn: configuration.isEnabled(slot),
            set: { isOn in
                if isOn {
                    popCounts[slot, default: 0] += 1
                    onSetEnabled(slot, true)
                } else {
                    editing = nil
                    if let onDisableFromEditor {
                        onDisableFromEditor(slot)
                    } else {
                        onSetEnabled(slot, false)
                    }
                }
            }
        )
    }

    /// Polska liczba mnoga: 1 danie, 2–4 dania, 5–21 dań, 22 dania…
    /// Reguła idzie po ostatniej cyfrze z wyjątkiem nastek.
    private static func dishesPlural(_ count: Int) -> String {
        if count == 1 { return "danie" }
        let lastTwo = count % 100
        if (12...14).contains(lastTwo) { return "dań" }
        return (2...4).contains(count % 10) ? "dania" : "dań"
    }
}

extension MealDayAxisList where Top == EmptyView {
    /// Sama oś (Ustawienia: nagłówek arkusza stoi nad listą).
    init(
        configuration: MealSlotConfiguration,
        schedule: MealSlotSchedule,
        plannedCount: @escaping (MealSlot) -> Int,
        onSetEnabled: @escaping (MealSlot, Bool) -> Void,
        onDisableFromEditor: ((MealSlot) -> Void)? = nil,
        onSetTime: @escaping (MealSlot, Int?) -> Void,
        onResetTimes: @escaping () -> Void,
        @ViewBuilder status: @escaping () -> Status
    ) {
        self.configuration = configuration
        self.schedule = schedule
        self.plannedCount = plannedCount
        self.onSetEnabled = onSetEnabled
        self.onDisableFromEditor = onDisableFromEditor
        self.onSetTime = onSetTime
        self.onResetTimes = onResetTimes
        self.showsTop = false
        self.topMargin = 0
        self.top = { EmptyView() }
        self.status = status
    }
}

/// Polska liczba mnoga posiłków: 1 posiłek, 2–4 posiłki, 5–21 posiłków…
/// Wspólna dla podpisu „N posiłki w dniu” w Ustawieniach i w kreatorze.
enum MealCountText {
    static func inDay(_ count: Int) -> String {
        "\(count) \(plural(count)) w dniu"
    }

    static func plural(_ count: Int) -> String {
        if count == 1 { return "posiłek" }
        let lastTwo = count % 100
        if (12...14).contains(lastTwo) { return "posiłków" }
        return (2...4).contains(count % 10) ? "posiłki" : "posiłków"
    }
}

// MARK: - Edytor pory

/// Koło godzin dla jednego posiłku, we własnym arkuszu na 1/3 ekranu.
///
/// Powód istnienia tego widoku jako osobnego arkusza: `DatePicker(.wheel)`
/// przejmuje pionowe przeciągnięcia w swoim obszarze i **nie da się** tego
/// wyłączyć. Wstawione w `ScrollView` zjadało przewijanie listy i gest
/// zamknięcia arkusza. Tutaj nic nie przewija się pod spodem, więc koło może
/// sobie łapać wszystko, co chce — a arkusz zamyka się uchwytem, krzyżykiem
/// albo stuknięciem w tło.
///
/// Godzina zapisuje się sama przy każdym obrocie koła (`onPick`), więc nie
/// ma czego zatwierdzać: zamyka się krzyżykiem, jak każdy arkusz, a nie
/// przyciskiem „Gotowe”, który udawał zapis.
///
/// Przy porach dodatkowych oś podaje `inPlan` — obok krzyżyka stoi „Wyłącz”
/// (albo „Włącz”, gdy pora jest wyłączona). Od 7.10.2026 w Ustawieniach
/// i w kreatorze tak samo (`MealDayAxisList`).
struct MealTimeEditorSheet: View {
    /// Czy pora dodatkowa jest w dniu — przycisk obok krzyżyka.
    /// (6.10.2026: czerwony „Wyłącz …” pod kołem „totalnie nie pasował”,
    /// przełącznik nad kołem też nie; 7.10.2026 Rafał: „obok X na sheet
    /// button wyłącz”.)
    struct InPlan {
        let isOn: Bool
        let set: (Bool) -> Void
    }

    let slot: MealSlot
    let minutes: Int?
    let onPick: (Int) -> Void
    let onClearTime: () -> Void
    let onClose: () -> Void
    let inPlan: InPlan?

    @Environment(\.colorScheme) private var scheme

    /// Czy pora jest w dniu — lokalnie, żeby przycisk i koło zmieniły się od
    /// razu, zanim zapis (i zamknięcie okienka) dojdą z góry.
    @State private var isInPlan: Bool

    /// Kopia lokalna: koło pisze tu na każdą klatkę przeciągnięcia,
    /// a dalej idzie dopiero wartość różna od zapisanej.
    @State private var selection: Date

    init(
        slot: MealSlot,
        minutes: Int?,
        onPick: @escaping (Int) -> Void,
        onClearTime: @escaping () -> Void,
        onClose: @escaping () -> Void,
        inPlan: InPlan? = nil
    ) {
        self.slot = slot
        self.minutes = minutes
        self.onPick = onPick
        self.onClearTime = onClearTime
        self.onClose = onClose
        self.inPlan = inPlan
        _isInPlan = State(initialValue: inPlan?.isOn ?? true)
        let start = minutes ?? MealSlotSchedule.snackSuggestedMinutes
        _selection = State(initialValue: MealSlotSchedule.date(fromMinutes: start))
    }

    var body: some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                EditorialSheetHeader(
                    eyebrow: "Pora posiłku",
                    title: slot.title,
                    icon: slot.icon,
                    accent: slot.cozyAccent,
                    compact: true,
                    onClose: onClose
                ) {
                    if inPlan != nil {
                        inPlanButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 2)
                // Nad kołem także w kolejności dotyku: `UIDatePicker` ma
                // naturalne 216 pt i ściśnięty do 150 łapał dotyk nad sobą
                // (6.10.2026 — akcja obok krzyżyka nie reagowała).
                .zIndex(1)

                DatePicker(
                    "",
                    selection: $selection,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.wheel)
                // Bez wymuszonej lokalizacji telefon w en_US pokaże AM/PM,
                // a cała reszta aplikacji rysuje godziny jako „%02d:%02d".
                .environment(\.locale, Locale(identifier: "pl_PL"))
                .frame(maxWidth: .infinity)
                // Niższe niż naturalne 216 pt, żeby zmieścić się w trzeciej
                // części ekranu — koło pokazuje wtedy mniej wierszy, ale dalej
                // kręci się tak samo. Na małych telefonach schodzi do 100.
                // Z „Wyłącz” w nagłówku koło ma pełne 216 pt (okienko jest
                // na to wyższe): nieściśnięte nie wystaje nad nagłówek, więc
                // nie zabiera stuknięcia przyciskowi obok krzyżyka.
                .frame(minHeight: 100, maxHeight: inPlan != nil ? 216 : 150)
                .clipped()
                .layoutPriority(1)
                .padding(.horizontal, 20)
                // Pora wyłączona — godzina zostaje, ale nie ma czego ustawiać.
                .opacity(isInPlan ? 1 : 0.35)
                .disabled(!isInPlan)
                .animation(.smooth(duration: 0.2), value: isInPlan)

                // Zdjąć porę można wyłącznie tam, gdzie model na to pozwala.
                // Przy pozostałych slotach `setting(_:toMinutes: nil)` jest
                // no-opem i UI nie ma prawa udawać, że zmiana przeszła.
                if !MealSlotSchedule.slotsRequiringTime.contains(slot) {
                    Button("Bez stałej pory", action: onClearTime)
                        .font(.sc(size: 13.5, weight: .semibold))
                        .foregroundStyle(SCPalette.terracotta)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .zIndex(1)
                }

                Spacer(minLength: 0)
            }
        }
        .onChange(of: selection) { _, newValue in
            onPick(MealSlotSchedule.minutes(from: newValue))
        }
        .onChange(of: isInPlan) { _, newValue in
            inPlan?.set(newValue)
        }
    }

    /// „Wyłącz” / „Włącz” obok krzyżyka — szklana pigułka tej samej
    /// wysokości co krążek, jak „Wyczyść” w wynikach Przepisów.
    private var inPlanButton: some View {
        Button {
            isInPlan.toggle()
        } label: {
            Text(isInPlan ? "Wyłącz" : "Włącz")
                .font(.sc(size: 13.5, weight: .semibold))
                .foregroundStyle(isInPlan ? SCPalette.terracotta : Color.scLabel(scheme))
                .contentTransition(.interpolate)
                .padding(.horizontal, 14)
                .frame(height: SCSheetIconLabel.size)
                .scChromeGlass(in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .accessibilityLabel(isInPlan ? "Wyłącz \(slot.accusativeName)" : "Włącz \(slot.accusativeName)")
    }
}
