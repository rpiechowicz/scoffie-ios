import SwiftUI

// Kalendarz v11 · Talerz — danie dnia na środku ekranu.
//
// Źródło: canvas claude.ai → „Weekly Meals - Kalendarz v11 Talerz.html”,
// `components/cal-v11-plate-2.jsx` (`V11Plate2`). Dzień przestaje być listą
// wierszy: jedno danie stoi wielkim okrągłym zdjęciem na środku, a reszta
// dnia ciągnie się pod nim sekwencją małych talerzy (`CalendarPlateStrip`).
//
// Powód jest ten sam, dla którego łuk doby zastąpił kiedyś poziomą oś: lista
// czterech wierszy zużywała cały ekran, żeby powiedzieć cztery nazwy,
// a pytanie „co teraz jem” dostawało w niej dokładnie tyle samo miejsca, co
// „co jadłem o ósmej”. Talerz odpowiada na to jedno pytanie całą planszą,
// a pozostałe dania zostają widoczne — tylko mniejsze.
//
// Cztery rzeczy różnią ten talerz od makiety:
//
//  1. **„Zjedzone” bez godziny.** Makieta pisała „zjedzone 08:12”, ale plan
//     zapamiętuje `eatenByUserIds`, czyli KTO odhaczył, a nie KIEDY.
//     Zmyślona godzina byłaby gorsza niż jej brak — ta sama decyzja, którą
//     podjęliśmy wcześniej przy węzłach łuku doby.
//  2. **Odliczanie ustępuje, gdy jest co robić.** Makieta trzymała w wielkim
//     wierszu samo „za 4 h 19 min”. U nas, odkąd otwiera się okno gotowania
//     albo wypada pora posiłku, stoi tam „Pora gotować” i „Pora jeść” —
//     „za 3 min” przy daniu, które robi się kwadrans, odpowiada na pytanie,
//     którego nikt już nie zadaje.
//  3. **Talerz woła kolorem pory, kiedy jest co robić.** Poświata za
//     zdjęciem oddycha, a spod rantu wybija pierścień — ten sam ruch
//     i ta sama barwa, którymi dawniej wołał węzeł łuku. Kiedy nic nie wisi
//     w powietrzu, talerz stoi nieruchomo.
//  4. **Nazwa dania otwiera szczegóły.** Makieta nie miała z talerza
//     żadnego wyjścia — a szczegół posiłku jest jedynym miejscem, w którym
//     przestawia się porcje. Stuknięcie w sam talerz zostaje przy odhaczaniu,
//     tak jak w projekcie.

// MARK: - Danie na talerzu

/// Jedno danie dnia — albo pusta pora — gotowe do narysowania.
///
/// Wszystko, co wymaga wiedzy o CAŁYM dniu (który posiłek jest „następny”,
/// ile zostało do jego pory), liczy ekran i podaje tutaj gotowe. Talerz
/// rysuje, a nie wnioskuje: dwa niezależne wyliczenia „następnego” prędzej
/// czy później wskazałyby dwa różne dania w sekwencji i na środku.
struct CalendarPlateItem: Identifiable, Equatable {
    /// Ten sam klucz, którym ekran adresuje kafel dnia (`DayCard.id`).
    let id: String
    let slot: MealSlot
    let status: CalendarMealStatus
    /// Pora z rozkładu gospodarstwa („14:00”). `nil` = pora dowolna.
    let time: String?
    /// Nazwa dania. `nil` = pora bez zaplanowanego posiłku.
    let title: String?
    let imageURL: URL?
    /// Kalorie na jedną osobę — ta sama liczba, którą sumuje pigułka celu.
    let kcal: Int
    let prepMinutes: Int
    /// Godzina, o której trzeba stanąć przy garnkach („13:00”). `nil`, gdy
    /// nie ma czego gotować albo pora posiłku jest dowolna.
    let cookFrom: String?
    /// „2 porcje” — dopisywane tylko wtedy, gdy ktoś świadomie odszedł od
    /// reguły auto. To, że coś jest domyślne, nie jest informacją.
    let servingsNote: String?
    /// Minuty do pory posiłku; ujemne = pora minęła. `nil` dla dnia, który
    /// nie jest dzisiaj — wtedy nie ma czego odliczać.
    let minutesAway: Int?
    /// Dzień miniony, a posiłek nieodhaczony.
    let isMissed: Bool

