import SwiftUI

// Grupy filtrów schowane za wierszem (28.09.2026, Rafał: „w głównych filtrach
// mam mnóstwo podkategorii, które są nieczytelne — zrób sekcje”). Od katalogu
// 1000 arkusz „Filtry” miał cztery siatki kafelków jedna pod drugą (cechy,
// kuchnia, okazje i sezon — ponad 25 kafelków), a filtry kategorii dwie
// kolejne. Na wierzchu zostaje to, czego się używa najczęściej, a reszta stoi
// jako wiersze w jednej karcie „Więcej filtrów”: ikona, nazwa i to, co wybrano
// (pigułki + liczba). Stuknięcie WPYCHA podstronę (`RecipeFilterPage`) w stos
// arkusza — systemowy pasek z tytułem, „wstecz” i „Wyczyść” — z TYMI SAMYMI
// kafelkami, piszącymi od razu do filtrów (6.10.2026; wcześniej półarkusz na
// arkuszu).
//
// Wzór wiersza to kafelek „Wyklucz składniki” (ikona w tincie, tytuł, chipy,
// plakietka, strzałka), więc cały arkusz czyta się jednym krojem.

// MARK: - Wiersz

/// Wiersz grupy filtrów w karcie „Więcej filtrów”.
struct RecipeFilterPickerRow: View {
    let icon: String
    let title: String
    /// Przykłady opcji, gdy nic nie wybrano — „Polska, włoska, grecka…”.
    let placeholder: String
    /// Wybrane opcje jako pigułki.
    let chips: [RecipeFilterChipLine.Chip]
    var accent: Color = SCPalette.terracotta
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RecipeFilterRowIcon(icon: icon, accent: accent)

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.sc(size: 15, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(scheme))

                    if chips.isEmpty {
                        Text(placeholder)
                            .font(.sc(size: 12.5))
                            .foregroundStyle(Color.scMuted(scheme))
                            .lineLimit(1)
                            .padding(.top, 2)
                    } else {
                        RecipeFilterChipLine(chips: chips, accent: accent)
                            .padding(.top, 7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !chips.isEmpty {
                    RecipeFilterCountBadge(count: chips.count, accent: accent)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }

                Image(systemName: "chevron.right")
                    .font(.sc(size: 12, weight: .bold))
                    .foregroundStyle(Color.scFaint(scheme))
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .animation(.smooth(duration: 0.22), value: chips.map(\.id))
        .accessibilityLabel(title)
        .accessibilityValue(chips.isEmpty ? "dowolne" : chips.map(\.title).joined(separator: ", "))
        .accessibilityHint("Otwiera wybór")
    }
}

/// Kafelek ikony na początku każdego wiersza filtrów — 32 pt w tincie akcentu.
struct RecipeFilterRowIcon: View {
    let icon: String
    var accent: Color = SCPalette.terracotta

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(accent.opacity(scheme == .dark ? 0.16 : 0.12))
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: icon)
                    .font(.sc(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            )
    }
}

/// Jedna opcja wyboru „jedno z kilku” — czas, trudność, kalorie.
struct RecipeFilterChoice<Value: Hashable> {
    let value: Value
    let title: String
}

/// Wiersz listy filtrów jak w Ustawieniach iOS (6.10.2026, Rafał: „prościej,
/// ale nie smutno”): pełny kolorowy kafelek ikony, tytuł i — po prawej —
/// wartość. Wybrana wartość stoi w kapsułce w kolorze wiersza, „dowolna”
/// szaro, bez kapsułki — od razu widać, co działa.
struct RecipeFilterListRowLabel: View {
    let icon: String
    let title: String
    let value: String
    let isActive: Bool
    let accent: Color
    let trailingIcon: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent)
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: icon)
                        .font(.sc(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                )

            Text(title)
                .font(.sc(size: 15, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(Color.scLabel(scheme))
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Group {
                if isActive {
                    Text(value)
                        .font(.sc(size: 13.5, weight: .bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(accent.opacity(scheme == .dark ? 0.18 : 0.14)))
                } else {
                    Text(value)
                        .font(.sc(size: 15))
                        .foregroundStyle(Color.scMuted(scheme))
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)

            Image(systemName: trailingIcon)
                .font(.sc(size: 11, weight: .bold))
                .foregroundStyle(Color.scFaint(scheme))
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .animation(.smooth(duration: 0.22), value: isActive)
    }
}

/// Wiersz „jedno z kilku” (trudność, kalorie): stuknięcie = systemowe menu
/// z opcjami. Pierwsza opcja to „dowolna”.
struct RecipeFilterListMenuRow<Value: Hashable>: View {
    let icon: String
    let title: String
    let choices: [RecipeFilterChoice<Value>]
    @Binding var selection: Value
    var accent: Color = SCPalette.terracotta

    private var isActive: Bool { selection != choices.first?.value }
    private var currentTitle: String { choices.first { $0.value == selection }?.title ?? "" }

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                    Text(choice.title).tag(choice.value)
                }
            }
        } label: {
            RecipeFilterListRowLabel(
                icon: icon,
                title: title,
                value: currentTitle,
                isActive: isActive,
                accent: accent,
                trailingIcon: "chevron.up.chevron.down"
            )
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityLabel(title)
        .accessibilityValue(currentTitle)
    }
}

