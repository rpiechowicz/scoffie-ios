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
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 32, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(Color.wmLabel(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // Tytuł wymiaruje się pierwszy. Bez tego HStack dzielił
                // szerokość po równo i „Plan tygodnia" — jedyny nagłówek
                // z akcjami obok — zjeżdżał przez `minimumScaleFactor` do
                // mniejszego stopnia niż „Przepisy" czy „Ustawienia".
                // Skalowanie zostaje jako zabezpieczenie na naprawdę wąskie
                // ekrany, ale nie odpala się już przy zwykłym układzie.
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
