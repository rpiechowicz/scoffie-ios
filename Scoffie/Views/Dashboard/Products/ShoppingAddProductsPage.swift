import SwiftUI

// „Dodaj produkty” — trzy strony wpychane w stos arkusza Zakupów
// (13.10.2026, artefakt „Własne produkty w Zakupach”, ekrany 2–5):
//
// - `ShoppingAddProductsPage` — z „+” w stopce Zakupów: pole szukania,
//   „Ostatnio dodawane” i działy sklepu; od drugiej litery wyniki
//   z katalogu i własnych nazw domu, a na końcu „Dodaj jako własny produkt”;
// - `ShoppingAddDepartmentPage` — stuknięty dział: jego produkty od A do Ż;
// - `ShoppingCustomProductPage` — własna nazwa: dział i ilość.
//
// Push, nie arkusz na arkuszu (CLAUDE.md, „Prościej, jak od Apple”: najwyżej
// jeden arkusz, dalszy krok = push z systemowym „wstecz”) — tak samo jak
// historia Zakupów. Makieta pokazywała arkusz nałożony na Zakupy; układ
// strony jest ten sam, zmienił się tylko sposób wejścia.
//
// Wybór (`ShoppingAddSelection`) jest wspólny dla wszystkich trzech stron:
// można zebrać mleko z szukania, płyn z „Chemii” i własną karmę dla kota,
// a „Dodaj 3 produkty” w stopce zapisuje je naraz — jedna zmiana listy
// i jedno powiadomienie dla domu.

// MARK: - Dodaj produkty

struct ShoppingAddProductsPage: View {
    let selection: ShoppingAddSelection
    /// „12–18 paź” — lista, do której dopisujemy (oglądany tydzień).
    let weekLabel: String
    let isAdding: Bool
    let onOpenDepartment: (String) -> Void
    let onOpenCustom: (String) -> Void
    let onCommit: () -> Void

    @Environment(\.shoppingListStore) private var store
    @Environment(\.colorScheme) private var scheme

    @State private var query = ""
    @FocusState private var isFocused: Bool

    private var foldedQuery: String {
        IngredientSearch.fold(query).trimmingCharacters(in: .whitespaces)
    }

    /// Wyniki od drugiej litery — jak w „Bez składników”.
    private var isSearching: Bool { foldedQuery.count >= 2 }

    private var searchPrompt: String {
        store.productCatalog.isEmpty
            ? "Szukaj produktu"
            : "Szukaj wśród \(PolishPlural.products(store.productCatalog.count))"
    }

