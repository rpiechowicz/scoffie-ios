import SwiftUI

// Wspólny nagłówek ekranu (v2).
//
// Wzorcem jest Przepisy: sam tytuł — 32pt heavy, tracking -0.5, kolor label,
// wyrównany do lewej — bez eyebrow („№ X · …"), bez drugiej linii i bez
// zmiennego, dziennego copy. Każda zakładka używa tego samego komponentu i
// tych samych marginesów (`SCPageMetrics`), więc tytuły siadają w tym samym
// miejscu przy przełączaniu tabów.
//
// Akcje po prawej (np. „…" i pigułka profilu na Planie) wchodzą przez
// `trailing`. Treść pod tytułem (np. pigułka wyszukiwarki na Przepisach)
// zostaje po stronie ekranu — nagłówek to tylko wiersz z tytułem.
struct EditorialPageHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Tytuł schodzi ze stopnia pisma, zamiast się urywać.
            //
            // `lineLimit(1)` + `minimumScaleFactor` nie wystarczały: Text
            // najpierw dostaje węższą propozycję, a dopiero potem skaluje,
            // więc „Plan tygodnia" obok trzech akcji kończyło jako „Plan
            // tygodn…". `ViewThatFits` mierzy NATURALNĄ szerokość każdego
            // wariantu i bierze największy, który wchodzi w resztę wiersza —
            // 32 pt tam, gdzie akcji nie ma (Przepisy, Produkty, Ustawienia),
            // 28 pt na Planie z trzema akcjami. Skalowanie zostaje na
            // ostatnim wariancie jako zabezpieczenie na bardzo wąskie ekrany
            // i duże czcionki systemowe.
            //
            // `fixedSize` tu NIE działa: HStack układa wtedy dzieci przy
            // ich idealnych szerokościach i cały wiersz wychodzi poza
            // kontener, ciągnąc za sobą marginesy całej strony.
            ViewThatFits(in: .horizontal) {
                titleText(size: 32)
                titleText(size: 28)
                titleText(size: 25, allowsScaling: true)
            }

            Spacer(minLength: 8)

            // Akcje biorą swój naturalny rozmiar — to od nich odejmuje się
            // szerokość dostępną dla tytułu, a nie odwrotnie.
            trailing()
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func titleText(size: CGFloat, allowsScaling: Bool = false) -> some View {
        Text(title)
            .font(.system(size: size, weight: .heavy))
            .tracking(-0.5)
            .foregroundStyle(Color.scLabel(scheme))
            .lineLimit(1)
            .minimumScaleFactor(allowsScaling ? 0.75 : 1)
            // VoiceOver ogłasza tytuł zakładki jako nagłówek — na każdej
            // zakładce tak samo, bo każda stoi na tym komponencie.
            .accessibilityAddTraits(.isHeader)
    }
}

extension EditorialPageHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

// Marginesy strony wspólne dla wszystkich zakładek v2. `top` odsuwa tytuł od
// Dynamic Island — wartość przeniesiona z Przepisów / Kalendarza.
//
// UWAGA, warunek kontraktu: `top` mierzy się od KRAWĘDZI EKRANU, nie od safe
// area. Kontener, który tego paddingu używa (ScrollView albo VStack ze stałym
// nagłówkiem), MUSI mieć `.ignoresSafeArea(.container, edges: .top)` — inaczej
// górny inset liczy się dwa razy i tytuł spada o 47–59 pt, zależnie od
// urządzenia. Tak wpadł ekran asystenta, dodany jako ostatni. Wyjątek: ekran
// pokazywany jako arkusz podaje własny, mniejszy `topPadding` (patrz
// `ProductsView`), bo tam mierzy się od uchwytu arkusza, nie od Dynamic Island.
enum SCPageMetrics {
    static let top: CGFloat = 78
    static let horizontal: CGFloat = 20
    static let bottom: CGFloat = 40
}

#Preview("Sam tytuł") {
    EditorialPageHeader("Przepisy")
        .padding(.horizontal, SCPageMetrics.horizontal)
}

#Preview("Z akcjami") {
    EditorialPageHeader(title: "Plan tygodnia") {
        EditorialIconButton(icon: "ellipsis", highlighted: false) {}
    }
    .padding(.horizontal, SCPageMetrics.horizontal)
}
