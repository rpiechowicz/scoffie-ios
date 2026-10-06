import SwiftUI

// Ekran 2 historii — jeden miesiąc, tygodnie na szynie.
// Źródło: canvas claude.ai → „Weekly Meals - Zakupy v2.html”
// (`components/shop-v2-history-flow.jsx` → `ShopHistFlowMonth`).
//
// Szyna jest ta sama, co oś dnia w Planie (`PlanRailMark`,
// `PlanTimelineMetrics`) — tylko kropka znaczy tydzień, a nie porę dnia.
// To jest celowe: w tej aplikacji pionowa linia z kropkami zawsze znaczy
// „czas idzie w dół”, i historia zakupów nie ma powodu mówić tego inaczej.
//
// Ekran wepchnięty w arkusz Zakupów (historia → miesiąc → lista), z systemowym
// paskiem: „wstecz” zdejmuje po jednym poziomie. Listę otwiera `ProductsView`
// (`ShoppingHistoryRoute.archive`) — ten ekran tylko oddaje stuknięcie.
struct ShoppingHistoryMonthPage: View {
    let month: ShoppingHistoryMonth
    var onOpenArchive: (ShoppingHistoryEntry) -> Void
    var onDelete: ((ShoppingHistoryEntry) -> Void)?

    @Environment(\.colorScheme) private var scheme

    /// Lista wskazana do skasowania z menu kontekstowego wiersza.
    @State private var pendingDelete: ShoppingHistoryEntry?

    private var meta: String {
        "\(PolishPlural.lists(month.listCount)) · \(PolishPlural.products(month.productCount))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ShoppingEyebrowRow(eyebrow: "Historia · \(month.year)", meta: meta)
                    .padding(.top, 8)

                weeks
                    .padding(.top, 4)
            }
            .padding(.horizontal, SCPageMetrics.horizontal)
            .padding(.bottom, SCPageMetrics.bottom)
        }
        .scrollIndicators(.hidden)
        .scPushedPage(month.name)
        .alert("Usunąć listę z historii?", isPresented: pendingDeleteBinding) {
            Button("Anuluj", role: .cancel) { pendingDelete = nil }
            Button("Usuń", role: .destructive) {
                if let pendingDelete { onDelete?(pendingDelete) }
                pendingDelete = nil
            }
        } message: {
            Text("Ta operacja usunie zapisany wpis historyczny dla tego tygodnia.")
        }
    }

    private var pendingDeleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    /// Jawne funkcje zamiast `cond ? nil : domknięcie` w argumencie.
    /// Warunek z `nil` po jednej stronie i wnioskowanym typem po drugiej daje
    /// dwa równorzędne rozwiązania (SE-0418), a kompilator zgłasza to
    /// kilkadziesiąt linii wyżej, przy najbliższym kontenerze SwiftUI.
    private func rowDeleteAction(for entry: ShoppingHistoryEntry) -> (() -> Void)? {
        guard onDelete != nil else { return nil }
        return { pendingDelete = entry }
    }

    // MARK: - Szyna tygodni

    private var weeks: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(month.weeks.enumerated()), id: \.element.weekStart) { weekIndex, week in
                weekRow(week, isFirst: weekIndex == 0, isLastWeek: weekIndex == month.weeks.count - 1)
            }
        }
        .background(alignment: .topLeading) { railLine }
        .animation(.snappy(duration: 0.3), value: month.entries.map(\.archiveId))
    }

    private func weekRow(_ week: ShoppingHistoryWeek, isFirst: Bool, isLastWeek: Bool) -> some View {
        HStack(alignment: .top, spacing: PlanTimelineMetrics.gutter) {
            PlanRailMark(
                time: week.shortLabel,
                color: week.isCurrent ? SCPalette.terracotta : Color.scFaint(scheme),
                muted: !week.isCurrent
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(weekEyebrow(week))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(week.isCurrent ? SCPalette.terracotta : Color.scFaint(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 4)
                    .padding(.bottom, 2)

                ForEach(Array(week.entries.enumerated()), id: \.element.archiveId) { index, entry in
                    ShoppingHistoryListRow(
                        entry: entry,
                        isLast: isLastWeek && index == week.entries.count - 1,
                        onOpen: { onOpenArchive(entry) },
                        onDelete: rowDeleteAction(for: entry)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, isFirst ? 18 : 12)
    }

    private func weekEyebrow(_ week: ShoppingHistoryWeek) -> String {
        let range = week.rangeLabel.uppercased()
        return week.isCurrent ? "\(range) · TEN TYDZIEŃ" : range
    }

    /// Pionowa linia szyny — pod treścią, od pierwszej kropki w dół.
    ///
    /// Na osi dnia w Planie każdy wiersz ma własną kropkę, więc linia kończy
    /// się tam, gdzie ostatnia. Tutaj kropka jest jedna na TYDZIEŃ, a pod nią
    /// stoi tyle wierszy, ile zamkniętych list — linia dobiegałaby więc kilka
    /// wierszy za ostatnią kropkę i urywała się w pustce. Zamiast mierzyć,
    /// gdzie dokładnie jest ostatnia kropka, linia po prostu gaśnie u dołu.
    private var railLine: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.scRule(scheme), Color.scRule(scheme), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1)

            Spacer(minLength: 0)
        }
        .padding(.leading, PlanTimelineMetrics.rail / 2 - 0.5)
        .padding(.top, 28)
        .padding(.bottom, 8)
        .allowsHitTesting(false)
    }
}