    var isEmptySlot: Bool { title == nil }
    var isEaten: Bool { status.isEaten }
}

extension CalendarPlateItem {
    /// Najdalszy horyzont, na jaki uprzedzamy o gotowaniu.
    ///
    /// Pieczeń na cztery godziny trzymałaby talerz w stanie „pora gotować”
    /// przez pół popołudnia — a wtedy ten stan przestaje cokolwiek znaczyć.
    /// Dwie godziny to tyle, ile zajmuje najdłuższe danie w katalogu, i tyle,
    /// ile człowiek jest w stanie planować „zaraz”.
    static let cookWindow = 120

    /// Najkrótsze przygotowanie, o którym w ogóle warto uprzedzać.
    ///
    /// „Pora gotować” pięć minut przed jogurtem z granolą to nie
    /// przypomnienie, tylko szum — i jeszcze stan, który mignie przez dwa
    /// tyknięcia zegara i zniknie.
    static let minPrepHint = 10

    /// Czy o tym daniu jest sens uprzedzać z wyprzedzeniem.
    var showsCookHint: Bool { prepMinutes >= Self.minPrepHint }

    /// Pora gotować: okno przygotowania już się otworzyło, a posiłek jeszcze
    /// przed nami.
    var isCooking: Bool {
        guard status == .next, showsCookHint else { return false }
        guard let away = minutesAway, away > 0 else { return false }
        return away <= min(prepMinutes, Self.cookWindow)
    }

    /// Pora jeść — godzina posiłku wypadła, z tą samą tolerancją, z jaką
    /// dawny wiersz listy mówił „teraz”.
    var isDue: Bool {
        guard status == .next, let away = minutesAway else { return false }
        return away <= 0 && away >= -CalendarRelativeTime.graceMinutes
    }

    /// Pora minęła na dobre i nikt nie odhaczył.
    var isLate: Bool {
        guard status == .next, let away = minutesAway else { return false }
        return away < -CalendarRelativeTime.graceMinutes
    }

    /// Czy talerz ma oddychać. Tylko wtedy, gdy jest co zrobić — pulsujący
    /// talerz bez powodu to migająca dioda, a nie informacja.
    var isUrgent: Bool { isCooking || isDue }

    /// Barwa, którą niesie ten talerz.
    ///
    /// Szałwia znaczy „zjedzone” — to samo, co kropki w plakietce dnia nad
    /// talerzem. Kolor pory dostaje wyłącznie danie, które jest teraz
    /// następne; reszta stoi w przygaszonym piśmie, żeby jedna pora nie
    /// wołała głośniej od drugiej bez powodu.
    func accent(in scheme: ColorScheme) -> Color {
        if isEaten { return SCPalette.sage }
        if status == .next { return slot.cozyAccent }
        return Color.scLabel(scheme).opacity(0.28)
    }

    /// „OBIAD · 14:00” — nadpis nad talerzem.
    ///
    /// Dla pory, która ani nie nadeszła, ani nie minęła (dzień przyszły,
    /// miniony, pora dowolna) zostaje sama nazwa pory: godzina stoi wtedy pod
    /// talerzem w sekwencji i nie ma po co pisać jej dwa razy na jednym
    /// ekranie.
    var kicker: String {
        guard let time else { return slot.title.uppercased() }

        switch status {
        case .eaten, .next, .later:
            return "\(slot.title.uppercased()) · \(time)"
        case .anytime, .planned:
            return slot.title.uppercased()
        }
    }

