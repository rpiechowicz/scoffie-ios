import SwiftUI

// Kalendarz v11 · Talerz — sekwencja dnia i jedno zdanie pod nią.
//
// Źródło: canvas claude.ai → „Weekly Meals - Kalendarz v11 Talerz.html”,
// `components/cal-v11-plate-2.jsx` (dolna część `V11Plate2` oraz
// `V11PDayLine`). Pod wielkim talerzem stoi cały dzień w miniaturze: małe
// talerze z godziną i porą, wybrany rośnie. Stuknięcie przekłada danie na
// środek — to jedyna nawigacja tego ekranu.
//
// Trzy rzeczy różnią sekwencję od makiety:
//
//  1. **Puste pory też tu stoją**, kreskowanym krążkiem — także w dniu bez
//     ani jednego dania. Makieta rysowała wyłącznie zaplanowane dania,
//     a pusty dzień miała jako osobną stronę z przyciskami. U nas pusty
//     dzień to TEN SAM ekran z pustym talerzem: te same piętra, ta sama
//     wysokość, te same miejsca — bo inaczej talerz stałby na pustym dniu
//     gdzie indziej niż na pełnym i każde machnięcie między nimi
//     przestawiałoby całą scenę.
//  2. **Talerze zjeżdżają wielkością, a nie wychodzą poza ekran.** Makieta
//     miała stałe 62 pt na kolumnę, co przy sześciu włączonych porach
//     (a tyle da się włączyć w Ustawieniach) nie mieści się na żadnym
//     telefonie. Poziomego przewijania NIE MA i mieć nie może: strona dnia
//     jeździ palcem w bok, więc druga oś pozioma w środku niej zabrałaby
//     połowę machnięć zmieniających dzień.
//  3. **Linia dnia nie podsumowuje, tylko prowadzi.** Makieta pisała w niej
//     „2 z 4 zjedzone · 1665 kcal” — a to samo mówią kropki w nagłówku dnia
//     i pigułka kcal nad dolnym menu. Zostało wyłącznie to, czego nie ma
//     nigdzie indziej: co jest dalej w sekwencji (`CalendarDayNote`).
//
// Talerzyk STOI, także gdy jego danie leci na talerz. Przez trzy wydania
// gasł na czas lotu („dziura w tacy”), żeby na ekranie nie było dwóch zdjęć
// tego samego dania — i to był błąd w założeniu: sekwencja nie jest tacą,
// z której coś się zdejmuje, tylko WSKAŹNIKIEM, który mówi, przy której
// porze stoi wielki talerz. Wybrane danie widać tu i tam CAŁY CZAS, także
// gdy nic się nie rusza, więc gaszenie talerzyka nie usuwało duplikatu —
// dokładało mrugnięcie w miejscu, na które właśnie stuknął palec, i to
// dwukrotne (zgaśnięcie i powrót), każde na innym zegarze niż lot.
// Duplikat nie przeszkadza, bo lot zaczyna się i kończy DOKŁADNIE na
// talerzyku, w jego rozmiarze: w pierwszych klatkach kopia leży na nim
// punkt w punkt (nie da się jej odróżnić), potem od niego odjeżdża,
// a wracając wtapia się w niego z powrotem (`CalendarPlate.swap`).
// Rusza się jedna rzecz — ta, która ma się ruszać.

// MARK: - Sekwencja dnia

struct CalendarPlateStrip: View {
    let items: [CalendarPlateItem]
    let selectedId: String?
    /// Szerokość, którą sekwencja ma do dyspozycji. Zero = jeszcze nie
    /// zmierzona; wtedy kolumny idą w rozmiarze z makiety.
    let width: CGFloat
    /// Sufit szerokości kolumny. Domyślnie 62 pt z makiety; krótki ekran
    /// podaje mniej, bo każdy punkt zabrany sekwencji wraca do talerza.
    var maxColumn: CGFloat = CalendarPlateStrip.designColumn
    /// Środek talerzyka danego dania (w przestrzeni `daySpace`) i rozmiar,
    /// jaki ma talerzyk NIEWYBRANY. Z tego talerz wie, skąd danie wznosi się
    /// na środek i dokąd opada z powrotem (`CalendarPlate.origin`).
    var onCellCenter: ((CalendarPlateItem, CGPoint, CGFloat) -> Void)?
    let onSelect: (CalendarPlateItem) -> Void

