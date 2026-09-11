import SwiftUI

/// Ruch nawigacji po dniach — JEDNA sprężyna na wszystko, co przestawia
/// dzień albo tydzień: wjazd strony w `DayPager`, przeskok podkreślenia po
/// stuknięciu w pasek dni, podmiana liczb przy zmianie tygodnia.
///
/// Osobny typ, bo `DayPager` jest generyczny i nie może mieć `static let`,
/// a `EditorialWeekBar` miał dotąd własną kopię z innym tłumieniem (0,82) —
/// to samo podkreślenie odbijało się inaczej zależnie od tego, czy zmiana
/// przyszła z gestu, czy ze stuknięcia. Tłumienie 0,86: przeskok bąbla
/// o kilkanaście punktów może się lekko odbić, ale cała strona nie —
/// przestrzeliłaby poza krawędź i mignęła tłem.
enum DayNavigationMotion {
    static let spring: Animation = .spring(response: 0.34, dampingFraction: 0.86)
}

/// Jak `DayPager` pokazuje zmianę dnia.
///
/// Dwa ekrany, dwa różne pytania. Plan tygodnia to LISTA — dzień jest
/// stroną, a strona wychodzi w bok i wjeżdża nowa (`slide`). Kalendarz to
/// SCENA — talerz stoi na środku zawsze w tym samym miejscu, a zmienia się
/// to, co na nim leży (`morph`). Przesuwanie sceny w bok, żeby postawić na
/// jej miejscu identyczną scenę z innym daniem, mówiło oczom „to jest inny
/// ekran", a to jest ten sam ekran z innym dniem.
enum DayPagerMotion {
    /// Stara strona zjeżdża za krawędź z zanikiem, nowa wjeżdża z przeciwnej.
    /// W danej chwili istnieje jedna strona, więc wysokość nie skacze.
    case slide
    /// Strona zostaje na miejscu (po geście wraca sprężyną spod palca),
    /// a treść przechodzi w nowy dzień własnymi przejściami: zdjęcie na
    /// talerzu robi „pop", liczby rolują, sekwencja i dopiski wchodzą
    /// i schodzą kryciem. Wymaga treści, która rysuje dzień z argumentu
    /// i NIE ma świeżej tożsamości na dzień — inaczej nie ma co morfować.
    case morph
}

/// Furtka między machnięciem palcem a stuknięciem w treść dnia.
///
/// `Button` w SwiftUI odpala akcję przy PUSZCZENIU palca w obrębie swojego
/// kształtu — bez względu na to, ile palec przejechał po drodze. `ScrollView`
/// potrafi mu to odebrać (dlatego przewijanie w pionie nie otwiera przypadkiem
/// posiłku), ale gest `DayPagera` jest tylko `simultaneousGesture` i przycisków
/// nie dotyka. Wiersz posiłku zajmuje całą szerokość strony, więc machnięcie
/// w bok kończy się w tym samym wierszu, w którym się zaczęło: dzień się
/// przestawiał i JEDNOCZEŚNIE otwierał się szczegół posiłku.
///
/// Stąd ta furtka: `DayPager` odnotowuje każdy poziomy ruch palca, a akcje
/// wierszy przepuszczają się przez `ifNotSwiping`.
@MainActor
final class DayPagerGate {
    /// Chwila ostatniego poziomego ruchu palca po stronie dnia.
    private var lastSwipeMove: Date = .distantPast

    /// Okno, w którym stuknięcie jest już tylko ogonem machnięcia.
    private static let window: TimeInterval = 0.3

    /// Woła `DayPager` przy każdym poziomym ruchu palca.
    func noteSwipeMovement() {
        lastSwipeMove = Date()
    }

