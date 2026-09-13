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
// Sześć rzeczy różni ten talerz od makiety:
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
//  3. **Talerz BIJE, kiedy jest co robić.** Nie „pulsuje”: bicie serca ma
//     dwa uderzenia — mocne i słabsze — potem pauzę, szybki wzrost i wolne
//     opadanie (`CalendarHeartbeat`). Talerz oddycha skalą, poświata
//     puchnie i jaśnieje z uderzeniem, a fala echosondy startuje przy każdym
//     uderzeniu — światło i pierścień są jednym rytmem, nie trzema
//     zegarami. Kiedy nic nie wisi w powietrzu, talerz stoi nieruchomo.
//  4. **Zdjęcie otwiera szczegóły, pieczątka odhacza.** Makieta odhaczała
//     stuknięciem w cały talerz i nie miała z niego żadnego wyjścia —
//     a szczegół posiłku jest jedynym miejscem, w którym przestawia się
//     porcje. Dwa osobne przyciski obok siebie: wielkie zdjęcie robi to, co
//     wielkie zdjęcie robi wszędzie indziej w aplikacji, a znaczek w rogu to,
//     co znaczek. Zapis (odhaczenie) nie może być tym gestem, który
//     najłatwiej wykonać przypadkiem.
//  5. **Zjedzone nie jest zielone.** Makieta malowała odhaczone danie
//     szałwią — a szałwia jest zarazem kolorem obiadu. Zjedzone śniadanie
//     wyglądało jak obiad. Odhaczenie schodzi na neutralny kolor pisma
//     (`Color.scChecked`), tak jak od dawna robi to sama pieczątka; pory
//     zostają swoje.
//  6. **Przełożone danie PRZYCHODZI OBROTEM TALERZA.** Makieta miała jeden
//     „pop” w miejscu. Próbowaliśmy wjazdu z boku (czytał się jak cięcie),
//     rozkwitu od środka (poprawny, ale niemy — nie mówił, skąd danie
//     przyszło) i trzy razy — lotu z talerzyka w sekwencji na środek, za
//     każdym razem inaczej dostrojonego. Lot poszedł do kosza w całości,
//     bo miał wadę nie do dostrojenia: SwiftUI nie interpolował modyfikatora
//     wstawionego PRZEZ PRZEJŚCIE (`AnyTransition.modifier(active:identity:)`),
//     więc zdjęcie pojawiało się małe przy talerzyku i przeskakiwało na
//     środek w jednej klatce. Do tego wisiał na zmierzonych miejscach
//     talerzyków, na dwóch zegarach, które musiały się zgadzać, i na stanie,
//     którego nie wolno było ruszyć w trakcie ruchu.
//
//     Teraz talerz OBRACA SIĘ wokół pionowej osi, jak odwracana moneta:
//     danie schodzące odwraca się od oka i znika za krawędzią, a w tej samej
//     chwili nowe wychodzi z krawędzi po drugiej stronie (`PlateTurn`).
//     Obie połowy jadą w tę samą stronę, więc oko widzi jeden przedmiot,
//     który się obrócił — nie dwa, które się wymieniły. Strona obrotu bierze
//     się z tego, czy danie stoi w sekwencji na prawo, czy na lewo od
//     poprzedniego, więc ruch nadal mówi, SKĄD przyszło danie. Przejęcie
//     wypada tam, gdzie oba zdjęcia są zwrócone krawędzią do oka i mają
//     zerową szerokość — cięcie jest niewidoczne i nie potrzebuje zgrania
//     w klatkę.
//
//     Trzy rzeczy, których w tym ruchu NIE MA i mieć nie może: pomiaru
//     (obrót nie wie i nie musi wiedzieć, gdzie stoją talerzyki), drugiego
//     zegara (jedna liczba prowadzi całą geometrię, a nieciągłość siedzi
//     w czystej funkcji tej liczby, nie w stanie) i skali — nic nie rośnie
//     od małego, bo „pojawia się małe i rośnie” to był właśnie ten objaw.
//     Gdyby obrót kiedyś przestał się interpolować, danie po prostu
//     zmieniłoby się w miejscu.
//
//     Stan obrotu prowadzi EKRAN (`CalendarPlateSwap` w `CalendarView`),
//     bo musi wejść w tej samej klatce, co podmiana dania — dokładnie tak,
//     jak `DayPager` ustawia `dayTurn` razem z datą. Poświata i echosonda
//     nie obracają się razem z talerzem, ale przygasają na czas obrotu
//     i wzbierają, gdy nowe danie stanie płasko (`seat`): świeci talerz
//     z daniem, a nie sam talerz. Zmiana DNIA to nadal co innego — wtedy
//     cały dzień jedzie w bok obrotem tacy (`CalendarView.dayPage`).
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

    /// Czy talerz ma bić. Tylko wtedy, gdy jest co zrobić — bijący talerz
    /// bez powodu to migająca dioda, a nie informacja.
    var isUrgent: Bool { isCooking || isDue }

    /// Barwa, którą niesie ten talerz.
    ///
    /// Zjedzone jest NEUTRALNE — kolor pisma, nie szałwia: szałwia jest
    /// kolorem obiadu i zjedzone śniadanie wyglądało jak obiad. Kolor pory
    /// dostaje wyłącznie danie, które jest teraz następne; reszta stoi
    /// w przygaszonym piśmie, żeby jedna pora nie wołała głośniej od drugiej
    /// bez powodu.
    func accent(in scheme: ColorScheme) -> Color {
        if isEaten { return Color.scChecked(scheme).opacity(0.55) }
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
        if isEaten { return Color.scChecked(scheme).opacity(0.7) }
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
            .animation(DayNavigationMotion.lift, value: item?.id)
            // Odhaczenie zmienia barwę nadpisu w miejscu (kolor pory →
            // neutralny); bez własnego odcisku przeskakiwałaby w jednej
            // klatce, podczas gdy pierścień wokół zdjęcia dojeżdża sprężyną.
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
/// Zdjęcie ma tożsamość po adresie: przy zmianie dania w tej samej kolumnie
/// stare przechodzi w nowe kryciem, zamiast podmienić się w klatce. Pusta
/// pora dostaje jeden wspólny klucz — kreskowany krążek jest ten sam dla
/// każdej pory i nie ma co w nim przechodzić.
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

// MARK: - Bicie serca

/// Rytm talerza, który woła: „lub-dub”, pauza, i od nowa.
///
/// Liczone z ZEGARA, nie z trzech niezależnych animacji `repeatForever`.
/// Poprzedni puls to była poświata jadąca w tę i z powrotem sinusoidą plus
/// dwa pierścienie startujące co dwie sekundy z własnych stoperów — trzy
/// zegary, które nigdy nie były w rytmie, i ruch, który wyglądał jak
/// oddychanie maszyny. Serce ma dwa uderzenia: mocne i zaraz po nim słabsze,
/// każde z szybkim wzrostem i wolniejszym opadaniem, a potem chwilę ciszy.
/// Jedna funkcja czasu daje skalę talerza, poświatę i start każdej fali
/// echosondy — więc wszystko bije razem.
///
/// Czas bierze się z `Date` odczytanego przez `TimelineView`, więc dwa
/// talerze (dzień wychodzący i wchodzący w trakcie obrotu tacy) biją w tym
/// samym rytmie, a pauza w tle (`paused`) nie zostawia niczego w pół drogi.
enum CalendarHeartbeat {
    /// Jeden cykl: dwa uderzenia i pauza. Wolniej niż serce w spoczynku —
    /// to ma być spokojne przypomnienie, nie alarm.
    static let cycle: TimeInterval = 2.4
    /// Kiedy w cyklu (0–1) padają uderzenia i jak mocno drugie w stosunku
    /// do pierwszego.
    private static let beats: [(at: Double, strength: Double)] = [(0.06, 1.0), (0.30, 0.55)]
    /// Fala echosondy żyje ~1,5 s: startuje przy uderzeniu i gaśnie
    /// w połowie następnego cyklu.
    private static let waveSpan = 0.62

    /// Siła uderzenia w tej chwili, 0–1. Zero między uderzeniami.
    static func beat(at date: Date) -> Double {
        let t = phase(at: date)
        let sum = beats.reduce(0.0) { $0 + $1.strength * bump(t, at: $1.at) }
        return min(1, sum)
    }

    /// Postęp każdej żywej fali echosondy, 0 (start przy uderzeniu) – 1
    /// (zgasła). Najwyżej dwie naraz.
    static func waves(at date: Date) -> [Double] {
        let t = phase(at: date)
        return beats.compactMap { beat in
            let r = (t - beat.at) / waveSpan
            return r >= 0 && r <= 1 ? r : nil
        }
    }

    private static func phase(at date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        return elapsed / cycle
    }

    /// Uderzenie: stromy wzrost (szerokość 0,035 cyklu), łagodne opadanie
    /// (0,09). Krzywa Gaussa po obu stronach, ale z różnymi szerokościami —
    /// symetryczny garb wyglądał jak wahadło, nie jak skurcz.
    private static func bump(_ t: Double, at center: Double) -> Double {
        let width = t < center ? 0.035 : 0.09
        let d = (t - center) / width
        return exp(-d * d)
    }
}

// MARK: - Talerz

/// Wielkie okrągłe zdjęcie dania z podwójnym rantem i pieczątką odhaczenia.
///
/// Dwa przyciski obok siebie, nie jeden w drugim: zdjęcie otwiera szczegóły
/// posiłku (jak każde zdjęcie dania w aplikacji), pieczątka w rogu odhacza
/// — jedyna czynność, którą ten ekran w ogóle zapisuje (Kalendarz nie
/// planuje). Dzień z przyszłości nie ma czego odhaczać, więc pieczątka jest
/// wtedy przygaszona; pusta pora nie ma czego otwierać, więc zdjęcie jest
/// wtedy tylko obrazkiem.
struct CalendarPlate: View {
    let item: CalendarPlateItem?
    var size: CGFloat = CalendarPlate.defaultSize
    /// Dzień z przyszłości i pusta pora nie mają czego odhaczać.
    let canToggle: Bool
    /// Pieczątka w rogu — odhacza.
    let onToggle: () -> Void
    /// Zdjęcie — otwiera szczegóły. `nil` dla pustej pory i pustego dnia.
    let onOpenDetail: (() -> Void)?
    /// Gdzie jest talerz w obrocie i co z niego schodzi. Ekran prowadzi ten
    /// ruch, bo musi ustawić go w TEJ SAMEJ zmianie stanu, co podmianę dania
    /// (patrz `CalendarPlateSwap`).
    var swap: CalendarPlateSwap = .settled

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Talerz zajmuje pół szerokości strony dnia, a strona jeździ palcem
    /// w bok — bez furtki machnięcie kończące się na talerzu otwierałoby
    /// posiłek przy okazji przestawiania dnia.
    @Environment(\.dayPagerGate) private var pagerGate

    /// Średnica z makiety — od niej liczą się wszystkie proporcje.
    static let defaultSize: CGFloat = 168
    /// Najmniejsza, PRZY KTÓREJ TALERZ JESZCZE WOLI TRZYMAĆ ROZMIAR: poniżej
    /// zdjęcie przestaje nieść danie i staje się ikonką.
    ///
    /// To jest preferencja, nie gwarancja. Talerz jest jedynym piętrem tego
    /// ekranu, które wolno ścisnąć — reszta to tekst, a tekst albo się
    /// czyta, albo nie — więc układ dnia oddaje mu tyle, ile zostało, także
    /// poniżej tej liczby: talerz nigdy nie wychodzi poza swoje pudełko
    /// (patrz `CalendarView.plateSize`), a o pudełko nie mniejsze od podłogi
    /// dba wybór trybu układu, który na najkrótszym ekranie zdejmuje kroki.
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

    private func accent(of item: CalendarPlateItem?) -> Color {
        item?.accent(in: scheme) ?? Color.scLabel(scheme).opacity(0.14)
    }

    private var isUrgent: Bool { item?.isUrgent == true }
    /// Czy serce bije: jest co robić i ruch nie jest wyłączony w dostępności.
    private var beats: Bool { isUrgent && !reduceMotion }

    var body: some View {
        ZStack {
            // Światło sceny POD daniem: poświata i echosonda nie obracają się
            // razem z talerzem (obracająca się plama światła to byłaby
            // latarnia, nie talerz). Ale nie stoją NIERUCHOMO: świeci talerz
            // Z DANIEM, nie sam talerz, więc w chwili, w której talerz stoi
            // krawędzią do oka, światło jest najsłabsze i wzbiera dopiero,
            // gdy nowe danie staje płasko (`seat`).
            CalendarPlateLight(
                tint: accent(of: item),
                diameter: size,
                ringWidth: ringWidth,
                loud: isUrgent,
                beats: beats,
                reduceMotion: reduceMotion
            )
            .id(item?.id ?? "empty")
            .transition(seat)
            // Własny odcisk, żeby światło przechodziło także wtedy, gdy danie
            // zmieniło się BEZ obrotu (minęła pora, plan przyszedł z serwera):
            // wtedy `swap.turn` stoi i transakcja obrotu nie powstaje. Czasy
            // niosą krzywe doczepione do `seat`, nie ta sprężyna.
            .animation(DayNavigationMotion.spring, value: item?.id)

            // Danie SCHODZĄCE z talerza — rysowane obok wchodzącego tylko na
            // czas obrotu i tylko w jego pierwszej połowie. Martwa kopia:
            // nie przyjmuje dotyku i nie istnieje dla VoiceOvera, bo to samo
            // danie jest w tej chwili osiągalne w sekwencji pod talerzem.
            //
            // `.identity` nie jest ozdobą: bez niej SwiftUI wstawiłby tę kopię
            // domyślnym przejściem kryciem, w transakcji obrotu, więc zdjęcie,
            // które JUŻ stoi na ekranie, wzbierałoby od zera — a nowe jest
            // w tej chwili schowane za krawędzią. Efekt: pół sekundy pustego
            // talerza na starcie. Kopia ma się pojawić w pełni i natychmiast,
            // bo to nie jest nic nowego: to jest to, co widać.
            if let leaving = swap.leaving {
                stage(leaving, live: false)
                    .transition(.identity)
                    .modifier(swap.effect(isLeaving: true, flat: reduceMotion))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            stage(item, live: true)
                .modifier(swap.effect(isLeaving: false, flat: reduceMotion))
        }
        // Obrót ma WŁASNY odcisk i własną krzywą, założoną tuż nad ruchem:
        // wewnętrzny `.animation` wygrywa z każdą transakcją z góry, więc
        // odhaczenie ani tyknięcie zegara nie mogą mu podmienić czasu.
        .animation(DayNavigationMotion.plateTurn, value: swap.turn)
        .frame(width: size, height: size)
        // Odhaczenie przygasza zdjęcie i przestawia pierścień W MIEJSCU —
        // bez tożsamości i bez obrotu, więc potrzebuje własnego odcisku,
        // inaczej ten jeden ruch przeskakiwałby w klatce.
        .animation(DayNavigationMotion.spring, value: item?.status)
    }

    /// Zdjęcie i pieczątka — dwa osobne przyciski w jednym pudełku.
    ///
    /// Nie przycisk w przycisku: zagnieżdżone przyciski w SwiftUI dzielą
    /// jeden obszar dotyku i o tym, który zadziała, decyduje kolejność
    /// w drzewie, nie miejsce stuknięcia. Obok siebie każdy ma swój obszar.
    /// `live` = to danie stoi na talerzu teraz. Kopia schodząca z obrotu ma
    /// `false`: nie bije rytmem serca (dwa bijące zdjęcia w jednym miejscu to
    /// dwa rytmy) i nie zużywa klatek na zegar, którego nikt nie zobaczy.
    private func stage(_ item: CalendarPlateItem?, live: Bool) -> some View {
        // Na pustej porze zdjęcie jest obrazkiem — nie ma być czytane jako
        // „przyciemniony przycisk”. Jawny typ, bo `[]` i `.isButton` w jednym
        // wyrażeniu warunkowym nie mają skąd wziąć typu bez podpowiedzi.
        let hiddenTraits: AccessibilityTraits = onOpenDetail == nil ? .isButton : []

        return ZStack(alignment: .bottomTrailing) {
            Button {
                pagerGate.ifNotSwiping { onOpenDetail?() }
            } label: {
                plate(item, live: live)
            }
            .buttonStyle(PlatePressStyle())
            .disabled(onOpenDetail == nil)
            .accessibilityLabel(accessibilityLabel(of: item))
            .accessibilityHint(onOpenDetail == nil ? "" : "Otwiera szczegóły posiłku")
            .accessibilityRemoveTraits(hiddenTraits)

            if let item, !item.isEmptySlot {
                CalendarPlateStamp(
                    status: item.status,
                    color: item.slot.cozyAccent,
                    size: badgeSize,
                    isEnabled: canToggle,
                    action: { pagerGate.ifNotSwiping(onToggle) }
                )
                .offset(x: 4 * scale, y: 4 * scale)
            }
        }
        .frame(width: size, height: size)
    }

    /// Światło talerza: przygasa, gdy talerz staje krawędzią, i wzbiera, gdy
    /// nowe danie staje płasko.
    ///
    /// Poświata nie obraca się razem z talerzem — ale świeci DANIE na
    /// talerzu, nie sam talerz, więc nie ma prawa świecić pełnym blaskiem
    /// w chwili, gdy żadne zdjęcie nie jest zwrócone do oka.
    ///
    /// Dwa czasy, nierówno rozstawione. Stare światło gaśnie szybko (0,18 s,
    /// czyli zanim talerz dojdzie do krawędzi), a nowe wzbiera krzywą, która
    /// zwleka na starcie (`easeIn` 0,40 s). Dzięki temu w chwili obrotu suma
    /// obu jest niska, a pełnia przychodzi chwilę PO tym, jak nowe danie
    /// stanie płasko. Czyta się to jak zapalanie się talerza pod daniem.
    ///
    /// Tożsamość po daniu, nie po kolorze: barwa pory zmienia się skokiem
    /// razem z daniem, a przenikanie robią dwie warstwy. Interpolowanie
    /// samego `tint` między porami prowadziło przez szarość w połowie drogi.
    /// Rytm serca nie gubi taktu przy podmianie — `CalendarHeartbeat` liczy
    /// z zegara bezwzględnego, więc świeży widok wchodzi w tej samej fazie.
    private var seat: AnyTransition {
        if reduceMotion { return .opacity }

        let glow = AnyTransition.opacity.combined(with: .scale(scale: 0.9))
        return .asymmetric(
            insertion: glow.animation(.easeIn(duration: 0.40)),
            removal: glow.animation(.easeOut(duration: 0.18))
        )
    }

    /// Talerz w rytmie serca.
    ///
    /// `TimelineView` z harmonogramem animacji odczytuje zegar co klatkę,
    /// ALE tylko dopóki serce bije (`paused`): talerz, który stoi, nie
    /// kosztuje ani jednej klatki. Poświata i fale (`CalendarPlateLight`)
    /// mają własny odczyt tego samego harmonogramu — obie warstwy pauzują
    /// i ruszają tym samym `beats` w tym samym przebiegu, a `CalendarHeartbeat`
    /// liczy z czasu czystą funkcją, więc różnica faz jest podklatkowa przy
    /// 84-milisekundowym zboczu uderzenia. Mieszkają osobno, bo talerz obraca
    /// się razem z daniem, a światło zostaje na scenie.
    ///
    /// Kopia schodząca z obrotu ma `live: false` i nie bije wcale: dwa
    /// zdjęcia oddychające w jednym miejscu to dwa rytmy, a jedno z nich
    /// i tak zaraz zniknie za krawędzią.
    private func plate(_ item: CalendarPlateItem?, live: Bool) -> some View {
        let beating = live && item?.isUrgent == true && !reduceMotion

        return TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !beating)) { context in
            let beat = beating ? CalendarHeartbeat.beat(at: context.date) : 0

            plateBody(item)
                // Talerz oddycha razem z uderzeniem — dwa i pół procenta to
                // tyle, ile widać jako życie, a za mało, żeby zdjęcie
                // „skakało”.
                .scaleEffect(1 + 0.024 * beat)
        }
    }

    /// Zdjęcie z rantami i cieniem — bez rytmu. To, co bije, jest nałożone
    /// wyżej (`plate`), żeby zegar nie przebudowywał zdjęcia co klatkę.
    private func plateBody(_ item: CalendarPlateItem?) -> some View {
        // W OBROCIE zdjęcie podmienia się natychmiast, poza nim przenika.
        //
        // Talerz zachowuje tożsamość przez cały obrót (musi, inaczej
        // `PlateTurn` nie miałby czego interpolować), więc zmiana dania
        // dochodzi do środka jako zmiana samego zdjęcia — a `CalendarPlateFace`
        // przenika zdjęcia kryciem. W transakcji obrotu to przenikanie
        // wypadałoby DOKŁADNIE na jego drugiej połowie i danie wychodziłoby
        // z krawędzi jako zlepek dwóch zdjęć. Obrót pokazuje zamianę sam,
        // i lepiej — więc w obrocie przenikania nie ma.
        //
        // Bez obrotu jest odwrotnie: danie, które zmieniło się samo (minęła
        // pora, plan przyszedł z serwera), nie ma żadnego ruchu, który by
        // o tym powiedział, i twarde cięcie zdjęcia czyta się jak usterka
        // odświeżania. Zostaje mu więc krótkie przenikanie.
        //
        // Jawny typ, bo `nil` obok wywołania w wyrażeniu warunkowym potrafi
        // w tym projekcie zgubić wnioskowanie (SE-0418, patrz `CLAUDE.md`).
        var faceFade: Animation? = .easeInOut(duration: 0.28)
        if swap.turning { faceFade = nil }

        return CalendarPlateFace(item: item, size: size)
            // Odcisk na identyfikatorze, nie na wszystkim: odhaczenie
            // (`item?.status`) ma dalej swoją sprężynę z wierzchu.
            .animation(faceFade, value: item?.id)
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
                    .strokeBorder(accent(of: item), lineWidth: ringWidth)
                    .padding(-ringInset)
                    .animation(DayNavigationMotion.spring, value: accent(of: item))
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.scLabel(scheme).opacity(scheme == .dark ? 0.10 : 0.08), lineWidth: 1)
                    .padding(-rimInset)
            }
    }

    private func accessibilityLabel(of item: CalendarPlateItem?) -> String {
        guard let item else { return "Pusty dzień" }
        guard !item.isEmptySlot else { return item.accessibilityDescription }
        // Kalorie tylko na wielkim talerzu — talerzyk w sekwencji ich nie
        // pokazuje, więc i nie czyta.
        return "\(item.accessibilityDescription), \(item.kcal) kcal"
    }
}

