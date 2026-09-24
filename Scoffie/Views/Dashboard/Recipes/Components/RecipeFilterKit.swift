import SwiftUI

// Klocki arkusza „Filtry”, filtrów kategorii i arkuszy wykluczania składników.
// Źródło: Claude Design, projekt 43b605d0-…, „Scoffie - Przepisy v3 -
// Filtry.html” → `components/filtry-final.jsx` (+ `rf-kit.jsx`, `rf2-kit.jsx`),
// dalej przerobione po uwagach Rafała (23.09.2026): wykres kalorii bez
// osobnego suwaka, kafelki ze zdjęciem dania, składniki jako pigułki.
//
// Makieta jest wzorem układu, a nie stylu kontrolek: akcja główna to wariant
// „soft” (`scSoftCapsule`), krzyżyk to `SCSheetCloseButton`, stopka to wspólna
// stopka arkuszy (`scSheetFooter`), a kafelek wyboru — `SCChoiceTile`. Gdzie
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

// MARK: - Nagłówek arkusza filtrów

/// Nagłówek „Filtrów” i filtrów kategorii: wspólny nagłówek arkusza
/// (`EditorialSheetHeader` z kafelkiem w tincie akcentu i zdaniem o zasięgu)
/// i „Wyczyść” obok krzyżyka.
///
/// Zasięg stał dotąd osobnym wierszem pod nagłówkiem („Wszystkie przepisy ·
/// Działają w każdej kategorii”), a nagłówek był samym słowem „Filtry” —
/// Rafał (23.09.2026): „dodaj ciut więcej tekstu i ulepsz to wizualnie, ale
/// nie przesadzaj”. Linijka „Aktywne: dieta, cechy” pod zasięgiem zniknęła
/// w rundzie 9 („niepotrzebne to jest”) — co jest włączone, widać po samych
/// kafelkach, a „Wyczyść” mówi, że jest co czyścić.
struct RecipeFilterHeader: View {
    let icon: String
    let eyebrow: String
    let title: String
    /// Gdzie filtry działają — jedno zdanie.
    let scope: String
    var accent: Color = SCPalette.terracotta
    let canClear: Bool
    let onClear: () -> Void
    let onClose: () -> Void

    var body: some View {
        EditorialSheetHeader(
            eyebrow: eyebrow,
            title: title,
            icon: icon,
            accent: accent,
            subtitle: scope,
            onClose: onClose
        ) {
            if canClear {
                RecipeFilterClearButton(action: onClear)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.22), value: canClear)
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

// MARK: - Kafelek opcji (Dieta, Cechy, filtry kategorii)

/// Kafelek 2 × 3: zdjęcie dania z tą cechą, nazwa, pod nią ile przepisów
/// zostanie po zaznaczeniu. Kafelek z profilu stoi z kłódką i nie da się go
/// odznaczyć — to robi przełącznik „Dopasowane do Ciebie” albo Ustawienia.
///
/// Rysunek jest wspólny (`SCChoiceTile`); tu dochodzi zdjęcie, liczba
/// przepisów i gaśnięcie kafelka, po którym nic by nie zostało.
struct RecipeFilterOptionTile: View {
    let title: String
    /// Ile zostanie po zaznaczeniu; `nil` = nie pokazuj (kafelek z profilu).
    let count: Int?
    let mark: SCChoiceMark
    var accent: Color = SCPalette.terracotta
    /// Przepis, którego zdjęcie stoi w kafelku — przykład dania z tą cechą
    /// (`RecipeFilterCovers`). `nil` = glif.
    var cover: Recipe? = nil
    /// Glif, gdy nie ma zdjęcia.
    var icon: String = "fork.knife"
    var accessibilityDetail: String?
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    /// Nic by nie zostało — kafelek gaśnie, ale zostaje na miejscu, żeby
    /// siatka nie przeskakiwała przy każdym stuknięciu obok.
    private var isDead: Bool { mark == .off && count == 0 }

    var body: some View {
        SCChoiceTile(
            title: title,
            mark: mark,
            accent: accent,
            isDimmed: isDead,
            accessibilityValue: accessibilityValue,
            action: action
        ) {
            RecipeFilterCoverThumb(recipe: cover, icon: icon, accent: accent)
        } detail: {
            if let count {
                (Text(verbatim: "\(count)")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.scLabel(scheme))
                    + Text(verbatim: " \(PolishPlural.recipesNoun(count))"))
                    .contentTransition(.numericText(value: Double(count)))
            } else {
                Text("Z profilu")
            }
        }
        .animation(.easeOut(duration: 0.3), value: count)
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if mark == .locked { parts.append("z Twojego profilu") }
        if let count { parts.append(PolishPlural.recipes(count)) }
        if let accessibilityDetail { parts.append(accessibilityDetail) }
        return parts.joined(separator: ", ")
    }
}

/// Miniatura kafelka: zdjęcie przepisu z CAŁYM talerzem, a bez zdjęcia glif
/// w tincie akcentu.
struct RecipeFilterCoverThumb: View {
    let recipe: Recipe?
    let icon: String
    let accent: Color

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let url = recipe?.imageURL {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    // Bez przybliżenia. Zdjęcia katalogu są poziome
                    // (1344 × 768) z talerzem na środku, zajmującym ~85 %
                    // wysokości, więc samo wypełnienie kwadratu wycina środek
                    // o boku wysokości zdjęcia — a w nim cały talerz z wąskim
                    // marginesem blatu. Dawne przybliżenie 1,45 zostawiało
                    // okno 530 px i ucinało rant każdego talerza, także miski
                    // z zupą i deski (sprawdzone na 15 zdjęciach katalogu;
                    // Rafał, 23.09.2026: „trochę się ucinają”).
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            accent.opacity(scheme == .dark ? 0.16 : 0.12)
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
        }
    }
}

