import SwiftUI

/// Zdjęcie kroku — ilustracja z kartami aplikacji z R2 (`TourStep.imageURL`,
/// od 24.09.2026 wszystkie pięć, 1474 × 1067 WebP).
///
/// ZAWSZE na pełną szerokość (Rafał: „obrazek daj na całość, żeby było
/// dobrze widać”), `scaledToFill` bez przybliżenia. Karty zajmują całą
/// szerokość grafiki, a nad i pod nimi jest ~12 % pustego kremu — gdy
/// brakuje wysokości, ucina się ten krem, nie karty. Pomniejszanie
/// w całości (`scaledToFit`) robiło z kart miniaturę na środku.
///
/// Wysokość kadru ma sufit: widoczna strona (`TourPage` podaje ją
/// w `tourViewport`) minus ZMIERZONA reszta kroku (`reserved`: eyebrow,
/// tytuł, opis, karta czterech punktów i marginesy — `TourStepView` mierzy
/// je co krok, bo tytuł i opis mają od jednej do trzech linii). Stały zapas
/// raz zostawiał pustkę pod kartą, raz wpychał czwarty punkt pod cień
/// stopki. Na Plus / Pro Max sufit leży nad naturalną wysokością i nic się
/// nie zmienia, na mniejszych ekranach obraz traci wysokość (przycina się,
/// szerokość zostaje) — tytuł i punkty mieszczą się nad stopką bez przewijania.
///
/// Zanim grafika dojdzie z sieci, kadr stoi w swoim rozmiarze na tincie
/// koloru kroku — układ nie skacze, a grafika wchodzi kryciem
/// (`CachedAsyncImage`). Zwykle jest już w pamięci: `TourStep.prefetchImages()`
/// rusza na ekranie logowania.
private struct TourMedia: View {
    let imageURL: URL
    let accent: Color
    /// Wysokość strony zajęta przez wszystko poza zdjęciem.
    let reserved: CGFloat

    @Environment(\.colorScheme) private var scheme
    @Environment(\.tourViewport) private var viewport

    /// Proporcje ilustracji (1474 × 1067).
    private static let aspect: CGFloat = 1474.0 / 1067.0

    /// `nil` przed pierwszym pomiarem — wtedy same proporcje.
    private var size: CGSize? {
        guard viewport.width > 0, viewport.height > 0 else { return nil }
        let fullWidth = viewport.width - 2 * TourLayout.mediaHorizontal
        let natural = fullWidth / Self.aspect
        // Ilustracja nie schodzi poniżej 85 % naturalnej wysokości: tyle
        // zjada sam krem nad i pod kartami (po ~7 %), a nagłówki kart
        // („Przepisy”, „Plan tygodnia”) leżą ~11 % od brzegu. Niżej ucinało
        // już karty. 85, nie 90 — przy 90 na iPhonie 16e czwarty punkt
        // wchodził pod cień stopki, a przewodnik ma stać bez przewijania.
        let height = min(natural, max(natural * 0.85, viewport.height - reserved))
        return CGSize(width: fullWidth, height: height)
    }

    var body: some View {
        mediaFrame
            .overlay {
                CachedAsyncImage(url: imageURL, variant: .large) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.clear
                    }
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
    /// w `WelcomeView`), więc kaskada gra przy każdym kroku.
    @State private var hasAppeared = false
    /// Wysokość nagłówka i karty punktów — reszta strony idzie na zdjęcie.
    /// 400 do pierwszego pomiaru (typowy krok na iPhonie 6,1").
    @State private var textHeight: CGFloat = 400

    private static let mediaGap: CGFloat = 16

    var body: some View {
        TourPage {
            VStack(alignment: .leading, spacing: 0) {
                TourMedia(
                    imageURL: step.imageURL,
                    accent: step.accent,
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

            SCStepFeatureCard(
                features: step.points.map {
                    SCStepFeature(icon: $0.icon, accent: step.accent, title: $0.title, subtitle: $0.subtitle)
                },
                revealed: hasAppeared,
                compact: true
            )
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