    /// Wykonuje akcję, chyba że ten sam dotyk przestawiał właśnie dzień.
    ///
    /// Znacznik czasu, a nie flaga kasowana w `onEnded`: kolejność zdarzeń przy
    /// puszczeniu palca (akcja `Button`-a kontra `onEnded` gestu) nie jest
    /// w SwiftUI ustalona, a flaga skasowana o klatkę za wcześnie wpuszcza
    /// dokładnie to stuknięcie, które miała zatrzymać. Znacznik nie ma czego
    /// gubić i sam się „kasuje”, więc urwany gest nie zostawia po sobie
    /// martwych przycisków.
    func ifNotSwiping(_ action: () -> Void) {
        guard Date().timeIntervalSince(lastSwipeMove) > Self.window else { return }
        action()
    }
}

private struct DayPagerGateKey: EnvironmentKey {
    @MainActor static let defaultValue = DayPagerGate()
}

extension EnvironmentValues {
    /// Furtka bieżącej strony dnia. Poza `DayPagerem` przepuszcza wszystko.
    var dayPagerGate: DayPagerGate {
        get { self[DayPagerGateKey.self] }
        set { self[DayPagerGateKey.self] = newValue }
    }
}

/// Jeden dzień na ekranie, przewijany palcem w bok.
///
/// Plan i Kalendarz pokazują ten sam tydzień, ale każdy swój dzień — i na obu
/// ruch w bok ma znaczyć TO SAMO: dzień do przodu albo do tyłu. Wcześniej Plan
/// robił to własną karuzelą zamkniętą w siedmiu dniach tygodnia, a Kalendarz
/// nie robił tego wcale i dzień zmieniało się wyłącznie stuknięciem w pasek.
/// Stąd jeden komponent zamiast dwóch zachowań: gest, próg, opór i animacja
/// są tu policzone raz.
///
/// Przekroczenie niedzieli (albo poniedziałku w tył) przesuwa razem z dniem
/// cały pasek na sąsiedni tydzień — `DatesViewModel.stepDay(from:by:)`.
///
/// Pionowe przewijanie treści dnia należy do tego widoku: nagłówki obu
/// ekranów są przypięte do góry, więc scrolluje się dokładnie tyle, ile
/// obejmuje `content`, i nic ponadto.
///
/// **Stuknięcie w dzień jedzie tak samo jak gest.** Z `animatesSelectionChanges`
/// każda zmiana `selectedDate` z zewnątrz — stuknięcie w pasek dni, strzałka
/// tygodnia, „DZIŚ" — dostaje ten sam dwufazowy zjazd i wjazd, co
/// przesunięcie palcem; kierunek bierze się z porównania dat. Bez tego
/// strona podmieniała się twardym cięciem, a podkreślenie na pasku
/// sprężynowało — dwa języki dla jednej czynności. To wymaga, żeby `content`
/// rysował dzień Z ARGUMENTU, a nie ze stanu ekranu: na czas zjazdu pager
/// pokazuje jeszcze stary dzień (`displayedDate`), choć `selectedDate` już
/// wskazuje nowy. Kalendarz rysuje z własnego stanu, więc zostaje przy
/// domyślnym `false` i twardym przeskoku.
struct DayPager<Content: View>: View {
    let datesViewModel: DatesViewModel
    @Binding var selectedDate: Date
    /// Dolny odstęp treści — ostatni kafel nie może kończyć się na krawędzi.
    let bottomPadding: CGFloat
    /// Czy zmiany `selectedDate` spoza gestu też mają zjazd i wjazd strony.
    let animatesSelectionChanges: Bool
    /// Czy treść dnia przewija się w pionie.
    ///
    /// Plan tygodnia bez tego nie istnieje: ma listę kafli dłuższą od ekranu
    /// i to przewijanie jest jego treścią. Kalendarz jest dokładnie odwrotny —
    /// cały dzień MA się mieścić w jednym widoku, a talerz sam zjeżdża
    /// wielkością do miejsca, które zostało.
    ///
    /// Różnica jest głębsza niż pasek przewijania: w środku `ScrollView`
    /// wysokość jest nieskończona, więc nie istnieje coś takiego jak
    /// „wysokość, która została", i strona nie ma się do czego dopasować.
    /// Dopiero strona bez przewijania dostaje prawdziwą wysokość zakładki
    /// i może ją rozdzielić między swoje piętra.
    let scrolls: Bool
    /// Zjazd strony albo przejście treści w miejscu — patrz `DayPagerMotion`.
    let motion: DayPagerMotion
    let content: (Date) -> Content