/// Kafelki po dwa w wierszu — WSZYSTKIE tej samej szerokości i wysokości.
///
/// `LazyVGrid` ustawiał komórki na środku wiersza, a potem wiersze `HStack`
/// z `fixedSize` wyrównywały wysokość tylko w obrębie wiersza: rząd
/// z „Bogate w błonnik” w dwóch liniach stał wyższy od rzędu z „Keto”.
/// Teraz siatka (`RecipeFilterTileGridLayout`) mierzy każdy kafelek przy
/// szerokości kolumny i daje wszystkim wysokość najwyższego — przy większej
/// czcionce albo węższym ekranie rośnie cała siatka naraz. Nieparzysty
/// ostatni kafelek zostaje w lewej kolumnie. Leniwość nie jest potrzebna:
/// sekcja ma najwyżej kilka kafelków.
struct RecipeFilterTileGrid<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    @ViewBuilder var tile: (Item) -> Tile

    var body: some View {
        RecipeFilterTileGridLayout(columns: 2, spacing: 8) {
            ForEach(items) { item in
                tile(item)
            }
        }
    }
}

/// Siatka o równych komórkach: szerokość = `(szerokość − odstępy) / kolumny`,
/// wysokość = najwyższy kafelek zmierzony przy TEJ szerokości (nie przy
/// nieskończonej — nazwa w dwóch liniach musi się zmieścić). Kafelek
/// (`SCChoiceTile`) jest elastyczny w obu osiach i wypełnia komórkę.
private struct RecipeFilterTileGridLayout: Layout {
    var columns: Int = 2
    var spacing: CGFloat = 8

