import SwiftUI

// Klocki arkusza „Filtry” i jego dwóch arkuszy-dzieci (kategoria składników,
// szukanie składnika). Źródło: Claude Design, projekt 43b605d0-…,
// „Scoffie - Przepisy v3 - Filtry.html” → `components/filtry-final.jsx`
// (+ `rf-kit.jsx`, `rf2-kit.jsx`).
//
// Makieta jest wzorem układu, a nie stylu kontrolek: pola wyboru to
// `SCCheckbox`, akcja główna to wariant „soft” (`scSoftCapsule`), krzyżyk to
// `SCSheetCloseButton`, szkło stopki to samo co pigułka „Cel dnia”. Gdzie
// makieta rysuje inaczej niż komponent aplikacji, wygrywa komponent.

// MARK: - Sekcja

/// Etykieta sekcji z opcjonalną wartością po prawej („do 30 min”). Krój jak
/// `EditorialSheetSectionLabel`, żeby arkusz filtrów czytał się jak reszta
/// arkuszy aplikacji.
struct RecipeFilterSection<Trailing: View, Content: View>: View {
    let title: String
    var top: CGFloat = 24
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.scFaint(scheme))
                    .lineLimit(1)

                Spacer(minLength: 8)

                trailing()
                    .font(.system(size: 13, weight: .medium))
                    .tracking(-0.1)
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 10)

            content()
        }
        .padding(.top, top)
    }
}

extension RecipeFilterSection where Trailing == EmptyView {
    init(title: String, top: CGFloat = 24, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, top: top, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - Kafelek z menu (czas, trudność)

/// Kafelek z bieżącą wartością, który po stuknięciu otwiera systemowe menu
/// z opcjami. Czas i trudność stoją obok siebie w jednym rzędzie — cztery
/// opcje segmentu w pół szerokości arkusza zmieściłyby się tylko ścięte.
struct RecipeFilterMenuTile<Value: Hashable>: View {
    struct Item {
        let value: Value
        let title: String
    }

    let title: String
    let icon: String
    let items: [Item]
    @Binding var selection: Value

    @Environment(\.colorScheme) private var scheme

    /// Pierwsza opcja to „dowolny” — wtedy kafelek stoi neutralnie.
    private var isActive: Bool { selection != items.first?.value }
    private var currentTitle: String { items.first { $0.value == selection }?.title ?? "" }

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item.title).tag(item.value)
                }
            }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? SCPalette.terracotta.opacity(scheme == .dark ? 0.2 : 0.14) : Color.scChipBg(scheme))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isActive ? SCPalette.terracotta : Color.scMuted(scheme))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Color.scFaint(scheme))
                    Text(currentTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(isActive ? SCPalette.terracotta : Color.scLabel(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .contentTransition(.interpolate)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Color.scFaint(scheme))
            }
            .padding(.horizontal, 12)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive ? SCPalette.terracotta.opacity(scheme == .dark ? 0.12 : 0.09) : Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isActive ? SCPalette.terracotta.opacity(0.4) : Color.scTileStroke(scheme), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(PlanPressStyle(scale: 0.97))
        .animation(.smooth(duration: 0.22), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityLabel(title)
        .accessibilityValue(currentTitle)
    }
}

// MARK: - Kafelek opcji (Dieta, Cechy)

/// Kafelek 2 × 3: pole wyboru, nazwa, pod nią ile przepisów zostanie po
/// zaznaczeniu. Kafelek z profilu stoi z kłódką i nie da się go odznaczyć —
/// to robi przełącznik „Dopasowane do Ciebie” albo Ustawienia.
struct RecipeFilterOptionTile: View {
    enum Mark { case off, on, locked }

