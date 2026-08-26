import SwiftUI

/// „Jak działa gotowanie z Thermomixem" — arkusz informacyjny otwierany
/// z ekranu integracji Cookidoo (a docelowo też z ekranu przepisu).
///
/// Cztery karty odpowiadają na cztery pytania, które zadaje sobie każdy
/// przy pierwszym kontakcie z funkcją — łącznie z uczciwym „czego to NIE
/// robi": zdalnego otwarcia przepisu na ekranie TM6 nie umie nawet
/// oficjalna aplikacja Cookidoo, więc mówimy to wprost zamiast pozwolić
/// użytkownikowi czekać przy urządzeniu na cud.
struct ThermomixInfoSheet: View {
    var onClose: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            WMPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    EditorialSheetHeader(
                        eyebrow: "Integracje",
                        title: "Gotuj z Thermomixem",
                        onClose: onClose
                    )
                    .padding(.bottom, 4)

                    infoCard(
                        icon: "fork.knife.circle.fill",
                        tint: WMPalette.terracotta,
                        title: "Co to jest?",
                        body: "Część przepisów w Weekly Meals ma swój odpowiednik w Cookidoo — oficjalnej bibliotece przepisów Thermomixa. Takie przepisy poznasz po znaczku Thermomix."
                    )

                    infoCard(
                        icon: "paperplane.circle.fill",
                        tint: WMPalette.sage,
                        title: "Jak to działa?",
                        body: "Gdy stukniesz \u{201E}Gotuj w Thermomixie\u{201D}, przepis trafi do planu \u{201E}Mój tydzień\u{201D} w Cookidoo na dzisiejszy dzień. Thermomix sam pobierze go z chmury — znajdziesz go na ekranie urządzenia, gotowego do rozpoczęcia gotowania."
                    )

                    infoCard(
                        icon: "hand.raised.circle.fill",
                        tint: WMPalette.indigo,
                        title: "Czego się spodziewać?",
                        body: "Przepis czeka w Twoim tygodniu na Thermomixie — nie otworzy się sam na jego ekranie. Tego nie potrafi nawet oficjalna aplikacja Cookidoo: gotowanie zawsze zatwierdzasz na urządzeniu."
                    )

                    infoCard(
                        icon: "lock.circle.fill",
                        tint: WMPalette.butter,
                        title: "Bezpieczeństwo",
                        body: "Dane logowania do Cookidoo są przechowywane na naszym serwerze w postaci zaszyfrowanej i używane wyłącznie do połączenia z Cookidoo. Nigdy nie wracają do aplikacji — w każdej chwili możesz się rozłączyć."
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func infoCard(icon: String, tint: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(Color.wmLabel(scheme))

                Text(body)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
