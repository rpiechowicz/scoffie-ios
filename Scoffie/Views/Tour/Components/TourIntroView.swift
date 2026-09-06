import SwiftUI

/// Krok zerowy przewodnika — obietnica produktu, zanim padnie pierwsze
/// pytanie. Typograficzny, bez zdjęcia: zdjęcia zaczynają się od kroku 1
/// i gdyby jedno stało już tutaj, cała reszta straciłaby efekt wejścia.
///
/// Przyciski i „Pomiń" są w `TourFooter` — stopkę składa `FeatureTourView`
/// poza animowaną treścią.
struct TourIntroView: View {
    @Environment(\.colorScheme) private var scheme

    private static let logoSize: CGFloat = 56

    var body: some View {
        TourPage {
            VStack(alignment: .leading, spacing: 0) {
                // Promień 22% boku to ten sam narożnik, który logo rysuje
                // sobie samo (`SCScoffieMark.drawBackground`) — przy
                // innej wartości maska podcinałaby własne tło znaku.
                SCScoffieMark(size: Self.logoSize)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: Self.logoSize * 0.22,
                            style: .continuous
                        )
                    )
                    .shadow(color: SCPalette.terracotta.opacity(0.28), radius: 18, x: 0, y: 10)
                    .padding(.bottom, 18)

                Text("Plan posiłków dla całego domu")
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(SCPalette.terracotta)
                    .padding(.bottom, 10)

                Text("Witaj w\nScoffie")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.6)
                    .lineSpacing(3)
                    .foregroundStyle(Color.scLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)

                Text("Układacie tydzień raz — resztą zajmuje się aplikacja. Lista zakupów powstaje sama z planu, a przepisy omijają to, czego nie jecie.")
                    .font(.system(size: 15.5))
                    .lineSpacing(3.5)
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 22)

                VStack(spacing: 0) {
                    TourFeatureRow(
                        icon: MenuConstans.Plan.icon,
                        tint: SCPalette.terracotta,
                        title: "Plan na cały tydzień",
                        subtitle: "Ułóżcie menu raz — widzi je cały dom"
                    )
                    TourFeatureRow(
                        icon: MenuConstans.Products.icon,
                        tint: SCPalette.sage,
                        title: "Lista zakupów z planu",
                        subtitle: "Składa się sama, po działach sklepu"
                    )
                    TourFeatureRow(
                        icon: MenuConstans.Recipes.icon,
                        tint: SCPalette.indigo,
                        title: "Przepisy krok po kroku",
                        subtitle: "Z czasem gotowania i listą składników"
                    )
                    TourFeatureRow(
                        icon: MenuConstans.Assistant.icon,
                        tint: SCPalette.terracottaDeep,
                        title: "Asystent od pomysłów",
                        subtitle: "Zapytaj, a ułoży posiłek i doda do planu"
                    )
                    TourFeatureRow(
                        icon: "leaf",
                        tint: SCPalette.sage,
                        title: "Pod Waszą dietę i alergeny",
                        subtitle: "Bez składników, których nie jecie",
                        isLast: true
                    )
                }
            }
            .padding(.horizontal, TourLayout.horizontal)
        }
    }
}

#Preview("Dark") {
    ZStack {
        TourBackground(scheme: .dark)
        VStack(spacing: 0) {
            TourIntroView()
            TourFooter(kind: .intro, onBack: {}, onPrimary: {}, onSkip: {})
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Light") {
    ZStack {
        TourBackground(scheme: .light)
        VStack(spacing: 0) {
            TourIntroView()
            TourFooter(kind: .intro, onBack: {}, onPrimary: {}, onSkip: {})
        }
    }
    .preferredColorScheme(.light)
}