    func kickerColor(in scheme: ColorScheme) -> Color {
        if isEaten { return SCPalette.sage }
        if status == .next && !isLate { return slot.cozyAccent }
        return Color.scMuted(scheme)
    }
}

// MARK: - Nadpis nad talerzem

/// Pora dnia i godzina nad talerzem — jedyna rzecz, która stoi nad zdjęciem.
///
/// Osobny widok, a nie pierwsze piętro podpisu, bo w projekcie stoi po
/// DRUGIEJ stronie talerza: nad nim. Kolor bierze stąd samo danie
/// (`CalendarPlateItem.kickerColor`), więc nadpis i pierścień wokół zdjęcia
/// nie mogą powiedzieć dwóch różnych rzeczy.
struct CalendarPlateKicker: View {
    let item: CalendarPlateItem?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(item?.kicker ?? " ")
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(item?.kickerColor(in: scheme) ?? Color.scMuted(scheme))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            // Pusty dzień nie ma pory, ale ma mieć tę samą wysokość: bez
            // spacji w miejscu nadpisu talerz podskakiwałby o trzynaście
            // punktów przy każdym wejściu w dzień bez planu.
            .opacity(item == nil ? 0 : 1)
            .contentTransition(.opacity)
            .animation(.smooth(duration: 0.3), value: item?.id)
    }
}

// MARK: - Talerz

/// Wielkie okrągłe zdjęcie dania z podwójnym rantem i pieczątką odhaczenia.
///
/// Stuknięcie odhacza — to jedyna czynność, którą ten ekran w ogóle zapisuje
/// (Kalendarz nie planuje). Dzień z przyszłości nie ma czego odhaczać, więc
/// wtedy talerz jest tylko obrazkiem.
struct CalendarPlate: View {
    let item: CalendarPlateItem?
    var size: CGFloat = CalendarPlate.defaultSize
    /// Dzień z przyszłości i pusta pora nie mają czego odhaczać.
    let canToggle: Bool
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Talerz zajmuje pół szerokości strony dnia, a strona jeździ palcem
    /// w bok — bez furtki machnięcie kończące się na talerzu odhaczałoby
    /// posiłek przy okazji przestawiania dnia.
    @Environment(\.dayPagerGate) private var pagerGate

    /// Średnica z makiety — od niej liczą się wszystkie proporcje.
    static let defaultSize: CGFloat = 168
    /// Najmniejsza, przy której zdjęcie jeszcze niesie danie, a nie ikonkę.
    static let minSize: CGFloat = 128

    private var scale: CGFloat { size / Self.defaultSize }
    /// Cienki rant zewnętrzny — sam kształt talerza, bez znaczenia.
    private var rimInset: CGFloat { (13 * scale).rounded() }
    /// Pierścień w kolorze pory — to on niesie stan.
    private var ringInset: CGFloat { (7 * scale).rounded() }
    private var ringWidth: CGFloat { max(2, (3 * scale).rounded()) }
    private var badgeSize: CGFloat { max(26, (32 * scale).rounded()) }

    private var accent: Color {
        item?.accent(in: scheme) ?? Color.scLabel(scheme).opacity(0.14)
    }

    private var isUrgent: Bool { item?.isUrgent == true }