// MARK: - Pieczątka

/// Znaczek odhaczenia w rogu talerza — osobny przycisk z własnym obszarem
/// dotyku (44 pt) i własnym ruchem.
///
/// Przy odhaczeniu podskakuje: to jedyny zapis na tym ekranie i ma być
/// widać, że coś się STAŁO, a nie tylko zmieniło kolor. Powrót sprężyną
/// z niskim tłumieniem — pieczątka, nie przełącznik.
private struct CalendarPlateStamp: View {
    let status: CalendarMealStatus
    let color: Color
    let size: CGFloat
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false

    var body: some View {
        Button(action: action) {
            CalendarMealCheck(status: status, color: color, size: size)
                .padding(3)
                // Pieczątka wycina się z talerza krążkiem tła — inaczej
                // kreskowane kółko „dowolnej pory” gubiło się na zdjęciu.
                .background(Circle().fill(Color.scPageBase(scheme)))
                .scaleEffect(popped ? 1.3 : 1)
                .scTapTarget(44, drawn: size + 6)
        }
        .buttonStyle(StampPressStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: popped)
        .onChange(of: status) { _, value in
            guard value == .eaten, !reduceMotion else { return }
            popped = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))
                popped = false
            }
        }
        .accessibilityLabel(status.isEaten ? "Cofnij oznaczenie zjedzenia" : "Oznacz jako zjedzone")
    }
}

