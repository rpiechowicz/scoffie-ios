import SwiftUI

struct OnboardingHeroPattern: View {
    @Environment(\.colorScheme) private var colorScheme

    private struct Tile: Hashable {
        let symbol: String
        let color: Color
    }

    // Bogata paleta ikon „kuchenno-planujących" — większa różnorodność =
    // mniejsze wrażenie powtórzenia podczas scrollowania.
    private static let tiles: [Tile] = [
        Tile(symbol: "frying.pan.fill",            color: WMPalette.terracotta),
        Tile(symbol: "leaf.fill",                  color: WMPalette.sage),
        Tile(symbol: "flame.fill",                 color: WMPalette.butter),
        Tile(symbol: "cart.fill",                  color: WMPalette.indigo),
        Tile(symbol: "heart.fill",                 color: WMPalette.terracottaDeep),
        Tile(symbol: "fork.knife",                 color: WMPalette.sage),
        Tile(symbol: "calendar",                   color: WMPalette.terracotta),
        Tile(symbol: "sparkles",                   color: WMPalette.butter),
        Tile(symbol: "clock.fill",                 color: WMPalette.indigo),
        Tile(symbol: "bell.fill",                  color: WMPalette.terracottaDeep),
        Tile(symbol: "carrot.fill",                color: WMPalette.terracotta),
        Tile(symbol: "cup.and.saucer.fill",        color: WMPalette.sage),
        Tile(symbol: "basket.fill",                color: WMPalette.butter),
        Tile(symbol: "birthday.cake.fill",         color: WMPalette.indigo),
        Tile(symbol: "fish.fill",                  color: WMPalette.terracottaDeep),
        Tile(symbol: "book.closed.fill",           color: WMPalette.terracotta),
        Tile(symbol: "list.bullet.clipboard.fill", color: WMPalette.sage),
        Tile(symbol: "timer",                      color: WMPalette.butter),
        Tile(symbol: "star.fill",                  color: WMPalette.indigo),
        Tile(symbol: "bookmark.fill",              color: WMPalette.terracottaDeep)
    ]

    // Per-row: inny `stride` (coprime z liczbą kafli = 20) powoduje, że każdy
    // rząd dostaje INNĄ permutację kafli — żaden rząd nie układa się w
    // identyczną sekwencję obok sąsiada. `rotation` przesuwa start.
    // Sąsiednie rzędy idą w przeciwnych kierunkach z różnymi prędkościami.
    private struct RowConfig {
        let stride: Int
        let rotation: Int
        let direction: CGFloat
        let speed: CGFloat
    }

    private let rowConfigs: [RowConfig] = [
        RowConfig(stride: 1,  rotation: 0, direction: -1, speed: 12),
        RowConfig(stride: 7,  rotation: 3, direction:  1, speed:  9),
        RowConfig(stride: 13, rotation: 9, direction: -1, speed: 14)
    ]

    // Wymiary zgodne z designem (Scoffie - Onboarding.html, B2):
    // tile 72, gap 10, hero 280, paddingTop 60 (pod status barem),
    // brand chip przy top 66 / left 24 (absolutne pozycjonowanie).
    private let tileSize: CGFloat = 72
    private let gap: CGFloat = 10
    private let heroHeight: CGFloat = 280
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
                        ForEach(0..<rowConfigs.count, id: \.self) { idx in
                            animatedRow(config: rowConfigs[idx], time: t)
                        }
                    }
                    .padding(.top, topInset)
                }

                bottomFade

                brandChip
                    .padding(.leading, brandChipLeading)
                    .padding(.top, brandChipTop)
            }
            .frame(width: proxy.size.width, height: heroHeight, alignment: .topLeading)
            .clipped()
        }
        .frame(height: heroHeight)
        .ignoresSafeArea(edges: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scoffie")
    }

    @ViewBuilder
    private func animatedRow(config: RowConfig, time: CGFloat) -> some View {
        let n = Self.tiles.count
        // Liniowa permutacja: stride coprime z n daje każdemu rzędowi inną
        // kolejność kafli, a rotation przesuwa pierwszy widoczny kafel.
        let rotated: [Tile] = (0..<n).map { i in
            Self.tiles[(config.rotation + i * config.stride) % n]
        }

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
            .fill(Color.wmTileBg(colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.wmTileStroke(colorScheme), lineWidth: 1)
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
                .init(color: Color.wmCanvas(colorScheme).opacity(0), location: 0.50),
                .init(color: Color.wmCanvas(colorScheme),            location: 0.95)
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
            WMSteamingBowlLogo(size: 22)

            Text("Scoffie")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.wmLabel(colorScheme))
        }
        .padding(.vertical, 6)
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .background(
            Capsule()
                .fill(
                    colorScheme == .dark
                        ? Color.wmCanvas(.dark).opacity(0.75)
                        : Color(red: 255 / 255, green: 251 / 255, blue: 244 / 255).opacity(0.85)
                )
                .background(.ultraThinMaterial, in: Capsule())
        )
    }
}

#Preview("Dark") {
    OnboardingHeroPattern()
        .background(Color.wmCanvas(.dark))
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    OnboardingHeroPattern()
        .background(Color.wmCanvas(.light))
        .preferredColorScheme(.light)
}
