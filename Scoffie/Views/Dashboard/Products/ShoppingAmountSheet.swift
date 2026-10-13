import SwiftUI

// „Zmień ilość” dopisanego produktu (13.10.2026, artefakt „Własne produkty
// w Zakupach”, ekran 7) — z menu przytrzymanego wiersza na Zakupach.
//
// Małe okno akcji na dole ekranu (CLAUDE.md: jeden arkusz + małe okno
// akcji), nie pełny arkusz: dwie liczby i stepper. Część z planu (i z
// przepisów) jest tylko do odczytu — zmienia ją plan; tu zmienia się
// wyłącznie to, co ktoś dopisał.

struct ShoppingAmountSheet: View {
    let item: ShoppingItem
    let members: [HouseholdMemberSnapshot]
    let currentUserId: String?
    /// Zapis nowej ilości (`nil` = bez ilości). Oddaje, czy się udało.
    let onSave: (ShoppingAmount?) async -> Bool
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.shoppingListStore) private var store

    @State private var amount: ShoppingAmount?
    @State private var isSaving = false
    @State private var didSeed = false

    private var accent: Color { ProductConstants.departmentColor(for: item.department) }

    private var manualListAmount: Double { item.manual?.amount ?? 0 }

    /// Część wiersza spoza dopisanego ręcznie (plan, przepisy).
    private var otherPart: Double? {
        guard item.hasAmount, !item.isOnlyManual else { return nil }
        let rest = item.totalAmount - manualListAmount
        return rest > 0.000_1 ? rest : nil
    }

    private var allowed: [ShoppingAmountUnit] {
        let pieceOnly = store.productCatalog.first { $0.nameKey == item.productNameKey }?.pieceOnly ?? false
        // Z planem w wierszu — tylko jego jednostka; sam dopisany produkt
        // może zmienić jednostkę (wtedy przeskoczy do swojego wiersza).
        return ShoppingAmountUnit.allowed(listUnit: otherPart != nil ? item.listUnit : nil, pieceOnly: pieceOnly)
    }

    private var addedBy: HouseholdMemberSnapshot? {
        item.manual?.addedById.flatMap { id in members.first { $0.id == id } }
    }

    private var addedByText: String {
        guard let id = item.manual?.addedById else { return "dopisane" }
        if id == currentUserId { return "przez Ciebie" }
        return addedBy.map { NotificationActorFormatter.firstName(from: $0.displayName) } ?? "dopisane"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShoppingSheetHeader(
                title: item.name,
                icon: ProductConstants.departmentIcon(for: item.department),
                accent: accent,
                onClose: { dismiss() }
            )
            .padding(.top, 22)

            ShoppingAddCard {
                if let otherPart {
                    HStack(spacing: 12) {
                        SCHeaderIconWell(icon: "fork.knife", accent: Color.scMuted(scheme), size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((item.addedFrom ?? []).isEmpty ? "Z planu" : "Z planu i przepisów")
                                .font(.sc(size: 15, weight: .semibold))
                                .foregroundStyle(Color.scLabel(scheme))
                            Text("zmienia się razem z planem")
                                .font(.sc(size: 12.5))
                                .foregroundStyle(Color.scMuted(scheme))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(ShoppingAmountText.list(otherPart, unit: item.unit))
                            .font(.sc(size: 15, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.scMuted(scheme))
                    }
                    .padding(12)

                    Rectangle()
                        .fill(Color.scRule(scheme))
                        .frame(height: 1)
                        .padding(.leading, 12 + 32 + 12)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        avatar
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Dopisane")
                                .font(.sc(size: 15, weight: .semibold))
                                .foregroundStyle(Color.scLabel(scheme))
                            Text(addedByText)
                                .font(.sc(size: 12.5))
                                .foregroundStyle(Color.scMuted(scheme))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ShoppingAmountEditor(
                        amount: amount,
                        allowed: allowed,
                        accent: accent,
                        lockedToList: otherPart != nil,
                        listTotal: otherPart,
                        onChange: { next in
                            withAnimation(.smooth(duration: 0.2)) { amount = next }
                        }
                    )
                    .padding(.leading, 32 + 12)
                }
                .padding(12)
            }
            .padding(.top, 16)

            HStack(spacing: 10) {
                SCDestructiveButton(
                    title: item.isOnlyManual ? "Usuń z listy" : "Usuń dopisane",
                    icon: "minus.circle"
                ) {
                    onRemove()
                    dismiss()
                }

                SCSoftButton(
                    title: "Zapisz",
                    leadingIcon: "checkmark",
                    trailingIcon: nil,
                    isEnabled: !isSaving,
                    isLoading: isSaving,
                    action: save
                )
            }
            .padding(.top, 18)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SCPageMetrics.horizontal)
        .onAppear {
            guard !didSeed else { return }
            didSeed = true
            amount = ShoppingAmount.fromList(amount: item.manual?.amount, unit: item.manual?.unit)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let addedBy {
            MemberAvatar(member: addedBy, members: members, size: 32)
        } else {
            SCHeaderIconWell(icon: "person.fill", accent: SCPalette.terracotta, size: 32)
        }
    }

    private func save() {
        isSaving = true
        Task { @MainActor in
            let saved = await onSave(amount)
            isSaving = false
            if saved { dismiss() }
        }
    }
}
