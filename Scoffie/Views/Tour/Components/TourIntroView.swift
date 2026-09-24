import SwiftUI

/// Krok zerowy przewodnika — obietnica produktu, zanim padnie pierwsze
/// pytanie. Typograficzny, bez zdjęcia: zdjęcia zaczynają się od kroku 1
/// i gdyby jedno stało już tutaj, cała reszta straciłaby efekt wejścia.
///
/// Układ: znak, nagłówek kroku (`SCStepHeader`), karta funkcji
/// (`SCStepFeatureCard`). Powitanie wprowadzenia Asystenta
/// (`AssistantIntroPages.swift`) ma ten sam znak i nagłówek, a pod nimi
/// pole z przykładami zamiast karty.
/// Przyciski i „Pomiń" są w stopce (`SCStepFooter`), którą składa
/// `WelcomeView` poza animowaną treścią.
struct TourIntroView: View {
    private static let logoSize: CGFloat = 56

    private let features: [SCStepFeature] = [
        SCStepFeature(icon: MenuConstans.Plan.icon, accent: SCPalette.terracotta, title: "Plan na cały tydzień", subtitle: "Ułóżcie menu raz — widzi je cały dom"),
        SCStepFeature(icon: MenuConstans.Products.icon, accent: SCPalette.sage, title: "Lista zakupów z planu", subtitle: "Składa się sama, po działach sklepu"),
        SCStepFeature(icon: MenuConstans.Recipes.icon, accent: SCPalette.indigo, title: "Przepisy krok po kroku", subtitle: "Z czasem gotowania i składnikami"),
        SCStepFeature(icon: MenuConstans.Assistant.icon, accent: SCPalette.terracottaDeep, title: "Asystent od pomysłów", subtitle: "Ułoży dzień albo tydzień — Ty zatwierdzasz"),
        SCStepFeature(icon: "leaf.fill", accent: SCPalette.sage, title: "Pod Waszą dietę i alergeny", subtitle: "Bez składników, których nie jecie"),
    ]

    var body: some View {
        TourPage {
            VStack(alignment: .leading, spacing: 0) {
                // Promień 22% boku to ten sam narożnik, który logo rysuje
                // sobie samo (`SCScoffieMark.drawBackground`) — przy
                // innej wartości maska podcinałaby własne tło znaku.
                // Bez poświaty pod spodem: przepływ stoi na kartach bez cienia.
                SCScoffieMark(size: Self.logoSize)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: Self.logoSize * 0.22,
                            style: .continuous
                        )
                    )
                    .padding(.bottom, 18)

                SCStepHeader(
                    eyebrow: "Plan posiłków dla całego domu",
                    title: "Witaj w Scoffie",
                    subtitle: "Scoffie pomaga zaplanować jedzenie na cały tydzień — dla Ciebie albo dla całego domu. Układacie menu raz, a lista zakupów, kalorie i przypomnienia robią się same."
                )
                .padding(.bottom, 22)

                SCStepFeatureCard(features: features)
            }
            .padding(.horizontal, TourLayout.horizontal)
        }
    }
}

#Preview("Dark") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()
        VStack(spacing: 0) {
            TourIntroView()
            SCStepFooter(slot: .link("Pomiń i przejdź do konfiguracji"), onSlotTap: {}, primaryTitle: "Poznaj aplikację", onPrimary: {})
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Light") {
    ZStack {
        SCPageBackground(scheme: .light).ignoresSafeArea()
        VStack(spacing: 0) {
            TourIntroView()
            SCStepFooter(slot: .link("Pomiń i przejdź do konfiguracji"), onSlotTap: {}, primaryTitle: "Poznaj aplikację", onPrimary: {})
        }
    }
    .preferredColorScheme(.light)
}
