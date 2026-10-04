import SwiftUI

/// Licznik przypięty do rogu okrągłej akcji nagłówka.
///
/// Powstał dla koszyka w nagłówku Planu tygodnia: lista zakupów jest teraz
/// arkuszem, a nie zakładką, więc bez plakietki nic na ekranie nie mówi, że
/// coś w niej jeszcze zostało — trzeba było ją otworzyć, żeby się dowiedzieć.
/// Plakietka odpowiada na to jedną liczbą: ile produktów czeka na kupienie.
///
/// Bez obwódki (4.10.2026): krążki pod spodem są szkłem bez własnej obwódki,
/// a kremowy pierścień w kolorze płótna rysował wokół plakietki jasną
/// obwódkę, której nic wokół nie miało. Od szkła odcina ją kolor i cień.
struct SCCountBadge: View {
    let count: Int
    var color: Color = SCPalette.terracotta

    /// Trzycyfrowe liczniki rozpychają pigułkę szerzej niż sama akcja pod
    /// spodem — „99+” mówi to samo, co „137”, w tym samym miejscu.
    private var label: String { count > 99 ? "99+" : "\(count)" }

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, count > 9 ? 5 : 0)
            .frame(minWidth: 17, minHeight: 17)
            .background(
                Capsule(style: .continuous)
                    .fill(color)
                    .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
            )
            .accessibilityHidden(true)
    }
}

extension View {
    /// Przypina licznik do prawego górnego rogu akcji. Zero chowa plakietkę.
    ///
    /// Wjazd i zjazd są sprężyste, a zmiana samej liczby przenika — plakietka
    /// zmienia się w tej samej chwili, w której użytkownik odhacza produkt
    /// w arkuszu nad spodem, więc twardy przeskok byłby widoczny.
    func scCountBadge(
        _ count: Int,
        color: Color = SCPalette.terracotta,
        offset: CGSize = CGSize(width: 5, height: -4)
    ) -> some View {
        overlay(alignment: .topTrailing) {
            if count > 0 {
                SCCountBadge(count: count, color: color)
                    .offset(x: offset.width, y: offset.height)
                    // Wejście bez podskoku: plakietka pojawia się zwykle przy
                    // pierwszym wczytaniu listy, a odbicie 0,72 robiło z tego
                    // skok, który przyciągał wzrok bez powodu.
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .contentTransition(.numericText())
            }
        }
        .animation(.smooth(duration: 0.28), value: count)
    }
}

#Preview("SCCountBadge") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()

        HStack(spacing: 18) {
            EditorialIconButton(icon: "cart", size: 34, tapTarget: 44) {}
                .scCountBadge(3)
            EditorialIconButton(icon: "cart", size: 34, tapTarget: 44) {}
                .scCountBadge(19)
            EditorialIconButton(icon: "cart", size: 34, tapTarget: 44) {}
                .scCountBadge(137)
            EditorialIconButton(icon: "cart", size: 34, tapTarget: 44) {}
                .scCountBadge(0)
        }
    }
    .preferredColorScheme(.dark)
}
