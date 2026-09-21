import SwiftUI

// Wiersz produktu na Zakupach v2 — pole wyboru (`SCCheckbox`) · nazwa (z daniami pod spodem) ·
// znacznik „Dziś” · ilość.
//
// Źródło: canvas claude.ai → „Weekly Meals - Zakupy v2.html”
// (`components/shop-v2-kit.jsx` → `ShopRow`, `components/shop-v2-final.jsx`).
//
// Wiersz nie jest kartą. Hairline biegnie WYŁĄCZNIE pod treścią, czyli od
// nazwy w prawo — kolumna kółek zostaje czysta i widać ją jako jedną pionową
// ścieżkę do odhaczania, a nie jako lewą krawędź szesnastu osobnych kafli.
// Ten sam zabieg co na osi dnia w Planie i w Kalendarzu.

struct ShoppingProductRow: View {
    let name: String
    let amount: String
    /// Dania, z których wziął się produkt — „Omlet ze szpinakiem · Krem
    /// z pomidorów”. `nil` chowa całą drugą linijkę, nie zostawia pustej.
    var dishes: String?
    let bought: Bool
    /// Kolor działu — niesie go pole wyboru i pigułka z ilością.
    var accent: Color = SCPalette.terracotta
    /// Znacznik „Dziś”. W trybie „Na dziś” gaśnie — tam wszystko jest na dziś,
    /// więc znacznik przy każdym wierszu przestawałby cokolwiek znaczyć.
    var showsTodayTag: Bool = false
    var isLast: Bool = false
    var isDisabled: Bool = false
    /// Podgląd archiwum — wiersz nadal wygląda jak wiersz, ale nie klika.
    var isReadOnly: Bool = false
    var onToggle: () -> Void = {}

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: 12) {
                SCCheckbox(on: bought, accent: accent)

                content
            }
            .contentShape(Rectangle())
        }
        // Wiersz bez karty i bez obwódki — ściśnięcie pod palcem jest
        // jedynym sygnałem, że w ogóle da się w niego kliknąć. Ta sama
        // reakcja, co na osi dnia w Planie, tylko delikatniejsza: wierszy
        // jest tu trzydzieści, a nie trzy.
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .disabled(isDisabled || isReadOnly)
        .opacity(isDisabled ? 0.72 : 1)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(bought ? [.isButton, .isSelected] : .isButton)
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 15.5, weight: .semibold))
                    .tracking(-0.3)
                    // Kupione zostaje CZYTELNE: `scMuted` (62 %), a nie
                    // `scFaint` (32 %). Przekreślenie samo mówi „załatwione”,
                    // a przygaszony do 32 % tekst pod kreską zlewał się
                    // z tłem — sprawdzone na poprzedniej wersji ekranu.
                    .foregroundStyle(bought ? Color.scMuted(scheme) : Color.scLabel(scheme))
                    .strikethrough(bought, color: Color.scStrike(scheme))
                    // Nazwa produktu nie łamie się na dwie linijki: wiersze
                    // muszą mieć jeden rytm, żeby kolumna kółek czytała się
                    // jako lista do odhaczania.
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let dishes, !dishes.isEmpty {
                    Text(dishes)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.scFaint(scheme))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsTodayTag && !bought {
                ShoppingTag(text: "Dziś")
                    .transition(.scale.combined(with: .opacity))
            }

            amountPill
        }
        .frame(minHeight: dishes == nil ? 48 : 54)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: bought)
    }

    /// Ilość w pigułce w kolorze działu.
    ///
    /// Wersja płaska („150 g” szarym tekstem obok nazwy) była nie do
    /// odczytania z ręki w sklepie: to jedyna LICZBA w wierszu, a wyglądała
    /// jak przypis. Pigułka daje jej własne pole i kontrast, a kolor działu
    /// wiąże ją z nagłówkiem alejki i z segmentem na pasku postępu — ta sama
    /// barwa mówi „to z tej półki”. Kupione schodzi do neutralnej szarości:
    /// ilość już nie jest potrzebna, więc przestaje wołać.
    private var amountPill: some View {
        SCCountingText(amount)
            .font(.system(size: 13, weight: .bold))
            .tracking(0.1)
            .monospacedDigit()
            .foregroundStyle(bought ? Color.scMuted(scheme) : accent)
            .lineLimit(1)
            // Ilość nigdy się nie zwija ani nie skaluje — miejsce oddaje jej
            // nazwa produktu, nie odwrotnie.
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    bought
                    ? Color.scChipBg(scheme)
                    : accent.opacity(scheme == .dark ? 0.20 : 0.12)
                )
            )
            .overlay(
                Capsule().stroke(
                    bought
                    ? Color.scTileStroke(scheme)
                    : accent.opacity(scheme == .dark ? 0.42 : 0.32),
                    lineWidth: 1
                )
            )
    }

    private var accessibilityLabel: Text {
        let state = bought ? "kupione" : "do kupienia"
        if let dishes, !dishes.isEmpty {
            return Text("\(name), \(amount), \(state). Do dań: \(dishes)")
        }
        return Text("\(name), \(amount), \(state)")
    }
}

#Preview("ShoppingProductRow") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()

        VStack(spacing: 0) {
            ShoppingProductRow(
                name: "Pierś z kurczaka",
                amount: "800 g",
                dishes: "Kurczak pieczony",
                bought: false,
                accent: SCPalette.terracottaDeep,
                showsTodayTag: true
            )
            ShoppingProductRow(
                name: "Pomidory krojone z puszki bez skórki",
                amount: "750 g",
                dishes: "Krem z pomidorów · Ryż z warzywami",
                bought: false,
                accent: SCPalette.sage
            )
            ShoppingProductRow(
                name: "Masło",
                amount: "250 g",
                dishes: "Omlet ze szpinakiem",
                bought: true,
                accent: SCPalette.lavender,
                isLast: true
            )
        }
        .padding(20)
    }
    .preferredColorScheme(.dark)
}