/// Wiersz, który WPYCHA podstronę (dieta, składniki, „Więcej filtrów”).
struct RecipeFilterListButtonRow: View {
    let icon: String
    let title: String
    let value: String
    let isActive: Bool
    var accent: Color = SCPalette.terracotta
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RecipeFilterListRowLabel(
                icon: icon,
                title: title,
                value: value,
                isActive: isActive,
                accent: accent,
                trailingIcon: "chevron.right"
            )
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint("Otwiera wybór")
    }
}

/// Kreska między wierszami listy — od tekstu, nie od kafelka ikony.
struct RecipeFilterListDivider: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(Color.scTileStroke(scheme))
            .frame(height: 1)
            .padding(.leading, 54)
    }
}

// MARK: - Przełącznik w kolorze

/// „Dowolny · 15 min · 30 min · 45 min” — przełącznik w stylu Liquid Glass
/// z iOS 26 (wariant L2, Rafał 6.10.2026: „ładniej, w iOS liquid”): tor
/// w kształcie kapsuły i JEDNA szklana soczewka w kolorze akcentu, która
/// przepływa sprężyną do stukniętej opcji i lekko się przy tym rozciąga.
/// Własny, a nie systemowy `.segmented`: systemowy nie daje koloru
/// zaznaczenia, a szary był „za smutny”.
struct RecipeFilterSegment<Value: Hashable>: View {
    let choices: [RecipeFilterChoice<Value>]
    @Binding var selection: Value
    var accent: Color = SCPalette.terracotta

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Szerokość toru — z niej szerokość i miejsce soczewki.
    @State private var width: CGFloat = 0
    /// Licznik przeskoków soczewki — każdy gra jedno „rozciągnięcie”.
    @State private var squish = 0

    private static var height: CGFloat { 42 }
    private static var inset: CGFloat { 3 }

