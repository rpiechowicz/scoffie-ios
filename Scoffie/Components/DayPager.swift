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

    /// Czas zjazdu starego dnia i wjazdu nowego. Fazy odmierza zegar, a nie
    /// domknięcie animacji: `withAnimation(_:completion:)` woła swoje
    /// domknięcie poza izolacją głównego aktora, a cały ten widok jest na nim.
    /// Wartości muszą odpowiadać animacjom w `step(by:)`.
    private static var exitDuration: Duration { .milliseconds(160) }
    private static var enterDuration: Duration { .milliseconds(320) }

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

        withAnimation(.easeIn(duration: 0.16)) {
            dragOffset = days > 0 ? -travel : travel
        }

        Task { @MainActor in
            try? await Task.sleep(for: Self.exitDuration)
            selectedDate = datesViewModel.stepDay(from: selectedDate, by: days)
            // Nowy dzień startuje z przeciwnej krawędzi, bez animacji —
            // dopiero powrót do zera jest animowany.
            dragOffset = days > 0 ? travel : -travel
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
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