    /// Nazwa przestrzeni współrzędnych, którą dzień zakłada na swojej
    /// kolumnie: w niej sekwencja melduje środki talerzyków, a talerz mierzy
    /// własny środek. Jedno miejsce dla obu, żeby różnica była w tych samych
    /// punktach.
    static let daySpace = "calendar-day"

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dayPagerGate) private var pagerGate

    /// Proporcje z makiety: kolumna 62 pt, talerz wybrany 56, reszta 46.
    static let designColumn: CGFloat = 62
    private static let selectedRatio: CGFloat = 56 / 62
    private static let restRatio: CGFloat = 46 / 62
    /// Najwęższa kolumna, przy której godzina jest jeszcze godziną, a nie
    /// plamką. Poniżej tej wartości sekwencja wolałaby nie istnieć, ale
    /// sześć pór i tak się w niej mieści na każdym telefonie.
    private static let minColumn: CGFloat = 38
    /// O ile obwódka wybranego talerzyka wychodzi poza zdjęcie (2 pt kreski
    /// przesuniętej o 3 pt na zewnątrz). Pudełko talerzyka jest o tyle
    /// wyższe, żeby obwódka nie wchodziła w odstęp nad sekwencją ani
    /// w podpis pod nią.
    private static let ringOverhang: CGFloat = 3

    private var gap: CGFloat { items.count > 4 ? 8 : 10 }

    /// Sufit kolumny po uwzględnieniu trybu ekranu — od niego liczy się
    /// wysokość pudełka talerzyka, a więc i wysokość całej sekwencji.
    private var ceiling: CGFloat { min(Self.designColumn, maxColumn) }

    private var column: CGFloat {
        guard width > 0, !items.isEmpty else { return ceiling }
        let free = width - gap * CGFloat(items.count - 1)
        return max(Self.minColumn, min(ceiling, free / CGFloat(items.count)))
    }

    private var selectedSize: CGFloat { (column * Self.selectedRatio).rounded() }
    private var restSize: CGFloat { (column * Self.restRatio).rounded() }

    /// Wysokość pudełka talerzyka — liczona z SUFITU kolumny, nie z kolumny.
    ///
    /// Kolumna zależy od liczby pór dnia (sześć pór ściska ją bardziej niż
    /// cztery), a sekwencja ma mieć na każdym dniu tę samą wysokość: inaczej
    /// dzień z sześcioma porami oddawałby talerzowi dziewięć punktów, dzień
    /// z czterema nie, i talerz przesuwałby się o połowę tego przy każdym
    /// machnięciu między nimi. Talerzyki mniejsze od pudełka stoją w nim po
    /// środku.
    private var boxSize: CGFloat {
        (ceiling * Self.selectedRatio).rounded() + Self.ringOverhang * 2
    }

    /// Odcisk do animacji zmiany dnia: dania i ich stany, bez minut.
    /// `items` jako całość zmienia się co minutę (odliczanie), a sekwencja
    /// nie ma wtedy nic do animowania — transakcja co tyknięcie byłaby
    /// pustym kosztem.
    private var fingerprint: [String] {
        items.map { "\($0.id).\($0.status)" }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: gap) {
            // Tożsamość kolumny to jej MIEJSCE w rzędzie, nie danie.
            //
            // Zmiana dnia ma przełożyć talerzyki, a nie wymienić rząd:
            // trzecia kolumna poniedziałku przechodzi w trzecią kolumnę
            // wtorku (zdjęcie kryciem, podpisy w miejscu), a czwarta —
            // jeśli wtorek ma o jedno danie więcej — dopiero wtedy wchodzi.
            // Tożsamość po daniu kazałaby usunąć wszystkie kolumny
            // poniedziałku i wstawić wszystkie wtorkowe, a że schodzące
            // kolumny żyją do końca swojego przejścia, rząd miałby przez
            // chwilę dwa razy tyle talerzyków i ściskałby je w połowie ruchu.
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button {
                    pagerGate.ifNotSwiping { onSelect(item) }
                } label: {
                    cell(item)
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityLabel(item.accessibilityDescription)
                .accessibilityAddTraits(item.id == selectedId ? .isSelected : [])
                .accessibilityHint("Przekłada danie na talerz")
            }
        }
        .frame(maxWidth: .infinity)
        // Wybrany talerz rośnie, poprzedni maleje — tą samą sprężyną, którą
        // danie wznosi się z tacy na talerz (`DayNavigationMotion.lift`),
        // żeby oba końce ruchu osiadały razem. Drugi odcisk na dania i stany:
        // gdy plan przyjdzie zmieniony, kolumny przekładają się tym samym
        // ruchem. Haptyka przekładania należy do ekranu (`CalendarView`),
        // nie do sekwencji: wybrany talerzyk zmienia się także przy zmianie
        // dnia, a wtedy stuknięcie ma już swój własny sygnał z pagera.
        .animation(DayNavigationMotion.lift, value: selectedId)
        .animation(DayNavigationMotion.spring, value: fingerprint)
    }

    private func cell(_ item: CalendarPlateItem) -> some View {
        let on = item.id == selectedId
        let size = on ? selectedSize : restSize

        return VStack(spacing: 8) {
            // Pudełko stałej wysokości, niezależnie od tego, który talerzyk
            // jest wybrany i ile ich jest: bez niego rosnący talerz podnosiłby
            // i opuszczał podpisy w całym rzędzie przy każdym stuknięciu.
            ZStack {
                plate(item, size: size, isSelected: on)
            }
            .frame(width: column, height: boxSize)
            // Meldunek o miejscu talerzyka — w przestrzeni dnia, żeby talerz
            // mógł policzyć, skąd danie wznosi się na środek. Zmienia się
            // tylko wtedy, gdy zmienia się układ (obrót tacy, inna liczba
            // pór), więc nie kosztuje przebiegów.
            .onGeometryChange(for: CGPoint.self) { proxy in
                let frame = proxy.frame(in: .named(Self.daySpace))
                return CGPoint(x: frame.midX, y: frame.midY)
            } action: { center in
                onCellCenter?(item, center, restSize)
            }

            VStack(spacing: 2) {
                // Godzina przechodzi kryciem, nie rolowaniem cyfr: gdy plan
                // przyjdzie zmieniony, w tej samej kolumnie potrafi stanąć
                // „dowolna” zamiast „20:00” i rolowanie robiło z tego zlepek.
                Text(item.time ?? "dowolna")
                    .font(.system(size: 11.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(on ? Color.scLabel(scheme) : Color.scMuted(scheme))
                    .contentTransition(.opacity)

                Text(item.slot.shortTitle)
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(labelColor(item, isSelected: on))
                    .contentTransition(.opacity)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: column)
        }
        .contentShape(Rectangle())
    }

    private func plate(_ item: CalendarPlateItem, size: CGFloat, isSelected: Bool) -> some View {
        CalendarPlateFace(item: item, size: size)
            .saturation(item.isEaten ? 0.45 : 1)
            .opacity(item.isEaten ? 0.6 : isSelected ? 1 : 0.78)
            .overlay {
                if let ring = ringColor(item, isSelected: isSelected) {
                    Circle()
                        .strokeBorder(ring, lineWidth: 2)
                        .padding(-Self.ringOverhang)
                        .transition(.opacity)
                }
            }
            // Pieczątka zjedzenia — ten sam znak co na wielkim talerzu,
            // wielkości guzika od koszuli, na krążku tła, żeby wycinał się
            // ze zdjęcia. Dwa różne rysunki „zjedzone” na jednym ekranie
            // to dwa znaki na jeden stan.
            .overlay(alignment: .bottomTrailing) {
                if item.isEaten {
                    CalendarMealCheck(
                        status: .eaten,
                        color: item.slot.cozyAccent,
                        size: max(14, (size * 0.34).rounded())
                    )
                    .background(Circle().fill(Color.scPageBase(scheme)))
                    .offset(x: 2, y: 2)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .animation(DayNavigationMotion.spring, value: item.status)
    }

    /// Obwódka talerzyka. `nil` = bez obwódki (zwykłe danie, nie wybrane).
    ///
    /// Wybrane danie obwodzi się zawsze — to ono stoi teraz na wielkim
    /// talerzu i musi być widać, skąd przyszło. Następne danie dnia nosi
    /// swoją obwódkę także wtedy, gdy użytkownik ogląda co innego: inaczej
    /// przekładając talerze, gubi się miejsce, do którego się wraca.
    private func ringColor(_ item: CalendarPlateItem, isSelected: Bool) -> Color? {
        if isSelected {
            // Zjedzone neutralnie, nie szałwią — szałwia to obiad i zjedzone
            // śniadanie w sekwencji wyglądało jak drugi obiad.
            if item.isEaten { return Color.scChecked(scheme).opacity(0.55) }
            if item.status == .next { return item.slot.cozyAccent }
            return Color.scLabel(scheme).opacity(0.5)
        }
        if item.status == .next { return item.slot.cozyAccent.opacity(0.45) }
        return nil
    }

    private func labelColor(_ item: CalendarPlateItem, isSelected: Bool) -> Color {
        guard isSelected else { return Color.scFaint(scheme) }
        if item.isEaten { return Color.scChecked(scheme).opacity(0.7) }
        return item.slot.cozyAccent
    }
}

// MARK: - Co dalej w sekwencji

/// Jedno zdanie pod sekwencją: co jest DALEJ względem tego, co stoi na
/// talerzu.
///
/// Liczy to ekran (`CalendarView.dayNote`), bo odpowiedź zależy od całego
/// dnia i od zegara. Tutaj zostaje wyłącznie to, JAK się o tym mówi.
///
/// Celowo NIE ma tu podsumowania dnia: „2 z 4 zjedzone” niosą kropki
/// w nagłówku dnia, „1665 kcal” — pigułka celu nad dolnym menu. Zdanie,
/// które powtarza to, co stoi dwa centymetry wyżej i niżej, nie jest
/// zdaniem, tylko szumem. Zostało to, czego nie ma nigdzie indziej.
enum CalendarDayNote: Equatable {
    /// Na talerzu stoi co innego niż następny posiłek dnia — jedno zdanie
    /// o nim, stuknięcie wraca. Bez tego przekładanie talerzy gubiło
    /// „teraz”, jedyną rzecz, dla której ten ekran w ogóle się otwiera.
    case next(CalendarPlateItem)
    /// Po daniu na talerzu jest jeszcze coś — stuknięcie przekłada.
    case after(CalendarPlateItem)
    /// Na talerzu stoi ostatnia pora dnia, a dzień nie jest domknięty.
    case last(CalendarPlateItem)
    /// Wszystko zjedzone i na talerzu stoi ostatnie danie.
    case closed
    /// Dzień bez ani jednego zaplanowanego posiłku — ile pór czeka.
    case empty(slots: Int)
}

// MARK: - Linia dnia

/// Jedno zdanie, jedna barwa, jedno stuknięcie — i STAŁA wysokość.
///
/// Linia stoi zawsze, także gdy nie ma nic do powiedzenia: to ostatnie
/// piętro układu dnia i gdyby znikała, talerz nad nią miałby na różnych
/// dniach różne miejsce. Widok jest JEDEN o zmiennej treści, a nie kilka
/// w gałęziach `if / else`: gałęzie mają w SwiftUI różne tożsamości, więc
/// przejście z „Następny: obiad…” w „Potem: kolacja…” wymieniałoby widok
/// zamiast przerolować tekst.
struct CalendarDayLine: View {
    let note: CalendarDayNote
    /// Klucz dnia — ziarno doboru wariantów zdań (`CalendarVoice`).
    let dayKey: String
    /// Wraca do następnego posiłku (dla `.next`).
    let onReturnToNext: () -> Void
    /// Przekłada na talerz podane danie (dla `.after`).
    let onSelect: (CalendarPlateItem) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dayPagerGate) private var pagerGate

    /// Wysokość linii — jedna linijka 13 pt z zapasem na kropkę.
    static let height: CGFloat = 18

    /// Zdanie, barwa i kropka policzone naraz, żeby zmieniały się w jednej
    /// transakcji. `key` to tożsamość zdania: to samo danie i ten sam rodzaj
    /// zdania rolują cyfry (tyknięcie zegara), inny rodzaj albo inne danie
    /// przechodzi kryciem — rolowanie „Potem: kolacja · 20:00” w „Następny:
    /// obiad za 3 min” literka po literce wyglądało jak usterka.
    private struct Line: Equatable {
        let key: String
        let text: String
        let color: Color
        let dot: Bool
        let tappable: Bool
    }

    /// Wariant zdania dla tego dnia — ten sam fakt, inny ton
    /// (`CalendarVoice`). Ziarno bierze klucz dnia, danie i rodzaj zdania.
    private func voice(_ variants: [String], _ kind: String, item: CalendarPlateItem? = nil) -> String {
        CalendarVoice.pick(variants, seed: "\(dayKey)|\(item?.id ?? "-")|line-\(kind)")
    }

    private var line: Line {
        switch note {
        case .next(let item):
            let phase = item.isCooking ? "cooking" : item.isDue ? "due" : item.isLate ? "late" : "countdown"
            return Line(
                key: "next-\(item.id)-\(phase)",
                text: nextText(item),
                color: SCPalette.terracotta,
                dot: true,
                tappable: true
            )
        case .after(let item):
            // Stan w kluczu: „· zjedzone” dochodzi, gdy domownik odhaczy to
            // danie z drugiego telefonu — bez tego dopisek rolowałby się
            // literka po literce pod niezmienionym kluczem.
            return Line(
                key: "after-\(item.id)-\(item.isEaten)",
                text: afterText(item),
                color: Color.scMuted(scheme),
                dot: false,
                tappable: true
            )
        case .last(let item):
            // Bez „dziś”: ta linia stoi też pod wczorajszym i czwartkowym
            // dniem, a wariant, który dokłada fakt, nie jest wariantem.
            let text = item.isEmptySlot
                ? voice(["Koniec dnia", "Dalej już nic", "Nic więcej tego dnia"], "last-empty", item: item)
                : voice(["Ostatni posiłek dnia", "To już wszystko", "Tym kończysz dzień", "Koniec menu na ten dzień"], "last", item: item)
            return Line(
                key: "last-\(item.isEmptySlot)",
                text: text,
                color: Color.scFaint(scheme),
                dot: false,
                tappable: false
            )
        case .closed:
            return Line(
                key: "closed",
                text: voice(["Dzień domknięty", "Wszystko zjedzone", "Komplet zjedzony", "Dzień zaliczony"], "closed"),
                color: SCPalette.sage,
                dot: true,
                tappable: false
            )
        case .empty(let slots):
            // Ile pór czeka na zaplanowanie — jedyna rzecz, której pusty
            // dzień nie mówi nigdzie indziej (pigułka pod talerzem mówi,
            // GDZIE się planuje). Warianty bez czasownika, bo liczebnik
            // zmieniałby jego formę („3 pory czekają”, „5 pór czeka”).
            let count = PolishPlural.form(slots, one: "pora", few: "pory", many: "pór")
            let text = voice(
                ["\(slots) \(count) do zaplanowania", "Do ułożenia: \(slots) \(count)", "Wolne: \(slots) \(count)"],
                "empty"
            )
            return Line(
                key: "empty",
                text: text,
                color: Color.scFaint(scheme),
                dot: false,
                tappable: false
            )
        }
    }

    var body: some View {
        let line = line

        HStack(spacing: 8) {
            if line.dot {
                Circle()
                    .fill(line.color)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(line.color.opacity(0.2), lineWidth: 3).padding(-3))
                    .transition(.scale.combined(with: .opacity))
            }

            // `ZStack` jako kontener przejścia — bez niego wymiana tożsamości
            // byłaby twardym cięciem (patrz `CalendarPlate.body`).
            ZStack {
                Text(line.text)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(-0.2)
                    .monospacedDigit()
                    .foregroundStyle(line.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .contentTransition(.numericText())
                    // Dzień w tożsamości: zdania różnią się wariantem między
                    // dniami (`CalendarVoice`), więc zmiana dnia ma przejść
                    // kryciem, nie rolowaniem liter pod tym samym kluczem.
                    // W obrębie dnia klucz stoi i cyfry odliczania rolują.
                    .id("\(dayKey)|\(line.key)")
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .onTapGesture { tap() }
        .animation(DayNavigationMotion.spring, value: line)
        .accessibilityAddTraits(line.tappable ? .isButton : [])
        .accessibilityHint(hint)
    }

    private func tap() {
        switch note {
        case .next:
            pagerGate.ifNotSwiping(onReturnToNext)
        case .after(let item):
            pagerGate.ifNotSwiping { onSelect(item) }
        case .last, .closed, .empty:
            return
        }
    }

    private var hint: String {
        switch note {
        case .next:  return "Wraca do następnego posiłku"
        case .after: return "Przekłada na talerz następne danie"
        default:     return ""
        }
    }

    /// „Następny: obiad za 4 h 19 min · gotuj od 13:00”.
    ///
    /// Odkąd robi się pilnie, zdanie zaczyna się od czynności, a nie od pory:
    /// „Pora gotować obiad · na 14:00” odpowiada na pytanie, które właśnie
    /// zastąpiło poprzednie.
    private func nextText(_ item: CalendarPlateItem) -> String {
        // Mianownik po dwukropku („Na stół: kolacja”), biernik po czasowniku
        // („Pora jeść kolację”) — `title.lowercased()` dawał „kolacja”
        // w obu i psuł „II śniadanie” w „ii śniadanie”.
        let name = item.slot.lowercaseName
        let object = item.slot.accusativeName

        if item.isCooking {
            let lead = voice(["Pora gotować \(object)", "Do kuchni: \(name)", "Czas gotować \(object)"], "next-cooking", item: item)
            guard let time = item.time else { return lead }
            return "\(lead) · na \(time)"
        }
        if item.isDue { return voice(["Pora jeść \(object)", "Na stół: \(name)", "Czas jeść \(object)"], "next-due", item: item) }
        if item.isLate { return "Następny: \(name) · pora minęła" }

        let lead = voice(["Następny:", "Przed tobą:", "Na horyzoncie:"], "next-lead", item: item)
        var head = "\(lead) \(name)"
        if let away = item.minutesAway {
            head += " \(CalendarRelativeTime.text(inMinutes: away))"
        } else if let time = item.time {
            head += " o \(time)"
        }

        guard item.showsCookHint, let cookFrom = item.cookFrom else { return head }
        return "\(head) · gotuj od \(cookFrom)"
    }

    /// „Potem: kolacja · 20:00”, „Potem: przekąska · dowolna pora · bez planu”.
    private func afterText(_ item: CalendarPlateItem) -> String {
        let lead = voice(["Potem:", "Dalej:", "Później:", "A potem:"], "after-lead", item: item)
        var parts = ["\(lead) \(item.slot.lowercaseName)", item.time ?? "dowolna pora"]
        if item.isEmptySlot {
            parts.append("bez planu")
        } else if item.isEaten {
            parts.append("zjedzone")
        }
        return parts.joined(separator: " · ")
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

            CalendarDayLine(note: .after(items[2]), dayKey: "2026-09-11", onReturnToNext: {}, onSelect: { _ in })
            CalendarDayLine(note: .next(items[1]), dayKey: "2026-09-11", onReturnToNext: {}, onSelect: { _ in })
            CalendarDayLine(note: .last(items[3]), dayKey: "2026-09-11", onReturnToNext: {}, onSelect: { _ in })
            CalendarDayLine(note: .closed, dayKey: "2026-09-11", onReturnToNext: {}, onSelect: { _ in })
            CalendarDayLine(note: .empty(slots: 3), dayKey: "2026-09-11", onReturnToNext: {}, onSelect: { _ in })
        }
        .padding(.horizontal, SCPageMetrics.horizontal)
    }
    .preferredColorScheme(.dark)
}
