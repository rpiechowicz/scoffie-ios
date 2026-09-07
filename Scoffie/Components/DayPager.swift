import SwiftUI

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
struct DayPager<Content: View>: View {
    let datesViewModel: DatesViewModel
    @Binding var selectedDate: Date
    /// Dolny odstęp treści — ostatni kafel nie może kończyć się na krawędzi.
    var bottomPadding: CGFloat = SCPageMetrics.bottom
    @ViewBuilder var content: (Date) -> Content

    /// Wychylenie strony w trakcie przeciągania, a po zatwierdzeniu — faza
    /// wyjścia i wejścia dnia.
    @State private var dragOffset: CGFloat = 0
    /// Zmierzona szerokość strony (patrz `background` w `body`).
    @State private var pageWidth: CGFloat = 0
    /// Licznik zmian dnia — `sensoryFeedback` potrzebuje czegoś, co rośnie
    /// wyłącznie przy geście (sama data zmienia się też przy starcie ekranu).
    @State private var daySteps = 0
    /// Blokada na czas animacji przejścia: bez niej drugie machnięcie w jej
    /// trakcie przestawiało dzień, ale zostawiało stronę odjechaną w bok.
    @State private var isPaging = false

    // Wszystkie stałe niżej są LICZONE (`static var { … }`), a nie
    // przechowywane: `DayPager` jest typem generycznym, a tam `static let`
    // nie przechodzi kompilacji — „static stored properties not supported
    // in generic types”.

    /// Ile trzeba przeciągnąć (z rozpędem), żeby dzień przeskoczył. Ta sama
    /// wartość co przy tygodniach na pasku dni — jeden ekran, jeden próg.
    private static var commitThreshold: CGFloat { 56 }
    /// Sufit wychylenia przy przeciąganiu w bok. Strona nie jeździ 1:1
    /// z palcem, dopóki gest nie jest zatwierdzony — ruch się wypłaszcza,
    /// żeby było widać, że to jeszcze nie jest zmiana dnia.
    private static var dragLimit: CGFloat { 70 }

    var body: some View {
        ScrollView {
            content(selectedDate)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, bottomPadding)
                // Zmiana dnia jest animowana ZE WZGLĘDU NA PASEK DNI (patrz
                // `step(by:)`), a ta sama animacja obejmowałaby też przebudowę
                // kafli — wjeżdżałyby na ekran, dopasowując po drodze wysokości
                // i teksty. Strona podmienia się poza ekranem, więc nie ma tu
                // czego animować. Zakres jest wąski: dotyczy wyłącznie zmian
                // `selectedDate`, więc animacje wewnątrz kafli (serduszko,
                // odhaczenie posiłku) zostają nietknięte.
                .animation(nil, value: selectedDate)
        }
        .scrollIndicators(.hidden)
        // Gest łapie się na całej stronie, także w przerwach między kaflami.
        .contentShape(Rectangle())
        .offset(x: dragOffset)
        // Szerokość strony — z niej liczy się dystans zjazdu przy zmianie
        // dnia. Mierzona spod spodu, żeby pomiar nie wpływał na układ treści.
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { pageWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in pageWidth = width }
            }
        }
        // `simultaneousGesture`, nie `gesture`: strona jest pionowym
        // `ScrollView`, a zwykły `DragGesture` przejąłby też ruch w pionie
        // i zabił przewijanie kafli. Tak oba gesty biegną obok siebie,
        // a przewaga w poziomie rozstrzyga, który z nich cokolwiek robi.
        .simultaneousGesture(daySwipe)
        .sensoryFeedback(.selection, trigger: daySteps)
    }

    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard !isPaging else { return }
                // Pion należy do przewijania kafli.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = Self.resisted(value.translation.width)
            }
            .onEnded { value in
                guard !isPaging else { return }
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                let travel = value.predictedEndTranslation.width

                guard isHorizontal, abs(travel) >= Self.commitThreshold else {
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
    /// czasów na oko. `response` jest ten sam, co przy stuknięciu w dzień na
    /// pasku (`EditorialWeekBar`), żeby gest i stuknięcie przestawiały
    /// podkreślenie identycznie; tłumienie 0.86 zamiast 0.82, bo przeskok
    /// bąbla o kilkanaście punktów może się odbić, a cała strona nie —
    /// przestrzeliłaby poza krawędź i mignęła tłem.
    private static var enterAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.86)
    }

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
        // Szerokość bywa jeszcze nieznana w pierwszej klatce po wejściu na
        // zakładkę; wtedy lepszy jest twardy przeskok niż zjazd donikąd.
        let travel = pageWidth > 0 ? pageWidth : Self.dragLimit
        isPaging = true
        daySteps += 1

        withAnimation(Self.exitAnimation) {
            dragOffset = days > 0 ? -travel : travel
        }

        Task { @MainActor in
            try? await Task.sleep(for: Self.exitDuration)
            // Nowy dzień startuje z przeciwnej krawędzi, bez animacji —
            // dopiero powrót do zera jest animowany.
            dragOffset = days > 0 ? travel : -travel

            // Data i strona ruszają TYM SAMYM wywołaniem: podkreślenie na
            // pasku dni jedzie dokładnie tak długo, jak wjeżdża strona, więc
            // nie wyprzedza jej ani nie zostaje w tyle. Wcześniej ta linijka
            // stała poza `withAnimation` i dzień po prostu przeskakiwał.
            withAnimation(Self.enterAnimation) {
                selectedDate = datesViewModel.stepDay(from: selectedDate, by: days)
                dragOffset = 0
            }
            try? await Task.sleep(for: Self.enterDuration)
            isPaging = false
        }
    }

    /// Opór przy przeciąganiu: pierwsze punkty idą prawie 1:1, dalej ruch się
    /// wypłaszcza i nigdy nie przekracza `dragLimit`.
    private static func resisted(_ translation: CGFloat) -> CGFloat {
        let ratio = translation / dragLimit
        return dragLimit * ratio / (1 + abs(ratio))
    }
}