    init(
        datesViewModel: DatesViewModel,
        selectedDate: Binding<Date>,
        bottomPadding: CGFloat = SCPageMetrics.bottom,
        animatesSelectionChanges: Bool = false,
        scrolls: Bool = true,
        motion: DayPagerMotion = .slide,
        @ViewBuilder content: @escaping (Date) -> Content
    ) {
        self.datesViewModel = datesViewModel
        self._selectedDate = selectedDate
        self.bottomPadding = bottomPadding
        self.animatesSelectionChanges = animatesSelectionChanges
        self.scrolls = scrolls
        self.motion = motion
        self.content = content
        self._displayedDate = State(initialValue: selectedDate.wrappedValue)
    }

    /// Dzień, który strona faktycznie rysuje. Przy zmianie z zewnątrz zostaje
    /// w tyle za `selectedDate` na czas zjazdu starej strony.
    @State private var displayedDate: Date
    /// Wychylenie strony w trakcie przeciągania, a po zatwierdzeniu — faza
    /// wyjścia i wejścia dnia.
    @State private var dragOffset: CGFloat = 0
    /// Krycie strony: zjazd i wjazd dnia idą z zanikiem, przeciąganie nie.
    @State private var pageOpacity: Double = 1
    /// Zmierzona szerokość strony (patrz `background` w `body`).
    @State private var pageWidth: CGFloat = 0
    /// Licznik zmian dnia — `sensoryFeedback` potrzebuje czegoś, co rośnie
    /// wyłącznie przy geście (sama data zmienia się też przy starcie ekranu).
    @State private var daySteps = 0
    /// Blokada na czas animacji przejścia: bez niej drugie machnięcie w jej
    /// trakcie przestawiało dzień, ale zostawiało stronę odjechaną w bok.
    @State private var isPaging = false
    /// Oś bieżącego gestu, rozstrzygnięta RAZ. Wcześniej warunek przewagi
    /// liczył się przy każdej klatce, więc gest prowadzony po skosie raz
    /// ruszał stroną, a raz nie — strona co chwilę przystawała pod palcem.
    @State private var isHorizontalDrag: Bool?
    /// Wychylenie palca w chwili rozstrzygnięcia osi. Odejmuje się je od
    /// translacji, żeby strona ruszała od zera, a nie skakała o próg gestu.
    @State private var dragBaseline: CGFloat = 0
    /// Furtka dla stuknięć w treść dnia — patrz `DayPagerGate`.
    @State private var gate = DayPagerGate()

    // Wszystkie stałe niżej są LICZONE (`static var { … }`), a nie
    // przechowywane: `DayPager` jest typem generycznym, a tam `static let`
    // nie przechodzi kompilacji — „static stored properties not supported
    // in generic types”.

    /// Ile trzeba przeciągnąć (z rozpędem), żeby dzień przeskoczył. Ta sama
    /// wartość co przy tygodniach na pasku dni — jeden ekran, jeden próg.
    private static var commitThreshold: CGFloat { 56 }
    /// Do progu strona jedzie 1:1 z palcem — tyle ruchu, ile gestu.
    private static var freeTravel: CGFloat { commitThreshold }
    /// Sufit wychylenia przy przeciąganiu w bok. Za progiem ruch się
    /// wypłaszcza: widać, że strona jest już na granicy zatwierdzenia.
    private static var dragLimit: CGFloat { 104 }
    /// Ile palec musi przejechać, żeby oś gestu dała się rozstrzygnąć.
    private static var axisLockDistance: CGFloat { 14 }