    let title: String
    /// Ile zostanie po zaznaczeniu; `nil` = nie pokazuj (kafelek z profilu).
    let count: Int?
    let mark: Mark
    var accent: Color = SCPalette.terracotta
    var accessibilityDetail: String?
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var isActive: Bool { mark != .off }
    private var tint: Color { mark == .locked ? SCPalette.sage : accent }
    /// Nic by nie zostało — kafelek gaśnie, ale zostaje na miejscu, żeby
    /// siatka nie przeskakiwała przy każdym stuknięciu obok.
    private var isDead: Bool { mark == .off && count == 0 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                markView

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: isActive ? .semibold : .medium))
                        .tracking(-0.25)
                        .foregroundStyle(isActive ? tint : Color.scLabel(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Group {
                        if let count {
                            Text(verbatim: PolishPlural.recipes(count))
                                .contentTransition(.numericText(value: Double(count)))
                        } else {
                            Text("Z Twojego profilu")
                        }
                    }
                    .font(.system(size: 12, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(Color.scFaint(scheme))
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive ? tint.opacity(scheme == .dark ? 0.12 : 0.09) : Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        mark == .on ? tint.opacity(0.4) : (mark == .locked ? .clear : Color.scTileStroke(scheme)),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.97))
        .disabled(mark == .locked || isDead)
        .opacity(isDead ? 0.4 : 1)
        .animation(.smooth(duration: 0.18), value: mark)
        .animation(.smooth(duration: 0.18), value: isDead)
        .animation(.easeOut(duration: 0.3), value: count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAddTraits(mark == .off ? .isButton : [.isButton, .isSelected])
    }

    @ViewBuilder
    private var markView: some View {
        if mark == .locked {
            RoundedRectangle(cornerRadius: 20 / 3, style: .continuous)
                .fill(SCPalette.sage.opacity(scheme == .dark ? 0.22 : 0.16))
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SCPalette.sage)
                )
        } else {
            SCCheckbox(on: mark == .on, accent: accent, size: 20)
        }
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if mark == .locked { parts.append("z Twojego profilu") }
        if let count { parts.append(PolishPlural.recipes(count)) }
        if let accessibilityDetail { parts.append(accessibilityDetail) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Kalorie: histogram z uchwytem

/// Limit kalorii na porcję jako suwak nad rozkładem przepisów.
///
/// Słupki to przedziały po 50 kcal: wysokość = ile przepisów ma taką
/// kaloryczność przy WSZYSTKICH pozostałych filtrach, kolor = czy zmieści
/// się pod limitem. Widać, co kosztuje przesunięcie uchwytu o krok —
/// „do 500” odcina górę rozkładu, a nie abstrakcyjną liczbę. Ostatni słupek
/// to „1000+”; uchwyt na samym końcu = bez limitu.
///
/// Gest idzie OBOK przewijania (`simultaneousGesture`): pionowy ruch palca
/// przewija arkusz, poziomy prowadzi uchwyt. Kierunek rozstrzyga się raz,
/// po pierwszych punktach ruchu; stuknięcie stawia uchwyt w miejscu palca.
struct RecipeFilterKcalSlider: View {
    @Binding var value: Int?
    /// Liczba przepisów w każdym przedziale (`RecipeFilterIndex.kcalHistogram`).
    let histogram: [Int]
    /// Cel z profilu (np. 500–800). `nil` = bez pola celu.
    let goalZone: ClosedRange<Int>?

    @Environment(\.colorScheme) private var scheme
    @State private var axis: Axis? = nil
    @State private var isDragging = false

    private let step = RecipeFilterOptions.calorieStep
    private let limitMax = RecipeFilterOptions.calorieScaleMax
    /// Skala sięga o jeden przedział dalej niż największy limit — tam stoi
    /// słupek „1000+” i tam parkuje uchwyt „bez limitu”.
    private var scaleEnd: Int { limitMax + step }

    private static let barsHeight: CGFloat = 52
    private static let thumb: CGFloat = 26
    private static let barSpacing: CGFloat = 3

    private var thumbValue: Int { value ?? scaleEnd }
    private var inset: CGFloat { Self.thumb / 2 }

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { proxy in
                let width = proxy.size.width
                VStack(spacing: 0) {
                    bars(width: width)
                        .frame(height: Self.barsHeight)
                    track(width: width)
                        .frame(height: Self.thumb + 8)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(drag(width: width))
            }
            .frame(height: Self.barsHeight + Self.thumb + 8)

            labels
                .frame(height: 16)
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kalorie na porcję")
        .accessibilityValue(value.map { "do \($0) kilokalorii" } ?? "bez limitu")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                let next = thumbValue + step
                value = next > limitMax ? nil : next
            case .decrement:
                value = max(RecipeFilterOptions.calorieMinimum, min(thumbValue, scaleEnd) - step)
            @unknown default:
                break
            }
        }
    }

    // MARK: Rysunek

    private func x(_ kcal: Int, width: CGFloat) -> CGFloat {
        let usable = max(1, width - 2 * inset)
        return inset + usable * CGFloat(min(max(kcal, 0), scaleEnd)) / CGFloat(scaleEnd)
    }

    /// Czy przedział `index` (od index·50 do (index+1)·50 kcal) mieści się
    /// pod limitem.
    private func isIncluded(bucket index: Int) -> Bool {
        guard let value else { return true }
        return (index + 1) * step <= value
    }

    private func barColor(included: Bool, empty: Bool) -> Color {
        if included {
            return SCPalette.terracotta.opacity(empty ? 0.25 : (scheme == .dark ? 0.62 : 0.55))
        }
        return Color.scLabel(scheme).opacity(empty ? 0.06 : 0.11)
    }

    private func bars(width: CGFloat) -> some View {
        let peak = max(histogram.max() ?? 0, 1)
        let usable = max(1, width - 2 * inset)
        let count = max(histogram.count, 1)
        let barWidth = max(2, (usable - Self.barSpacing * CGFloat(count - 1)) / CGFloat(count))

        return HStack(alignment: .bottom, spacing: Self.barSpacing) {
            ForEach(Array(histogram.enumerated()), id: \.offset) { index, recipes in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(barColor(included: isIncluded(bucket: index), empty: recipes == 0))
                    .frame(
                        width: barWidth,
                        height: recipes == 0 ? 2 : max(4, Self.barsHeight * CGFloat(recipes) / CGFloat(peak))
                    )
            }
        }
        .frame(width: usable, height: Self.barsHeight, alignment: .bottomLeading)
        .padding(.horizontal, inset)
        .animation(.smooth(duration: 0.35), value: histogram)
        .animation(isDragging ? nil : .smooth(duration: 0.2), value: value)
    }

    private func track(width: CGFloat) -> some View {
        let thumbX = x(thumbValue, width: width)
        let zoneStart = goalZone.map { x($0.lowerBound, width: width) } ?? 0
        let zoneEnd = goalZone.map { x(min($0.upperBound, scaleEnd), width: width) } ?? 0

        return ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(Color.scBarTrack(scheme))
                .frame(width: max(0, width - 2 * inset), height: 4)
                .offset(x: inset)

            if goalZone != nil {
                Capsule(style: .continuous)
                    .fill(SCPalette.sage.opacity(0.75))
                    .frame(width: max(0, zoneEnd - zoneStart), height: 4)
                    .offset(x: zoneStart)
            }

            Capsule(style: .continuous)
                .fill(SCPalette.terracotta)
                .frame(width: max(0, thumbX - inset), height: 4)
                .offset(x: inset)

            Circle()
                .fill(.white)
                .frame(width: Self.thumb, height: Self.thumb)
                .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.2), radius: 5, x: 0, y: 2)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .scaleEffect(isDragging ? 1.14 : 1)
                .offset(x: thumbX - Self.thumb / 2)
                .animation(.spring(response: 0.26, dampingFraction: 0.7), value: isDragging)
        }
        .frame(width: width, height: Self.thumb + 8)
    }

    private var labels: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                Text(verbatim: "0")
                    .fixedSize()
                    .position(x: inset, y: 8)
                Text(verbatim: "500")
                    .fixedSize()
                    .position(x: x(500, width: width), y: 8)
                    .opacity(goalLabelCovers500(width: width) ? 0 : 1)
                if let zone = goalZone {
                    Text(verbatim: "Twój cel \(zone.lowerBound)–\(zone.upperBound)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(SCPalette.sage)
                        .fixedSize()
                        .position(x: goalLabelX(zone: zone, width: width), y: 8)
                }
                Text(verbatim: "\(limitMax)+")
                    .fixedSize()
                    .position(x: width - inset - 4, y: 8)
            }
        }
        .font(.system(size: 11.5))
        .monospacedDigit()
        .foregroundStyle(Color.scFaint(scheme))
    }

    /// Podpis celu pod środkiem pola, ale nie na „0” ani na „1000+”.
    private func goalLabelX(zone: ClosedRange<Int>, width: CGFloat) -> CGFloat {
        let mid = x((zone.lowerBound + min(zone.upperBound, scaleEnd)) / 2, width: width)
        return min(max(mid, 70), width - 84)
    }

    private func goalLabelCovers500(width: CGFloat) -> Bool {
        guard let zone = goalZone else { return false }
        return abs(goalLabelX(zone: zone, width: width) - x(500, width: width)) < 70
    }

    // MARK: Gest

    private func snappedValue(at locationX: CGFloat, width: CGFloat) -> Int? {
        let usable = max(1, width - 2 * inset)
        let raw = Double((locationX - inset) / usable) * Double(scaleEnd)
        let snapped = Int((raw / Double(step)).rounded()) * step
        if snapped > limitMax { return nil }
        return max(RecipeFilterOptions.calorieMinimum, snapped)
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if axis == nil {
                    let moved = hypot(gesture.translation.width, gesture.translation.height)
                    guard moved > 6 else { return }
                    axis = abs(gesture.translation.width) > abs(gesture.translation.height) ? .horizontal : .vertical
                    if axis == .horizontal { isDragging = true }
                }
                guard axis == .horizontal else { return }
                let next = snappedValue(at: gesture.location.x, width: width)
                if next != value {
                    // Za palcem bez sprężyny — animacja by się za nim wlokła.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { value = next }
                }
            }
            .onEnded { gesture in
                defer {
                    axis = nil
                    isDragging = false
                }
                // Stuknięcie: uchwyt dojeżdża do palca.
                guard axis == nil else { return }
                let next = snappedValue(at: gesture.location.x, width: width)
                guard next != value else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { value = next }
            }
    }
}

