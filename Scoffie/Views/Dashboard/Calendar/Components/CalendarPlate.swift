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
//  3. **Talerz woła kolorem pory, kiedy jest co robić.** Poświata za
//     zdjęciem oddycha, a spod rantu wybija podwójna echosonda — ten sam
//     ruch i ta sama barwa, którymi dawniej wołał węzeł łuku, tylko
//     głośniej, bo talerz jest sześć razy większy. Kiedy nic nie wisi
//     w powietrzu, talerz stoi nieruchomo.
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
//  6. **Nowe danie rozkwita od środka.** Makieta miała jeden „pop”
//     w miejscu; my próbowaliśmy wjazdu z boku i czytał się jak przeskok.
//     Teraz nowe danie rośnie kryciem od 0,86, stare gaśnie i maleje,
//     a kierunek (dzień do przodu, talerzyk na prawo) zostaje tylko jako
//     dziesięciopunktowy przechył — cień ruchu, nie ruch.

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
            .animation(DayNavigationMotion.spring, value: item?.id)
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
/// Dwa przyciski obok siebie, nie jeden w drugim: zdjęcie otwiera szczegóły
/// posiłku (jak każde zdjęcie dania w aplikacji), pieczątka w rogu odhacza
/// — jedyna czynność, którą ten ekran w ogóle zapisuje (Kalendarz nie
/// planuje). Dzień z przyszłości nie ma czego odhaczać, więc pieczątka jest
/// wtedy przygaszona; pusta pora nie ma czego otwierać, więc zdjęcie jest
/// wtedy tylko obrazkiem.
struct CalendarPlate: View {
    let item: CalendarPlateItem?
    /// Skąd wjeżdża nowe danie: `1` z prawej (dzień albo talerzyk do przodu),
    /// `-1` z lewej, `0` w miejscu (odhaczenie, pierwsze wejście).
    var direction: Int = 0
    var size: CGFloat = CalendarPlate.defaultSize
    /// Dzień z przyszłości i pusta pora nie mają czego odhaczać.
    let canToggle: Bool
    /// Pieczątka w rogu — odhacza.
    let onToggle: () -> Void
    /// Zdjęcie — otwiera szczegóły. `nil` dla pustej pory i pustego dnia.
    let onOpenDetail: (() -> Void)?

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

    private var accent: Color {
        item?.accent(in: scheme) ?? Color.scLabel(scheme).opacity(0.14)
    }

    private var isUrgent: Bool { item?.isUrgent == true }

    var body: some View {
        // `ZStack` nie jest ozdobą: przejście przy podmianie dania gra tylko
        // wtedy, gdy widok o zmiennej tożsamości siedzi w JAKIMŚ kontenerze.
        ZStack {
            stage
                // Podmiana dania na środku. To samo danie odhaczone zostaje
                // na miejscu — zmienia mu się pierścień i pieczątka, a nie
                // tożsamość (ekran przypina wtedy odhaczone danie, żeby
                // „następny” nie wypchnął go z talerza spod palca).
                .id(item?.id ?? "empty")
                .transition(swap)
        }
        .frame(width: size, height: size)
        // Odcisk na identyfikatorze dania, nie na zdjęciu: to on rozstrzyga,
        // czy talerz ma się przełożyć, czy tylko zmienić stan w miejscu.
        // Ta sama sprężyna, którą jedzie strona dnia i podkreślenie na pasku
        // dni — jeden ruch na jedną czynność, także wtedy, gdy ta czynność
        // to zmiana dnia. Drugi odcisk na stan: odhaczenie przygasza zdjęcie
        // w miejscu i bez niego ten jeden ruch przeskakiwałby w klatce.
        .animation(DayNavigationMotion.spring, value: item?.id)
        .animation(DayNavigationMotion.spring, value: item?.status)
    }

