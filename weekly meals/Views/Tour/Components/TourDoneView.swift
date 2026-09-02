import SwiftUI

/// Ekran domykający przewodnik — przejście z „oto co potrafimy" do „teraz
/// Wasza kolej".
///
/// Każdy wiersz to para: co podajesz → po co nam to. Kreator pyta o wzrost,
/// wagę i alergeny zaraz po pierwszym uruchomieniu, więc powód musi paść
/// zanim padnie pytanie, a nie w polityce prywatności.
///
/// Przyciski są w `TourDoneFooter` — stopkę składa `FeatureTourView`
/// poza animowaną treścią.
struct TourDoneView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TourPage {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Zostały dwie minuty")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(WMPalette.terracotta)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.wmAccentTint(scheme)))
                .padding(.bottom, 14)

                Text("Znasz już nas.\nTeraz my poznajmy Ciebie.")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .lineSpacing(3)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)

                Text("Kilka pytań — każde ma konkretny powód:")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .padding(.bottom, 12)

                VStack(spacing: 0) {
                    TourFeatureRow(
                        icon: "slider.horizontal.3",
                        tint: WMPalette.terracotta,
                        title: "Wzrost, waga, wiek i aktywność",
                        subtitle: "Liczymy dzienne zapotrzebowanie i rozkładamy je na posiłki",
                        alignsTop: true
                    )
                    TourFeatureRow(
                        icon: "leaf",
                        tint: WMPalette.sage,
                        title: "Alergeny",
                        subtitle: "Przepisy z tymi składnikami nie pokażą się nigdzie — ani w planie, ani na liście zakupów",
                        alignsTop: true
                    )
                    TourFeatureRow(
                        icon: "fork.knife",
                        tint: WMPalette.indigo,
                        title: "Dieta i cel kaloryczny",
                        subtitle: "Zawężamy katalog i pilnujemy, żeby dzień się spinał: wege, bez laktozy, bez wieprzowiny",
                        alignsTop: true
                    )
                    TourFeatureRow(
                        icon: "clock",
                        tint: WMPalette.butter,
                        title: "Posiłki i ich pory",
                        subtitle: "Dobieramy liczbę dań i takie przepisy, które zdążycie ugotować",
                        alignsTop: true
                    )
                    TourFeatureRow(
                        icon: "house",
                        tint: WMPalette.terracottaDeep,
                        title: "Gospodarstwo",
                        subtitle: "Plan i lista zakupów są wspólne — zaprosisz do nich domowników",
                        isLast: true,
                        alignsTop: true
                    )
                }
                .padding(.bottom, 14)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Dane zostają na Twoim koncie — zmienisz je w każdej chwili w Ustawieniach.")
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color.wmMuted(scheme))
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 8)
        }
    }
}

/// Stopka ekranu domykającego: powrót do ostatniego kroku albo wejście
/// do kreatora.
struct TourDoneFooter: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            WMSoftIconButton(
                systemName: "chevron.left",
                accessibilityLabel: "Wstecz",
                action: onBack
            )
            WMSoftButton(title: "Opowiedz nam o sobie", action: onContinue)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }
}

#Preview("Dark") {
    ZStack {
        TourBackground(scheme: .dark)
        VStack(spacing: 0) {
            TourDoneView()
            TourDoneFooter(onContinue: {}, onBack: {})
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Light") {
    ZStack {
        TourBackground(scheme: .light)
        VStack(spacing: 0) {
            TourDoneView()
            TourDoneFooter(onContinue: {}, onBack: {})
        }
    }
    .preferredColorScheme(.light)
}
