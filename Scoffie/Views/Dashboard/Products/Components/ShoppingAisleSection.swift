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

    /// Zmierzona wysokość rozwiniętych wierszy — z niej jedzie roleta.
    @State private var rowsHeight: CGFloat = 0

    private var accent: Color { ProductConstants.departmentColor(for: department) }
    private var icon: String { ProductConstants.departmentIcon(for: department) }

    private var boughtCount: Int { items.filter(\.isChecked).count }
    private var isComplete: Bool { !items.isEmpty && boughtCount == items.count }
    private var isCollapsible: Bool { mode == .list }

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

            if isCollapsible {
                blind
                collapsedRule
            } else {
                rows
            }
        }
    }

    /// Kreska domykająca zwiniętą alejkę.
    ///
    /// Nie pojawia się i nie znika — rośnie z zera razem z roletą i w tej samej
    /// transakcji. Element wchodzący tranzycją musiałby najpierw dostać miejsce,
    /// a to jest dokładnie ten skok, którego roleta się pozbyła.
    ///
    /// Stoi POZA pomiarem rolety: wliczona w niego doliczałaby się do wysokości
    /// rozwiniętej sekcji i zostawiała pod ostatnim wierszem dziewięć pustych
    /// punktów, a przy zwiniętej (wysokość 0) i tak nie byłoby jej widać.
    private var collapsedRule: some View {
        Rectangle()
            .fill(Color.scRule(scheme))
            .frame(height: isCollapsed ? 1 : 0)
            .padding(.top, isCollapsed ? 8 : 0)
            .opacity(isCollapsed ? 1 : 0)
    }

    // MARK: - Roleta
    //
    // Zwijanie NIE jest wstawianiem i usuwaniem wierszy z układu.
    //
    // Tak było wcześniej — `if isCollapsed` z tranzycją — i widać było, gdzie
    // ten pomysł się łamie: wiersz usunięty tranzycją zostaje w układzie na
    // czas SWOJEGO zniknięcia, więc najpierw robiła się pusta przestrzeń
    // wielkości całej sekcji, a dopiero potem reszta listy jechała w górę.
    // Dwie animacje pod rząd zamiast jednej.
    //
    // Roleta trzyma jedną liczbę: wysokość. Wiersze stoją nieruchomo, przypięte
    // do góry, a przycięta ramka zjeżdża po nich jak żaluzja — to, co zostaje
    // pod spodem, przesuwa się dokładnie w tym samym tempie i w tej samej
    // chwili, bo to jest ta sama zmiana układu, nie druga z kolei.
    //
    // `fixedSize` w pionie jest tu warunkiem działania: bez niego ramka o zerowej
    // wysokości ściskałaby wiersze do zera, pomiar w tle oddawałby zero i roleta
    // nie miałaby dokąd wracać.
    private var blind: some View {
        rows
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.size.height, initial: true) { _, height in
                            // Próg 0,5 pt ucina drgania z zaokrągleń pikseli —
                            // bez niego pomiar potrafi krążyć między dwiema
                            // wartościami przy każdym przerysowaniu.
                            if abs(height - rowsHeight) > 0.5 { rowsHeight = height }
                        }
                }
            }
            .frame(height: blindHeight, alignment: .top)
            .clipped()
            // Przycięcie nie obcina dotknięć — bez tego zwinięta alejka
            // dalej łapała stuknięcia w niewidoczne wiersze.
            .allowsHitTesting(!isCollapsed)
            .accessibilityHidden(isCollapsed)
    }

    /// `nil` = wysokość naturalna. Zwrócone przy pierwszym rysowaniu, zanim
    /// pomiar wróci — inaczej sekcja mignęłaby pusta.
    private var blindHeight: CGFloat? {
        if isCollapsed { return 0 }
        return rowsHeight > 0 ? rowsHeight : nil
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
                    // Licznik zmienia się przy KAŻDYM odhaczeniu, czyli poza
                    // transakcją zwijania — własna animacja jest tu po to,
                    // żeby cyfra przewinęła się zamiast mrugnąć.
                    .animation(.easeInOut(duration: 0.22), value: boughtCount)

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
        .buttonStyle(PlanPressStyle(scale: 0.98))
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
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                Text("\(boughtCount) z \(items.count)")
                    .font(.system(size: 12.5, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
                    .fixedSize()
                    // Cyfra przewija się w miejscu, zamiast podmieniać się
                    // skokiem — przy szybkim odhaczaniu widać, że licznik
                    // faktycznie liczy, a nie miga.
                    .contentTransition(.numericText())
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
                    accent: accent,
                    showsTodayTag: mode == .list && isTodayItem(item),
                    isLast: index == ordered.count - 1,
                    isDisabled: disablesTaps,
                    isReadOnly: mode == .readOnly,
                    onToggle: { onToggleItem(item) }
                )
            }
        }
        // Przeniesienie kupionego na dół alejki czeka 0,2 s. Bez tej zwłoki
        // wiersz uciekał spod palca w tej samej klatce, w której zapalał się
        // ptaszek, i nie dawało się zobaczyć, CO się właściwie odhaczyło.
        .animation(.spring(response: 0.38, dampingFraction: 0.88).delay(0.2), value: orderSignature)
    }
}
