import SwiftUI

// Historia list zakupów — miesiące.
//
// Na Zakupach z zamkniętą listą te same wiersze stoją WPROST na ekranie
// (patrz `ProductsView.archivedState`): skoro tydzień jest domknięty, historia
// jest jedyną rzeczą, jaka na tym ekranie została. Ten ekran jest dla drugiego
// przypadku — lista jest aktywna, ktoś wchodzi do historii z menu „…”.
//
// Od 6.10.2026 historia, miesiąc i lista to kolejne ekrany W arkuszu Zakupów
// (push w jego `NavigationStack`, systemowy pasek z „wstecz”), a nie trzy
// arkusze ułożone jeden na drugim. Stos trzyma `ProductsView`
// (`ShoppingHistoryRoute`); ekrany tylko oddają stuknięcia.
struct ShoppingHistoryPage: View {
    let months: [ShoppingHistoryMonth]
    var onOpenMonth: (ShoppingHistoryMonth) -> Void
    /// „Usuń całą historię” — JEDYNE miejsce tej akcji (menu „…” Zakupów
    /// już jej nie ma).
    var onDeleteAll: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    @State private var confirmingDeleteAll = false

    private var listCount: Int { months.reduce(0) { $0 + $1.listCount } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ShoppingEyebrowRow(
                    eyebrow: "Zamknięte listy",
                    meta: months.isEmpty ? nil : PolishPlural.lists(listCount)
                )
                .padding(.top, 8)

                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    .padding(.top, 12)

                if months.isEmpty {
                    emptyNote
                        .padding(.top, 24)
                } else {
                    ShoppingMonthList(months: months, onOpen: onOpenMonth)
                }
            }
            .padding(.horizontal, SCPageMetrics.horizontal)
            .padding(.bottom, SCPageMetrics.bottom)
        }
        .scrollIndicators(.hidden)
        .scPushedPage("Historia")
        .toolbar {
            if onDeleteAll != nil, !months.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) { confirmingDeleteAll = true } label: {
                            Label("Usuń całą historię", systemImage: "trash")
                        }
                    } label: {
                        Label("Więcej opcji historii", systemImage: "ellipsis")
                    }
                }
            }
        }
        .alert("Usunąć całą historię list?", isPresented: $confirmingDeleteAll) {
            Button("Anuluj", role: .cancel) { }
            Button("Usuń wszystko", role: .destructive) { onDeleteAll?() }
        } message: {
            Text("Ta operacja usunie wszystkie zapisane listy produktów z historii.")
        }
    }

    private var emptyNote: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.scMuted(scheme))

            // Krój pustych stanów list (16 heavy / 13), jak `noteCard` Zakupów.
            Text("Historia jest pusta")
                .font(.system(size: 16, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(Color.scLabel(scheme))

            Text("Zamknięte listy zakupów trafią tutaj same.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.scMuted(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }
}

/// Wiersze miesięcy — te same na ekranie z zamkniętą listą i w arkuszu
/// historii, więc stoją w jednym miejscu.
struct ShoppingMonthList: View {
    let months: [ShoppingHistoryMonth]
    var onOpen: (ShoppingHistoryMonth) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(months.enumerated()), id: \.element.key) { index, month in
                ShoppingHistoryMonthRow(
                    month: month,
                    isLast: index == months.count - 1,
                    onOpen: { onOpen(month) }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topLeading)))
            }
        }
        .animation(.snappy(duration: 0.3), value: months.map(\.key))
    }
}
