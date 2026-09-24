import SwiftUI

/// Krok przewodnika: plakat z R2 na całą wysokość strony.
///
/// Plakat (1080 × 2344, te same grafiki co zrzuty w App Store) ma własny
/// nagłówek, opis i karty aplikacji — dlatego krok nie rysuje już nad nim
/// ani pod nim niczego swojego (Rafał 24.09.2026: „podmień przewodnik”).
/// Dawny układ — pozioma ilustracja, `SCStepHeader`, karta czterech funkcji
/// — powtarzałby ten sam tekst dwa razy.
///
/// Plakat mieści się w CAŁOŚCI bez przewijania: bierze wysokość strony nad
/// stopką, szerokość z proporcji, i stoi na środku. Na wąskim, wysokim
/// ekranie pierwszeństwo ma szerokość (marginesy strony), na niskim —
/// wysokość (plakat się zwęża). Zanim dojdzie z sieci, w jego miejscu stoi
/// tint koloru kroku w tym samym rozmiarze, a plakat wchodzi kryciem
/// (`CachedAsyncImage`); zwykle jest już w pamięci, bo
/// `TourStep.prefetchImages()` rusza na ekranie logowania.
struct TourStepView: View {
    let step: TourStep

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Wjazd plakatu — przestawiane w `.task` (klatka oddechu, jak
    /// w `SCReveal`); każda strona ma własną tożsamość (`.id(pageKey)`
    /// w `WelcomeView`), więc wjazd gra przy każdym kroku.
    @State private var hasAppeared = false

    private static let aspect: CGFloat = 1080.0 / 2344.0
    private static let radius: CGFloat = 26

    var body: some View {
        GeometryReader { proxy in
            let availableHeight = max(0, proxy.size.height - TourLayout.top - TourLayout.bottom)
            let maxWidth = max(0, proxy.size.width - 2 * TourLayout.mediaHorizontal)
            let width = min(maxWidth, availableHeight * Self.aspect)

            poster
                .frame(width: width, height: width / Self.aspect)
                .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.96)
                .opacity(hasAppeared || reduceMotion ? 1 : 0)
                .animation(.smooth(duration: 0.5), value: hasAppeared)
                .position(x: proxy.size.width / 2, y: TourLayout.top + availableHeight / 2)
        }
        .task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            hasAppeared = true
        }
    }

    private var poster: some View {
        RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
            .fill(step.accent.opacity(scheme == .dark ? 0.14 : 0.10))
            .overlay {
                CachedAsyncImage(url: step.imageURL, variant: .poster) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.clear
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
            // Tekst plakatu dla VoiceOver — obrazka czytnik nie przeczyta.
            .accessibilityElement()
            .accessibilityLabel(step.title)
            .accessibilityValue(step.lead)
            .accessibilityAddTraits(.isImage)
    }
}

#Preview("Krok 1 · Dark") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()
        VStack(spacing: 0) {
            TourStepView(step: TourStep.all[0])
            SCStepFooter(slot: .progress(step: 1, total: 5), showsBack: true, onBack: {}, primaryTitle: "Dalej", onPrimary: {})
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Krok 4 · Light") {
    ZStack {
        SCPageBackground(scheme: .light).ignoresSafeArea()
        VStack(spacing: 0) {
            TourStepView(step: TourStep.all[3])
            SCStepFooter(slot: .progress(step: 4, total: 5), showsBack: true, onBack: {}, primaryTitle: "Dalej", onPrimary: {})
        }
    }
    .preferredColorScheme(.light)
}
