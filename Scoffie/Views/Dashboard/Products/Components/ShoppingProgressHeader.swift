import SwiftUI

// Podsumowanie listy na Zakupach v2: „10 z 29 kupione” i pasek postępu
// z segmentem na każdą alejkę, w jej kolorze.
//
// Źródło: canvas claude.ai → „Weekly Meals - Zakupy v2.html”
// (`components/shop-v2-kit.jsx` → `ShopProgress`, `ShopBar`).
//
// Jeden podzielony pasek zamiast łuku i szesnastu pręcików przy nagłówkach:
// segment jest szeroki proporcjonalnie do liczby produktów w dziale, więc
// z jednego rzutu oka widać i ile zostało w sumie, i gdzie to leży.

/// Jeden dział na pasku postępu.
struct ShoppingProgressSegment: Identifiable, Equatable {
    let id: String
    let bought: Int
    let total: Int
    let color: Color

    var share: Double { max(0, Double(total)) }
    var fill: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(bought) / Double(total))
    }
}

struct ShoppingProgressBar: View {
    let segments: [ShoppingProgressSegment]
    var height: CGFloat = 5
    var spacing: CGFloat = 3

    @Environment(\.colorScheme) private var scheme

    private var totalWeight: Double {
        max(1, segments.reduce(0) { $0 + $1.share })
    }

    var body: some View {
        // SwiftUI nie zna wag `flex`, więc szerokości liczymy sami: odejmujemy
        // przerwy, resztę dzielimy proporcjonalnie do liczby produktów.
        GeometryReader { geo in
            let gaps = CGFloat(max(0, segments.count - 1)) * spacing
            let usable = max(0, geo.size.width - gaps)

            HStack(spacing: spacing) {
                ForEach(segments) { segment in
                    let width = usable * CGFloat(segment.share / totalWeight)

                    Capsule()
                        .fill(Color.scBarTrack(scheme))
                        .frame(width: width, height: height)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(segment.color)
                                .frame(width: width * CGFloat(segment.fill), height: height)
                        }
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
        }
        .frame(height: height)
        // Sprężyna bez odbicia, nie krzywa: wypełnienie segmentu dojeżdża
        // do końca miękko, więc odhaczenie widać na pasku nawet wtedy, gdy
        // przyrost to jedna dwudziesta jego szerokości.
        .animation(.spring(response: 0.42, dampingFraction: 0.95), value: segments)
    }
}

/// „10 z 29 kupione” + „19 do kupienia” + pasek.
struct ShoppingProgressHeader: View {
    let bought: Int
    let total: Int
    let segments: [ShoppingProgressSegment]

    @Environment(\.colorScheme) private var scheme

    private var remaining: Int { max(0, total - bought) }
    private var isComplete: Bool { total > 0 && remaining == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    CountingNumber(target: bought)
                        .font(.system(size: 20, weight: .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(Color.scLabel(scheme))

                    Text("z \(total) kupione")
                        .font(.system(size: 13, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 8)

                Text(isComplete ? "Wszystko kupione" : "\(remaining) do kupienia")
                    .font(.system(size: 12.5, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(isComplete ? SCPalette.sage : Color.scMuted(scheme))
                    .lineLimit(1)
                    // Prawa etykieta nie skaluje się ani nie zwija — jest
                    // krótsza od lewej i to lewa oddaje jej miejsce.
                    .fixedSize()
                    // Licznik schodzi w dół, więc i cyfra ma się przewijać
                    // w dół; „Wszystko kupione” wchodzi zwykłym przenikaniem,
                    // bo to już nie jest liczba.
                    .contentTransition(.numericText(countsDown: true))
                    .id(isComplete)
                    .transition(.opacity)
                    // Animacja siedzi na TEJ etykiecie, nie na całym wierszu:
                    // duży licznik obok to `CountingNumber`, który prowadzi
                    // własne odliczanie — objęty animacją z zewnątrz dostawał
                    // dwie na raz i drgał w trakcie.
                    .animation(.easeInOut(duration: 0.28), value: remaining)
            }

            ShoppingProgressBar(segments: segments)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isComplete
            ? Text("Wszystko kupione, \(total) z \(total)")
            : Text("\(bought) z \(total) kupione, \(remaining) do kupienia")
        )
    }
}
