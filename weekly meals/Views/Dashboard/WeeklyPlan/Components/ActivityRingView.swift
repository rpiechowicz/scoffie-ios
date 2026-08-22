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

/// Stos 3 pierścieni aktywności – śniadanie / obiad / kolacja.
/// Używane w hero ekranu i w wersji compact w kafelkach.
struct WeeklyActivityRings: View {
    struct Segment {
        let progress: CGFloat
        let start: Color
        let end: Color
    }

    let breakfast: Segment
    let lunch: Segment
    let dinner: Segment

    var lineWidth: CGFloat = 16
    var spacing: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let outerInset: CGFloat = 0
            let middleInset = lineWidth + spacing
            let innerInset = (lineWidth + spacing) * 2

            ZStack {
                ActivityRing(
                    progress: breakfast.progress,
                    lineWidth: lineWidth,
                    startColor: breakfast.start,
                    endColor: breakfast.end
                )
                .padding(outerInset)

                ActivityRing(
                    progress: lunch.progress,
                    lineWidth: lineWidth,
                    startColor: lunch.start,
                    endColor: lunch.end
                )
                .padding(middleInset)

                ActivityRing(
                    progress: dinner.progress,
                    lineWidth: lineWidth,
                    startColor: dinner.start,
                    endColor: dinner.end
                )
                .padding(innerInset)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Kolory dla każdego slotu – spójne na całym ekranie.
///
/// Posiłek dodatkowy dzieli rodzinę koloru z posiłkiem, obok którego stoi
/// (II śniadanie idzie ze śniadaniem), tylko w jaśniejszym wariancie —
/// sześć niezależnych gradientów zamieniłoby dzień w tęczę, a i tak nie
/// niosłoby informacji, bo to wciąż „ten sam moment dnia, mniejszy posiłek".
enum MealSlotPalette {
    static func colors(for slot: MealSlot) -> (start: Color, end: Color) {
        switch slot {
        case .breakfast:
            return (
                Color(red: 1.00, green: 0.58, blue: 0.22),
                Color(red: 1.00, green: 0.82, blue: 0.30)
            )
        case .secondBreakfast:
            return (
                Color(red: 1.00, green: 0.72, blue: 0.40),
                Color(red: 1.00, green: 0.88, blue: 0.55)
            )
        case .lunch:
            return (
                Color(red: 0.28, green: 0.56, blue: 1.00),
                Color(red: 0.34, green: 0.82, blue: 0.95)
            )
        case .afternoonSnack:
            return (
                Color(red: 0.45, green: 0.72, blue: 1.00),
                Color(red: 0.55, green: 0.90, blue: 0.96)
            )
        case .dinner:
            return (
                Color(red: 0.61, green: 0.38, blue: 1.00),
                Color(red: 0.95, green: 0.40, blue: 0.78)
            )
        case .snack:
            return (
                Color(red: 0.74, green: 0.58, blue: 1.00),
                Color(red: 0.97, green: 0.60, blue: 0.86)
            )
        }
    }

    static func gradient(for slot: MealSlot, startPoint: UnitPoint = .topLeading, endPoint: UnitPoint = .bottomTrailing) -> LinearGradient {
        let colors = colors(for: slot)
        return LinearGradient(
            colors: [colors.start, colors.end],
            startPoint: startPoint,
            endPoint: endPoint
        )
    }
}
