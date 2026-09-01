import SwiftUI

/// Chip „Znajdziesz w…" — mówi wprost, w którym miejscu aplikacji szukać
/// funkcji z tego kroku. Zastępuje rysunek paska zakładek, który w tej
/// skali byłby plamką.
private struct TourPlaceChip: View {
    let icon: String
    let place: String
    let accent: Color

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(0.18))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                )

            (
                Text("Znajdziesz w ")
                    .foregroundStyle(Color.wmMuted(scheme))
                + Text(place)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .fontWeight(.semibold)
            )
            .font(.system(size: 13))
            .tracking(-0.08)
        }
        .padding(.leading, 7)
        .padding(.trailing, 13)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(Color.wmTileBg(scheme)))
        .overlay(Capsule(style: .continuous).stroke(Color.wmCardStroke(scheme), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

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
                    .stroke(Color.wmCardStroke(scheme), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

/// Jeden krok przewodnika: gdzie to jest (chip), jak wygląda (zdjęcie),
/// co robi (tytuł i opis), co z tego macie (trzy punkty).
struct TourStepView: View {
    let step: TourStep
    let index: Int
    let total: Int
    let onBack: () -> Void
    let onNext: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TourScaffold {
            VStack(alignment: .leading, spacing: 0) {
                TourPlaceChip(icon: step.placeIcon, place: step.place, accent: step.accent)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 14)

                TourMedia(imageName: step.imageName, accent: step.accent)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 22)

                VStack(alignment: .leading, spacing: 8) {
                    Text(step.title)
                        .font(.system(size: 27, weight: .bold))
                        .tracking(-0.4)
                        .lineSpacing(2)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(step.summary)
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(step.points, id: \.self) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(WMPalette.terracotta)
                            Text(point)
                                .font(.system(size: 13.5))
                                .foregroundStyle(Color.wmLabel(scheme).opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 10)
            .padding(.bottom, 8)
        } footer: {
            VStack(spacing: 18) {
                WelcomeStepper(step: index + 1, total: total)

                HStack(spacing: 10) {
                    WMSoftIconButton(
                        systemName: "chevron.left",
                        accessibilityLabel: "Wstecz",
                        action: onBack
                    )
                    WMSoftButton(
                        title: index == total - 1 ? "Poznajmy się" : "Dalej",
                        action: onNext
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
    }
}

#Preview("Krok 1 · Dark") {
    ZStack {
        TourBackground(scheme: .dark)
        TourStepView(step: TourStep.all[0], index: 0, total: 5, onBack: {}, onNext: {})
    }
    .preferredColorScheme(.dark)
}

#Preview("Krok 4 · Light") {
    ZStack {
        TourBackground(scheme: .light)
        TourStepView(step: TourStep.all[3], index: 3, total: 5, onBack: {}, onNext: {})
    }
    .preferredColorScheme(.light)
}