// MARK: - Pływająca stopka

/// Szklana kapsuła nad dołem arkusza — ile zostaje i akcja. To samo szkło co
/// pigułka „Cel dnia” i dolne menu: treść przewija się pod nią i jest przez
/// nią widać, a warstwa tła pod szkłem przygasza ją do rozmytej plamy.
struct RecipeFilterFloatingBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            leading()
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .padding(7)
        .frame(minHeight: 66)
        .glassEffect(
            .regular.tint(Color.scPageBase(scheme).opacity(0.35)),
            in: .capsule
        )
        .background(Color.scPageBase(scheme).opacity(0.72), in: .capsule)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        // Wygaszenie nad kapsułą: ostatnie wiersze listy nie urywają się na
        // krawędzi szkła, tylko w nim giną.
        .background(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: Color.scPageBase(scheme).opacity(0), location: 0),
                    .init(color: Color.scPageBase(scheme).opacity(0.75), location: 0.55),
                    .init(color: Color.scPageBase(scheme).opacity(0.96), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 150)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }
}

/// Akcja w stopce — wariant „soft”, niższy niż `SCSoftButton`, bo stoi
/// w kapsule obok liczników, a nie sam na dole ekranu.
struct RecipeFilterFooterButton: View {
    let title: String
    var trailingIcon: String? = "chevron.right"
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .tracking(-0.3)
                    .lineLimit(1)
                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundStyle(SCPalette.terracotta)
            .padding(.horizontal, 22)
            .frame(height: 52)
            .scSoftCapsule()
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.96))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.smooth(duration: 0.18), value: isEnabled)
    }
}

