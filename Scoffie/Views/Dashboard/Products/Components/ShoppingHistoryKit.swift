import SwiftUI

// Wspólne części trzech ekranów historii zakupów.
// Źródło: canvas claude.ai → „Weekly Meals - Zakupy v2.html”, sekcja
// „Zakupy v2 · Historia · Final” (`components/shop-v2-history-flow.jsx`).

/// Mała pigułka z etykietą — „DZIŚ” przy produkcie, „TEN MIESIĄC” przy wierszu
/// miesiąca. Jeden rysunek, bo to jest ta sama rzecz: krótkie słowo, które
/// mówi „to jest to teraz”.
struct ShoppingTag: View {
    let text: String
    var color: Color = SCPalette.terracotta

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                Capsule().fill(color.opacity(scheme == .dark ? 0.18 : 0.12))
            )
    }
}

/// Wiersz pod tytułem ekranu: eyebrow tygodnia albo sekcji po lewej, meta
/// po prawej. Stoi na wszystkich czterech ekranach zakupów, więc mieszka
/// tutaj, a nie w każdym z osobna.
struct ShoppingEyebrowRow: View {
    let eyebrow: String
    var meta: String?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(eyebrow)
                // Wersaliki robi komponent, nie wywołujący: eyebrow jest
                // wersalikami zawsze i cztery ekrany nie mają czego pilnować.
                .textCase(.uppercase)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.scMuted(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            if let meta, !meta.isEmpty {
                Text(meta)
                    .font(.system(size: 12.5, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(Color.scFaint(scheme))
                    .lineLimit(1)
                    // Meta ustępuje miejsca eyebrow, a nie odwrotnie — data
                    // tygodnia jest ważniejsza od liczby list.
                    .layoutPriority(-1)
                    .transition(.opacity)
            }
        }
        .frame(minHeight: 22)
    }
}

/// Nagłówek arkusza zakupów: tytuł · akcje · krzyżyk.
///
/// Osobny komponent, a nie `EditorialSheetHeader`: tamten prowadzi eyebrow NAD
/// tytułem i trzyma go w 24 punktach, a te ekrany są ciągiem dalszym Zakupów
/// i mają czytać się jak one — duży tytuł, a pod nim własny wiersz z eyebrow
/// i metą (`ShoppingEyebrowRow`).
///
/// Zamyka KRZYŻYK, nie strzałka wstecz, i to nawet wtedy, gdy arkusze stoją
/// jeden na drugim. Arkusz się zamyka — dokładnie to samo robi przeciągnięcie
/// w dół — a strzałka obiecywałaby nawigację, której tu nie ma.
struct ShoppingSheetHeader<Trailing: View>: View {
    let title: String
    var onClose: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Ta sama drabinka stopni pisma, co w `EditorialPageHeader`:
            // tytuł schodzi o stopień, zamiast się urywać.
            ViewThatFits(in: .horizontal) {
                titleText(size: 32)
                titleText(size: 28)
                titleText(size: 24, allowsScaling: true)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                trailing()
                SCSheetCloseButton(action: onClose)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func titleText(size: CGFloat, allowsScaling: Bool = false) -> some View {
        Text(title)
            .font(.system(size: size, weight: .heavy))
            .tracking(-0.5)
            .foregroundStyle(Color.scLabel(scheme))
            .lineLimit(1)
            .minimumScaleFactor(allowsScaling ? 0.75 : 1)
    }
}

extension ShoppingSheetHeader where Trailing == EmptyView {
    init(title: String, onClose: @escaping () -> Void) {
        self.init(title: title, onClose: onClose) { EmptyView() }
    }
}

/// Mini pierścień postępu zamiast checkboxa.
///
/// Wiersz historii nie jest do odhaczania, więc kółko z ptaszkiem byłoby
/// obietnicą, której ekran nie dotrzyma. Pierścień mówi to samo jedną
/// kreską: pełny w szałwii z ptaszkiem to komplet, częściowy w maśle to
/// lista zamknięta z brakami — a takie właśnie bywają.
struct ShoppingHistoryRing: View {
    let progress: Double
    let isComplete: Bool
    var size: CGFloat = 22

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Rysowana część pierścienia. Startuje od zera i dociąga po wejściu
    /// wiersza — pierścień „nabiega”, tak samo jak licznik nad listą.
    @State private var drawn: Double = 0

