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
// Pięć rzeczy różni ten talerz od makiety:
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
//  5. **Nowe danie wjeżdża od strony, z której przyszło.** Makieta miała
//     jeden „pop” w miejscu. U nas dzień do przodu i talerzyk na prawo
//     wjeżdżają z prawej, do tyłu i na lewo — z lewej; stare danie zawsze
//     gaśnie w miejscu. Kierunek jest jedyną rzeczą, której krycie nie
//     umie powiedzieć, a przy machnięciu palcem to on jest treścią ruchu.

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

    /// Czy pora tego dania jest jeszcze przed nami (dzisiaj) albo w ogóle
    /// nie jest dzisiaj. Godzina „gotuj od” po minionej porze już o niczym
    /// nie mówi.
    var isAhead: Bool {
        guard let away = minutesAway else { return true }
        return away > 0
    }

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

    /// Jedno zdanie dla VoiceOver: „Obiad, 14:00, Pierś z indyka, zjedzone”.
    /// Wspólne dla wielkiego talerza i talerzyka w sekwencji — ten sam
    /// element ma się przedstawiać tak samo, niezależnie od rozmiaru.
    var accessibilityDescription: String {
        var parts = [slot.title]
        if let time { parts.append(time) }
        parts.append(title ?? "nic nie zaplanowano")
        if isEaten { parts.append("zjedzone") }
        return parts.joined(separator: ", ")
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
            // punktów przy każdym wejściu w dzień bez planu. Krycie zostawia
            // element w drzewie dostępności, więc VoiceOver trzeba odesłać
            // osobno — inaczej zatrzymywałby się na pustym polu nad talerzem.
            .opacity(item == nil ? 0 : 1)
            .accessibilityHidden(item == nil)
            .contentTransition(.opacity)
            .animation(DayNavigationMotion.spring, value: item?.id)
            // Odhaczenie zmienia barwę nadpisu w miejscu (kolor pory →
            // szałwia); bez własnego odcisku przeskakiwałaby w jednej klatce,
            // podczas gdy pierścień wokół zdjęcia dojeżdża sprężyną.
            .animation(DayNavigationMotion.spring, value: item?.status)
    }
}

// MARK: - Powierzchnia talerza

/// Okrągłe zdjęcie dania — albo gradient pory, gdy przepis nie ma zdjęcia,
/// albo kreskowany krążek, gdy pora jest pusta.
///
/// JEDEN widok dla wielkiego talerza i dla talerzyków w sekwencji, bo to jest
/// ten sam znak w dwóch rozmiarach. Wcześniej każdy z nich miał własną kopię
/// gradientu i własny kreskowany krążek — i od pierwszej poprawki koloru
/// rozjeżdżałyby się po cichu.
///
/// Zdjęcie ma tożsamość po adresie: przy zmianie dnia stare przechodzi w nowe
/// kryciem, zamiast podmienić się w klatce. Pusta pora dostaje jeden wspólny
/// klucz — kreskowany krążek jest ten sam dla każdej pory i nie ma co w nim
/// przechodzić.
struct CalendarPlateFace: View {
    let item: CalendarPlateItem?
    let size: CGFloat

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            surface
                .id(key)
                .transition(.opacity)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var key: String {
        guard let item, !item.isEmptySlot else { return "empty" }
        return item.imageURL?.absoluteString ?? item.id
    }

    @ViewBuilder
    private var surface: some View {
        if let item, !item.isEmptySlot {
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
        } else {
            // Pusta pora i pusty dzień dostają ten sam kreskowany krążek, co
            // kreskowane kółko „dowolnej pory” — jeden znak na „nic tu
            // jeszcze nie stoi”. Pusty dzień nie ma pory, więc nie ma
            // i jej ikony; zostaje sam kalendarz.
            ZStack {
                Circle().fill(Color.scChipBg(scheme))

                Circle()
                    .strokeBorder(
                        Color.scRule(scheme),
                        style: StrokeStyle(lineWidth: size > 100 ? 1.5 : 1.2, dash: dash)
                    )

                Image(systemName: item?.slot.icon ?? "calendar")
                    .font(.system(size: iconSize, weight: .light))
                    .foregroundStyle(Color.scFaint(scheme))
            }
        }
    }

    private var dash: [CGFloat] { size > 100 ? [5, 4] : [3.5, 3] }
    private var iconSize: CGFloat { max(13, (size * (size > 100 ? 0.2 : 0.34)).rounded()) }

