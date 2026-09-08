import SwiftUI

// Jedna alejka sklepu na Zakupach v2 — nagłówek z ikoną i licznikiem, pod nim
// wiersze produktów. Źródło: canvas claude.ai → „Weekly Meals - Zakupy v2.html”
// (`components/shop-v2-final.jsx` → `ShopFinalHead`).
//
// Zniknęły: folio 44 pt, karta z obwódką i pręcik postępu przy nagłówku.
// Postęp alejki mówi teraz JEDEN pasek na górze ekranu, podzielony na segmenty
// w kolorach działów — a nie szesnaście osobnych pręcików, z których każdy
// pokazywał ułamek czegoś innego. Zostaje sam eyebrow w kolorze działu i to,
// czego naprawdę się szuka w sklepie: „3 z 8”.
//
// Nagłówek zwija sekcję. Alejka kupiona w całości zwija się sama — decyzję
// podejmuje ekran (`ProductsView`), bo tylko on widzi, czy to właśnie odhaczony
// ostatni produkt ją domknął, czy użytkownik rozwinął ją potem ręcznie.
struct ShoppingAisleSection: View {
    /// Czym jest ta sekcja w danym momencie ekranu.
    enum Mode {
        /// Pełna lista: zwijana, kupione spadają na dół, znaczniki „Dziś”.
        case list
        /// Filtr „Na dziś”: bez zwijania i bez znaczników, licznik mówi,
        /// ile produktów z tej alejki wchodzi w dzisiejsze dania.
        case today
        /// Podgląd zamkniętej listy z historii — wygląda tak samo, nie klika.
        case readOnly
    }

    let department: String
    let items: [ShoppingItem]
    var mode: Mode = .list
    var isCollapsed: Bool = false
    var disablesTaps: Bool = false
    /// Dania pod nazwą produktu. Zwraca `nil`, gdy nie ma czego pokazać.
    var dishSummary: (ShoppingItem) -> String? = { _ in nil }
    var isTodayItem: (ShoppingItem) -> Bool = { _ in false }
    var onToggleSection: () -> Void = {}
    var onToggleItem: (ShoppingItem) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme

    private var accent: Color { ProductConstants.departmentColor(for: department) }
    private var icon: String { ProductConstants.departmentIcon(for: department) }

    private var boughtCount: Int { items.filter(\.isChecked).count }
    private var isComplete: Bool { !items.isEmpty && boughtCount == items.count }
    private var isCollapsible: Bool { mode == .list }
    private var showsRows: Bool { !isCollapsible || !isCollapsed }

    /// Kupione spadają na dół alejki — to, co zostało do wzięcia, stoi zawsze
    /// pod nagłówkiem. `enumerated` na wejściu trzyma kolejność stabilną:
    /// bez niej dwa produkty odhaczone w tej samej klatce potrafiły się
    /// zamienić miejscami przy każdym przerysowaniu.
    private var orderedItems: [ShoppingItem] {
        guard mode == .list else { return items }
        return items
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isChecked != rhs.element.isChecked {
                    return !lhs.element.isChecked
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Zmienia się dokładnie wtedy, gdy wiersze mają się przestawić — i tylko
    /// na tę zmianę wieszamy animację przenoszenia.
    private var orderSignature: String {
        orderedItems.map(\.productKey).joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if showsRows {
                rows
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -8)),
                            removal: .opacity
                        )
                    )
            } else {
                // Zwinięta sekcja zostawia po sobie kreskę, nie pustkę —
                // inaczej dwa nagłówki pod rząd czytały się jak jeden blok.
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    .padding(.top, 8)
            }
        }
        .animation(.smooth(duration: 0.28), value: isCollapsed)
    }

    // MARK: - Nagłówek

    private var header: some View {
        Button(action: { if isCollapsible { onToggleSection() } }) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)

                Text(department.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    // Nazwy działów są z góry znane i najdłuższa („CHEMIA
                    // I GOSPODARSTWO”) mieści się w wierszu; skala 0,8 to
                    // zabezpieczenie na duże czcionki systemowe, nie plan A.
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                counter

                if isCollapsible {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.scFaint(scheme))
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                        .padding(.leading, 2)
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isCollapsible)
        .accessibilityLabel(headerAccessibilityLabel)
        .accessibilityHint(isCollapsible ? (isCollapsed ? "Stuknij, aby rozwinąć" : "Stuknij, aby zwinąć") : "")
    }

    @ViewBuilder
    private var counter: some View {
        switch mode {
        case .today:
            Text("\(items.count) na dziś")
                .font(.system(size: 12.5, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(Color.scMuted(scheme))
                .lineLimit(1)
                .fixedSize()

        case .list, .readOnly:
            if isComplete {
                HStack(spacing: 4) {
                    Text("Kupione")
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                }
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(SCPalette.sage)
                .lineLimit(1)
                .fixedSize()
                .transition(.opacity)
            } else {
                Text("\(boughtCount) z \(items.count)")
                    .font(.system(size: 12.5, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.opacity)
            }
        }
    }

    private var headerAccessibilityLabel: Text {
        switch mode {
        case .today:
            return Text("\(department), \(items.count) na dziś")
        case .list, .readOnly:
            return Text("\(department), \(boughtCount) z \(items.count) kupione")
        }
    }

    // MARK: - Wiersze

    private var rows: some View {
        let ordered = orderedItems

        return VStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.element.productKey) { index, item in
                ShoppingProductRow(
                    name: item.name,
                    amount: item.displayAmount,
                    dishes: dishSummary(item),
                    bought: item.isChecked,
                    showsTodayTag: mode == .list && isTodayItem(item),
                    isLast: index == ordered.count - 1,
                    isDisabled: disablesTaps,
                    isReadOnly: mode == .readOnly,
                    onToggle: { onToggleItem(item) }
                )
            }
        }
        .animation(.snappy(duration: 0.34), value: orderSignature)
    }
}
