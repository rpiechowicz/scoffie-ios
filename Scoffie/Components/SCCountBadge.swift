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
            .font(.sc(size: 10.5, weight: .heavy))
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
        modifier(SCCountBadgeModifier(count: count, color: color, offset: offset))
    }
}

/// Plakietka STOI w drzewie zawsze (Rafał 4.10.2026: „jak się pojawia i znika
/// badge zakupów, psuje się animacja”) — jak plakietka na wyspie Gotuj.
/// Pojawienie i zniknięcie = skala i krycie w miejscu, przy znikaniu trzyma
/// ostatnią liczbę, a sama liczba roluje się `SCMotion.textRoll`, jak każda
/// cyfra w aplikacji. Animacje są przypięte do PLAKIETKI — dawne
/// `.animation(value: count)` na całym przycisku animowało przy każdej
/// zmianie liczby także krążek pod spodem, a wstawiany widok przeskakiwał.
private struct SCCountBadgeModifier: ViewModifier {
    let count: Int
    let color: Color
    let offset: CGSize

    /// Ostatnia dodatnia liczba — z nią plakietka gaśnie, zamiast pokazać 0.
    @State private var shownCount: Int

    init(count: Int, color: Color, offset: CGSize) {
        self.count = count
        self.color = color
        self.offset = offset
        _shownCount = State(initialValue: max(count, 1))
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                SCCountBadge(count: shownCount, color: color)
                    .contentTransition(.numericText(value: Double(shownCount)))
                    .animation(SCMotion.textRoll, value: shownCount)
                    .scaleEffect(count > 0 ? 1 : 0.3)
                    .opacity(count > 0 ? 1 : 0)
                    .animation(.smooth(duration: 0.28), value: count > 0)
                    .offset(x: offset.width, y: offset.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onChange(of: count) { _, new in
                if new > 0 { shownCount = new }
            }
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
