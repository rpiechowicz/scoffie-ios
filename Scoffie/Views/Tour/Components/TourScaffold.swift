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
/// Powitanie i ekran „Teraz my poznajmy Ciebie” (kroki z plakatem mają
/// własny układ — `TourStepView`). Treść ma mieścić się bez przewijania;
/// `ScrollView` jest tu jako
/// zabezpieczenie: na iPhonie mini albo przy powiększonej czcionce
/// systemowej to samo ułożenie nie zmieści się co do punktu, a wtedy
/// lepiej przewinąć niż przyciąć. `.basedOnSize` gasi gumowanie, gdy
/// wszystko się mieści, więc na docelowym ekranie strona stoi nieruchomo.
///
/// Stopki tu celowo nie ma. Składa ją `WelcomeView` pod animowaną
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
