import SwiftUI

// Editorial week strip used on the Cozy Kitchen Kalendarz v2.
// Past days = strikethrough numbers, today = bold + accent underline,
// planned = sage dot. Tap to select.
//
// Nad paskiem stoi wiersz podpisu: który to tydzień („TEN TYDZIEŃ · 8–14 WRZ"),
// strzałki i „DZIŚ". Bez niego przesunięcie o kilka tygodni w przód zostawiało
// użytkownika z siedmioma liczbami bez informacji, o jaki tydzień chodzi.
//
// Animations:
// - Terracotta selected-day underline slides between cells via matched geometry.
// - Sage planned dots fade/scale in & out when a day's planned status changes.
// - Cała plansza jeździ palcem w bok: lewo = następny tydzień, prawo =
//   poprzedni. Asystent umie zaplanować kolejne tygodnie, więc musi istnieć
//   sposób, żeby je obejrzeć — a przewijanie planszy jest tym, czego
//   użytkownik próbuje pierwszym odruchem.
struct EditorialWeekBar: View {
    let datesViewModel: DatesViewModel
    // Wybrany dzień jest stanem ekranu, który pokazuje pasek — nie
    // `DatesViewModel`. Plan i Kalendarz dzielą tydzień, ale każdy trzyma
    // własny dzień, więc przestawienie dnia w jednej zakładce nie przestawia
    // go w drugiej.
    @Binding var selectedDate: Date
    let plannedDates: Set<String>   // "yyyy-MM-dd" keys for days that already have ≥1 meal
    /// Wiersz podpisu nad dniami. Domyślnie jest — wyłącza go tylko ekran,
    /// który sam pisze, o którym tygodniu mówi.
    var showsWeekCaption: Bool = true

    @Environment(\.colorScheme) private var scheme
    @Namespace private var indicatorNS

    /// Przesunięcie planszy w trakcie przeciągania. Zerowane razem ze
    /// zmianą tygodnia, żeby plansza wróciła na miejsce w tej samej animacji,
    /// w której podmieniają się liczby dni.
    @State private var dragOffset: CGFloat = 0
    /// Licznik zmian tygodnia — tylko po to, żeby `sensoryFeedback` miało
    /// czym się wyzwolić (sam `weekStartISO` zmienia się też przy starcie).
    @State private var weekChanges = 0