/// Dotknięcie pieczątki: wyraźne ściśnięcie, jak wciśnięcie guzika.
private struct StampPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Poświata

/// Miękka plama w kolorze pory za talerzem.
///
/// Bez własnego stanu i bez własnego zegara: siłę uderzenia (`beat`) podaje
/// talerz z jednej chwili zegara, tej samej, z której liczy własną skalę
/// i fale echosondy. Kiedy woła (`loud`), plama jest mocniejsza i szersza
/// — cicha poświata pod talerzem o średnicy 168 pt ginęła na ciemnym tle
/// i puls było widać dopiero, gdy się go szukało.
private struct CalendarPlateGlow: View {
    let tint: Color
    let diameter: CGFloat
    let loud: Bool
    /// Siła uderzenia 0–1; zero, gdy talerz stoi.
    let beat: Double

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [tint.opacity(loud ? 0.44 : 0.22), tint.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter * (loud ? 0.4 : 0.34)
                )
            )
            .frame(width: diameter, height: diameter)
            // Odrobinę w górę: talerz ma stać w świetle, a nie na nim.
            .offset(y: -diameter * 0.05)
            .scaleEffect(1 + 0.16 * beat)
            .opacity((loud ? 0.55 : 0.72) + 0.45 * beat)
            // Barwa i siła światła osiadają razem z daniem, nie po nim:
            // przy 0,45 s poświata dochodziła do koloru nowej pory grubo po
            // tym, jak talerz już stał.
            .animation(.smooth(duration: 0.3), value: tint)
            .animation(.smooth(duration: 0.3), value: loud)
            .allowsHitTesting(false)
    }
}

