import SwiftUI

/// Jeden pierścień aktywności w stylu Apple Activity.
/// Renderuje tor tła + postęp z gradientem i zaokrąglonym zakończeniem.
struct ActivityRing: View {
    let progress: CGFloat            // 0...1 (może być > 1 – wtedy "przepełnia" się w nakładkę)
    let lineWidth: CGFloat
    let startColor: Color
    let endColor: Color
    var trackOpacity: Double = 0.14

    var body: some View {
        let clamped = max(0, min(progress, 1))

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
                .shadow(color: endColor.opacity(clamped > 0 ? 0.35 : 0), radius: 6, x: 0, y: 0)
        }
    }
}