    /// Ile trzeba przeciągnąć (razem z rozpędem), żeby tydzień przeskoczył.
    /// Liczone z `predictedEndTranslation`, więc szybkie machnięcie palcem
    /// wystarczy — nie trzeba przeciągać przez pół ekranu.
    private static let commitThreshold: CGFloat = 56
    /// Sufit wychylenia planszy. Plansza nie jeździ 1:1 z palcem: nie ma
    /// dokąd odjechać (za nią nie ma drugiego tygodnia, tylko te same
    /// komórki z innymi liczbami), więc opór rośnie i ruch się wypłaszcza.
    private static let dragLimit: CGFloat = 56

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "EE"
        return f
    }()

    /// „14" — dzień bez miesiąca, gdy cały tydzień siedzi w jednym miesiącu.
    private static let dayOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "d"
        return f
    }()

    /// „14 wrz" — z miesiącem, gdy tydzień przechodzi przez granicę miesiąca.
    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "d MMM"
        return f
    }()

    var body: some View {
        // 14, nie 6: strzałki zmiany tygodnia siedziały praktycznie na
        // liczbach dni i wiersz podpisu czytał się jak część planszy dni,
        // a nie jak osobna kontrolka nad nią.
        VStack(alignment: .leading, spacing: 14) {
            if showsWeekCaption {
                weekCaption
            }

            HStack(spacing: 0) {
                ForEach(datesViewModel.dates, id: \.self) { date in
                    DayCell(
                        date: date,
                        isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                        isToday: datesViewModel.isToday(date),
                        isPast: !datesViewModel.isEditable(date) && !datesViewModel.isToday(date),
                        isPlanned: plannedDates.contains(PlanWeek.dateKey(date)),
                        indicatorNS: indicatorNS
                    )
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Ta sama sprężyna, którą `DayPager` wjeżdża stroną —
                        // stuknięcie i gest przestawiają podkreślenie identycznie.
                        withAnimation(DayNavigationMotion.spring) {
                            selectedDate = date
                        }
                    }
                }
            }
            // Przeciąganie łapie się w całym prostokącie paska, także
            // w przerwach między komórkami.
            .contentShape(Rectangle())
            .offset(x: dragOffset)
            // `simultaneousGesture`, nie `gesture`: pasek siedzi w pionowym
            // `ScrollView` ekranu, a zwykły `DragGesture` przejmowałby też
            // ruch w pionie i zabijał przewijanie dokładnie w tym miejscu,
            // od którego zaczyna się większość gestów. Tak oba biegną obok
            // siebie, a warunek przewagi w poziomie rozstrzyga, który
            // z nich cokolwiek robi.
            .simultaneousGesture(weekSwipe)
        }
        .sensoryFeedback(.selection, trigger: weekChanges)
    }

    // MARK: - Podpis tygodnia

    private var weekCaption: some View {
        HStack(spacing: 6) {
            Text(captionText)
                .scFont(9.5, weight: .bold, relativeTo: .caption2)
                .tracking(1.1)
                .foregroundStyle(Color.scMuted(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 6)

            if !datesViewModel.isCurrentWeek {
                Button {
                    changeWeek { datesViewModel.goToCurrentWeek() }
                } label: {
                    Text("DZIŚ")
                        .scFont(9.5, weight: .bold, relativeTo: .caption2)
                        .tracking(1)
                        .foregroundStyle(SCPalette.terracotta)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.18 : 0.12))
                        )
                        .overlay(
                            Capsule().stroke(SCPalette.terracotta.opacity(0.34), lineWidth: 1)
                        )
                        // Pigułka ma ~22 pt wysokości; cel dotyku dostaje 44
                        // bez podnoszenia wiersza podpisu.
                        .frame(minWidth: 44)
                        .scTapHeight(drawn: 22)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                .accessibilityLabel("Wróć do bieżącego tygodnia")
            }

            // Strzałki zostają obok gestu, nie zamiast niego: przesuwanie
            // planszy trzeba najpierw odkryć, a to jedyna nawigacja po
            // tygodniach, jaką ma Kalendarz.
            weekStepButton(icon: "chevron.left", label: "Poprzedni tydzień") {
                datesViewModel.goToPreviousWeek()
            }
            weekStepButton(icon: "chevron.right", label: "Następny tydzień") {
                datesViewModel.goToNextWeek()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: datesViewModel.isCurrentWeek)
    }

    private func weekStepButton(
        icon: String,
        label: String,
        step: @escaping () -> Void
    ) -> some View {
        Button {
            changeWeek(step)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.scLabel(scheme))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.scTileBg(scheme)))
                .overlay(Circle().stroke(Color.scTileStroke(scheme), lineWidth: 1))
                // Kółko zostaje 26 pt (wiersz podpisu ma być niski), cel
                // dotyku rośnie do 44. Dwa cele obok siebie zachodzą na
                // siebie o kilkanaście punktów — środek między strzałkami
                // i tak jest niczyj.
                .scTapTarget(drawn: 26)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// „TEN TYDZIEŃ · 8–14 WRZ". Nazwa własna tygodnia tylko dla sąsiadów
    /// bieżącego — „ZA 5 TYGODNI" niesie mniej niż sama data, a przy dużym
    /// odskoku i tak liczy się zakres dni.
    private var captionText: String {
        let range = weekRangeText
        switch datesViewModel.currentWeekOffset {
        case 0:  return "TEN TYDZIEŃ · \(range)"
        case 1:  return "PRZYSZŁY TYDZIEŃ · \(range)"
        case -1: return "POPRZEDNI TYDZIEŃ · \(range)"
        default: return "TYDZIEŃ · \(range)"
        }
    }

    private var weekRangeText: String {
        let dates = datesViewModel.dates
        guard let first = dates.first, let last = dates.last else { return "" }
        let calendar = PlanWeek.calendar
        let sameMonth = calendar.component(.month, from: first)
            == calendar.component(.month, from: last)
        let from = sameMonth
            ? Self.dayOnlyFormatter.string(from: first)
            : Self.dayMonthFormatter.string(from: first)
        return "\(from)–\(Self.dayMonthFormatter.string(from: last))".uppercased()
    }

    // MARK: - Gest tygodnia

    private var weekSwipe: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                // Pionowy ruch należy do scrolla ekranu — pasek siedzi
                // w `ScrollView` i nie wolno mu przejmować przewijania.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = Self.resisted(value.translation.width)
            }
            .onEnded { value in
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                let travel = value.predictedEndTranslation.width

                guard isHorizontal, abs(travel) >= Self.commitThreshold else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        dragOffset = 0
                    }
                    return
                }

                changeWeek {
                    if travel < 0 {
                        datesViewModel.goToNextWeek()
                    } else {
                        datesViewModel.goToPreviousWeek()
                    }
                }
            }
    }

    /// Zmiana tygodnia w jednej animacji z powrotem planszy na miejsce.
    /// Liczby dni mają `.contentTransition(.interpolate)`, więc przechodzą
    /// płynnie zamiast przeskakiwać.
    private func changeWeek(_ step: () -> Void) {
        withAnimation(DayNavigationMotion.spring) {
            step()
            dragOffset = 0
        }
        weekChanges += 1
    }

    /// Opór na krawędzi: pierwsze punkty idą prawie 1:1, dalej ruch się
    /// wypłaszcza i nigdy nie przekracza `dragLimit`.
    private static func resisted(_ translation: CGFloat) -> CGFloat {
        let ratio = translation / dragLimit
        return dragLimit * ratio / (1 + abs(ratio))
    }

    private struct DayCell: View {
        let date: Date
        let isSelected: Bool
        let isToday: Bool
        let isPast: Bool
        let isPlanned: Bool
        let indicatorNS: Namespace.ID

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            let label = Color.scLabel(scheme)
            let muted = Color.scMuted(scheme)
            let strike = Color.scStrike(scheme)
            let accent = SCPalette.terracotta

            VStack(spacing: 4) {
                Text(EditorialWeekBar.shortDayFormatter.string(from: date).uppercased())
                    .scFont(9, weight: .bold, relativeTo: .caption2)
                    .tracking(1)
                    .foregroundStyle(isSelected ? label : muted)
                    // Jak niżej przy numerze dnia — bez tego kolor skrótu
                    // przeskakiwał zamiast płynnie przejść razem ze sprężyną.
                    .contentTransition(.interpolate)

                Text(dayNumber)
                    .scFont(18, weight: isSelected ? .heavy : .semibold, relativeTo: .body)
                    .tracking(-0.3)
                    .foregroundStyle(isPast ? muted : label)
                    .strikethrough(isPast, color: strike)
                    // Grubość fontu nie jest animowalna „za darmo": w sprężynie
                    // zaznaczenia tekst czekał do końca animacji i dopiero wtedy
                    // przeskakiwał semibold → heavy. `.interpolate` prowadzi wagę
                    // płynnie razem z suwającym się podkreśleniem.
                    .contentTransition(.interpolate)

                ZStack {
                    // Reserve the slot height so layout doesn't shift while
                    // the indicators animate in/out.
                    Color.clear.frame(height: 2)

                    // Sage planned dot — fades/scales in/out when the planned
                    // state of a day changes.
                    if isPlanned && !isSelected {
                        Capsule()
                            .fill(SCPalette.sage)
                            .frame(width: 10, height: 2)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Terracotta selected-day underline — slides between cells
                    // because all DayCells share the same indicator namespace.
                    if isSelected {
                        Capsule()
                            .fill(accent)
                            .frame(width: 18, height: 2)
                            .matchedGeometryEffect(id: "weekbar.indicator", in: indicatorNS)
                    }
                }
                .frame(height: 4)
                .padding(.top, 4)
            }
            .padding(.bottom, 8)
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            // `.isButton` jest tu jawnie: komórka reaguje na `onTapGesture`,
            // a nie jest `Button`, więc VoiceOver czytał datę bez słowa, że
            // da się w nią stuknąć.
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        }

        private var dayNumber: String {
            let f = DateFormatter()
            f.dateFormat = "d"
            return f.string(from: date)
        }

        private var accessibilityLabel: String {
            let weekday = DateFormatter.localizedString(from: date, dateStyle: .full, timeStyle: .none)
            if isToday { return "\(weekday), dziś" }
            if isPast { return "\(weekday), przeszłość" }
            if isPlanned { return "\(weekday), zaplanowany" }
            return weekday
        }
    }
}
