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
        let isOver = progress > 1

        ZStack {
            // Tor
            Circle()
                .stroke(
                    startColor.opacity(trackOpacity),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            // Postęp — pierwsza pętla. Podział na pętle robi KSZTAŁT
            // (`RingLap`), nie widok: `animatableData` to surowy postęp, więc
            // każda klatka animacji liczy podział od nowa i druga pętla rusza
            // dopiero wtedy, gdy pierwsza dojedzie do pełnego koła. Dwa
            // osobne `trim` liczone w widoku interpolowały się równolegle od
            // zera i nadmiar rysował się ciemniejszym kolorem od pierwszej
            // klatki, zanim zwykły postęp skończył jechać.
            RingLap(progress: progress, lap: 0)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [startColor, endColor, startColor]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                // Pełne koło zostaje w pełnej mocy także po przekroczeniu
                // celu: „cel zrobiony" nie przestaje być prawdą dlatego, że
                // doszło do niego jeszcze trochę.
                .shadow(color: endColor.opacity(clamped > 0 && !isOver ? 0.35 : 0), radius: 6, x: 0, y: 0)

            // Nadmiar — druga pętla, ten sam kolor przyciemniony. Rysowany
            // ZAWSZE, nie pod `if` — przy `if` przejście przez 100 %
            // wstawiałoby widok skokiem. Pusta ścieżka nie rysuje niczego,
            // więc koszt jest żaden. Sufit na drugiej pętli: przy 300 %
            // nakładka i tak domknęłaby koło.
            RingLap(progress: progress, lap: 1)
                .stroke(
                    endColor.scOverTargetShade,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .shadow(color: .black.opacity(isOver ? 0.35 : 0), radius: 3, x: 0, y: 1)
        }
    }
}

// MARK: - Pętla pierścienia

/// Łuk jednej pętli pierścienia od godziny dwunastej, w prawo.
///
/// `lap` mówi, którą pętlę rysuje ten kształt: zerowa to postęp 0–100 %,
/// pierwsza to nadmiar 100–200 %. Postęp jest `animatableData`, więc
/// SwiftUI interpoluje SUROWĄ liczbę, a podział na pętle liczy się z niej
/// przy każdej klatce — to jedyny sposób, żeby nadmiar zaczął rosnąć dokładnie
/// w chwili, w której pierwsza pętla się domknie, a nie razem z nią.
struct RingLap: Shape {
    var progress: CGFloat
    let lap: Int

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let fraction = max(0, min(progress - CGFloat(lap), 1))
        guard fraction > 0 else { return Path() }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * Double(fraction)),
            clockwise: false
        )
        return path
    }
}
