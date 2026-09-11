import SwiftUI

// Kalendarz v11 · Talerz — sekwencja dnia i jedno zdanie pod nią.
//
// Źródło: canvas claude.ai → „Weekly Meals - Kalendarz v11 Talerz.html”,
// `components/cal-v11-plate-2.jsx` (dolna część `V11Plate2` oraz
// `V11PDayLine`). Pod wielkim talerzem stoi cały dzień w miniaturze: małe
// talerze z godziną i porą, wybrany rośnie. Stuknięcie przekłada danie na
// środek — to jedyna nawigacja tego ekranu.
//
// Dwie rzeczy różnią sekwencję od makiety:
//
//  1. **Puste pory też tu stoją**, kreskowanym krążkiem. Makieta rysowała
//     wyłącznie zaplanowane dania, ale „kolacji nie ma” jest w tym ekranie
//     odpowiedzią, a nie brakiem odpowiedzi — dawna lista mówiła to wprost
//     osobnym wierszem i nie wolno tego zgubić po drodze.
//  2. **Talerze zjeżdżają wielkością, a nie wychodzą poza ekran.** Makieta
//     miała stałe 62 pt na kolumnę, co przy sześciu włączonych porach
//     (a tyle da się włączyć w Ustawieniach) nie mieści się na żadnym
//     telefonie. Poziomego przewijania NIE MA i mieć nie może: strona dnia
//     jeździ palcem w bok, więc druga oś pozioma w środku niej zabrałaby
//     połowę machnięć zmieniających dzień.

// MARK: - Sekwencja dnia

