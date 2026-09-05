import SwiftUI

/// Ekran domykający przewodnik — przejście z „oto co potrafimy" do „teraz
/// Wasza kolej".
///
/// Każdy wiersz to para: co podajesz → po co nam to. Kreator pyta o wzrost,
/// wagę i alergeny zaraz po pierwszym uruchomieniu, więc powód musi paść
/// zanim padnie pytanie, a nie w polityce prywatności.
///
/// Przyciski są w `TourFooter` — stopkę składa `FeatureTourView`
/// poza animowaną treścią.
struct TourDoneView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TourPage {
            VStack(alignment: .leading, spacing: 0) {
                // Ten sam chip, co „Znajdziesz w…" na krokach — stoi w tym
                // samym miejscu, więc przy wjeździe tego ekranu nie zmienia
                // ani wysokości, ani tła.
                TourChip(
                    icon: "clock",
                    accent: SCPalette.terracotta,
                    label: Text("Zostały dwie minuty")
                        .foregroundStyle(Color.scLabel(scheme))
                        .fontWeight(.semibold)
                )
                .padding(.bottom, 14)

                Text("Znasz już nas.\nTeraz my poznajmy Ciebie.")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .lineSpacing(3)
                    .foregroundStyle(Color.scLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)

                Text("Kilka pytań — każde ma konkretny powód:")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.scMuted(scheme))
                    .padding(.bottom, 12)

                VStack(spacing: 0) {
                    TourFeatureRow(
                        icon: "slider.horizontal.3",
                        tint: SCPalette.terracotta,
                        title: "Wzrost, waga, wiek i aktywność",
                        subtitle: "Liczymy dzienne zapotrzebowanie i rozkładamy je na posiłki",
                        alignsTop: true
                    )
                    TourFeatureRow(
                        icon: "leaf",
                        tint: SCPalette.sage,
                        title: "Alergeny",
                        subtitle: "Przepisy z tymi składnikami nie pokażą się nigdzie — ani w planie, ani na liście zakupów",
                        alignsTop: true
                    )
                    TourFeatureRow(
                        icon: "fork.knife",
                        tint: SCPalette.indigo,
                        title: "Dieta i cel kaloryczny",
                        subtitle: "Zawężamy katalog i pilnujemy, żeby dzień się spinał: wege, bez laktozy, bez wieprzowiny",
                        alignsTop: true
                    )
                    TourFeatureRow(
                        icon: "clock",
                        tint: SCPalette.butter,
                        title: "Posiłki i ich pory",
                        subtitle: "Dobieramy liczbę dań i takie przepisy, które zdążycie ugotować",
                        alignsTop: true
                    )
                    TourFeatureRow(
                        icon: "house",
                        tint: SCPalette.terracottaDeep,
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
                .foregroundStyle(Color.scMuted(scheme))
            }
            .padding(.horizontal, TourLayout.horizontal)
        }
    }
}

#Preview("Dark") {
    ZStack {
        TourBackground(scheme: .dark)
        VStack(spacing: 0) {
            TourDoneView()
            TourFooter(kind: .done, onBack: {}, onPrimary: {}, onSkip: {})
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Light") {
    ZStack {
        TourBackground(scheme: .light)
        VStack(spacing: 0) {
            TourDoneView()
            TourFooter(kind: .done, onBack: {}, onPrimary: {}, onSkip: {})
        }
    }
    .preferredColorScheme(.light)
}
