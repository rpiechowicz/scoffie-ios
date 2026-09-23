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
/// każdy krok ma tytuł i trzy punkty, bez akapitu. `ScrollView` jest tu jako
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

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, TourLayout.top)
                .padding(.bottom, TourLayout.bottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }
}

/// Kapsułka nad treścią: ikona w kafelku i krótka etykieta. Kroki mówią
/// nią „Znajdziesz w Zakładce Plan", ekran domykający — „Zostały dwie
/// minuty". Jeden widok dla obu, bo stoją w tym samym miejscu na kolejnych
/// ekranach: inna wysokość albo inne tło robiłyby skok przy przejściu.
struct TourChip: View {
    let icon: String
    let accent: Color
    let label: Text

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            // Tint jak w `SCHeaderIconWell`, ale glif 12 pt — przy 24 pt
            // kafelka proporcja nagłówka dawała 10 pt i ikona ginęła.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(scheme == .dark ? 0.16 : 0.12))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                )

            label
                .font(.system(size: 13))
                .tracking(-0.08)
        }
        .padding(.leading, 7)
        .padding(.trailing, 13)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(Color.scTileBg(scheme)))
        .overlay(Capsule(style: .continuous).stroke(Color.scTileStroke(scheme), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Punkt pod tytułem kroku: ptaszek w kółku w tincie akcentu i jedno zdanie.
/// Trzy takie zamiast akapitu opisu — konkret czyta się szybciej niż zdanie
/// o tym samym.
struct TourPoint: View {
    let text: String
    let accent: Color

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Do góry, nie do środka: dłuższy punkt łamie się na dwie linie,
        // a ptaszek ma zostać przy pierwszej. 2 pt nad tekstem wyrównują
        // środek 22-punktowego kółka ze środkiem pierwszej linii.
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(accent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(accent.opacity(scheme == .dark ? 0.16 : 0.12)))
            Text(text)
                .font(.system(size: 15))
                .tracking(-0.15)
                .foregroundStyle(Color.scLabel(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }
}
