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

                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)

                content

                footer
            }
        }
    }

    // MARK: - Nagłówek

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Na dziś")
                    .font(.system(size: 22, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(hasEverything ? "Wszystko kupione" : "\(missingCount) do kupienia")
                    .font(.system(size: 13, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(hasEverything ? SCPalette.sage : Color.scMuted(scheme))
                    .lineLimit(1)
                    .fixedSize()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.scMuted(scheme))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.scChipBg(scheme)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zamknij")
            }

            Text("\(dayLabel) · \(PolishPlural.dishes(dishes.count)) · \(boughtCount) z \(todayItems.count) kupione")
                .font(.system(size: 13, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(Color.scMuted(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, SCPageMetrics.horizontal)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: - Treść

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(dishes) { dish in
                    dishSection(dish)
                }
            }
            .padding(.horizontal, SCPageMetrics.horizontal)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func dishSection(_ dish: ShoppingDish) -> some View {
        // Kupione spadają na dół grupy — tak samo jak w alejce na liście.
        let dishItems = index.items(items, for: dish)
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isChecked != rhs.element.isChecked {
                    return !lhs.element.isChecked
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        return VStack(alignment: .leading, spacing: 0) {
            dishHeader(dish, items: dishItems)

            ForEach(Array(dishItems.enumerated()), id: \.element.productKey) { idx, item in
                ShoppingProductRow(
                    name: item.name,
                    amount: item.displayAmount,
                    dishes: item.department,
                    bought: item.isChecked,
                    isLast: idx == dishItems.count - 1,
                    isDisabled: disablesTaps,
                    onToggle: { onToggleItem(item) }
                )
            }
            .animation(
                .snappy(duration: 0.34),
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

                Text("\(PolishPlural.ingredients(dishItems.count)) · \(isComplete ? "wszystko kupione" : PolishPlural.bought(bought))")
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
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.scRule(scheme))
                .frame(height: 1)

            SCSoftButton(
                title: "Pokaż w liście zakupów",
                leadingIcon: "list.bullet",
                trailingIcon: nil,
                action: onShowInList
            )
            .padding(.horizontal, SCPageMetrics.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }
}
