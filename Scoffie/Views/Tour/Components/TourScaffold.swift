import SwiftUI

/// Wspólna podłoga wszystkich trzech ekranów przewodnika: kremowe/ciemne
/// tło z ciepłą poświatą u góry.
///
/// Poświata jest tu, a nie w `SCPageBackground`, bo tamta wersja startuje
/// od `scPageBase` (o pół tonu ciemniejszego od canvasu) i pod pełną
/// stroną bez nagłówka robiła widoczny szew przy dolnej krawędzi.
struct TourBackground: View {
    let scheme: ColorScheme

    var body: some View {
        ZStack(alignment: .top) {
            Color.scCanvas(scheme)
            RadialGradient(
                colors: [
                    SCPalette.terracotta.opacity(scheme == .dark ? 0.24 : 0.16),
                    .clear,
                ],
                center: .top,
                startRadius: 0,
                endRadius: 300
            )
            .frame(height: 380)
        }
        .ignoresSafeArea()
    }
}

/// Przewijalna treść jednego ekranu przewodnika.
///
/// Treść ma mieścić się bez przewijania — taki jest cel projektu i dlatego
/// każdy krok dostaje trzy punkty, a nie pięć. `ScrollView` jest tu jako
/// zabezpieczenie: na iPhonie mini albo przy powiększonej czcionce
/// systemowej to samo ułożenie nie zmieści się co do punktu, a wtedy
/// lepiej przewinąć niż przyciąć. `.basedOnSize` gasi gumowanie, gdy
/// wszystko się mieści, więc na docelowym ekranie strona stoi nieruchomo.
///
/// Stopki tu celowo nie ma. Składa ją `FeatureTourView` pod animowaną
/// treścią, żeby stepper i przyciski stały w miejscu, gdy kroki
/// przejeżdżają na bok — dokładnie tak, jak w kreatorze profilu.
struct TourPage<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }
}

/// Wiersz „ikona w kafelku + tytuł + podpis" z hairline'em pod spodem.
/// Używają go ekran powitalny i ekran domykający — w obu niesie tę samą
/// myśl: jedna rzecz na wiersz, powód napisany wprost.
struct TourFeatureRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    var isLast: Bool = false
    /// Ekran domykający ma dłuższe podpisy i potrzebuje wyrównania do góry.
    var alignsTop: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: alignsTop ? .top : .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tint)
                    )
                    .padding(.top, alignsTop ? 1 : 0)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.scLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)

            if !isLast {
                Rectangle()
                    .fill(Color.scCardStroke(scheme))
                    .frame(height: 1)
            }
        }
    }
}