    var body: some View {
        Button {
            pagerGate.ifNotSwiping(onToggle)
        } label: {
            // `ZStack` nie jest ozdobą: przejście przy podmianie dania gra
            // tylko wtedy, gdy widok o zmiennej tożsamości siedzi w JAKIMŚ
            // kontenerze. Etykieta przycisku sama w sobie nim nie jest —
            // bez tego opakowania talerz podmieniałby się twardym cięciem.
            ZStack {
                plate
                    // Podmiana dania na środku: krótki „pop”, jak w makiecie.
                    // To samo danie odhaczone zostaje na miejscu — zmienia mu
                    // się pierścień i pieczątka, a nie tożsamość.
                    .id(item?.id ?? "empty")
                    .transition(
                        .scale(scale: 0.94)
                        .combined(with: .opacity)
                    )
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(PlatePressStyle())
        .disabled(!canToggle)
        // Odcisk na identyfikatorze dania, nie na zdjęciu: to on rozstrzyga,
        // czy talerz ma się przełożyć („pop” z makiety), czy tylko zmienić
        // stan w miejscu. Bez tego modyfikatora podmiana byłaby twardym
        // cięciem — przejścia w SwiftUI grają tylko wtedy, gdy zmiana
        // identyczności leci w animowanej transakcji.
        .animation(.smooth(duration: 0.34), value: item?.id)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(actionHint)
    }

    private var plate: some View {
        face
            .frame(width: size, height: size)
            .clipShape(Circle())
            // Cień pod talerzem, nie pod pierścieniem: rant ma leżeć na
            // planszy, a samo danie unosić się nad nią.
            .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.22), radius: 26 * scale, y: 14 * scale)
            // Dwa ranty, licząc od zdjęcia na zewnątrz: pierścień pory tuż
            // przy krawędzi, a za nim cienka obwódka, która jest już samym
            // kształtem talerza. Makieta miała je odwrotnie ustawione
            // w kodzie, ale rysują się w tej samej kolejności.
            .overlay {
                Circle()
                    .strokeBorder(accent, lineWidth: ringWidth)
                    .padding(-ringInset)
                    .animation(.smooth(duration: 0.32), value: accent)
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.scLabel(scheme).opacity(scheme == .dark ? 0.10 : 0.08), lineWidth: 1)
                    .padding(-rimInset)
            }
            // Dwie warstwy pod talerzem, w tej kolejności (pierwsze
            // `.background` leży bliżej wierzchu).
            //
            // Pierścień wybijający spod rantu — sygnał „pora na to danie”.
            // Ten sam ruch i ta sama barwa, którymi dawniej wołał węzeł łuku
            // doby; stoi pod zdjęciem, więc WYCHODZI zza niego, zamiast
            // pojawiać się w locie.
            .background {
                if isUrgent {
                    if reduceMotion {
                        // Bez ruchu zostaje sam pierścień — w miejscu,
                        // w którym echosonda spędza połowę cyklu.
                        Circle()
                            .strokeBorder(accent.opacity(0.4), lineWidth: ringWidth)
                            .frame(width: size, height: size)
                            .scaleEffect(1.2)
                    } else {
                        CalendarPlatePing(tint: accent, diameter: size, lineWidth: ringWidth)
                    }
                }
            }
            // Głębiej — poświata w kolorze pory. Nie rozjaśnia dania, tylko
            // planszę wokół niego, i to ona oddycha, kiedy jest co robić.
            .background {
                CalendarPlateGlow(
                    tint: accent,
                    diameter: size * 2.02,
                    breathes: isUrgent && !reduceMotion
                )
            }
            .overlay(alignment: .bottomTrailing) {
                if let item, !item.isEmptySlot {
                    CalendarMealCheck(
                        status: item.status,
                        color: item.slot.cozyAccent,
                        size: badgeSize
                    )
                    .padding(3)
                    // Pieczątka wycina się z talerza krążkiem tła — inaczej
                    // kreskowane kółko „dowolnej pory” gubiło się na zdjęciu.
                    .background(Circle().fill(Color.scPageBase(scheme)))
                    .opacity(canToggle ? 1 : 0.55)
                    .offset(x: 4 * scale, y: 4 * scale)
                }
            }
    }

    @ViewBuilder
    private var face: some View {
        if let item, !item.isEmptySlot {
            photo(item)
        } else {
            // Pusta pora i pusty dzień dostają ten sam kreskowany talerz, co
            // kreskowane kółko na liście — jeden znak na „nic tu jeszcze nie
            // stoi”.
            ZStack {
                Circle().fill(Color.scChipBg(scheme))

                Circle()
                    .strokeBorder(
                        Color.scRule(scheme),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )

                Image(systemName: item?.slot.icon ?? "calendar")
                    .font(.system(size: size * 0.2, weight: .light))
                    .foregroundStyle(Color.scFaint(scheme))
            }
        }
    }

    private func photo(_ item: CalendarPlateItem) -> some View {
        Group {
            if let url = item.imageURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallback(item.slot)
                    }
                }
            } else {
                fallback(item.slot)
            }
        }
        // Zjedzone przygasa — zostaje czytelne, ale przestaje konkurować
        // z tym, co dopiero przed użytkownikiem. Ta sama reguła, co
        // w miniaturach w Planie tygodnia.
        .saturation(item.isEaten ? 0.5 : 1)
        .opacity(item.isEaten ? 0.78 : 1)
    }

    private func fallback(_ slot: MealSlot) -> some View {
        ZStack {
            LinearGradient(
                colors: [slot.cozyTint, slot.cozyTint.mix(with: .black, by: 0.40)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: slot.icon)
                .font(.system(size: size * 0.22, weight: .light))
                .foregroundStyle(Color.white.opacity(0.65))
        }
    }

    private var accessibilityLabel: String {
        guard let item else { return "Pusty dzień" }
        guard let title = item.title else {
            return "\(item.slot.title): nic nie zaplanowano"
        }
        var parts = [item.slot.title, title, "\(item.kcal) kcal"]
        if let time = item.time { parts.insert(time, at: 1) }
        if item.isEaten { parts.append("zjedzone") }
        return parts.joined(separator: ", ")
    }

    /// Co robi stuknięcie w talerz. Pusto, gdy nie robi nic — dzień
    /// z przyszłości i pusta pora nie mają czego odhaczać.
    private var actionHint: String {
        guard canToggle, let item, !item.isEmptySlot else { return "" }
        return item.isEaten ? "Cofnij oznaczenie zjedzenia" : "Oznacz jako zjedzone"
    }
}

