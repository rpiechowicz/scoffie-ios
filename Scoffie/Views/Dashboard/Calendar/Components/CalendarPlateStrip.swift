import SwiftUI

// Kalendarz v11 · Talerz — sekwencja dnia pod wielkim talerzem.
//
// Źródło: canvas claude.ai → „Weekly Meals - Kalendarz v11 Talerz.html”,
// `components/cal-v11-plate-2.jsx` (dolna część `V11Plate2`). Pod wielkim
// talerzem stoi cały dzień w miniaturze: małe talerze z godziną i porą,
// wybrany rośnie. Stuknięcie przekłada danie na środek — to jedyna
// nawigacja tego ekranu.
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
//  3. **Pod sekwencją nie ma zdania.** Makieta pisała tam „2 z 4 zjedzone ·
//     1665 kcal” (`V11PDayLine`), a potem stała tu linia dnia z tym, co
//     dalej („Potem: kolacja · 20:00”, „Tym kończysz dzień”). Rafał
//     (23.09.2026): „tego nie potrzebujemy”. Kropki w nagłówku dnia, pigułka
//     kcal nad dolnym menu i obwódka następnego talerzyka w samej sekwencji
//     mówią to samo bez zdania, a miejsce po linii bierze talerz.
//
// Sekwencja nie bierze udziału w przekładaniu dania na talerz i o niczym
// przy tym nie melduje. Trzy wydania z rzędu brała: talerzyk gasł na czas
// lotu („dziura w tacy”), a każda kolumna meldowała układowi swój środek,
// żeby wielki talerz wiedział, skąd nadlecieć. Jedno i drugie wyszło razem
// z lotem (`CalendarPlate`), bo oba wynikały z tego samego błędnego
// założenia: że sekwencja jest TACĄ, z której danie się zdejmuje. Jest
// WSKAŹNIKIEM — mówi, przy której porze stoi wielki talerz, i wybrane danie
// widać tu i tam cały czas, także gdy nic się nie rusza. Talerzyk ma więc
// jedno zadanie przy przekładaniu: urosnąć i dostać obwódkę. Obrót talerza
// nie potrzebuje od sekwencji ani jednej liczby.

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
    let onSelect: (CalendarPlateItem) -> Void

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
        // Wybrany talerz rośnie, poprzedni maleje — sprężyną `lift`. To
        // JEDYNY ruch, jaki niesie przełożenie dania: wielki talerz nad
        // sekwencją tylko przenika zdjęciem (`DayNavigationMotion.plateFade`),
        // więc rosnący talerzyk i jego obwódka są tym, co mówi, że coś się
        // stało i gdzie. Drugi odcisk na dania i stany:
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

#Preview("Sekwencja dnia") {
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

        CalendarPlateStrip(items: items, selectedId: "ob", width: 353, onSelect: { _ in })
            .padding(.horizontal, SCPageMetrics.horizontal)
    }
    .preferredColorScheme(.dark)
}
