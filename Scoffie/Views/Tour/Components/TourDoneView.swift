import SwiftUI

/// Ekran domykający przewodnik — przejście z „oto co potrafimy" do „teraz
/// Wasza kolej".
///
/// Każdy wiersz to para: co podajesz → po co nam to. Kreator pyta o wzrost,
/// wagę i alergeny zaraz po pierwszym uruchomieniu, więc powód musi paść
/// zanim padnie pytanie, a nie w polityce prywatności. Od 23.09.2026 powód
/// mieści się w kilku słowach — dawne podpisy szły na dwie–trzy linie.
///
/// Przyciski są w stopce (`SCStepFooter`), którą składa `FeatureTourView`
/// poza animowaną treścią.
struct TourDoneView: View {
    @Environment(\.colorScheme) private var scheme

    private let features: [SCStepFeature] = [
        SCStepFeature(icon: "figure.walk", accent: SCPalette.terracotta, title: "Wzrost, waga, wiek i aktywność", subtitle: "Z nich liczymy dzienny cel"),
        SCStepFeature(icon: "leaf.fill", accent: SCPalette.sage, title: "Dieta i alergeny", subtitle: "Dania z alergenem znikają z planu i zakupów"),
        SCStepFeature(icon: "clock.fill", accent: SCPalette.indigo, title: "Posiłki w ciągu dnia", subtitle: "Tyle dań dostanie każdy dzień"),
        SCStepFeature(icon: "house.fill", accent: SCPalette.terracottaDeep, title: "Gospodarstwo", subtitle: "Wspólny plan i lista zakupów"),
    ]

    var body: some View {
        TourPage {
            VStack(alignment: .leading, spacing: 0) {
                // Nagłówek jak na krokach: eyebrow w kolorze, tytuł, opis.
                // Kafelek z zegarem stoi tam, gdzie powitanie ma logo.
                SCStepHeader(
                    icon: "clock.fill",
                    eyebrow: "Zostały dwie minuty",
                    title: "Znasz już nas.\nTeraz my poznajmy Ciebie.",
                    subtitle: "Kilka krótkich pytań, żeby plan, przepisy i kalorie od pierwszego dnia pasowały do Ciebie — a nie do „przeciętnego człowieka”."
                )
                .padding(.bottom, 22)

                SCStepFeatureCard(features: features)
                    .padding(.bottom, 14)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("Zmienisz to w każdej chwili w Ustawieniach.")
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color.scFaint(scheme))
                .padding(.horizontal, 6)
            }
            .padding(.horizontal, TourLayout.horizontal)
        }
    }
}

#Preview("Dark") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()
        VStack(spacing: 0) {
            TourDoneView()
            SCStepFooter(slot: .empty, showsBack: true, onBack: {}, primaryTitle: "Opowiedz nam o sobie", onPrimary: {})
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Light") {
    ZStack {
        SCPageBackground(scheme: .light).ignoresSafeArea()
        VStack(spacing: 0) {
            TourDoneView()
            SCStepFooter(slot: .empty, showsBack: true, onBack: {}, primaryTitle: "Opowiedz nam o sobie", onPrimary: {})
        }
    }
    .preferredColorScheme(.light)
}
