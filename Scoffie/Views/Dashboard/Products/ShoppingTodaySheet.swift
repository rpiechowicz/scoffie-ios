import SwiftUI

// Arkusz „Na dziś” — dzisiejsze dania z ich produktami, pogrupowane po daniu.
//
// Źródło: canvas claude.ai → „Weekly Meals - Zakupy v2.html”
// (`components/shop-v2-final.jsx` → `ShopTodaySheet`, `ShopDishHead`).
//
// Lista zakupów jest ułożona po alejkach sklepu — i tak ma być, bo tak się
// chodzi między półkami. Ale pytanie „czego mi brakuje na dzisiejszy obiad”
// przecina alejki w poprzek i na liście po działach nie da się na nie
// odpowiedzieć. Arkusz pokazuje tę samą listę drugą osią: danie po daniu,
// ze zdjęciem i licznikiem składników. Odhaczanie działa tak samo, bo to są
// te same produkty — nie kopia.
//
// „Pokaż w liście zakupów” zamyka arkusz i zawęża listę do dzisiejszych
// braków: podgląd zostaje podglądem, a tryb w sklepie trybem.
struct ShoppingTodaySheet: View {
    let date: Date
    let dishes: [ShoppingDish]
    let items: [ShoppingItem]
    let index: ShoppingDishIndex
    var members: [HouseholdMemberSnapshot] = []
    var disablesTaps: Bool = false
    var onToggleItem: (ShoppingItem) -> Void = { _ in }
    var onShowInList: () -> Void = {}
    var onClose: () -> Void = {}

    @Environment(\.colorScheme) private var scheme

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "EEEE d MMM"
        return formatter
    }()

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    // MARK: - Liczby

    private var todayItems: [ShoppingItem] {
        items.filter { index.isForToday($0) }
    }

    /// Dania, pod którymi jest co pokazać.
    ///
    /// Po zamknięciu listy i zmianie planu aktywna lista niesie tylko produkty
    /// DOŁOŻONE tą zmianą, więc danie sprzed zamknięcia zostaje bez ani jednego
    /// wiersza. Nagłówek „0 składników · 0 kupionych” nad pustką nie mówi nic
    /// poza tym, że coś się popsuło.
    private var visibleDishes: [ShoppingDish] {
        dishes.filter { !index.items(items, for: $0).isEmpty }
    }

    private var boughtCount: Int { todayItems.filter(\.isChecked).count }
    private var missingCount: Int { todayItems.count - boughtCount }
    private var hasEverything: Bool { missingCount == 0 }

    private var dayLabel: String {
        let raw = Self.dayFormatter.string(from: date)
        guard let first = raw.first else { return raw }
        return String(first).uppercased(with: Locale(identifier: "pl_PL")) + raw.dropFirst()
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                content

                footer
            }
        }
    }

    // MARK: - Nagłówek

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShoppingSheetHeader(title: "Na dziś", onClose: onClose)

            ShoppingEyebrowRow(
                eyebrow: "\(dayLabel) · \(PolishPlural.dishes(visibleDishes.count))",
                meta: hasEverything ? "Wszystko kupione" : "\(missingCount) do kupienia"
            )
            .padding(.top, 14)
        }
        .padding(.horizontal, SCPageMetrics.horizontal)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: - Treść

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visibleDishes) { dish in
                    dishSection(dish)
                }
            }
            .padding(.horizontal, SCPageMetrics.horizontal)
            // Stopka stoi pod listą, a jej cień leży na liście — ostatnie
            // danie musi dać się wyciągnąć ponad niego.
            .padding(.bottom, SCEdgeShade.bottomHeight)
        }
        .scrollIndicators(.hidden)
        // Zamiast kreski pod nagłówkiem — treść gaśnie, gdy pod niego wjeżdża.
        .scScrollEdgeFade()
    }

    private func dishSection(_ dish: ShoppingDish) -> some View {
        // Kolejność z listy — odhaczenie nie przestawia wierszy, tak samo
        // jak w alejce.
        let dishItems = index.items(items, for: dish)

        return VStack(alignment: .leading, spacing: 0) {
            dishHeader(dish, items: dishItems)

            ForEach(Array(dishItems.enumerated()), id: \.element.productKey) { idx, item in
                ShoppingProductRow(
                    name: item.name,
                    amount: item.displayAmount,
                    dishes: item.department,
                    bought: item.isChecked,
                    // Ilość trzyma kolor DZIAŁU także tutaj, choć arkusz jest
                    // pogrupowany po daniach: ta sama barwa co na liście mówi,
                    // z której półki produkt się bierze.
                    accent: ProductConstants.departmentColor(for: item.department),
                    isLast: idx == dishItems.count - 1,
                    isDisabled: disablesTaps,
                    onToggle: { onToggleItem(item) }
                )
            }
            // Ta sama zwłoka co na liście — kupiony składnik schodzi na dół
            // grupy dopiero wtedy, gdy widać już, że ptaszek wszedł.
            .animation(
                .spring(response: 0.38, dampingFraction: 0.88).delay(0.2),
                value: dishItems.map(\.productKey).joined(separator: "|")
            )
        }
    }

    private func dishHeader(_ dish: ShoppingDish, items dishItems: [ShoppingItem]) -> some View {
        let bought = dishItems.filter(\.isChecked).count
        let isComplete = !dishItems.isEmpty && bought == dishItems.count

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Self.shortDayFormatter.string(from: dish.date).uppercased()) · \(dish.slot.title.uppercased())")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(dish.slot.cozyAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(dish.title)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.35)
                    .foregroundStyle(Color.scLabel(scheme))
                    // Tytuł dania jest jedyną rzeczą w arkuszu, która MOŻE
                    // wziąć drugą linijkę — to on identyfikuje grupę.
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                SCCountingText("\(PolishPlural.ingredients(dishItems.count)) · \(isComplete ? "wszystko kupione" : PolishPlural.bought(bought))")
                    .font(.system(size: 12.5, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(isComplete ? SCPalette.sage : Color.scMuted(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            thumbnail(dish)
        }
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private func thumbnail(_ dish: ShoppingDish) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let url = dish.imageURL {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            placeholderThumb(dish)
                        }
                    }
                } else {
                    placeholderThumb(dish)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )

            if !dish.participantIds.isEmpty && !members.isEmpty {
                PlanWhoBadge(participantIds: dish.participantIds, members: members, size: 20)
                    .offset(x: 5, y: 5)
            }
        }
        .frame(width: 56, height: 56)
    }

    private func placeholderThumb(_ dish: ShoppingDish) -> some View {
        ZStack {
            dish.slot.cozyAccent.opacity(scheme == .dark ? 0.22 : 0.14)
            Image(systemName: dish.slot.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(dish.slot.cozyAccent)
        }
    }

    // MARK: - Stopka

    private var footer: some View {
        SCSheetFooter {
            SCSoftButton(
                title: "Pokaż w liście zakupów",
                leadingIcon: "list.bullet",
                trailingIcon: nil,
                action: onShowInList
            )
        }
    }
}
