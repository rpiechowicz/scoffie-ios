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
// Arkusz stoi NA arkuszu Zakupów i sam otwiera nad sobą arkusz z listą —
// cofanie zdejmuje po jednym poziomie, tak jak strzałka w lewym górnym rogu.
struct ShoppingHistoryMonthSheet: View {
    let month: ShoppingHistoryMonth
    /// Produkty zamkniętej listy — z magazynu, żeby arkusz nie musiał znać
    /// reguły „druga rewizja pokazuje tylko to, co dołożyła”.
    var itemsForArchive: (String) -> [ShoppingItem]
    var dishSummary: (ShoppingItem) -> String? = { _ in nil }
    var onDelete: ((ShoppingHistoryEntry) -> Void)?
    var onClose: () -> Void

    @Environment(\.colorScheme) private var scheme

    @State private var openedArchiveId: String?
    /// Lista wskazana do skasowania z menu kontekstowego wiersza.
    @State private var pendingDelete: ShoppingHistoryEntry?

    private var meta: String {
        "\(PolishPlural.lists(month.listCount)) · \(PolishPlural.products(month.productCount))"
    }

    /// Otwarty wpis wyszukiwany po id przy każdym rysowaniu — dzięki temu
    /// usunięcie listy z arkusza nad spodem zamyka go samo, zamiast zostawiać
    /// otwarty ekran czegoś, czego już nie ma.
    private var openedEntryBinding: Binding<ShoppingHistoryEntry?> {
        Binding(
            get: {
                guard let openedArchiveId else { return nil }
                return month.entries.first { $0.archiveId == openedArchiveId }
            },
            set: { openedArchiveId = $0?.archiveId }
        )
    }

    var body: some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ShoppingSheetHeader(title: month.name, onClose: onClose)

                    ShoppingEyebrowRow(eyebrow: "Historia · \(month.year)", meta: meta)
                        .padding(.top, 20)

                    weeks
                        .padding(.top, 4)
                }
                .padding(.horizontal, SCPageMetrics.horizontal)
                .padding(.top, 18)
                .padding(.bottom, SCPageMetrics.bottom)
            }
            .scrollIndicators(.hidden)
        }
        .alert("Usunąć listę z historii?", isPresented: pendingDeleteBinding) {
            Button("Anuluj", role: .cancel) { pendingDelete = nil }
            Button("Usuń", role: .destructive) {
                if let pendingDelete { onDelete?(pendingDelete) }
                pendingDelete = nil
            }
        } message: {
            Text("Ta operacja usunie zapisany wpis historyczny dla tego tygodnia.")
        }
        .sheet(item: openedEntryBinding) { entry in
            ShoppingArchiveSheet(
                entry: entry,
                items: itemsForArchive(entry.archiveId),
                weekRange: weekRange(for: entry),
                dishSummary: dishSummaryAction(for: entry),
                // Skasowanie z arkusza listy nie zamyka go ręcznie: wpis
                // znika z miesiąca, `openedEntryBinding` przestaje go
                // znajdować i arkusz schodzi sam.
                onDelete: archiveDeleteAction(for: entry),
                onClose: { openedArchiveId = nil }
            )
            .presentationDetents([.large])
            .dashboardLiquidSheet()
        }
    }

    private var pendingDeleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    /// Dania pod nazwą produktu tylko dla OGLĄDANEGO tygodnia.
    ///
    /// Indeks dań jest zbudowany z planu tego jednego tygodnia, więc przy
    /// liście sprzed miesiąca dopisałby „Pomidorom” dzisiejszą zupę — danie,
    /// którego wtedy nie było. `isCurrent` na tygodniu znaczy dokładnie
    /// „to jest tydzień oglądany na Planie”, więc pytamy o to jego.
    private func dishSummaryAction(for entry: ShoppingHistoryEntry) -> (ShoppingItem) -> String? {
        let week = month.weeks.first { $0.weekStart == entry.weekStart }
        guard week?.isCurrent == true else { return { _ in nil } }
        return dishSummary
    }

    /// Jawne funkcje zamiast `cond ? nil : domknięcie` w argumencie.
    /// Warunek z `nil` po jednej stronie i wnioskowanym typem po drugiej daje
    /// dwa równorzędne rozwiązania (SE-0418), a kompilator zgłasza to
    /// kilkadziesiąt linii wyżej, przy najbliższym kontenerze SwiftUI.
    private func rowDeleteAction(for entry: ShoppingHistoryEntry) -> (() -> Void)? {
        guard onDelete != nil else { return nil }
        return { pendingDelete = entry }
    }

    /// Arkusz listy potwierdza kasowanie SAM (ma własny alert nad sobą), więc
    /// dostaje akcję, która kasuje wprost.
    private func archiveDeleteAction(for entry: ShoppingHistoryEntry) -> (() -> Void)? {
        guard let onDelete else { return nil }
        return { onDelete(entry) }
    }

    private func weekRange(for entry: ShoppingHistoryEntry) -> String {
        month.weeks.first { $0.weekStart == entry.weekStart }?.rangeLabel ?? ""
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
                        onOpen: { openedArchiveId = entry.archiveId },
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
