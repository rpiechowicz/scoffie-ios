import SwiftUI

struct OnboardingHeroPattern: View {
    @Environment(\.colorScheme) private var colorScheme

    private struct Tile: Hashable {
        let symbol: String
        let color: Color
    }

    // Kuchnia, jedzenie i planowanie — 41 symboli. Liczba pierwsza celowo:
    // każdy `stride` w `rowConfigs` jest z nią względnie pierwszy, więc każdy
    // rząd dostaje pełną, INNĄ permutację (patrz `animatedRow`).
    private static let symbols: [String] = [
        "frying.pan.fill", "leaf.fill", "flame.fill", "cart.fill", "heart.fill",
        "fork.knife", "calendar", "sparkles", "clock.fill", "bell.fill",
        "carrot.fill", "cup.and.saucer.fill", "basket.fill", "birthday.cake.fill", "fish.fill",
        "book.closed.fill", "list.bullet.clipboard.fill", "timer", "star.fill", "bookmark.fill",
        "takeoutbag.and.cup.and.straw.fill", "mug.fill", "wineglass.fill", "waterbottle.fill", "refrigerator.fill",
        "oven.fill", "stove.fill", "microwave.fill", "cooktop.fill", "popcorn.fill",
        "drop.fill", "sun.max.fill", "moon.stars.fill", "person.2.fill", "house.fill",
        "chart.pie.fill", "bag.fill", "gift.fill", "scalemass.fill", "cup.and.heat.waves.fill",
        "target"
    ]

    // Wszystkie osiem akcentów palety, nie pięć: róż, morska i lawenda
    // (barwy pór „pomiędzy”) rozbijają rytm terakota–szałwia–masło–indygo.
    private static let colors: [Color] = [
        SCPalette.terracotta, SCPalette.sage, SCPalette.butter, SCPalette.indigo,
        SCPalette.rose, SCPalette.teal, SCPalette.lavender, SCPalette.terracottaDeep
    ]

    /// Barwa kafla — pseudolosowa, ale STAŁA między klatkami (liczona z pozycji
    /// kafla i numeru rzędu, bez generatora), żeby kolory nie migały przy każdym
    /// odświeżeniu `TimelineView`. Ta sama ikona w innym rzędzie wychodzi
    /// zwykle w innym kolorze, a sąsiednie kafle nigdy nie dzielą barwy.
    private static func tiles(forRow row: Int, order: [Int]) -> [Tile] {
        var previous = -1
        return order.enumerated().map { position, symbolIndex in
            var hash = UInt64(symbolIndex &* 2_654_435_761) ^ UInt64(row &* 40_503 &+ position &* 97)
            hash ^= hash >> 13
            hash = hash &* 0x5bd1_e995
            hash ^= hash >> 15
            var colorIndex = Int(hash % UInt64(colors.count))
            if colorIndex == previous { colorIndex = (colorIndex + 3) % colors.count }
            previous = colorIndex
            return Tile(symbol: symbols[symbolIndex], color: colors[colorIndex])
        }
    }

    // Per-row: inny `stride` (względnie pierwszy z liczbą symboli = 41) daje
    // każdemu rzędowi INNĄ permutację — żaden rząd nie układa się w identyczną
    // sekwencję obok sąsiada. `rotation` przesuwa start. Sąsiednie rzędy idą
    // w przeciwnych kierunkach z różnymi prędkościami.
    private struct RowConfig {
        let stride: Int
        let rotation: Int
        let direction: CGFloat
        let speed: CGFloat
    }

    private static let rowConfigs: [RowConfig] = [
        RowConfig(stride: 1,  rotation: 0,  direction: -1, speed: 12),
        RowConfig(stride: 7,  rotation: 11, direction:  1, speed:  9),
        RowConfig(stride: 17, rotation: 23, direction: -1, speed: 14)
    ]

    /// Kafle rzędów liczone RAZ, a nie w każdej klatce animacji.
    private let rows: [[Tile]]

    init() {
        let n = Self.symbols.count
        rows = Self.rowConfigs.enumerated().map { row, config in
            let order = (0..<n).map { (config.rotation + $0 * config.stride) % n }
            return Self.tiles(forRow: row, order: order)
        }
    }

