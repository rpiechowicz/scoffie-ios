import SwiftUI

/// Zdjęcie kroku w kadrze 16:13.
///
/// Zdjęcia to rendery telefonów na jasnym tle z szerokim marginesem —
/// `scaledToFill` plus delikatne przybliżenie zjada ten margines, żeby
/// ekrany aplikacji zajmowały kadr, a nie pływały w pustce.
private struct TourMedia: View {
    let imageName: String
    let accent: Color

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Color.clear
            .aspectRatio(16.0 / 13.0, contentMode: .fit)
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
}

/// Treść jednego kroku przewodnika: gdzie to jest (chip), jak wygląda
/// (zdjęcie), co robi (tytuł), co z tego macie (trzy punkty). Pasek kroków
/// i przyciski są w stopce (`SCStepFooter`) — osobno, bo treść jeździ
/// między krokami, a stopka ma stać w miejscu.
struct TourStepView: View {
    let step: TourStep

    @Environment(\.colorScheme) private var scheme

    /// „Znajdziesz w Zakładce Plan" — mówi wprost, w którym miejscu
    /// aplikacji szukać funkcji z tego kroku. Zastępuje rysunek paska
    /// zakładek, który w tej skali byłby plamką.
    private var placeLabel: Text {
        Text("Znajdziesz w ")
            .foregroundStyle(Color.scMuted(scheme))
        + Text(step.place)
            .foregroundStyle(Color.scLabel(scheme))
            .fontWeight(.semibold)
    }

    var body: some View {
        TourPage {
            VStack(alignment: .leading, spacing: 0) {
                TourChip(icon: step.placeIcon, accent: step.accent, label: placeLabel)
                    .padding(.horizontal, TourLayout.horizontal)
                    .padding(.bottom, 14)

                TourMedia(imageName: step.imageName, accent: step.accent)
                    .padding(.horizontal, TourLayout.mediaHorizontal)
                    .padding(.bottom, 22)

                // Ten sam nagłówek kroku, co w kreatorze i u asystenta —
                // tu bez kafelka, bo miejsce i kolor niesie chip nad zdjęciem.
                SCStepHeader(title: step.title)
                    .padding(.horizontal, TourLayout.horizontal)
                    .padding(.bottom, 16)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(step.points, id: \.self) { point in
                        TourPoint(text: point, accent: SCPalette.sage)
                    }
                }
                .padding(.horizontal, TourLayout.horizontal)
            }
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