/// „Wyczyść” obok krzyżyka — pojawia się dopiero, gdy jest co czyścić.
struct RecipeFilterClearButton: View {
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: compact ? 11 : 12, weight: .bold))
                Text("Wyczyść")
                    .font(.system(size: compact ? 13 : 14, weight: .semibold))
                    .tracking(-0.2)
            }
            .foregroundStyle(SCPalette.terracotta)
            .padding(.horizontal, compact ? 11 : 13)
            .frame(height: compact ? 32 : 36)
            .scSoftCapsule()
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .accessibilityLabel("Wyczyść filtry")
    }
}

// MARK: - Wykluczenia: chipy i plakietka

/// Wykluczony składnik jako chip. Mały — w wierszu kategorii (bez krzyżyka),
/// duży — w pasku „Wykluczone” (z krzyżykiem, stuknięcie przywraca).
/// Z profilu — z kłódką, w szałwii, bez krzyżyka.
struct RecipeFilterExclusionChip: View {
    let title: String
    var locked: Bool = false
    var small: Bool = false
    /// Świeżo dodany — mocniej podświetlony przez chwilę.
    var fresh: Bool = false

    @Environment(\.colorScheme) private var scheme

    private var tint: Color { locked ? SCPalette.sage : SCPalette.terracotta }

