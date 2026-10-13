import SwiftUI

// Klocki dopisywania produktów na Zakupach (13.10.2026, artefakt „Własne
// produkty w Zakupach”, ekrany 1–7). Zbudowane z tego, co aplikacja już ma:
// kafelek działu z alejek (`RecipeExclusionDepartmentIcon`), pigułka ilości
// w kolorze działu jak na liście, szkło stepera jak `SCStepper`, przyciski
// „soft”. Nowe są tylko układy.

// MARK: - Działy

enum ShoppingDepartments {
    /// Wszystkie działy w kolejności obchodzenia sklepu (`ProductConstants`).
    static let all: [String] = [
        ProductConstants.Department.vegetables,
        ProductConstants.Department.fruits,
        ProductConstants.Department.meat,
        ProductConstants.Department.fish,
        ProductConstants.Department.dairy,
        ProductConstants.Department.bakery,
        ProductConstants.Department.grains,
        ProductConstants.Department.canned,
        ProductConstants.Department.spices,
        ProductConstants.Department.oils,
        ProductConstants.Department.alcohols,
        ProductConstants.Department.beverages,
        ProductConstants.Department.snacks,
        ProductConstants.Department.frozen,
        ProductConstants.Department.bakerySweets,
        ProductConstants.Department.household,
        ProductConstants.Department.other
    ]
}