    /// Zdjęcie i pieczątka — dwa osobne przyciski w jednym pudełku.
    ///
    /// Nie przycisk w przycisku: zagnieżdżone przyciski w SwiftUI dzielą
    /// jeden obszar dotyku i o tym, który zadziała, decyduje kolejność
    /// w drzewie, nie miejsce stuknięcia. Obok siebie każdy ma swój obszar.
    private var stage: some View {
        // Na pustej porze zdjęcie jest obrazkiem — nie ma być czytane jako
        // „przyciemniony przycisk”. Jawny typ, bo `[]` i `.isButton` w jednym
        // wyrażeniu warunkowym nie mają skąd wziąć typu bez podpowiedzi.
        let hiddenTraits: AccessibilityTraits = onOpenDetail == nil ? .isButton : []

        return ZStack(alignment: .bottomTrailing) {
            Button {
                pagerGate.ifNotSwiping { onOpenDetail?() }
            } label: {
                plate
            }
            .buttonStyle(PlatePressStyle())
            .disabled(onOpenDetail == nil)
            .accessibilityLabel(accessibilityLabel)
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

    /// Nowe danie rozkwita od środka; stare gaśnie i maleje w miejscu.
    ///
    /// Rozkwit, nie wjazd z boku. Wjazd z boku o ćwierć średnicy czytał się
    /// jako przeskok: zdjęcie pojawiało się przesunięte i dopiero dojeżdżało
    /// na miejsce. Teraz nowe danie rośnie od 0,86 do pełnego rozmiaru
    /// kryciem — a kierunek zostaje tylko jako cień: dziesięć punktów
    /// przechyłu w stronę, z której przyszło. Tyle wystarczy, żeby ruch
    /// w tył czuć inaczej niż w przód, i za mało, żeby cokolwiek skakało.
    ///
    /// Zejście CELOWO nie ma kierunku. Przejście zejścia bierze się z tego,
    /// co stało w widoku w chwili jego WSTAWIENIA — czyli z kierunku
    /// poprzedniej zmiany, nie tej. Gdyby stare danie odjeżdżało „w drugą
    /// stronę”, to przy zmianie kierunku (dzień w przód, potem w tył)
    /// odjeżdżałoby w tę samą stronę, z której wjeżdża nowe, i oba
    /// przecinałyby się na środku.
    private var swap: AnyTransition {
        let removal = AnyTransition.opacity.combined(with: .scale(scale: 0.94))
        let bloom = AnyTransition.scale(scale: 0.86).combined(with: .opacity)

        if direction == 0 || reduceMotion {
            return .asymmetric(insertion: bloom, removal: removal)
        }

        let lean = AnyTransition.offset(x: CGFloat(direction) * 10)
        return .asymmetric(insertion: bloom.combined(with: lean), removal: removal)
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
            // Echosonda — sygnał „pora na to danie”. Dwa pierścienie
            // przesunięte o pół cyklu, żeby fala szła bez przerwy: jeden
            // pierścień co dwie sekundy ginął w tle i wyglądał jak drgnięcie,
            // nie jak wołanie. Stoi pod zdjęciem, więc WYCHODZI zza niego,
            // zamiast pojawiać się w locie.
            .background {
                if isUrgent {
                    if reduceMotion {
                        // Bez ruchu zostaje sam mocny pierścień — w miejscu,
                        // w którym echosonda spędza połowę cyklu.
                        Circle()
                            .strokeBorder(accent.opacity(0.55), lineWidth: ringWidth * 1.5)
                            .frame(width: size, height: size)
                            .scaleEffect(1.24)
                    } else {
                        CalendarPlatePing(tint: accent, diameter: size, lineWidth: ringWidth * 1.6, delay: 0)
                        CalendarPlatePing(tint: accent, diameter: size, lineWidth: ringWidth * 1.6, delay: 1.0)
                    }
                }
            }
            // Głębiej — poświata w kolorze pory. Nie rozjaśnia dania, tylko
            // planszę wokół niego, i to ona oddycha, kiedy jest co robić.
            .background {
                CalendarPlateGlow(
                    tint: accent,
                    diameter: size * 2.2,
                    breathes: isUrgent && !reduceMotion,
                    loud: isUrgent
                )
            }
    }

    private var accessibilityLabel: String {
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
/// Oddycha wyłącznie wtedy, gdy jest co zrobić (`breathes`) — i oddycha
/// SKALĄ ORAZ KRYCIEM, a nie promieniem gradientu: gradient przeliczany co
/// klatkę kosztuje tyle, ile cały ten ekran razem wzięty. Kiedy woła
/// (`loud`), jest mocniejsza i szersza: cicha poświata pod talerzem
/// o średnicy 168 pt ginęła na ciemnym tle i puls było widać dopiero, gdy
/// się go szukało.
private struct CalendarPlateGlow: View {
    let tint: Color
    let diameter: CGFloat
    let breathes: Bool
    let loud: Bool

    @State private var inhaled = false

    var body: some View {
        // Jawny typ i osobna zmienna, a nie wyrażenie warunkowe wprost
        // w wywołaniu: w tym projekcie ternar z dwoma skróconymi nazwami
        // składowych potrafi zgłosić się kilkadziesiąt linii wyżej jako
        // `ambiguous use of 'init'` (patrz `CLAUDE.md`).
        let motion: Animation = breathes
            ? .easeInOut(duration: 1.9).repeatForever(autoreverses: true)
            : .smooth(duration: 0.4)

        return Circle()
            .fill(
                RadialGradient(
                    colors: [tint.opacity(loud ? 0.42 : 0.22), tint.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter * (loud ? 0.4 : 0.34)
                )
            )
            .frame(width: diameter, height: diameter)
            // Odrobinę w górę: talerz ma stać w świetle, a nie na nim.
            .offset(y: -diameter * 0.05)
            .scaleEffect(inhaled ? 1.14 : 1)
            .opacity(inhaled ? 1 : (loud ? 0.55 : 0.72))
            .animation(motion, value: inhaled)
            .animation(.smooth(duration: 0.45), value: tint)
            .animation(.smooth(duration: 0.45), value: loud)
            .onAppear { inhaled = breathes }
            .onChange(of: breathes) { _, value in inhaled = value }
            .allowsHitTesting(false)
    }
}

// MARK: - Echosonda

/// Pierścień wybijający spod talerza i gasnący.
///
/// `autoreverses: false`, więc pierścień nie wraca do środka, tylko zaczyna
/// od nowa: powrót widać jako ruch wsteczny, a echosonda ma bić zawsze w tę
/// samą stronę. Skok na początek cyklu wypada przy zerowym kryciu, czyli
/// poza wzrokiem. Ramka jest STAŁA, oddycha `scaleEffect` — rosnąca ramka
/// kazałaby układowi przeliczać się co klatkę bez końca. `delay` przesuwa
/// start o ułamek cyklu, żeby dwa pierścienie szły jeden za drugim.
private struct CalendarPlatePing: View {
    let tint: Color
    let diameter: CGFloat
    let lineWidth: CGFloat
    let delay: Double

    @State private var expanded = false

    var body: some View {
        Circle()
            .strokeBorder(tint, lineWidth: lineWidth)
            .frame(width: diameter, height: diameter)
            .scaleEffect(expanded ? 1.48 : 1)
            .opacity(expanded ? 0 : 0.85)
            .animation(
                .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                value: expanded
            )
            .onAppear {
                guard delay > 0 else {
                    expanded = true
                    return
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                    expanded = true
                }
            }
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
                    // Lekkie uniesienie razem z kryciem — podpis „wypływa”
                    // spod talerza, który właśnie rozkwitł, a nie pojawia się
                    // znikąd.
                    .transition(.opacity.combined(with: .offset(y: 5)))
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