    private func columnWidth(_ total: CGFloat) -> CGFloat {
        guard columns > 0 else { return 0 }
        return max(0, (total - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    private func rowCount(_ subviews: Subviews) -> Int {
        guard columns > 0 else { return 0 }
        return (subviews.count + columns - 1) / columns
    }

    private func cellHeight(column: CGFloat, subviews: Subviews) -> CGFloat {
        subviews
            .map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }
            .max() ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rowCount(subviews)
        guard rows > 0 else { return .zero }

        let column: CGFloat
        let width: CGFloat
        if let proposed = proposal.width, proposed.isFinite {
            width = proposed
            column = columnWidth(proposed)
        } else {
            // Sonda bez szerokości — kolumna szeroka jak najszerszy kafelek,
            // nigdy nieskończoność.
            column = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
            width = column * CGFloat(columns) + spacing * CGFloat(columns - 1)
        }

        let height = cellHeight(column: column, subviews: subviews)
        return CGSize(
            width: width,
            height: height * CGFloat(rows) + spacing * CGFloat(rows - 1)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard columns > 0 else { return }
        let column = columnWidth(bounds.width)
        let height = cellHeight(column: column, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            let row = index / columns
            let col = index % columns
            subview.place(
                at: CGPoint(
                    x: bounds.minX + CGFloat(col) * (column + spacing),
                    y: bounds.minY + CGFloat(row) * (height + spacing)
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: column, height: height)
            )
        }
    }
}

// MARK: - Kalorie: wykres, który jest suwakiem

/// Limit kalorii na porcję jako wykres rozkładu przepisów, który sam jest
/// suwakiem — bez osobnego toru z wypełnieniem pod spodem.
///
/// Słupki to przedziały po 50 kcal: wysokość = ile przepisów ma taką
/// kaloryczność przy WSZYSTKICH pozostałych filtrach, kolor = czy mieści się
/// pod limitem. Pionowa kreska z gałką na osi to granica: palec prowadzi ją
/// po całym wykresie, stuknięcie stawia ją w miejscu palca. Ostatni słupek
/// to „1000+”; kreska za nim = bez limitu.
///
/// Wcześniej pod wykresem był osobny suwak (tor z terakotowym wypełnieniem
/// i białą gałką), a cel siedział w trzech miejscach naraz: pasmo za
/// słupkami, odcinek toru i linijka legendy. Rafał (23.09): „możesz
/// zrezygnować z tego Progressu, zrób to ładniej”. Teraz cel to szałwiowy
/// odcinek NA osi z podpisem „500 · Twój cel · 800”, a nad nim ledwie widoczna
/// poświata — kreska limitu nigdy nie przecina napisu.
///
/// Liczba na górze karty to sam limit; krzyżyk obok niej go zdejmuje,
/// a „Do celu” stawia go na górnej granicy celu.
///
/// Gest idzie OBOK przewijania (`simultaneousGesture`): pionowy ruch palca
/// przewija arkusz, poziomy prowadzi kreskę. Kierunek rozstrzyga się raz, po
/// pierwszych punktach ruchu. W trakcie ruchu kreska idzie za palcem bez
/// animacji, ale zmiana wartości NIE wyłącza animacji w transakcji — liczby
/// w stopce, na kafelkach i na górze karty rolują się razem z palcem.
struct RecipeFilterKcalChart: View {
    @Binding var value: Int?
    /// Liczba przepisów w każdym przedziale (`RecipeFilterIndex.kcalHistogram`).
    let histogram: [Int]
    /// Cel z profilu na jeden posiłek (np. 500–800). `nil` = bez celu.
    let goalZone: ClosedRange<Int>?

    @Environment(\.colorScheme) private var scheme
    @State private var axis: Axis? = nil
    @State private var isDragging = false
    /// Czy palec jest na wykresie. `GestureState` wraca do `false` także
    /// wtedy, gdy gest zostanie przerwany (przewijanie przejęło palec) —
    /// `onEnded` wtedy nie przychodzi i bez tego `axis` zostawałby na
    /// następny ruch, a gałka powiększona.
    @GestureState private var isTouching = false

    private let step = RecipeFilterOptions.calorieStep
    private let limitMax = RecipeFilterOptions.calorieScaleMax
    /// Skala sięga o jeden przedział dalej niż największy limit — tam stoi
    /// słupek „1000+” i tam parkuje kreska „bez limitu”.
    private var scaleEnd: Int { limitMax + step }

    private static let chartHeight: CGFloat = 96
    private static let barsMax: CGFloat = 74
    private static let barGap: CGFloat = 3
    /// Gałka na osi: białe koło 16 pt w terakotowym pierścieniu 3 pt.
    private static let knob: CGFloat = 22
    /// Podpisy osi: odstęp od osi (gałka wystaje pod nią 11 pt) i wysokość.
    private static let axisGap: CGFloat = 10
    private static let axisHeight: CGFloat = 16
    /// Wykres z podpisami — cała ta wysokość łapie palec, więc gałkę da się
    /// chwycić także za dolną połowę, która wystaje pod oś.
    private static var totalHeight: CGFloat { chartHeight + axisGap + axisHeight }

    private var thumbValue: Int { value ?? scaleEnd }
    /// Margines skali po bokach — gałka na skraju nie wychodzi poza kartę.
    private var inset: CGFloat { 8 }

    /// Pole celu przycięte do skali — cel „do 1200” kończy się na „1000+”.
    private var visibleZone: ClosedRange<Int>? {
        guard let goalZone, goalZone.lowerBound < scaleEnd else { return nil }
        return max(0, goalZone.lowerBound)...min(scaleEnd, goalZone.upperBound)
    }

    /// Gdzie „Do celu” stawia limit: górna granica celu, najwyżej 1000.
    private var goalTarget: Int? {
        guard let goalZone else { return nil }
        return min(goalZone.upperBound, limitMax)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow

            chart
                .padding(.top, 14)
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.scTileStroke(scheme), lineWidth: 1)
        )
        .sensoryFeedback(.selection, trigger: value)
        .onChange(of: isTouching) { _, touching in
            guard !touching else { return }
            axis = nil
            isDragging = false
        }
    }

    // MARK: Góra karty

    /// Limit dużą liczbą, obok krzyżyk, który go zdejmuje; po prawej „Do celu”,
    /// gdy jest cel i limit na nim nie stoi.
    private var topRow: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack(alignment: .leading) {
                if let value {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        // Wartość czyta VoiceOver z wykresu — tu byłaby drugi raz.
                        Group {
                            Text("do")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.scMuted(scheme))
                            Text(verbatim: "\(value)")
                                .font(.system(size: 26, weight: .heavy))
                                .tracking(-0.6)
                                .monospacedDigit()
                                .foregroundStyle(Color.scLabel(scheme))
                                .contentTransition(.numericText(value: Double(value)))
                            Text("kcal")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.scMuted(scheme))
                        }
                        .accessibilityHidden(true)

                        clearButton
                            .alignmentGuide(.firstTextBaseline) { dimensions in
                                dimensions[VerticalAlignment.center] + 5
                            }
                    }
                    .transition(.opacity)
                } else {
                    Text("Bez limitu")
                        .font(.system(size: 22, weight: .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(Color.scLabel(scheme))
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let target = goalTarget, value != target {
                goalChip(target: target)
            }
        }
        .frame(minHeight: 32)
        // Także w trakcie ruchu palca — cyfry limitu rolują się z kreską.
        .animation(.smooth(duration: 0.2), value: value)
    }

    /// Zdejmuje limit jednym stuknięciem — bez przeciągania kreski za
    /// „1000+”. Krzyżyk jak w polu szukania: czyści to, obok czego stoi.
    private var clearButton: some View {
        Button {
            set(nil)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.scFaint(scheme))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.9))
        .accessibilityLabel("Zdejmij limit kalorii")
    }

    private func goalChip(target: Int) -> some View {
        Button {
            set(target)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "scope")
                    .font(.system(size: 11.5, weight: .bold))
                Text("Do celu")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.1)
            }
            .foregroundStyle(SCPalette.sage)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .scSoftCapsule(SCPalette.sage)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .accessibilityLabel("Ustaw limit na \(target) kilokalorii, górną granicę Twojego celu")
    }

    private func set(_ newValue: Int?) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { value = newValue }
    }

    // MARK: Wykres

    private var chart: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                if let zone = visibleZone {
                    goalWash(zone: zone, width: width)
                }
                bars(width: width)
                baseline(width: width)
                axisLabels(width: width)
                    .offset(y: Self.chartHeight + Self.axisGap)
                marker(width: width)
            }
            .frame(width: width, height: Self.totalHeight, alignment: .topLeading)
            .contentShape(Rectangle())
            .simultaneousGesture(drag(width: width))
        }
        .frame(height: Self.totalHeight)
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
            return SCPalette.terracotta.opacity(empty ? 0.3 : 0.9)
        }
        return Color.scLabel(scheme).opacity(empty ? 0.06 : 0.11)
    }

    private func barHeight(_ recipes: Int, peak: Int) -> CGFloat {
        recipes == 0 ? 2 : max(4, Self.barsMax * CGFloat(recipes) / CGFloat(peak))
    }

    /// Słupki stoją dokładnie na swoich przedziałach skali (a nie w `HStack`
    /// z odstępem), więc kreska limitu trafia zawsze w szczelinę między nimi.
    private func bars(width: CGFloat) -> some View {
        let peak = max(histogram.max() ?? 0, 1)

        return ZStack(alignment: .bottomLeading) {
            ForEach(Array(histogram.enumerated()), id: \.offset) { index, recipes in
                let start = x(index * step, width: width) + Self.barGap / 2
                let end = x((index + 1) * step, width: width) - Self.barGap / 2
                UnevenRoundedRectangle(
                    topLeadingRadius: 3,
                    bottomLeadingRadius: 1,
                    bottomTrailingRadius: 1,
                    topTrailingRadius: 3,
                    style: .continuous
                )
                .fill(barColor(included: isIncluded(bucket: index), empty: recipes == 0))
                .frame(width: max(1, end - start), height: barHeight(recipes, peak: peak))
                .offset(x: start)
            }
        }
        .frame(width: width, height: Self.chartHeight, alignment: .bottomLeading)
        .animation(.smooth(duration: 0.35), value: histogram)
        .animation(isDragging ? nil : .smooth(duration: 0.2), value: value)
        .accessibilityHidden(true)
    }

    /// Ledwie widoczna poświata nad odcinkiem celu — mówi „tu”, ale nie
    /// zasłania słupków i nie niesie napisu, który przecinałaby kreska.
    private func goalWash(zone: ClosedRange<Int>, width: CGFloat) -> some View {
        let start = x(zone.lowerBound, width: width)
        let end = x(zone.upperBound, width: width)

        return LinearGradient(
            colors: [SCPalette.sage.opacity(0), SCPalette.sage.opacity(scheme == .dark ? 0.12 : 0.10)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: max(0, end - start), height: Self.chartHeight)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 6,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 6,
                style: .continuous
            )
        )
        .offset(x: start)
        .accessibilityHidden(true)
    }

    /// Oś: włoskowa linia na całą szerokość, na niej szałwiowy odcinek celu.
    private func baseline(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.scRule(scheme))
                .frame(width: width, height: 1)

            if let zone = visibleZone {
                let start = x(zone.lowerBound, width: width)
                let end = x(zone.upperBound, width: width)
                Capsule(style: .continuous)
                    .fill(SCPalette.sage)
                    .frame(width: max(4, end - start), height: 4)
                    .offset(x: start)
            }
        }
        .frame(width: width, height: 4)
        .offset(y: Self.chartHeight - 2)
        .accessibilityHidden(true)
    }

    private func marker(width: CGFloat) -> some View {
        let markerX = x(thumbValue, width: width)
        let knob = Self.knob

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(SCPalette.terracotta)
                .frame(width: 2, height: Self.chartHeight)
                .offset(x: markerX - 1)

            Circle()
                .fill(SCPalette.terracotta)
                .frame(width: knob, height: knob)
                .overlay(Circle().fill(Color.white).padding(3))
                .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.2), radius: 4, x: 0, y: 2)
                .scaleEffect(isDragging ? 1.2 : 1)
                .animation(.spring(response: 0.26, dampingFraction: 0.7), value: isDragging)
                .offset(x: markerX - knob / 2, y: Self.chartHeight - knob / 2)
        }
        .frame(width: width, height: Self.chartHeight, alignment: .topLeading)
        // Za palcem bez sprężyny — animacja by się za nim wlokła. Wyłączona
        // tylko TU, a nie dla całej zmiany, żeby liczby przepisów wokół dalej
        // rolowały się w trakcie ruchu.
        .animation(isDragging ? nil : .spring(response: 0.34, dampingFraction: 0.82), value: thumbValue)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Podpisy osi

    private struct AxisMark: Identifiable {
        let id: String
        let x: CGFloat
        let text: String
        var isGoal = false

        /// Szerokość napisu z grubsza (11 pt, cyfry o stałej szerokości) —
        /// tyle, żeby dwa podpisy nie weszły na siebie.
        var approximateWidth: CGFloat { CGFloat(text.count) * 6.6 }
    }

    /// Bez celu: 0 · 250 · 500 · 750 · 1000+. Z celem: najpierw jego granice
    /// w szałwii i „Twój cel” między nimi, potem skrajne liczby — każdy
    /// podpis tylko tam, gdzie nie wchodzi na już postawiony (cel 950–1100
    /// zostawia samo „950”, a nie „950” wklejone w „1000+”).
    private func axisMarks(width: CGFloat) -> [AxisMark] {
        let endX = width - inset - 6
        let maxText = "\(limitMax)+"
        guard let zone = visibleZone else {
            return [
                AxisMark(id: "0", x: inset, text: "0"),
                AxisMark(id: "250", x: x(250, width: width), text: "250"),
                AxisMark(id: "500", x: x(500, width: width), text: "500"),
                AxisMark(id: "750", x: x(750, width: width), text: "750"),
                AxisMark(id: "max", x: endX, text: maxText)
            ]
        }

        let lower = x(zone.lowerBound, width: width)
        let reachesEnd = zone.upperBound >= scaleEnd
        let upper = reachesEnd ? endX : x(zone.upperBound, width: width)

        var marks: [AxisMark] = []
        func place(_ mark: AxisMark) {
            let fits = marks.allSatisfy { placed in
                abs(placed.x - mark.x) >= (placed.approximateWidth + mark.approximateWidth) / 2 + 6
            }
            if fits { marks.append(mark) }
        }

        place(AxisMark(id: "lower", x: lower, text: "\(zone.lowerBound)", isGoal: true))
        place(AxisMark(id: "upper", x: upper, text: reachesEnd ? maxText : "\(zone.upperBound)", isGoal: true))
        place(AxisMark(id: "goal", x: (lower + upper) / 2, text: "Twój cel", isGoal: true))
        if !marks.contains(where: { $0.id == "goal" }) {
            place(AxisMark(id: "goal", x: (lower + upper) / 2, text: "cel", isGoal: true))
        }
        place(AxisMark(id: "0", x: inset, text: "0"))
        place(AxisMark(id: "max", x: endX, text: maxText))
        return marks
    }

    private func axisLabels(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(axisMarks(width: width)) { mark in
                Text(verbatim: mark.text)
                    .font(.system(size: 11, weight: mark.isGoal ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(mark.isGoal ? SCPalette.sage : Color.scFaint(scheme))
                    .fixedSize()
                    .position(x: mark.x, y: Self.axisHeight / 2)
            }
        }
        .frame(width: width, height: Self.axisHeight, alignment: .topLeading)
        .accessibilityHidden(true)
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
            .updating($isTouching) { _, touching, _ in
                touching = true
            }
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
                    value = next
                }
            }
            .onEnded { gesture in
                defer {
                    axis = nil
                    isDragging = false
                }
                // Stuknięcie (palec prawie się nie ruszył): kreska dojeżdża do
                // palca. Liczone z przesunięcia, a nie z `axis` — ten mógł już
                // wyzerować przerwany gest.
                let moved = hypot(gesture.translation.width, gesture.translation.height)
                guard moved <= 6 else { return }
                let next = snappedValue(at: gesture.location.x, width: width)
                guard next != value else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { value = next }
            }
    }
}