    private var color: Color { isComplete ? SCPalette.sage : SCPalette.butter }
    private var lineWidth: CGFloat { 1.5 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.scFaint(scheme).opacity(0.5), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: drawn)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.42, weight: .heavy))
                    .foregroundStyle(color)
                    .opacity(drawn >= 0.999 ? 1 : 0)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else {
                drawn = progress
                return
            }
            withAnimation(.easeOut(duration: 0.55).delay(0.05)) { drawn = progress }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.easeOut(duration: 0.3)) { drawn = newValue }
        }
    }
}

/// Wiersz jednej zamkniętej listy: pierścień · nazwa i data zamknięcia ·
/// „29 z 29” · chevron.
struct ShoppingHistoryListRow: View {
    let entry: ShoppingHistoryEntry
    var isLast: Bool = false
    var onOpen: () -> Void
    var onDelete: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                ShoppingHistoryRing(progress: entry.progress, isComplete: entry.isComplete)

                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.system(size: 15.5, weight: .semibold))
                            .tracking(-0.3)
                            .foregroundStyle(Color.scLabel(scheme))
                            .lineLimit(1)

                        Text("Zamknięta \(ShoppingHistoryFormat.closedAt(entry.closedAt)) · \(PolishPlural.products(entry.total))")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.scFaint(scheme))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(entry.bought) z \(entry.total)")
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .tracking(-0.1)
                        // Niepełna lista mówi to maślanym kolorem — tym samym,
                        // co jej pierścień. Komplet nie ma czym wołać.
                        .foregroundStyle(entry.isComplete ? Color.scMuted(scheme) : SCPalette.butter)
                        .lineLimit(1)
                        .fixedSize()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.scFaint(scheme))
                }
                .frame(minHeight: 56)
                .overlay(alignment: .bottom) {
                    if !isLast {
                        Rectangle()
                            .fill(Color.scRule(scheme))
                            .frame(height: 1)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .accessibilityLabel("\(entry.name), zamknięta \(ShoppingHistoryFormat.closedAt(entry.closedAt)), \(entry.bought) z \(entry.total) kupione")
        .contextMenu {
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Usuń listę z historii", systemImage: "trash")
                }
            }
        }
    }
}

/// Wiersz miesiąca na liście historii.
struct ShoppingHistoryMonthRow: View {
    let month: ShoppingHistoryMonth
    var isLast: Bool = false
    var onOpen: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var meta: String {
        var parts = [PolishPlural.lists(month.listCount), PolishPlural.products(month.productCount)]
        if let last = month.lastClosedAt {
            parts.append("ostatnia \(ShoppingHistoryFormat.closedAt(last))")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(month.name)
                            .font(.system(size: 15.5, weight: .semibold))
                            .tracking(-0.3)
                            .foregroundStyle(Color.scLabel(scheme))
                            .lineLimit(1)

                        if month.isCurrent {
                            ShoppingTag(text: "Ten miesiąc")
                        }
                    }

                    Text(meta)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.scFaint(scheme))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.scFaint(scheme))
            }
            .frame(minHeight: 56)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle()
                        .fill(Color.scRule(scheme))
                        .frame(height: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .accessibilityLabel("\(month.name) \(month.year), \(meta)")
    }
}

/// Tytuł sekcji z licznikiem — „Historia · 5 list”.
struct ShoppingSectionTitle: View {
    let title: String
    var count: String?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(Color.scLabel(scheme))
                .lineLimit(1)

            if let count {
                Text(count)
                    .font(.system(size: 13, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
                    .fixedSize()
            }

            Spacer(minLength: 0)
        }
    }
}