    /// Przeskok soczewki: sprężyna z lekkim dobiciem, jak systemowy
    /// przełącznik iOS 26; przy „Ogranicz ruch” samo płynne przejście.
    private var slide: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.74)
    }

    var body: some View {
        let count = max(choices.count, 1)
        let index = choices.firstIndex { $0.value == selection } ?? 0
        let lensWidth = max(0, (width - Self.inset * 2) / CGFloat(count))

        ZStack(alignment: .leading) {
            // Tor — kapsuła na płasko, z cienką obwódką.
            Capsule()
                .fill(Color.scBarTrack(scheme))
                .overlay(Capsule().strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))

            // Soczewka — JEDNA, przesuwana (nie wstawiana od nowa przy każdym
            // wyborze), ze szkła w kolorze akcentu. Pod przyciskami i bez
            // dotyku: szkło w etykiecie przycisku potrafiło łapać stuknięcia
            // (patrz `scChromeGlass`).
            Color.clear
                .frame(width: lensWidth, height: Self.height - Self.inset * 2)
                .scChromeGlass(
                    in: Capsule(),
                    tint: accent.opacity(scheme == .dark ? 0.42 : 0.32)
                )
                .keyframeAnimator(initialValue: LensSquish(), trigger: squish) { lens, frame in
                    lens.scaleEffect(x: frame.x, y: frame.y)
                } keyframes: { _ in
                    KeyframeTrack(\.x) {
                        MoveKeyframe(1)
                        CubicKeyframe(1.14, duration: 0.12)
                        CubicKeyframe(0.97, duration: 0.15)
                        CubicKeyframe(1, duration: 0.16)
                    }
                    KeyframeTrack(\.y) {
                        MoveKeyframe(1)
                        CubicKeyframe(0.86, duration: 0.12)
                        CubicKeyframe(1.04, duration: 0.15)
                        CubicKeyframe(1, duration: 0.16)
                    }
                }
                .offset(x: Self.inset + lensWidth * CGFloat(index))
                .opacity(width > 0 ? 1 : 0)
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                    let isOn = choice.value == selection
                    Button {
                        guard choice.value != selection else { return }
                        if !reduceMotion { squish += 1 }
                        selection = choice.value
                    } label: {
                        Text(choice.title)
                            .font(.sc(size: 14, weight: isOn ? .bold : .semibold))
                            .foregroundStyle(isOn ? accent : Color.scMuted(scheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.height)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, Self.inset)
        }
        .frame(height: Self.height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .animation(slide, value: index)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Rozciągnięcie soczewki przy przeskoku — wszerz i spłaszczenie, potem
/// lekkie odbicie i spoczynek.
private struct LensSquish {
    var x: CGFloat = 1
    var y: CGFloat = 1
}

// MARK: - Zdjęcia rodzaju dania

/// Rodzaj dania jako kółka ze zdjęciem dania i podpisem — NA STAŁE, bez
/// przewijania w bok: do pięciu w jednym rzędzie, więcej — rzędy po cztery
/// (Rafał 6.10.2026: „góra mi pasuje”). Przy rzędach po cztery podpis to
/// krótka nazwa w JEDNEJ linii (`RecipeFacetOption.shortTitle`, wariant R1),
/// żeby siatka stała równo. W obrębie aspektu opcje łączą się przez LUB, jak
/// wszędzie w filtrach kategorii.
struct RecipeFacetPhotoGrid: View {
    let options: [RecipeFacetOption]
    let accent: Color
    /// Glif zdjęcia, gdy żaden przepis z tą opcją nie ma zdjęcia.
    let icon: String
    let isOn: (String) -> Bool
    let cover: (String) -> Recipe?
    let onToggle: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    private static let photo: CGFloat = 56

    private var columns: [GridItem] {
        let count = options.count <= 5 ? max(options.count, 1) : 4
        return Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 14) {
            ForEach(options) { option in
                let selected = isOn(option.id)
                Button {
                    withAnimation(.smooth(duration: 0.2)) { onToggle(option.id) }
                } label: {
                    VStack(spacing: 6) {
                        RecipeFilterCoverThumb(recipe: cover(option.id), icon: icon, accent: accent)
                            .frame(width: Self.photo, height: Self.photo)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
                            .padding(4)
                            .overlay(
                                Circle()
                                    .strokeBorder(accent, lineWidth: 2.5)
                                    .opacity(selected ? 1 : 0)
                            )
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "checkmark")
                                    .font(.sc(size: 10, weight: .heavy))
                                    .foregroundStyle(Color.scPageBase(scheme))
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(accent))
                                    .scaleEffect(selected ? 1 : 0.4)
                                    .opacity(selected ? 1 : 0)
                            }

                        Text(option.shortTitle ?? option.title)
                            .font(.sc(size: 11, weight: .semibold))
                            .foregroundStyle(selected ? Color.scLabel(scheme) : Color.scMuted(scheme))
                            .multilineTextAlignment(.center)
                            .lineLimit(option.shortTitle == nil ? 2 : 1)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlanPressStyle(scale: 0.95))
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: options.filter { isOn($0.id) }.map(\.id))
    }
}

// MARK: - Smak

/// Smak jako dwa kafle ze zdjęciem dania z tej kategorii (wariant S2 ze
/// zdjęciem, Rafał 6.10.2026). Jeden wybór albo żaden: drugie stuknięcie
/// odznacza, a nic nie zaznaczone = każdy smak.
struct RecipeTasteTiles: View {
    let options: [RecipeFacetOption]
    let selection: String?
    let cover: (String) -> Recipe?
    let onSelect: (String?) -> Void

    @Environment(\.colorScheme) private var scheme

    /// Słodkie w różu, słone w szałwii — te same kolory w kafelku i w kapsułce.
    static func accent(for option: String) -> Color {
        option == "sweet" ? SCPalette.rose : SCPalette.sage
    }