// MARK: - Akcje stopki i nagłówka

/// Akcja w stopce obok liczników — wariant „soft” zwężony do treści.
/// Pełną szerokość w stopce bierze `EditorialPrimaryActionButton`.
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
            .frame(height: 50)
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
/// Ten sam w filtrach, w wykluczaniu składników i w alergenach.
///
/// Sama ikona w terakotowym krążku „soft”, rozmiarem jak krzyżyk arkusza
/// (Rafał, 24.09: „zmień button z ikona+wyczyść na samą ikonę”). Słowo
/// zostaje tylko dla VoiceOver.
struct RecipeFilterClearButton: View {
    /// Co czyta VoiceOver — „Wyczyść filtry”, „Wyczyść wykluczenia”…
    var accessibilityLabel: String = "Wyczyść filtry"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SCPalette.terracotta)
                .frame(width: 36, height: 36)
                .scSoftSurface(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .accessibilityLabel(accessibilityLabel)
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

// MARK: - Składnik jako pigułka

/// Stan składnika w wykluczeniach.
enum IngredientExclusionState: Equatable {
    case available
    case excluded
    /// Wykluczony razem z całą grupą — stuknięcie wyjmuje go z grupy.
    case excludedByGroup
}

/// Składnik do stuknięcia — w dziale, w rodzajach grupy i w wynikach
/// szukania. Wykluczony: terakota z ikoną zakazu; wykluczony razem z grupą:
/// przerywana obwódka (jest wykluczony, ale nie z osobna).
///
/// Zastąpiła wiersz z przyciskiem „Wyklucz” przy każdym składniku: w dziale
/// „Warzywa” było 49 takich wierszy po 56 pt i 49 terakotowych przycisków
/// jeden pod drugim. Chmura pigułek mieści ten sam dział na półtora ekranu,
/// a stan widać po samej pigułce.
///
/// Grupa („Papryka”) ma strzałkę: stuknięcie rozwija jej rodzaje
/// (`disclosure`), a nie wyklucza — całą grupę wyklucza pigułka
/// „Wszystkie” w rozwiniętym panelu.
struct RecipeExclusionPill: View {
    enum Disclosure: Equatable {
        case collapsed
        case expanded
    }

    let title: String
    let state: IngredientExclusionState
    /// Dopasowanie do pogrubienia (znak startu i długość).
    var highlight: (offset: Int, length: Int)? = nil
    /// Pigułka grupy — `nil` dla zwykłego składnika.
    var disclosure: Disclosure? = nil
    /// Ile rodzajów grupy wykluczono z osobna — plakietka przy nazwie.
    var excludedKinds: Int = 0
    /// Mniejsza — w panelu rodzajów grupy.
    var compact: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var isExcluded: Bool { state != .available }

    private var foreground: Color {
        switch state {
        case .available:       return Color.scLabel(scheme)
        case .excluded:        return SCPalette.terracotta
        case .excludedByGroup: return SCPalette.terracotta.opacity(0.85)
        }
    }

    private var fill: Color {
        switch state {
        case .excluded:
            return SCPalette.terracotta.opacity(scheme == .dark ? 0.16 : 0.10)
        case .excludedByGroup:
            return SCPalette.terracotta.opacity(scheme == .dark ? 0.08 : 0.05)
        case .available:
            if disclosure == .expanded { return Color.scChipBg(scheme) }
            // W panelu rodzajów (tło `scChipBg`) pigułka stoi na kolorze
            // strony — inaczej zlewałaby się z panelem.
            return compact ? Color.scPageBase(scheme) : Color.scTileBg(scheme)
        }
    }

    private var stroke: Color {
        switch state {
        case .excluded:        return SCPalette.terracotta.opacity(0.45)
        case .excludedByGroup: return SCPalette.terracotta.opacity(0.35)
        case .available:       return disclosure == .expanded ? Color.scRule(scheme) : Color.scTileStroke(scheme)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isExcluded {
                    Image(systemName: "nosign")
                        .font(.system(size: compact ? 11 : 12, weight: .bold))
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }

                titleText
                    .font(.system(size: compact ? 13.5 : 14.5, weight: isExcluded ? .semibold : .medium))
                    .tracking(-0.2)
                    .lineLimit(1)

                if excludedKinds > 0 && !isExcluded {
                    RecipeFilterCountBadge(count: excludedKinds)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }

                if let disclosure {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isExcluded ? SCPalette.terracotta.opacity(0.8) : Color.scFaint(scheme))
                        .rotationEffect(.degrees(disclosure == .expanded ? 180 : 0))
                        .padding(.trailing, -2)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 12 : 14)
            .frame(height: compact ? 32 : 36)
            .background(Capsule(style: .continuous).fill(fill))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        stroke,
                        style: StrokeStyle(
                            lineWidth: state == .excluded ? 1.2 : 1,
                            dash: state == .excludedByGroup ? [3, 3] : []
                        )
                    )
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .animation(.smooth(duration: 0.2), value: state)
        .animation(.smooth(duration: 0.25), value: disclosure)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isExcluded ? [.isButton, .isSelected] : .isButton)
    }

    private var titleText: Text {
        guard let highlight, highlight.offset >= 0, highlight.offset + highlight.length <= title.count else {
            return Text(title)
        }
        let start = title.index(title.startIndex, offsetBy: highlight.offset)
        let end = title.index(start, offsetBy: highlight.length)
        return Text(title[..<start]) + Text(title[start..<end]).fontWeight(.heavy) + Text(title[end...])
    }

    private var accessibilityValue: String {
        switch state {
        case .excluded:        return "wykluczone"
        case .excludedByGroup: return "wykluczone razem z całą grupą"
        case .available:       return excludedKinds > 0 ? "wykluczone rodzaje: \(excludedKinds)" : ""
        }
    }

    private var accessibilityHint: String {
        if let disclosure {
            return disclosure == .expanded ? "Zwija rodzaje" : "Rozwija rodzaje"
        }
        return isExcluded ? "Przywraca składnik" : "Wyklucza składnik"
    }
}