    var body: some View {
        HStack(spacing: small ? 4 : 6) {
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: small ? 8.5 : 9.5, weight: .bold))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.system(size: small ? 12.5 : 13, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Color.scLabel(scheme))
                .lineLimit(1)
            if !locked && !small {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(tint)
            }
        }
        .padding(.leading, small ? (locked ? 7 : 9) : (locked ? 9 : 11))
        .padding(.trailing, small ? 9 : (locked ? 11 : 10))
        .frame(height: small ? 24 : 30)
        .background(Capsule(style: .continuous).fill(tint.opacity(fresh ? 0.28 : (scheme == .dark ? 0.14 : 0.11))))
        .overlay(Capsule(style: .continuous).strokeBorder(tint.opacity(fresh ? 0.6 : 0.3), lineWidth: 1))
        .fixedSize()
        .animation(.easeOut(duration: 0.6), value: fresh)
    }
}

/// „+2” / „+6 więcej” po chipach, które się nie zmieściły.
struct RecipeFilterMoreChip: View {
    let label: String
    var small: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(label)
            .font(.system(size: small ? 12.5 : 13, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Color.scMuted(scheme))
            .padding(.horizontal, small ? 8 : 11)
            .frame(height: small ? 24 : 30)
            .background(Capsule(style: .continuous).fill(Color.scChipBg(scheme)))
            .fixedSize()
    }
}

/// Liczba wykluczeń w wierszu — pełny akcent, bo to jedyna rzecz, która
/// w liście kategorii mówi „tu coś jest”.
struct RecipeFilterCountBadge: View {
    let count: Int
    var locked: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8.5, weight: .bold))
            }
            Text(verbatim: "\(count)")
                .font(.system(size: 12, weight: .heavy))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, locked ? 7 : 6)
        .frame(minWidth: 20, minHeight: 20)
        .background(Capsule(style: .continuous).fill(locked ? SCPalette.sage : SCPalette.terracotta))
        .animation(.easeOut(duration: 0.25), value: count)
    }
}

/// Chipy wykluczeń w jednym wierszu: tyle, ile się mieści (maks. 3), reszta
/// jako „+N”. Wiersz nie rośnie w pionie, niezależnie od liczby wykluczeń.
struct RecipeFilterChipLine: View {
    struct Chip: Identifiable {
        let id: String
        let title: String
        var locked: Bool = false
    }

    let chips: [Chip]
    var maxVisible: Int = 3

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: min(maxVisible, chips.count), through: 1, by: -1)), id: \.self) { visible in
                line(visible: visible)
            }
            // Ostateczność: nawet jeden chip się nie mieści (bardzo długa
            // nazwa przy dużym piśmie) — sama liczba.
            RecipeFilterMoreChip(label: "\(chips.count)", small: true)
        }
    }

    private func line(visible: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(chips.prefix(visible)) { chip in
                RecipeFilterExclusionChip(title: chip.title, locked: chip.locked, small: true)
            }
            if chips.count > visible {
                RecipeFilterMoreChip(label: "+\(chips.count - visible)", small: true)
            }
        }
    }
}

// MARK: - Pole szukania

/// Pole szukania składnika. W arkuszu filtrów jest tylko wejściem do arkusza
/// szukania (`onTap`), w arkuszach-dzieciach — prawdziwym polem.
struct RecipeFilterSearchField: View {
    let prompt: String
    var text: Binding<String>? = nil
    var focus: FocusState<Bool>.Binding? = nil
    var isActive: Bool = false
    var onTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let onTap {
            Button(action: onTap) { field }
                .buttonStyle(PlanPressStyle(scale: 0.985))
        } else {
            field
        }
    }

    private var field: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.scFaint(scheme))

            if let text {
                textField(text)
                if !text.wrappedValue.isEmpty {
                    Button {
                        text.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.scFaint(scheme))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Wyczyść pole")
                    .transition(.opacity)
                }
            } else {
                Text(prompt)
                    .font(.system(size: 15))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scFaint(scheme))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.scChipBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isActive ? SCPalette.terracotta.opacity(0.6) : Color.scTileStroke(scheme),
                    lineWidth: isActive ? 1.5 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.smooth(duration: 0.18), value: isActive)
        .animation(.smooth(duration: 0.18), value: text?.wrappedValue.isEmpty ?? true)
    }

    @ViewBuilder
    private func textField(_ text: Binding<String>) -> some View {
        let field = TextField(text: text) {
            Text(prompt).foregroundStyle(Color.scFaint(scheme))
        }
        .font(.system(size: 16))
        .tracking(-0.2)
        .foregroundStyle(Color.scLabel(scheme))
        .tint(SCPalette.terracotta)
        .submitLabel(.search)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)

        if let focus {
            field.focused(focus)
        } else {
            field
        }
    }
}

// MARK: - Wiersz składnika