    static func icon(for option: String) -> String {
        option == "sweet" ? "birthday.cake.fill" : "frying.pan.fill"
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options) { option in
                let isOn = selection == option.id
                let accent = Self.accent(for: option.id)
                Button {
                    withAnimation(.smooth(duration: 0.22)) { onSelect(isOn ? nil : option.id) }
                } label: {
                    HStack(spacing: 10) {
                        RecipeFilterCoverThumb(recipe: cover(option.id), icon: Self.icon(for: option.id), accent: accent)
                            .frame(width: 38, height: 38)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Text(option.title)
                            .font(.sc(size: 15, weight: .bold))
                            .tracking(-0.2)
                            .foregroundStyle(isOn ? accent : Color.scLabel(scheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 7)
                    .padding(.trailing, 10)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isOn ? accent.opacity(scheme == .dark ? 0.18 : 0.14) : Color.scTileBg(scheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isOn ? accent.opacity(0.5) : Color.scTileStroke(scheme), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PlanPressStyle(scale: 0.97))
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Karta z wierszami grup — jedna płyta (`scTileBg` + `scTileStroke`), wiersze
/// rozdzielone kreską od tekstu, nie od krawędzi.
struct RecipeFilterPickerGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.scTileStroke(scheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Kreska między wierszami karty — od miejsca, gdzie zaczyna się tekst.
struct RecipeFilterPickerDivider: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(Color.scTileStroke(scheme))
            .frame(height: 1)
            .padding(.leading, 56)
    }
}

extension RecipeFilterPickerRow {
    /// „Polska, włoska, grecka…” — pierwsze nazwy opcji jako podpowiedź, co
    /// jest w środku. Wielkość liter podaje wołający (`sentence`), bo „Boże
    /// Narodzenie” w środku zdania zostaje z wielkiej.
    static func placeholder(from titles: [String], limit: Int = 3) -> String {
        let shown = Array(titles.prefix(limit))
        guard !shown.isEmpty else { return "" }
        return shown.joined(separator: ", ") + (titles.count > limit ? "…" : "")
    }

    /// Nazwy jak w zdaniu: pierwsza z wielkiej litery, reszta bez zmian
    /// (wołający podaje je już małą literą albo w formie ze zdania).
    static func sentence(_ parts: [String]) -> [String] {
        guard let first = parts.first, let letter = first.first else { return parts }
        let head = letter.uppercased() + String(first.dropFirst())
        return [head] + Array(parts.dropFirst())
    }
}

// MARK: - Podstrona

/// Podstrona filtrów wpchnięta w stos arkusza (Filtry na Przepisach, filtry
/// wyboru przepisu do planu): systemowy pasek z tytułem, „wstecz”
/// i „Wyczyść” tej grupy, pod nim jedno zdanie, treść (kafelki rysuje
/// wołający) i stopka z liczbą przepisów na żywo i „Gotowe”. Zmiany idą od
/// razu do filtrów, więc „Gotowe” tylko kończy — co znaczy „koniec”, mówi
/// wołający (`onDone`: zamknięcie arkusza Filtrów albo powrót do listy
/// wyboru do planu).
struct RecipeFilterPage<Content: View>: View {
    let title: String
    var accent: Color = SCPalette.terracotta
    /// Jedno zdanie nad treścią — jak łączą się zaznaczone opcje. Puste = bez.
    var hint: String = ""
    /// Ile opcji tej grupy jest zaznaczonych — „Wyczyść” i stopka.
    let selectedCount: Int
    /// Ile przepisów zostaje przy bieżącym wyborze (wszystkie filtry).
    let resultCount: Int
    let totalCount: Int
    /// „przepisów” / „w tej kategorii” / „do wyboru”.
    let totalContext: String
    let onClear: () -> Void
    let onDone: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !hint.isEmpty {
                        Text(hint)
                            .font(.sc(size: 13))
                            .foregroundStyle(Color.scMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 12)
                    }

                    content()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
            // Pod systemowym paskiem — miękka krawędź, bez kreski.
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scSheetFooter { footer }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Wyczyść") {
                    withAnimation(.smooth(duration: 0.22)) { onClear() }
                }
                .disabled(selectedCount == 0)
                .accessibilityLabel("Wyczyść: \(title.lowercased())")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "\(resultCount)")
                        .font(.sc(size: 15, weight: .bold))
                        .tracking(-0.3)
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(scheme))
                        .contentTransition(.numericText(value: Double(resultCount)))

                    Text(verbatim: "z \(totalCount) \(totalContext)")
                        .font(.sc(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                }

                Text(verbatim: selectedCount == 0 ? "Nic nie zaznaczone" : "Zaznaczone: \(selectedCount)")
                    .font(.sc(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(selectedCount == 0 ? Color.scFaint(scheme) : accent)
                    .contentTransition(.numericText(value: Double(selectedCount)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.25), value: resultCount)
            .animation(.smooth(duration: 0.25), value: selectedCount)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Zostaje \(PolishPlural.recipes(resultCount)) z \(totalCount) \(totalContext)")

            RecipeFilterFooterButton(title: "Gotowe", trailingIcon: nil, action: onDone)
        }
        .padding(.leading, 4)
    }
}
