import SwiftUI

/// Wymiary wspólne dla siedmiu ekranów przewodnika.
///
/// Ekrany przejeżdżają na bok jeden po drugim, więc każda różnica między
/// nimi jest widoczna jako skok w trakcie przejścia. Przed ujednoliceniem
/// powitanie miało margines 28, kroki 22–24, a górny odstęp wahał się
/// między 10 a 24 punktami — tytuł i chip lądowały za każdym razem gdzie
/// indziej.
enum TourLayout {
    /// Margines stron aplikacji (`SCPageMetrics`) — ten sam, co w stopce
    /// kroków (`SCSheetFooter`), więc tekst i przycisk stoją w jednej linii.
    static let horizontal: CGFloat = SCPageMetrics.horizontal
    /// Zdjęcie kroku wychodzi 4 pt poza margines tekstu — celowo, żeby
    /// kadr czytał się jako fotografia, a nie kolejny akapit.
    static let mediaHorizontal: CGFloat = SCPageMetrics.horizontal - 4
    static let top: CGFloat = 16
    /// Cień stopki (`SCEdgeShade`) leży na treści — przewinięta do końca
    /// strona kończy się nad nim, a nie w nim.
    static let bottom: CGFloat = SCEdgeShade.bottomHeight + 8
}

/// Przewijalna treść jednego ekranu przewodnika.
///
/// Treść ma mieścić się bez przewijania — taki jest cel projektu i dlatego
/// każdy krok ma tytuł, dwa zdania opisu i cztery punkty; zdjęcie kroku
/// oddaje wysokość, zanim zacznie się przewijanie (`TourMedia`). `ScrollView` jest tu jako
/// zabezpieczenie: na iPhonie mini albo przy powiększonej czcionce
/// systemowej to samo ułożenie nie zmieści się co do punktu, a wtedy
/// lepiej przewinąć niż przyciąć. `.basedOnSize` gasi gumowanie, gdy
/// wszystko się mieści, więc na docelowym ekranie strona stoi nieruchomo.
///
/// Stopki tu celowo nie ma. Składa ją `FeatureTourView` pod animowaną
/// treścią (`SCStepFooter`), żeby pasek kroków i przyciski stały w miejscu,
/// gdy kroki przejeżdżają na bok — dokładnie tak, jak w kreatorze profilu.
struct TourPage<Content: View>: View {
    private let content: Content
    /// Widoczna część strony — dla sufitu zdjęcia kroku (`TourMedia`).
    @State private var viewport: CGSize = .zero

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, TourLayout.top)
                .padding(.bottom, TourLayout.bottom)
                .environment(\.tourViewport, viewport)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            viewport = size
        }
    }
}

extension EnvironmentValues {
    /// Rozmiar widocznej strony przewodnika (`TourPage`); `.zero` przed
    /// pierwszym pomiarem.
    @Entry var tourViewport: CGSize = .zero
}

/// Punkty kroku w jednej karcie: ikona w kafelku z tintem koloru kroku
/// (`SCHeaderIconWell`) i jedno zdanie, wiersze przedzielone linią — ten sam
/// wiersz, co `SCStepFeatureCard` na powitaniu i ekranie końcowym, więc
/// cały przewodnik mówi jednym językiem. Do 24.09.2026 były tu ptaszki
/// w kółkach, jak z listy zadań. Karta jak każda inna w aplikacji —
/// `scTileBg` + `scTileStroke`, bez cienia.
///
/// Wiersze wchodzą kaskadą (`scReveal`: krycie + 14 pt z dołu) — kafelek
/// dostaje przy tym lekkie „kliknięcie” (0,6 → 1). Bez ruchu całego ekranu:
/// strona i tak wjeżdża z boku (`FeatureTourView`).
struct TourPointsCard: View {
    let points: [TourPoint]
    let accent: Color
    let isVisible: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let badge: CGFloat = 32
    private static let spacing: CGFloat = 12
    private static let horizontalPadding: CGFloat = 16
    private static let radius: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                row(point, order: index)
                    .scReveal(isVisible, order: index)
                if index < points.count - 1 {
                    Rectangle()
                        .fill(Color.scRule(scheme))
                        .frame(height: 1)
                        .padding(.leading, Self.horizontalPadding + Self.badge + Self.spacing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }

    private func row(_ point: TourPoint, order: Int) -> some View {
        HStack(spacing: Self.spacing) {
            SCHeaderIconWell(icon: point.icon, accent: accent, size: Self.badge)
                .scaleEffect(isVisible || reduceMotion ? 1 : 0.6)
                .animation(
                    reduceMotion
                        ? nil
                        : .spring(response: 0.42, dampingFraction: 0.62)
                            .delay(0.22 + Double(order) * 0.05),
                    value: isVisible
                )
            Text(point.text)
                .font(.system(size: 14.5, weight: .medium))
                .tracking(-0.15)
                .foregroundStyle(Color.scLabel(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.horizontalPadding)
        // 6, nie 10: przy ilustracji na pełną szerokość (Plan, Przepisy)
        // cztery punkty muszą zmieścić się nad stopką bez przewijania.
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