/// Chmura pigułek składników. Zawija jak `AllergenChipFlow`, ale widok
/// oznaczony `recipeExclusionFullWidth()` (rozwinięte rodzaje grupy) bierze
/// cały wiersz: kończy wiersz przed sobą i zaczyna nowy za sobą.
///
/// Jeden `Layout` zamiast dwóch chmur rozciętych panelem: pigułki zachowują
/// tożsamość i przy rozwijaniu grupy PRZESUWAJĄ się na nowe miejsca, a nie
/// znikają w jednej chmurze, żeby pojawić się w drugiej.
struct RecipeExclusionFlow: Layout {
    var spacing: CGFloat = 8

    fileprivate struct FullWidthKey: LayoutValueKey {
        static let defaultValue = false
    }

    private struct Placement {
        let index: Int
        let origin: CGPoint
        let size: CGSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let placements = arrange(width: width, subviews: subviews)
        let height = placements.map { $0.origin.y + $0.size.height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for placement in arrange(width: bounds.width, subviews: subviews) {
            subviews[placement.index].place(
                at: CGPoint(x: bounds.minX + placement.origin.x, y: bounds.minY + placement.origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(placement.size)
            )
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Placement] {
        var placements: [Placement] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            if subview[FullWidthKey.self] {
                // Zamknij bieżący wiersz, połóż panel na całą szerokość
                // i zacznij kolejny wiersz pod nim.
                if x > 0 {
                    y += rowHeight + spacing
                }
                let height = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
                placements.append(Placement(index: index, origin: CGPoint(x: 0, y: y), size: CGSize(width: width, height: height)))
                y += height + spacing
                x = 0
                rowHeight = 0
                continue
            }

            let ideal = subview.sizeThatFits(.unspecified)
            let size = CGSize(width: min(ideal.width, width), height: ideal.height)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            placements.append(Placement(index: index, origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return placements
    }
}

extension View {
    /// W `RecipeExclusionFlow`: ten widok zajmuje cały wiersz.
    func recipeExclusionFullWidth() -> some View {
        layoutValue(key: RecipeExclusionFlow.FullWidthKey.self, value: true)
    }
}

/// Ikona działu w tincie jego barwy — te same glify i barwy co alejki
/// Zakupów (`ProductConstants`), więc „Warzywa” wyglądają tak samo w obu
/// miejscach.
struct RecipeExclusionDepartmentIcon: View {
    let department: String
    var size: CGFloat = 34

    var body: some View {
        // Ten sam kafelek, co w nagłówkach arkuszy (`SCHeaderIconWell`).
        SCHeaderIconWell(
            icon: ProductConstants.departmentIcon(for: department),
            accent: ProductConstants.departmentColor(for: department),
            size: size
        )
    }
}

/// Nazwa działu nad pigułkami w wynikach szukania — ikona i wersaliki
/// w barwie działu.
struct RecipeExclusionDepartmentLabel: View {
    let department: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: ProductConstants.departmentIcon(for: department))
                .font(.system(size: 11, weight: .bold))
            Text(department.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.2)
                .lineLimit(1)
        }
        .foregroundStyle(ProductConstants.departmentColor(for: department))
        .padding(.horizontal, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Przełączanie wykluczeń

extension RecipeFilterOptions {
    /// Stan składnika: wykluczony sam, razem z grupą albo dostępny.
    func exclusionState(of exclusion: IngredientExclusion, parent: IngredientGroup? = nil) -> IngredientExclusionState {
        if excludedIngredients.contains(exclusion) { return .excluded }
        if let parent, excludedIngredients.contains(parent.exclusion) { return .excludedByGroup }
        return .available
    }

    /// Ile rodzajów grupy wykluczono z osobna. Cała grupa wykluczona = 0,
    /// bo wtedy pigułka grupy sama stoi w terakocie.
    func excludedKinds(of group: IngredientGroup) -> Int {
        guard !excludedIngredients.contains(group.exclusion) else { return 0 }
        return group.members.reduce(0) { $0 + (excludedIngredients.contains($1.exclusion) ? 1 : 0) }
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