/// Kafel działu w siatce 3 × N: ikona i barwa alejki, nazwa, pod nią liczba
/// produktów (w arkuszu) albo nic (wybór działu własnego produktu).
struct ShoppingDepartmentTile: View {
    let department: String
    var subtitle: String? = nil
    var isSelected: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var accent: Color { ProductConstants.departmentColor(for: department) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                RecipeExclusionDepartmentIcon(department: department, size: 32)

                Text(department)
                    .font(.sc(size: 13, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if let subtitle {
                    Text(subtitle)
                        .font(.sc(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(Color.scFaint(scheme))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 11)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, minHeight: subtitle == nil ? 86 : 104, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? accent.opacity(scheme == .dark ? 0.16 : 0.10) : Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? accent.opacity(0.55) : Color.scTileStroke(scheme), lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.97))
        .accessibilityLabel(department)
        .accessibilityValue(subtitle ?? "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Siatka kafli działów — trzy w rzędzie.
struct ShoppingDepartmentGrid<Tile: View>: View {
    let departments: [String]
    @ViewBuilder let tile: (String) -> Tile

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(departments, id: \.self) { department in
                tile(department)
            }
        }
    }
}

// MARK: - Karta wierszy

/// Karta wierszy w arkuszu — jedna barwa kart w całej aplikacji
/// (`scTileBg` + `scTileStroke`, bez cienia).
struct ShoppingAddCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.scTileStroke(scheme), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Wiersz produktu w arkuszu

/// Produkt do wybrania: kafelek działu · nazwa (trafienie w terakocie) · pod
/// nią dział albo „Na liście · 1,3 l” · „+” albo — po wybraniu — pigułka
/// ilości i ptaszek. Pod wybranym może się rozwinąć edytor ilości.
struct ShoppingProductPickRow: View {
    let product: ShoppingProduct
    /// Wiersz tego produktu na liście tygodnia (`nil` = jeszcze go nie ma).
    let listItem: ShoppingItem?
    var highlight: (offset: Int, length: Int)? = nil
    /// „ostatnio 2 szt” — przy „Ostatnio dodawanych”.
    var lastAmount: ShoppingAmount? = nil
    let draft: ShoppingProductDraft?
    let isEditing: Bool
    var showsRule: Bool = false
    let onToggle: () -> Void
    let onAmountTap: () -> Void
    let onAmountChange: (ShoppingAmount?) -> Void

    @Environment(\.colorScheme) private var scheme

    private var accent: Color { ProductConstants.departmentColor(for: product.department) }

    private var allowedUnits: [ShoppingAmountUnit] {
        ShoppingAmountUnit.allowed(listUnit: listItem?.listUnit, pieceOnly: product.pieceOnly)
    }

    var body: some View {
        VStack(spacing: 0) {
            row
            if let draft, isEditing {
                ShoppingAmountEditor(
                    amount: draft.amount,
                    allowed: allowedUnits,
                    accent: accent,
                    lockedToList: listItem?.listUnit != nil,
                    listTotal: listItem.flatMap(listTotal(for:)),
                    onChange: onAmountChange
                )
                .padding(.leading, 12 + 32 + 12)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .overlay(alignment: .top) {
            if showsRule {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    .padding(.leading, 12 + 32 + 12)
            }
        }
        .animation(.smooth(duration: 0.24), value: isEditing)
        .animation(.smooth(duration: 0.2), value: draft)
    }

    private var row: some View {
        HStack(spacing: 12) {
            RecipeExclusionDepartmentIcon(department: product.department, size: 32)

            VStack(alignment: .leading, spacing: 1) {
                name
                    .font(.sc(size: 15, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)

                subtitle
                    .font(.sc(size: 12.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let draft {
                amountButton(draft)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }

            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .fill(draft == nil ? SCPalette.terracotta.opacity(scheme == .dark ? 0.18 : 0.13) : SCPalette.terracotta)
                    Image(systemName: draft == nil ? "plus" : "checkmark")
                        .font(.sc(size: 14, weight: .bold))
                        .foregroundStyle(draft == nil ? SCPalette.terracotta : Color.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 32, height: 32)
                .contentShape(Circle())
            }
            .buttonStyle(PlanPressStyle(scale: 0.9))
            .accessibilityLabel(draft == nil ? "Wybierz \(product.name)" : "Odznacz \(product.name)")
        }
        .padding(.vertical, 7)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .accessibilityElement(children: .contain)
    }

    /// Nazwa z podświetlonym trafieniem. Przesunięcie liczone w znakach
    /// złożonej nazwy (`IngredientSearch.fold` zamienia znak na znak).
    private var name: Text {
        let title = product.name
        guard let highlight,
              highlight.offset >= 0,
              highlight.length > 0,
              highlight.offset + highlight.length <= title.count
        else { return Text(title) }
        let start = title.index(title.startIndex, offsetBy: highlight.offset)
        let end = title.index(start, offsetBy: highlight.length)
        return Text(title[..<start])
            + Text(title[start..<end]).foregroundColor(SCPalette.terracotta)
            + Text(title[end...])
    }

    private var subtitle: Text {
        if let listItem {
            let amount = listItem.displayAmount
            return Text(amount.isEmpty ? "Na liście" : "Na liście · \(amount)")
                .fontWeight(.medium)
                .foregroundColor(accent)
        }
        let base = product.isCustom ? "Twój produkt · \(product.department)" : product.department
        if let lastAmount, draft == nil {
            return Text("\(base) · ostatnio \(lastAmount.text)").foregroundColor(Color.scMuted(scheme))
        }
        return Text(base).foregroundColor(Color.scMuted(scheme))
    }

    private func amountButton(_ draft: ShoppingProductDraft) -> some View {
        Button(action: onAmountTap) {
            Group {
                if let amount = draft.amount {
                    Text(amount.text)
                        .font(.sc(size: 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Capsule().fill(accent.opacity(scheme == .dark ? 0.20 : 0.12)))
                        .overlay(Capsule().stroke(accent.opacity(scheme == .dark ? 0.42 : 0.32), lineWidth: 1))
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.sc(size: 10, weight: .bold))
                        Text("ilość")
                            .font(.sc(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color.scMuted(scheme))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .overlay(
                        Capsule().strokeBorder(Color.scFaint(scheme), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    )
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .accessibilityLabel(draft.amount.map { "Ilość \($0.text)" } ?? "Ustaw ilość")
    }

    /// Co stanie w pigułce na liście po dopisaniu — tylko w jednostce wiersza.
    private func listTotal(for item: ShoppingItem) -> Double? {
        item.hasAmount ? item.totalAmount : nil
    }
}

// MARK: - Edytor ilości

/// Ilość dopisywanego produktu: wartość w kolorze działu, szklany stepper
/// (minus | plus — jak `SCStepper`), jednostki do wyboru i „Bez ilości”.
/// Gdy produkt już stoi na liście, jednostka jest jego wiersza („jak na
/// liście”), a pod wartością — co będzie razem.
struct ShoppingAmountEditor: View {
    let amount: ShoppingAmount?
    let allowed: [ShoppingAmountUnit]
    var accent: Color = SCPalette.terracotta
    var lockedToList: Bool = false
    /// Ilość, którą wiersz listy już ma (w jednostce listy).
    var listTotal: Double? = nil
    let onChange: (ShoppingAmount?) -> Void

    @Environment(\.colorScheme) private var scheme

    private var listUnit: String? { allowed.first?.listUnit }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(amount?.text ?? "bez ilości")
                        .font(.sc(size: 20, weight: .heavy))
                        .tracking(-0.4)
                        .monospacedDigit()
                        .foregroundStyle(amount == nil ? Color.scMuted(scheme) : accent)
                        .contentTransition(.numericText(value: amount?.value ?? 0))

                    if let together {
                        Text("razem \(together)")
                            .font(.sc(size: 12.5))
                            .monospacedDigit()
                            .foregroundStyle(Color.scMuted(scheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(SCMotion.textRoll, value: amount)

                stepper
            }

            HStack(spacing: 6) {
                if allowed.count > 1 {
                    ForEach(allowed) { unit in
                        unitChip(unit)
                    }
                }
                if lockedToList {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.sc(size: 10, weight: .bold))
                        Text("jak na liście")
                            .font(.sc(size: 12.5))
                    }
                    .foregroundStyle(Color.scMuted(scheme))
                    .padding(.leading, allowed.count > 1 ? 2 : 0)
                }
                Spacer(minLength: 8)
                if amount != nil {
                    Button("Bez ilości") { onChange(nil) }
                        .font(.sc(size: 12.5, weight: .semibold))
                        .foregroundStyle(SCPalette.terracotta)
                        .buttonStyle(.plain)
                }
            }
        }
    }

    /// „razem 2,3 l” — gdy wiersz listy ma ilość w tej samej jednostce.
    private var together: String? {
        guard let listTotal, let amount, let listUnit, amount.unit.listUnit == listUnit else { return nil }
        return ShoppingAmountText.list(listTotal + amount.listValue, unit: listUnit)
    }

    private var stepper: some View {
        HStack(spacing: 0) {
            stepButton("minus", enabled: amount != nil) {
                onChange(amount?.stepped(by: -1))
            }
            Rectangle()
                .fill(Color.scTileStroke(scheme))
                .frame(width: 1, height: 18)
            stepButton("plus", enabled: amount.map { $0.value < $0.unit.maxAmount } ?? true) {
                if let amount {
                    onChange(amount.stepped(by: 1))
                } else {
                    let unit = ShoppingAmountUnit.preferred(in: allowed)
                    onChange(ShoppingAmount(value: unit.defaultAmount, unit: unit))
                }
            }
        }
        .scChromeGlass(in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ilość")
    }

    private func stepButton(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.sc(size: 12, weight: .bold))
                .foregroundStyle(SCPalette.terracotta)
                .frame(width: 38, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(systemName == "plus" ? "Więcej" : "Mniej")
    }

    private func unitChip(_ unit: ShoppingAmountUnit) -> some View {
        let isOn = amount?.unit == unit
        return Button {
            guard !isOn else { return }
            onChange(ShoppingAmount(value: unit.defaultAmount, unit: unit))
        } label: {
            Text(unit.rawValue)
                .font(.sc(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? SCPalette.terracotta : Color.scMuted(scheme))
                .frame(minWidth: 40)
                .padding(.horizontal, 6)
                .frame(height: 28)
                .background(
                    Capsule().fill(isOn ? SCPalette.terracotta.opacity(scheme == .dark ? 0.18 : 0.14) : Color.scChipBg(scheme))
                )
                .overlay(
                    Capsule().strokeBorder(isOn ? SCPalette.terracotta.opacity(0.4) : Color.scTileStroke(scheme), lineWidth: 1)
                )
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Znacznik dopisanego na liście

/// „dopisane” albo „+1 l” z kółkiem osoby, która dopisała — druga linijka
/// wiersza listy, obok dań z planu.
struct ShoppingAddedMark: Equatable {
    let member: HouseholdMemberSnapshot?
    let members: [HouseholdMemberSnapshot]
    let text: String

    /// Wiersz z dopisaną ręcznie częścią — `nil`, gdy nikt nic nie dopisał.
    static func make(for item: ShoppingItem, members: [HouseholdMemberSnapshot]) -> ShoppingAddedMark? {
        guard let manual = item.manual else { return nil }
        let member = manual.addedById.flatMap { id in members.first { $0.id == id } }
        let text: String
        if let amount = manual.amount, let unit = manual.unit, !item.isOnlyManual {
            text = "+" + ShoppingAmountText.list(amount, unit: unit)
        } else {
            text = "dopisane"
        }
        return ShoppingAddedMark(member: member, members: members, text: text)
    }
}

extension ShoppingItem {
    /// Wiersz istnieje WYŁĄCZNIE dzięki ręcznemu dopisaniu — zdjęcie go
    /// usuwa cały („Usuń z listy”), a nie tylko dopisaną część.
    var isOnlyManual: Bool {
        guard let manual, (addedFrom ?? []).isEmpty else { return false }
        guard let amount = manual.amount else { return !hasAmount }
        return abs(totalAmount - amount) < 0.01
    }
}