// MARK: - Poświata

/// Miękka plama w kolorze pory za talerzem.
///
/// Oddycha wyłącznie wtedy, gdy jest co zrobić (`breathes`) — i oddycha
/// SKALĄ ORAZ KRYCIEM, a nie promieniem gradientu: gradient przeliczany co
/// klatkę kosztuje tyle, ile cały ten ekran razem wzięty.
private struct CalendarPlateGlow: View {
    let tint: Color
    let diameter: CGFloat
    let breathes: Bool

    @State private var inhaled = false

    var body: some View {
        // Jawny typ i osobna zmienna, a nie wyrażenie warunkowe wprost
        // w wywołaniu: w tym projekcie ternar z dwoma skróconymi nazwami
        // składowych potrafi zgłosić się kilkadziesiąt linii wyżej jako
        // `ambiguous use of 'init'` (patrz `CLAUDE.md`).
        let motion: Animation = breathes
            ? .easeInOut(duration: 2.2).repeatForever(autoreverses: true)
            : .smooth(duration: 0.4)

        return Circle()
            .fill(
                RadialGradient(
                    colors: [tint.opacity(0.22), tint.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter * 0.34
                )
            )
            .frame(width: diameter, height: diameter)
            // Odrobinę w górę: talerz ma stać w świetle, a nie na nim.
            .offset(y: -diameter * 0.05)
            .scaleEffect(inhaled ? 1.06 : 1)
            .opacity(inhaled ? 1 : 0.72)
            .animation(motion, value: inhaled)
            .animation(.smooth(duration: 0.45), value: tint)
            .onAppear { inhaled = breathes }
            .onChange(of: breathes) { _, value in inhaled = value }
            .allowsHitTesting(false)
    }
}

// MARK: - Pierścień „pora na to danie”

/// Pierścień wybijający spod talerza i gasnący — echosonda.
///
/// `autoreverses: false`, więc pierścień nie wraca do środka, tylko zaczyna
/// od nowa: powrót widać jako ruch wsteczny, a echosonda ma bić zawsze w tę
/// samą stronę. Skok na początek cyklu wypada przy zerowym kryciu, czyli
/// poza wzrokiem. Ramka jest STAŁA, oddycha `scaleEffect` — rosnąca ramka
/// kazałaby układowi przeliczać się co klatkę bez końca.
private struct CalendarPlatePing: View {
    let tint: Color
    let diameter: CGFloat
    let lineWidth: CGFloat