/// Składnik albo grupa w arkuszu kategorii i w wynikach szukania.
/// Wykluczony: ikona zakazu i nazwa w terakocie, po prawej „Przywróć”.
/// Reszta: po prawej „Wyklucz”.
struct RecipeFilterIngredientRow: View {
    enum RowState: Equatable {
        case available
        case excluded
        /// Wykluczony razem z całą grupą — „Przywróć” wyjmuje go z grupy.
        case excludedByGroup
    }

    let title: String
    let subtitle: String
    let state: RowState
    var isGroup: Bool = false
    /// Dopasowanie do pogrubienia (znak startu i długość).
    var highlight: (offset: Int, length: Int)? = nil
    /// Wcięcie rodzaju pod grupą.
    var indent: CGFloat = 0
    /// Rozwinięcie rodzajów grupy — `nil` = wiersz bez linku.
    var expandTitle: String? = nil
    var isExpanded: Bool = false
    var showsRule: Bool = true
    let onToggle: () -> Void
    var onExpand: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    private var isExcluded: Bool { state != .available }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    if isExcluded {
                        Image(systemName: "nosign")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(state == .excluded ? SCPalette.terracotta : Color.scFaint(scheme))
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                    titleText
                        .font(.system(size: 15.5, weight: isExcluded ? .semibold : .medium))
                        .tracking(-0.3)
                        .foregroundStyle(state == .excluded ? SCPalette.terracotta : Color.scLabel(scheme))
                        .lineLimit(1)

                    if isGroup {
                        Text("Grupa")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.scMuted(scheme))
                            .padding(.horizontal, 7)
                            .frame(height: 19)
                            .background(Capsule(style: .continuous).fill(Color.scChipBg(scheme)))
                            .fixedSize()
                    }
                }

                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)

                if let expandTitle, let onExpand {
                    Button(action: onExpand) {
                        HStack(spacing: 3) {
                            Text(expandTitle)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(SCPalette.terracotta)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 1)
                    .accessibilityHint(isExpanded ? "Zwija rodzaje" : "Rozwija rodzaje")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actionButton
        }
        .padding(.vertical, 8)
        .padding(.leading, indent)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) {
            if showsRule {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    .padding(.leading, indent)
            }
        }
        .animation(.smooth(duration: 0.2), value: state)
    }

    private var titleText: Text {
        guard let highlight, highlight.offset >= 0, highlight.offset + highlight.length <= title.count else {
            return Text(title)
        }
        let start = title.index(title.startIndex, offsetBy: highlight.offset)
        let end = title.index(start, offsetBy: highlight.length)
        return Text(title[..<start]) + Text(title[start..<end]).fontWeight(.bold) + Text(title[end...])
    }

    private var actionButton: some View {
        Button(action: onToggle) {
            HStack(spacing: 5) {
                if !isExcluded {
                    Image(systemName: "nosign")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(isExcluded ? "Przywróć" : "Wyklucz")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.1)
            }
            .foregroundStyle(isExcluded ? Color.scLabel(scheme) : SCPalette.terracotta)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background {
                if isExcluded {
                    Capsule(style: .continuous).fill(Color.scChipBg(scheme))
                        .overlay(Capsule(style: .continuous).strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
                } else {
                    Color.clear.scSoftCapsule()
                }
            }
            .contentShape(Capsule(style: .continuous))
            .contentTransition(.opacity)
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .accessibilityLabel("\(isExcluded ? "Przywróć" : "Wyklucz") \(title)")
    }
}

// MARK: - Przełączanie wykluczeń

extension RecipeFilterOptions {
    /// Stan wiersza składnika: wykluczony sam, razem z grupą albo dostępny.
    func rowState(of exclusion: IngredientExclusion, parent: IngredientGroup? = nil) -> RecipeFilterIngredientRow.RowState {
        if excludedIngredients.contains(exclusion) { return .excluded }
        if let parent, excludedIngredients.contains(parent.exclusion) { return .excludedByGroup }
        return .available
    }

    mutating func toggle(item: IngredientItem, in parent: IngredientGroup?) {
        toggle(
            exclusion: item.exclusion,
            groupMembers: parent?.members.map(\.exclusion) ?? [],
            parentGroup: parent?.exclusion
        )
    }

    mutating func toggle(group: IngredientGroup) {
        toggle(exclusion: group.exclusion, groupMembers: group.members.map(\.exclusion))
    }
}