    var body: some View {
        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        SCSearchField(
                            prompt: searchPrompt,
                            text: $query,
                            focus: $isFocused,
                            isActive: isFocused
                        )
                        .padding(.top, 6)

                        if isSearching {
                            results
                                .transition(.opacity)
                        } else {
                            start
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .containerRelativeFrame(.horizontal)
                    .animation(.smooth(duration: 0.2), value: isSearching)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                // Pod systemowym paskiem — miękka krawędź, bez kreski.
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scSheetFooter {
                    ShoppingAddFooter(selection: selection, isAdding: isAdding, onCommit: onCommit)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection.count)
        .navigationTitle("Dodaj produkty")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        // „Wstecz” i „Wyczyść” w terakocie, jak na stronach `scPushedPage`.
        .tint(SCPalette.terracotta)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ShoppingAddNavTitle(title: "Dodaj produkty", subtitle: "Lista \(weekLabel)")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Wyczyść") { selection.clear() }
                    .disabled(selection.isEmpty)
                    .accessibilityLabel("Odznacz wszystkie wybrane produkty")
            }
        }
        .task { await store.loadProductCatalog() }
    }

    // MARK: Start: ostatnio dodawane i działy

    @ViewBuilder
    private var start: some View {
        let recent = recentProducts

        if !recent.isEmpty {
            EditorialSheetSectionLabel(title: "Ostatnio dodawane")
                .padding(.top, 22)
                .padding(.bottom, 4)

            ShoppingAddCard {
                ForEach(Array(recent.enumerated()), id: \.element.id) { offset, entry in
                    pickRow(entry.product, lastAmount: entry.amount, showsRule: offset > 0)
                }
            }
        }

        EditorialSheetSectionLabel(title: "Działy")
            .padding(.top, 22)
            .padding(.bottom, 4)

        if store.productCatalog.isEmpty {
            Text("Katalog wczyta się, gdy będzie internet. Własny produkt dopiszesz od razu — wpisz jego nazwę.")
                .font(.sc(size: 13))
                .foregroundStyle(Color.scMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
        } else {
            let counts = departmentCounts
            ShoppingDepartmentGrid(departments: ShoppingDepartments.all.filter { (counts[$0] ?? 0) > 0 }) { department in
                ShoppingDepartmentTile(
                    department: department,
                    subtitle: PolishPlural.products(counts[department] ?? 0)
                ) {
                    isFocused = false
                    onOpenDepartment(department)
                }
            }
        }
    }

    /// „Ostatnio dodawane” jako produkty — z katalogu (z aliasami i masą
    /// sztuki), a gdy go nie ma albo to własna nazwa — z samego wpisu.
    private struct RecentEntry: Identifiable {
        let product: ShoppingProduct
        let amount: ShoppingAmount?
        var id: String { product.id }
    }

    private var recentProducts: [RecentEntry] {
        let catalogById = Dictionary(
            store.productCatalog.compactMap { product in product.ingredientId.map { ($0, product) } },
            uniquingKeysWith: { first, _ in first }
        )
        return store.recentProducts.prefix(6).map { recent in
            let product = recent.ingredientId.flatMap { catalogById[$0] } ?? ShoppingProduct(
                name: recent.name,
                department: recent.department,
                ingredientId: recent.ingredientId,
                pieceOnly: false,
                aliases: []
            )
            return RecentEntry(product: product, amount: ShoppingAmount.fromList(amount: recent.amount, unit: recent.unit))
        }
    }

    private var departmentCounts: [String: Int] {
        Dictionary(grouping: store.productCatalog, by: \.department).mapValues(\.count)
    }

    // MARK: Wyniki

    @ViewBuilder
    private var results: some View {
        let hits = ShoppingProductSearch.results(for: query, in: store.productSearchIndex)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let exact = hits.contains { $0.product.nameKey == ShoppingProduct.nameKey(trimmed) }

        if hits.isEmpty {
            Text("Nie ma „\(trimmed)” w katalogu.")
                .font(.sc(size: 13.5))
                .foregroundStyle(Color.scMuted(scheme))
                .padding(.horizontal, 6)
                .padding(.top, 22)
                .padding(.bottom, 10)
        } else {
            EditorialSheetSectionLabel(title: "Produkty")
                .padding(.top, 22)
                .padding(.bottom, 4)

            ShoppingAddCard {
                ForEach(Array(hits.enumerated()), id: \.element.id) { offset, hit in
                    pickRow(hit.product, highlight: hit.highlight, showsRule: offset > 0)
                }
            }
        }

        if !exact {
            ShoppingCustomProductRow(name: trimmed) {
                isFocused = false
                onOpenCustom(trimmed)
            }
            .padding(.top, hits.isEmpty ? 0 : 12)
        }
    }

    private func pickRow(
        _ product: ShoppingProduct,
        highlight: (offset: Int, length: Int)? = nil,
        lastAmount: ShoppingAmount? = nil,
        showsRule: Bool
    ) -> some View {
        ShoppingPickRowHost(
            product: product,
            selection: selection,
            highlight: highlight,
            lastAmount: lastAmount,
            showsRule: showsRule
        )
    }
}

// MARK: - Dział

struct ShoppingAddDepartmentPage: View {
    let department: String
    let selection: ShoppingAddSelection
    let isAdding: Bool
    let onCommit: () -> Void

    @Environment(\.shoppingListStore) private var store
    @Environment(\.colorScheme) private var scheme

    @State private var query = ""
    @FocusState private var isFocused: Bool