    @State private var expanded = false

    var body: some View {
        Circle()
            .strokeBorder(tint, lineWidth: lineWidth)
            .frame(width: diameter, height: diameter)
            .scaleEffect(expanded ? 1.26 : 1)
            .opacity(expanded ? 0 : 0.55)
            .animation(
                .easeOut(duration: 2.1).repeatForever(autoreverses: false),
                value: expanded
            )
            .onAppear { expanded = true }
            .allowsHitTesting(false)
    }
}

/// Dotknięcie talerza: samo ściśnięcie, bez zmiany krycia.
///
/// `PlainButtonStyle` przygasza etykietę do ~0,72 — na wierszu z tłem to
/// czytelna reakcja, ale tutaj etykietą jest zdjęcie leżące na własnej
/// poświacie, więc przygaszenie odsłaniało spod niego kolorową plamę.
private struct PlatePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - Pigułka szczegółu

/// Pigułka 30 pt pod nazwą dania: „gotuj od 13:00”, „60 min · 1208 kcal”,
/// „zjedzone”. Tapowalna wysokość, bo w makiecie pigułki stoją w jednym
/// rzędzie z odliczaniem i muszą się czytać z tej samej odległości.
struct CalendarPlateChip: View {
    let text: String
    var icon: String?
    /// Barwa akcentu. `nil` = pigułka neutralna, w przygaszonym piśmie.
    var tint: Color?

    @Environment(\.colorScheme) private var scheme

    private var color: Color { tint ?? Color.scMuted(scheme) }

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
            }

            Text(text)
                .font(.system(size: 12.5, weight: .bold))
                .tracking(-0.15)
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(
            Capsule().fill(tint.map { $0.opacity(0.14) } ?? Color.scChipBg(scheme))
        )
        .overlay(
            Capsule().strokeBorder(
                tint.map { $0.opacity(0.32) } ?? Color.scTileStroke(scheme),
                lineWidth: 1
            )
        )
        .fixedSize()
    }
}

// MARK: - Podpis talerza