    var body: some View {
        page
        // Gest łapie się na całej stronie, także w przerwach między kaflami.
        .contentShape(Rectangle())
        .offset(x: dragOffset)
        .opacity(pageOpacity)
        // Szerokość strony — z niej liczy się dystans zjazdu przy zmianie
        // dnia. Mierzona spod spodu, żeby pomiar nie wpływał na układ treści.
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { pageWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in pageWidth = width }
            }
        }
        // `simultaneousGesture`, nie `gesture`: w trybie przewijanym strona
        // jest pionowym `ScrollView`, a zwykły `DragGesture` przejąłby też
        // ruch w pionie i zabił przewijanie kafli. Tak oba gesty biegną obok
        // siebie, a przewaga w poziomie rozstrzyga, który z nich cokolwiek
        // robi. W trybie bez przewijania nie ma z czym konkurować, ale reguła
        // zostaje jedna dla obu — jeden gest, jedno zachowanie.
        .simultaneousGesture(daySwipe)
        .sensoryFeedback(.selection, trigger: daySteps)
        .onChange(of: selectedDate) { _, target in
            guard animatesSelectionChanges, !isPaging else { return }
            guard !Calendar.current.isDate(target, inSameDayAs: displayedDate) else { return }
            // Przed pierwszym pomiarem (wejście na zakładkę) nie ma dokąd
            // zjeżdżać — twardy przeskok, tak jak przed tą zmianą.
            guard pageWidth > 0 else {
                displayedDate = target
                return
            }
            transition(to: target, forward: target > displayedDate, movesSelection: false)
        }
    }

    /// Strona dnia — przewijana albo nie, zależnie od `scrolls`.
    ///
    /// Obie gałęzie niosą ten sam zestaw modyfikatorów treści, różnią się
    /// wyłącznie tym, co ją opakowuje. W gałęzi bez przewijania odstęp
    /// z dołu wchodzi POD ramkę na pełną wysokość, nie nad nią: inaczej
    /// treść dostałaby do podziału swoją naturalną wysokość zamiast tej,
    /// która realnie została na ekranie.
    @ViewBuilder
    private var page: some View {
        // W trybie `slide` zmiana dnia jest animowana ZE WZGLĘDU NA PASEK
        // DNI (patrz `transition(to:)`), a ta sama animacja obejmowałaby
        // też przebudowę kafli — wjeżdżałyby na ekran, dopasowując po drodze
        // wysokości i teksty. Strona podmienia się poza ekranem, więc nie ma
        // tam czego animować i animacja jest wyłączona. Zakres jest wąski:
        // wyłącznie zmiany dnia, więc serduszko i odhaczenie zostają.
        //
        // W trybie `morph` jest dokładnie odwrotnie: ta animacja JEST
        // przejściem dnia — to w niej zdjęcie na talerzu robi „pop", liczby
        // rolują, a sekwencja wchodzi kryciem. Zdjęcie jej tutaj zamieniłoby
        // morfowanie w twarde cięcie na środku ekranu.
        let dayChange: Animation? = motion == .slide ? nil : DayNavigationMotion.spring
        let day = content(animatesSelectionChanges ? displayedDate : selectedDate)
            .animation(dayChange, value: selectedDate)
            .animation(dayChange, value: displayedDate)
            .environment(\.dayPagerGate, gate)

        if scrolls {
            ScrollView {
                day
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, bottomPadding)
            }
            .scrollIndicators(.hidden)
        } else {
            day
                .padding(.bottom, bottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isPaging else { return }

                if isHorizontalDrag == nil {
                    let horizontal = abs(value.translation.width)
                    let vertical = abs(value.translation.height)
                    // Dopóki gest nie odjechał na tyle, żeby było wiadomo,
                    // dokąd zmierza, nie robi nic — ani strona, ani furtka.
                    guard max(horizontal, vertical) >= Self.axisLockDistance else { return }
                    isHorizontalDrag = horizontal > vertical
                    dragBaseline = value.translation.width
                }

                // Pion należy do przewijania kafli.
                guard isHorizontalDrag == true else { return }

                // Od tej chwili stuknięcia z tego dotyku są ogonem machnięcia,
                // a nie wyborem posiłku.
                gate.noteSwipeMovement()
                dragOffset = Self.resisted(value.translation.width - dragBaseline)
            }
            .onEnded { value in
                let wasHorizontal = isHorizontalDrag == true
                let baseline = dragBaseline
                isHorizontalDrag = nil
                dragBaseline = 0

                guard !isPaging, wasHorizontal else { return }
                let travel = value.predictedEndTranslation.width - baseline

                guard abs(travel) >= Self.commitThreshold else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        dragOffset = 0
                    }
                    return
                }

                step(by: travel < 0 ? 1 : -1)
            }
    }

    /// Wjazd nowego dnia — i to samo, czym jedzie podkreślenie na pasku dni.
    ///
    /// JEDNA animacja na dwie rzeczy, nie dwie podobne: strona i pasek ruszają
    /// w tej samej chwili tą samą sprężyną, więc lądują razem bez dobierania
    /// czasów na oko. Stała jest wspólna z `EditorialWeekBar`
    /// (`DayNavigationMotion.spring`), więc gest i stuknięcie przestawiają
    /// podkreślenie identycznie.
    private static var enterAnimation: Animation { DayNavigationMotion.spring }

    /// Zjazd starego dnia: przyspiesza, bo strona ucieka za krawędź.
    ///
    /// Krzywa i odmierzany czas liczą się z JEDNEJ liczby. Fazy odmierza
    /// zegar, a nie domknięcie animacji (`withAnimation(_:completion:)` woła
    /// swoje domknięcie poza izolacją głównego aktora, a cały ten widok jest
    /// na nim), więc rozjechanie się tych dwóch wartości podmieniałoby dzień
    /// w połowie zjazdu — na oczach użytkownika.
    private static var exitSeconds: TimeInterval { 0.16 }
    private static var exitAnimation: Animation { .easeIn(duration: exitSeconds) }
    private static var exitDuration: Duration { .milliseconds(Int(exitSeconds * 1000)) }

    /// Ile strona odjeżdża, zanim zniknie — ułamek szerokości, nie cała.
    ///
    /// Przy pełnej szerokości strona pokonywała ~390 pt w 160 ms i to widać:
    /// treść przelatywała przez ekran jak smuga. Krótszy dystans z zanikiem
    /// czyta się jako to samo („dzień wyszedł w bok”), a nie ma czasu rozmyć
    /// się w ruchu.
    private static var exitTravelRatio: CGFloat { 0.42 }

    /// Ile trzymać blokadę po starcie wjazdu — tyle, ile sprężyna osiada.
    private static var enterDuration: Duration { .milliseconds(340) }

    /// Zmiana dnia w dwóch fazach: stary dzień zjeżdża w bok, nowy wjeżdża
    /// z przeciwnej strony.
    ///
    /// Dwie fazy, a nie `.transition` na zmianie `id`: przy przejściu obie
    /// strony żyłyby przez chwilę w tym samym miejscu pionowego `ScrollView`
    /// i wysokość skakałaby do wyższej z nich. Tutaj w danym momencie istnieje
    /// zawsze jedna strona, więc nic nie podskakuje, a kierunek zjazdu bierze
    /// się wprost z gestu — nie trzeba go zgadywać z porównania dat.
    private func step(by days: Int) {
        daySteps += 1
        transition(
            to: datesViewModel.stepDay(from: selectedDate, by: days),
            forward: days > 0,
            movesSelection: true
        )
    }

    /// Zjazd i wjazd — wspólne dla gestu i dla zmiany z zewnątrz.
    ///
    /// `movesSelection` mówi, czy to pager przestawia `selectedDate` (gest),
    /// czy tylko dogania datę, którą ktoś już przestawił (stuknięcie w pasek,
    /// strzałka tygodnia). W drugim przypadku podkreślenie na pasku już
    /// jedzie — ruszyło w chwili stuknięcia, czyli tam, gdzie palec; strona
    /// dojeżdża za nim.
    private func transition(to target: Date, forward: Bool, movesSelection: Bool) {
        isPaging = true

        if motion == .morph {
            morph(to: target, movesSelection: movesSelection)
            return
        }

        // Szerokość bywa jeszcze nieznana w pierwszej klatce po wejściu na
        // zakładkę; wtedy lepszy jest twardy przeskok niż zjazd donikąd.
        let travel = pageWidth > 0 ? pageWidth * Self.exitTravelRatio : Self.dragLimit

        withAnimation(Self.exitAnimation) {
            dragOffset = forward ? -travel : travel
            pageOpacity = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: Self.exitDuration)
            // Nowy dzień startuje z przeciwnej krawędzi, bez animacji —
            // dopiero powrót do zera jest animowany.
            dragOffset = forward ? travel : -travel

            // Data i strona ruszają TYM SAMYM wywołaniem: podkreślenie na
            // pasku dni jedzie dokładnie tak długo, jak wjeżdża strona, więc
            // nie wyprzedza jej ani nie zostaje w tyle. Wcześniej ta linijka
            // stała poza `withAnimation` i dzień po prostu przeskakiwał.
            withAnimation(Self.enterAnimation) {
                if movesSelection { selectedDate = target }
                displayedDate = target
                dragOffset = 0
                pageOpacity = 1
            }
            try? await Task.sleep(for: Self.enterDuration)
            isPaging = false

            // Zmiana, która przyszła w trakcie animacji (szybkie dwa
            // stuknięcia), została zignorowana przez `onChange` — strona
            // dogania datę bez drugiego zjazdu, żeby nie ustawiać kolejki.
            if !Calendar.current.isDate(displayedDate, inSameDayAs: selectedDate) {
                displayedDate = selectedDate
            }
        }
    }

    /// Przejście dnia w miejscu — jedna faza, jedna sprężyna.
    ///
    /// Strona NIE wyjeżdża za krawędź. Po geście wraca sprężyną spod palca
    /// (wychylenie z przeciągania jest już kierunkowym sygnałem: tyle, ile
    /// palec przesunął, tyle strona oddaje), a po stuknięciu w pasek dni
    /// stoi nieruchomo — kierunek niesie wtedy podkreślenie na pasku. W tej
    /// SAMEJ animowanej transakcji zmienia się dzień, więc wszystko, co
    /// treść umie animować, animuje się razem z powrotem strony: zdjęcie na
    /// talerzu robi „pop", odliczanie roluje cyfry, sekwencja i dopiski
    /// wchodzą kryciem. Zjazd starej strony i wjazd nowej byłyby tu dwiema
    /// animacjami tej samej rzeczy.
    ///
    /// Blokada `isPaging` trwa tyle, ile osiada sprężyna — z tego samego
    /// powodu, co przy zjeździe: drugie machnięcie w trakcie zostawiałoby
    /// stronę w pół drogi.
    private func morph(to target: Date, movesSelection: Bool) {
        withAnimation(Self.enterAnimation) {
            if movesSelection { selectedDate = target }
            displayedDate = target
            dragOffset = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: Self.enterDuration)
            isPaging = false

            if !Calendar.current.isDate(displayedDate, inSameDayAs: selectedDate) {
                displayedDate = selectedDate
            }
        }
    }

    /// Opór przy przeciąganiu: do progu zatwierdzenia strona idzie 1:1
    /// z palcem, dalej ruch się wypłaszcza i nigdy nie przekracza `dragLimit`.
    ///
    /// Wcześniej opór działał od pierwszego punktu i przy 70 pt gestu strona
    /// przesuwała się o 35 — machnięcie wyglądało, jakby ekran je zignorował.
    private static func resisted(_ translation: CGFloat) -> CGFloat {
        let distance = abs(translation)
        guard distance > freeTravel else { return translation }

        let sign: CGFloat = translation < 0 ? -1 : 1
        let slack = dragLimit - freeTravel
        let ratio = (distance - freeTravel) / slack
        return sign * (freeTravel + slack * ratio / (1 + ratio))
    }
}
