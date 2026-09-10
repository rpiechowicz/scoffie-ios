import SwiftUI

/// Jeden pierścień aktywności w stylu Apple Activity.
/// Renderuje tor tła + postęp z gradientem i zaokrąglonym zakończeniem.
///
/// `progress` powyżej 1 „przepełnia się w nakładkę": pierścień domyka pełne
/// koło, a nadwyżka idzie DRUGĄ pętlą po tym samym torze.
///
/// **Nadwyżka jest TYM SAMYM kolorem przyciemnionym o jedną trzecią — dokładnie
/// jak w `MacroProgressTrack`.** Te dwa rysunki stoją w arkuszu „Cel dnia" obok
/// siebie, pierścienie po lewej i paski po prawej, i mówią o tych samych
/// czterech liczbach; przekroczony cel nie może w nich wyglądać na dwa różne
/// zdarzenia.
///
/// Wcześniej pierścień gasił pełne koło do jednej trzeciej mocy i puszczał
/// nadwyżkę w pełnym kolorze z poświatą — świecąca druga pętla przekrzykiwała
/// wtedy trzy pozostałe pierścienie i wyglądała bardziej na alarm niż na
/// „cel zrobiony z okładem". Pasek obok od początku mówił to spokojniej.
///
/// Zostaje sam cień rzucany przez drugą pętlę na pierwszą — nie po to, żeby
/// świecić, tylko żeby dało się zobaczyć, że jedna leży na drugiej. Pasek nie
/// ma tego problemu, bo jego warstwy leżą obok siebie, a nie na sobie.
struct ActivityRing: View {
    let progress: CGFloat            // 0...1 (może być > 1 – wtedy "przepełnia" się w nakładkę)
    let lineWidth: CGFloat
    let startColor: Color
    let endColor: Color
    var trackOpacity: Double = 0.14

    var body: some View {
        let clamped = max(0, min(progress, 1))
        // Sufit na drugiej pętli: przy 300 % nakładka i tak domknęłaby koło,
        // a rysowanie trzeciej warstwy niczego już nie dodaje.
        let overflow = max(0, min(progress - 1, 1))
        let isOver = overflow > 0

        ZStack {
            // Tor
            Circle()
                .stroke(
                    startColor.opacity(trackOpacity),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            // Postęp
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [startColor, endColor, startColor]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                // Pełne koło zostaje w pełnej mocy także po przekroczeniu
                // celu: „cel zrobiony" nie przestaje być prawdą dlatego, że
                // doszło do niego jeszcze trochę.
                .shadow(color: endColor.opacity(clamped > 0 && !isOver ? 0.35 : 0), radius: 6, x: 0, y: 0)

            // Nadmiar. Rysowany ZAWSZE, nie pod `if` — przy `if` przejście
            // przez 100 % wstawiałoby widok skokiem i łuk pojawiałby się
            // gotowy, zamiast wyjeżdżać z zera razem z resztą animacji.
            // Przycięcie do zera nie rysuje niczego, więc koszt jest żaden.
            Circle()
                .trim(from: 0, to: overflow)
                .stroke(
                    endColor.mix(black: 0.34),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: .black.opacity(isOver ? 0.35 : 0), radius: 3, x: 0, y: 1)
        }
    }
}