/// Trzy piętra pod talerzem: nadpis z porą, wielkie zdanie o czasie, nazwa
/// dania i rząd pigułek ze szczegółami.
///
/// Cała treść liczy się TUTAJ, z jednego `CalendarPlateItem` — ekran podaje
/// fakty, a nie zdania. Dzięki temu „Pora gotować” w wielkim wierszu i kolor
/// pigułki „gotuj od” nie mogą się rozjechać: wynikają z tej samej liczby.
struct CalendarPlateCaption: View {
    let item: CalendarPlateItem?
    /// Otwiera szczegóły posiłku. `nil` dla pustej pory — nie ma czego
    /// otwierać.
    let onOpenDetail: (() -> Void)?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dayPagerGate) private var pagerGate

    var body: some View {
        VStack(spacing: 0) {
            Text(headline)
                .font(.system(size: 34, weight: .bold))
                .tracking(-1.3)
                .monospacedDigit()
                .foregroundStyle(headlineColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // Odliczanie tyka co minutę. Bez tego liczby podmieniałyby
                // się skokiem w miejscu, na które patrzy się najdłużej.
                .contentTransition(.numericText())

            if let title = item?.title {
                Button {
                    pagerGate.ifNotSwiping { onOpenDetail?() }
                } label: {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .tracking(-0.45)
                        .foregroundStyle(item?.isEaten == true ? Color.scMuted(scheme) : Color.scLabel(scheme))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 310)
                        .contentTransition(.opacity)
                }
                .buttonStyle(.plain)
                .disabled(onOpenDetail == nil)
                .padding(.top, 5)
                .accessibilityHint("Otwiera szczegóły posiłku")
            }

            if !chips.isEmpty {
                // Pigułki nie skracają się i nie zawijają w pół słowa —
                // „gotuj od 13:00” przełamane po „od” nie jest krótsze, tylko
                // gorsze. `ViewThatFits` próbuje najpierw jednego rzędu,
                // a gdy się nie mieści (długa godzina + porcje na SE),
                // schodzi na dwa. Kolejność jest ważna: pierwszy wariant,
                // który się mieści, wygrywa.
                ViewThatFits(in: .horizontal) {
                    chipRow(chips)

                    VStack(spacing: 6) {
                        chipRow(Array(chips.prefix(2)))
                        chipRow(Array(chips.dropFirst(2)))
                    }
                }
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity)
        // Podpis podmienia się treścią, a NIE tożsamością.
        //
        // Makieta unosiła go w całości („rise”), ale tam każdy talerz miał
        // podpis tej samej wysokości. U nas nazwa dania łamie się na jedną
        // albo dwie linijki, a pigułek bywa dwie albo cztery — przejście
        // przez tożsamość trzymałoby przez chwilę oba podpisy naraz i cała
        // strona podskakiwałaby o wysokość tego wyższego. Tekst przechodzi
        // więc kryciem w miejscu (`contentTransition`), a sam blok dojeżdża
        // do nowej wysokości tą samą sprężyną.
        .animation(.smooth(duration: 0.3), value: item?.id)
        // Odliczanie tyka co minutę osobno od podmiany dania: bez własnego
        // odcisku liczby przeskakiwałyby bez `numericText`.
        .animation(.smooth(duration: 0.25), value: headline)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func chipRow(_ row: [Chip]) -> some View {
        HStack(spacing: 6) {
            ForEach(row) { chip in
                CalendarPlateChip(text: chip.text, icon: chip.icon, tint: chip.tint)
            }
        }
    }

    // MARK: Treść

    private var headline: String {
        guard let item else { return "Pusty dzień" }
        if item.isEmptySlot { return "Nic nie zaplanowano" }
        if item.isEaten { return "Zjedzone" }

        switch item.status {
        case .next:
            // Odkąd okno gotowania jest otwarte, odliczanie przestaje być
            // odpowiedzią: „za 3 min” przy daniu, które robi się kwadrans,
            // mówi, ile zostało do JEDZENIA, a pytanie brzmi już co innego.
            if item.isCooking { return "Pora gotować" }
            if item.isDue { return "Pora jeść" }
            if item.isLate { return "Pora minęła" }
            guard let away = item.minutesAway else { return item.time ?? "Dowolna pora" }
            return CalendarRelativeTime.text(inMinutes: away)
        case .later:
            guard let away = item.minutesAway else { return item.time ?? "Dowolna pora" }
            return CalendarRelativeTime.text(inMinutes: away)
        case .anytime:
            return "Dowolna pora"
        case .planned:
            return item.time ?? "Dowolna pora"
        case .eaten:
            return "Zjedzone"
        }
    }

    private var headlineColor: Color {
        guard let item else { return Color.scMuted(scheme) }
        if item.isEmptySlot { return Color.scMuted(scheme) }
        if item.isEaten { return SCPalette.sage }
        guard item.status == .next else { return Color.scLabel(scheme) }
        if item.isLate { return Color.scMuted(scheme) }
        // Terakota znaczy „to jest następne”. Kiedy robi się pilnie, wielki
        // wiersz przechodzi w kolor pory — ten sam, którym w tej samej chwili
        // oddycha poświata pod talerzem.
        if item.isUrgent { return item.slot.cozyAccent }
        return SCPalette.terracotta
    }

    private struct Chip: Identifiable {
        let id: String
        let text: String
        var icon: String?
        var tint: Color?
    }

    private var chips: [Chip] {
        guard let item else { return [] }

        if item.isEmptySlot {
            return [Chip(id: "plan", text: "Zaplanujesz w Planie", icon: "square.and.pencil")]
        }

        var out: [Chip] = []

        if item.isEaten {
            out.append(Chip(id: "eaten", text: "zjedzone", icon: "checkmark", tint: SCPalette.sage))
        } else if item.isMissed {
            out.append(Chip(id: "missed", text: "nie odhaczone", icon: "xmark"))
        }

        // „Gotuj od” tylko dopóki gotowanie jest jeszcze przed nami — przy
        // zjedzonym daniu i przy minionej porze ta godzina już o niczym nie
        // mówi. Terakota, gdy to danie jest następne; kolor pory, gdy okno
        // gotowania właśnie się otworzyło.
        if !item.isEaten, !item.isMissed, item.showsCookHint, let cookFrom = item.cookFrom {
            var tint: Color?
            if item.isCooking {
                tint = item.slot.cozyAccent
            } else if item.status == .next {
                tint = SCPalette.terracotta
            }
            out.append(Chip(id: "cook", text: "gotuj od \(cookFrom)", icon: "flame", tint: tint))
        }

        var meta = "\(item.kcal) kcal"
        if item.prepMinutes > 0 { meta = "\(item.prepMinutes) min · \(meta)" }
        out.append(Chip(id: "meta", text: meta, icon: "clock"))

        if let servings = item.servingsNote {
            out.append(Chip(id: "servings", text: servings, icon: "person.2"))
        }
        return out
    }
}

#Preview("Talerz — stany") {
    let next = CalendarPlateItem(
        id: "ob", slot: .lunch, status: .next, time: "14:00",
        title: "Pierś z indyka pieczona z ziemniakami i brokułem",
        imageURL: nil, kcal: 604, prepMinutes: 60, cookFrom: "13:00",
        servingsNote: nil, minutesAway: 259, isMissed: false
    )
    let cooking = CalendarPlateItem(
        id: "ob2", slot: .lunch, status: .next, time: "14:00",
        title: "Pierś z indyka pieczona z ziemniakami i brokułem",
        imageURL: nil, kcal: 604, prepMinutes: 60, cookFrom: "13:00",
        servingsNote: "2 porcje", minutesAway: 45, isMissed: false
    )
    let eaten = CalendarPlateItem(
        id: "sn", slot: .breakfast, status: .eaten, time: "08:00",
        title: "Owsianka kakaowa z bananem", imageURL: nil, kcal: 510,
        prepMinutes: 12, cookFrom: "07:48", servingsNote: nil,
        minutesAway: -100, isMissed: false
    )
    let missed = CalendarPlateItem(
        id: "ko", slot: .dinner, status: .planned, time: "20:00",
        title: "Krem z pomidorów z grzankami", imageURL: nil, kcal: 355,
        prepMinutes: 26, cookFrom: "19:34", servingsNote: nil,
        minutesAway: nil, isMissed: true
    )

    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()

        ScrollView {
            VStack(spacing: 46) {
                ForEach([next, cooking, eaten, missed]) { item in
                    VStack(spacing: 0) {
                        CalendarPlateKicker(item: item)
                            .padding(.bottom, 14)
                        CalendarPlate(item: item, canToggle: true, onToggle: {})
                        CalendarPlateCaption(item: item, onOpenDetail: {})
                            .padding(.top, 18)
                    }
                }
            }
            .padding(.vertical, 40)
            .padding(.horizontal, SCPageMetrics.horizontal)
        }
    }
    .preferredColorScheme(.dark)
}
