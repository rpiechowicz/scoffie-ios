import SwiftUI

// Grupy filtrów schowane za wierszem (28.09.2026, Rafał: „w głównych filtrach
// mam mnóstwo podkategorii, które są nieczytelne — zrób sekcje, gdzie będzie
// się otwierał sheet na pół ekranu”). Od katalogu 1000 arkusz „Filtry” miał
// cztery siatki kafelków jedna pod drugą (cechy, kuchnia, okazje i sezon —
// ponad 25 kafelków), a filtry kategorii dwie kolejne. Na wierzchu zostaje to,
// czego się używa najczęściej, a reszta stoi jako wiersze w jednej karcie
// „Więcej filtrów”: ikona, nazwa i to, co wybrano (pigułki + liczba). Stuknięcie
// otwiera półarkusz z TYMI SAMYMI kafelkami, co dotąd, piszący do tej samej
// kopii roboczej — liczby na kafelkach i w stopce zmieniają się na żywo.
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(scheme == .dark ? 0.16 : 0.12))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accent)
                    )

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(scheme))

                    if chips.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 12.5))
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
                    .font(.system(size: 12, weight: .bold))
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

// MARK: - Półarkusz

/// Półarkusz z kafelkami jednej grupy filtrów. Kafelki rysuje wołający
/// (`tile`) — te same `RecipeFilterOptionTile`, co wcześniej w arkuszu, z liczbą
/// „ile zostanie” — a zapis idzie od razu do kopii roboczej rodzica, więc
/// „Gotowe” tylko zamyka.
struct RecipeFilterPickerSheet<Item: Identifiable, Tile: View>: View {
    let eyebrow: String
    let title: String
    let icon: String
    var accent: Color = SCPalette.terracotta
    /// Jedno zdanie pod tytułem — jak łączą się zaznaczone opcje.
    let hint: String
    let items: [Item]
    /// Ile opcji tej grupy jest zaznaczonych — „Wyczyść” i stopka.
    let selectedCount: Int
    /// Ile przepisów zostaje przy bieżącym wyborze (wszystkie filtry).
    let resultCount: Int
    let totalCount: Int
    /// „przepisów” / „w tej kategorii” / „do wyboru”.
    let totalContext: String
    let onClear: () -> Void
    @ViewBuilder let tile: (Item) -> Tile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 10)

                ScrollView {
                    RecipeFilterTileGrid(items: items, tile: tile)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                        .containerRelativeFrame(.horizontal)
                }
                .scrollIndicators(.hidden)
                .scScrollEdgeFade()
                .scSheetFooter { footer }
            }
        }
    }

    private var header: some View {
        EditorialSheetHeader(
            eyebrow: eyebrow,
            title: title,
            icon: icon,
            accent: accent,
            subtitle: hint,
            compact: true,
            onClose: { dismiss() }
        ) {
            if selectedCount > 0 {
                RecipeFilterClearButton(accessibilityLabel: "Wyczyść: \(title.lowercased())") {
                    withAnimation(.smooth(duration: 0.22)) { onClear() }
                }
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.22), value: selectedCount > 0)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "\(resultCount)")
                        .font(.system(size: 15, weight: .bold))
                        .tracking(-0.3)
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(scheme))
                        .contentTransition(.numericText(value: Double(resultCount)))

                    Text(verbatim: "z \(totalCount) \(totalContext)")
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                }

                Text(verbatim: selectedCount == 0 ? "Nic nie zaznaczone" : "Zaznaczone: \(selectedCount)")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(selectedCount == 0 ? Color.scFaint(scheme) : accent)
                    .contentTransition(.numericText(value: Double(selectedCount)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.25), value: resultCount)
            .animation(.smooth(duration: 0.25), value: selectedCount)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Zostaje \(PolishPlural.recipes(resultCount)) z \(totalCount) \(totalContext)")

            RecipeFilterFooterButton(title: "Gotowe", trailingIcon: nil) { dismiss() }
        }
        .padding(.leading, 4)
    }
}
