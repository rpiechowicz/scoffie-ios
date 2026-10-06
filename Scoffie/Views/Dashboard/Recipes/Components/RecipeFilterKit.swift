import SwiftUI

// Klocki arkusza „Filtry”, jego podstron (wykluczanie składników, „Więcej
// filtrów”) i filtrów wyboru przepisu do planu.
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
                    .font(.sc(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.scFaint(scheme))
                    .lineLimit(1)

                Spacer(minLength: 8)

                trailing()
                    .font(.sc(size: 13, weight: .medium))
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

/// Nagłówek arkusza „Filtry”: wspólny nagłówek arkusza
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
    /// „Dopasowane do Ciebie” jako sama ikona obok krzyżyka (Rafał 4.10.2026:
    /// „ten button dałbym gdzieś indziej, może sama ikona obok X”): różdżka,
    /// włączona = szkło w tincie szałwii. `nil` = bez przełącznika (profil
    /// bez diety i celu).
    var fitIsOn: Bool? = nil
    var onToggleFit: () -> Void = {}
    let onClose: () -> Void

    var body: some View {
        EditorialSheetHeader(
            eyebrow: eyebrow,
            title: title,
            icon: icon,
            accent: accent,
            subtitle: scope,
            subtitleTransition: .opacity,
            onClose: onClose
        ) {
            HStack(spacing: 8) {
                if canClear {
                    RecipeFilterClearButton(action: onClear)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
                if let fitIsOn {
                    SCSheetIconButton(
                        systemName: "wand.and.stars",
                        tint: fitIsOn ? SCPalette.sage : nil,
                        accessibilityLabel: "Dopasowane do Ciebie",
                        action: onToggleFit
                    )
                    .symbolEffect(.bounce, value: fitIsOn)
                    .accessibilityValue(fitIsOn ? "włączone" : "wyłączone")
                }
            }
        }
        .animation(.smooth(duration: 0.22), value: canClear)
        .animation(.smooth(duration: 0.22), value: fitIsOn)
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
                .font(.sc(size: 18, weight: .semibold))
                .foregroundStyle(accent)
        }
    }
}

/// Jeden aspekt kategorii (rodzaj dania, smak, mięso…) jako sekcja kafelków
/// z liczbą „ile zostanie” — sekcja kategorii w „Filtrach” i filtry wyboru
/// przepisu do planu. Wybór i liczby podaje wołający, więc ta sama sekcja
/// pisze do `RecipeFilterOptions.categoryFilters` albo do własnego filtra
/// wyboru do planu. W obrębie aspektu opcje łączą się przez LUB — przy
/// dwóch zaznaczonych etykieta mówi to, zanim ktoś zdziwi się, że liczba
/// urosła.
struct RecipeFacetTilesSection: View {
    let facet: RecipeFacet
    /// Etykieta sekcji — „Obiady · Rodzaj dania” albo sam aspekt.
    let title: String
    var top: CGFloat = 24
    let accent: Color
    /// Glif kafelka bez zdjęcia.
    let icon: String
    let isOn: (String) -> Bool
    let count: (String) -> Int
    let cover: (String) -> Recipe?
    let onToggle: (String) -> Void

    var body: some View {
        let picked = facet.options.filter { isOn($0.id) }.count

        RecipeFilterSection(title: title, top: top) {
            if picked > 1 {
                Text("dowolna z zaznaczonych")
                    .transition(.opacity)
            }
        } content: {
            RecipeFilterTileGrid(items: facet.options) { option in
                RecipeFilterOptionTile(
                    title: option.title,
                    count: count(option.id),
                    mark: isOn(option.id) ? .on : .off,
                    accent: accent,
                    cover: cover(option.id),
                    icon: icon
                ) {
                    withAnimation(.smooth(duration: 0.18)) { onToggle(option.id) }
                }
            }
        }
        .animation(.smooth(duration: 0.2), value: picked > 1)
    }
}

/// Jeden pasek pod liczbą w stopce filtrów — ile z puli zostaje (zakres
/// jednej kategorii, ulubione, wybór do planu). Bez zakresu stopka „Filtrów”
/// pokazuje cztery paski kategorii.
struct RecipeFilterProgressBar: View {
    let count: Int
    let total: Int
    var accent: Color = SCPalette.terracotta

