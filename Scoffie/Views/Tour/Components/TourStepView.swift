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
                    .stroke(Color.scCardStroke(scheme), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

/// Treść jednego kroku przewodnika: gdzie to jest (chip), jak wygląda
/// (zdjęcie), co robi (tytuł i opis), co z tego macie (trzy punkty).
/// Stepper i przyciski są w `TourFooter` — osobno, bo treść jeździ
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

                VStack(alignment: .leading, spacing: 8) {
                    Text(step.title)
                        .font(.system(size: 27, weight: .bold))
                        .tracking(-0.4)
                        .lineSpacing(2)
                        .foregroundStyle(Color.scLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(step.summary)
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, TourLayout.horizontal)
                .padding(.bottom, 14)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(step.points, id: \.self) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(SCPalette.terracotta)
                            Text(point)
                                .font(.system(size: 13.5))
                                .foregroundStyle(Color.scLabel(scheme).opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, TourLayout.horizontal)
            }
        }
    }
}

#Preview("Krok 1 · Dark") {
    ZStack {
        TourBackground(scheme: .dark)
        VStack(spacing: 0) {
            TourStepView(step: TourStep.all[0])
            TourFooter(kind: .step(index: 0, total: 5), onBack: {}, onPrimary: {}, onSkip: {})
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Krok 4 · Light") {
    ZStack {
        TourBackground(scheme: .light)
        VStack(spacing: 0) {
            TourStepView(step: TourStep.all[3])
            TourFooter(kind: .step(index: 3, total: 5), onBack: {}, onPrimary: {}, onSkip: {})
        }
    }
    .preferredColorScheme(.light)
}
