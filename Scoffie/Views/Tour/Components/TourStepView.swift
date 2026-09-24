import SwiftUI

/// Zdjęcie kroku w kadrze 16:13.
///
/// Zdjęcia to rendery telefonów na jasnym tle z szerokim marginesem —
/// `scaledToFill` plus delikatne przybliżenie zjada ten margines, żeby
/// ekrany aplikacji zajmowały kadr, a nie pływały w pustce.
///
/// Wysokość kadru ma sufit: widoczna strona (`TourPage` podaje ją
/// w `tourViewport`) minus to, czego potrzebuje reszta kroku (`reserved`:
/// eyebrow, tytuł w dwóch liniach, opis, karta czterech punktów, marginesy). Na
/// Plus / Pro Max sufit leży nad 16:13 i nic się nie zmienia, na zwykłym
/// iPhonie kadr traci kilkanaście punktów, na SE / mini wyraźnie więcej
/// (zdjęcie się przycina, szerokość zostaje) — tytuł i punkty mieszczą się
/// nad stopką bez przewijania.
private struct TourMedia: View {
    let imageName: String
    let accent: Color

    @Environment(\.colorScheme) private var scheme
    @Environment(\.tourViewport) private var viewport

    private static let aspect: CGFloat = 16.0 / 13.0
    /// Wszystko na stronie kroku poza zdjęciem (liczone z odstępów
    /// `TourStepView` i `TourLayout`, z zapasem na dwulinijkowy tytuł
    /// i trzylinijkowy opis — `TourStep.lead`; bez kapsułki „Znajdziesz w…”
    /// nad zdjęciem, za to z eyebrow i wyższymi wierszami punktów z ikonami).
    private static let reserved: CGFloat = 470
    /// Poniżej tego kadr przestaje coś pokazywać — wtedy lepiej przewinąć.
    private static let minimum: CGFloat = 150

    /// `nil` przed pierwszym pomiarem — wtedy sam 16:13.
    private var height: CGFloat? {
        guard viewport.width > 0, viewport.height > 0 else { return nil }
        let natural = (viewport.width - 2 * TourLayout.mediaHorizontal) / Self.aspect
        return min(natural, max(Self.minimum, viewport.height - Self.reserved))
    }

    var body: some View {
        mediaFrame
            .overlay {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(1.06)
            }
            .background(
                RadialGradient(
                    colors: [accent.opacity(scheme == .dark ? 0.20 : 0.14), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 260
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mediaFrame: some View {
        if let height {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: height)
        } else {
            Color.clear
                .aspectRatio(Self.aspect, contentMode: .fit)
        }
    }
}

/// Treść jednego kroku przewodnika: jak wygląda (zdjęcie), gdzie to jest
/// (eyebrow), co robi (tytuł i dwa zdania opisu), co z tego macie (cztery punkty w karcie,
/// wchodzące kaskadą po wjeździe strony). Pasek kroków
/// i przyciski są w stopce (`SCStepFooter`) — osobno, bo treść jeździ
/// między krokami, a stopka ma stać w miejscu.
struct TourStepView: View {
    let step: TourStep

    @Environment(\.colorScheme) private var scheme
    /// Kaskada punktów — przestawiane w `.task` (klatka oddechu, jak
    /// w `SCReveal`); każda strona ma własną tożsamość (`.id(phase)`
    /// w `FeatureTourView`), więc kaskada gra przy każdym kroku.
    @State private var hasAppeared = false

    var body: some View {
        TourPage {
            VStack(alignment: .leading, spacing: 0) {
                TourMedia(imageName: step.imageName, accent: step.accent)
                    .padding(.horizontal, TourLayout.mediaHorizontal)
                    .padding(.bottom, 20)

                // Ten sam nagłówek kroku, co w kreatorze i u asystenta: eyebrow
                // w kolorze kroku mówi, gdzie to jest w aplikacji — bez kafelka,
                // bo nad nagłówkiem stoi zdjęcie.
                SCStepHeader(
                    accent: step.accent,
                    eyebrow: step.eyebrow,
                    title: step.title,
                    subtitle: step.lead
                )
                    .padding(.horizontal, TourLayout.horizontal)
                    .padding(.bottom, 14)

                TourPointsCard(points: step.points, accent: step.accent, isVisible: hasAppeared)
                    .padding(.horizontal, TourLayout.horizontal)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            hasAppeared = true
        }
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