// MARK: - Fala echosondy

/// Jeden pierścień wybijający spod talerza — startuje przy uderzeniu serca
/// i gaśnie, rozchodząc się.
///
/// Bez własnej animacji: postęp 0–1 podaje talerz z zegara serca
/// (`CalendarHeartbeat.waves`). Ramka jest STAŁA, rośnie `scaleEffect` —
/// rosnąca ramka kazałaby układowi przeliczać się co klatkę bez końca.
/// Krycie gaśnie szybciej, niż pierścień rośnie (kwadrat), żeby fala
/// rozpływała się, a nie „wyłączała”.
private struct CalendarPlateWave: View {
    let tint: Color
    let diameter: CGFloat
    let lineWidth: CGFloat
    let progress: Double

    var body: some View {
        let eased = 1 - pow(1 - progress, 2)

        Circle()
            .strokeBorder(tint, lineWidth: lineWidth)
            .frame(width: diameter, height: diameter)
            .scaleEffect(1 + 0.5 * eased)
            .opacity(0.9 * pow(1 - progress, 1.6))
            .allowsHitTesting(false)
    }
}

// MARK: - Światło sceny

/// Poświata i echosonda pod talerzem — w rytmie serca, ale POZA daniem.
///
/// Osobny widok z własnym odczytem zegara, bo talerz ma tożsamość dania
/// i przy przełożeniu leci z tacy albo na tacę — a światło jest sceną
/// i ma stać na środku, tylko zmieniając barwę pory. Harmonogram jest ten
/// sam co w `CalendarPlate.plate`, oba widoki pauzują i ruszają tym samym
/// `beats` w tym samym przebiegu, a `CalendarHeartbeat` liczy z czasu
/// czystą funkcją — więc oddech talerza i uderzenie poświaty padają razem
/// z dokładnością do klatki (zbocze uderzenia trwa 84 ms, więc tego nie
/// widać). Dwie warstwy w kolejności od spodu: głębiej poświata, bliżej
/// wierzchu echosonda.
private struct CalendarPlateLight: View {
    let tint: Color
    let diameter: CGFloat
    let ringWidth: CGFloat
    /// Czy jest co robić — mocniejsza poświata i fale.
    let loud: Bool
    /// Czy serce bije: jest co robić i ruch nie jest wyłączony w dostępności.
    let beats: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !beats)) { context in
            let beat = beats ? CalendarHeartbeat.beat(at: context.date) : 0
            let waves = beats ? CalendarHeartbeat.waves(at: context.date) : []

            ZStack {
                CalendarPlateGlow(tint: tint, diameter: diameter * 2.2, loud: loud, beat: beat)

                if loud, reduceMotion {
                    // Bez ruchu zostaje sam mocny pierścień — w miejscu,
                    // w którym fala spędza połowę swojego życia.
                    Circle()
                        .strokeBorder(tint.opacity(0.55), lineWidth: ringWidth * 1.5)
                        .frame(width: diameter, height: diameter)
                        .scaleEffect(1.24)
                } else {
                    ForEach(Array(waves.enumerated()), id: \.offset) { _, wave in
                        CalendarPlateWave(tint: tint, diameter: diameter, lineWidth: ringWidth * 1.6, progress: wave)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Obrót talerza

/// Gdzie jest talerz w obrocie i co z niego schodzi.
///
/// Stan obrotu mieszka w EKRANIE (`CalendarView`), a nie w talerzu, i to nie
/// jest szczegół implementacji — to jedyny sposób, żeby ruch zaczął się
/// w tej samej klatce, w której zmienia się danie. Gdyby talerz wykrywał
/// zmianę u siebie (`onChange`), pierwszą klatkę nowe danie stałoby już
/// płasko na środku, a obrót ruszałby dopiero z drugiej: mignięcie, po
/// którym „coś się jeszcze obraca”. Ekran ustawia `turn` razem
/// z `pickedCardId` (dokładnie tak, jak `DayPager` ustawia `dayTurn` razem
/// z datą), więc pierwsza klatka jest już początkiem ruchu.
///
/// `turn` chodzi między 0 i 1 NAPRZEMIENNIE, a `reversed` mówi, w którą
/// stronę leci bieżący obrót. Brzmi dziwniej, niż jest, i bierze się
/// z jednego twardego ograniczenia SwiftUI: „ustaw 0 bez animacji, potem
/// animuj do 1” nie działa, bo obie zmiany trafiają w jedną aktualizację
/// i skracają się do zera. Wartość, która po prostu jedzie na drugi koniec,
/// nie potrzebuje zerowania — a `reversed` (zwykłe pole, nieanimowane)
/// przelicza ją na postęp liczony zawsze od zera:
///
///     t = reversed ? 1 - turn : turn
///
/// W spoczynku `t` wynosi 1 (obrót skończony, danie stoi płasko), dlatego
/// stan początkowy to `turn = 0` PRZY `reversed = true`.
struct CalendarPlateSwap: Equatable {
    /// Postęp obrotu jako surowa liczba: 0 albo 1, naprzemiennie.
    var turn: CGFloat = 0
    /// Czy bieżący obrót jedzie z 1 do 0.
    var reversed: Bool = true
    /// W którą stronę obraca się talerz: `1` = danie z prawej strony
    /// sekwencji, `-1` = z lewej. Nieanimowane — zmienia się skokiem razem
    /// z daniem.
    var spin: CGFloat = 1
    /// Danie schodzące z talerza — rysowane tylko na czas obrotu. `nil`
    /// = talerz stoi albo nie ma czego zdejmować (pierwsze wejście w dzień).
    var leaving: CalendarPlateItem?
    /// Czy obrót właśnie trwa.
    var turning = false

    /// Talerz w spoczynku: obrót skończony, nic nie schodzi.
    static let settled = CalendarPlateSwap()

    /// Zaczyna obrót. Woła się to w TEJ SAMEJ zmianie stanu, co podmianę
    /// dania na talerzu. `false` = obrót już trwa i to stuknięcie zostało
    /// wchłonięte.
    ///
    /// Wchłonięcie nie jest ustępstwem, tylko warunkiem poprawności.
    /// `reversed` przelicza surową liczbę na postęp (`t = reversed ? 1 - turn
    /// : turn`), a przestawienie go, gdy poprzedni obrót jest w połowie,
    /// przerzuciłoby `t` z `x` na `1 − x`: talerz skoczyłby o tyle stopni,
    /// ile zdążył się obrócić, i to na odwrót. Wolno więc zaczynać obrót
    /// dopiero wtedy, gdy poprzedni osiadł — a wtedy `t` wynosi 1 i oba
    /// przeliczenia dają to samo, więc zamiana jest niewidoczna.
    ///
    /// Wchłonięte stuknięcie i tak dojdzie na talerz i to bez opóźnienia:
    /// danie WCHODZĄCE zawsze rysuje to, co ekran ma za bieżące, a w pierwszej
    /// połowie obrotu stoi ono schowane za krawędzią. Stuknięcie w tym czasie
    /// podmienia więc zdjęcie, którego nikt jeszcze nie widzi, i z krawędzi
    /// wychodzi już najnowsze danie. W drugiej połowie widać zamianę samego
    /// zdjęcia — bez obrotu, bo obrót jest w toku.
    mutating func begin(leaving: CalendarPlateItem?, spin: CGFloat) -> Bool {
        guard !turning else { return false }
        self.leaving = leaving
        self.spin = spin
        turning = true
        reversed = turn == 1
        turn = reversed ? 0 : 1
        return true
    }

    /// Kończy obrót: kopia schodząca przestaje istnieć i wolno zacząć
    /// następny. Nie rusza `turn`, więc nie jest animacją — to sprzątanie
    /// po niej.
    mutating func end() {
        leaving = nil
        turning = false
    }

    func effect(isLeaving: Bool, flat: Bool) -> PlateTurn {
        PlateTurn(turn: turn, reversed: reversed, spin: spin, leaving: isLeaving, flat: flat)
    }
}

/// Jedna połowa obrotu talerza — cała geometria z JEDNEJ interpolowanej
/// liczby.
///
/// Talerz obraca się wokół pionowej osi, jak odwracana moneta: danie
/// schodzące odwraca się od oka i znika za krawędzią (0° → 90°), a w tej
/// samej chwili danie wchodzące wychodzi z krawędzi po drugiej stronie
/// (−90° → 0°). Obie połowy jadą w TĘ SAMĄ stronę, więc oko widzi jeden
/// przedmiot, który się obrócił, a nie dwa, które się wymieniły.
///
/// **Dlaczego akurat obrót.** Przez trzy podejścia danie leciało z talerzyka
/// w sekwencji na środek, rosnąc po drodze — i nie dało się tego doprowadzić
/// do porządku. Ruch zależał od zmierzonych miejsc talerzyków (a te melduje
/// układ, więc bywały nieznane albo mierzone w trakcie innego ruchu), od
/// dwóch zegarów, które musiały się zgadzać, i od tego, żeby SwiftUI
/// interpolował modyfikator wstawiony PRZEZ PRZEJŚCIE
/// (`AnyTransition.modifier(active:identity:)`) — a tego nie robił: zdjęcie
/// pojawiało się małe przy talerzyku i przeskakiwało na środek w jednej
/// klatce. Obrót nie mierzy niczego, nie ma drugiego zegara i nic w nim nie
/// rośnie od małego: gdyby przestał się interpolować, danie po prostu
/// zmieniłoby się w miejscu.
///
/// **Mechanizm.** `Animatable` po jednej liczbie, nakładane przez
/// `.modifier(...)` — ta sama droga, którą jedzie obrót dnia na tacy
/// (`CalendarView.DayTurnEffect`) i wysepka (`SCIslandMorph`). To jedyny
/// sposób animowania, który w tej aplikacji sprawdził się na ekranie.
/// Nieciągłość (przejęcie w połowie) siedzi w CZYSTEJ funkcji tej liczby,
/// a nie w stanie, więc nie ma czego zerować w połowie ruchu i nie ma dwóch
/// zmian stanu, które musiałyby trafić w dwie różne aktualizacje.
///
/// **Przejęcie.** Pierwsza połowa czasu należy do dania schodzącego, druga
/// do wchodzącego — w danej chwili widać dokładnie jedno. Zamiana wypada
/// tam, gdzie oba są zwrócone krawędzią do oka, czyli mają zerową szerokość
/// na ekranie: cięcie kryciem jest wtedy niewidoczne i nie potrzebuje
/// zgrania w klatkę.
///
/// **Perspektywa** 0,45 — tyle, żeby obrót był obrotem, a nie zwężaniem
/// zdjęcia. Skali celowo NIE ma: nic nie rośnie i nic nie maleje, bo
/// „pojawia się małe i rośnie” to dokładnie ten objaw, dla którego lot
/// z tacy poszedł do kosza.
///
/// Z wyłączonym ruchem w dostępności (`flat`) zostaje samo przenikanie
/// kryciem, bez obrotu i bez cięcia: oba dania są wtedy widoczne przez cały
/// czas, jedno gaśnie, drugie wzbiera.
struct PlateTurn: ViewModifier, Animatable {
    var turn: CGFloat
    let reversed: Bool
    let spin: CGFloat
    /// Czy ten modyfikator prowadzi danie SCHODZĄCE z talerza.
    let leaving: Bool
    /// Ruch wyłączony w dostępności — zostaje przenikanie kryciem.
    let flat: Bool

    var animatableData: CGFloat {
        get { turn }
        set { turn = newValue }
    }

    func body(content: Content) -> some View {
        // Postęp liczony zawsze od zera, bez względu na to, w którą stronę
        // jedzie surowa liczba.
        let t = min(max(reversed ? 1 - turn : turn, 0), 1)
        // Ile ma za sobą TA połowa obrotu: pierwsza połowa czasu jest
        // schodzącej, druga wchodzącej.
        let half = leaving ? min(1, t / 0.5) : max(0, (t - 0.5) / 0.5)
        // Schodzące: 0° → 90°. Wchodzące: −90° → 0°. Ten sam kierunek.
        let angle = 90 * (leaving ? half : half - 1)
        let mine = leaving ? (t < 0.5) : (t >= 0.5)

        return content
            .rotation3DEffect(
                .degrees(flat ? 0 : Double(spin * angle)),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.45
            )
            .opacity(opacity(t: t, mine: mine))
    }

    private func opacity(t: CGFloat, mine: Bool) -> Double {
        guard !flat else { return Double(leaving ? 1 - t : t) }
        // Krycie jest tu tylko ubezpieczeniem cięcia: przy 90° zdjęcie ma
        // zerową szerokość i tak, więc nie widać, że gaśnie.
        return mine ? 1 : 0
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
/// Zdania ze słów mają po kilka wariantów (`CalendarVoice`) — ten sam fakt,
/// inny ton, stabilnie dla dnia i dania.
///
/// Podpis ma STAŁĄ wysokość — tę samą dla każdego dania, dla pustej pory
/// i dla pustego dnia: odliczanie to zawsze jedna linijka, nazwa dostaje
/// z góry `titleLines` linijek (także wtedy, gdy jest krótsza albo nie ma
/// jej wcale), pigułki to zawsze jeden rząd. To jest warunek konieczny,
/// żeby sekwencja pod spodem stała w miejscu przy przekładaniu talerzy
/// i żeby talerz na pustym dniu stał dokładnie tam, gdzie na pełnym.
struct CalendarPlateCaption: View {
    let item: CalendarPlateItem?
    /// Klucz dnia — ziarno doboru wariantów zdań. Ten sam dzień mówi zawsze
    /// tak samo, kolejny inaczej.
    let dayKey: String
    /// Ile linijek dostaje nazwa dania. Dwie na normalnym ekranie, jedna na
    /// krótkim, gdzie każde 23 pt idzie na talerz.
    var titleLines: Int = 2
    /// Czy w ogóle rysować rząd pigułek. Na najkrótszych ekranach (SE)
    /// czterdzieści punktów rzędu to różnica między talerzem a ikonką —
    /// wtedy szczegóły zostają w arkuszu posiłku, a tu zostaje nazwa.
    var showsChips: Bool = true
    /// Skąd wjeżdża nowe zdanie: `1` z prawej (danie na prawo), `-1` z lewej,
    /// `0` w miejscu. Ten sam kierunek, w którym danie przełożyło się na
    /// talerz — podpis idzie za daniem.
    var lean: Int = 0
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
                    // Nowe zdanie wjeżdża od strony, z której przyszło danie
                    // (i odrobinę z dołu), stare gaśnie w miejscu — zejście
                    // celowo bez kierunku, z tego samego powodu co na
                    // talerzu: kierunek zależy od celu, a cel przy zejściu
                    // jest już inny.
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(x: CGFloat(lean) * 16, y: 5)),
                            removal: .opacity
                        )
                    )
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
        // Sprężyna wzniesienia na przełożenie dania — ta sama, którą jedzie
        // talerz — druga na zmianę stanu w miejscu (odhaczenie przygasza
        // nazwę i wymienia pigułki) i osobny, krótszy odcisk na tyknięcie
        // zegara.
        .animation(DayNavigationMotion.lift, value: item?.id)
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

    /// Wariant zdania dla tego dnia i tego dania. `kind` rozdziela ziarna,
    /// żeby „Pora jeść” i „Zjedzone” tego samego dania nie były zawsze tym
    /// samym numerem wariantu.
    private func voice(_ variants: [String], _ kind: String) -> String {
        CalendarVoice.pick(variants, seed: "\(dayKey)|\(item?.id ?? "-")|\(kind)")
    }

    private var headline: String {
        guard let item else {
            return voice(["Pusty dzień", "Czysta karta", "Nic w planie", "Jeszcze bez planu"], "empty-day")
        }
        if item.isEmptySlot {
            return voice(["Nic nie zaplanowano", "Jeszcze pusto", "Wolna pora", "Bez planu"], "empty-slot")
        }

        switch item.status {
        case .eaten:
            return voice(["Zjedzone", "Odhaczone", "Zaliczone", "Po posiłku"], "eaten")
        case .next:
            // Odkąd okno gotowania jest otwarte, odliczanie przestaje być
            // odpowiedzią: „za 3 min” przy daniu, które robi się kwadrans,
            // mówi, ile zostało do JEDZENIA, a pytanie brzmi już co innego.
            if item.isCooking { return voice(["Pora gotować", "Do kuchni!", "Czas gotować", "Gotujemy!"], "cooking") }
            if item.isDue { return voice(Self.dueVariants, "due") }
            if item.isLate { return voice(Self.lateVariants, "late") }
            guard let away = item.minutesAway else { return item.time ?? anytime }
            return CalendarRelativeTime.text(inMinutes: away)
        case .later:
            guard let away = item.minutesAway else { return item.time ?? anytime }
            // Danie „później” może mieć porę za sobą (wieczorem, gdy nic nie
            // odhaczono, „następne” jest śniadanie, a obiad — „później”).
            // Wtedy mówi to samo, co mówiłoby jako następne, tym samym
            // wielkim zdaniem — nie odmieńcem „pora minęła” z małej litery.
            if away <= 0 {
                if away >= -CalendarRelativeTime.graceMinutes {
                    return voice(Self.dueVariants, "due")
                }
                return voice(Self.lateVariants, "late")
            }
            return CalendarRelativeTime.text(inMinutes: away)
        case .anytime:
            return anytime
        case .planned:
            return item.time ?? anytime
        }
    }

    private var anytime: String {
        voice(["Dowolna pora", "Kiedy chcesz", "Bez godziny"], "anytime")
    }

    /// Jedno miejsce dla zdań, które padają z dwóch gałęzi („następne”
    /// i „później” po porze) — żeby nie rozjechały się przy poprawce.
    /// „Minęła” bez stopnia: o 22:00 obiad z 14:00 nie jest „trochę” późno.
    private static let dueVariants = ["Pora jeść", "Smacznego!", "Na stół!", "Czas jeść"]
    private static let lateVariants = ["Pora minęła", "Już po porze", "Po czasie"]

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
        if item.isEaten { return Color.scLabel(scheme) }
        guard item.status == .next else { return Color.scLabel(scheme) }
        if item.isLate { return Color.scMuted(scheme) }
        // Terakota znaczy „to jest następne”. Kiedy robi się pilnie, wielki
        // wiersz przechodzi w kolor pory — ten sam, którym w tej samej chwili
        // bije poświata pod talerzem.
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
    /// „Zjedzone” niesie już wielki wiersz, nadpis i pieczątka — czwarty raz
    /// to samo słowo w pigułce nie było informacją.
    private var chips: [Chip] {
        // Pusty dzień i pusta pora mówią to samo: dokąd iść, żeby coś tu
        // stanęło. Ikona z dolnego menu, nie własna — użytkownik ma trafić
        // wzrokiem po tym samym znaku, który widzi w pasku pod spodem.
        guard let item, !item.isEmptySlot else {
            // Tożsamość pigułki idzie za doborem słów: inny wariant to inna
            // pigułka (wchodzi skalą i kryciem), a nie ta sama z literami
            // rolującymi się pod `numericText`.
            let text = voice(["Zaplanujesz w Planie", "Ułożysz w Planie", "Dodasz w Planie"], "plan-chip")
            return [Chip(id: "plan|\(text)", text: text, icon: MenuConstans.Plan.icon)]
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
            // Słowa w tożsamości, godzina poza nią: zmiana wariantu wymienia
            // pigułkę, zmiana godziny (inne danie) roluje cyfry.
            let lead = voice(["gotuj od", "start o", "do kuchni o"], "cook-chip")
            out.append(Chip(id: "cook|\(lead)", text: "\(lead) \(cookFrom)", icon: "flame", tint: tint))
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
                        CalendarPlate(item: item, canToggle: true, onToggle: {}, onOpenDetail: {})
                            .padding(.vertical, CalendarPlate.maxRimInset)
                        CalendarPlateCaption(item: item, dayKey: "2026-09-11", onOpenDetail: {})
                    }
                }

                VStack(spacing: 16) {
                    CalendarPlateKicker(item: nil)
                    CalendarPlate(item: nil, canToggle: false, onToggle: {}, onOpenDetail: nil)
                        .padding(.vertical, CalendarPlate.maxRimInset)
                    CalendarPlateCaption(item: nil, dayKey: "2026-09-11", onOpenDetail: nil)
                }
            }
            .padding(.vertical, 40)
            .padding(.horizontal, SCPageMetrics.horizontal)
        }
    }
    .preferredColorScheme(.dark)
}
