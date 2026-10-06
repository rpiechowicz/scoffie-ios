import SwiftUI

// Ekran 3 historii — jedna zamknięta lista, tylko do odczytu.
// Źródło: canvas claude.ai → „Weekly Meals - Zakupy v2.html”
// (`components/shop-v2-history-flow.jsx` → `ShopHistFlowList`).
//
// Dokładnie ten sam układ, co aktywna lista: pasek alejek, sekcje działów
// z licznikiem, wiersze z daniami pod nazwą. Bez odhaczania, bez „Na dziś”.
// To nie jest osobny ekran „podglądu archiwum” — to jest ta sama lista,
// tyle że zamknięta, i ma tak wyglądać.
//
// Ostatni ekran stosu historii w arkuszu Zakupów (push, systemowy pasek
// z „wstecz” i „…”). Po skasowaniu listy `ProductsView` sam zdejmuje ten
// ekran ze stosu — wpisu już nie ma.
struct ShoppingArchivePage: View {
    let entry: ShoppingHistoryEntry
    let items: [ShoppingItem]
    let weekRange: String
    /// Dania pod nazwą produktu — sensowne tylko dla oglądanego tygodnia,
    /// bo indeks jest zbudowany z JEGO planu.
    var dishSummary: (ShoppingItem) -> String? = { _ in nil }
    var onDelete: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    /// Potwierdzenie kasowania przed `onDelete` — alert na tym ekranie.
    @State private var confirmingDelete = false

    private var groups: [(department: String, items: [ShoppingItem])] {
        ProductConstants.grouped(items)
    }

    private var segments: [ShoppingProgressSegment] {
        groups.map { group in
            ShoppingProgressSegment(
                id: group.department,
                bought: group.items.filter(\.isChecked).count,
                total: group.items.count,
                color: ProductConstants.departmentColor(for: group.department)
            )
        }
    }

    private var eyebrow: String {
        "\(weekRange) · zamknięta \(ShoppingHistoryFormat.closedAt(entry.closedAt))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ShoppingEyebrowRow(eyebrow: eyebrow)
                    .padding(.top, 8)

                ShoppingProgressHeader(
                    bought: items.filter(\.isChecked).count,
                    total: items.count,
                    segments: segments
                )
                .padding(.top, 16)

                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    .padding(.top, 16)

                ForEach(Array(groups.enumerated()), id: \.element.department) { _, group in
                    ShoppingAisleSection(
                        department: group.department,
                        items: group.items,
                        mode: .readOnly,
                        dishSummary: dishSummary
                    )
                }
            }
            .padding(.horizontal, SCPageMetrics.horizontal)
            .padding(.bottom, SCPageMetrics.bottom)
        }
        .scrollIndicators(.hidden)
        .scPushedPage(entry.name)
        .toolbar {
            if onDelete != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Label("Usuń listę z historii", systemImage: "trash")
                        }
                    } label: {
                        Label("Więcej opcji listy", systemImage: "ellipsis")
                    }
                }
            }
        }
        .alert("Usunąć listę z historii?", isPresented: $confirmingDelete) {
            Button("Anuluj", role: .cancel) { }
            Button("Usuń", role: .destructive) { onDelete?() }
        } message: {
            Text("Ta operacja usunie zapisany wpis historyczny dla tego tygodnia.")
        }
    }
}
