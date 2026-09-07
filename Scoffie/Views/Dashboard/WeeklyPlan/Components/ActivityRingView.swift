import SwiftUI

/// Jeden pierścień aktywności w stylu Apple Activity.
/// Renderuje tor tła + postęp z gradientem i zaokrąglonym zakończeniem.
///
/// `progress` powyżej 1 „przepełnia się w nakładkę": pierścień domyka pełne
/// koło, a nadwyżka idzie DRUGĄ pętlą po tym samym torze.
///
/// Przy tym pełne koło GAŚNIE do jednej trzeciej mocy, a pełną moc ma dopiero
/// nadwyżka. Sam cień na styku dwóch warstw tego nie załatwiał — przy pełnym
/// kole w pełnym kolorze druga pętla w tym samym kolorze była widoczna dopiero
/// z bliska. Tak zmienia się CAŁY pierścień, więc przejście przez cel widać,
/// zanim się doczyta legendę.
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
                .opacity(isOver ? 0.3 : 1)
                .shadow(color: endColor.opacity(clamped > 0 && !isOver ? 0.35 : 0), radius: 6, x: 0, y: 0)

            // Nadmiar. Rysowany ZAWSZE, nie pod `if` — przy `if` przejście
            // przez 100 % wstawiałoby widok skokiem i łuk pojawiałby się
            // gotowy, zamiast wyjeżdżać z zera razem z resztą animacji.
            // Przycięcie do zera nie rysuje niczego, więc koszt jest żaden.
            Circle()
                .trim(from: 0, to: overflow)
                .stroke(
                    endColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: endColor.opacity(isOver ? 0.5 : 0), radius: 6, x: 0, y: 0)
                .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
        }
    }
}
