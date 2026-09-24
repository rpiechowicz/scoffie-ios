import SwiftUI

/// Zdjęcie kroku.
///
/// Dwa rodzaje grafik (`TourStep.isArtwork`):
/// - rendery telefonów na jasnym tle z szerokim marginesem — kadr 16:13,
///   `scaledToFill` plus delikatne przybliżenie zjada ten margines, żeby
///   ekrany aplikacji zajmowały kadr, a nie pływały w pustce;
/// - ilustracje z kartami aplikacji (od 24.09.2026, Plan i Przepisy) —
///   ZAWSZE na pełną szerokość (Rafał: „obrazek daj na całość, żeby było
///   dobrze widać”), `scaledToFill` bez przybliżenia. Karty zajmują całą
///   szerokość grafiki, a nad i pod nimi jest ~12 % pustego kremu — gdy
///   brakuje wysokości, ucina się ten krem, nie karty. Pomniejszanie
///   w całości (`scaledToFit`) robiło z kart miniaturę na środku, a kadr
///   16:13 z przybliżeniem ucinał karty z boków.
///
/// Wysokość kadru ma sufit: widoczna strona (`TourPage` podaje ją
/// w `tourViewport`) minus ZMIERZONA reszta kroku (`reserved`: eyebrow,
/// tytuł, opis, karta czterech punktów i marginesy — `TourStepView` mierzy
/// je co krok, bo tytuł i opis mają od jednej do trzech linii). Stały zapas
/// raz zostawiał pustkę pod kartą, raz wpychał czwarty punkt pod cień
/// stopki. Na
/// Plus / Pro Max sufit leży nad naturalną wysokością i nic się nie zmienia,
/// na mniejszych ekranach obraz traci wysokość (przycina się, szerokość
/// zostaje) — tytuł i punkty mieszczą się nad stopką bez przewijania.
private struct TourMedia: View {
    let imageName: String
    let accent: Color
    let isArtwork: Bool
    /// Wysokość strony zajęta przez wszystko poza zdjęciem.
    let reserved: CGFloat

    @Environment(\.colorScheme) private var scheme
    @Environment(\.tourViewport) private var viewport

    private static let renderAspect: CGFloat = 16.0 / 13.0
    /// Proporcje ilustracji (`TourPlan`, `TourRecipes`: 1200 × 868).
    private static let artworkAspect: CGFloat = 1200.0 / 868.0
    /// Poniżej tego kadr przestaje coś pokazywać — wtedy lepiej przewinąć.
    private static let minimum: CGFloat = 150

    private var aspect: CGFloat { isArtwork ? Self.artworkAspect : Self.renderAspect }

    /// `nil` przed pierwszym pomiarem — wtedy same proporcje.
    private var size: CGSize? {
        guard viewport.width > 0, viewport.height > 0 else { return nil }
        let fullWidth = viewport.width - 2 * TourLayout.mediaHorizontal
        let natural = fullWidth / aspect
        // Ilustracja nie schodzi poniżej 90 % naturalnej wysokości: tyle
        // zjada sam krem nad i pod kartami (po ~5 %), a nagłówki kart
        // („Przepisy”, „Plan tygodnia”) leżą ~12 % od brzegu. Niżej ucinało
        // już karty — wtedy lepiej, żeby strona się przewinęła.
        let floor = isArtwork ? natural * 0.9 : Self.minimum
        let height = min(natural, max(floor, viewport.height - reserved))
        return CGSize(width: fullWidth, height: height)
    }

    var body: some View {
        mediaFrame
            .overlay {
                if isArtwork {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(1.06)
                }
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
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mediaFrame: some View {
        if let size {
            Color.clear
                .frame(width: size.width, height: size.height)
        } else {
            Color.clear
                .aspectRatio(aspect, contentMode: .fit)
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
    /// Wysokość nagłówka i karty punktów — reszta strony idzie na zdjęcie.
    /// 400 do pierwszego pomiaru (typowy krok na iPhonie 6,1").
    @State private var textHeight: CGFloat = 400

    private static let mediaGap: CGFloat = 16

    var body: some View {
        TourPage {
            VStack(alignment: .leading, spacing: 0) {
                TourMedia(
                    imageName: step.imageName,
                    accent: step.accent,
                    isArtwork: step.isArtwork,
                    reserved: textHeight + Self.mediaGap + TourLayout.top + TourLayout.bottom
                )
                .padding(.horizontal, TourLayout.mediaHorizontal)
                .padding(.bottom, Self.mediaGap)

                textBlock
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        textHeight = height
                    }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            hasAppeared = true
        }
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            .padding(.bottom, 12)

            TourPointsCard(points: step.points, accent: step.accent, isVisible: hasAppeared)
                .padding(.horizontal, TourLayout.horizontal)
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