    // Wymiary zgodne z designem (Scoffie - Onboarding.html, B2):
    // tile 72, gap 10, hero 280, paddingTop 60 (pod status barem),
    // brand chip przy top 66 / left 24 (absolutne pozycjonowanie).
    //
    // Wysokość daje RODZIC (`AuthView`: 150–280 pt). Ekran logowania nie
    // przewija się, więc na niskim telefonie to hero oddaje miejsce treści —
    // rzędy kafli zostają te same, tylko kadr i wygaszenie u dołu są krótsze.
    private let tileSize: CGFloat = 72
    private let gap: CGFloat = 10
    private let topInset: CGFloat = 60
    private let brandChipTop: CGFloat = 66
    private let brandChipLeading: CGFloat = 24

    private var itemWidth: CGFloat { tileSize + gap }

    var body: some View {
        // GeometryReader mierzy parent width, a potem wymusza ten rozmiar na
        // zawartości. Bez tego HStack z kaflami propaguje swoją intrinsic
        // width do parent layoutu, rozpychając cały widok. `.clipped()` kropi
        // wizualny nadmiar, carousel nadal przewija się „za kadrem".
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                TimelineView(.animation) { context in
                    let t = CGFloat(context.date.timeIntervalSinceReferenceDate)
                    VStack(alignment: .leading, spacing: gap) {
                        ForEach(0..<Self.rowConfigs.count, id: \.self) { idx in
                            animatedRow(rows[idx], config: Self.rowConfigs[idx], time: t)
                        }
                    }
                    .padding(.top, topInset)
                }

                bottomFade

                brandChip
                    .padding(.leading, brandChipLeading)
                    .padding(.top, brandChipTop)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .ignoresSafeArea(edges: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scoffie")
    }

    @ViewBuilder
    private func animatedRow(_ rotated: [Tile], config: RowConfig, time: CGFloat) -> some View {
        let cycle = CGFloat(rotated.count) * itemWidth
        let scrolled = time * config.speed
        let wrapped = scrolled.truncatingRemainder(dividingBy: cycle)
        // offsetX ∈ [-cycle, 0]; 2× duplikacja kafli ukrywa zawijanie.
        let offsetX: CGFloat = config.direction < 0 ? -wrapped : (wrapped - cycle)

        HStack(spacing: gap) {
            ForEach(0..<(rotated.count * 2), id: \.self) { i in
                tileCell(rotated[i % rotated.count])
            }
        }
        .offset(x: offsetX)
    }

    private func tileCell(_ tile: Tile) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.scTileBg(colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.scTileStroke(colorScheme), lineWidth: 1)
            )
            .overlay(
                Image(systemName: tile.symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(tile.color)
            )
            .frame(width: tileSize, height: tileSize)
    }

    private var bottomFade: some View {
        // 1:1 wg designu: linear-gradient(to bottom, transparent 50%, bg 95%).
        LinearGradient(
            stops: [
                .init(color: Color.scCanvas(colorScheme).opacity(0), location: 0.50),
                .init(color: Color.scCanvas(colorScheme),            location: 0.95)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    private var brandChip: some View {
        HStack(spacing: 8) {
            // Mini app icon (logo v3) — chip udaje systemowy notification
            // banner, więc pokazuje prawdziwą ikonę aplikacji.
            SCScoffieMark(size: 22)

            Text("Scoffie")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.scLabel(colorScheme))
        }
        .padding(.vertical, 6)
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .background(
            Capsule()
                .fill(
                    colorScheme == .dark
                        ? Color.scCanvas(.dark).opacity(0.75)
                        : Color(red: 255 / 255, green: 251 / 255, blue: 244 / 255).opacity(0.85)
                )
                .background(.ultraThinMaterial, in: Capsule())
        )
    }
}

#Preview("Dark") {
    OnboardingHeroPattern()
        .frame(height: 280)
        .background(Color.scCanvas(.dark))
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    OnboardingHeroPattern()
        .frame(height: 280)
        .background(Color.scCanvas(.light))
        .preferredColorScheme(.light)
}