    /// Gradient pory pod ikoną — ten sam, którym Plan tygodnia rysuje kafel
    /// bez zdjęcia (`MealSlot.cozyGradient`), więc danie bez fotografii
    /// wygląda tak samo na obu zakładkach.
    private func fallback(_ slot: MealSlot) -> some View {
        ZStack {
            slot.cozyGradient

            Image(systemName: slot.icon)
                .font(.system(size: iconSize, weight: .light))
                .foregroundStyle(Color.white.opacity(0.65))
        }
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
    /// Skąd wjeżdża nowe danie: `1` z prawej (dzień albo talerzyk do przodu),
    /// `-1` z lewej, `0` w miejscu (odhaczenie, pierwsze wejście).
    var direction: Int = 0
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
    /// Najmniejsza, PRZY KTÓREJ TALERZ JESZCZE WOLI TRZYMAĆ ROZMIAR: poniżej
    /// zdjęcie przestaje nieść danie i staje się ikonką.
    ///
    /// To jest preferencja, nie gwarancja. Talerz jest jedynym piętrem tego
    /// ekranu, które wolno ścisnąć — reszta to tekst, a tekst albo się
    /// czyta, albo nie — więc na najkrótszych ekranach (SE z paskiem kroków)
    /// układ oddaje mu tyle, ile zostało, także poniżej tej liczby: talerz
    /// nigdy nie wychodzi poza swoje pudełko (patrz `CalendarView.plateSize`).
    static let minSize: CGFloat = 72
    /// O ile cienki rant zewnętrzny wychodzi poza zdjęcie przy pełnym
    /// rozmiarze. Układ dnia liczy z tego odstęp od sąsiadów: rant jest
    /// rysowany poza ramką talerza, więc bez tego zapasu dotykałby nadpisu.
    static let maxRimInset: CGFloat = 13

    private var scale: CGFloat { size / Self.defaultSize }
    /// Cienki rant zewnętrzny — sam kształt talerza, bez znaczenia.
    private var rimInset: CGFloat { Self.rimInset(for: size) }

    /// Rant zewnętrzny dla zadanej średnicy — JEDNO miejsce, z którego
    /// korzysta i sam talerz, i obrys podglądu menu kontekstowego w ekranie.
    /// W dół, jak średnica (`CalendarView.plateSize`): zdjęcie plus dwa
    /// ranty nie mogą przekroczyć pudełka nawet o punkt.
    static func rimInset(for size: CGFloat) -> CGFloat {
        (maxRimInset * size / defaultSize).rounded(.down)
    }
    /// Pierścień w kolorze pory — to on niesie stan.
    private var ringInset: CGFloat { (7 * scale).rounded() }
    private var ringWidth: CGFloat { max(2, (3 * scale).rounded()) }
    private var badgeSize: CGFloat { max(26, (32 * scale).rounded()) }

    private var accent: Color {
        item?.accent(in: scheme) ?? Color.scLabel(scheme).opacity(0.14)
    }

    private var isUrgent: Bool { item?.isUrgent == true }

    var body: some View {
        // Na dniu, którego nie da się odhaczać, talerz jest obrazkiem — nie
        // ma być czytany jako „przyciemniony przycisk”. Jawny typ, bo `[]`
        // i `.isButton` w jednym wyrażeniu warunkowym nie mają skąd wziąć
        // typu bez podpowiedzi.
        let hiddenTraits: AccessibilityTraits = canToggle ? [] : .isButton

        return Button {
            pagerGate.ifNotSwiping(onToggle)
        } label: {
            // `ZStack` nie jest ozdobą: przejście przy podmianie dania gra
            // tylko wtedy, gdy widok o zmiennej tożsamości siedzi w JAKIMŚ
            // kontenerze. Etykieta przycisku sama w sobie nim nie jest —
            // bez tego opakowania talerz podmieniałby się twardym cięciem.
            ZStack {
                plate
                    // Podmiana dania na środku. To samo danie odhaczone
                    // zostaje na miejscu — zmienia mu się pierścień
                    // i pieczątka, a nie tożsamość (ekran przypina wtedy
                    // odhaczone danie, żeby „następny” nie wypchnął go
                    // z talerza spod palca).
                    .id(item?.id ?? "empty")
                    .transition(swap)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(PlatePressStyle())
        .disabled(!canToggle)
        // Odcisk na identyfikatorze dania, nie na zdjęciu: to on rozstrzyga,
        // czy talerz ma się przełożyć, czy tylko zmienić stan w miejscu.
        // Ta sama sprężyna, którą jedzie strona dnia i podkreślenie na pasku
        // dni — jeden ruch na jedną czynność, także wtedy, gdy ta czynność
        // to zmiana dnia. Drugi odcisk na stan: odhaczenie przygasza zdjęcie
        // w miejscu i bez niego ten jeden ruch przeskakiwałby w klatce.
        .animation(DayNavigationMotion.spring, value: item?.id)
        .animation(DayNavigationMotion.spring, value: item?.status)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(actionHint)
        .accessibilityRemoveTraits(hiddenTraits)
    }

    /// Nowe danie wjeżdża od strony, z której przyszło; stare gaśnie
    /// w miejscu.
    ///
    /// Zejście CELOWO nie ma kierunku. Przejście zejścia bierze się z tego,
    /// co stało w widoku w chwili jego WSTAWIENIA — czyli z kierunku
    /// poprzedniej zmiany, nie tej. Gdyby stare danie odjeżdżało „w drugą
    /// stronę”, to przy zmianie kierunku (dzień w przód, potem w tył)
    /// odjeżdżałoby w tę samą stronę, z której wjeżdża nowe, i oba
    /// przecinałyby się na środku.
    private var swap: AnyTransition {
        let removal = AnyTransition.opacity.combined(with: .scale(scale: 0.96))

        if direction == 0 || reduceMotion {
            let pop = AnyTransition.scale(scale: 0.94).combined(with: .opacity)
            return .asymmetric(insertion: pop, removal: removal)
        }

        let slide = AnyTransition.offset(x: CGFloat(direction) * (size * 0.26).rounded())
        let arrival = slide.combined(with: .opacity).combined(with: .scale(scale: 0.96))
        return .asymmetric(insertion: arrival, removal: removal)
    }

    private var plate: some View {
        CalendarPlateFace(item: item, size: size)
            // Zjedzone przygasa — zostaje czytelne, ale przestaje konkurować
            // z tym, co dopiero przed użytkownikiem. Ta sama reguła, co
            // w miniaturach w Planie tygodnia.
            .saturation(item?.isEaten == true ? 0.5 : 1)
            .opacity(item?.isEaten == true ? 0.78 : 1)
            // Cień pod talerzem, nie pod pierścieniem: rant ma leżeć na
            // planszy, a samo danie unosić się nad nią.
            .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.22), radius: 26 * scale, y: 14 * scale)
            // Dwa ranty, licząc od zdjęcia na zewnątrz: pierścień pory tuż
            // przy krawędzi, a za nim cienka obwódka, która jest już samym
            // kształtem talerza.
            .overlay {
                Circle()
                    .strokeBorder(accent, lineWidth: ringWidth)
                    .padding(-ringInset)
                    .animation(DayNavigationMotion.spring, value: accent)
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

    private var accessibilityLabel: String {
        guard let item else { return "Pusty dzień" }
        guard !item.isEmptySlot else { return item.accessibilityDescription }
        // Kalorie tylko na wielkim talerzu — talerzyk w sekwencji ich nie
        // pokazuje, więc i nie czyta.
        return "\(item.accessibilityDescription), \(item.kcal) kcal"
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

/// Pigułka 30 pt pod nazwą dania: „gotuj od 13:00”, „60 min · 1208 kcal”.
/// Tapowalna wysokość, bo w makiecie pigułki stoją w jednym rzędzie
/// z odliczaniem i muszą się czytać z tej samej odległości.
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
                // Bez `fixedSize`: rząd pigułek ma się ŚCISNĄĆ, gdy danie ma
                // i „gotuj od”, i własną liczbę porcji, zamiast schodzić do
                // drugiego rzędu i podnosić wszystko pod spodem.
                .minimumScaleFactor(0.75)
                // Liczby w pigułce rolują się przy zmianie dania — „60 min ·
                // 1208 kcal” w „12 min · 510 kcal” — zamiast przeskakiwać.
                .contentTransition(.numericText())
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
        .animation(DayNavigationMotion.spring, value: tint)
    }
}

// MARK: - Podpis talerza

/// Trzy piętra pod talerzem: wielkie zdanie o czasie, nazwa dania i rząd
/// pigułek ze szczegółami.
///
/// Cała treść liczy się TUTAJ, z jednego `CalendarPlateItem` — ekran podaje
/// fakty, a nie zdania. Dzięki temu „Pora gotować” w wielkim wierszu i kolor
/// pigułki „gotuj od” nie mogą się rozjechać: wynikają z tej samej liczby.
///
/// Podpis ma STAŁĄ wysokość — tę samą dla każdego dania, dla pustej pory
/// i dla pustego dnia: odliczanie to zawsze jedna linijka, nazwa dostaje
/// z góry `titleLines` linijek (także wtedy, gdy jest krótsza albo nie ma
/// jej wcale), pigułki to zawsze jeden rząd. To jest warunek konieczny,
/// żeby sekwencja pod spodem stała w miejscu przy przekładaniu talerzy
/// i żeby talerz na pustym dniu stał dokładnie tam, gdzie na pełnym.
struct CalendarPlateCaption: View {
    let item: CalendarPlateItem?
    /// Ile linijek dostaje nazwa dania. Dwie na normalnym ekranie, jedna na
    /// krótkim, gdzie każde 23 pt idzie na talerz.
    var titleLines: Int = 2
    /// Czy w ogóle rysować rząd pigułek. Na najkrótszych ekranach (SE)
    /// czterdzieści punktów rzędu to różnica między talerzem a ikonką —
    /// wtedy szczegóły zostają w arkuszu posiłku, a tu zostaje nazwa.
    var showsChips: Bool = true
    /// Otwiera szczegóły posiłku. `nil` dla pustej pory — nie ma czego
    /// otwierać.
    let onOpenDetail: (() -> Void)?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dayPagerGate) private var pagerGate

    var body: some View {
        VStack(spacing: 0) {
            // Wielki wiersz ma tożsamość po daniu I po rodzaju zdania: między
            // daniami oraz między „za 4 h 19 min” a „Pora gotować” przechodzi
            // kryciem, a w obrębie tego samego odliczania (tyknięcie zegara)
            // roluje cyfry. Rolowanie „za 4 h 19 min” w „Pusty dzień” literka
            // po literce wyglądało jak usterka renderowania.
            ZStack {
                Text(headline)
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-1.3)
                    .monospacedDigit()
                    .foregroundStyle(headlineColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .id(headlineKey)
                    .transition(.opacity)
            }

            titleSlot
                .padding(.top, 5)

            // Jeden rząd, zawsze — także pusty. Pigułki, których jest za
            // dużo, ściskają się pismem, a nie schodzą do drugiego rzędu:
            // drugi rząd pojawiałby się i znikał zależnie od dania i cała
            // sekwencja pod spodem podskakiwałaby o trzydzieści sześć
            // punktów.
            if showsChips {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        CalendarPlateChip(text: chip.text, icon: chip.icon, tint: chip.tint)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .frame(height: 30)
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity)
        // Jedna sprężyna na przełożenie dania — ta sama, którą jedzie strona
        // dnia — druga na zmianę stanu w miejscu (odhaczenie przygasza nazwę
        // i wymienia pigułki) i osobny, krótszy odcisk na tyknięcie zegara.
        .animation(DayNavigationMotion.spring, value: item?.id)
        .animation(DayNavigationMotion.spring, value: item?.status)
        .animation(.smooth(duration: 0.25), value: headline)
        .accessibilityElement(children: .contain)
    }

    /// Nazwa dania w pudełku o wysokości `titleLines` linijek — zawsze,
    /// niezależnie od tego, ile nazwa faktycznie zajmuje i czy w ogóle jest.
    ///
    /// Wysokość bierze się z NARYSOWANEJ i schowanej próbki o tylu
    /// linijkach, a nie z liczby: linijka pisma 18 pt to nie jest okrągłe
    /// 23 pt (interlinia kroju systemowego, `tracking`, zaokrąglanie do
    /// piksela), a próbka w tym samym kroju mierzy się sama i nie rozjedzie
    /// się przy pierwszej zmianie wielkości pisma. Tekst jest ułożony do
    /// góry, więc pierwsza linijka nazwy stoi zawsze w tym samym miejscu —
    /// także po zmianie dnia.
    private var titleSlot: some View {
        ZStack(alignment: .top) {
            titleText(probe, eaten: false)
                .hidden()
                .accessibilityHidden(true)

            if let title = item?.title {
                Button {
                    pagerGate.ifNotSwiping { onOpenDetail?() }
                } label: {
                    titleText(title, eaten: item?.isEaten == true)
                        .contentTransition(.opacity)
                }
                .buttonStyle(.plain)
                .disabled(onOpenDetail == nil)
                .transition(.opacity)
                .accessibilityHint("Otwiera szczegóły posiłku")
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// Próbka o dokładnie `titleLines` linijkach.
    private var probe: String {
        Array(repeating: "X", count: max(1, titleLines)).joined(separator: "\n")
    }

    private func titleText(_ name: String, eaten: Bool) -> some View {
        Text(name)
            .font(.system(size: 18, weight: .semibold))
            .tracking(-0.45)
            .foregroundStyle(eaten ? Color.scMuted(scheme) : Color.scLabel(scheme))
            .multilineTextAlignment(.center)
            .lineLimit(titleLines)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 310)
    }

    // MARK: Treść

    private var headline: String {
        guard let item else { return "Pusty dzień" }
        if item.isEmptySlot { return "Nic nie zaplanowano" }

        switch item.status {
        case .eaten:
            return "Zjedzone"
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
            // Danie „później” może mieć porę za sobą (wieczorem, gdy nic nie
            // odhaczono, „następne” jest śniadanie, a obiad — „później”).
            // Wtedy mówi to samo, co mówiłoby jako następne, tym samym
            // wielkim zdaniem — nie odmieńcem „pora minęła” z małej litery.
            if away <= 0 {
                return away >= -CalendarRelativeTime.graceMinutes ? "Pora jeść" : "Pora minęła"
            }
            return CalendarRelativeTime.text(inMinutes: away)
        case .anytime:
            return "Dowolna pora"
        case .planned:
            return item.time ?? "Dowolna pora"
        }
    }

    /// Tożsamość wielkiego wiersza: danie plus RODZAJ zdania. Zdania
    /// z liczbami (odliczanie, godzina) dzielą jeden klucz, żeby cyfry
    /// rolowały; zdania ze słów mają klucz po treści, żeby zmiana rodzaju
    /// przechodziła kryciem.
    private var headlineKey: String {
        let base = item?.id ?? "empty"
        let kind = headline.contains(where: { $0.isNumber }) ? "digits" : headline
        return "\(base)|\(kind)"
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

    /// Pigułki mówią wyłącznie to, czego nie ma nigdzie wyżej na talerzu.
    /// „Zjedzone” niesie już wielki wiersz, szałwiowy nadpis i pieczątka —
    /// czwarty raz to samo słowo w pigułce nie było informacją.
    private var chips: [Chip] {
        // Pusty dzień i pusta pora mówią to samo: dokąd iść, żeby coś tu
        // stanęło. Ikona z dolnego menu, nie własna — użytkownik ma trafić
        // wzrokiem po tym samym znaku, który widzi w pasku pod spodem.
        guard let item, !item.isEmptySlot else {
            return [Chip(id: "plan", text: "Zaplanujesz w Planie", icon: MenuConstans.Plan.icon)]
        }

        var out: [Chip] = []

        if item.isMissed {
            out.append(Chip(id: "missed", text: "nie odhaczone", icon: "xmark"))
        }

        // „Gotuj od” tylko dopóki gotowanie jest jeszcze przed nami — przy
        // zjedzonym daniu, przy minionej porze (także dzisiejszej) ta godzina
        // już o niczym nie mówi. Terakota, gdy to danie jest następne; kolor
        // pory, gdy okno gotowania właśnie się otworzyło.
        if !item.isEaten, !item.isMissed, item.isAhead, item.showsCookHint, let cookFrom = item.cookFrom {
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
                    VStack(spacing: 16) {
                        CalendarPlateKicker(item: item)
                        CalendarPlate(item: item, canToggle: true, onToggle: {})
                            .padding(.vertical, CalendarPlate.maxRimInset)
                        CalendarPlateCaption(item: item, onOpenDetail: {})
                    }
                }

                VStack(spacing: 16) {
                    CalendarPlateKicker(item: nil)
                    CalendarPlate(item: nil, canToggle: false, onToggle: {})
                        .padding(.vertical, CalendarPlate.maxRimInset)
                    CalendarPlateCaption(item: nil, onOpenDetail: nil)
                }
            }
            .padding(.vertical, 40)
            .padding(.horizontal, SCPageMetrics.horizontal)
        }
    }
    .preferredColorScheme(.dark)
}
