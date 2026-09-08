import SwiftUI

/// Licznik przypięty do rogu okrągłej akcji nagłówka.
///
/// Powstał dla koszyka w nagłówku Planu tygodnia: lista zakupów jest teraz
/// arkuszem, a nie zakładką, więc bez plakietki nic na ekranie nie mówi, że
/// coś w niej jeszcze zostało — trzeba było ją otworzyć, żeby się dowiedzieć.
/// Plakietka odpowiada na to jedną liczbą: ile produktów czeka na kupienie.
///
/// Obwódka jest w kolorze płótna, nie przezroczysta: plakietka wisi na
/// krawędzi pigułki i bez odcięcia zlewała się z jej obwódką w jedną plamę.
struct SCCountBadge: View {
    let count: Int
    var color: Color = SCPalette.terracotta
    /// Kolor obwódki odcinającej plakietkę od tego, na czym wisi.
    var ringColor: Color?

    @Environment(\.colorScheme) private var scheme

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
                    .shadow(color: color.opacity(0.45), radius: 4, x: 0, y: 2)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(ringColor ?? Color.scCanvas(scheme), lineWidth: 2)
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
        offset: CGSize = CGSize(width: 6, height: -5)
    ) -> some View {
        overlay(alignment: .topTrailing) {
            if count > 0 {
                SCCountBadge(count: count, color: color)
                    .offset(x: offset.width, y: offset.height)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .contentTransition(.numericText())
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: count)
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