    private var products: [ShoppingProduct] {
        let all = store.productCatalog.filter { $0.department == department }
        guard IngredientSearch.fold(query).trimmingCharacters(in: .whitespaces).count >= 1 else {
            return all.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
        let index = ShoppingProductSearch.Index(all)
        return ShoppingProductSearch.results(for: query, in: index, limit: all.count).map(\.product)
    }

    var body: some View {
        let list = products

        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        SCSearchField(
                            prompt: "Szukaj w dziale \(department)",
                            text: $query,
                            focus: $isFocused,
                            isActive: isFocused
                        )
                        .padding(.top, 6)

                        EditorialSheetSectionLabel(title: query.isEmpty ? "Od A do Ż" : "Wyniki")
                            .padding(.top, 22)
                            .padding(.bottom, 4)

                        if list.isEmpty {
                            Text("W tym dziale nie ma takiego produktu.")
                                .font(.sc(size: 13.5))
                                .foregroundStyle(Color.scMuted(scheme))
                                .padding(.horizontal, 6)
                        } else {
                            ShoppingAddCard {
                                ForEach(Array(list.enumerated()), id: \.element.id) { offset, product in
                                    ShoppingPickRowHost(
                                        product: product,
                                        selection: selection,
                                        showsRule: offset > 0
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .containerRelativeFrame(.horizontal)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scSheetFooter {
                    ShoppingAddFooter(selection: selection, isAdding: isAdding, onCommit: onCommit)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection.count)
        .navigationTitle(department)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        // „Wstecz” i „Wyczyść” w terakocie, jak na stronach `scPushedPage`.
        .tint(SCPalette.terracotta)
    }
}

// MARK: - Własny produkt

struct ShoppingCustomProductPage: View {
    let initialName: String
    let selection: ShoppingAddSelection
    /// Wraca do poprzedniej strony (wybór już zawiera produkt).
    let onDone: () -> Void

    @Environment(\.shoppingListStore) private var store
    @Environment(\.colorScheme) private var scheme

    @State private var name = ""
    @State private var department = ProductConstants.Department.other
    @State private var isGuessed = false
    @State private var amount: ShoppingAmount?
    @State private var didSeed = false
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Nazwa, która JEST w katalogu, idzie jako produkt z katalogu — tak
    /// samo postąpiłby serwer, a tu widać to od razu (dział, sztuki).
    private var catalogMatch: ShoppingProduct? {
        let key = ShoppingProduct.nameKey(trimmedName)
        return store.productCatalog.first { $0.nameKey == key }
    }

    /// Wiersz tego produktu, który już stoi na liście — wtedy ilość idzie
    /// w jego jednostce, jak w szukaniu (bez drugiego wiersza „Mleko (szt)”).
    private var listItem: ShoppingItem? {
        let key = ShoppingProduct.nameKey(trimmedName)
        guard !key.isEmpty else { return nil }
        return store.items.first { $0.productNameKey == key }
    }

    private var allowedUnits: [ShoppingAmountUnit] {
        ShoppingAmountUnit.allowed(listUnit: listItem?.listUnit, pieceOnly: catalogMatch?.pieceOnly ?? false)
    }

    var body: some View {
        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        EditorialSheetSectionLabel(title: "Nazwa")
                            .padding(.top, 10)
                            .padding(.bottom, 4)

                        ShoppingAddCard {
                            HStack(spacing: 12) {
                                RecipeExclusionDepartmentIcon(department: department, size: 32)

                                TextField("Np. karma dla kota", text: $name)
                                    .font(.sc(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.scLabel(scheme))
                                    .tint(SCPalette.terracotta)
                                    .focused($isNameFocused)
                                    .submitLabel(.done)
                                    .textInputAutocapitalization(.sentences)
                                    .padding(.horizontal, 12)
                                    .frame(height: 42)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.scChipBg(scheme))
                                    )
                                    .onChange(of: name) { _, newValue in
                                        if newValue.count > 60 { name = String(newValue.prefix(60)) }
                                    }
                            }
                            .padding(10)
                        }

                        if let match = catalogMatch {
                            Label("Jest w katalogu — dopiszemy „\(match.name)” z działu \(match.department).", systemImage: "checkmark.seal.fill")
                                .font(.sc(size: 12.5))
                                .foregroundStyle(Color.scMuted(scheme))
                                .padding(.horizontal, 6)
                                .padding(.top, 8)
                        } else {
                            HStack {
                                EditorialSheetSectionLabel(title: "Dział")
                                if isGuessed {
                                    Text("podpowiedziany")
                                        .font(.sc(size: 12))
                                        .foregroundStyle(Color.scFaint(scheme))
                                        .padding(.trailing, 6)
                                        .padding(.bottom, 6)
                                }
                            }
                            .padding(.top, 22)
                            .padding(.bottom, 4)

                            ShoppingDepartmentGrid(departments: ShoppingDepartments.all) { item in
                                ShoppingDepartmentTile(department: item, isSelected: item == department) {
                                    isNameFocused = false
                                    withAnimation(.smooth(duration: 0.2)) {
                                        department = item
                                        isGuessed = false
                                    }
                                }
                            }
                        }

                        EditorialSheetSectionLabel(title: "Ilość")
                            .padding(.top, 22)
                            .padding(.bottom, 4)

                        ShoppingAddCard {
                            ShoppingAmountEditor(
                                amount: amount.flatMap { allowedUnits.contains($0.unit) ? $0 : nil },
                                allowed: allowedUnits,
                                accent: ProductConstants.departmentColor(for: catalogMatch?.department ?? department),
                                lockedToList: listItem?.listUnit != nil,
                                listTotal: listItem.flatMap { $0.hasAmount ? $0.totalAmount : nil },
                                onChange: { amount = $0 }
                            )
                            .padding(12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .containerRelativeFrame(.horizontal)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scSheetFooter {
                    SCSoftButton(
                        title: "Gotowe",
                        leadingIcon: "checkmark",
                        trailingIcon: nil,
                        isEnabled: !trimmedName.isEmpty,
                        action: done
                    )
                }
            }
        }
        .navigationTitle("Własny produkt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        // „Wstecz” i „Wyczyść” w terakocie, jak na stronach `scPushedPage`.
        .tint(SCPalette.terracotta)
        .onAppear(perform: seed)
    }

    private func seed() {
        guard !didSeed else { return }
        didSeed = true
        name = ShoppingProduct.displayName(initialName)
        if let guess = ShoppingProductSearch.guessDepartment(for: initialName, in: store.productSearchIndex) {
            department = guess
            isGuessed = true
        }
    }

    private func done() {
        guard !trimmedName.isEmpty else { return }
        let product = catalogMatch ?? ShoppingProduct(
            name: ShoppingProduct.displayName(trimmedName),
            department: department,
            ingredientId: nil,
            pieceOnly: false,
            aliases: []
        )
        let allowed = ShoppingAmountUnit.allowed(listUnit: listItem?.listUnit, pieceOnly: product.pieceOnly)
        selection.put(ShoppingProductDraft(
            product: product,
            amount: amount.flatMap { allowed.contains($0.unit) ? $0 : nil }
        ))
        onDone()
    }
}

// MARK: - Wspólne

/// Wiersz produktu podpięty pod wybór i listę — jedna droga dla wyników,
/// „Ostatnio dodawanych” i działu.
private struct ShoppingPickRowHost: View {
    let product: ShoppingProduct
    let selection: ShoppingAddSelection
    var highlight: (offset: Int, length: Int)? = nil
    var lastAmount: ShoppingAmount? = nil
    var showsRule: Bool = false

    @Environment(\.shoppingListStore) private var store

    var body: some View {
        let listItem = store.items.row(for: product)
        let allowed = ShoppingAmountUnit.allowed(listUnit: listItem?.listUnit, pieceOnly: product.pieceOnly)

        ShoppingProductPickRow(
            product: product,
            listItem: listItem,
            highlight: highlight,
            lastAmount: lastAmount,
            draft: selection.draft(for: product),
            isEditing: selection.editingKey == product.nameKey,
            showsRule: showsRule,
            onToggle: {
                withAnimation(.smooth(duration: 0.22)) {
                    selection.toggle(product, suggested: lastAmount, allowed: allowed)
                }
            },
            onAmountTap: {
                withAnimation(.smooth(duration: 0.24)) {
                    if selection.editingKey == product.nameKey {
                        selection.editingKey = nil
                    } else {
                        selection.editingKey = product.nameKey
                        // Edytor otwiera się z ilością do poprawienia, nie
                        // z pustym polem — najczęściej wystarczy „+”.
                        if selection.draft(for: product)?.amount == nil {
                            let unit = ShoppingAmountUnit.preferred(in: allowed)
                            selection.setAmount(ShoppingAmount(value: unit.defaultAmount, unit: unit), for: product)
                        }
                    }
                }
            },
            onAmountChange: { amount in
                withAnimation(.smooth(duration: 0.2)) {
                    selection.setAmount(amount, for: product)
                }
            }
        )
    }
}

/// „Dodaj »xyz« · jako własny produkt” — na końcu wyników.
private struct ShoppingCustomProductRow: View {
    let name: String
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ShoppingAddCard {
            Button(action: action) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 9.6, style: .continuous)
                        .strokeBorder(SCPalette.terracotta.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.sc(size: 14, weight: .bold))
                                .foregroundStyle(SCPalette.terracotta)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Dodaj „\(name)”")
                            .font(.sc(size: 15, weight: .semibold))
                            .tracking(-0.3)
                            .foregroundStyle(Color.scLabel(scheme))
                            .lineLimit(1)
                        Text("jako własny produkt")
                            .font(.sc(size: 12.5))
                            .foregroundStyle(Color.scMuted(scheme))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.sc(size: 12, weight: .bold))
                        .foregroundStyle(Color.scFaint(scheme))
                }
                .padding(.vertical, 9)
                .padding(.leading, 12)
                .padding(.trailing, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlanPressStyle(scale: 0.985))
        }
    }
}

/// Stopka stron dodawania: „Dodaj 3 produkty” — tylko, gdy coś wybrano.
private struct ShoppingAddFooter: View {
    let selection: ShoppingAddSelection
    let isAdding: Bool
    let onCommit: () -> Void

    var body: some View {
        if !selection.isEmpty {
            SCSoftButton(
                title: "Dodaj \(PolishPlural.products(selection.count))",
                leadingIcon: "cart.badge.plus",
                trailingIcon: nil,
                isEnabled: !isAdding,
                isLoading: isAdding,
                action: onCommit
            )
            .contentTransition(.numericText(value: Double(selection.count)))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Tytuł paska z drugą linijką („Lista 12–18 paź”).
private struct ShoppingAddNavTitle: View {
    let title: String
    let subtitle: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.sc(size: 16, weight: .semibold))
                .foregroundStyle(Color.scLabel(scheme))
            Text(subtitle)
                .font(.sc(size: 11.5))
                .foregroundStyle(Color.scMuted(scheme))
        }
        .accessibilityElement(children: .combine)
    }
}
