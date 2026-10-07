import SwiftUI

/// Wymiary wspólne dla wszystkich kroków kreatora.
///
/// Jedno miejsce, bo kroki jeżdżą na bok jeden po drugim i każda różnica
/// między nimi jest widoczna jako skok w trakcie przejścia.
///
/// Od 7.10.2026 karty, wiersze i odstępy w środku kroków biorą się z widoków
/// Ustawień (`ProfileBodyForm`, `DietPreferencesForm`, `MealDayAxisList`,
/// `HouseholdKit`) — dawne klocki kreatora (`WelcomeSection`,
/// `WelcomeOptionRow`, `welcomeCard()`, `YearWheelPicker`) usunięte.
enum WelcomeLayout {
    /// Margines stron aplikacji (`SCPageMetrics`) — ten sam, co w stopce
    /// kroków (`SCSheetFooter`), więc karty i przycisk stoją w jednej linii.
    static let horizontal: CGFloat = SCPageMetrics.horizontal
    /// Od bezpiecznego obszaru, jak strona przewodnika (`TourLayout.top`) —
    /// przejście przewodnik → kreator nie przesuwa nagłówka.
    static let topInset: CGFloat = TourLayout.top
    /// Oddech pod ostatnią kartą. Stopka kroków stoi w `safeAreaBar`
    /// (7.10.2026), więc przewijana treść sama kończy się nad nią — dawny
    /// zapas na wysokość stopki i jej cień (~150 pt) odpadł.
    static let bottomInset: CGFloat = 24
    /// Odstęp nagłówka kroku od treści.
    static let headerSpacing: CGFloat = 22
}

/// Strona kroku kreatora: nagłówek i treść w przewijaniu, górny brzeg treści
/// gaśnie pod paskiem stanu (`scScrollEdgeFade`). Krok „Posiłki” ma zamiast
/// niej listę (`MealDayAxisList` z nagłówkiem w `top:`), bo przesunięcie
/// wiersza działa tylko w `List`.
struct WelcomeStepPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, WelcomeLayout.horizontal)
            .padding(.top, WelcomeLayout.topInset)
            .padding(.bottom, WelcomeLayout.bottomInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scScrollEdgeFade()
        .scrollDismissesKeyboard(.interactively)
    }
}
