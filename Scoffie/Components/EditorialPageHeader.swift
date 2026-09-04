import SwiftUI

// Wspólny nagłówek ekranu (v2).
//
// Wzorcem jest Przepisy: sam tytuł — 32pt heavy, tracking -0.5, kolor label,
// wyrównany do lewej — bez eyebrow („№ X · …"), bez drugiej linii i bez
// zmiennego, dziennego copy. Każda zakładka używa tego samego komponentu i
// tych samych marginesów (`WMPageMetrics`), więc tytuły siadają w tym samym
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
            Text(title)
                .font(.system(size: 32, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(Color.wmLabel(scheme))
                .lineLimit(1)
                // Skalowanie zostaje wyłącznie jako zabezpieczenie na bardzo
                // wąskie ekrany. Przy zwykłym układzie nie odpala się, bo
                // tytuł dostaje pierwszeństwo, a akcje obok są na tyle
                // wąskie, że mieści się pełne 32 pt.
                //
                // `fixedSize` tu NIE działa: HStack układa wtedy dzieci przy
                // ich idealnych szerokościach i cały wiersz wychodzi poza
                // kontener, ciągnąc za sobą marginesy całej strony.
                .minimumScaleFactor(0.9)
                .layoutPriority(1)

            Spacer(minLength: 8)

            // Akcje też biorą swój naturalny rozmiar. Sam `layoutPriority`
            // na tytule przechylał podział za mocno w drugą stronę —
            // pigułka gospodarstwa gubiła nazwę i zostawała z samą ikoną
            // i strzałką.
            trailing()
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
enum WMPageMetrics {
    static let top: CGFloat = 78
    static let horizontal: CGFloat = 20
    static let bottom: CGFloat = 40
}

#Preview("Sam tytuł") {
    EditorialPageHeader("Przepisy")
        .padding(.horizontal, WMPageMetrics.horizontal)
}

#Preview("Z akcjami") {
    EditorialPageHeader(title: "Plan tygodnia") {
        EditorialIconButton(icon: "ellipsis", highlighted: false) {}
    }
    .padding(.horizontal, WMPageMetrics.horizontal)
}