    var body: some View {
        GeometryReader { proxy in
            Capsule(style: .continuous)
                .fill(accent.opacity(0.2))
                .overlay(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(accent)
                        .frame(width: total == 0 || count == 0
                               ? 0
                               : max(5, proxy.size.width * CGFloat(min(count, total)) / CGFloat(total)))
                }
        }
        .frame(height: 5)
        .animation(.smooth(duration: 0.3), value: count)
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

// MARK: - Akcje stopki i nagłówka

/// Akcja w stopce obok liczników — wariant „soft” zwężony do treści
/// („Gotowe” w Filtrach i na ich podstronach). Pełną szerokość w stopce
/// bierze `EditorialPrimaryActionButton`. Wariant z samą lupą („Pokaż”)
/// zniknął z filtrami na żywo (6.10.2026).
struct RecipeFilterFooterButton: View {
    let title: String
    var trailingIcon: String? = "chevron.right"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.sc(size: 15.5, weight: .semibold))
                    .tracking(-0.3)
                    .lineLimit(1)
                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.sc(size: 12, weight: .bold))
                }
            }
            .foregroundStyle(SCPalette.terracotta)
            .padding(.horizontal, 22)
            .frame(height: 50)
            .scSoftCapsule()
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.96))
    }
}

/// „Wyczyść” obok krzyżyka — pojawia się dopiero, gdy jest co czyścić.
/// Ten sam w filtrach, w wykluczaniu składników i w alergenach.
///
/// Sama ikona w terakotowym szklanym krążku, rozmiarem jak krzyżyk arkusza
/// (Rafał, 24.09: „zmień button z ikona+wyczyść na samą ikonę”). Słowo
/// zostaje tylko dla VoiceOver.
struct RecipeFilterClearButton: View {
    /// Co czyta VoiceOver — „Wyczyść filtry”, „Wyczyść wykluczenia”…
    var accessibilityLabel: String = "Wyczyść filtry"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.sc(size: 14, weight: .semibold))
                .foregroundStyle(SCPalette.terracotta)
                // Rozmiar krzyżyka obok (`SCSheetIconLabel.size`).
                .frame(width: SCSheetIconLabel.size, height: SCSheetIconLabel.size)
                // Szkło w tincie terakoty — para dla szklanego krzyżyka obok
                // (`SCSheetIconSurface`, Liquid Glass runda 2).
                .scChromeGlass(in: Circle(), tint: SCPalette.terracotta.opacity(0.22))
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
    /// Kolor chipa bez kłódki — terakota w wykluczaniu, kolor grupy
    /// w wierszach „Więcej filtrów” (tam terakota czytałaby się jak „wykluczone”).
    var accent: Color = SCPalette.terracotta

    @Environment(\.colorScheme) private var scheme

    private var tint: Color { locked ? SCPalette.sage : accent }

    var body: some View {
        HStack(spacing: small ? 4 : 6) {
            if locked {
                Image(systemName: "lock.fill")
                    .font(.sc(size: small ? 8.5 : 9.5, weight: .bold))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.sc(size: small ? 12.5 : 13, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Color.scLabel(scheme))
                .lineLimit(1)
            if !locked && !small {
                Image(systemName: "xmark")
                    .font(.sc(size: 8, weight: .heavy))
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
            .font(.sc(size: small ? 12.5 : 13, weight: .semibold))
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
    var accent: Color = SCPalette.terracotta

    var body: some View {
        HStack(spacing: 3) {
            if locked {
                Image(systemName: "lock.fill")
                    .font(.sc(size: 8.5, weight: .bold))
            }
            Text(verbatim: "\(count)")
                .font(.sc(size: 12, weight: .heavy))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, locked ? 7 : 6)
        .frame(minWidth: 20, minHeight: 20)
        .background(Capsule(style: .continuous).fill(locked ? SCPalette.sage : accent))
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
    var accent: Color = SCPalette.terracotta

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
                RecipeFilterExclusionChip(title: chip.title, locked: chip.locked, small: true, accent: accent)
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
                        .font(.sc(size: compact ? 11 : 12, weight: .bold))
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }

                titleText
                    .font(.sc(size: compact ? 13.5 : 14.5, weight: isExcluded ? .semibold : .medium))
                    .tracking(-0.2)
                    .lineLimit(1)

                if excludedKinds > 0 && !isExcluded {
                    RecipeFilterCountBadge(count: excludedKinds)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }

                if let disclosure {
                    Image(systemName: "chevron.down")
                        .font(.sc(size: 10, weight: .bold))
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
                .font(.sc(size: 11, weight: .bold))
            Text(department.uppercased())
                .font(.sc(size: 10.5, weight: .bold))
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