struct CalendarPlateStrip: View {
    let items: [CalendarPlateItem]
    let selectedId: String?
    /// Szerokość, którą sekwencja ma do dyspozycji. Zero = jeszcze nie
    /// zmierzona; wtedy kolumny idą w rozmiarze z makiety.
    let width: CGFloat
    let onSelect: (CalendarPlateItem) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dayPagerGate) private var pagerGate

    /// Proporcje z makiety: kolumna 62 pt, talerz wybrany 56, reszta 46.
    private static let designColumn: CGFloat = 62
    private static let selectedRatio: CGFloat = 56 / 62
    private static let restRatio: CGFloat = 46 / 62
    /// Najwęższa kolumna, przy której godzina jest jeszcze godziną, a nie
    /// plamką. Poniżej tej wartości sekwencja wolałaby nie istnieć, ale
    /// sześć pór i tak się w niej mieści na każdym telefonie.
    private static let minColumn: CGFloat = 38

    private var gap: CGFloat { items.count > 4 ? 8 : 10 }

    private var column: CGFloat {
        guard width > 0, !items.isEmpty else { return Self.designColumn }
        let free = width - gap * CGFloat(items.count - 1)
        return max(Self.minColumn, min(Self.designColumn, free / CGFloat(items.count)))
    }

    private var selectedSize: CGFloat { (column * Self.selectedRatio).rounded() }
    private var restSize: CGFloat { (column * Self.restRatio).rounded() }

    var body: some View {
        HStack(alignment: .bottom, spacing: gap) {
            ForEach(items) { item in
                Button {
                    pagerGate.ifNotSwiping { onSelect(item) }
                } label: {
                    cell(item)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(item))
                .accessibilityAddTraits(item.id == selectedId ? .isSelected : [])
                .accessibilityHint("Przekłada danie na talerz")
            }
        }
        .frame(maxWidth: .infinity)
        // Wybrany talerz rośnie, poprzedni maleje — jedną sprężyną, tą samą,
        // którą jedzie strona dnia i podkreślenie na pasku dni.
        .animation(DayNavigationMotion.spring, value: selectedId)
        .sensoryFeedback(.selection, trigger: selectedId)
    }

    private func cell(_ item: CalendarPlateItem) -> some View {
        let on = item.id == selectedId
        let size = on ? selectedSize : restSize

        return VStack(spacing: 8) {
            // Pudełko wysokości WYBRANEGO talerza, niezależnie od tego, który
            // jest wybrany: bez niego rosnący talerz podnosiłby i opuszczał
            // podpisy w całym rzędzie przy każdym stuknięciu.
            ZStack {
                plate(item, size: size, isSelected: on)
            }
            .frame(width: column, height: selectedSize)

            VStack(spacing: 2) {
                Text(item.time ?? "dowolna")
                    .font(.system(size: 11.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(on ? Color.scLabel(scheme) : Color.scMuted(scheme))

                Text(item.slot.shortTitle)
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(labelColor(item, isSelected: on))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: column)
        }
        .contentShape(Rectangle())
    }

    private func plate(_ item: CalendarPlateItem, size: CGFloat, isSelected: Bool) -> some View {
        face(item, size: size)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .saturation(item.isEaten ? 0.45 : 1)
            .opacity(item.isEaten ? 0.6 : isSelected ? 1 : 0.78)
            .overlay {
                if let ring = ringColor(item, isSelected: isSelected) {
                    Circle()
                        .strokeBorder(ring, lineWidth: 2)
                        .padding(-3)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if item.isEaten { eatenBadge(size: size) }
            }
            .animation(.smooth(duration: 0.24), value: item.status)
    }

    @ViewBuilder
    private func face(_ item: CalendarPlateItem, size: CGFloat) -> some View {
        if item.isEmptySlot {
            // Ten sam kreskowany krążek, co na wielkim talerzu i co
            // w kółku „bez pory” — jeden znak na „nic tu jeszcze nie stoi”.
            ZStack {
                Circle().fill(Color.scChipBg(scheme))

                Circle()
                    .strokeBorder(
                        Color.scRule(scheme),
                        style: StrokeStyle(lineWidth: 1.2, dash: [3.5, 3])
                    )

                Image(systemName: item.slot.icon)
                    .font(.system(size: size * 0.34, weight: .light))
                    .foregroundStyle(Color.scFaint(scheme))
            }
        } else if let url = item.imageURL {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    fallback(item.slot, size: size)
                }
            }
        } else {
            fallback(item.slot, size: size)
        }
    }

    private func fallback(_ slot: MealSlot, size: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [slot.cozyTint, slot.cozyTint.mix(with: .black, by: 0.40)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: slot.icon)
                .font(.system(size: size * 0.34, weight: .light))
                .foregroundStyle(Color.white.opacity(0.65))
        }
    }

    /// Pieczątka zjedzenia — guzik od koszuli w rogu talerzyka.
    ///
    /// Krążek bierze kolor tła, ptaszek kolor pisma: pieczątka siedzi na
    /// zdjęciu, które ma przygasać, a jasny krążek byłby na nim kolejną
    /// plamą światła.
    private func eatenBadge(size: CGFloat) -> some View {
        Image(systemName: "checkmark.circle.fill")
            .symbolRenderingMode(.palette)
            .font(.system(size: max(11, size * 0.34), weight: .bold))
            .foregroundStyle(Color.scChecked(scheme).opacity(0.9), Color.scPageBase(scheme))
            .offset(x: 2, y: 2)
            .transition(.scale(scale: 0.4).combined(with: .opacity))
    }

    /// Obwódka talerzyka. `nil` = bez obwódki (zwykłe danie, nie wybrane).
    ///
    /// Wybrane danie obwodzi się zawsze — to ono stoi teraz na wielkim
    /// talerzu i musi być widać, skąd przyszło. Następne danie dnia nosi
    /// swoją obwódkę także wtedy, gdy użytkownik ogląda co innego: inaczej
    /// przekładając talerze, gubi się miejsce, do którego się wraca.
    private func ringColor(_ item: CalendarPlateItem, isSelected: Bool) -> Color? {
        if isSelected {
            if item.isEaten { return SCPalette.sage }
            if item.status == .next { return item.slot.cozyAccent }
            return Color.scLabel(scheme).opacity(0.5)
        }
        if item.status == .next { return item.slot.cozyAccent.opacity(0.45) }
        return nil
    }

    private func labelColor(_ item: CalendarPlateItem, isSelected: Bool) -> Color {
        guard isSelected else { return Color.scFaint(scheme) }
        if item.isEaten { return SCPalette.sage }
        return item.slot.cozyAccent
    }

    private func accessibilityLabel(_ item: CalendarPlateItem) -> String {
        var parts = [item.slot.title]
        if let time = item.time { parts.append(time) }
        if let title = item.title {
            parts.append(title)
        } else {
            parts.append("nic nie zaplanowano")
        }
        if item.isEaten { parts.append("zjedzone") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Stan całego dnia

/// Jednym zdaniem: co z tym dniem.
///
/// Liczy to ekran (`CalendarView.daySummary`), bo odpowiedź zależy od
/// wszystkich posiłków naraz, od zegara i od celu dnia. Tutaj zostaje
/// wyłącznie to, JAK się o tym mówi.
///
/// Następca `CalendarDayFocus` ze środka łuku doby. Różnica jest w tym, czego
/// ten stan już NIE niesie: „co teraz” mówi teraz sam talerz, więc nie ma tu
/// ani następnego posiłku, ani okna gotowania — zostaje podsumowanie.
enum CalendarDaySummary: Equatable {
    /// Dzień bez ani jednego zaplanowanego posiłku.
    case empty
    /// Dzień z przyszłości — jest tylko plan, nie ma czego odhaczać.
    case plan(meals: Int, kcal: Int, firstTime: String?)
    /// Wszystko odhaczone. `delta` = zjedzone minus cel dnia.
    case closed(kcal: Int, delta: Int)
    /// Część dnia odhaczona.
    case partial(kcal: Int, eaten: Int, total: Int)
    /// Nic nie odhaczone.
    case untouched(planKcal: Int, meals: Int, isPast: Bool)
}

// MARK: - Linia dnia

/// Jedno zdanie pod sekwencją — jedna barwa, jedna myśl.
///
/// Ma pierwszeństwo przed podsumowaniem dnia, gdy użytkownik ogląda na
/// talerzu co innego niż następny posiłek: wtedy mówi, co jest następne,
/// i stuknięciem wraca. Bez tego przekładanie talerzy gubiło „teraz” —
/// jedyną rzecz, dla której ten ekran w ogóle się otwiera.
///
/// „Odhacz cały dzień” tu nie wróciło, choć makieta stawia je w tym miejscu
/// pod dniem minionym. Jedno stuknięcie zapisujące pięć posiłków naraz jest
/// deklaracją, a nie zapisem — decyzja zapadła przy poprzednim układzie
/// ekranu i nic jej od tamtej pory nie podważyło.
struct CalendarDayLine: View {
    let summary: CalendarDaySummary
    /// Następne danie dnia — podawane TYLKO wtedy, gdy na talerzu stoi co
    /// innego. `nil` znaczy „talerz i tak pokazuje to, co trzeba”.
    let nextAway: CalendarPlateItem?
    let onReturnToNext: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dayPagerGate) private var pagerGate

    var body: some View {
        if let nextAway {
            line(text: nextText(nextAway), color: SCPalette.terracotta, dot: true)
                .contentShape(Rectangle())
                .onTapGesture { pagerGate.ifNotSwiping(onReturnToNext) }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Wraca do następnego posiłku")
        } else if let summaryText {
            line(text: summaryText, color: summaryColor, dot: summaryHasDot)
        }
    }

    private func line(text: String, color: Color, dot: Bool) -> some View {
        HStack(spacing: 8) {
            if dot {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(color.opacity(0.2), lineWidth: 3).padding(-3))
            }

            Text(text)
                .font(.system(size: 13, weight: .bold))
                .tracking(-0.2)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .contentTransition(.numericText())
        .animation(.smooth(duration: 0.28), value: text)
    }

    /// „Następny: obiad za 4 h 19 min · gotuj od 13:00”.
    ///
    /// Odkąd robi się pilnie, zdanie zaczyna się od czynności, a nie od pory:
    /// „Pora gotować obiad · na 14:00” odpowiada na pytanie, które właśnie
    /// zastąpiło poprzednie.
    private func nextText(_ item: CalendarPlateItem) -> String {
        let name = item.slot.title.lowercased()

        if item.isCooking {
            guard let time = item.time else { return "Pora gotować \(name)" }
            return "Pora gotować \(name) · na \(time)"
        }
        if item.isDue { return "Pora jeść \(name)" }
        if item.isLate { return "Następny: \(name) · pora minęła" }

        var head = "Następny: \(name)"
        if let away = item.minutesAway {
            head += " \(CalendarRelativeTime.text(inMinutes: away))"
        } else if let time = item.time {
            head += " o \(time)"
        }

        guard item.showsCookHint, let cookFrom = item.cookFrom else { return head }
        return "\(head) · gotuj od \(cookFrom)"
    }

    private var summaryText: String? {
        switch summary {
        case .empty:
            // Pusty dzień ma pod sekwencją dopisek z dwoma wyjściami
            // (`CalendarEmptyDayNote`) — zdanie nad nim byłoby tym samym
            // powiedzianym dwa razy.
            return nil
        case .plan(let meals, let kcal, let firstTime):
            guard let firstTime else { return "\(PolishPlural.meals(meals)) · \(kcal) kcal w planie" }
            return "\(PolishPlural.meals(meals)) · \(kcal) kcal w planie · od \(firstTime)"
        case .closed(let kcal, let delta):
            if delta > 0 { return "Dzień domknięty · \(kcal) kcal · +\(delta) nad celem" }
            if delta < 0 { return "Dzień domknięty · \(kcal) kcal · \(-delta) pod celem" }
            return "Dzień domknięty · \(kcal) kcal · równo z celem"
        case .partial(let kcal, let eaten, let total):
            return "\(eaten) z \(total) zjedzone · \(kcal) kcal"
        case .untouched(let planKcal, let meals, let isPast):
            guard isPast else { return "\(PolishPlural.meals(meals)) w planie · \(planKcal) kcal" }
            return "Nic nie odhaczone · plan \(planKcal) kcal"
        }
    }

    private var summaryColor: Color {
        switch summary {
        case .closed, .partial: return SCPalette.sage
        default:                return Color.scFaint(scheme)
        }
    }

    private var summaryHasDot: Bool {
        switch summary {
        case .closed, .partial: return true
        default:                return false
        }
    }
}

#Preview("Sekwencja i linia dnia") {
    let items = [
        CalendarPlateItem(
            id: "sn", slot: .breakfast, status: .eaten, time: "08:00",
            title: "Owsianka kakaowa", imageURL: nil, kcal: 510, prepMinutes: 12,
            cookFrom: "07:48", servingsNote: nil, minutesAway: -100, isMissed: false
        ),
        CalendarPlateItem(
            id: "ob", slot: .lunch, status: .next, time: "14:00",
            title: "Indyk z ziemniakami", imageURL: nil, kcal: 604, prepMinutes: 60,
            cookFrom: "13:00", servingsNote: nil, minutesAway: 259, isMissed: false
        ),
        CalendarPlateItem(
            id: "ko", slot: .dinner, status: .later, time: "20:00",
            title: "Pierogi z truskawkami", imageURL: nil, kcal: 900, prepMinutes: 70,
            cookFrom: "18:50", servingsNote: nil, minutesAway: 619, isMissed: false
        ),
        CalendarPlateItem(
            id: "pk", slot: .snack, status: .anytime, time: nil,
            title: nil, imageURL: nil, kcal: 0, prepMinutes: 0,
            cookFrom: nil, servingsNote: nil, minutesAway: nil, isMissed: false
        )
    ]

    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()

        VStack(spacing: 28) {
            CalendarPlateStrip(items: items, selectedId: "ob", width: 353, onSelect: { _ in })

            CalendarDayLine(
                summary: .partial(kcal: 1665, eaten: 1, total: 4),
                nextAway: nil,
                onReturnToNext: {}
            )

            CalendarDayLine(
                summary: .partial(kcal: 1665, eaten: 1, total: 4),
                nextAway: items[1],
                onReturnToNext: {}
            )

            CalendarDayLine(
                summary: .closed(kcal: 2903, delta: 603),
                nextAway: nil,
                onReturnToNext: {}
            )
        }
        .padding(.horizontal, SCPageMetrics.horizontal)
    }
    .preferredColorScheme(.dark)
}
