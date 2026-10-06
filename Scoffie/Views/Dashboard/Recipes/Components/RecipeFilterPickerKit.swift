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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(scheme == .dark ? 0.16 : 0.12))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: icon)
                            .font(.sc(size: 14, weight: .semibold))
                            .foregroundStyle(accent)
                    )

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
